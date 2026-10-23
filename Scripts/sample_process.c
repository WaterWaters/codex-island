// macOS aggregate process counters only. No command lines, paths or stacks.
// Build: xcrun clang -O2 Scripts/sample_process.c -o /tmp/island-sample
// Usage: /tmp/island-sample PID SECONDS INTERVAL_SECONDS > private-samples.jsonl
#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static long number(const char *text, long maximum) {
    char *end = NULL;
    errno = 0;
    long result = strtol(text, &end, 10);
    if (errno || !text[0] || *end || result < 1 || result > maximum) return -1;
    return result;
}

static double monotonic_seconds(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return value.tv_sec + value.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: island-sample PID SECONDS INTERVAL_SECONDS\n");
        return 2;
    }
    long pid = number(argv[1], 2147483647), duration = number(argv[2], 86400);
    long interval = number(argv[3], 60);
    if (pid < 1 || duration < 1 || interval < 1) return 2;
    double start = monotonic_seconds();
    for (;;) {
        struct rusage_info_v4 info = {0};
        if (proc_pid_rusage((int)pid, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
            fprintf(stderr, "Process counters unavailable (%s). No observation completed.\n", strerror(errno));
            return 1;
        }
        double elapsed = monotonic_seconds() - start;
        printf("{\"elapsedSeconds\":%.3f,\"userNanoseconds\":%" PRIu64
               ",\"systemNanoseconds\":%" PRIu64 ",\"physicalBytes\":%" PRIu64
               ",\"residentBytes\":%" PRIu64 ",\"interruptWakeups\":%" PRIu64
               ",\"packageIdleWakeups\":%" PRIu64 ",\"billedEnergyCounter\":%" PRIu64 "}\n",
               elapsed, info.ri_user_time, info.ri_system_time, info.ri_phys_footprint,
               info.ri_resident_size, info.ri_interrupt_wkups, info.ri_pkg_idle_wkups, info.ri_billed_energy);
        fflush(stdout);
        if (elapsed >= duration) break;
        double remaining = duration - elapsed;
        double wait = remaining < interval ? remaining : interval;
        struct timespec delay = {.tv_sec = (time_t)wait,
            .tv_nsec = (long)((wait - (time_t)wait) * 1e9)};
        while (nanosleep(&delay, &delay) == -1 && errno == EINTR) {}
    }
    return 0;
}
