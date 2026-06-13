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

#define TAG "KEQDIS"

/* Forward declaration — определение в конце файла */
static void *xray_log_reader(void *arg);
#define XTAG "KEQDIS_XRAY"

/*
 * double_fork_exec — запускает бинарник через двойной fork.
 *
 * Схема:
 *   JVM (родитель)
 *     └─ fork() → промежуточный (pid1)
 *                   setsid()          ← новая сессия
 *                   └─ fork() → внук (pid2) — execv(binary)
 *                   _exit(0)          ← промежуточный завершается
 *
 * JVM делает waitpid(pid1) — быстро, pid1 уже мёртв.
 * Внук (pid2) усыновляется init/zygote, полностью отвязан от JVM.
 * Phantom Process Killer не видит связи между JVM и pid2.
 *
 * pid2 передаётся через pipe обратно в JVM.
 */
static pid_t double_fork_exec(const char *binPath, char *const argv[], const char *assetDir) {
    /* pipe для передачи pid внука родителю */
    int pidpipe[2];
    if (pipe(pidpipe) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "double_fork_exec: pipe failed errno=%d", errno);
        return -1;
    }

    pid_t pid1 = fork();
    if (pid1 < 0) {
        close(pidpipe[0]); close(pidpipe[1]);
        __android_log_print(ANDROID_LOG_ERROR, TAG, "double_fork_exec: first fork failed errno=%d", errno);
        return -1;
    }

    if (pid1 == 0) {
        /* ── промежуточный процесс ── */
        close(pidpipe[0]); /* не читаем */

        setsid();
        prctl(PR_SET_PDEATHSIG, 0);

        pid_t pid2 = fork();
        if (pid2 < 0) {
            /* не смогли форкнуть внука */
            pid_t err = -1;
            write(pidpipe[1], &err, sizeof(err));
            close(pidpipe[1]);
            _exit(1);
        }

        if (pid2 == 0) {
            /* ── внук: целевой процесс ── */
            close(pidpipe[1]);
            prctl(PR_SET_PDEATHSIG, 0);

            /* Закрываем все fd кроме stdin/stdout/stderr */
            int max = (int)sysconf(_SC_OPEN_MAX);
            for (int i = 3; i < max; i++) close(i);

            if (assetDir) setenv("XRAY_LOCATION_ASSET", assetDir, 1);

            execv(binPath, argv);
            /* execv вернулся — ошибка */
            _exit(127);
        }

        /* промежуточный: отправляем pid2 родителю и умираем */
        write(pidpipe[1], &pid2, sizeof(pid2));
        close(pidpipe[1]);
        _exit(0);
    }

    /* ── родитель (JVM) ── */
    close(pidpipe[1]);

    /* ждём завершения промежуточного (быстро) */
    int wstatus;
    waitpid(pid1, &wstatus, 0);

    /* читаем pid внука */
    pid_t pid2 = -1;
    read(pidpipe[0], &pid2, sizeof(pid2));
    close(pidpipe[0]);

    return pid2;
}

