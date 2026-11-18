#define _GNU_SOURCE
#include <jni.h>
#include <sched.h>
#include <stdio.h>
#include <unistd.h>

/* как fml::RequestAffinity(kNotEfficiency) в движке: все ядра, кроме самых медленных по cpuinfo_max_freq.
 * одинаковые ядра или нечитаемые частоты: маску не трогаем */
JNIEXPORT jboolean JNICALL
Java_com_keqdroid_keqdroid_NativeHelper_nativeAvoidEfficiencyCores(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    long count = sysconf(_SC_NPROCESSORS_CONF);
    if (count <= 1 || count > CPU_SETSIZE) return JNI_FALSE;

    long speeds[CPU_SETSIZE];
    long min = 0, max = 0;
    for (long i = 0; i < count; i++) {
        char path[96];
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%ld/cpufreq/cpuinfo_max_freq", i);
        speeds[i] = 0;
        FILE *f = fopen(path, "re");
        if (f) {
            if (fscanf(f, "%ld", &speeds[i]) != 1) speeds[i] = 0;
            fclose(f);
        }
        if (speeds[i] <= 0) continue;
        if (min == 0 || speeds[i] < min) min = speeds[i];
        if (speeds[i] > max) max = speeds[i];
    }
    if (min == 0 || min == max) return JNI_FALSE;

    cpu_set_t set;
    CPU_ZERO(&set);
    for (long i = 0; i < count; i++) {
        if (speeds[i] > min) CPU_SET((int)i, &set);
    }
    /* 0 значит вызывающий поток, а не весь процесс */
    return sched_setaffinity(0, sizeof(set), &set) == 0 ? JNI_TRUE : JNI_FALSE;
}
