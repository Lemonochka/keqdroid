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
 * Пишет строку ядра в logcat (XTAG) и, если задан logpath, дублирует её в файл.
 * Дублирование в файл нужно потому, что на Android 13+ untrusted_app не может
 * читать logcat (SELinux), поэтому in-app экран логов опирается на этот файл.
 * Файл кольцуется по размеру (CORE_LOG_MAX). logpath == "" → только logcat.
 */
static void core_log_line(const char *logpath, const char *line) {
    if (!line || !*line) return;
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
        int linepos = 0, elapsed = 0;

        while (elapsed < 3000) {
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
                break;
            } else {
                usleep(50000);
                elapsed += 50;
            }
        }
        if (linepos > 0) {
            line[linepos] = '\0';
            core_log_line(logpath, line);
        }

        int wstatus = 0;
        if (waitpid(pid2, &wstatus, WNOHANG) == pid2) {
            if (WIFEXITED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startCore: crashed immediately exit_code=%d", WEXITSTATUS(wstatus));
            else if (WIFSIGNALED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startCore: killed signal=%d", WTERMSIG(wstatus));
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