/* ── tun2socks ──────────────────────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_startTun2Socks(
        JNIEnv *env, jclass clazz,
        jint tunFd, jstring jBinPath, jstring jProxyUrl) {

    const char *binPath  = (*env)->GetStringUTFChars(env, jBinPath,  NULL);
    const char *proxyUrl = (*env)->GetStringUTFChars(env, jProxyUrl, NULL);

    /* Снимаем FD_CLOEXEC — fd должен пережить execv */
    fcntl(tunFd, F_SETFD, fcntl(tunFd, F_GETFD) & ~FD_CLOEXEC);

    char fdStr[32];
    snprintf(fdStr, sizeof(fdStr), "fd://%d", (int)tunFd);

    char *argv[] = {
            (char *)binPath,
            "--device",  fdStr,
            "--proxy",   (char *)proxyUrl,
            "--loglevel","warning",
            NULL
    };

    /* pidpipe — передаём pid2 родителю */
    int pidpipe[2];
    if (pipe(pidpipe) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startTun2Socks: pidpipe failed errno=%d", errno);
        (*env)->ReleaseStringUTFChars(env, jBinPath,  binPath);
        (*env)->ReleaseStringUTFChars(env, jProxyUrl, proxyUrl);
        return -1;
    }

    /*
     * diagpipe — внук пишет errno сразу после execv (если execv провалился)
     * или закрывает его при успешном execv (FD_CLOEXEC снят не будет, поэтому
     * при успешном execv write-конец закроется автоматически → read вернёт 0).
     * Родитель читает int: 0 = execv успешен, >0 = errno ошибки.
     */
    int diagpipe[2];
    if (pipe(diagpipe) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startTun2Socks: diagpipe failed errno=%d", errno);
        close(pidpipe[0]); close(pidpipe[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath,  binPath);
        (*env)->ReleaseStringUTFChars(env, jProxyUrl, proxyUrl);
        return -1;
    }
    /* diagpipe[1] должен закрыться при execv — ставим FD_CLOEXEC */
    fcntl(diagpipe[1], F_SETFD, fcntl(diagpipe[1], F_GETFD) | FD_CLOEXEC);

    pid_t pid1 = fork();
    if (pid1 < 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startTun2Socks: first fork failed errno=%d", errno);
        close(pidpipe[0]); close(pidpipe[1]);
        close(diagpipe[0]); close(diagpipe[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath,  binPath);
        (*env)->ReleaseStringUTFChars(env, jProxyUrl, proxyUrl);
        return -1;
    }

    if (pid1 == 0) {
        /* ── промежуточный ── */
        close(pidpipe[0]);
        close(diagpipe[0]);
        setsid();
        prctl(PR_SET_PDEATHSIG, 0);

        pid_t pid2 = fork();
        if (pid2 < 0) {
            pid_t err = -1;
            write(pidpipe[1], &err, sizeof(err));
            close(pidpipe[1]);
            close(diagpipe[1]);
            _exit(1);
        }

        if (pid2 == 0) {
            /* ── внук: tun2socks ── */
            close(pidpipe[1]);
            prctl(PR_SET_PDEATHSIG, 0);

            /* Закрываем всё кроме stdin/stdout/stderr, tunFd и diagpipe[1] */
            int max = (int)sysconf(_SC_OPEN_MAX);
            for (int i = 3; i < max; i++) {
                if (i != (int)tunFd && i != diagpipe[1]) close(i);
            }

            execv(binPath, argv);

            /* execv провалился — пишем errno в diagpipe и выходим */
            int err = errno;
            write(diagpipe[1], &err, sizeof(err));
            close(diagpipe[1]);
            _exit(127);
        }

        /* промежуточный: отправляем pid2 и умираем */
        close(diagpipe[1]); /* промежуточный не пишет в diagpipe */
        write(pidpipe[1], &pid2, sizeof(pid2));
        close(pidpipe[1]);
        _exit(0);
    }

    /* ── родитель (JVM) ── */
    close(pidpipe[1]);
    close(diagpipe[1]); /* закрываем write-конец — читаем только read-конец */

    waitpid(pid1, NULL, 0);

    pid_t pid2 = -1;
    read(pidpipe[0], &pid2, sizeof(pid2));
    close(pidpipe[0]);

    (*env)->ReleaseStringUTFChars(env, jBinPath,  binPath);
    (*env)->ReleaseStringUTFChars(env, jProxyUrl, proxyUrl);

    if (pid2 <= 0) {
        close(diagpipe[0]);
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startTun2Socks: second fork failed");
        return -1;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "startTun2Socks: pid=%d", (int)pid2);

    /*
     * Ждём короткое время (~300ms) чтобы поймать немедленный execv-краш.
     * Если execv успешен — diagpipe[1] закрылся в exec (FD_CLOEXEC),
     * read вернёт 0. Если провалился — прочитаем errno.
     *
     * fcntl O_NONBLOCK + usleep чтобы не блокировать JVM надолго.
     */
    {
        fcntl(diagpipe[0], F_SETFL, fcntl(diagpipe[0], F_GETFL, 0) | O_NONBLOCK);
        int diag_errno = 0;
        int waited = 0;
        ssize_t nr;
        while (waited < 300) {
            nr = read(diagpipe[0], &diag_errno, sizeof(diag_errno));
            if (nr > 0) {
                /* execv провалился */
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startTun2Socks: execv failed errno=%d (%s) path=%s",
                                    diag_errno, strerror(diag_errno), binPath);
                close(diagpipe[0]);
                /* Убиваем внука если он как-то выжил */
                kill(pid2, SIGKILL);
                return -1;
            } else if (nr == 0) {
                /* EOF — write-конец закрылся: execv успешен */
                break;
            } else {
                usleep(10000); /* 10ms */
                waited += 10;
            }
        }
        close(diagpipe[0]);

        /* Проверяем не умер ли процесс сразу после execv */
        int wstatus = 0;
        if (waitpid(pid2, &wstatus, WNOHANG) == pid2) {
            if (WIFEXITED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startTun2Socks: process exited immediately code=%d", WEXITSTATUS(wstatus));
            else if (WIFSIGNALED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startTun2Socks: process killed signal=%d", WTERMSIG(wstatus));
            return -1;
        }
    }

    return (jint)pid2;
}

/* ── Xray ───────────────────────────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_startXray(
        JNIEnv *env, jclass clazz,
        jstring jBinPath, jstring jConfigPath, jstring jAssetDir) {

    const char *binPath    = (*env)->GetStringUTFChars(env, jBinPath,    NULL);
    const char *configPath = (*env)->GetStringUTFChars(env, jConfigPath, NULL);
    const char *assetDir   = (*env)->GetStringUTFChars(env, jAssetDir,   NULL);

    if (access(binPath, F_OK) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: binary not found: %s", binPath);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -1;
    }
    if (access(configPath, F_OK) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: config not found: %s", configPath);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -2;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG,
                        "startXray: bin=%s config=%s asset=%s", binPath, configPath, assetDir);

    int pipefd[2] = {-1, -1};
    if (pipe(pipefd) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: output pipe failed errno=%d", errno);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    int pidpipe[2];
    if (pipe(pidpipe) != 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: pid pipe failed errno=%d", errno);
        close(pipefd[0]); close(pipefd[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    pid_t pid1 = fork();
    if (pid1 < 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: first fork failed errno=%d", errno);
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
            for (int i = 3; i < max; i++) close(i);

            setenv("XRAY_LOCATION_ASSET", assetDir, 1);

            char *argv[] = { (char *)binPath, "run", "-c", (char *)configPath, NULL };
            execv(binPath, argv);
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
        __android_log_print(ANDROID_LOG_ERROR, TAG, "startXray: second fork failed");
        if (pipefd[0] >= 0) close(pipefd[0]);
        return -3;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "startXray: forked pid=%d", (int)pid2);

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
                            __android_log_print(ANDROID_LOG_DEBUG, XTAG, "%s", line);
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
            __android_log_print(ANDROID_LOG_DEBUG, XTAG, "%s", line);
        }

        int wstatus = 0;
        if (waitpid(pid2, &wstatus, WNOHANG) == pid2) {
            if (WIFEXITED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startXray: crashed immediately exit_code=%d", WEXITSTATUS(wstatus));
            else if (WIFSIGNALED(wstatus))
                __android_log_print(ANDROID_LOG_ERROR, TAG,
                                    "startXray: killed signal=%d", WTERMSIG(wstatus));
            close(pipefd[0]);
            return -4;
        }

        fcntl(pipefd[0], F_SETFL, fcntl(pipefd[0], F_GETFL, 0) & ~O_NONBLOCK);

        int *fdptr = malloc(sizeof(int));
        if (fdptr) {
            *fdptr = pipefd[0];

            pthread_t thr;
            pthread_attr_t attr;
            pthread_attr_init(&attr);
            pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

            int rc = pthread_create(&thr, &attr, xray_log_reader, fdptr);
            pthread_attr_destroy(&attr);

            if (rc != 0) {
                __android_log_print(ANDROID_LOG_WARN, TAG,
                                    "startXray: failed to start log reader thread rc=%d", rc);
                free(fdptr);
                close(pipefd[0]);
            }
        } else {
            close(pipefd[0]);
        }
    }

    return (jint)pid2;
}

JNIEXPORT jint JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_startKphttp(
        JNIEnv *env, jclass clazz,
        jstring jBinPath, jstring jConfigPath, jstring jAssetDir) {

    const char *binPath    = (*env)->GetStringUTFChars(env, jBinPath,    NULL);
    const char *configPath = (*env)->GetStringUTFChars(env, jConfigPath, NULL);
    const char *assetDir   = (*env)->GetStringUTFChars(env, jAssetDir,   NULL);

    if (access(binPath, F_OK) != 0) {
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -1;
    }
    if (access(configPath, F_OK) != 0) {
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -2;
    }

    int pipefd[2] = {-1, -1};
    if (pipe(pipefd) != 0) {
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    int pidpipe[2];
    if (pipe(pidpipe) != 0) {
        close(pipefd[0]); close(pipefd[1]);
        (*env)->ReleaseStringUTFChars(env, jBinPath, binPath);
        (*env)->ReleaseStringUTFChars(env, jConfigPath, configPath);
        (*env)->ReleaseStringUTFChars(env, jAssetDir, assetDir);
        return -3;
    }

    pid_t pid1 = fork();
    if (pid1 < 0) {
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
            for (int i = 3; i < max; i++) close(i);

            char *argv[] = { (char *)binPath, "--config", (char *)configPath, NULL };
            execv(binPath, argv);
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
        close(pipefd[0]);
        return -3;
    }

    if (pipefd[0] >= 0) {
        int *fdptr = (int *)malloc(sizeof(int));
        if (fdptr != NULL) {
            *fdptr = pipefd[0];
            pthread_t thr;
            pthread_attr_t attr;
            pthread_attr_init(&attr);
            pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
            int rc = pthread_create(&thr, &attr, xray_log_reader, fdptr);
            pthread_attr_destroy(&attr);
            if (rc != 0) {
                free(fdptr);
                close(pipefd[0]);
            }
        } else {
            close(pipefd[0]);
        }
    }

    return (jint)pid2;
}

/* ── base64 decode ──────────────────────────────────────────────────────── */

static int b64val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return 0;
}

/* Декодирует base64 строку. Возвращает кол-во байт или -1.
 *
 * Исправление: старая проверка "olen + 3 > maxlen" ошибочно отклоняла
 * ключи длиной 43 символа (base64 без '='): на последней неполной группе
 * olen=30, 30+3=33 > 32 → возврат -1, хотя реально пишется только 2 байта.
 * Теперь проверяем фактическое количество байт для текущей группы.
 */
static int b64_decode(const char *in, uint8_t *out, int maxlen) {
    int len = (int)strlen(in);
    /* убираем trailing = и пробелы */
    while (len > 0 && (in[len-1] == '=' || in[len-1] == ' ' ||
                       in[len-1] == '\n' || in[len-1] == '\r')) len--;
    int olen = 0;
    for (int i = 0; i < len; i += 4) {
        /* сколько байт запишем в этой группе: 1, 2 или 3 */
        int nbytes = 1 + (i+2 < len ? 1 : 0) + (i+3 < len ? 1 : 0);
        if (olen + nbytes > maxlen) return -1;
        int a = b64val(in[i]);
        int b = (i+1 < len) ? b64val(in[i+1]) : 0;
        int c = (i+2 < len) ? b64val(in[i+2]) : 0;
        int d = (i+3 < len) ? b64val(in[i+3]) : 0;
        out[olen++] = (uint8_t)((a << 2) | (b >> 4));
        if (i+2 < len) out[olen++] = (uint8_t)(((b & 0xf) << 4) | (c >> 2));
        if (i+3 < len) out[olen++] = (uint8_t)(((c & 0x3) << 6) | d);
    }
    return olen;
}

/* Hex-кодирование. out должен быть 2*len+1 байт. */
static void hex_encode(const uint8_t *in, int len, char *out) {
    static const char hx[] = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        out[i*2]   = hx[in[i] >> 4];
        out[i*2+1] = hx[in[i] & 0xf];
    }
    out[len*2] = '\0';
}

