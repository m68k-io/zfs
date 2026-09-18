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
- **Seven fix branches remain** (originally thirteen; four deleted
  2026-08-24 as merged/withdrawn, `tzdata`+`libcap-utils` combined into
  one new branch, `claude/alpine_ci_deps`, and `send_progress_race`
  deleted 2026-08-30 as a misdiagnosis — see "Current status" below and
  the entry below for each), each stacked directly on `baseline` and
  each targeting one root cause. All are one commit apiece except
  `claude/lzc_send_wrapper_splice_race`, which carries three after
  2026-08-30 (see its entry for why) (`claude/alpine_ci_deps` is a deliberate,
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
  `claude/lzc_send_wrapper_splice_race` re-validated 2026-08-30 with
  three dedicated ZTS regression tests, each failing without its commit
  and passing with it (see its entry below). None yet re-tested in real
  CI:
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
  - `claude/send_progress_race` — **deleted 2026-08-30, withdrawn as a
    misdiagnosis.** It blamed `fprintf(3)` issued shortly after a
    `send_progress_thread` create/cancel/join cycle, but that thread
    writes to `stderr` and nothing else (all five of its `fprintf()`
    calls are hardcoded to it), while the corrupted output is on
    `stdout` — it cannot have touched the corrupted stream. Nor was it
    the harmless improvement it was previously described as: it changed
    two `dgettext` msgids (orphaning existing translations), dropped the
    upstream GCC/UBSan `-Wformat-overflow` pragma, and discarded
    `write(2)`'s return value at all three sites. Never had a PR. Tip
    preserved locally as tag `dropped/send_progress_race`
    (`0e74dc641`) in case any of it is wanted later; nothing on the
    remote. See cluster 6 in `INVESTIGATIONS.md` for the proven root
    cause that replaces it.
  - `claude/lzc_send_wrapper_splice_race` (`55cc1c83b`, rewritten
    2026-08-30, **three commits — a deliberate exception to the
    one-commit-per-branch rule**, see the note below). **No PR yet.**
    All three are in `lib/libzfs_core/libzfs_core.c`'s
    `lzc_send_wrapper()`, each with its own ZTS regression test that
    fails without it and passes with it:
    - `8b4829679` "don't let the send relay rewind the output fd" —
      `send_worker()`'s `splice()` used a `NULL` `off_out`, which
      latches the destination's file position on entry and writes it
      back on return *even when it transfers nothing*, rewinding the
      fd under the caller's own output. Fix: explicit thread-local
      offset, plus a resync afterwards that is **conditional on
      having actually relayed bytes**. Test:
      `rsend/send_dryrun_parsable`.
    - `5c4533785` "relay by hand when the destination is O_APPEND" —
      `splice()` refuses `O_APPEND` targets (`EINVAL`), so
      `zfs send >>file` died of `SIGPIPE` writing nothing. Pre-
      existing, not introduced by the commit above. Fix: a
      `read()`/`write()` loop for those destinations. Test:
      `rsend/send_append_redirect`.
    - `55cc1c83b` "report a failed send destination instead of dying
      on it" — a relay failure closed the pipe under the still-
      writing send, killing it by `SIGPIPE` before the real error
      could surface (`zfs send >/dev/full`: exit 141, silence). Fix:
      block `SIGPIPE` across the relay, consume it, and let the
      relay's error outrank `func()`'s. Test: `rsend/send_dest_error`
      (Linux-gated). Does **not** fix the message text — see cluster
      6 for why that needs a `module/` change.
    The earlier single commit (`842250155`, and `1c4bb02cc` before
    it) is superseded: its unconditional resync `lseek()` reproduced
    the very rewind it meant to fix, measured 200/200 corrupt. Old
    tip preserved locally as tag
    `pre-review/lzc_send_wrapper_splice_race`. Three commits rather
    than three branches because they are sequential edits to one
    function that would conflict textually as separate branches —
    worth revisiting if they are submitted upstream separately.
    See cluster 6 in `INVESTIGATIONS.md` for the full investigation.
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

## Update (2026-08-30): send-relay bugs re-investigated, one branch dropped

- **`claude/lzc_send_wrapper_splice_race` rewritten**, now three
  commits (`8b4829679`, `5c4533785`, `55cc1c83b`), force-pushed by the
  user after the rewrite; the third commit pushed as a fast-forward.
  The previously-published single commit is superseded because it did
  not actually fix the bug — see the branch entry above and cluster 6
  in `INVESTIGATIONS.md`. Old tip kept locally as tag
  `pre-review/lzc_send_wrapper_splice_race`.
- **`claude/send_progress_race` deleted**, remote and local, as a
  misdiagnosis rather than a merely-superseded fix. Tip kept locally
  as tag `dropped/send_progress_race`.
- **`claude/combined-review-11` is now stale**: it still carries the
  withdrawn `send_progress_race` commit and the superseded single-
  commit version of `lzc_send_wrapper_splice_race`. It needs
  regenerating from the current branches before it is used for
  anything — not done here.
- Neither branch ever had an upstream PR, checked via `gh pr list
  --repo openzfs/zfs --head <branch> --state all` and by filtering the
  upstream PR list on `head.repo.owner.login == "m68k-io"` (zero hits
  both ways), so the force-push and the delete created no cross-
  reference and broke no review.

## Update (2026-09-04): master sync, full rebase, identity change, one new branch

- **`master` synced to `aa26ca67b`** (12 new upstream commits, two of
  which touch `common.run`/`linux.run`). `baseline` rebased onto it,
  and every `claude/*` branch rebased onto `baseline` — no conflicts
  in any of them.
- **All fix commits re-authored to `Alexander Moch
  <mail@alexmoch.com>`**, author *and* `Signed-off-by:`, replacing
  the `m68k.io <noreply@m68k.io>` convention adopted 2026-08-30. Per
  explicit instruction. The `Copyright (c) 2026 by m68k.io` headers
  in the three new `rsend` test files were changed to match, since
  those go upstream with the fix. `claude-meta` deliberately left on
  `m68k.io` — the instruction named the fixes, not the docs branch.
- **New branch `claude/is_kmemleak_false_positive`**: one commit,
  "ZTS: don't mistake a compiled-in kmemleak for a running one".
  Fixes `is_kmemleak()` in `libtest.shlib`, which treated the mere
  existence of `/sys/kernel/debug/kmemleak` as proof the detector was
  live — it is created before the kernel checks whether kmemleak
  actually started, so a `CONFIG_DEBUG_KMEMLEAK_DEFAULT_OFF` kernel
  (Alpine's `linux-stable`) trips it. Full reasoning, kernel-source
  evidence and the CI proof are in `CLAUDE.md`'s 2026-09-04 entries.
  Independent of the Alpine work and upstream-submittable on its own.
- **`claude/lzc_send_wrapper_splice_race` amended**: its third commit
  now registers `send_dest_error` in `linux.run` rather than
  `common.run`. Registering a Linux-gated test in `common.run` was
  the actual cause of the `SKIP rsend/send_dest_error` that earlier
  notes wrongly recorded as correct and by-design. FreeBSD now comes
  back entirely clean.
- **`claude/combined-review` rebuilt, six commits** on the rebased
  `baseline`: `ksh_alpine_prebuilt`, `getopt_long_permute`, the three
  `lzc_send_wrapper_splice_race` commits, and the new kmemleak fix.
  Verified byte-identical to the user's `alpine/combined` on
  `alex-moch/zfs` before results were read.
- **`claude/zfs_get_006_posixly_correct`** rebased and pushed along
  with the rest, still the unused alternative to
  `getopt_long_permute`, still not deleted.
- 34 cancelled workflow runs deleted from `m68k-io/zfs`; failed runs
  kept for comparison history.

## Update (2026-09-04, later): getopt commit message corrected

- **`claude/getopt_long_permute` message rewritten**, code untouched.
  Three factual errors fixed: it claimed the change affects `zfs
  unmount`/`unshare` (those route through `unshare_unmount()`, which
  uses plain `getopt()` and is not modified); it cited an upstream
  issue URL for a skip that is actually the kmemleak false positive;
  and it called `send-c_stream_size_estimate` a "pre-existing
  unrelated issue", which it is not — that is the bug the send-relay
  commits fix.
- **`claude/combined-review` rebuilt** on the corrected commit. Diffed
  against the CI-validated tree beforehand: byte-identical, so the
  full-matrix validation still stands and the re-triggered runs were
  cancelled rather than spent again.
- **The `alex-moch/zfs` copy of that commit still carries the old
  message**, and the upstream issue links straight to it. Correcting
  it there means cherry-picking the corrected commit and rebuilding
  `alpine/combined`; the tree does not change, so CI stays green. The
  user is aware and chose to leave it for now.

## Update (2026-09-15): master resync, new branch `claude/kmemleak_alpine`

- **`master` fast-forwarded 90 commits to `44aa82a6c`**, `baseline`
  rebased onto it and force-pushed. One conflict: upstream added
  `quick`, `linux` and `freebsd` cases to `zfs-qemu.yml`'s
  `os_selection` switch, which the `**DEBUG**` commit deletes wholesale.
  Resolved in favour of the DEBUG intent — those cases are gone on
  this branch and everything falls through to the six-runner default
  list that includes `alpine3-24`. Worth re-checking on the next
  resync, since upstream's real lists keep growing and the fork's
  restriction silently discards them.

- **New branch `claude/kmemleak_alpine`**, two commits on `baseline`:
  - *"ZTS: fix test-runner crashing immediately under -m"* — restores
    the `sh` dropped from the `scan=0` invocation in a 2022 cleanup,
    which has made `-m` unusable ever since. One word, and
    independently upstream-submittable: it is a real bug on every
    platform, nothing to do with Alpine.
  - *"CI: turn on kmemleak leak checking for the Alpine runner"* —
    appends `kmemleak=on` to `default_kernel_opts` in the deps step
    that already switches Alpine to the `-stable` kernel and already
    relies on the poweroff/boot before the build, then passes `-m` to
    `zfs-tests.sh` on `alpine*` in `qemu-6-tests.sh`. The cmdline
    rewrite sources the config to read the existing options back
    rather than pattern-matching their spelling; tested against both
    quoted and unquoted forms of `default_kernel_opts`.

  The two changes are useless apart: the boot flag alone gets a slower
  kernel with no reporting, and `-m` alone has nothing to report on.
  The predicate fix is deliberately *not* in this branch — it is a
  separate PR and, with kmemleak genuinely on, changes nothing
  observable here.

- **The commit messages carry no `Fixes:` line** for the commit that
  broke `-m`, per the standing no-cross-references rule, even though
  upstream would normally want one on a fix of this shape. Flagged to
  the user; their call before it goes upstream.

- **What the first run measures**: whether a kmemleak-enabled ZTS run
  fits inside GitHub's 6h job cap, and how much false-positive noise
  ZFS generates now that every non-empty report is a FAIL. Neither
  number is knowable from the source.

## Update (2026-09-15, later): two new branches, one experiment running

- **`claude/kmemleak_alpine` gained a third commit.** "ZTS: look for the
  kmemleak file the way it is later used" — the `-m` existence check
  used `os.path.exists()` on a 0700 debugfs as an unprivileged user, and
  then, once that was spelled with sudo, depended on `test(1)`, which is
  not in the constrained PATH the suite builds from `commands.cfg`. It
  now uses `sudo -n sh -c "test -e …"` and reports sudo's own stderr on
  failure, since the previous version's `capture_output=True` was why
  the first failed run explained nothing. The commit was amended rather
  than stacked, because the earlier version was simply incomplete.

- **New branch `claude/kmemleak_balanced`** — the experiment. **It
  failed: the step hit the 330-minute cap and the job finished at 5h
  58m 51s of the 6h ceiling.** `claude/kmemleak_alpine` plus a
  cherry-pick of the upstream
  draft that splits tests across the two VMs by measured runtime instead
  of count, plus two commits: raising the ZTS step timeout to 330
  minutes, and a `**DEBUG**` commit restricting the matrix to
  `alpine3-24` so six jobs at up to six hours each do not hit this
  account's concurrency limits. Drop that last one before the branch
  goes anywhere.
  - Running the new `split_tags()` locally and pricing both halves
    against baseline per-test timings predicts **1075 tests / ~5:16** and
    **1047 tests / ~4:35**. So it should finish with roughly 14 minutes
    of margin, and the ~40 minute imbalance that eats the margin is the
    timing-database effect: the database is built from runs without
    kmemleak. Watch out — if the slower VM ever did use the full 330,
    the job would sit at 355 minutes with only ~5 left for artifact
    collection before the six-hour ceiling, and the artifacts would be
    lost.
  - **Outcome.** The test-count prediction was exact — vm2 ran 1047 —
    and both time predictions were too low. vm2 took **4:58:24**
    against 4:35 predicted; vm1 never finished and projects to
    **~6:10** against 5:16 predicted. The error is in the same
    direction for both, so the per-test kmemleak weighting used to
    price the halves is systematically light on this workload; do not
    reuse it without recalibrating. Artifacts did survive, because the
    step cap fired 78 seconds before the job ceiling rather than after
    it. Full analysis in `claude-notes/INVESTIGATIONS.md`, cluster 9.
  - The branch keeps its value as a measurement, not as something to
    submit. What upstream needs from it is the finding — a perfect
    split still lands ~3 minutes over — not the commits, two of which
    (the 330-minute cap and the `**DEBUG**` restriction) exist only to
    run the experiment.

- **New branch `claude/zio_crypt_key_unwrap_leak`** — one commit,
  "zio_crypt: free the key unwrap uios when decryption fails", on
  `baseline`. Three lines moved: release the uios as soon as the crypto
  call returns, then test the result. Fixes a leak that is reachable
  from userland by repeating `zfs load-key` with the wrong passphrase.
  Full reasoning, the kmemleak evidence and the before/after numbers are
  in `CLAUDE.md`'s 2026-09-15 entries. Independent of all the Alpine
  work and upstream-submittable on its own — and worth submitting
  promptly, since the bug reached master only a day earlier and has
  never been in a release.
  - **The commit message carries no reference to the commit that
    introduced it**, per the standing rule. Upstream would normally want
    a `Fixes:` line on a fix of this shape; that is the user's call
    before submitting.

- **A worktree at `~/Development/zfs-meta`** was added so documentation
  could be committed while a ZTS run held the main checkout. Remove it
  with `git worktree remove` when it is no longer wanted.

## Update (2026-09-15, evening): two PRs open, one more branch

- **Two PRs opened upstream by the user**, both deliberately small
  enough not to need further testing:
  - the `zio_crypt_key_unwrap` leak fix, byte-identical to what was
    verified here (204 leaked objects to 0);
  - the missing `sh` in the `-m` `scan=0` invocation.
  - **The second one is not sufficient on its own, and the user knows
    it.** `kmemleak_cb` runs during `parse_args()`, long before the
    line that PR fixes, and its `os.path.exists()` check fails for any
    unprivileged caller — which is how `zfs-tests.sh` and the CI start
    the suite. So `-m` still dies first, in exactly the way the second
    CI run demonstrated; the PR only helps when the suite is run as
    root. The user chose to upstream it anyway as an obviously-correct
    one-word fix and let the rest follow later. The companion fix is
    the third commit on `claude/kmemleak_alpine`, ready whenever they
    want it.

- **New branch `claude/mount_loopback_losetup_show`** — one commit on
  `baseline`, pushed, matrix run cancelled on sight, checkstyle left to
  run. Takes the loop device name from `losetup --show -f` instead of
  attaching and then looking it up, which on Alpine fails for any
  device past the first eight. Full root cause and the cascade it
  caused are in `claude-notes/INVESTIGATIONS.md` as cluster 8.
  Upstream-submittable on its own and unrelated to everything else in
  flight.

- **Submission state of the three ready branches**, none dependent on
  each other: `zio_crypt_key_unwrap_leak` (PR open, checkstyle green),
  `mount_loopback_losetup_show` (ready), and `claude/kmemleak_alpine`'s
  third commit (ready, is the companion PR 19117 needs).

- **Convention worth keeping**: pushing a fix branch triggers a
  six-job matrix that competes with any long experiment for the
  account's concurrency. The pattern settled on is push, cancel the
  `zfs-qemu` run within seconds by polling `gh run list --branch`, and
  leave `checkstyle` running — it is cheap and it is what validates
  cstyle and the 72-character commit message limits before a PR goes
  out. Poll on the branch, not on a short SHA: the runs API needs the
  full 40-character hash and silently returns nothing for an
  abbreviated one, which caused a duplicate full-matrix run earlier in
  the day.

- **`claude/alpine_boot_time`** (2026-09-17) -- the Alpine CI
  investigation branch, on top of `claude/combined-review` rather than
  `baseline`, so its runs carry the seven real fixes and the test
  phase is meaningful instead of noisy. Nine commits, clean ones
  first so they cherry-pick out:
  - `CI: report how long a VM takes to answer` -- prints the elapsed
    wait in `qemu-wait-for-vm.sh`. Every platform, every run.
  - `CI: keep the build VM's console log` -- captures vm0's serial
    console the way the testing VMs' already are. Nothing recorded the
    build VM's boot before this.
  - `CI: stop cloud-init stalling every Alpine boot` -- the one-line
    `rc-update del cloud-init-local boot`. Worth about five minutes a
    job.
  - `CI: name the Alpine runners by firmware, and add 3.23` -- four
    variants, `alpine3-{23,24}-{bios,uefi}`, image derived from the
    name, secure boot disabled for uefi.
  - `CI: let the Alpine uefi image take the grub path` -- one glob
    narrowed to `alpine*-bios`, extlinux edits scoped to bios.
  - Four `**DEBUG**` commits on top: drop clang (3.23 has no clang22),
    report `AT_MINSIGSTKSZ`, mask AMX, restrict the matrix to the four
    variants.

  Naming note: an earlier draft kept `alpine3-24` unsuffixed and
  extracted an `edit_grub_cmdline` function so uefi could reuse it.
  The explicit `-bios`/`-uefi` naming plus a one-token glob change is
  the smaller diff and does not touch a code path every other
  distribution runs through; that is what is on the branch.

## Update (2026-09-18): four PRs open, fixes split out, flake caught

**Five PRs opened upstream**, each a single commit on master. The
earlier branches were based on `baseline`, which would have dragged its
`**DEBUG**` runner-restriction commit into every PR; these are not.

- #19132 `alpine/cloud-init` -- CI: stop cloud-init stalling every
  Alpine boot. Measured 24-27s against roughly five minutes, taken
  where the second boot actually waits rather than from step
  durations, which are swamped by build time.
- #19135 `alpine/losetup` -- ZTS: take the loop device name from
  losetup itself. Also verified green on almalinux10, debian13,
  fedora44 and ubuntu26 in an earlier combined-review run, so the new
  `--show` path is exercised on glibc as well as musl.
- #19136 `alpine/kmemleak` -- ZTS: look for the kmemleak file the way
  it is later used. Note its CI passing means "nothing else broke":
  the `-m` path is only reached with kmemleak enabled, which no
  upstream runner does.
- #19138 `alpine/dropTestCases` -- ZTS: zfs_get_006_neg: drop
  argument-ordering cases.

- #19139 `alpine/diffutils` -- CI: install diffutils on the Alpine
  runner. A no-op on 3.24, where the package already arrives
  transitively; it states a requirement the list otherwise leaves to
  chance. The apk list is re-wrapped, and that re-wrap was the only
  untested thing about it -- an earlier attempt split `libcap-utils`
  across a line break, which would have installed two packages that do
  not exist. The 3.24 job in the combined run installs it cleanly.

**Held deliberately.** The three `lzc_send_wrapper` commits need more
scrutiny than the others: they change shipped library code rather than
a test or a CI script. Worth knowing for sequencing --
`send-c_stream_size_estimate` fails *only* on Alpine without them
(almalinux10, debian13, fedora44, ubuntu26 all pass), so enabling the
runner off a master that lacks the fix means a red runner on day one,
with a failure that looks Alpine-specific and is not. Either the relay
PR lands first, or the test goes on the exceptions list, which the
maintainer already offered.

**Superseded.** `claude/getopt_long_permute` is a competing option to
the one #19138 takes, not an independent fix.

**Blocked, not broken.** `claude/ksh_alpine_prebuilt` waits on moving
the package under the OpenZFS organisation, which the maintainer
raised himself. Its filename also hardcodes `alpine3.24`; fix that
while moving it.

### The maintainer's reply, and what it unblocked

kmemleak is explicitly not a requirement: "Let's not let that block
getting Alpine added, running it without kmemleak like all the other
runners is fine." So `claude/kmemleak_alpine`'s enablement commit
stays local, and the possible future home is an optional runner over a
subset of the suite.

That also lapsed the condition holding `zfs_get_006_neg`: the hold was
for the CI-side question to settle, in case a subsetting arrangement
covered those cases anyway. It settled the other way -- full suite, no
kmemleak, no Alpine-specific runfile -- so nothing will cover them
incidentally. Note this is not the maintainer deciding the question;
he leaned that way and so did we.

### Sequencing from here

Get the PRs accepted, clean up branches, re-test CI off the then
master, and post the enablement PR if that is good. ksh93 after. The
re-test is what decides whether the relay PR goes before the
enablement PR or an exception does.

### Working branches

- **`claude/combined-fixes`** -- the six fixes on master with one
  `**DEBUG**` commit restricting the matrix to Alpine 3.23 and 3.24.
  3.23 cannot get past deps there: master's package list pins
  `clang22`, which 3.23 does not have.
- **`claude/configure_flake`** -- on `baseline`, for hunting the
  CONFIG_MODULES failure. Skips the test stages and gives the same
  image ten names, so one run is ten samples at about sixteen minutes
  each rather than one at four hours. This is what caught it.
- **`claude/alpine_boot_time`** -- the uefi work, now with the three
  fixes that made those runners boot and test, plus `-lts` variants
  holding the kernel still across releases, a sparse-send probe, and
  CPU/AT_MINSIGSTKSZ reporting. The `**DEBUG**` commits no longer sit
  strictly on top; harmless for cherry-picking by SHA, worth knowing
  when lifting the clean ones out.

One process note. Pushing a master-based branch to the fork fires
every workflow, because only `baseline` carries the commit that
rewrites the other workflows' triggers to `workflow_dispatch`. One
push cost 35 runs to cancel. Branches meant for test runs belong on
`baseline`; branches meant for PRs belong on master and should be
pushed when you are ready for that.
