# ZFS branch inventory (m68k-io/zfs)

Moved out of `CLAUDE.md` on 2026-08-26 to keep that file focused on
current status. This is reference material: what branches exist in
this fork and what each one does. See `INVESTIGATIONS.md` for the
underlying root-cause analysis behind each fix.

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
    Traced the original `readlink -e $(which touch)` back to this
    test's 2018 introduction (`0e85048f5`) — no comment, no rationale
    ever given; confirmed via `user_ns_exec.c` (runs commands via a
    real `/bin/sh -c` inside the new namespace, no raw `execve` that
    would need a pre-resolved path) that it was never load-bearing,
    just unexamined defensive boilerplate carried through a 2022
    `which`→`command -v` refactor. **PR `openzfs/zfs#18999`, open
    2026-08-26.**
  - `claude/getopt_permute` (`054846daf`, new 2026-08-23, found while
    validating `claude/mmp`). **PR `openzfs/zfs#18994`, open
    2026-08-26, framed as "essentially a no-op for all the other
    distributions" since glibc permutes either way.** — glibc's
    `getopt()` permutes `argv` by
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
  - `claude/mkbusy_kill_race` (`9036c2fe9`, new 2026-08-23, cluster 6).
    **No PR yet.** — `mkbusy` daemonizes and gets reparented to init; `zfs_destroy_001_
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
    **No PR yet.**
  - `claude/lzc_send_wrapper_splice_race` (`1c4bb02cc`, new
    2026-08-23, the real root cause of the same bug as
    `claude/send_progress_race` above). **No PR yet.** —
    `lzc_send_wrapper()`'s
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
  - `claude/procfs_stale_read_portable` (`a947d314e` as of
    2026-08-25, superseding `b6f387b30`) — `procfs_list_stale_read`
    grepped `cat`'s stderr for the literal string
    `"Input/output error"` (GNU coreutils' wording); Alpine's `cat`
    says `"I/O error"` instead, so the grep never matched regardless
    of whether the actual stale-read behavior was correct.
    **First attempt (`b6f387b30`) checked `cat`'s exit status
    instead of grepping at all — caught as a real regression in test
    precision** (the original piped into `grep`, so the pipeline's
    exit status was grep's, not cat's; the original test never
    actually checked cat's own exit code, only that stderr matched
    that specific text — switching to a bare exit-status check
    widened the assertion to accept *any* `cat` failure, not
    specifically EIO). Corrected to `grep -E "Input/output
    error|I/O error"` instead, restoring the original specificity
    while covering both known wordings — this test is Linux-only
    (`:Linux` tag in `linux.run`), so GNU coreutils (all glibc
    distros) and Alpine's coreutils package are the complete set for
    this suite's CI matrix. Verified directly against the real
    kernel module and real `/proc/spl/kstat/zfs/<pool>/txgs`, both
    scenarios the test exercises, plus a synthetic `cat` shell
    function confirming the regex matches both wordings and rejects
    an unrelated failure (e.g. permission denied). **PR
    `openzfs/zfs#18998`, open 2026-08-26.**
  - `claude/exec_001_pos_multicall` (`855033220`, new 2026-08-24,
    same quick triage pass) — see cluster 1 (BusyBox/multi-call
    applet dispatch) above for the full story. `myls`'s naming
    traced back to the original 2015 illumos test-suite port
    (`6bb24f4dc`) — no platform-specific reason, illumos/Solaris has
    no multi-call-binary dispatch, so the name never mattered on any
    platform this test was ever tested against. **PR
    `openzfs/zfs#19000`, open 2026-08-26.**

  Next for these thirteen: the user submits them upstream independently
  (each is small/targeted enough to go as its own PR, matching the
  "small, targeted fixes" principle). Not this fork's job to merge or
  combine them.

## Update (2026-08-26): fork resync, branch cleanup, cluster 4 fix

- `claude/alpine_ci_deps` merged upstream as `openzfs/zfs#18988`
  (2026-08-25) — deleted, local + `origin`.
- `origin/master` confirmed byte-identical to `openzfs/zfs` master
  (`998eca979`, direct SHA comparison, not just fork-sync trust).
  Local `master` fast-forwarded, `baseline` rebased onto it (trivial:
  the only thing on top of `master` is the permanent `**DEBUG**`
  commit) and force-with-leased to `origin/baseline`.
- All eight `combined-review-*` staging branches (`2` through
  `8-cluster4-fix`) deleted, local + `origin` — each was a throwaway
  validation branch for a specific past investigation round (cluster
  5's ksh check, the save_env fix, cluster 4's diagnostic work) and
  had already served its purpose. Replaced by `claude/combined-review-9`
  (below).
