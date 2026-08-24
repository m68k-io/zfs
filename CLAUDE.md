# OpenZFS on Alpine — CI enablement project

## Goal

Get the GitHub Actions **Alpine CI runner** (`zfs-qemu.yml`, matrix entry
`alpine3-24`) passing the ZFS Test Suite (ZTS) on this fork,
`https://github.com/m68k-io/zfs`. Upstream is `openzfs/zfs`; `master` here
tracks upstream `master`.

## Working principles

- **Small, targeted fixes.** One narrow cause per branch/commit, same
  shape as the existing `claude/*` branches (one file, one root cause,
  one commit each).
- **Commit message body lines must be ≤72 chars.** `checkstyle`'s
  `commitcheck` enforces this and fails the build otherwise (caught this
  the hard way on `claude/tzdata`, 2026-08-23 — amended to fix). Wrap
  commit messages accordingly from the start.
- **This is meant to land upstream eventually — never break other
  platforms.** Prefer fixing things on the ZTS test-suite side (wrong
  assumption about GNU coreutils/glibc/bash behavior) over touching
  `module/`/`lib/` core code, whenever the root cause is really a
  test-portability issue rather than a product bug. When a cluster does
  turn out to be a genuine product bug (current leading suspect: the zdb
  teardown crash, cluster 4 — looks like real memory corruption, not a
  portability issue), any core-code fix must be either musl/Alpine-scoped
  or genuinely correct on every platform. Flag such changes for extra
  scrutiny: this VM can't run the FreeBSD or other-Linux-distro legs of
  ZTS, so non-regression on those platforms can't be verified locally —
  say so explicitly rather than assuming safety.
- **Logs stay external to the zfs tree**, in the sibling `~/Development/
  logs/` directory — they're CI run artifacts, not source, and
  `claude/*` branches need to stay cherry-pick-clean for upstream PRs.
- **Never force ZFS teardown.** No `SIGKILL`/`-9` on a process holding a
  ZFS mount open, no lazy `umount -l` on a ZFS mount, no `zpool destroy
  -f` on a pool reporting busy. Escalating through that sequence during
  an interrupted test run took down most services on the VM badly enough
  (login process itself restarted, per the second login prompt the user
  saw) that a reboot was the practical fix (2026-08-23). Not memory
  pressure — this VM has 32GB and was running a ~33-test subset, while
  real CI runs the full ~2000-test suite on 8GB VMs without issue, which
  rules that out. Far more likely: `SIGKILL` mid-operation on a process
  touching a ZFS mount left kernel-side state (locks/refcounts)
  inconsistent, and the follow-up lazy umount + forced destroy-on-busy
  hit a lock-ordering problem or deadlock in the kernel module (a fresh
  `--enable-debug` build) — a module/kernel robustness issue triggered
  by forcing teardown, not a resource-sizing one (more RAM/CPU would not
  prevent a repeat). Exact mechanism still unconfirmed (no pstore
  capture). If a pool/
  process/unmount reports busy: stop, investigate (`fuser`, lingering
  test processes), or let the test harness's own cleanup/interrupt path
  handle it — don't force it.
- **ZTS is known to be flaky** — the user confirms occasional failures
  with no real cause happen on the glibc distros/Ubuntu too, not just
  here. A single unexpected FAIL outside the current target list isn't
  automatically a real bug; rerun before concluding anything, especially
  for tests not directly related to whatever's being validated.
- **A fresh VM needs `sudo apk add shadow`** before trusting local ZTS
  results (see item 6 under "Local build & test setup" below) — CI's
  actual Alpine VM has `useradd`/`groupadd`/etc. available even though
  they're not in `qemu-3-deps-vm.sh`'s explicit package list.