/* Проверяет, является ли строка hex-ключом WG (ровно 64 hex-символа). */
static int is_hex_key(const char *s) {
    int len = (int)strlen(s);
    if (len != 64) return 0;
    for (int i = 0; i < 64; i++) {
        char c = s[i];
        if (!((c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F'))) return 0;
    }
    return 1;
}

/*
 * WG-ключ → hex строка (64 символа + '\0'). Возвращает 1 при успехе.
 * Автоматически определяет формат: hex (64 симв.) или base64 (44 симв. с '=').
 */
static int key_to_hex(const char *key, char *out65) {
    if (is_hex_key(key)) {
        /* уже hex — просто нормализуем в нижний регистр */
        for (int i = 0; i < 64; i++)
            out65[i] = (char)(key[i] >= 'A' && key[i] <= 'F'
                              ? key[i] - 'A' + 'a' : key[i]);
        out65[64] = '\0';
        return 1;
    }
    /* пробуем base64 */
    uint8_t raw[32];
    if (b64_decode(key, raw, 32) != 32) return 0;
    hex_encode(raw, 32, out65);
    return 1;
}

/* ── helpers ────────────────────────────────────────────────────────────── */

static void trim_str(char *s) {
    char *p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p)+1);
    int l = (int)strlen(s);
    while (l > 0 && (s[l-1]==' '||s[l-1]=='\t'||s[l-1]=='\n'||s[l-1]=='\r'))
        s[--l] = '\0';
}

/* ── буферизованный запись в сокет ──────────────────────────────────────── */

typedef struct { int fd; char buf[65536]; int pos; int err; } UW;

static void uw_init(UW *w, int fd) { w->fd=fd; w->pos=0; w->err=0; }

static void uw_write(UW *w, const char *s) {
    int n = (int)strlen(s);
    if (w->err || n == 0) return;
    /* Если строка не влезает в буфер — сначала сбрасываем буфер, затем
       пишем напрямую (актуально для длинных I1-I5 CPS-строк). */
    if (w->pos + n >= (int)sizeof(w->buf)) {
        if (w->pos > 0) {
            if (write(w->fd, w->buf, w->pos) != w->pos) { w->err=1; return; }
            w->pos = 0;
        }
        if (n >= (int)sizeof(w->buf)) {
            /* строка длиннее всего буфера — пишем напрямую */
            if (write(w->fd, s, n) != n) { w->err=1; }
            return;
        }
    }
    memcpy(w->buf + w->pos, s, n);
    w->pos += n;
}

static int uw_flush(UW *w) {
    if (w->err) return -1;
    if (w->pos > 0 && write(w->fd, w->buf, w->pos) != w->pos) return -1;
    w->pos = 0;
    return 0;
}

/* ── Фоновый читатель вывода Xray ─────────────────────────────────────────
 *
 * Читает pipe до EOF (Xray завершился) и пишет каждую строку в logcat.
 * Запускается как detached pthread — не нужно join().
 * fd закрывает сам перед выходом.
 */
static void *xray_log_reader(void *arg) {
    int fd = *(int *)arg;
    free(arg);

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
                    __android_log_print(ANDROID_LOG_DEBUG, XTAG, "%s", line);
                linepos = 0;
            } else {
                line[linepos++] = c;
            }
        }
    }
    if (linepos > 0) {
        line[linepos] = '\0';
        __android_log_print(ANDROID_LOG_DEBUG, XTAG, "%s", line);
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "xray_log_reader: pipe closed (xray exited)");
    close(fd);
    return NULL;
}
