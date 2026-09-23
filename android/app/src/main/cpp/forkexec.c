#include <sys/socket.h>
#include <sys/un.h>
#include <stdint.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <jni.h>
#include <pthread.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <android/log.h>
#include <errno.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/stat.h>
#include <time.h>

#define TAG "KEQDIS"
#define XTAG "KEQDIS_XRAY"

/* Кольцевой файл логов ядра: при превышении усекаем в ноль. */
#define CORE_LOG_MAX (512 * 1024)

/* Аргумент фонового читателя: fd пайпа + путь к файлу логов (может быть пустым). */
typedef struct { int fd; char logpath[1024]; } xray_log_arg;

/* Forward declaration — определение в конце файла */
static void *xray_log_reader(void *arg);

/*
 * Счётчик неудачных дозвонов ядра сессии до своего сервера — тихая прослушка
 * для автовыбора.
 *
 * mihomo пишет о таком на уровне warning: «[TCP] dial <прокси> (match ...)
 * ... error: ...». xray 26.x — только на info («failed to find an available
 * destination» внутри «failed to process outbound traffic»). Поэтому сессия
 * обоих ядер работает не тише info, а лишнее срезает g_log_threshold.
 * Считаем здесь, где строка уже в руках, а приложение раз в секунду читает
 * число: ни сети, ни радио, ни лишнего разбора.
 *
 * Прямые соединения (DIRECT, REJECT) не считаются: мёртвый сайт — не мёртвый
 * сервер. Ядра замера сюда не попадают вовсе — у них нет файла лога, а их
 * отказы про чужие серверы.
 */
static long g_dial_failures = 0;

static int is_server_dial_failure(const char *line) {
    if (strstr(line, "failed to find an available destination")) return 1;
    /* XHTTP дозванивается лениво: ядро сразу отдаёт соединение и пишет
     * «tunneling request», а отказ сервера приходит отдельной строкой
     * транспорта — «splithttp: failed to POST ... connection refused» или
     * «unexpected status 502» от фронта, за которым сервер умер. */
    const char *xhttp = strstr(line, "splithttp: ");
    if (xhttp) {
        xhttp += 11;
        if (strncmp(xhttp, "failed to create", 16) == 0) return 0;
        return strncmp(xhttp, "failed to ", 10) == 0 ||
               strncmp(xhttp, "unexpected status ", 18) == 0;
    }
    /* Только TCP: сервер без UDP на каждый QUIC-запрос отвечает отказом, и
     * живой сервер сыпал бы «отказами» от одного открытого ютуба. Проба,
     * которой потом проверяют сервер, всё равно идёт по TCP. */
    const char *dial = strstr(line, "[TCP] dial ");
    if (!dial || !strstr(line, " error: ")) return 0;
    dial += 11;
    if (strncmp(dial, "DIRECT", 6) == 0 || strncmp(dial, "REJECT", 6) == 0) return 0;
    return 1;
}

JNIEXPORT jlong JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeDialFailures(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return (jlong)__atomic_load_n(&g_dial_failures, __ATOMIC_RELAXED);
}

/*
 * С какого уровня строки ядра идут в лог и logcat: 0 debug, 1 info, 2 warning,
 * 3 error, 4 none/silent; 0 пропускает всё. Это уровень, выбранный человеком,
 * когда сессию подняли до info ради счётчиков (sessionConfigFor в
 * KeqdisVpnService): лог остаётся таким, каким он его заказывал.
 */
static int g_log_threshold = 0;

JNIEXPORT void JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeSetCoreLogLevel(
        JNIEnv *env, jclass clazz, jint level) {
    (void)env; (void)clazz;
    __atomic_store_n(&g_log_threshold, (int)level, __ATOMIC_RELAXED);
}

/*
 * «[TUN] Tun adapter listening at:» — mihomo взял дескриптор туннеля. Пишет он
 * это уровнем info, и при выбранном warning строка в лог не попадает, поэтому
 * сервис ждёт её здесь, до порога (awaitMihomoTun). Без этого каждое
 * подключение стояло четыре секунды до таймаута.
 */
static long g_tun_ready = 0;

JNIEXPORT jlong JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeTunReadyCount(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return (jlong)__atomic_load_n(&g_tun_ready, __ATOMIC_RELAXED);
}

/* Уровень строки ядра. mihomo: «time="..." level=info msg="..."». xray — по
 * метке после времени: «2026/09/23 02:09:14.123456 [Info] ...». Строка без
 * уровня (баннер, access-лог) не режется никогда. */
