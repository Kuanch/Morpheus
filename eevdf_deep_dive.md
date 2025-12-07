# Deep Dive: The EEVDF Scheduler (Linux 6.12+)

This document explains the mechanics of the **Earliest Eligible Virtual Deadline First (EEVDF)** scheduler, which replaced CFS in recent Linux kernels. It focuses on how it handles preemption, wakeup latency, and fairness.

## 1. The Core Shift: From "Fairness" to "Deadlines"

### Legacy CFS (Completely Fair Scheduler)
-   **Goal**: "Everyone gets an equal % of the CPU."
-   **Mechanism**: Tracks `vruntime` (virtual runtime). The task with the *lowest* `vruntime` runs next.
-   **Preemption**: If a waking task has a lower `vruntime` than the current task (minus a "granularity" fudge factor), it preempts.
-   **Problem**: It struggled with latency. To reduce latency, you had to reduce the slice (granularity), which hurt throughput. It was a trade-off.

### EEVDF (Earliest Eligible Virtual Deadline First)
-   **Goal**: "Everyone gets their slice by a specific deadline."
-   **Mechanism**: Tracks two things:
    1.  **Eligibility**: "Am I owed service right now?" (Based on `vruntime` vs. Average).
    2.  **Deadline**: "When should I finish my slice?" (Based on `vruntime` + `slice`).
-   **Decision**: Pick the **Eligible** task with the **Earliest Deadline**.

---

## 1.1 The Math: Calculating the Deadline

You asked: *"Is the deadline calculated as `se->deadline = se->vruntime + calc_delta_fair(delta_exec) + calc_delta_fair(slice)`?"*

**Answer**: **YES.**

The deadline is **not static**. It is a rolling target calculated when a task finishes a slice (or yields).

**The Formula**:
```c
// In update_deadline():
se->deadline = se->vruntime + calc_delta_fair(se->slice, se);
```
*   `se->vruntime`: The task's *current* virtual runtime (which includes the `delta_exec` it just ran).
*   `calc_delta_fair(se->slice, se)`: The *virtual* size of the new slice.

**The Implication**:
*   **Rolling Target**: Every time you burn a slice, your deadline is pushed forward by one virtual slice.
*   **Back of the Line**: This new deadline is likely later than other tasks, so you move to the back of the queue.

---

## 2. Wakeup Logic: Handling "Lag"

You asked: *"When a long sleep task is waken, its vruntime must be aggressively behind... how does EEVDF handle this?"*

**Answer**: EEVDF explicitly calculates and preserves **Lag**.

### The Mechanism (`place_entity`)
When a task sleeps, it stops accumulating `vruntime`. Meanwhile, the system's "Average Vruntime" keeps moving forward. The difference is **Lag** (Positive Lag = Credit).

In CFS, this "credit" was often capped to prevent a task from starving everyone else for seconds (the "sleeper bonus" problem).

In EEVDF:
1.  **Lag Calculation**: `lag = avg_vruntime - se->vruntime`
2.  **Placement**: `se->vruntime = avg_vruntime - lag`
    *   It **preserves** the credit. A long-sleeping task wakes up with a `vruntime` significantly *behind* the current time.
3.  **Eligibility**: Because its `vruntime` is so low, it is immediately **Eligible**.
4.  **Deadline**: Its deadline is calculated as `vruntime + slice`. Since `vruntime` is low, its deadline is also very early (likely earlier than the current running task).
5.  **Result**: It preempts immediately (unless Slice Protection kicks in).

---

## 3. Slice Protection: Preventing "Context Switch Storms"

You asked: *"How does slice protection work?"*

**Answer**: Slice Protection is the EEVDF equivalent of "Granularity", but smarter. It guarantees a task can run for a minimum amount of time even if a "better" task wakes up.

### The Mechanism (`protect_slice`)
1.  **The Protected Zone**: Every time a task is picked, the scheduler calculates a `vprot` (Protected Virtual Runtime).
    *   `vprot = vruntime + base_slice`
2.  **The Check**: When a new task wakes up (even one with an earlier deadline!), the scheduler checks:
    *   `if (current->vruntime < current->vprot)` -> **Do Not Preempt**.