- **New fix branch: `claude/dnode_rele_uaf`** — resolves cluster 4 (the
  zdb/dbuf teardown crash, see `INVESTIGATIONS.md` for the full
  root-cause narrative and validation detail). One-line summary:
  `dnode_rele_and_unlock()`'s `ZFS_DEBUG`-only assert read
  `dnh->dnh_zrlock` after the dnode's parent block could already have
  been concurrently freed by another thread's dbuf eviction of a
  *different* dnode sharing the same block — a real heap-use-after-free,
  reproduced under ASAN and cross-validated against 16 real CI cores
  (all crashing at the identical instruction offset) plus a clean
  74/74-PASS real-CI run of the same test groups with the fix applied.
  `#ifdef ZFS_DEBUG` only; moves an unsafe read earlier, doesn't change
  non-debug/production code paths. **Cross-platform scrutiny done
  (2026-08-26)**: full 16-platform run on the `alex-moch/zfs` final-QA
  repo plus two 6-platform runs here — 0 cluster-4-signature failures
  across 28 platform-legs. One unconfirmed lead: `alloc_class_016_pos`
  FAILed once on `ubuntu26` with a "pool busy" cleanup error, not
  cluster 4's signature — looks like ordinary ZTS flakiness but not
  yet confirmed via rerun. **Not yet submitted upstream** — nothing
  technical left blocking it, just hasn't been submitted.
- **New combined-review branch: `claude/combined-review-9`**, built by
  cherry-picking every currently-unmerged real branch onto the rebased
  `baseline` — the four open-PR branches (`getopt_permute`,
  `procfs_stale_read_portable`, `user_namespace`,
  `exec_001_pos_multicall`), the three no-PR-yet branches
  (`mkbusy_kill_race`, `send_progress_race`,
  `lzc_send_wrapper_splice_race`), and the new `dnode_rele_uaf` fix.
  All eight cherry-picks applied clean, no conflicts.

  **Update, same session**: all seven individual branches were then
  also rebased onto the new `baseline` (each collapsed to its single
  real commit, clean, force-with-leased), and `combined-review-9` was
  deleted and rebuilt from their fresh tips — so every branch listed
  above is now current against `master`/`baseline`, not just
  `combined-review-9`. Every push in this round (7 rebases + the
  rebuild) triggered a real CI run as usual; all were cancelled
  immediately per explicit instruction, a one-off deferral matching
  the 2026-08-24 16-run cancellation, not a standing policy.

- **`claude/combined-review-10` (2026-08-27)**, off
  `combined-review-9` — adds one `**DEBUG**` commit on top of the same
  8-patch stack: redirects `qemu-3-deps-vm.sh`'s Alpine ksh93 install
  to `m68k-io/ksh`'s new `zfs` branch (briefly misnamed `zsh` — typo,
  renamed same day; see that fork's own branch inventory) instead of
  plain `ksh93/ksh --branch 1.0`, to validate cluster 5 combined with
  everything else in one real-CI run. User's own call: this redirect
  belongs in a diagnostic commit on this fork, not a permanent change
  (upstream doesn't know about the ksh fork).
  **First push** (`git clone --branch zfs` + build from source) was
  accidentally cancelled ~2h into its own CI run before completing —
  see the "Current status" cluster-5 entry in `CLAUDE.md` for the full
  account and the real per-test data recovered from the job log before
  it was deleted (all five cluster-5 tests passed, zero `[FAIL]`
  anywhere in what completed). **Second push** (`b639740a8`) replaced
  the from-source build with installing a prebuilt release instead
  (`m68k-io/ksh` release `alpine-9bcb5762` — see `CLAUDE.md` for
  detail), cutting real CI time on this leg. Check
  `gh run list --repo m68k-io/zfs --branch claude/combined-review-10`
  for this run's outcome if not already known.


## Update (2026-08-27): PR batch merged, branches/CI cleaned up, ksh install promoted to a real branch

- **Four PRs merged**: `getopt_permute` (`#18994`), `procfs_stale_
  read_portable` (`#18998`, merged under the title "accept Alpine's
  EIO error message" -- reviewer reworded the commit message and
  dropped an inline comment during review, same code change), `user_
  namespace` (`#18999`), `exec_001_pos_multicall` (`#19000`). User
  synced this fork's `master` from upstream afterward.
- `baseline` rebased onto the new `master` (trivial -- one commit, the
  permanent `**DEBUG**` runner-restriction commit), force-with-leased.
- The four now-merged branches deleted, local + `origin`.
- **`claude/dnode_rele_uaf`, `claude/getopt_long_permute`, `claude/
  lzc_send_wrapper_splice_race`, `claude/mkbusy_kill_race`, `claude/
  send_progress_race`** -- the five remaining active fix branches --
  all rebased onto the new `baseline`, clean, force-with-leased.
- **New fix branch: `claude/getopt_long_permute`** (this session) --
  resolves `zfs_get_006_neg`: none of `zfs_main.c`'s six
  `getopt_long()` calls had a leading `+` in their optstring, so all
  six ran in GNU-permuting mode on musl (glibc permutes regardless via
  a non-portable extension; `POSIXLY_CORRECT` stops it on glibc but
  musl's `getopt_long()` ignores that variable entirely by design,
  confirmed by reading musl's source). Fixed all six call sites (one
  repeated defect, not six independent ones) with the portable `+`
  prefix, already precedented in-tree (`cmd/zhack.c`). Validated:
  `zfs_get_006_neg` + full `zfs_get` group (11 PASS, 1 expected SKIP),
  `zfs_list`/`zfs_mount`/`zfs_share`/`zfs_unmount`/`zfs_unshare`/
  `channel_program` groups (61/61 PASS), `rsend` (50/51 PASS, the one
  FAIL a pre-existing unrelated issue). Real-CI confirmed on its own
  isolated run before this session's rebase (`33040755881`, now
  deleted after extracting this): `zfs_get_006_neg` **PASS** on
  Alpine; every other failure in that run was either cluster 4/5 (not
  included on this single-topic branch) or the already-tracked `send-
  c_stream_size_estimate`. **No PR yet.**