static int core_line_level(const char *line) {
    if (strncmp(line, "time=\"", 6) == 0) {
        const char *lv = strstr(line, " level=");
        if (!lv) return 4;
        lv += 7;
        if (strncmp(lv, "debug", 5) == 0) return 0;
        if (strncmp(lv, "info", 4) == 0) return 1;
        if (strncmp(lv, "warn", 4) == 0) return 2;
        if (strncmp(lv, "error", 5) == 0) return 3;
        return 4;
    }
    const char *tag = strchr(line, '[');
    if (!tag) return 4;
    if (strncmp(tag, "[Debug]", 7) == 0) return 0;
    if (strncmp(tag, "[Info]", 6) == 0) return 1;
    if (strncmp(tag, "[Warning]", 9) == 0) return 2;
    if (strncmp(tag, "[Error]", 7) == 0) return 3;
    return 4;
}

/*
 * Пишет строку ядра в logcat (XTAG) и, если задан logpath, дублирует её в файл.
 * Дублирование в файл нужно потому, что на Android 13+ untrusted_app не может
 * читать logcat (SELinux), поэтому in-app экран логов опирается на этот файл.
 * Файл кольцуется по размеру (CORE_LOG_MAX). logpath == "" → только logcat.
 */
static void core_log_line(const char *logpath, const char *line) {
    if (!line || !*line) return;
    /* Счётчики — до порога: ради них сессия и работает на info. */
    if (logpath && *logpath) {
        if (is_server_dial_failure(line))
            __atomic_add_fetch(&g_dial_failures, 1, __ATOMIC_RELAXED);
        if (strstr(line, "[TUN] Tun adapter listening at:"))
            __atomic_add_fetch(&g_tun_ready, 1, __ATOMIC_RELAXED);
    }
    if (core_line_level(line) < __atomic_load_n(&g_log_threshold, __ATOMIC_RELAXED))
        return;
    __android_log_print(ANDROID_LOG_DEBUG, XTAG, "%s", line);
    if (!logpath || !*logpath) return;
    int lf = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (lf < 0) return;
    struct stat st;
    if (fstat(lf, &st) == 0 && st.st_size > CORE_LOG_MAX) {
        if (ftruncate(lf, 0) == 0) lseek(lf, 0, SEEK_SET);
    }
    char ts[24];
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    size_t tn = strftime(ts, sizeof(ts), "%m-%d %H:%M:%S ", &tmv);
    if (tn > 0) (void)write(lf, ts, tn);
    (void)write(lf, line, strlen(line));
    (void)write(lf, "\n", 1);
    close(lf);
}