3.  **The Exception (`PREEMPT_SHORT`)**:
    *   If the waking task has a **shorter slice** (e.g., a high-priority audio thread with a tiny slice) than the current task, it is allowed to "puncture" the protection.
    *   This allows latency-sensitive tasks to preempt throughput-heavy tasks, but prevents two throughput tasks from thrashing each other.

### Why this is better than CFS Granularity
-   **CFS**: "Don't preempt if difference < X ms". It was a static wall.
-   **EEVDF**: "Don't preempt if I haven't finished my guaranteed slice yet, UNLESS you are a tiny latency-sensitive task." It adapts to the workload.

---

## 5. Cross-CPU Migration: The "Lag" Problem

You asked: *"If a task sleeps on CPU0 but wakes on CPU1, does CPU1 pay for CPU0's debt?"*

**Answer**: **YES, but with a limit.**

### The Mechanism
1.  **Leaving CPU0**: When the task dequeues (migrates), EEVDF calculates its Lag.
    *   `update_entity_lag()` is called.
    *   **Crucial Step**: The lag is **clamped** to `+/- 2 * se->slice`.
    *   This prevents a task from accumulating infinite credit (e.g., if it was stuck behind a realtime task for 10 seconds).
2.  **Joining CPU1**: When the task enqueues on CPU1:
    *   `place_entity()` sees the preserved `vlag`.
    *   It subtracts this lag from CPU1's average vruntime.
    *   `vruntime = avg_vruntime(CPU1) - vlag`.

### The Implication
-   **The "Bully" Effect**: If your task had positive lag (credit) on CPU0, it **will** come to CPU1 with a very low `vruntime` and likely preempt the current task on CPU1 immediately.
-   **The Limit**: Since lag is capped at `2 * slice`, the maximum "bullying" it can do is roughly **2 full time slices**.
-   **Trade-off**: If you increase `sched_base_slice_ns` (e.g., to 10ms), you are also increasing this "Migration Credit Limit" (to 20ms). A migrated task could potentially hog CPU1 for 20ms to catch up.

---

## 7. Cgroups: The Hierarchy of Fairness

You asked: *"How does cgroup affect the task picking and wakeup_preempt?"*

**Answer**: EEVDF is **Hierarchical**. It doesn't just compare Task A vs. Task B. It compares **Group A vs. Group B**.

### The Mechanism (`find_matching_se`)
When a task in `Group A` wakes up and tries to preempt a task in `Group B`:
1.  **Walk Up**: The scheduler walks up the cgroup tree for both tasks until it finds the **Highest Common Ancestor**.
2.  **Comparison**: It compares the **Group Entities** at that level.
    *   Example: `Root -> AppGroup -> TaskA` vs `Root -> BgGroup -> TaskB`.
    *   It compares `AppGroup` vs `BgGroup`.
3.  **Decision**:
    *   If `AppGroup` is eligible and has an earlier deadline than `BgGroup`, it wins.
    *   **Crucial**: The individual deadline of `TaskA` doesn't matter yet. If `AppGroup` is starving, `TaskA` gets to run, even if `TaskA` itself has a "bad" deadline relative to `TaskB`.

### Why this matters for you
-   **Isolation**: This is why placing your video threads in a `top-app` cgroup (with high shares/weight) is so effective.
-   **The Shield**: If `top-app` has a huge weight, its `vruntime` moves very slowly. It will almost always be "Eligible" compared to `background`.
-   **Preemption**: A task in `top-app` will preempt a task in `background` almost immediately, because the *Group* comparison wins, regardless of the tasks' individual states.

---

## 8. Example: The Math of Isolation

You asked: *"Could you give me examples about different cgroup and how this affect tasks' vruntime?"*

**Scenario**:
-   **Group A (`top-app`)**: Weight = 10240 (High Priority)
-   **Group B (`background`)**: Weight = 102 (Low Priority)
-   **Standard Weight**: 1024 (Nice 0)

**The Formula**:
`vruntime_delta = physical_time * (1024 / weight)`

**The Race**:
Both groups run for **10ms** of physical time.

1.  **Group A (`top-app`)**:
    *   `vruntime += 10ms * (1024 / 10240)`
    *   `vruntime += 10ms * 0.1`
    *   **Result**: Increases by only **1ms**.