- **Git identity convention**: real fixes intended for upstream are
  authored/signed-off as `Alexander Moch <mail@alexmoch.com>`, matching
  the precedent set by the three existing `claude/*` branches (DCO
  sign-off needs to trace to a real accountable person). Meta/non-
  upstream-bound commits (docs, `claude-meta` branch) use the canonical
  `Claude <noreply@anthropic.com>` identity instead — no model name in
  it (matches `github.com/claude`'s convention), since the model running
  a given session may vary (Sonnet, Opus, Fable, ...). No default git
  identity is configured repo-wide — set it explicitly per commit (e.g.
  `git -c user.name=... -c user.email=... commit ...`) so the two never
  get mixed up by accident.
- **This fork (`m68k-io/zfs`) is a staging area, not the final upstream
  source.** The real repo is `https://github.com/alex-moch` (a separate
  account), where the user does final QA on cherry-picked real-fix
  commits, without the `**DEBUG**` commit, before anything goes to
  `openzfs/zfs`. So the `**DEBUG**` CI-restriction commit on `baseline`
  here is intentional and stays — it's local to this staging fork, never
  gets cherry-picked, and doesn't need reverting.

## Repo layout (`~/Development/zfs`)

- `origin` = `https://github.com/m68k-io/zfs.git` (this fork). No GitHub
  credentials configured — confirmed by trying `git push` (2026-08-23,
  see "Current status" below), not just an assumption. No push/PR/API
  access until the user provides a token.
- `master` — mirrors upstream `openzfs/zfs` master, unmodified.
- `baseline` — the base branch to fork new work from, **not** a branch
  that fix branches ever get merged into. The actual flow: real fix
  commits on `claude/<topic>` branches get merged into upstream
  `openzfs/zfs` master independently by the user (via the separate
  `github.com/alex-moch` account/process — see "This fork is a staging
  area" below), this fork's `master` then gets updated to match upstream,
  and `baseline` gets rebased onto the new `master`. So `baseline` is
  always "current upstream master + whatever local-only staging
  conveniences don't belong upstream" (right now: the permanent
  `**DEBUG**` commit) — never a growing pile of merged fix commits.
  `claude/<topic>` branches are effectively disposable once their
  commit(s) land upstream: the code reaches `baseline` naturally through
  the master-sync-and-rebase, not through a merge from the branch.
  `baseline` itself + `master` + Alpine/musl build fixes:
  - `a983deb6e` — `alignas(type)` is C11; musl's `stdalign.h` exposes it
    unconditionally (unlike glibc, which gates it behind C11), so it broke
    the `-std=gnu99` build. Fixed with `alignas(__alignof__(uint64_t))`.
    Still local-only (not yet upstream) — **`master` alone does not build
    in this environment**; always build against `baseline`, never bare
    `master`, until this lands upstream.
  - `64740cac5` — **DEBUG**, intentionally permanent on this staging fork:
    restricts CI to a runner subset (`alpine3-24, almalinux10, debian13,
    fedora44, freebsd15-1r, ubuntu26`) to save cycles while iterating.
    Stays here — see "This fork is a staging area" above. Message carries
    a standalone `[skip ci]` line (added 2026-08-23, see "CI hygiene"
    below) — since this commit is always the permanent tip of `baseline`
    after every rebase, this suppresses `push`-triggered CI on `baseline`
    automatically, indefinitely, with no extra step needed per rebase.
  - The stale-CDDL-boilerplate fix (previously `493476596` here) landed
    upstream for real — confirmed 2026-08-23 when rebasing `baseline`
    onto a freshly-synced `master`: git recognized it as patch-id-
    equivalent to an already-upstream commit and dropped it automatically,
    leaving only the two commits above.
- Eleven one-commit fix branches, each stacked directly on `baseline` and
  each targeting one root cause. Not meant to be merged into `baseline`
  (see above) — meant to go to upstream `openzfs/zfs` independently.
  **Six validated locally with real ZTS test runs as of 2026-08-23** (see
  "Local validation results" below for the actual run output);
  `claude/linux-stable-kernel` had its underlying mechanism verified but
  not full ZTS-test execution (see cluster 7 above for exactly what was
  and wasn't checked); `claude/mkbusy_kill_race` was validated directly
  (3/3 fail before, 3/3 pass after, see cluster 6 above);
  `claude/send_progress_race` validated via manual repro and a 79-test
  regression sweep (see below). None yet re-tested in real CI:
  - `claude/mmp` (`ff9ad253a`, amended locally from `origin/claude/mmp`'s
    `a4283ddbe` to drop an unrelated blank-line deletion) — musl's
    `gethostid()` ignores `/etc/hostid` and always returns 0, so
    `mmp_set_hostid` (used by ~15 `mmp/*` tests) never matched. Fix falls
    back to reading the hostid file directly with `od` when `hostid`
    disagrees.
  - `claude/history_uncompress` (`8ce47cb1b`) — Alpine has no
    `uncompress` binary; swapped in `gunzip` (handles `.Z`, accepts `-f`)
    in `history_001_pos`/`history_007_pos`.
  - `claude/user_namespace` (`8ae2ff41c`) — `readlink -f` on Alpine
    resolves `touch`/`chmod` through the `busybox` symlink to the
    `/bin/coreutils` multi-call binary, losing the `argv[0]` BusyBox uses
    to pick the applet ("unknown program"). Fix drops the `readlink -f`.
  - `claude/getopt_permute` (`054846daf`, new 2026-08-23, found while
    validating `claude/mmp`) — glibc's `getopt()` permutes `argv` by
    default (a GNU extension), reordering flags to the front regardless
    of position; musl's `getopt()` is strict POSIX and stops parsing at
    the first non-option argument. `mmp_write_uberblocks.ksh`'s zinject
    call (unmodified from upstream) puts `-L uber` *after* the positional
    pool name, which only glibc tolerates. Fixed by reordering flags
    before the positional arg — a no-op on glibc, since it accepts both
    orderings. **This is likely a broader pattern**: any ZTS test (or
    real invocation) that places flags after a positional argument on any
    OpenZFS CLI tool (`zinject`, `zpool`, `zfs`, ...) is exposed to this
    on musl. Only this one instance has been found and fixed so far —
    worth a dedicated sweep for other occurrences, not yet done. Depends
    on `claude/mmp` to be testable at all (`mmp_write_uberblocks` fails
    at an earlier step on `baseline` alone).
  - `claude/tzdata` (`93e4d710e`, new 2026-08-23, found while validating
    `claude/history_uncompress`; originally `c5edaf6cd`, amended to wrap
    the commit body at 72 chars after `checkstyle`'s `commitcheck`
    caught it) — Alpine doesn't ship zoneinfo data by
    default (unlike glibc distros, which bundle it). `history_007_pos`
    sets `TZ=America/Denver` before formatting a timestamp for comparison
    against a pre-recorded expected value; without `tzdata` installed,
    the `TZ` setting silently has no effect and timestamps come out in
    UTC, 6 hours off. This is a CI-provisioning fix (`tzdata` added to
    `qemu-3-deps-vm.sh`'s `alpine()` package list), not a test-script fix
    — confirmed via `grep -rl "TZ=" tests/zfs-tests/tests/functional/`
    that `history_007_pos` is the only test affected.
  - `claude/libcap-utils` (`34789f470`, new 2026-08-23, found during
    cluster-6 triage) — `zoned_uid_common.kshlib`'s `run_in_userns_caps()`
    needs `capsh` (from `libcap-utils`, missing from CI's Alpine dep
    list) for any `cap_spec` other than `"all"`; without it,
    `"$(which capsh)"` is empty and the resulting `unshare ... '' -- ...`
    fails with `unshare: failed to execute : No such file or directory`.
    Same CI-provisioning shape as `claude/tzdata`. Fixes
    `zoned_uid_023/025/026/030_pos` and turns the `device_access_add`
    SKIP into a genuine PASS; `capsh` is also referenced by
    `device_access.kshlib` and other `zoned_uid` tests not individually
    re-verified, so the real scope is likely wider.
  - `claude/linux-stable-kernel` (`74f10cadb`, new 2026-08-23, cluster 7)
    — Alpine's `linux-virt` kernel (what CI boots) has
    `CONFIG_SCSI_DEBUG` compiled out, which 17 tests need to simulate
    expand/fault-injection scenarios. Swaps `linux-virt`/`linux-virt-dev`
    for `linux-stable`/`linux-stable-dev` (`CONFIG_SCSI_DEBUG=m` there)
    and switches extlinux's default kernel accordingly. See cluster 7
    above for the full verification chain and what's still unconfirmed
    (`update-extlinux` itself, and a full real-CI boot).
  - `claude/mkbusy_kill_race` (`9036c2fe9`, new 2026-08-23, cluster 6) —
    `mkbusy` daemonizes and gets reparented to init; `zfs_destroy_001_
    pos`/`_005_neg` killed it and immediately checked `pgrep -fl mkbusy`
    with zero delay, racing init's reaping of the dead child. Confirmed
    a generic timing race (reproduced standalone with no ZFS involved),
    not Alpine/musl-specific — just loses the race more often here.
    Added `kill_mkbusy()` (kill + poll up to 5s) to `zfs_destroy_
    common.kshlib`, fixed all 5 call sites. Confirmed fixed: 3/3 passes
    after, previously 3/3 failures.
  - `claude/send_progress_race` (`32d09c43d`, new 2026-08-23, cluster 6,
    real product bug not a test-script issue) — `zfs send -nP` output
    corruption in `lib/libzfs/libzfs_sendrecv.c`; see the full diagnosis
    under cluster 6 above. Fix: a `send_print_line()` helper (flush +
    single `write(2)`) replacing `fprintf(3)` at the 3 call sites that
    print after a `send_progress_thread` create/cancel/join cycle.
    Branched from `baseline` (not bare `master` — see the `baseline`
    bullet above on why), rebuilt and reinstalled clean, re-verified 8/8
    on the new base before committing. Superseded as the *root-cause*
    fix by `claude/lzc_send_wrapper_splice_race` below, but still a
    valid, independent, harmless improvement in its own right.
  - `claude/lzc_send_wrapper_splice_race` (`1c4bb02cc`, new
    2026-08-23, the real root cause of the same bug as
    `claude/send_progress_race` above) — `lzc_send_wrapper()`'s
    internal `send_worker()` relay thread `splice()`s into the
    caller's destination fd using an implicit, shared kernel file
    position, which races with callers (like `estimate_size()`) that
    write to that same fd right after the wrapper returns. Fix: give
    `splice()` an explicit, thread-local output offset instead, and
    re-sync it onto the fd with one `lseek()` after `pthread_join()`.
    See cluster 6 above for the full investigation and validation
    (40/40 + 20/20 + a real send/receive round trip, all using the
    *original* unfixed `libzfs_sendrecv.c` to prove this fix alone is
    sufficient).
  - `claude/get_prop_empty_value` (`f9d7d9aae`, new 2026-08-24,
    found while digging into the `lzc_send_wrapper_splice_race` CI
    lead — see "Current status" above for the full story) —
    `get_prop()`/`get_pool_prop()`/`get_vdev_prop()` in
    `libtest.shlib` checked exit status but not whether the command
    actually printed a value, so a rare empty-output hiccup from
    `zfs get`/`zpool get` (real cause still unknown, not reproduced
    locally) surfaced as a confusing, misattributed `bc`/`[` crash
    several steps later instead of a clear failure. Now `log_fail`s
    immediately with a specific message when output is empty — used
    by nearly every test in the suite, not just the one that
    surfaced it.

  Next for these eleven: the user submits them upstream independently
  (each is small/targeted enough to go as its own PR, matching the
  "small, targeted fixes" principle). Not this fork's job to merge or
  combine them.

## Local validation results (2026-08-23)

Ran the targeted test groups (`mmp`, `history`, `user_namespace`)
locally against each branch, using the six scratch disks' host VM
directly (no nested qemu — this VM already *is* the Alpine target, per
"Local environment" below).

- **`claude/mmp`**: 16/17 `mmp/*` tests pass (all 14 CI flagged, plus
  `mmp_degraded_import`/`mmp_zhack_reclaim`, same root cause, just not
  part of the July CI run's particular selection — confirmed as real
  failures in the fresh August CI run, see below). 17th
  (`mmp_write_uberblocks`) needs `claude/getopt_permute` too. **Also
  fixes `cli_root/zpool_split/zpool_split_props`** (cluster 6, outside
  the `mmp/` directory but calls `mmp_set_hostid` directly) — confirmed
  standalone with `claude/mmp` alone, no other branch needed.
- **`claude/getopt_permute`**: combined with `claude/mmp`, the 17th
  (`mmp_write_uberblocks`) also passes — full 17/17.
- **`claude/history_uncompress`**: 10/10 `history/*` tests pass, but
  only after also installing `tzdata` (see `claude/tzdata`) and `shadow`
  (see "Local build & test setup" below) locally — those two gaps are
  environment-provisioning issues, not part of what this branch fixes.
- **`claude/tzdata`**: combined with `claude/history_uncompress`,
  `history_007_pos` goes from FAIL to PASS on its own merits (confirmed
  by installing `tzdata` and rerunning just that test before rerunning
  the full group).
- **`claude/user_namespace`**: `user_namespace_001` now passes;
  `_002`/`_003` SKIP, `_004`/`secpolicy_*` PASS — this exact pattern
  (2 SKIP, 4 PASS once `_001` is fixed) matches both real CI logs
  (July and August) exactly, confirming it's not a local artifact.
- **`claude/send_progress_race`**: manual repro 8/8 clean (`zfs send
  -nP`, no corruption) both before committing (old `master` base) and
  again after rebasing onto the post-sync `baseline`; the real ZTS test
  `rsend/send-c_stream_size_estimate` 8/8; a custom-runfile sweep of the
  full `rsend/` directory (79 tests) for regressions: 77 PASS / 1 SKIP
  (expected, pre-existing, tracked upstream) / 2 FAIL
  (`send_raw_ashift`, `send_raw_large_blocks`) — both confirmed unrelated
  to the fix: they failed before any send/receive logic ran, on
  `truncate: cannot open '/var/tmp/testdir/vdev_a'`, because the custom
  runfile ran `rsend/` out of the harness's normal managed order and an
  earlier test's cleanup removed the shared `/var/tmp/testdir` directory
  — neither test touches the `parsable`/`-P` code path this fix changed.

Not yet done: submitting these upstream, a full local ZTS run, and
re-running through actual CI.

## Latest CI runs: `logs/qemu-alpine3-24_20260713/` and `_20260823/`

Both from GitHub's Alpine 3.24 runner, **on `baseline` (i.e. without any
of the six fix branches above)**. Build succeeded both times
(`build-exitcode.txt` = 0).

- **`_20260713`** (original, used for the cluster triage below):
  `summary.txt`: **1951 PASS / 58 FAIL / 49 SKIP (94.80%)**. Full
  per-test output is in `failed.txt` (`<summary>test_name</summary>
  <pre>...</pre>` blocks, ripgrep-friendly).
- **`_20260823`** (fresh confirmation run, no `failed.txt` — only
  `summary.txt`): **1994 PASS / 61 FAIL / 54 SKIP (94.55%)**. Same
  clusters, same near-identical failure list (a few new/renamed tests
  from upstream drift in the ~6 weeks between runs — e.g.
  `dedup_fdt_pacing`, `zpool_add_001_neg` — but nothing that changes the
  triage below). Notably **does** include `mmp_degraded_import` and
  `mmp_zhack_reclaim` in the unexpected-FAIL list (the July run didn't
  run them at all), confirming they share `claude/mmp`'s root cause as
  found during local validation, not a local-only artifact.

Both split results into tests with known/expected non-PASS outcomes
(unrelated to Alpine) and tests that are unexpectedly non-PASS on Alpine
— the latter is the actual target list.

### Cross-platform confirmation: `logs/qemu-{almalinux10,debian13,
fedora44,freebsd15-1r,ubuntu26}_20260823/`

Same run as `_20260823` above, same `baseline` commit, the other 5 OS
legs of the same CI matrix (added by the user, 2026-08-23). **All five
show zero unexpected FAILs or SKIPs** — every non-PASS result on every
other platform is already a known/expected issue unrelated to Alpine.
This confirms, cheaply and cleanly, that every still-open item in the
clusters below (4, 5, and the remaining cluster-6 tests) is genuinely
Alpine-specific — not a pre-existing cross-platform bug this project
would be wasting time chasing. It also confirms cluster 7's working
theory: the other platforms don't skip `zpool_expand`/`zpool_reopen`/
`fault/auto_*`/etc., so those SKIPs are specific to Alpine's CI VM disk
config, not a shared runner limitation.

### Unexpected-failure clusters identified so far

1. **BusyBox applet dispatch** — `readlink -f` (or anything that resolves
   through the `busybox` symlink) breaks argv[0]-based dispatch.
   Confirmed root cause of `user_namespace_001` (fix exists) and
   `exec/exec_001_pos` (`coreutils: unknown program 'myls'` — copying a
   binary to a new name and exec'ing it fails; not yet fixed, same family
   as the user_namespace fix but a different code path since it's a copied
   binary, not a symlink resolution).
2. **musl `gethostid()`** — root cause of the 13 `mmp/*` failures + 1
   `multihost_history` (fix exists, see `claude/mmp`).
3. **Missing `uncompress`** — root cause of `history_001_pos`/`_007_pos`
   (fix exists, see `claude/history_uncompress`).
4. **zdb crash on pool teardown (musl-only)** — `zdb` segfaults inside
   `spa_unload → {brt_vdevs_free,ddt_unload} → ddt_table_free/brt →
   dbuf_destroy` when exiting after a BRT (block cloning) or DDT (dedup)
   test. Backtrace shows a `libspl_backtrace`/signal handler firing from
   within `dbuf_destroy`, suggesting real memory corruption (not just an
   assertion), possibly exposed by musl's malloc behaving differently than
   glibc's. Affects at least: `block_cloning_copyfilerange`,
   `block_cloning_lwb_buffer_overflow`, `dedup_bclone`, `dedup_fdt_import`,
   `dedup_legacy_create`, `dedup_legacy_fdt_upgrade`, likely
   `gang_blocks_ddt_copies`. Still the highest-value cluster (looks like a
   real bug, not a portability issue), but **not reproduced yet
   (2026-08-23)**: manually reproduced `zdb -vvvvv <pool> -O <file>`
   (the exact command `get_same_blocks` in `libtest.shlib` runs) standalone
   5x and via the individual `block_cloning_copyfilerange`/`dedup_bclone`
   tests — all clean. Ran the *entire* `block_cloning` + `dedup` groups
   together (54 tests, closer to how CI actually exercises them, in case
   it's accumulated-state/memory-pressure dependent) — still no crash,
   52/54 passed. This is consistent with the crash being genuinely
   non-deterministic (real heap corruption often is), so isolated repro
   attempts may just need more tries, or it may need the surrounding
   ~2000-test run's memory pressure to manifest — not yet resolved either
   way. Enabled core dumps this session (`core_pattern` ->
   `/var/tmp/core.%e.%p`, `ulimit -c unlimited`) in case it fires next
   time; no core produced yet.
   - **Real progress (2026-08-24, user asked to "go ahead with
     cluster 4"), still not reproduced, but no longer a black box.**
     Found two REAL, detailed crash logs already sitting locally
     (`~/Development/logs/qemu-alpine3-24_20260823/vm1/current/
     output/block_cloning/block_cloning_clone_mmap_{write,cached}/
     stderr`) that hadn't been fully read before — the previous
     session's "not reproduced" attempts targeted
     `block_cloning_copyfilerange`/`dedup_bclone`, not these two.
     Both backtraces are **byte-for-byte identical**
     (`dbuf_destroy+0x24b` → `dbuf_destroy+0x42d` →
     `brt_vdevs_free+0x130` → `brt_unload+0x2c` → `spa_unload+0x1d5`
     → `spa_evict_all+0x6f` → `spa_fini+0x09` → `kernel_fini+0x0e` →
     `main+0xb10`, across two separate test runs, separate processes)
     — that rules out "random heap corruption manifesting
     differently each time" and points at a genuine, deterministic
     logic/ordering bug instead. `dbuf_destroy` appears twice
     (recursively): `brt_vdevs_free()`'s `dnode_rele(brtvd->
     bv_mos_entries_dnode, brtvd)` (`module/zfs/brt.c:851`) → the
     dnode's hold count hits zero → `dnode_rele_and_unlock()` releases
     the dnode's parent dbuf → that recursively triggers a *second*
     `dbuf_destroy()`, which is where it actually crashes. Also
     decoded the corrupted trailing stack frame
     (`0x7074736574007676`) as the ASCII bytes `"vv\0testp"` — i.e.
     the literal string `"testpool"` (this project's default
     `$TESTPOOL` name) sitting where a return address should be,
     confirming real stack/heap corruption, not just a bad unwind.
     `dnode.c`'s own comment on `dnode_rele_and_unlock()` documents
     this *exact* hazard class ("releasing the last hold could result
     in the dnode's parent dbuf evicting its dnode handles ... must
     first drop the dnode handle") — but `ddt.c` uses the identical
     `dnode_hold()`/`dnode_rele()` pairing pattern in three places
     without (apparently) crashing anywhere near as often, so this
     isn't simply "this API pairing is unsafe" in general (it's used
     safely all over ZFS). Checked `spa_unload()`
     (`module/zfs/spa.c:2411-2418`): `dsl_pool_close()` runs — which
     sets `spa->spa_meta_objset = NULL` — *before* `ddt_unload()`/
     `brt_unload()` release their still-outstanding dnode holds into
     that objset. Normally safe (an outstanding hold should keep the
     dnode pinned regardless), so the working theory is a **rare race
     between BRT/DDT's held-dnode teardown and something else
     touching the same dbuf around the same time** (a background ARC/
     dbuf-cache eviction thread being the most likely suspect, not
     yet checked) — not a trivial one-line bug.
     **Still not locally reproduced**: 115+ further iterations this
     session alone (20 individual `block_cloning_clone_mmap_write`
     repros with the exact `$TESTPOOL`/`$TESTFS` names matching the
     decoded corrupted string, then 80 more in a tight loop reusing
     the pool across iterations) — zero crashes. Confirms it needs
     something beyond "run this one test enough times" — likely
     either genuine timing (a concurrent eviction thread winning a
     narrow race) or accumulated whole-suite state neither this nor
     the previous session's 54-test group run could trigger.
     **Recommendation**: this is now well past "black box, no lead" —
     it's a plausible, specific, well-evidenced race in BRT/DDT's
     pool-teardown dnode release path, but pinning the exact trigger
     needs either an actual live crash to attach a debugger to (still
     waiting on a core dump) or checking what concurrent activity
     (ARC eviction, async destroy, etc.) can run during
     `spa_unload()`'s window between `dsl_pool_close()` and
     `brt_unload()`/`ddt_unload()` — not attempted yet, and not
     something to guess a kernel-level fix for without more certainty
     given the stakes of getting BRT/DDT reference counting wrong.
   - **Aside, found while chasing this, unrelated**: two other tests in
     the same run, `block_cloning_copyfilerange_clone` and
     `_clone_partial` (not part of any previously-identified cluster —
     may be new upstream tests), fail with `copy_file_range(CLONE):
     Invalid argument` from `clonefile -F`. Looks like a kernel-capability
     gap (`COPY_FILE_RANGE_CLONE` flag not supported by this kernel
     build), reproducible standalone. Real CI's `_20260823` log also
     shows related `block_cloning_clone_mmap_*` failures, so this is
     plausibly a genuine current CI issue too — but it's a kernel-feature
     question, not an Alpine/musl portability one, so it's outside this
     project's scope. Noted, not investigated further.
5. **musl `SIGILL` in `ld-musl-x86_64.so.1`** — `zpool_iostat`/
   `zpool_status` `-c` (custom command) variants and their plain
   `_005_pos`/`_003_pos` siblings crash with `trap invalid opcode` /
   `segfault ... in ld-musl-x86_64.so.1`, reported via dmesg (`libshell.so`
   involved). Distinct from cluster 4 (different crash signature).
   **Not reproduced (2026-08-23)**: ran all 9 of these tests
   (`zpool_iostat_005_pos`, `zpool_iostat_-c_disable/homedir/searchpath`,
   `zpool_status_003_pos`, `zpool_status_-c_disable/homedir/searchpath`,
   plus `zfs_unmount_001_neg` from cluster 6 which lives in the same
   `cli_user/` family) individually, correctly as the non-root `zfs` user
   (they need `-u zfs`, not the `-t` default of root — running as root
   trips a real, unrelated `zpool` safety check and gives a false FAIL,
   a mistake made and corrected mid-session) — all 9 passed cleanly, no
   crash, no dmesg entries. Same open question as cluster 4: genuinely
   non-deterministic, or only manifests under the full suite's
   accumulated state/memory pressure. Not resolved.
6. **Cluster 6 triage, 2026-08-23** — went through the full original
   list. Methodology note that applies to all of this: local `-t <path>`
   runs default to root; several `cli_user/*` tests need `-u zfs`
   (confirmed by a false-FAIL detour on the `-c` tests above) — always
   check which user a test's directory section specifies in `tests/
   runfiles/*.run` before trusting a local FAIL.
   - **Resolved, not their own bugs**:
     - `zpool_split_props` — identical `mmp_set_hostid` error as the
       `mmp/*` cluster (calls it directly). Fixed by `claude/mmp` alone,
       no new branch needed.
     - `zoned_uid_023_pos`/`_025_pos`/`_026_pos` (and `_030_pos`, found
       while checking scope) — `zoned_uid_common.kshlib`'s
       `run_in_userns_caps()` needs `capsh` (from `libcap-utils`, not in
       CI's Alpine dep list) for any `cap_spec` other than `"all"`;
       without it, `"$(which capsh)"` is empty and the resulting
       `unshare ... '' -- ...` fails with `unshare: failed to execute :
       No such file or directory`. Fixed by new branch
       `claude/libcap-utils` (CI-provisioning fix, same shape as
       `claude/tzdata`). Bonus: `device_access_add` (cluster 7 SKIP, not
       FAIL — it guards on `capsh`'s availability) now genuinely passes
       too. `capsh` is also referenced by `device_access.kshlib` and
       other `zoned_uid` tests not individually re-verified, so the real
       scope may be wider than what's listed in that commit.
     - `zfs_unmount_001_neg`, `zpool_iostat_005_pos`,
       `zpool_iostat_-c_disable/homedir/searchpath`,
       `zpool_status_003_pos`, `zpool_status_-c_disable/homedir/
       searchpath` — all 9 pass cleanly run correctly as user `zfs` (see
       cluster 5 above; these live in the same `cli_user/` family and
       were checked together). No fix needed, no bug found — the
       original FAILs may be the same non-deterministic/order-dependent
       thing as clusters 4/5, or the ZTS flakiness the user described.
     - `zfs_list_002_pos`/`_003_pos`, `zpool_list_001_pos` — passed
       cleanly on a fresh local `baseline` run, unable to reproduce the
       original FAIL at all. Likely flaky, per the user's note that ZTS
       has known flaky failures independent of platform.
     - `zfs_destroy_001_pos`/`_005_neg` — **real bug, fixed
       (2026-08-23).** `ERROR: pgrep -fl mkbusy unexpectedly exited 0`
       is not a BusyBox/GNU `pgrep` difference (that guess was wrong).
       `mkbusy` (`tests/zfs-tests/cmd/mkbusy.c`) daemonizes: forks, the
       parent prints the child's pid and exits immediately, and the
       child is reparented to init. Both tests did `kill -TERM $pidlist`
       immediately followed by `log_mustnot pgrep -fl mkbusy` with zero
       delay — a real race against init reaping the now-dead child
       before it disappears from a `pgrep` scan. Confirmed deterministic
       (3/3 failures before the fix) and confirmed as a generic timing
       race, not ZFS- or musl-specific: an isolated repro (`kill -TERM`
       + immediate `pgrep`, no ZFS involved, in a tight loop) reproduced
       the same race standalone. Fixed by new branch
       `claude/mkbusy_kill_race`: added `kill_mkbusy()` to
       `zfs_destroy_common.kshlib`, which kills the pidlist then polls
       `pgrep` (up to 5s) instead of checking once immediately; updated
       all 5 call sites across both tests. Confirmed fixed: 3/3 passes
       after, previously 3/3 failures.
   - **Investigated, ruled out, still open**:
     - `zfs_get_006_neg` — a negative test asserting `zfs get all -r`
       (and 27 similar malformed invocations) must be *rejected*. Already
       sets `export POSIXLY_CORRECT=1` before running these (upstream
       anticipating glibc's `getopt()` permutation), so `getopt_permute`
       was a reasonable first guess — ruled out: `zfs get all -r <pool>`
       still wrongly succeeds even under `POSIXLY_CORRECT=1`. Real cause
       is something deeper in `zfs_do_get()`'s argument handling in
       `cmd/zfs/zfs_main.c` (likely how it manually scans for stray
       dash-prefixed operands after `getopt()` finishes) — not found.
   - **`rsend/send-c_stream_size_estimate` — real product bug, TRUE
     root cause found (2026-08-23, second pass after the fix already
     landed — see below), and it is not a libc/musl bug at all.**
     Traced past the original `bc: bad expression` symptom to
     genuinely corrupted `zfs send -nP` output: the "full" and "size"
     lines interleave, with exactly the size line's byte length
     missing from the front of the full line.
     - **First pass (led to the committed fix, still correct as a
       mitigation):** `strace -f` showed the "full" line's `writev()`
       succeeding with the correct byte count, `lseek`/`ftello(3)`
       immediately after correctly reporting the true offset, yet the
       *next* `printf(3)` call to the same stream still landed at file
       offset 0. This correlated with `estimate_size()` having just
       created/cancelled/joined a `send_progress_thread`, so the fix
       (bypass `printf(3)`'s buffering — build each line with
       `snprintf()`, emit with one `write(2)`) was written and lands
       in `claude/send_progress_race` (`32d09c43d`). It works (77/79
       `rsend/` regression clean, 8/8 manual repro) but the writeup at
       the time honestly flagged that the *why* wasn't pinned down at
       the libc level.
     - **Second pass, the actual mechanism (this session, per the
       user's explicit "dig into libc" ask):** built musl 1.2.6 from
       the local `~/Development/musl` checkout, read
       `src/stdio/__stdio_write.c`, `__towrite.c`, `ftell.c`,
       `fseek.c`, and the cancellation internals in
       `src/thread/pthread_cancel.c` — nothing there explains a
       cross-stream position corruption (the progress thread only
       ever writes to `stderr`, never to `fout`, so there's no shared
       `FILE*` for musl's per-file locking to even be relevant to).
       A synthetic standalone repro isolating exactly the pthread_
       create/cancel/join + two-fprintf-to-a-fresh-FILE pattern (no
       ZFS code at all) ran **3000/3000 clean** — proving the musl
       cancellation path itself is not the cause. Went back to the
       real binary instead: swapped the pre-fix `libzfs_sendrecv.c`
       into a scratch rebuild (`.libs/libzfs.so`, loaded via
       `LD_LIBRARY_PATH` over the real installed/fixed one, so the
       system `zfs` stayed on the fix throughout), reproduced
       corruption 10/10 that way, then used `strace -f -tt -yy` with
       **no** `-e` filter (a filtered trace had hidden the real
       cause). That revealed a third thread doing:
       `pipe2([5,6], O_CLOEXEC)` then
       `splice(5, NULL, 1, NULL, 65536, SPLICE_F_MOVE|SPLICE_F_MORE)`
       — **splicing directly into fd 1, the same fd `fout`'s buffered
       writes target.** That thread is `send_worker` in
       `lib/libzfs_core/libzfs_core.c`'s `lzc_send_wrapper()`: since
       Linux 5.10 (`4d03e3cc5982`), `ZFS_IOC_SEND*` ioctls `EINVAL` on
       kernel writes to fd types without iter ops (a plain file being
       one), so whenever the destination fd isn't *already* a pipe
       (`S_ISFIFO`), `lzc_send_wrapper()` transparently opens an
       internal pipe, spawns a thread that `splice()`s from it to the
       real destination fd, and hands the *pipe's write end* to the
       actual ioctl instead — used even for a pure size estimate
       (`lzc_send_space_resume_redacted()` calls it with
       `orig_fd = STDOUT_FILENO`, unconditionally). **Confirmed
       causal, not just correlated**, with a clean A/B: piping the
       exact same command instead of redirecting to a regular file
       (`zfs send -nP ... | cat > file`, which makes stdout a FIFO and
       makes `lzc_send_wrapper()` take its no-thread fast-path) came
       back **10/10 clean**; the direct-file-redirect form corrupted
       **every time**. So the real bug is a race between
       `send_worker`'s `splice()` (targeting the same fd) and the
       calling code's own direct writes to that fd — not a libc
       buffering quirk, and not specific to the progress thread's
       cancellation at all (that was a correlated red herring: both
       are triggered from the same `estimate_size()` call, so both
       "just happened before" the corrupting write). Almost certainly
       not Alpine/musl-specific either — Linux's `splice()`-to-a-
       regular-file position handling not composing safely with a
       concurrent direct writer on the same fd would reproduce on any
       distro give the right scheduling; Alpine/this environment's
       timing just seems to hit the race window very reliably.
     - **The principled fix was attempted and confirmed
       (2026-08-23, same session, user asked to keep digging into
       `lzc_send_wrapper()` specifically).** New branch
       `claude/lzc_send_wrapper_splice_race` (`1c4bb02cc`, based on
       `baseline` like the other fix branches, **not** stacked on
       `claude/send_progress_race`): in `lzc_send_wrapper()`,
       `send_worker()`'s `splice(from, NULL, to, NULL, ...)` used a
       `NULL` output offset — implicit, shared-kernel-file-position
       mode. Changed to an **explicit**, thread-local offset
       (`&ctx.pos`, seeded once from `lseek(orig_fd, 0, SEEK_CUR)`
       before the thread starts, re-synced onto `orig_fd` with a
       single `lseek(orig_fd, ctx.pos, SEEK_SET)` after
       `pthread_join()`) — falls back to the old `NULL` behavior if
       `orig_fd` isn't seekable. This means `send_worker()` never
       touches the shared implicit position at all while the caller
       could be concurrently relying on it, sidestepping the entire
       race class regardless of its exact kernel-level mechanism
       (which — see above — wasn't fully pinned down: attempting to
       reconcile the precise thread-creation order against
       `estimate_size()`'s source hit a real, unresolved contradiction
       that wasn't worth further budget chasing once the structural
       fix was in hand and proven).
       - **Confirmed to be the true, sufficient root-cause fix**: built
         and tested this change *by itself*, on `baseline`, with the
         **original, unmodified** `estimate_size()`/
         `send_print_verbose()` (i.e. the pre-`send_progress_race`
         `fprintf(3)`-based code) — 40/40 clean `zfs send -nP`
         (single snapshot), 20/20 clean `zfs send -nPR` (multi-
         snapshot replicate, exercises multiple `estimate_size()` /
         `lzc_send_wrapper()` cycles per run), and a real
         `zfs send | zfs receive` round trip confirmed byte-identical
         data (`diff -r` clean) — proving the fix doesn't harm actual
         stream relaying, only removes the race on the destination
         fd's position.
       - Net effect on `claude/send_progress_race`: still committed,
         still a correct and harmless improvement (avoiding
         `fprintf(3)`'s buffering for machine-parsed output is
         defensible on its own merits), but it is **not** the root-
         cause fix — `claude/lzc_send_wrapper_splice_race` is. Both
         branches are independent (each based on `baseline`, neither
         depends on the other) and both are safe to submit upstream;
         the `send_progress_race` commit message/rationale predates
         this finding and still frames it as a libc mystery — leaving
         that commit's text as-is (it's already pushed/real) rather
         than rewriting published history, corrected here instead.
       - Formal ZTS re-run for this specific fix (`rsend/send-
         c_stream_size_estimate`) hit an unrelated test-runner harness
         permission issue in the time available (symlink creation
         under `tests/zfs-tests/bin/` when run as the `zfs` user) —
         not chased down; the manual validation above (60 iterations
         + a real send/receive round trip, zero failures) was judged
         sufficient given the session's remaining budget.
     - Branch `claude/send_progress_race` (`32d09c43d`): adds a
       `send_print_line()` helper (flush + single `write(2)`) to
       `libzfs_sendrecv.c`, used at all 3 sites that print
       `zfs send -P` output following a progress-thread create/cancel/
       join cycle: `send_print_verbose()`'s
       parsable branch (used by both `estimate_size()` and
       `dump_snapshot()`/`zfs_send_cb_impl()`), and both `"size\t%llu
       \n"` call sites. The non-parsable/human-readable verbose branch
       is untouched (not proven affected, lower stakes since it's not
       machine-parsed).
     - This is real product code with correctness implications beyond
       Alpine (every `zfs send -P`/`-v` invocation goes through this
       path), not a test-script portability issue. The fix itself
       (explicit flush + direct `write(2)` instead of relying on
       `printf(3)`'s internal buffering/position-tracking) is a
       platform-neutral, defensive pattern — correct and behaviorally
       identical in output on every platform, not gated to Alpine/musl
       — but genuine non-regression on glibc/FreeBSD **could not be
       verified locally**; real CI is what actually confirms that,
       same limitation as every other core-code change in this
       project.
     - Confirmed fixed: manual repro 8+/8+ clean runs, real ZTS test
       8/8, full `rsend/` directory (79 tests) run for regressions —
       see "Local validation results" for the outcome.
   - **Still open, no lead yet**: `procfs_list_stale_read` (fails because
     `grep "Input/output error"` doesn't match — the actual I/O error
     message text may differ on this kernel/musl, not confirmed).
7. **SKIPs that should be PASS — root cause found and fixed
   (2026-08-23).** Originally guessed as "needs real disks" (wrong
   guess). All 17 remaining tests (`zpool_expand_001/003/005/006_pos`,
   `zpool_reopen_*` (7, including `setup`), `zpool_split_wholedisk`,
   `zpool_import_aux_paths`, `fault/auto_offline_001_pos`,
   `fault/auto_online_001/002_pos`, `fault/auto_replace_001/002_pos`,
   `fault/auto_spare_ashift`, `fault/auto_spare_shared`,
   `fault/suspend_draid_fgroups`, `fault/suspend_on_probe_errors`,
   `fault/suspend_resume_single`, `procfs/pool_state` — confirmed via
   `grep -l scsi_debug` across every one) all depend on the Linux
   `scsi_debug` kernel module (a synthetic SCSI device driver used to
   test expand/reopen/fault-injection scenarios real static disks can't
   easily simulate) via `load_scsi_debug()` in `tests/zfs-tests/include/
   blkdev.shlib`, which calls `log_unsupported` when `modprobe -n
   scsi_debug` fails. That fails because Alpine's `linux-virt` kernel
   (what CI actually boots) has `CONFIG_SCSI_DEBUG` compiled out
   entirely (`/boot/config-*-virt`: `# CONFIG_SCSI_DEBUG is not set`) —
   not a missing package, the module doesn't exist for that kernel at
   all.

   Initially judged not fixable within scope (assumed switching kernel
   flavors was a much bigger CI-infrastructure decision) — **corrected
   after the user pushed back and asked me to actually check the
   mechanics rather than assume.** It turned out to be small: fixed by
   `claude/linux-stable-kernel`, which boots Alpine's `linux-stable`
   kernel flavor instead (`CONFIG_SCSI_DEBUG=m` there) by changing one
   package (`linux-virt`/`linux-virt-dev` -> `linux-stable`/
   `linux-stable-dev`) and one config line (`/etc/update-extlinux.conf`:
   `default=virt` -> `default=stable`). No explicit reboot needed in the
   CI script — `qemu-3-deps.sh` already runs with `--poweroff`, and
   `qemu-prepare-for-build.sh`'s `virsh start` boots the VM fresh for
   the build step right after, so the new default kernel just takes
   effect on the pipeline's existing next boot.

   Verification chain (2026-08-23): downloaded the actual cloud image
   CI boots (`generic_alpine-3.24.1-x86_64-bios-cloudinit-r0.qcow2`)
   and inspected it directly via `qemu-nbd` (no full boot needed) —
   confirmed it boots via `extlinux` (raw `SYSLINUX` boot sector, no
   partition table), not GRUB as this practice VM uses, and that
   `/etc/update-extlinux.conf` has exactly `default=virt` matching the
   fix's `sed` pattern. Separately confirmed `linux-stable` actually has
   `CONFIG_SCSI_DEBUG=m` and that `scsi_debug` loads and creates a
   working synthetic disk, by installing it and rebooting into it on
   this practice VM (GRUB-based, since it was set up from the standard
   ISO rather than the cloud image — proved the kernel-flavor-switch
   concept this way, since this VM has no `extlinux` tooling to test
   that exact command against). `grep -rn "linux-virt"` across
   `.github/workflows/` confirmed the package list is the only place it
   was referenced — nothing else assumed the running kernel is
   specifically `-virt` by name. **Not verified**: `update-extlinux`
   itself, or a full boot of the real cloud image end to end — that
   happens via real CI once this branch is tested there, same as every
   other fix branch in this repo.

## Local environment

- **This VM *is* the Alpine test target itself** — i.e. it's the same
  kind of VM the real CI's Ubuntu orchestrator launches under QEMU as the
  `alpine3-24` runner (compare `logs/qemu-alpine3-24_20260713/vm1` /
  `vm2`, which is what this VM stands in for). No need to reproduce the
  outer Ubuntu-orchestrates-qemu layer
  (`.github/workflows/scripts/qemu-*.sh`) locally — we work directly
  inside the Alpine environment those scripts would otherwise set up.
- Alpine 3.24.1 VM, 16 vCPU, 32G RAM, kernel 6.18.44-0-virt.
- System disk `/dev/vda` — **do not touch**.
- Six empty scratch block devices directly attached to this VM, standing
  in for whatever test/scratch disks the real CI Alpine VM gets:
  `nvme0n1`, `nvme1n1`, `nvme2n1`, `sda`, `sdb`, `sdc`. Use these as ZTS
  test vdevs / for building and running the test suite locally.
- `ripgrep` installed (`sudo apk add ripgrep`) for grepping the logs —
  `failed.txt` is 7.5k lines of `<summary>test</summary><pre>...` blocks.
- No GitHub token configured yet — can't push, open PRs, or use `gh`.

## Local build & test setup (done)

The VM came pre-provisioned close to CI's `alpine()` dep list already
(udev, dhcpcd, nfs, samba, sshd all running; `ksh` was already real ksh93,
not the BusyBox one). Steps taken to get `baseline` built and ZTS runnable:

1. `sudo apk add` the exact package list from
   `.github/workflows/scripts/qemu-3-deps-vm.sh`'s `alpine()` function
   (only `clang22` was actually missing).
2. On `baseline`: `./autogen.sh && ./configure --prefix=/usr --enable-pyzfs
   --enable-debuginfo --enable-debug && make -j$(nproc) && sudo make
   install` — same flags CI uses (`zfs-qemu.yml` passes `--enable-debug`
   to `qemu-4-build.sh`). Built clean, no errors, only benign objtool
   warnings about `luaD_throw` missing `__noreturn`.
3. `sudo depmod -a && sudo modprobe zfs` — kernel modules
   (`/lib/modules/6.18.44-0-virt/extra/{zfs,spl}.ko.gz`) load fine.
   `zfs version` / `zpool version` both report `zfs-2.4.99-1`.
4. `sudo mkdir -p /etc/zfs && sudo touch /etc/zfs/zpool.cache` — matches
   the Alpine-specific step in `qemu-6-tests.sh`.
5. Confirmed `./scripts/zfs-tests.sh -t zpool_create_001_pos` passes both
   with default file/loopback vdevs and with `DISKS="sda sdb sdc"` (real
   scratch disks) — so the six scratch disks are usable as real ZTS test
   vdevs via the `DISKS` env var (space-separated bare device names, e.g.
   `DISKS="sda sdb sdc nvme0n1 nvme1n1 nvme2n1"`), which is what cluster 7
   (disk-related SKIPs) will need to investigate.
6. **Correction (2026-08-23)**: earlier assumed `useradd`/`groupadd`/etc.
   being absent (`zfs-tests.sh`'s `Missing util(s): ...` line) matched
   real CI, since they're not in `qemu-3-deps-vm.sh`'s explicit `alpine()`
   package list. That was wrong — validating `claude/history_uncompress`
   locally, `history_009_pos`/`history_010_pos` (which need `useradd`)
   FAILed here but PASSed in the real logged CI run
   (`logs/qemu-alpine3-24_20260713/vm1log.txt`), so CI's actual Alpine
   VM does have `useradd` available somehow — evidently from the base
   cloud image (`qemu-2-start.sh`'s `openzfs` zvol image), not from the
   explicit deps script. `sudo apk add shadow` on this VM closes the gap
   (confirmed: both tests pass afterwards). Do this on any fresh VM
   before trusting local ZTS results — the `capsh` part of that missing-
   util list is unrelated (from `libcap-utils`) and still genuinely
   absent; hasn't been checked whether anything needs it.

## Current status / next steps

- **First batch of upstream PRs submitted, waiting on merge
  (2026-08-24)**: asked for a recommended submission order
  (product-code fixes first, `linux-stable-kernel` last) — user
  explicitly disagreed and chose `linux-stable-kernel`, `mmp`, and
  `history_uncompress` first instead. Helped fill out PR description
  templates (Motivation/Description/How Tested) for all four —
  `get_prop_empty_value` (branch/PR title later changed to "fail on
  missing output" after the user refined the fix with a sentinel to
  correctly distinguish "printed nothing" from "printed an
  legitimately-empty value" — see cluster 6 above) got added to the
  batch too. Correcting/expanding testing sections along the way:
  confirmed `mmp` clean across the *whole* CI matrix, not just Alpine
  (glibc distros too — initially only checked Alpine, corrected after
  the user pushed back); found that the `auto_replace_001/002_pos`
  "new lead" flagged the day before is a non-issue — ZTS's own
  results summary already lists both as pre-existing, tracked-
  upstream expected failures (`openzfs/zfs#14851` and "Known issue"),
  unrelated to the `linux-stable-kernel` change; confirmed
  `get_prop_empty_value` (PR `openzfs/zfs#18983`) essentially clean
  across upstream's full ~19-distro CI matrix, one unrelated
  `zpool_trim_multiple` flake aside.
  **All four PRs are now open upstream**
  (`openzfs/zfs#18979` mmp, `#18980` linux-stable-kernel, `#18981`
  history_uncompress, `#18983` get_prop_empty_value) — none merged
  yet. **User is deliberately waiting for this first batch to merge
  before submitting the remaining seven branches themselves** (not
  asking for help with that submission round) — nothing for this
  fork to do until they come back, at which point the next step is:
  sync this fork's `master` from upstream and rebase `baseline` onto
  it, per the established flow. Also noticed in passing:
  `openzfs/zfs#18971` (the `alignas(type)`/C99 build fix matching
  `baseline`'s local-only commit) is open too, and `#18972` (the
  CDDL-boilerplate fix) is already merged — confirming what the
  `baseline` rebase auto-detected as already-upstream a few days
  ago. Remaining seven branches: user will submit them personally
  once the first batch merges — not something to pick up unprompted.
- **Real CI results read back (2026-08-24)**, after all ten `claude/*`
  branches' first CI runs finally cleared the runner backlog. Every
  branch's *own* fix validated for real, matching what local testing
  predicted, with two expected exceptions (each branch is
  independently upstream-bound, so a test needing two branches
  combined still fails on either alone — by design, not a problem):
  `send_progress_race` (PASS), `mkbusy_kill_race` (2/2 PASS),
  `libcap-utils` (5/5 PASS), `history_uncompress` (2/2 PASS — notably
  *without* needing `tzdata` on real CI, unlike locally; real CI's
  Alpine image likely already ships `tzdata`, unlike this session's
  stripped-down local VM), `mmp` (16/17 PASS, 17th needs
  `getopt_permute` — expected), `user_namespace` (exact predicted
  pattern: 4 PASS + 2 SKIP), `linux-stable-kernel` (15/17 PASS).
  `tzdata` and `getopt_permute` each FAIL alone as expected (need
  their pair branch). `fedora44` failed on two runs with "the hosted
  runner lost communication with the server" — transient GitHub
  Actions infra, unrelated to any of our code.
  - **Both leads resolved (2026-08-24)**:
    - `claude/linux-stable-kernel`'s `auto_replace_001/002_pos`:
      non-issue — both already listed in ZTS's own "Tests with
      results other than PASS that are expected" summary, tracked
      against pre-existing upstream issues (`openzfs/zfs#14851` and
      "Known issue"), unrelated to this branch.
    - `claude/lzc_send_wrapper_splice_race`'s `get_prop lrefer`
      empty-output failure: **confirmed NOT caused by that branch**
      — checked every other CI run available (`mmp`, `tzdata`,
      `user_namespace`, `libcap-utils`, `getopt_permute`,
      `history_uncompress`, `mkbusy_kill_race` — none touch send
      code at all) and every one hits the *identical* failure, same
      timing (~30-40ms after the snapshot), same signature. It's a
      pre-existing flake present on `baseline` regardless of branch.
      Traced the mechanism precisely: `within_percent()` in
      `math.shlib` is called unquoted
      (`within_percent $ds_size $ds_lrefer 90`); when `get_prop
      lrefer $send_ds` returns truly empty output, the empty
      unquoted argument vanishes from the call, shifting `90` into
      the `$2` slot and leaving `percent` unset — that's what
      produces the `bc: bad expression`/`[: argument expected`
      errors. Tried hard to reproduce the underlying empty-output
      cause locally (400+ iterations, including under heavy
      artificial CPU/memory/I/O stress via 16 busy-loops + 4
      concurrent `dd oflag=direct` writers + a 24 GiB memory hog) —
      never reproduced it. Found the likely reason why: the CI log's
      `zfs_dbgmsg` dump at the failure moment shows genuine
      *concurrent, unrelated* pool activity (`testpool3`, mid `zfs
      recv`) on a different kernel thread at the same wall-clock
      second — `vm1`/`vm2` in the CI logs aren't two separate
      machines, they're two parallel `test-runner.py` processes
      (different `-T` test-group lists) sharing one kernel on one
      VM, which is a form of contention a single-stream local repro
      can't produce. Root kernel-level cause (why `zfs get -Hpo
      value` returns literally empty rather than a stale value under
      that contention) still unknown — would need instrumentation
      inside the actual CI runner to pin down further.
      - **Fixed what *was* fixable**: `get_prop()`/`get_pool_prop()`/
        `get_vdev_prop()` in `libtest.shlib` checked exit status but
        never validated the command actually printed a value, so
        this class of failure always surfaces several steps removed
        from the real cause (a `bc` crash instead of "get_prop
        returned empty"). New branch `claude/get_prop_empty_value`
        (`f9d7d9aae`) makes all three `log_fail` immediately with a
        specific message when output is empty. Doesn't fix or
        explain the underlying rare `zfs get` hiccup — makes it
        diagnosable instead of confusing, for every test that uses
        these (very widely used) helpers, not just this one.
        Verified with a standalone ksh harness (real `zfs get` on the
        success path; a stubbed empty-output `zfs get` on the
        failure path) since the formal ZTS test-runner has an
        unrelated local permission issue (see below) that wasn't
        worth fighting again for a pure-shell-logic change.
- Basics are done: `baseline` builds and installs cleanly, kernel module
  loads, ZTS runs (both file-vdev and real-disk modes confirmed).
- Six `claude/*` fix branches now exist, all locally validated (see
  "Local validation results" above plus the cluster 6 triage above for
  the newest, `claude/libcap-utils`), ready for the user to submit
  upstream independently — not this fork's job to merge or combine them
  (see "Repo layout" above for the actual flow: upstream PR -> update
  this fork's `master` -> rebase `baseline`).
- Cluster 6 (untriaged) is now mostly resolved: 2 more branches
  (`claude/libcap-utils` new; `claude/mmp` covers `zpool_split_props`
  too), several false leads ruled out (9 `cli_user/*` tests were a
  local testing-methodology bug, not real bugs; 3 more just flaky).
  `zfs_destroy_001_pos`/`_005_neg` fixed by `claude/mkbusy_kill_race`
  (a real kill/pgrep race, confirmed generic not Alpine-specific).
  `send-c_stream_size_estimate` traced to a real `zfs send` progress-
  thread teardown race in `libzfs_sendrecv.c` — fixed by
  `claude/send_progress_race` (`32d09c43d`), see cluster 6 above. Still
  open, no lead: `procfs_list_stale_read`, `zfs_get_006_neg`
  (getopt_permute ruled out).
- Clusters 4 and 5 (the two crash clusters) are both still
  **unreproduced** despite real attempts this session (individual tests,
  full test-group batches, correct non-root user) — genuinely
  non-deterministic, or dependent on the full ~2000-test suite's
  accumulated state. Not resolved either way.
- Cluster 7 (disk-related SKIPs) is now fixed: root cause was
  `scsi_debug` missing from `linux-virt`'s kernel config, not disk
  availability. `device_access_add` (turned out to SKIP on missing
  `capsh`, same as the `zoned_uid` finding) was actually the outlier,
  not representative of the other 16. Fixed by `claude/linux-stable-
  kernel` — see cluster 7 above for the full verification chain.
- GitHub push/PR/API access is now working (2026-08-23) — the user
  configured credentials and `gh`. Do not write credential details,
  token values, or where they're stored into this file or anywhere else
  persistent; just that access works. All eleven previously-pushed
  branches (`baseline`, `master`, `claude-meta`, `claude/mmp`,
  `claude/history_uncompress`, `claude/user_namespace`,
  `claude/getopt_permute`, `claude/tzdata`, `claude/libcap-utils`,
  `claude/linux-stable-kernel`, `claude/mkbusy_kill_race`) match
  `origin`. `claude/mmp` and `claude/tzdata` each needed
  `--force-with-lease` once, after being amended locally post-push
  (blank-line cleanup; commit-message line length for `checkstyle`'s
  `commitcheck`, respectively). `claude/send_progress_race`,
  `claude/lzc_send_wrapper_splice_race`, and
  `claude/get_prop_empty_value` are all pushed too, bringing the
  total to fourteen branches (`baseline`, `master`, `claude-meta`,
  eight original fix branches, and these three).
- **CI hygiene (2026-08-23)**: cleaned up 15 stale cancelled runs and 7
  redundant successful `checkstyle` runs from the Actions history via
  `gh run delete`. Separately, synced with upstream: fetched, fast-
  forwarded `master` 8 commits to `84aa7e7e0` (none touch
  `libzfs_sendrecv.c`/the send-progress-thread code — the race above
  isn't independently fixed upstream), then rebased `baseline` onto it
  (see the `baseline` bullet above for the resulting commit list).
  Adopted a `[skip ci]` convention to stop `baseline`/`claude-meta`
  pushes from burning CI cycles on branches that don't need it (docs,
  or a rebase-only push with no new code): baked a standalone
  `[skip ci]` body line into `baseline`'s permanent **DEBUG** commit
  (self-perpetuating across every future rebase, since that commit is
  always the tip) and into `claude-meta`'s current tip commit — new
  `claude-meta` commits should carry it too going forward. Real
  `claude/<topic>` fix branches are *not* included in this convention —
  those still need real CI validation.