/* ── Ядро прокси (xray / mihomo) ─────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeStartCore(
        JNIEnv *env, jclass clazz,
        jstring jBinPath, jstring jConfigPath, jstring jAssetDir, jstring jLogName,
        jstring jCoreKind, jint jTunFd) {

    const char *binPath    = (*env)->GetStringUTFChars(env, jBinPath,    NULL);
    const char *configPath = (*env)->GetStringUTFChars(env, jConfigPath, NULL);
    const char *assetDir   = (*env)->GetStringUTFChars(env, jAssetDir,   NULL);
    const char *logName    = jLogName ? (*env)->GetStringUTFChars(env, jLogName, NULL) : NULL;

    /* Какое ядро запускаем: у них разный argv и разный способ показать базы geo.
     * Копируем в свой буфер ДО fork: в ребёнке JNI-вызовы делать нельзя, а
     * стековый буфер наследуется как есть. */
    char coreKind[16];
    coreKind[0] = '\0';
    if (jCoreKind) {
        const char *ck = (*env)->GetStringUTFChars(env, jCoreKind, NULL);
        if (ck) {
            snprintf(coreKind, sizeof(coreKind), "%s", ck);
            (*env)->ReleaseStringUTFChars(env, jCoreKind, ck);
        }
    }
    const int isMihomo = (strcmp(coreKind, "mihomo") == 0);

    /* Путь к файлу логов ядра: <assetDir>/<logName>. Пустое имя → файл выключен
     * (ping/спидтест им пользоваться не должны, чтобы не засорять лог соединения). */
    char logpath[1024];
    logpath[0] = '\0';
    if (logName && logName[0])
        snprintf(logpath, sizeof(logpath), "%s/%s", assetDir, logName);
    if (logName) (*env)->ReleaseStringUTFChars(env, jLogName, logName);

    if (access(binPath, F_OK) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: binary not found: %s", binPath);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -1;
    }
    if (access(configPath, F_OK) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: config not found: %s", configPath);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -2;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG,
                        "startCore: kind=%s bin=%s config=%s dir=%s tunFd=%d",
                        coreKind[0] ? coreKind : "xray", binPath, configPath, assetDir, (int)jTunFd);

    /*
     * Дескриптор TUN, если ядро само владеет туннелем (mihomo читает его номер
     * из `tun.file-descriptor` в конфиге, xray — из окружения). Снимаем
     * FD_CLOEXEC — иначе execv закроет его, и ядро получит «bad file
     * descriptor» на устройстве, которого уже нет. Владение остаётся за
     * ParcelFileDescriptor на стороне сервиса: у ребёнка своя копия таблицы
     * дескрипторов, и его close() нашего не трогает.
     */
    const int tunFd = (int)jTunFd;
    if (tunFd >= 0) {
        fcntl(tunFd, F_SETFD, fcntl(tunFd, F_GETFD) & ~FD_CLOEXEC);
    }

    int pipefd[2] = {-1, -1};
    if (pipe(pipefd) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: output pipe failed errno=%d", errno);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    int pidpipe[2];
    if (pipe(pidpipe) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: pid pipe failed errno=%d", errno);
        close(pipefd[0]); close(pipefd[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    /*
     * Двойной fork с setsid: ядро усыновляет init, и JVM не нужно его
     * дожидаться. От ограничения дочерних процессов (Android 12+) это не
     * прячет: система ищет их по cgroup приложения, а не по родителю, поэтому
     * смерть ядра сервис переживает сам (см. reviveCore в KeqdisVpnService).
     */
    pid_t pid1 = fork();
    if (pid1 < 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: first fork failed errno=%d", errno);
        close(pipefd[0]); close(pipefd[1]);
        close(pidpipe[0]); close(pidpipe[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    if (pid1 == 0) {
        close(pidpipe[0]);
        close(pipefd[0]);

        setsid();
        prctl(PR_SET_PDEATHSIG, 0);

        pid_t pid2 = fork();
        if (pid2 < 0) {
            pid_t err = -1;
            write(pidpipe[1], &err, sizeof(err));
            close(pidpipe[1]);
            close(pipefd[1]);
            _exit(1);
        }

        if (pid2 == 0) {
            close(pidpipe[1]);

            dup2(pipefd[1], STDOUT_FILENO);
            dup2(pipefd[1], STDERR_FILENO);
            close(pipefd[1]);

            prctl(PR_SET_PDEATHSIG, 0);

            int max = (int)sysconf(_SC_OPEN_MAX);
            for (int i = 3; i < max; i++) {
                if (i != tunFd) close(i);
            }

            /* xray ищет geoip.dat/geosite.dat по XRAY_LOCATION_ASSET, mihomo —
             * в своём рабочем каталоге (`-d`). Каталог один и тот же (filesDir),
             * различается только способ его назвать. */
            if (isMihomo) {
                char *argv[] = {
                    (char *)binPath, "-d", (char *)assetDir, "-f", (char *)configPath, NULL
                };
                execv(binPath, argv);
            } else {
                setenv("XRAY_LOCATION_ASSET", assetDir, 1);
                /* Дескриптор туннеля xray берёт только отсюда: в его конфиге
                 * места под номер нет вовсе (proxy/tun/tun_android.go читает
                 * переменную окружения). Ставим лишь когда номер дали — иначе
                 * ядро сочло бы за дескриптор ноль, то есть наш stdin. */
                if (tunFd >= 0) {
                    char fdEnv[16];
                    snprintf(fdEnv, sizeof(fdEnv), "%d", tunFd);
                    setenv("XRAY_TUN_FD", fdEnv, 1);
                }
                char *argv[] = { (char *)binPath, "run", "-c", (char *)configPath, NULL };
                execv(binPath, argv);
            }
            dprintf(STDOUT_FILENO, "execv failed errno=%d path=%s\n", errno, binPath);
            _exit(127);
        }

        close(pipefd[1]);
        write(pidpipe[1], &pid2, sizeof(pid2));
        close(pidpipe[1]);
        _exit(0);
    }

    close(pipefd[1]);
    close(pidpipe[1]);

    waitpid(pid1, NULL, 0);

    pid_t pid2 = -1;
    read(pidpipe[0], &pid2, sizeof(pid2));
    close(pidpipe[0]);

    (*env)->ReleaseStringUTFChars(env, jBinPath,    binPath);
    (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
    (*env)->ReleaseStringUTFChars(env, jAssetDir,   assetDir);

    if (pid2 <= 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: second fork failed");
        if (pipefd[0] >= 0) close(pipefd[0]);
        return -3;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "startCore: forked pid=%d", (int)pid2);

    if (pipefd[0] >= 0) {
        fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL, 0) | O_NONBLOCK);

        char buf[4096], line[512];
        int linepos = 0, died = 0;

        /*
         * Короткое окно перед тем, как отдать pid: ловим ядро, умершее сразу
         * (нет бинаря под эту архитектуру, конфиг не разобрался). Признак —
         * закрытая труба: оба её конца висят на stdout/stderr ядра и уходят
         * вместе с процессом. waitpid тут не годится — после двойного fork
         * ядро нам не ребёнок, а внук, усыновлённый init, и звать его некому.
         *
         * Окно короткое намеренно, и это не осторожность, а цена. Здоровое
         * ядро трубу держит и всё время в неё пишет, поэтому сколько тут
         * стоим, столько платит КАЖДОЕ подключение: прежние три секунды были
         * ровно тем зазором, когда туннель уже поднят и трафик идёт, а
         * приложение всё ещё крутит кружок. Негодный конфиг роняет ядро за
         * 60-100 мс (замерено на mihomo), так что четверти секунды хватает, а
         * смерть позже подберёт ожидание SOCKS-порта в KeqdisVpnService — оно
         * смотрит /proc и покажет ту же жалобу ядра из лога.
         *
         * Убрать окно совсем всё же нельзя: у временных ядер замера проверки
         * по /proc нет, и для них это единственный признак «не взлетело» —
         * без него батч ждал бы порт все восемь секунд таймаута.
         */
        struct timespec t0, now;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (;;) {
            ssize_t n = read(pipefd[0], buf, sizeof(buf));
            if (n > 0) {
                for (ssize_t i = 0; i < n; i++) {
                    char c = buf[i];
                    if (c == '\n' || linepos >= (int)sizeof(line) - 1) {
                        line[linepos] = '\0';
                        if (linepos > 0)
                            core_log_line(logpath, line);
                        linepos = 0;
                    } else {
                        line[linepos++] = c;
                    }
                }
            } else if (n == 0) {
                died = 1;
                break;
            } else {
                usleep(10000);
            }
            clock_gettime(CLOCK_MONOTONIC, &now);
            long waited_ms = (now.tv_sec - t0.tv_sec) * 1000 +
                             (now.tv_nsec - t0.tv_nsec) / 1000000;
            if (waited_ms >= 250) break;
        }
        if (linepos > 0) {
            line[linepos] = '\0';
            core_log_line(logpath, line);
        }

        if (died) {
            __android_log_print(ANDROID_LOG_ERROR, TAG, "startCore: core exited on startup");
            close(pipefd[0]);
            return -4;
        }

        fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL, 0) & ~O_NONBLOCK);

        xray_log_arg *targ = malloc(sizeof(xray_log_arg));
        if (targ) {
            targ->fd = pipefd[0];
            snprintf(targ->logpath, sizeof(targ->logpath), "%s", logpath);

            pthread_t thr;
            pthread_attr_t attr;
            pthread_attr_init(&attr);
            pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

            int rc = pthread_create(&thr, &attr, xray_log_reader, targ);
            pthread_attr_destroy(&attr);

            if (rc != 0) {
                __android_log_print(ANDROID_LOG_WARN, TAG,
                                    "startCore: failed to start log reader thread rc=%d", rc);
                free(targ);
                close(pipefd[0]);
            }
        } else {
            close(pipefd[0]);
        }
    }

    return (jint)pid2;
}

/* ── Фоновый читатель вывода Xray ─────────────────────────────────────────
 *
 * Читает pipe до EOF (Xray завершился) и пишет каждую строку в logcat.
 * Запускается как detached pthread — не нужно join().
 * fd закрывает сам перед выходом.
 */
static void *xray_log_reader(void *arg) {
    xray_log_arg *a = (xray_log_arg *)arg;
    int fd = a->fd;
    char logpath[1024];
    snprintf(logpath, sizeof(logpath), "%s", a->logpath);
    free(a);

    char buf[4096], line[1024];
    int linepos = 0;

    while (1) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n <= 0) break;   /* EOF или ошибка — Xray умер */
        for (ssize_t i = 0; i < n; i++) {
            char c = buf[i];
            if (c == '\n' || linepos >= (int)sizeof(line) - 1) {
                line[linepos] = '\0';
                if (linepos > 0)
                    core_log_line(logpath, line);
                linepos = 0;
            } else {
                line[linepos++] = c;
            }
        }
    }
    if (linepos > 0) {
        line[linepos] = '\0';
        core_log_line(logpath, line);
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "xray_log_reader: pipe closed (xray exited)");
    close(fd);
    return NULL;
}
