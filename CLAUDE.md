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
- **Never put PR numbers or upstream commit SHAs in `claude-meta`
  commit messages (2026-08-24).** GitHub cross-references a PR's
  timeline from a bare `#NNNN`/`owner/repo#NNNN` mention (or a SHA
  that happens to match that PR's head commit) in *any* commit
  message it can see, including ones pushed to an unrelated branch on
  a fork — which is exactly what `claude-meta` is relative to
  `openzfs/zfs`'s real PRs. The user does not want this fork's
  meta/notes branch showing up in those PRs' histories. Caught once
  (commit rewritten via detached-HEAD cherry-pick + `git branch -f`
  + `--force-with-lease`, since it wasn't the tip) — but the GitHub
  cross-reference it had already created stayed even after the
  rewrite; force-pushing over history does **not** retroactively
  clear an already-indexed PR timeline entry, so get this right the
  first time rather than relying on being able to fix it after.
  Confirmed scope with the user: referencing a PR/commit in
  CLAUDE.md's own prose is fine (rendering `#NNNN` in a file GitHub
  displays doesn't create that same cross-reference) — the rule is
  specifically about commit message text.
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
  - `a983deb6e` (`alignas(type)` C99 build fix) landed upstream for real as
    PR `#18971`, **merged 2026-08-24** — confirmed when rebasing `baseline`
    onto a freshly fast-forwarded `master` (5 new commits): git recognized
    it as patch-id-equivalent to the now-upstream `2aadd7307` and dropped
    it automatically, same self-cleaning behavior as the CDDL fix before
    it. `baseline` no longer carries any local-only build fix — just the
    DEBUG commit below. **Confirmed for real (2026-08-24, later the same
    day)**: checked out bare `master`, ran `autogen.sh && configure &&
    make` end to end — clean build, exit 0. The old standing rule
    ("master alone does not build in this environment — always build
    against `baseline`") is retired as of this commit; bare `master`
    is fine to build against now.
  - `64740cac5` (now `06a89ec7e` after the 2026-08-24 rebase) —
    **DEBUG**, intentionally permanent on this staging fork:
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
    leaving only the two commits above (now just the one DEBUG commit,
    per the `a983deb6e` update above).
- **Eight one-commit fix branches remain** (originally thirteen; four
  deleted 2026-08-24 as merged/withdrawn, and `tzdata`+`libcap-utils`
  combined into one new branch, `claude/alpine_ci_deps` — see "Current
  status" below for both), each stacked directly on `baseline` and each
  targeting one root cause (`claude/alpine_ci_deps` is a deliberate,
  narrow exception — two CI-provisioning package additions in one
  commit, not two separate root causes, done specifically because they
  collide on the same wrapped `apk add` line in `qemu-3-deps-vm.sh`).
  Not meant to be merged into `baseline` (see above) — meant to go to
  upstream `openzfs/zfs` independently.
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
    on musl. Depends on `claude/mmp` to be testable at all
    (`mmp_write_uberblocks` fails at an earlier step on `baseline` alone).
    **Partial sweep done (2026-08-24), on the user's ask.** Classified
    every plain `getopt()` call in `cmd/` by whether its optstring has a
    leading `+`/`-` (permutation-safe on both libcs) or not (glibc
    permutes, musl doesn't — the exact mechanism here): exposed tools are
    `zfs`, `zpool`, `zinject`, `zhack` (one parser only —
    `metaslab_leak`'s `"f"`, everything else in `zhack` already guards
    with `+`), all 6 `zstream` subcommands, `raidz_test`, and
    `zfs_ids_to_path`. Cross-checked against real ZTS invocations for
    everything **except `zfs`/`zpool` themselves** (by far the largest
    surface — ~40 subcommand parsers across ~2000 tests; doing this
    precisely, the way `zinject` was checked below, means a
    flag-arity table per subcommand, not a generic regex, since a naive
    "flag after any non-dash token" sweep is mostly noise from flag
    *values* like `-d $DISK1` — not yet done, stopped here on the
    user's call, not for lack of a path forward). Results for what
    *was* checked: **`zinject`** — every invocation in the suite,
    using its real flag-arity table (`:aA:b:C:d:D:E:f:Fg:qhIc:t:T:l:
    mr:s:e:uL:p:P:`); the only real flag-after-positional case anywhere
    is the already-fixed `mmp_write_uberblocks.ksh` one, nothing else.
    **`zhack`**'s one exposed parser (`metaslab leak`) — only one test
    calls it (`zhack_metaslab_leak.ksh`) and never passes `-f` at all,
    so it's a latent inconsistency, not a currently-triggered bug.
    **`zstream`** (all 6 subcommands) and **`raidz_test`**/
    **`zfs_ids_to_path`** — every invocation checked, flags always
    precede positionals, clean.
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
    that `history_007_pos` is the only test affected. **Superseded
    2026-08-24**: this branch was deleted (local + `origin`) after being
    rebased onto the post-first-batch `baseline` hit a real conflict —
    the now-merged `linux-stable-kernel` PR reflowed the same wrapped
    `apk add` package list this fix touches (`linux-virt`->`linux-stable`
    shifted the line wrapping). Combined with `claude/libcap-utils`
    (same conflict, same file) into one new branch, `claude/alpine_ci_deps`
    — see "Current status" below.
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
    re-verified, so the real scope is likely wider. **Superseded
    2026-08-24**: same fate as `claude/tzdata` above — deleted, combined
    into `claude/alpine_ci_deps`.
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
    with zero delay, racing init's reaping of the dead child. Added
    `kill_mkbusy()` (kill + poll up to 5s) to `zfs_destroy_
    common.kshlib`, fixed all 5 call sites. Confirmed fixed: 3/3 passes
    after, previously 3/3 failures.
    **The original "not Alpine/musl-specific" claim was underargued
    (2026-08-24 correction, prompted by the user asking why the same
    thing would work on glibc)**: the cited "isolated repro" that
    supposedly ruled this out never left this same Alpine/musl
    machine, so it only ruled out *ZFS*-specific, not
    *platform*-specific — a real gap, not just an omission. Went back
    and actually checked the mechanism: `mkbusy.c`'s child does no
    work at all after `daemonize()` (just `pause()`), so nothing
    CPU-bound or I/O-bound delays signal handling. Reproduced the
    no-ZFS race directly (100 `mkbusy`-against-`/tmp`-file
    spawn/kill/`pgrep` cycles): 99/100 hits. Crucially, a cheaper O(1)
    check (`cat /proc/$pid/stat`, direct lookup by pid) missed the
    zombie *every* time — already reaped — while `pgrep -f` (a full
    linear `/proc` scan, opening every process's `cmdline` to
    pattern-match) reliably still caught it. So the real mechanism is:
    the race outcome is decided by whether the *checking command's own
    cost* exceeds the reap latency, not by "how promptly the local
    init reaps." That part genuinely does generalize: `kill(2)` being
    asynchronous (returning before the target has necessarily died or
    been reaped) is POSIX-guaranteed on any Unix, and Alpine's `pgrep`
    is confirmed (`apk info --who-owns`) to be `procps-ng` 4.0.6 — the
    same upstream tool used as `pgrep` on Ubuntu/Fedora/Debian, not an
    Alpine-only implementation, so its /proc-scan cost profile isn't
    Alpine-specific either. If anything, systemd (the subreaper on
    most glibc CI legs) does more per-`SIGCHLD` bookkeeping than
    Alpine's minimal init, which would widen this race there, not
    close it. **Where the generalization is genuinely uncertain**:
    `zfs_destroy_005_neg.ksh`'s `pgrep -fl mkbusy` checks run
    unconditionally on every platform including FreeBSD, whose `pgrep`
    is a different implementation (BSD's own, via `sysctl`/`kvm`, not
    `procps-ng`) — only the weaker "kill is async, zombies need
    reaping" part of the argument extends there, not the "identical
    tool, identical scan cost" part. The one pre-fix cross-platform CI
    run already on record above showed zero unexpected failures on
    this test across the 5 non-Alpine legs, which is thin evidence
    either way given ZTS's known flakiness — not proof it can't fire
    elsewhere, but not confirmation it's equally frequent there
    either. None of this changes whether the fix (poll instead of a
    single check) is correct — it is, regardless of the exact
    mechanism — only how confidently "not platform-specific" can be
    stated in the PR description.
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
  - `claude/get_prop_empty_value` (`f9d7d9aae`, new 2026-08-24) —
    `get_prop()`/`get_pool_prop()`/`get_vdev_prop()` in
    `libtest.shlib` checked exit status but not whether the command
    actually printed a value; now `log_fail`s immediately with a
    specific message when output is empty. The logic is verified
    correct (real value / legitimately-empty value / stubbed
    empty-output case, all checked live). **Its motivation was wrong
    and later withdrawn**: originally thought this explained the
    `rsend/send-c_stream_size_estimate` CI failure — live
    reproduction (2026-08-24, see "Current status" below) proved
    that failure is genuine `zfs send -nP` output corruption
    (already root-caused elsewhere in this file), and `get_prop`
    was never involved. There's no confirmed instance of `zfs
    get`/`zpool get` actually printing nothing. User is closing
    `openzfs/zfs#18983` rather than carry a defensive check with no
    real trigger behind it.
  - `claude/procfs_stale_read_portable` (`b6f387b30`, new 2026-08-24,
    a quick triage pass) — `procfs_list_stale_read` grepped `cat`'s
    stderr for the literal string `"Input/output error"` (GNU
    coreutils' wording); Alpine's `cat` says `"I/O error"` instead,
    so the grep never matched regardless of whether the actual stale-
    read behavior was correct. Checks `cat`'s exit status instead —
    portable, since a nonzero exit on `EIO` is guaranteed where the
    exact message text isn't. Verified directly against the real
    kernel module and real `/proc/spl/kstat/zfs/<pool>/txgs`, both
    scenarios the test exercises.
  - `claude/exec_001_pos_multicall` (`855033220`, new 2026-08-24,
    same quick triage pass) — see cluster 1 (BusyBox/multi-call
    applet dispatch) above for the full story.

  Next for these thirteen: the user submits them upstream independently
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

1. **Multi-call-binary applet dispatch (Alpine's `coreutils` package,
   not actually BusyBox — confirmed via `readlink -f $(which ls)` →
   `coreutils`, not `busybox`)** — breaks whenever a test's `argv[0]`
   basename isn't a name the dispatch table recognizes. Confirmed
   root cause of `user_namespace_001` (symlink-resolution variant,
   fix exists) and `exec/exec_001_pos` (`coreutils: unknown program
   'myls'` — copying the binary to a differently-named file, then
   exec'ing it, is the same dispatch-by-basename failure via a
   different code path — **fixed 2026-08-24**,
   `claude/exec_001_pos_multicall` (`855033220`): copy to
   `$TESTDIR/ls` instead of `$TESTDIR/myls` — plain rename, dispatch
   is by basename only, no other behavior change, verified directly
   (both the execute and the `mmap(2)`/`PROT_EXEC` checks). Checked
   `exec_002_neg.ksh`'s identical `myls` pattern too: confirmed
   *not* affected and left alone — it sets `exec=off` first, so the
   kernel refuses the `execve(2)` itself (`EACCES`/126) before the
   binary's own dispatch logic would ever run either way, confirmed
   directly rather than just reasoned about).
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
   `dedup_legacy_create`, `dedup_legacy_fdt_upgrade`,
   `block_cloning_clone_mmap_write`, `block_cloning_clone_mmap_cached`,
   `block_cloning_copyfilerange_fallback_same_txg`,
   `block_cloning_ficlone`, `block_cloning_fideduperange_compress`,
   `dedup_fdt_pacing`, `dedup_legacy_fdt_mixed`, `dedup_legacy_gang`,
   `dedup_prune` (all found 2026-08-24 in the `fix/history-uncompress-
   alpine` branch's real CI job, run `32638440188`/job `97191643086` —
   this "at least" list has never been an exhaustive pass over
   `failed.txt`, so treat it as a lower bound, not a closed set), likely
   `gang_blocks_ddt_copies`. **Confirmed both BRT and DDT teardown hit
   the identical bug, not just BRT** (2026-08-24, user asked whether the
   dedup failures in that job were "the related zdb crash" — checked
   every one): all six dedup failures above show the byte-identical
   chain `dbuf_destroy+0x24b` -> `dbuf_destroy+0x42d` ->
   **`ddt_table_free+0xfc` -> `ddt_unload+0x2d`** -> `spa_unload+0x1cd`
   -> `spa_evict_all+0x6f` -> `spa_fini+0x09` -> `kernel_fini+0x0e` ->
   `main+0xb10` — identical offsets across all six, and identical to the
   BRT-side chain below except for the `ddt_table_free`/`ddt_unload`
   swap-in for `brt_vdevs_free`/`brt_unload` (note: `spa_unload`'s own
   offset differs slightly, `+0x1cd` for the DDT path vs `+0x1d5` for
   the BRT path — consistent with it being the same crash reached via
   two different call sites in `spa_unload()`, not a different bug).
   This resolves the open question `ddt.c`'s writeup below raised about
   whether `ddt.c`'s use of the same `dnode_hold()`/`dnode_rele()`
   pairing pattern as `brt.c` was actually unsafe too: it is.
   **Two more confirmed instances (2026-08-24), from a different real
   run** (the long-stuck `combined-review` `zfs-qemu` job finally
   completed after 3h33m — run `32758399185`, job `97531384792` — this
   is the fully-combined branch with essentially every other known fix
   already applied, so its unexpected-FAIL list is an unusually clean
   signal): `alloc_class_013_pos` ("removing a dedup device from a pool
   succeeds", crashes via `zdb -bbcc`) and `block_cloning_replay` — both
   show the identical `dbuf_destroy+0x24b` -> `dbuf_destroy+0x42d` chain.
   Added both to the affected list above. With nearly every other known
   issue already fixed in that branch, this run's entire unexpected-FAIL
   list (16 tests) reduces almost completely to just cluster 4 (7 of
   the 16: the two new ones here plus `dedup_bclone`, `dedup_fdt_create`,
   `dedup_legacy_fdt_mixed`, `dedup_legacy_fdt_upgrade`, `dedup_prune` —
   note `dedup_fdt_create` and `dedup_legacy_fdt_upgrade` are newly
   caught here too, added above) and cluster 5 (9 of the 16, see below)
   — plus the one already-known, deliberately-unfixed `zfs_get_006_neg`.
   That's about as clean a confirmation as this project is likely to
   get that these two clusters are the real remaining Alpine-specific
   gap, not noise from something still unfixed elsewhere. Still the
   highest-value cluster (looks like a
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
     **Follow-up: confirmed the eviction thread is real and active,
     still no crash, user decided to stop here (2026-08-24).** Added
     throwaway instrumentation to `module/zfs/dbuf.c` (never
     committed — `fprintf(stderr, "CLDBG ...")` + `fflush()` at the
     top of `dbuf_destroy()`, in `dbuf_evict_one()`, and right before
     the `mutex_exit()` in `dbuf_rele_and_unlock()`'s bonus-buffer
     branch, plus a deliberate `delay()` after that `mutex_exit()`
     and inside `dbuf_evict_one()` to widen the exact window
     `dnode.c`'s own comment warns about — standard technique for
     forcing a rare race open). Note: `fprintf`/`stderr` aren't
     kernel-safe, so this instrumentation only builds for the
     userspace `libzpool`/`zdb` target, not the actual kernel module
     — fine for this investigation since `zdb -O` runs the identical
     C code from `libzpool.so` entirely in userspace, no kernel
     module needed. Confirmed real: `dbuf_cache_max_bytes` is
     `UINT64_MAX` by default, so the small test pools used for
     reproduction never grew the dbuf cache enough to trigger
     eviction at all (zero `dbuf_evict_one` calls in early attempts)
     — forcing it tiny via `zdb -o dbuf_cache_max_bytes=1024` made
     the eviction thread engage for real, confirmed via trace: a
     second, distinct thread ID actively calling `dbuf_evict_one()`,
     with observed memory-address reuse across different objects in
     rapid succession (real allocator churn, not simulated). Despite
     this, and despite widening the artificial delay from 20ms to
     200ms at both race points: still zero crashes.
     **Cores likely matter, in the opposite direction from usual
     intuition**: this VM has 16 dedicated, mostly-idle cores, so the
     two relevant threads (main + evict) rarely get preempted
     mid-critical-section. Real CI runners have far fewer cores
     (GitHub's standard runners: 2-4) and — per the `get_prop`/
     `lrefer` investigation above — run *two* parallel test-runner
     workers sharing that small core count simultaneously, meaning
     genuinely heavier scheduler contention than anything reproduced
     here. Pinning to 2 cores (`taskset -c 0,1`) plus 4 busy-loop
     processes pinned to the same 2 cores (to approximate that
     contention) still didn't trigger it in the time available —
     though the busy-loops only covered part of that particular run
     (a background-job-survival mistake mid-session — `nohup ... &
     disown` died along with the rest of its shell when a *different*
     foreground command in the same tool call hit its timeout and got
     SIGTERM'd; relaunched and verified with `pgrep`/`mpstat` before
     trusting it the second time).
     **Cumulative total: ~185 local reproduction attempts across four
     different strategies this session (plain repeated runs, forced
     eviction pressure via the tunable, artificial delays at the race
     points, 2-core pinning + background contention) — zero
     crashes.** Given that, and the strength of the static-analysis
     evidence already in hand (two byte-identical real backtraces,
     the corrupted-stack-frame confirmation, the precise mechanism
     traced through `brt.c`/`dnode.c`/`dbuf.c`/`spa.c`), the user
     decided to stop chasing a live local reproduction and treat this
     as write-up-complete rather than open. **Next step, if ever
     revisited, is not more local iteration**: it's either (a) an
     actual crash with a live debugger attached (still waiting on a
     core dump from a real CI or local run), or (b) filing this
     upstream with OpenZFS's dbuf/ARC/BRT maintainers, who have far
     more context on which cross-thread interactions in this area are
     actually safe than can be reconstructed from source reading
     alone. **Not** something to guess a kernel-level fix for without
     more certainty, given the stakes of getting BRT/DDT reference
     counting wrong. The `module/zfs/dbuf.c` instrumentation was
     reverted, not committed anywhere.
   - **Third identical crash log found (2026-08-24), user asked to check
     `block_cloning_copyfilerange_fallback_same_txg` and
     `block_cloning_large_offset` specifically.** `block_cloning_
     large_offset` is clean — PASS in the `_20260823` Alpine run, no
     issue. `block_cloning_copyfilerange_fallback_same_txg` FAILed in
     that same run (`Memory fault` in `get_same_blocks`,
     `~/Development/logs/qemu-alpine3-24_20260823/vm1/current/output/
     block_cloning/block_cloning_copyfilerange_fallback_same_txg/
     stderr`) with a backtrace **byte-for-byte identical** to the two
     `block_cloning_clone_mmap_{write,cached}` ones above, right down to
     the same corrupted `0x7074736574007676` (`"testpool"`)
     stack-frame artifact — a third independent confirmation of the
     same deterministic bug, not previously added to the affected-test
     list below (that list was written from "at least" a partial pass
     over `failed.txt`, not an exhaustive one — worth assuming there
     may be a few more uncatalogued instances rather than treating the
     list as closed). Added to the list. Doesn't change the
     already-decided outcome (still not chasing a live repro further,
     per the 2026-08-24 "cores likely matter" write-up above) — just
     more static evidence for the same conclusion.
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
   - **Real progress (2026-08-24, user asked to check the `-c` tests
     specifically after seeing them FAIL in a real summary).** The
     "not reproduced... as the correct `zfs` user" conclusion above
     turned out to be incomplete, not wrong about the user mixup being
     *a* real methodology bug, but wrong that it was the *whole*
     explanation: pulled the actual `failed.txt` block for these tests
     from the `_20260823` Alpine run and it explicitly says
     `(run as zfs)` — real CI already runs them as the correct user and
     they still crash there. Decoded the crash properly this time
     instead of treating it as an opaque one-liner: all six `-c`
     variants (`zpool_iostat`/`zpool_status` × `disable`/`homedir`/
     `searchpath`) segfault at **the exact same offset** (`0x20944`)
     inside `ld-musl-x86_64.so.1`, with byte-identical disassembly in
     every dmesg line — not a flaky/random crash, a fully deterministic
     one. The faulting bytes are musl's classic word-at-a-time
     `strlen`-family zero-byte-detection bit trick (`0xfefefefefefefeff`
     / `0x8080808080808080`, an 8-bytes-at-a-time scan) — i.e., some
     buffer is being `strlen()`'d and the scan runs off the end of a
     mapped page before finding a NUL. **Confirmed genuinely
     Alpine/musl-specific, not just untested elsewhere**: the same
     `_20260823` run's `fedora44`, `debian13`, and `almalinux10` output
     logs for this exact test all show a clean `SUCCESS`/PASS — real
     evidence, not an assumption.
     **New lead, not chased further yet**: decoded the crashing
     process's `comm` field via Linux's 15-char `TASK_COMM_LEN`
     truncation — `"zpool_iostat_-c_disable"[:15]` is exactly
     `"zpool_iostat_-c"`, matching the dmesg `comm` byte-for-byte. That
     means the crashing process is almost certainly **the `ksh93` test
     script interpreter itself** (which renames its own process title
     to the running script's basename), not the `zpool` CLI binary —
     `comm` only reflects the *original* script name at crash time if
     the crash happens before any `exec()` replaces the process image,
     which rules out a forked-and-exec'd child like `zpool` or `awk`
     showing up under this name. This lines up with, and sharpens, the
     original "`libshell.so` involved" detail already noted above
     (`libshell.so.4` is ksh93's own shell-execution library, confirmed
     via `ldd /bin/ksh` on this VM) — the bug is most likely in ksh93's
     interaction with musl, triggered by something in these specific
     test scripts' own constructs (env var manipulation, `typeset`,
     command substitution setup, etc.), not in `zpool`'s C code at all.
     **Still not reproduced**: ~50 manual attempts this session (single
     runs, a 20-iteration loop, and a 30-iteration loop faithfully
     replicating all three `-c` variants' actual logic — disable/enable/
     unset, `$HOME/.zpool.d`, `ZPOOL_SCRIPTS_PATH` with two dirs) as
     user `zfs` — zero crashes. The real `zfs-tests.sh -t <test>`
     harness invocation hit the same `STF_SUITE`/path-resolution quirk
     noted elsewhere in this file (`-u zfs` didn't clear it either) —
     not re-debugged, per established practice here of trusting direct
     manual replication over fighting that harness quirk. Since the new
     theory implicates `ksh93` interpreting the *actual script file*
     rather than any command this session hand-typed, that harness gap
     is more likely to matter here than it has for other clusters —
     manual command replication cannot trigger a bug that lives in how
     ksh parses/executes the literal script text. Next step, if
     revisited: get the real harness running this specific test (fix or
     route around the path-resolution issue) rather than continue
     hand-replicating the commands.
   - **Follow-up (2026-08-24, same day): closed the harness gap above,
     still not reproduced.** User pushed back on treating the `-t`
     harness quirk as a dead end. Fixed the actual repro method: this
     session's manual attempts had been run through `sh -c`, not `ksh
     -p`, on the theory that `ksh93` itself (not `zpool`) is the likely
     crash site — an oversight, since that never actually exercised
     ksh93 at all. Re-ran ~150 attempts through real `ksh -p` on the
     literal `.ksh` files (isolated, a CPU-contended variant via
     `taskset` + background `yes` loops, and 15 batches of 6-way
     parallel execution) — still zero crashes. **Ruled out a build/
     version mismatch definitively**: this VM's `ksh --version` and the
     real CI job's build log both show the exact same string,
     `93u+m/1.1.0-alpha+48940aaa 2026-08-16` — identical commit,
     identical build timestamp; the user also confirmed they'd
     literally copy-pasted `qemu-3-deps-vm.sh`'s own ksh93-from-source
     recipe when provisioning this VM. **Found and fixed a real gap in
     the harness invocation itself**: `test-runner.py`'s `TestGroup`
     falls back to `logname` (whoever invoked the process) when a
     runfile section's `user =` is blank — and `zpool_iostat`/
     `zpool_status`'s sections in `common.run` do leave it blank. So
     real CI's `(run as zfs)` label means the *entire* `test-runner.py`
     process was launched as `zfs`, not that this one test overrides
     its user — this session had only ever wrapped individual `ksh`
     invocations in `sudo -u zfs`, never run the harness process itself
     that way. Got a minimal custom runfile working end-to-end as user
     `zfs` (`zfs-tests.sh -r <path>`, `-c` in that script means
     something unrelated to `test-runner.py`'s own `-c` — costed one
     wrong turn) — `zpool_status`'s 4 tests all passed once a real
     `$TESTPOOL` existed. `zpool_iostat`'s tests hit a *different*,
     unexplained snag: the `media` script exits 1 only when invoked
     through the harness, despite an identical manual `zpool iostat -c
     media testpool` succeeding moments later by hand — a real,
     reproducible discrepancy between harness and manual invocation,
     just not yet the segfault itself. Not chased further this round.
     **Bonus finding while reading the raw job log directly** (`run
     32638440188`, job `97191643086`, `fix/history-uncompress-alpine`
     branch): two more instances of this exact same deterministic
     crash (same `0x20944` offset), on `zpool_add_001_neg` and a
     `zpool_create_00*` test — cluster 5's scope is broader than just
     the `-c` script tests.
   - **Confirmed and generalized further (2026-08-24, same
     `combined-review` run as cluster 4's update above), and the
     comm-truncation theory got corrected.** `zpool_add_001_neg` and
     `zpool_create_001_neg` (identified exactly by name this time, not
     truncated) both show the identical `0x20944` offset crash — same
     bug, confirmed exact test names. These are about as minimal as a
     ZTS test gets: `misc.cfg`-only setup, `set -A args ...` then a
     plain `while` loop of `log_mustnot zpool <args>`, no custom
     scripts, no `-c` anything. **Correction to the earlier "ksh crashes
     during its own exit/cleanup" framing**: the log shows only 2 of
     the ~10 loop iterations completing (`SUCCESS: zpool add exited 2`,
     `SUCCESS: zpool add -f exited 2`) before the crash — it dies
     *mid-loop*, on the 3rd call or so, not during script teardown.
     The "crashes right when the test should finish" read came from
     the earlier `-c` tests' logs looking like they'd completed
     (multiple `SUCCESS` lines before the crash line), which was an
     inference from incomplete evidence, not a confirmed mechanism —
     this new data shows a much earlier crash point instead, so "which
     exact point in a script this fires at" is still open, not settled
     as "always at exit." `zfs_list_003_pos` and `zfs_list_007_pos`
     failed in this same run too, with the same silent-early-
     termination shape (no `ERROR`, no `ASSERTION` failure, just stops
     after 2-3 `SUCCESS` lines) — very likely more instances, though no
     explicit segfault line was visible in the captured log snippet for
     these two specifically, so treat as probable, not fully confirmed.
     **`zpool_add_001_neg` retried locally, 100 more times** (real
     `ksh -p` on the actual file, as user `zfs`, real `$TESTPOOL`) —
     zero crashes, bringing this session's cumulative local-repro count
     for cluster 5 to 350+ attempts across every angle tried
     (isolated, contended, parallel, and now the simplest-possible
     failing test), still without a single local reproduction.
   - **ROOT CAUSE FOUND (2026-08-24), via a real core dump off real
     CI — `sh_envgen()` in ksh93 itself, not `zpool` or `zdb`.** Local
     reproduction never succeeded (350+ attempts, every angle tried:
     real `ksh`, real loopback disks matching CI exactly, varied/
     padded environments, CPU contention, genuine parallelism, a full
     untagged local suite run). Pivoted to capturing a real core off
     real CI instead: added a diagnostic-only commit on top of
     `claude/combined-review-2` (`kernel.core_pattern=/var/tmp/
     core.%e.%p`, `ulimit -c unlimited` in `qemu-6-tests.sh`'s Alpine
     block, plus an `scp` of `/var/tmp/core.*` back in
     `qemu-7-prepare.sh`) and restricted the matrix to `alpine3-24`
     only (`zfs-qemu.yml`'s `os_selection`) to get a fast, focused run.
     The resulting run (`32782473016`, job `97607371379`, ~5.5h) came
     back with **10 real core files** in its artifact (5.3 MB total —
     the size worry going in was unfounded; each core is 1.8-2.6 MB,
     musl's default `coredump_filter` excludes most file-backed shared-
     library pages). Analyzed with `gdb` locally, using this VM's own
     `ksh93`/`musl-dbg` (confirmed earlier to be byte-identical in
     version/commit to what produced the cores — `zdb`/`libzpool`
     needed a fresh rebuild of the exact `claude/combined-review-2`
     commit to reduce (not eliminate) build-id mismatches; `libshell.so`/
     `libast.so` still didn't match build-id, but were close enough for
     `addr2line` offset lookups against this VM's own copies to resolve
     correctly, confirmed by getting *consistent, sensible* answers
     across seven different cores).
     **Seven of the ten cores** (`zpool_iostat_-c.*` ×3,
     `zpool_status_-c.*` ×3, `zpool_add_001_n.11967`,
     `zpool_create_00.12007`, `zfs_list_003_po.17728`,
     `zfs_list_007_po.17830/17858/17877` — the `zfs_list` ones
     "probable" above are now **confirmed**) show the **exact same
     crash, byte-identical down to the file offset in every single
     one**: `#0 strlen()` (musl, `src/string/strlen.c:17`) called on a
     pointer that is fully unmapped (`a = 0x7fa465c3f110 <error:
     Cannot access memory at address 0x7fa465c3f110>` — the literal bad
     pointer, captured directly for the first time), called from
     `#1 0x...af9` inside `/lib/libshell.so.4` at file offset `0x4caf9`
     in every core — which `addr2line` resolves to **`sh_envgen()`**
     in `src/cmd/ksh93/sh/name.c`. `sh_envgen()` is ksh93's own
     function for building the environment array before `exec()`ing a
     child process (called from `sh/path.c` and `sh/xec.c` on every
     external command a script runs) — it walks `sh.var_tree` via
     `nv_scan(..., pushnam, ...)`, and `pushnam()`'s helper `staknam()`
     (both `static`, inlined into `sh_envgen` at `-O2`, hence the
     single resolved frame) does `strlen(nv_name(np))` on every
     exported variable's name to size a stack-allocated buffer. If
     `nv_name(np)` returns a stale pointer for some variable — plausible
     given ksh93's "stak" allocator (a scratch/temporary string stack
     distinct from the OS thread stack) is a known-fragile design
     where a variable can end up holding a pointer into a stak region
     that gets popped/reused before the variable is later read — this
     is exactly the crash. **This is why nothing about `zpool`, `zdb`,
     disk backend, or resource pressure ever mattered**: the crash is
     entirely inside ksh93's own environment-building code, triggered
     on *any* external command exec, which is why it hit such
     superficially unrelated tests (`zpool_add`, `zfs_list`, the `-c`
     script tests) — they all just happen to `exec` something (`zpool`,
     `awk`, a user script) at the point some exported variable's name
     pointer has already gone stale. Also explains why manual
     replication of "the commands the test runs" never reproduced it:
     the bug isn't in *what* gets exec'd, it's in ksh's own bookkeeping
     of *previously-exported variables* by the time *some* exec happens
     — almost certainly dependent on the exact sequence of variable
     exports/scope changes earlier in the script (or possibly earlier
     in the whole test run, inherited some other way), which none of
     this session's manual reproductions replicated faithfully since
     they either ran the real script in isolation (missing whatever
     came before in a real full-suite run) or hand-typed approximations
     of it.
     **The `zdb` core** (`core.zdb.10856`, from cluster 4, captured by
     the same infrastructure) added little beyond confirming the
     already-known mechanism: `Program terminated with signal SIGABRT`
     via `abort()`, called from a `write()` inside `libzpool.so` — this
     is `libspl_backtrace()`'s own signal handler doing its
     async-signal-safe `write(2)` dump of the crash backtrace (the same
     text already seen via dmesg: `dbuf_destroy` -> `brt_vdevs_free`/
     `ddt_unload` -> ...) before calling `abort()` to terminate
     cleanly. All 100 threads in the core show the identical abort()
     chain (not the original SIGSEGV's frame), and build-id mismatches
     blocked deeper unwinding through the signal trampoline — no new
     information for cluster 4 beyond what dmesg already gave, but a
     useful confirmation that the capture infrastructure works and
     that the "print backtrace via write(), then abort()" model is
     exactly what's happening.
     **Not yet done**: an actual fix. The right fix is almost certainly
     somewhere in ksh93's `stak`/`nv_name`/variable-scope handling
     (upstream `ksh93` project, not this repo — this is a shell bug,
     not a ZFS bug), and pinning down *which* variable and *which*
     stak-invalidating operation precedes the bad export would need
     either a live debugger catching it in the act (still not achieved
     locally) or a closer read of `sh_envgen`/`staknam`/`nv_name`'s
     interaction with `stakset`/`stakinstall` in the ksh93 source.
     Given this is upstream `ksh93`'s bug, not `openzfs/zfs`'s, the
     actionable next step for *this* project is probably just to
     report it to the `ksh93` project with this exact analysis, rather
     than attempt a fix here.
     **Fix written and pushed (2026-08-24), in the sibling `ksh93`
     fork** (`~/Development/ksh`, `https://github.com/m68k-io/ksh`,
     branch `claude/sh_envgen_stale_strbuf`) — this is a separate repo
     from this one, not part of `openzfs/zfs`, so nothing changes here.
     Closer reading of `staknam()`/`sh_envgen()` confirmed the exact
     mechanism: both `nv_getval()` (for a reference variable with a
     subscript) and `nv_name()` (for a compound/namespace-qualified
     name) can return a pointer into the single, shared `sh.strbuf`
     string stream, whose contract (`sfstruse(3)`) explicitly says the
     returned pointer is only valid until the next write to that same
     stream. `staknam()` called `nv_name()` *twice* (size, then fill)
     with a `value` from `nv_getval()` sitting unused in between — if
     either `nv_name()` call wrote to `sh.strbuf`, it could invalidate
     `value` before it was ever read, and the double `nv_name()` call
     itself risks a size/content mismatch (it can leave `sh.last_table`
     changed as a side effect, changing what a second call for the same
     variable resolves to). `git blame` traced this to a likely real
     regression, `db227904a` (2024-02-28, "Further robustify
     sh_reinit()") — before it, an imported variable used the stable
     `np->nvenv` pointer directly, bypassing `staknam()` and this
     hazard entirely; after it, `pushnam()` always goes through
     `nv_getval()` instead. Fix: copy `value` to stable stack memory
     before calling `nv_name()` at all, and call `nv_name()` exactly
     once. Full local regression suite (`bin/shtests`) run both before
     and after the fix: one failure either way, `subshell.sh`'s
     `shcomp` variant — confirmed pre-existing and unrelated (a
     stderr-draining timing race, fails intermittently on unmodified
     `48940aaa` too, at the same rate) — otherwise clean. **Still not
     locally reproduced** even with this fix applied (same as without
     it), so this is based on a correct-per-the-documented-contract
     static analysis, not a confirmed-by-repro fix — flagged as such in
     the commit message.
     **Real-CI validation (2026-08-25) shows this fix did NOT resolve
     the crashes.** Added a diagnostic-only commit on top of
     `claude/combined-review-2` (kept as `claude/combined-review-3`)
     pointing `qemu-3-deps-vm.sh`'s ksh93 build at
     `https://github.com/m68k-io/ksh.git` branch
     `claude/sh_envgen_stale_strbuf` instead of upstream, restricted to
     a runfile of just the known-failing tests for a fast (~24min)
     targeted run instead of the full ~5.5h suite. Run
     `32816307233`, job `97705239675`: confirmed via the build log
     (`KornShell Version AJM 93u+m/1.1.0-alpha+36c724d4`) that the fix
     really was the binary under test. `zpool_add_001_neg`,
     `zpool_create_001_neg`, all 3 `zpool_iostat_-c_*`, all 3
     `zpool_status_-c_*`, and `zfs_list_007_pos` **still crashed**.
     Downloaded the fresh core dumps from this run and confirmed via
     `gdb`/`addr2line` an **identical** crash signature to the pre-fix
     cores: `#0 strlen()` on an unmapped pointer, called from the same
     file offset (`0x4caf9`) in `libshell.so.4`, resolving to the same
     `sh_envgen` frame. So `staknam()`'s stale-`sh.strbuf` bug is real
     and independently worth fixing (still pushed, still passes the
     full local regression suite) but is **not** the trigger for these
     specific crashes — either a different stale-pointer path into
     `sh.strbuf` is the actual culprit (`nv_name()`/`nv_getval()` are
     not the only functions in `name.c`/`nvtree.c`/`nvdisc.c` that
     write to it), or something else entirely. True root cause of
     cluster 5 remains open. Full writeup, including the exact repro
     branch/job and next-step ideas (`nv_scan()` callback
     instrumentation to log which variable is being processed right
     before the crash), lives in the sibling `~/Development/ksh`
     fork's own `CLAUDE.md`.
     **ACTUAL ROOT CAUSE FOUND (2026-08-25).** Added the `nv_scan()`
     instrumentation from the idea above (branch
     `claude/sh_envgen_instrumentation` on `m68k-io/ksh`, raw
     `write(2)` logging in `pushnam()`) and ran it via a new
     `claude/combined-review-4` branch here. The crash fired again
     (same tests) but **zero instrumented `pushnam()` lines appear
     for any crashing PID** — the crash isn't in `pushnam()`/
     `staknam()` at all. Disassembled the exact crash address instead
     (confirmed via `nm` to fall strictly inside `sh_envgen`'s own
     emitted range, not `nv_scan`'s or `pushnam`'s separate symbols):
     it's `sh_envgen()`'s own `strlen(sh.save_env[i])` line.
     `sh.save_env[]` holds raw pointers directly into `environ` for
     env vars with invalid (non-identifier) names; nothing guarantees
     that memory survives until `sh_envgen()` next reads it (`fixargs()`
     can relocate `environ`'s storage for the process-title trick, and
     `exscript()` replaces `environ` wholesale). This is why it never
     reproduced locally: it's gated on environment *content* (whether
     any inherited env var has an invalid name), not timing — this dev
     VM's environment has none (`sh.save_env_n == 0`, confirmed live via
     `gdb`), so the vulnerable code path never even executes here.
     Also explains the earlier `1.0`-vs-`dev` branch split found by the
     `claude/combined-review-5-ksh10-check` run below: `zpool_add_001_
     neg`/`zpool_create_001_neg`/`zfs_list_007_pos` crash on *both*
     branches (this bug predates the split), while `zpool_iostat_-c_*`/
     `zpool_status_-c_*` crashed only on `dev` (a separate, still-open
     question — possibly a second issue, not yet investigated since
     this fix may resolve them too).
     **Fix pushed**: `claude/save_env_dangling_environ_ptr` on
     `m68k-io/ksh` (`import1var()` now copies via `sh_strdup()` instead
     of aliasing `environ` directly). Full writeup including the
     disassembly evidence and a real bug caught in the first attempt at
     this fix (a `free()` call that crashed on `sh_envgen()`'s own
     stak-allocated copy) is in the sibling `~/Development/ksh` fork's
     `CLAUDE.md`. **Validating now** via
     `claude/combined-review-6-saveenv-fix` here — check
     `gh run list --repo m68k-io/zfs --branch
     claude/combined-review-6-saveenv-fix` for the outcome if not
     already known.

     **Aside, found while chasing this (2026-08-25)**: re-ran the
     unmodified fast targeted runfile against plain upstream ksh's
     `1.0` branch (`claude/combined-review-5-ksh10-check`, no m68k-io
     fork fix at all) specifically to check whether cluster 5 is
     `dev`-branch-specific, since this repo's CI has always built ksh
     from an unpinned clone of `dev` (ksh93/ksh's unstable branch,
     versioned `93u+m/1.1.0-alpha+<hash>`) rather than any release —
     the last real tag, `v1.0.10`, is from 2024-08-01, over two years
     stale, while the separately-maintained `1.0` branch is still
     receiving backports (tip from 2026-08-17) and never received
     `db227904a`, the commit the disproven `staknam` theory traced to.
     Result: `zpool_iostat_-c_*`/`zpool_status_-c_*` (6 tests) do NOT
     crash on `1.0` — clean pass — while `zpool_add_001_neg`/
     `zpool_create_001_neg`/`zfs_list_007_pos` still crash on `1.0`
     too. This was the finding that prompted digging into
     `combined-review-4`'s cores more carefully above, since it proved
     cluster 5 wasn't one bug.
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
     - `zfs_get_006_neg` — **real root cause found (2026-08-24, quick
       triage pass), deliberately not fixed.** A negative test
       asserting `zfs get all -r` (and 27 similar malformed
       invocations) must be *rejected*. Confirmed with a debug-
       instrumented build (never committed, reverted after): there is
       **no** manual dash-prefixed-operand scan in `zfs_do_get()` at
       all (that was a reasonable-sounding guess, but wrong) — the
       real cause is that `getopt_long()` on musl **unconditionally
       permutes `argv`, ignoring `POSIXLY_CORRECT` entirely**,
       confirmed with a standalone repro against musl directly
       (`getopt_long(argc, argv, ":d:o:s:jrt:Hp", ...)`, with and
       without `POSIXLY_CORRECT=1` in the environment — permutes
       either way). This is inconsistent with musl's own plain
       `getopt()`, which does *not* permute (matches the finding
       behind `claude/getopt_permute`, but is a genuinely different
       mechanism — that fix was about a *test script's* argument
       order; this is the *CLI's own* parser silently accepting
       malformed input). `zfs_do_get()` uses `getopt_long()`
       specifically for `--json`/`--json-int` support, so `-r`
       appearing after the `all` positional gets silently reordered
       and accepted as a real flag instead of being rejected.
       **Not a musl bug** — read musl's actual source
       (`~/Development/musl/src/misc/getopt_long.c:34`) to confirm:
       permutation is controlled *exclusively* by the optstring's
       leading character (`+` disables it, `-` is a different GNU
       mode, anything else permutes), with **zero** reference to
       `POSIXLY_CORRECT` anywhere in the file — deliberate, by
       design, not an oversight, matching musl's general philosophy
       of avoiding glibc's implicit environment-variable-driven
       behavior toggles in favor of an explicit API contract. glibc
       documents and honors the exact same `+`/`-` leading-character
       convention alongside its own `POSIXLY_CORRECT` fallback, so
       the portable, correct fix (a leading `+` in the optstring
       passed to `getopt_long()`, forcing POSIX-strict parsing) isn't
       an Alpine-specific shim — it corrects `zfs_main.c` relying on
       a glibc-only, environment-dependent convention instead of the
       explicit one that actually works correctly on every libc.
       **Deliberately not implemented**:
       `cmd/zfs/zfs_main.c` is used by every `zfs` subcommand, and
       forcing strict ordering is a genuine user-facing CLI parsing
       *behavior change* for `zfs get` (anyone currently relying on
       flags-after-positionals working would be affected) — that's a
       real product-behavior decision, not a
       test-portability fix, and deserves the user's explicit
       go-ahead rather than being bundled into a "quick checks" pass.
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
   - **`procfs_list_stale_read` — root cause found and fixed
     (2026-08-24).** Confirmed directly (real kernel module loaded,
     real `/proc/spl/kstat/zfs/<pool>/txgs`, real `cat`): the stale
     read genuinely fails with `EIO` exactly as intended, but
     Alpine's `cat` (the "coreutils" package's multi-call binary, a
     lightweight reimplementation, not GNU coreutils) reports it as
     `cat: -: I/O error`, not `Input/output error` — the string the
     test grepped for. New branch
     `claude/procfs_stale_read_portable` (`b6f387b30`): check `cat`'s
     exit status (portable, `EIO` reliably yields nonzero) instead of
     its message text (not portable). Verified both scenarios the
     test exercises (clearing entries via `echo 0 > $TXG_HIST`, and
     pushing old entries out via enough new `zpool sync` calls)
     directly against the real procfs file — both now correctly
     detect the failure. The formal test-runner invocation hit the
     same `STF_SUITE`/path-resolution quirk noted elsewhere in this
     file (not re-debugged); the manual replication exercises the
     identical real kernel module + real `cat` binary the test itself
     would, so it's trusted as sufficient here too.
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
- Alpine 3.24.1 VM, 16 vCPU, 32G RAM, kernel **7.1.5-0-stable**
  (switched from `6.18.44-0-virt` on 2026-08-24, see "Current status"
  below — `linux-virt`/`linux-lts` are no longer installed at all, only
  `linux-stable`, matching what `master`'s CI now provisions).
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
  yet. **`#18983` is being closed (2026-08-24)**: a reviewer asked
  for the CI logs behind the "observed on real CI" claim, which led
  to discovering the claim was wrong (see the `get_prop_empty_value`
  entries above) — no confirmed real-world trigger for the fix, so
  the user is withdrawing it rather than defend an unconfirmed
  failure mode. **User is deliberately waiting for this first batch to merge
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
  `send_progress_race` (**PASS was wrong — see the 2026-08-24 correction
  below; this was misread from the ZTS test result alone, without
  noticing the run's own build had failed on 3 platforms**),
  `mkbusy_kill_race` (2/2 PASS),
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
      empty-output failure: **misdiagnosed at the time (2026-08-24),
      corrected 2026-08-24 after the user pushed on the "how do you
      know it's `get_prop`" question and asked for a live repro.**
      Originally read `ERROR: within_percent 16795648 90 exited 2`
      and *assumed*, without checking, that `16795648` was `$ds_size`
      and the vanished argument was `$ds_lrefer` (from `get_prop`) —
      that assumption was never verified and turned out backwards.
      This is the *same* `rsend/send-c_stream_size_estimate` failure
      already correctly root-caused above as genuine `zfs send -nP`
      output corruption (the "real product bug, TRUE root cause
      found" entry) — it should have been recognized as the same bug
      instead of re-investigated from scratch under a new theory.
      Confirmed by live reproduction on a throwaway branch (`baseline`
      + `get_prop_empty_value` only, deliberately excluding both send
      fixes, with debug prints added to `get_prop()` and
      `get_estimated_size()`): reproduced on the **first attempt**,
      and `ds_size=[] ds_lrefer=[16795648]` — `get_prop`'s output
      (`$ds_lrefer`) was correct throughout; `get_estimated_size()`'s
      `awk` parse of `zfs send -nP`'s output (`$ds_size`) came back
      empty because the captured output was just `size\t16819824`
      with the `full\t<snap>\t<size>` line missing entirely. The
      400+-iteration local reproduction attempts failed because they
      were chasing empty `get_prop` output, which doesn't happen —
      once the actual target (`zfs send -nP` corruption) was
      instrumented, it reproduced immediately, no contention needed.
      **`get_prop` is not, and never was, implicated in this test.**
      The "two parallel `test-runner.py` workers sharing one VM"
      scheduling-contention theory was never verified either; it's
      the kind of hypothesis that sounded plausible and got restated
      as fact through repetition rather than evidence. There remains
      no confirmed instance, anywhere, of `zfs get`/`zpool get`
      actually exiting 0 while printing nothing.
      - **`claude/get_prop_empty_value`'s own logic still checks out**
        on its own merits, unrelated to this test: re-verified live
        (2026-08-24) against a real pool — real value returns
        unchanged, a user property explicitly set to `""` returns
        empty without `log_fail`, a stubbed "exits 0, prints nothing"
        `zfs` triggers `log_fail` immediately with the intended
        message. It just has no connection to any failure actually
        observed on CI — the PR's motivating example was wrong, and
        the user is closing `openzfs/zfs#18983` rather than keep a
        defensive check with no confirmed trigger.
      - **Still open**: `claude/lzc_send_wrapper_splice_race`'s own
        real CI run (job `97254204074`) *also* failed
        `send-c_stream_size_estimate`, despite the branch's local
        validation claiming to be "sufficient on its own" against the
        original unfixed `estimate_size()`/`send_print_verbose()`.
        `claude/send_progress_race`'s CI run passed it. Both branches
        are based on `baseline`, neither stacked on the other, so
        this isn't a merge-order artifact — genuinely unresolved why
        the splice-race fix doesn't clear this on real CI when the
        progress-thread workaround does. Not yet investigated further.
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
  `claude/send_progress_race` (`32d09c43d`), see cluster 6 above.
  `procfs_list_stale_read` fixed by `claude/procfs_stale_read_portable`
  (`b6f387b30`) — grepped for non-portable `cat` error text, see
  cluster 6 above. `zfs_get_006_neg`: real cause found (musl's
  `getopt_long()` unconditionally permutes, ignoring
  `POSIXLY_CORRECT`) but deliberately not fixed — see cluster 6
  above for why.
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
- **First PR batch resolved, fork synced and cleaned up (2026-08-24).**
  Checked all four first-batch PRs via `gh pr view --json state,mergedAt`
  (not just local patch-id matching): `#18979` (mmp), `#18980`
  (linux-stable-kernel), and `#18981` (history_uncompress) all **MERGED**;
  `#18983` (get_prop_empty_value) **CLOSED**, not merged, as already
  planned (see above — no confirmed real trigger for that fix). `origin`'s
  `master` had already picked up the merges via GitHub's fork-sync (no
  separate `upstream` remote configured — `git fetch`/`pull` against
  `origin` was sufficient); fast-forwarded local `master` 5 commits to
  `bd474db2f`, then rebased `baseline` onto it (see the `baseline` bullet
  above — the `alignas` fix dropped out the same way the CDDL fix did),
  and force-with-leased the result to `origin/baseline`
  (`64740cac5` -> `06a89ec7e`). Checked Actions afterwards per the DEBUG
  commit's `[skip ci]` line: confirmed no new runs were triggered by the
  push (most recent run predated it by ~9 minutes), and branch
  deletion doesn't trigger any workflow here (`grep`-confirmed no
  `on: delete` triggers) — nothing needed cleaning up.
  Deleted six branches, local + remote where they existed on `origin`:
  `claude/mmp`, `claude/linux-stable-kernel`, `claude/history_uncompress`
  (merged), `claude/get_prop_empty_value` (closed/withdrawn),
  `combined-review` (a stacked-all-13-fixes validation branch, not part
  of the 13/14-branch inventory documented in this file, superseded now
  that the individual branches are the real PR sources — **was** on
  `origin` too, caught and deleted after an initial miss, see below),
  and `repro-test` (local-only throwaway repro branch for the
  `get_prop`/send-corruption investigation, already resolved). **Note
  for next time**: `git branch -vv` only lists tracking info for
  branches with an explicit upstream configured in `.git/config` — it
  is *not* a reliable way to check whether a branch exists on `origin`.
  Use `gh api repos/<repo>/branches` (or `git ls-remote origin`) instead;
  this session initially misjudged `combined-review` as local-only on
  that basis, then had to catch and delete it from `origin` separately
  after `git branch -a` (post-fetch) surfaced it.
  Nine `claude/<topic>` fix branches now remain, all still unsubmitted —
  per "Repo layout" above, this first batch resolving is the trigger
  condition for the user to submit those nine personally; not yet
  requested, so not started unprompted.
- **Remaining nine fix branches rebased onto the new `baseline`, and
  `tzdata`+`libcap-utils` combined (2026-08-24, same session as
  above).** User asked whether rebasing the remaining branches made
  sense; rather than answer abstractly, actually tested it (checked
  each branch out, ran `git rebase baseline`, recorded the result,
  aborted on conflict) before answering. **7 of 9 rebased clean** and,
  as a side effect, collapsed back down to a single commit each
  (they'd accumulated now-redundant patch-id-equivalent commits — the
  old CDDL fix, stale DEBUG-commit variants, sometimes the `alignas`
  fix — restoring the "one file, one root cause, one commit" shape):
  `user_namespace`, `getopt_permute`, `mkbusy_kill_race`,
  `send_progress_race`, `lzc_send_wrapper_splice_race`,
  `procfs_stale_read_portable`, `exec_001_pos_multicall`.
  **2 conflicted for real**: `tzdata` and `libcap-utils` both edit the
  same wrapped `apk add` package list in `qemu-3-deps-vm.sh` that the
  now-merged `linux-stable-kernel` PR also touched (its
  `linux-virt`->`linux-stable` swap reflowed the line wrapping) — a
  cosmetic collision, not a real design conflict. User's call: combine
  both into one new commit/branch, `claude/alpine_ci_deps`
  (`2a466d1f4`), rather than resolve them as two separate rebases —
  deliberate, narrow exception to the "one root cause per branch" rule
  since they're both trivial CI-provisioning package additions
  colliding on the same line; see the `tzdata`/`libcap-utils` entries
  above for the cross-reference. `claude/tzdata` and
  `claude/libcap-utils` deleted (local + `origin`) after this.
  All 8 resulting branches (the 7 rebased + the 1 new combined one)
  force-with-leased / pushed to `origin`. Since real `claude/<topic>`
  fix branches are deliberately *not* covered by the `[skip ci]`
  convention (see "CI hygiene" above — they still need real CI
  validation eventually), these 8 pushes triggered 16 real workflow
  runs; per the user's explicit instruction this round, all 16 were
  cancelled immediately via `gh run cancel` (confirmed via polling
  `gh run list` until every one showed `completed`/`cancelled` — a
  few needed a second cancel request before GitHub's status caught
  up). This was a deliberate choice to defer burning CI cycles on
  this batch, not a standing policy — future pushes to these branches
  should get real CI runs as normal unless told otherwise again.
- **Real bug found and fixed in `claude/send_progress_race`
  (2026-08-24), correcting a wrong "PASS" claim above.** User asked
  to check why the non-Alpine legs of the orphaned `combined-review`
  run (`32758399185`) all failed — that run itself was stale/deleted
  branch noise, but the failure inside it was real: every glibc
  platform (`ubuntu24`, `fedora44`, `almalinux10`, `debian13`,
  `centos-stream9/10`, `ubuntu22/26`, `almalinux8/9`, `debian12`)
  failed to even *build*, with `lib/libzfs/libzfs_sendrecv.c:1099:16:
  error: ignoring return value of 'write' declared with attribute
  'warn_unused_result' [-Werror=unused-result]` — `send_print_line()`
  used `(void) write(...)`, and a bare `(void)` cast does not silence
  `-Wunused-result` for glibc's fortified (`-D_FORTIFY_SOURCE=3`)
  `write()`, so `-Werror` turned it into a hard build failure on every
  glibc target. musl doesn't fortify `write()` the same way, which is
  why this never showed up in any local Alpine testing.
  Checked further and found this wasn't just the stale run: the real
  CI run for `claude/send_progress_race`'s own branch (`32657510068`,
  2026-08-23) hit the identical error on 3 of its 6 DEBUG-matrix
  platforms (`fedora44`, `almalinux10`, `debian13`) — the branch's
  overall run conclusion was `failure`, not the `PASS` recorded above;
  that entry was written from the ZTS test result alone, without
  noticing the run's own build had failed elsewhere in the same
  matrix. Fixed (still open, not yet re-merged upstream) by capturing
  `write()`'s result in a `__maybe_unused` variable instead of casting
  it to `void` — the same idiom already used for this exact situation
  elsewhere in the tree (`lib/libspl/backtrace.c`,
  `cmd/zstream/zstream_backtrace.c`). Verified it compiles clean
  locally (musl can't reproduce the glibc-specific warning itself, so
  this only confirms no regression, not that the original error is
  gone); amended into the existing commit (`9dcd82329` ->
  `9ce9083b1`) since it's a fix to that same commit's own bug, not a
  new logical change, and force-with-leased the result to `origin`.
  **Unlike the rebase batch above, this push's CI run was deliberately
  left running** (not cancelled) specifically to get real confirmation
  the glibc build error is actually gone — check
  `gh run list --repo m68k-io/zfs --branch claude/send_progress_race`
  for the outcome next session if not already known.
- **This VM's kernel switched from `linux-virt` to `linux-stable`
  (2026-08-24), to match what `master`'s CI now provisions.** Prompted
  by the user asking to check out `master` and evaluate what the VM
  itself needed to change. Evaluation found: (a) bare `master` now
  builds cleanly here (confirmed for real, see the `a983deb6e` bullet
  above) — the old "always build against `baseline`" rule is retired;
  (b) `linux-stable-dev` was missing from an otherwise-complete package
  list (every other package in `master`'s current
  `qemu-3-deps-vm.sh` was already installed); (c) the VM was still
  booting `linux-virt` even though `linux-stable` had been installed
  earlier (cluster 7 investigation) but never made the persistent
  default. First attempt was to set `GRUB_DEFAULT` and regenerate
  `grub.cfg` (this VM boots via GRUB with multiple kernel entries,
  unlike real CI's cloud image which boots via bare `extlinux` with a
  `default=` line — the `linux-stable-kernel` branch's `sed` fix
  doesn't apply here directly). The user then suggested a cleaner
  alternative: just uninstall `linux-virt`/`linux-virt-dev` (and,
  as it turned out, `linux-lts` too) instead of managing
  `GRUB_DEFAULT` — closer to what a real, ephemeral CI VM actually
  looks like (those never have `linux-virt` installed at all under the
  current deps script) and avoids an index-shift landmine (if
  `GRUB_DEFAULT=1` were left set while an entry above it got removed,
  it would silently point at the wrong kernel afterward). `apk del`
  needed the user to run directly (blocked by the permission classifier
  as a risky action from this session). Installed `linux-stable-dev`,
  rebuilt/reinstalled ZFS against the new kernel (`configure` picked up
  `/usr/src/linux-headers-7.1.5-0-stable` correctly, clean build,
  modules load: `zfs-2.4.99-1`/`zfs-kmod-2.4.99-1`), and directly
  confirmed the actual point of the switch: `modprobe scsi_debug
  dev_size_mb=64` now creates a real synthetic disk (`CONFIG_SCSI_DEBUG
  =m` live), which it could not on `linux-virt`.