2.  **Group B (`background`)**:
    *   `vruntime += 10ms * (1024 / 102)`
    *   `vruntime += 10ms * 10`
    *   **Result**: Increases by **100ms**.

**The Consequence**:
*   Group B's `vruntime` explodes. It moves "to the back of the line" extremely fast.
*   Group A's `vruntime` barely moves. It stays "Eligible" (below the average) for a very long time.
*   **Conclusion**: Group A can run for 100ms, and it will *still* appear to have used less "virtual time" than Group B running for just 1ms. This is why `top-app` dominates the CPU.

---

## 6. Tuning for Your Workload (Video Recording)

Since you are on Linux 6.12+ (EEVDF), your tuning strategy changes:

| Feature | Old CFS Knob | New EEVDF Knob |
| :--- | :--- | :--- |
| **Minimum Run Time** | `sched_min_granularity_ns` | `sched_base_slice_ns` |
| **Wakeup Preemption** | `sched_wakeup_granularity_ns` | **REMOVED** (Handled by Slice Protection) |
| **Latency vs Throughput** | Hard to tune | Tune `base_slice_ns` directly |

**Recommendation**:
Keep increasing `sched_base_slice_ns`.
-   **Effect**: It increases the `vprot` window.
-   **Result**: Your video encoder gets a larger "Protected Zone" where it cannot be preempted by background noise, even if that background noise has "better" deadlines.

---

## 9. Common Android Cgroups

Android uses cgroups heavily to segregate tasks. Here are the standard ones:

| Cgroup Name | Typical Shares (Weight) | Quota (Throttling) | Purpose |
| :--- | :--- | :--- | :--- |
| **`top-app`** | **High** (e.g., 20,480+) | **None** (-1) | The app currently on screen + SurfaceFlinger. The "VIP" room. |
| **`foreground`** | **Default** (1,024) | **None** (-1) | Apps running foreground services (e.g., Music playback). |
| **`background`** | **Low** (e.g., 102) | **Strict** (e.g., 50%) | Apps not visible. They get scraps of CPU time. |
| **`system-background`** | **Tiny** (e.g., 52) | **Strict** | Maintenance tasks. |

**How EEVDF treats them**:
*   `top-app` is almost always "Eligible" because its weight is massive. It effectively has "infinite credit".
*   `background` is almost never "Eligible" if `top-app` wants to run.

---

## 10. The "Ultra" Cgroup Experiment

You asked: *"If I have an 'ultra' cgroup (shares=20480) and 'top-app' (shares=4096), what happens?"*

**Analysis**:

1.  **The CFS Battle (Ultra vs. Top-App)**:
    *   **Ultra**: 20480 shares.
    *   **Top-App**: 4096 shares.
    *   **Ratio**: 5:1.
    *   **Result**: If both groups are 100% busy, **Ultra gets 83% of the CPU**, and Top-App gets 17%.
    *   **Conclusion**: Yes, your "Ultra" group becomes the new King of CFS. It will dominate `top-app`.

2.  **Does this stop RT Preemption?**
    *   **Answer**: **NO.** Absolutely not.

---

## 11. The RT Wall: Cgroups vs. Real-Time

You asked: *"Does this avoid RT preempt CFS? or cgroup just have effects on CFS tasks?"*

**The Hard Truth**:
`cpu.shares` (and the entire EEVDF/CFS logic) **ONLY** applies to `SCHED_NORMAL` tasks.

**The Hierarchy of Power**:
1.  **Stop Class** (Migration/Watchdog) - *God Mode*
2.  **Deadline Class** (`SCHED_DEADLINE`)
3.  **Real-Time Class** (`SCHED_FIFO` / `SCHED_RR`)
4.  **Fair Class** (`SCHED_NORMAL` / `SCHED_BATCH`) <- **Your Cgroups live here**
5.  **Idle Class**

**The Consequence**:
*   If you have a `SCHED_FIFO` task (even a tiny one with Priority 1), it is **strictly more important** than your "Ultra" group.
*   The kernel will **always** pick the RT task first.
*   Your "Ultra" group (shares=20480) will be preempted **immediately** by any RT task.
*   **Cgroups cannot protect you from RT tasks.** They only protect you from *other* CFS tasks (like background services).

