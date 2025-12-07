/*
 * set_slice.c
 *
 * Tool to set a custom EEVDF slice (sched_runtime) for a specific PID/TID.
 *
 * Usage: ./set_slice <PID> <SLICE_MS>
 * Example: ./set_slice 1234 20  (Sets 20ms slice for TID 1234)
 *
 * Compile:
 *   Android: clang set_slice.c -o set_slice
 *   Linux:   gcc set_slice.c -o set_slice
 */

#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <sys/syscall.h>
#include <linux/sched.h>

// If headers are missing
#ifndef __NR_sched_setattr
  #if defined(__x86_64__)
    #define __NR_sched_setattr 314
  #elif defined(__aarch64__)
    #define __NR_sched_setattr 274
  #endif
#endif

#ifndef SCHED_NORMAL
#define SCHED_NORMAL 0
#endif

struct sched_attr {
    uint32_t size;
    uint32_t sched_policy;
    uint64_t sched_flags;
    int32_t  sched_nice;
    uint32_t sched_priority;
    uint64_t sched_runtime;
    uint64_t sched_deadline;
    uint64_t sched_period;
};

int sched_setattr(pid_t pid, const struct sched_attr *attr, unsigned int flags)
{
    return syscall(__NR_sched_setattr, pid, attr, flags);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        printf("Usage: %s <PID> <SLICE_MS>\n", argv[0]);
        printf("  PID: Task ID to update\n");
        printf("  SLICE_MS: Slice in milliseconds (e.g. 10)\n");
        return 1;
    }

    pid_t pid = atoi(argv[1]);
    int slice_ms = atoi(argv[2]);
    uint64_t slice_ns = (uint64_t)slice_ms * 1000000ULL;

    struct sched_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.size = sizeof(attr);
    
    // We must preserve the existing policy/nice if possible, 
    // but sched_setattr requires us to specify them.
    // For simplicity, we assume SCHED_NORMAL and Nice 0 (or let kernel handle it).
    // A robust tool would read sched_getattr first.
    
    // Let's try to read current attributes first
    // Note: sched_getattr is syscall __NR_sched_getattr (315 on x86, 275 on arm64)
    // But for this simple tool, we'll just force SCHED_NORMAL + Custom Slice.
    
    attr.sched_policy = SCHED_NORMAL;
    attr.sched_nice = 0; // Warning: This might reset nice value!
    attr.sched_runtime = slice_ns; // THIS IS THE MAGIC FIELD for EEVDF

    printf("Setting PID %d to SCHED_NORMAL with Slice %d ms (%llu ns)...\n", 
           pid, slice_ms, attr.sched_runtime);

    if (sched_setattr(pid, &attr, 0) < 0) {
        perror("sched_setattr failed");
        return 1;
    }

    printf("Success! PID %d now has a custom slice.\n", pid);
    return 0;
}
