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

/* больше этого файл логов обнуляется */
#define CORE_LOG_MAX (512 * 1024)

typedef struct { int fd; char logpath[1024]; } xray_log_arg;

static void *xray_log_reader(void *arg);

/* отказы дозвона ядра сессии до своего сервера, для автовыбора. xray 26 пишет их только на info, поэтому сессия на info,
 * а лишнее режет g_log_threshold. DIRECT и REJECT не считаем: мёртвый сайт не мёртвый сервер */
static long g_dial_failures = 0;

static int is_server_dial_failure(const char *line) {
    if (strstr(line, "failed to find an available destination")) return 1;
    /* XHTTP дозванивается лениво: отказ сервера приходит отдельной строкой транспорта (failed to POST, unexpected status 502) */
    const char *xhttp = strstr(line, "splithttp: ");
    if (xhttp) {
        xhttp += 11;
        if (strncmp(xhttp, "failed to create", 16) == 0) return 0;
        return strncmp(xhttp, "failed to ", 10) == 0 ||
               strncmp(xhttp, "unexpected status ", 18) == 0;
    }
    /* только TCP: сервер без UDP отказывает каждому QUIC-запросу, и живой сыпал бы отказами от одного ютуба */
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

/* уровень, выбранный пользователем: сессию подняли до info ради счётчиков, а в лог идёт только заказанное;
 * 0 пропускает всё */
static int g_log_threshold = 0;

JNIEXPORT void JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeSetCoreLogLevel(
        JNIEnv *env, jclass clazz, jint level) {
    (void)env; (void)clazz;
    __atomic_store_n(&g_log_threshold, (int)level, __ATOMIC_RELAXED);
}

/* строку о готовности TUN mihomo пишет на info, и при warning она в лог не попадает, поэтому ловим её
 * до порога; без этого каждое подключение стояло четыре секунды до таймаута */
static long g_tun_ready = 0;

JNIEXPORT jlong JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeTunReadyCount(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return (jlong)__atomic_load_n(&g_tun_ready, __ATOMIC_RELAXED);
}

/* строку без уровня (баннер, access-лог) не режем никогда */
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

/* дублируем в файл: на Android 13+ приложению logcat не читается (SELinux), экран логов живёт на этом файле */
static void core_log_line(const char *logpath, const char *line) {
    if (!line || !*line) return;
    /* счётчики до порога: ради них сессия и работает на info */
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

JNIEXPORT jint JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeStartCore(
        JNIEnv *env, jclass clazz,
        jstring jBinPath, jstring jConfigPath, jstring jAssetDir, jstring jLogName,
        jstring jCoreKind, jint jTunFd, jstring jOwnerSocket) {

    const char *binPath    = (*env)->GetStringUTFChars(env, jBinPath,    NULL);
    const char *configPath = (*env)->GetStringUTFChars(env, jConfigPath, NULL);
    const char *assetDir   = (*env)->GetStringUTFChars(env, jAssetDir,   NULL);
    const char *logName    = jLogName ? (*env)->GetStringUTFChars(env, jLogName, NULL) : NULL;

    /* копируем до fork: в ребёнке JNI звать нельзя */
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

    char ownerSocket[128];
    ownerSocket[0] = '\0';
    if (jOwnerSocket) {
        const char *os = (*env)->GetStringUTFChars(env, jOwnerSocket, NULL);
        if (os) {
            snprintf(ownerSocket, sizeof(ownerSocket), "%s", os);
            (*env)->ReleaseStringUTFChars(env, jOwnerSocket, os);
        }
    }

    /* пустое имя выключает файл: пинг и спидтест не должны засорять лог соединения */
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

    /* снимаем FD_CLOEXEC, иначе execv закроет дескриптор и ядро получит bad file descriptor;
     * владеет им ParcelFileDescriptor сервиса, и close() у ребёнка его не трогает */
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

    /* двойной fork отдаёт ядро init, но от лимита дочерних процессов Android 12+ это не прячет: система ищет
     * по cgroup, поэтому смерть ядра сервис переживает сам (reviveCore) */
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

            /* владельца соединения ядро спрашивает у нас, см. mihomo- и xray-android-uid-owner.patch */
            if (ownerSocket[0]) setenv("KEQDROID_OWNER_SOCKET", ownerSocket, 1);
            /* geo xray ищет по XRAY_LOCATION_ASSET, mihomo в рабочем каталоге -d, каталог один */
            if (isMihomo) {
                char *argv[] = {
                    (char *)binPath, "-d", (char *)assetDir, "-f", (char *)configPath, NULL
                };
                execv(binPath, argv);
            } else {
                setenv("XRAY_LOCATION_ASSET", assetDir, 1);
                /* номер дескриптора xray читает только из окружения (proxy/tun/tun_android.go); без номера переменную
                 * не ставим, иначе ядро взяло бы ноль, то есть stdin */
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

        /* Ядро, умершее сразу, ловим по закрытой трубе: после двойного fork оно нам внук, и waitpid не годится.
         * Окно добавляется к каждому подключению, но плохой конфиг роняет mihomo за 60-100 мс, и четверти секунды
         * хватает. Убрать окно нельзя: у ядер замера нет проверки по /proc, и без него пачка ждала бы порт все восемь секунд */
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

/* detached-поток, трубу закрывает сам */
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
        if (n <= 0) break;
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
