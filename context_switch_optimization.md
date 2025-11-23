# Optimization Strategy: Reducing Context Switch Overhead

This document analyzes strategies to reduce the high MIPS overhead observed in `finish_task_switch`, `_raw_spin_unlock_irq`, and related functions during FHD30 video recording.

## Part 1: Analysis of Your Proposals

### 1. Turn off `WAKEUP_PREEMPTION`
**Proposal**: Disable the scheduler feature that allows a newly woken task to preempt the currently running task immediately.
**Analysis**:
-   **Pros**: Significantly reduces "involuntary" context switches. If the Camera Service wakes up the Encoder, it won't immediately kick the Camera Service off the CPU. They might run to completion of their slice.
-   **Cons**: **Latency spikes**. If a high-priority UI or Audio thread wakes up and has to wait for a background task to finish its slice, you might see frame drops (jank) or audio glitches.
-   **Verdict**: **High Risk / High Reward**. Worth testing, but monitor "jank" stats closely. In modern kernels, this is often controlled via `sched_features`.

**Experiment Command**:
```bash
# Disable Wakeup Preemption
echo NO_WAKEUP_PREEMPTION > /sys/kernel/debug/sched/features

# Verify
cat /sys/kernel/debug/sched/features | grep WAKEUP_PREEMPTION
```