---

## 12. The Shield: How Shares Prevent Preemption

You asked: *"Does higher cpu.shares protect tasks being preempted by wakeup CFS or other CFS?"*

**Answer**: **YES.** High shares act as a "Preemption Shield" against other CFS tasks.

### Mechanism 1: Protection from "Wakeup Preemption"
When a background task wakes up, it wants to run. The scheduler compares it to the Current Task (You).
*   **Scenario**: You are in `Ultra` (High Shares). You have been running for 5ms.
*   **The Math**: Because of your high shares, your `vruntime` has only increased by a tiny amount (e.g., 0.5ms virtual time).
*   **The Check**: The scheduler sees your `vruntime` is still very low (you look "starving").
*   **Result**: The scheduler decides you are still "Eligible" and "Deserving", so it **denies** the background task's request to preempt you. You keep running.

### Mechanism 2: Protection from "Tick Preemption" (Time Limit)
Normally, a task is preempted when its "Time Slice" runs out (e.g., every 3ms).
*   **The Math**: `vruntime` grows slower for High Share tasks.
*   **The Result**: It takes much longer (in real time) for your `vruntime` to reach the deadline.
*   **Effect**: A standard task might get kicked off after 3ms. Your `Ultra` task might run for 15ms or 20ms before the scheduler decides it has "used up" its fair share.

**Summary**:
*   **High Shares** = **Slower Vruntime Growth** = **Harder to Preempt**.

---

## 13. Advanced Tuning: Custom Slices per Task

You asked: *"How do we manage to adjust `se->slice` in EEVDF? Do I have to change kernel code?"*

**Answer**: **NO.** You can use the `sched_setattr()` syscall from userspace.

### The Mechanism
EEVDF allows specific tasks to have a **Custom Slice** (`se->custom_slice`), overriding the global default.
*   **Syscall**: `sched_setattr()`
*   **Parameter**: `sched_attr.sched_runtime`
*   **Mapping**: `se->slice = attr->sched_runtime`

### How to Implement
1.  **In C/C++ (Production)**:
    Call `sched_setattr` in your Camera HAL code for critical threads.
    ```c
    struct sched_attr attr = {
        .size = sizeof(attr),
        .sched_policy = SCHED_NORMAL,
        .sched_nice = 0,
        .sched_runtime = 20 * 1000 * 1000, // 20ms Slice (Huge Protection)
    };
    sched_setattr(0, &attr, 0); // 0 = Current Thread
    ```

2.  **Command Line (Testing)**:
    I have created a tool `set_slice.c` (check your workspace).
    ```bash
    # Set PID 1234 to have a 20ms slice
    ./set_slice 1234 20
    ```

### Verification
You can verify if a task has a custom slice by reading `/proc/sched_debug`.
*   Look for the **'S'** flag (Slice) in the task list.
*   Example:
    ```text
    R  task   PID    ...  custom_slice ...
    R  CamHAL 1234   ...       S       ...
    ```

**Why this is the "Holy Grail"**:
*   You can leave the global system responsive (small default slice).
*   But give your Video Encoder a **massive** slice (e.g., 20ms) so it never gets preempted during a frame.

---

## 14. Verification: Checking `se->slice`

You asked: *"How do we check `se->slice`? Any cmd for it?"*

**Answer**: Yes, the kernel exposes this in two places.

### 1. The Global View (`/proc/sched_debug`)
This is the best way to see the slice for **every running task**.

```bash
cat /proc/sched_debug
```

**Output Format**:
Look for the `slice` column (it's usually the 6th or 7th column).
```text
runnable tasks:
 S            task   PID       vruntime   eligible    deadline             slice          sum-exec ...
 R          CamHAL  1234    12345.678900      E       12345.698900 S    20.000000      500.123456 ...
```
*   **`slice`**: The current slice in milliseconds (e.g., `20.000000`).
*   **`S` flag**: If you see an 'S' right before the slice value, it means `custom_slice` is active!

### 2. The Per-Process View (`/proc/<PID>/sched`)
This gives detailed stats for a single process.

```bash
cat /proc/1234/sched | grep slice
```

**Output**:
```text
se.slice                                     :             20.000000
se.custom_slice                              :                     1
```