- **New fix branch: `claude/ksh_alpine_prebuilt`** (this session) --
  promotes the ksh93-install redirect from a `**DEBUG**` commit (on
  the now-deleted `combined-review-10`) to a real, permanent commit:
  `qemu-3-deps-vm.sh`'s Alpine `ksh93` install step now installs the
  prebuilt, fixed `.apk` from `m68k-io/ksh`'s `zfs` release
  (`apk add --allow-untrusted`) instead of cloning and building
  upstream `ksh93/ksh`'s (unfixed) `1.0` branch from source. Not a
  DEBUG hack because it's a legitimate, intended-to-stay fix for this
  fork's own CI -- but also not directly upstream-submittable to
  `openzfs/zfs` as-is, since it depends on a personal fork's GitHub
  release rather than anything `openzfs/zfs` could reasonably point
  at; see the commit message for the intended end state (revert once
  the ksh fixes land in `ksh93/ksh` proper). Hit and fixed a
  `commitcheck` **subject**-line-length violation while landing this
  (75 chars; the limit applies to the subject independently of the
  72-char *body*-wrap rule already documented above) -- see
  `CLAUDE.md`'s working principles for the corrected note.
- **`claude/combined-review-9` and `claude/combined-review-10`
  deleted**, local + `origin` -- superseded by `claude/combined-
  review-11` below. Before deleting `-10`, extracted its real-CI run's
  data (see `claude-notes/CI-RUN-2026-08-27-combined-review-10.md`):
  clusters 4 and 5 both confirmed resolved *in combination*, zero core
  dumps on Alpine.
- **New combined-review branch: `claude/combined-review-11`** -- six
  commits on the rebased `baseline`: `dnode_rele_uaf`, `getopt_long_
  permute`, `lzc_send_wrapper_splice_race`, `mkbusy_kill_race`,
  `send_progress_race`, `ksh_alpine_prebuilt`. Every currently-
  unmerged fix, all cherry-picked clean, no conflicts.
- **CI/workflow-run cleanup**: deleted 69 stale/orphaned workflow runs
  on `m68k-io/zfs` -- old pre-rebase commits on branches that got
  force-pushed this session, and runs whose branch had already been
  deleted (the entire `combined-review-2` through `-8-cluster4-fix`
  diagnostic-branch history, the four just-merged branches' old runs,
  and 7 sub-minute cancelled-noise runs from the `master` sync).
  `alex-moch/zfs`'s runs were checked too -- nothing redundant there,
  left alone.
- **`/var/tmp` on the local dev VM cleaned up** (19GB of accumulated
  ZTS test leftovers -- `tmp.*` scratch files, `file-vdev*`/`file1`
  loopback-backed test images, old `test_results/`, a stray `core.sh.*`
  already analyzed in an earlier session, etc.). Confirmed safe first:
  `zpool list`/`zpool status` showed no imported pools, `mount` showed
  no ZFS datasets or loop devices mounted under `/var/tmp`, and no
  zfs-related process was running -- nothing was actually using any of
  it, so a plain `rm -rf` (not a forced ZFS teardown of anything) was
  sufficient.