### 2. Increase `sched_base_slice_ns` AND `sched_wakeup_granularity_ns`
**Proposal**: Increase the minimum time a task runs (`base_slice`) AND the threshold required to preempt it (`wakeup_granularity`).
**Analysis**:
-   **The Trap**: Even with `NO_WAKEUP_PREEMPTION`, if a sleeping task wakes up with a very low `vruntime` (it's been starving), the scheduler might still preempt the current task if the difference exceeds `sched_wakeup_granularity_ns`.
-   **Scenario**: You observed a High Priority (Nice -20) task being preempted by a Normal (Nice 0) task after only 1.5ms. This happens because the Nice 0 task's "debt" exceeded the default granularity (often ~3-4ms).
-   **Solution**: You must increase **both**. `base_slice` gives you the *right* to run longer, but `wakeup_granularity` gives you the *defense* against waking tasks.
-   **Recommendation**: Set `wakeup_granularity` to be larger than `base_slice` (e.g., 1.5x or 2x) to strongly discourage preemption.

**Experiment Command**:
```bash
# For older kernels (CFS):
# Check current value (in nanoseconds, e.g., 3000000 = 3ms)
cat /proc/sys/kernel/sched_min_granularity_ns
# Increase to 10ms
echo 10000000 > /proc/sys/kernel/sched_min_granularity_ns

# CRITICAL: Increase wakeup granularity (e.g., to 15ms)
echo 15000000 > /proc/sys/kernel/sched_wakeup_granularity_ns

# For Linux 6.6+ (EEVDF Scheduler):
# The parameter is renamed to 'sched_base_slice_ns'
cat /sys/kernel/debug/sched/base_slice_ns
echo 10000000 > /sys/kernel/debug/sched/base_slice_ns
# Note: EEVDF handles lag differently, but base_slice is still the primary knob.
```

### 3. High Priority Cgroup & CPU Shares
**Proposal**: Add video threads to a high-priority cgroup and increase CPU shares.
**Analysis**:
-   **Effectiveness**: This helps with **contention** (making sure you get the CPU when you want it) but **doesn't necessarily reduce switching**.
-   **Why**: Even if you have 100% CPU shares, if your code logic is "Process Frame -> Send to Encoder -> Wait for Next Frame", you *will* sleep. And when you sleep, you switch.
-   **Verdict**: **Necessary but insufficient**. You should definitely do this to prevent *other* apps from stealing cycles, but it won't stop the intrinsic switching of the video pipeline itself.

**Experiment Command**:
```bash
# Find the PID of your thread (e.g., MediaCodec)
pid=$(pidof media.codec)

# Move to 'top-app' cgroup (highest priority in Android)
echo $pid > /dev/cpuset/top-app/tasks

# Alternatively, check stune (schedtune) boost
echo 50 > /dev/stune/top-app/schedtune.boost
```

---

## Part 2: Additional Recommendations

### 4. CPU Pinning (Affinity) & Isolation
**Strategy**: Pin the critical path (Camera Service, MediaCodec, SurfaceFlinger) to a specific set of "Big" or "Mid" cores.
**Why it helps**:
-   **Cache Locality**: If the producer and consumer run on the same cluster (or even same core, sequentially), the data stays hot in L2/L3 cache.
-   **Reduced Migration**: `finish_task_switch` is expensive, but **migration** (moving a task to another CPU) is even more expensive (IPIs, cache flushing). Pinning stops migration.
-   **Implementation**: Use `cpuset` cgroups or `taskset`.

**Experiment Command**:
```bash
# Pin PID 1234 to CPUs 4-7 (e.g., Mid/Big cores)
taskset -p f0 1234

# Or via cpusets (Android specific)
echo 4-7 > /dev/cpuset/camera-daemon/cpus
echo $pid > /dev/cpuset/camera-daemon/tasks
```

### 5. SCHED_FIFO (Real-Time Policy)
**Strategy**: Move the critical encoder/camera threads to `SCHED_FIFO` policy.
**Why it helps**:
-   **Priority**: `SCHED_FIFO` tasks **never** get preempted by normal (CFS) tasks. They run until they sleep or yield.
-   **Reduced Overhead**: The scheduling logic for RT tasks is simpler (`pick_next_task_rt` is faster than `pick_next_task_fair`).
-   **Risk**: If a FIFO thread goes into an infinite loop, your phone freezes (Watchdog will eventually kill it).

**Experiment Command**:
```bash
# Set PID 1234 to SCHED_FIFO with priority 50
chrt -f -p 50 1234

# Check status
chrt -p 1234
```

### 6. The Compromise Plan: Hybrid Real-Time (3A Only)
**Proposal**: Only promote the **3A (Auto Exposure/White Balance/Focus)** thread to `SCHED_FIFO`.

**Analysis**:
-   **Why it makes sense**: 3A is primarily **computational** (math heavy). It takes statistics, crunches numbers, and outputs settings. It rarely blocks on complex IPC (Binder) compared to the Request/Result threads.
-   **Benefit**: **Run-to-Completion**. When 3A wakes up, it runs uninterrupted until it finishes. This minimizes context switch overhead specifically for this heavy calculation.
-   **Safety**: Since it's just one thread (and usually runs on a specific cadence), the risk of freezing the whole system is much lower than the "All FIFO" approach.

**Experiment Command**:
```bash
# 1. Identify the 3A thread name (Vendor specific, e.g., "Cam3A", "Algo", "Hw3a")
ps -T -p $(pidof android.hardware.camera.provider@2.4-service)

# 2. Promote ONLY that thread
chrt -f -p 50 <TID_OF_3A_THREAD>
```

### 7. The Extremely Aggressive Plan: The "RTOS" Approach
**Proposal**: Since the video pipeline is periodic (33ms frames) and well-defined, move **ALL** Camera HAL and Encoder threads to `SCHED_FIFO`. Effectively treating Linux as a Real-Time Operating System.

**Analysis**:
-   **The Dream**: Perfect determinism. Thread A runs -> finishes -> wakes Thread B -> yields. No CFS overhead, no preemption by background apps.
-   **The Nightmare (Risks)**:
    1.  **Priority Inversion**: If your FIFO thread waits for a non-FIFO thread (e.g., Binder, Gralloc, SurfaceFlinger), the pipeline stalls. You must promote *all* dependencies.
    2.  **System Freeze**: If an I-frame takes 40ms to encode, the FIFO thread holds the CPU for 40ms. The UI thread (CFS) cannot run. The phone UI freezes, touch fails, and the Watchdog might reboot the device.

**Implementation Strategy**:
1.  **Identify Critical Path**: Only promote `RequestThread`, `ResultThread`, and `MediaCodec_loop`. Leave control threads as CFS.
2.  **Pinning is Mandatory**: Pin these FIFO threads to the **Big/Mid Cluster** only. Leave the Little Cluster free for the UI/System Server to keep the phone alive.
3.  **Watchdog**: Ensure your threads yield (sleep) frequently.

**Experiment Command**:
```bash
# 1. Find all threads of the camera provider
ps -T -p $(pidof android.hardware.camera.provider@2.4-service)

# 2. Batch promote them (DANGEROUS - Do not do this on a primary device without adb root access to revert)
for tid in $(ls /proc/$(pidof android.hardware.camera.provider@2.4-service)/task); do
    chrt -f -p 50 $tid
done
```

### 8. Batching (Pipeline Tuning)
**Strategy**: Instead of passing 1 frame at a time, pass **batches** of frames (if latency allows).
**Why it helps**:
-   **The Math**:
    -   1 Frame/switch = 30 switches/sec.
    -   3 Frames/switch = 10 switches/sec.
-   **Implementation**: This requires code changes in the Camera HAL or MediaCodec to buffer inputs.
-   **Trade-off**: Increases latency (the first frame waits for the third before processing starts).

### 9. Interrupt Coalescing (Hardware Tuning)
**Strategy**: Tune the hardware (Camera/Storage) to fire fewer interrupts.
**Why it helps**:
-   Every interrupt triggers `handle_softirqs` and often wakes up a thread (causing a switch).
-   If the hardware can buffer data and fire 1 interrupt for every 5 events, you reduce kernel overhead significantly.

---

## Summary of Action Plan

1.  **Immediate Tuning**: Increase `sched_min_granularity_ns` (or equivalent) to favor throughput.
2.  **Isolation**: Pin video threads to the Mid-core cluster.
3.  **Policy**: Experiment with `SCHED_FIFO` for the most critical encoder thread.
4.  **Code**: If possible, look into batching buffers in the HAL.

---

## Part 3: Verification - Did we actually win?

You asked: *"If I reduce MIPS and meet latency specs, is it a good optimization?"*
**Answer**: YES, absolutely. Reducing MIPS means the CPU does less "administrative work" (kernel overhead) and more "real work" (video encoding). This usually translates to **lower power consumption** and **better thermal performance**.

However, you must verify these 3 hidden risks:

### 1. The "Race to Sleep" & Power
-   **Theory**: Less switching = Better Cache Locality = Higher IPC (Instructions Per Clock). You finish the work faster and enter `cpuidle` sooner.
-   **Verify**: Check the **Power Meter** (or battery drain). MIPS isn't the only factor; CPU Frequency matters too. Ensure the scheduler isn't keeping the CPU at a high frequency for *too* long just because the tasks are running longer.

### 2. The 99th Percentile (Jank)
-   **Theory**: Average latency might be fine (33ms), but if one frame takes 50ms because a FIFO thread blocked the UI, you have a "Jank".
-   **Verify**: Don't just look at "Average FPS". Look at **Frame Drops** and **Max Frame Time**.
    ```bash
    dumpsys SurfaceFlinger --latency
    ```

### 3. System Responsiveness
-   **Theory**: If your video threads hog the CPU, background tasks (Notifications, Network, Thermal Daemon) might starve.
-   **Verify**: Try interacting with the phone while recording. Pull down the notification shade. Does it stutter? If yes, your optimization is too aggressive.
