// macOS aggregate process counters only. No command lines, paths or stacks.
// Build: xcrun clang -O2 Scripts/sample_process.c -o /tmp/island-sample
// Usage: /tmp/island-sample PID SECONDS INTERVAL_SECONDS > private-samples.jsonl
#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
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

static uint64_t nanoseconds(uint64_t ticks, mach_timebase_info_data_t timebase) {
    // proc_pid_rusage CPU counters use Mach absolute time, not nanoseconds.
    // Intel commonly has a 1:1 timebase; Apple Silicon need not.
    __uint128_t result = (__uint128_t)ticks * timebase.numer / timebase.denom;
    return result > UINT64_MAX ? UINT64_MAX : (uint64_t)result;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "Usage: island-sample PID SECONDS INTERVAL_SECONDS\n");
        return 2;
    }
    long pid = number(argv[1], 2147483647), duration = number(argv[2], 86400);
    long interval = number(argv[3], 60);
    if (pid < 1 || duration < 1 || interval < 1) return 2;
#if defined(__x86_64__)
    // Rosetta reports a virtual 1:1 Mach timebase, but proc_pid_rusage still
    // returns the host's native ticks. Refuse to publish misleading CPU data.
    int translated = 0;
    size_t translated_size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &translated_size, NULL, 0) == 0) {
        if (translated != 0) {
            fprintf(stderr, "Run the sampler natively; Rosetta CPU timebase is incompatible with process counters.\n");
            return 1;
        }
    } else if (errno != ENOENT) {
        fprintf(stderr, "Cannot establish native sampler execution. No observation completed.\n");
        return 1;
    }
#endif
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) {
        fprintf(stderr, "Mach timebase unavailable. No observation completed.\n");
        return 1;
    }
    double start = monotonic_seconds();
    for (;;) {
        struct rusage_info_v4 info = {0};
        if (proc_pid_rusage((int)pid, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
            fprintf(stderr, "Process counters unavailable (%s). No observation completed.\n", strerror(errno));
            return 1;
        }
        // V4 billed energy is a separate bank-accounting counter. Recount's
        // V6 field explicitly reports task CPU energy in nanojoules; older
        // SDKs/kernels retain the V4 sample with an unavailable energy value.
        char energy_nj[32] = "null";
#if defined(RUSAGE_INFO_V6) && !defined(ISLAND_SAMPLER_DISABLE_V6)
        struct rusage_info_v6 energy_info = {0};
        if (proc_pid_rusage((int)pid, RUSAGE_INFO_V6, (rusage_info_t *)&energy_info) == 0) {
            snprintf(energy_nj, sizeof(energy_nj), "%" PRIu64, energy_info.ri_energy_nj);
        }
#endif
        double elapsed = monotonic_seconds() - start;
        printf("{\"elapsedSeconds\":%.3f,\"userNanoseconds\":%" PRIu64
               ",\"systemNanoseconds\":%" PRIu64 ",\"physicalBytes\":%" PRIu64
               ",\"residentBytes\":%" PRIu64 ",\"interruptWakeups\":%" PRIu64
               ",\"packageIdleWakeups\":%" PRIu64 ",\"billedEnergyCounter\":%" PRIu64
               ",\"cpuTimeUnits\":\"nanoseconds\",\"machTimebaseNumer\":%" PRIu32 ",\"machTimebaseDenom\":%" PRIu32
               ",\"taskEnergyNanojoules\":%s}\n",
               elapsed, nanoseconds(info.ri_user_time, timebase), nanoseconds(info.ri_system_time, timebase),
               info.ri_phys_footprint, info.ri_resident_size, info.ri_interrupt_wkups, info.ri_pkg_idle_wkups,
               info.ri_billed_energy, timebase.numer, timebase.denom, energy_nj);
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
