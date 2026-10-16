# OpenZFS on Alpine — CI enablement project

## Goal

Get the GitHub Actions **Alpine CI runner** (`zfs-qemu.yml`, matrix entry
`alpine3-24`) passing the ZFS Test Suite (ZTS) on this fork,
`https://github.com/m68k-io/zfs`. Upstream is `openzfs/zfs`; `master` here
tracks upstream `master`.

## Working principles

- **Note-taking: keep `CLAUDE.md` trimmed to current status; new
  investigation/history/reports go in `claude-notes/`.** This file
  regrew to 1776 lines once before (split out 2026-08-26, see
  `claude-notes/INVESTIGATIONS.md`'s intro for the full rationale) by
  letting historical narrative accumulate at the bottom under the
  frequently-read status section. Going forward:
  - A **new failure cluster's root-cause writeup** (the kind of deep,
    multi-paragraph investigation clusters 1-7 got) is an addition to
    `claude-notes/INVESTIGATIONS.md`, not `CLAUDE.md` — even if the
    investigation happens in a session focused on "current status."
  - A **new `claude/*` fix branch** gets its entry in
    `claude-notes/BRANCHES.md`, not `CLAUDE.md`.
  - A **one-off real-CI run's pass/fail analysis** (mapping failures to
    known fixes/clusters, the kind of thing `CI-RUN-2026-08-25-master.md`
    is) gets its own new dated file,
    `claude-notes/CI-RUN-<YYYY-MM-DD>-<short-description>.md` — never
    appended to an existing report (those are point-in-time snapshots,
    not logs) and never folded into `CLAUDE.md` (it goes stale as fixes
    land, which is fine for a dated snapshot but wrong for an evergreen
    file).
  - `CLAUDE.md` itself only gets: updates to "Current status / next
    steps" (edit in place, don't just append — retire/trim entries once
    they're resolved and reflected in `claude-notes/`), corrections to
    working principles, and genuinely new environment/build-setup facts.
  - New files under `claude-notes/` need no `.gitignore` change (the
    whole directory is allowlisted) — but a brand-new *root-level* meta
    file would, same as `CLAUDE.md` was before this convention existed;
    prefer putting it in `claude-notes/` instead of adding another root
    exception.
- **Small, targeted fixes.** One narrow cause per branch/commit, same
  shape as the existing `claude/*` branches (one file, one root cause,
  one commit each).
- **Commit message subject line AND body lines must each be ≤72 chars.**
  `checkstyle`'s `commitcheck` enforces both independently and fails the
  build otherwise. Caught the body-wrap version the hard way on
  `claude/tzdata` (2026-08-23); caught the *subject*-length version
  separately on `claude/ksh_alpine_prebuilt` (2026-08-27, error text is
  literally `commit subject over 72 characters`) — two distinct checks,
  don't assume fixing one covers the other. Check both before pushing.
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
- **Git identity convention (superseded 2026-08-30)**: everything in
  this fork — upstream-bound fixes and meta/docs commits alike — is
  authored, committed and signed off as `m68k.io <noreply@m68k.io>`.
  This replaces the earlier split convention (`Alexander Moch
  <mail@alexmoch.com>` for fixes, `Claude <noreply@anthropic.com>` for
  meta commits), which the user retired; neither of those identities
  should be used now. No default git identity is configured repo-wide —
  set it explicitly per commit (e.g. `git -c user.name=...
  -c user.email=... commit ...`). Note `scripts/commitcheck.sh`
  requires a well-formed `Signed-off-by: Name <email>` line and
  enforces **both** the subject and every body line at ≤72 chars; run
  it per commit before pushing.
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


## Where things live

This file covers goals, working principles, local environment/build
setup, and current status. Two related files, split out on
2026-08-26 to keep this one focused:

- `claude-notes/BRANCHES.md` — inventory of every `claude/*` fix
  branch in this fork: what each one does, its commit, and its
  upstream PR/merge status where applicable.
- `claude-notes/INVESTIGATIONS.md` — the full root-cause narrative
  for every failure cluster (1-7), local validation results, and
  real CI run summaries from the original triage.
- `claude-notes/CI-RUN-*.md` — dated snapshots mapping one specific
  real-CI run's failures to known fixes/PRs/clusters. These go
  stale as fixes land; check current PR/branch state before
  trusting an old one.

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
  ago. Remaining six branches (was seven;
  `send_progress_race` withdrawn 2026-08-30): user will submit them
  personally once the first batch merges — not something to pick up
  unprompted.
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
      - **Resolved (retired 2026-10-11).** This bullet recorded that
        the 2026-08-24 version of `claude/lzc_send_wrapper_splice_race`
        still failed `send-c_stream_size_estimate` on real CI. That
        version's resync re-did the rewind (fixed 2026-08-30), and the
        side-by-side run of 2026-09-04 below shows the test passing
        with the branch and failing without it. Left in place this
        long, it read as an open contradiction; it was not one.
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
- **Retired (was: "Real bug found and fixed in
  `claude/send_progress_race`", 2026-08-24).** The branch itself was
  withdrawn 2026-08-30 as a misdiagnosis and deleted, so its CI
  follow-up is moot; full history is in `claude-notes/`. The one
  durable lesson from it, which applies to any core-code change here:
  a bare `(void) write(...)` does **not** silence `-Wunused-result`
  for glibc's fortified (`-D_FORTIFY_SOURCE=3`) `write()`, so
  `-Werror` turned it into a hard *build* failure on every glibc CI
  target while musl built it clean — invisible to all local Alpine
  testing. Capture the result in a `__maybe_unused` variable instead,
  the idiom already used in `lib/libspl/backtrace.c` and
  `cmd/zstream/zstream_backtrace.c`. Second lesson: that branch's run
  was recorded as `PASS` from the ZTS result alone while the run's own
  build had failed on 3 of 6 platforms — read the run conclusion, not
  just the test result.
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
- **PR tracker, superseded — see the 2026-09-02 update below for
  current status.** (2026-08-27 snapshot, kept for history) — every
  `claude/*` fix branch's upstream
  status as of this writing (see `claude-notes/BRANCHES.md` for the
  per-branch technical detail; this is just the submission status):
  - **Merged**: `alpine_ci_deps` (`#18988`), `mmp` (`#18979`),
    `linux-stable-kernel` (`#18980`), `history_uncompress` (`#18981`),
    `getopt_permute`/`mmp_write_uberblocks` (`#18994`),
    `procfs_stale_read_portable` (`#18998`, merged as "accept Alpine's
    EIO error message" — same fix, reworded during review),
    `user_namespace` (`#18999`), `exec_001_pos_multicall` (`#19000`).
    Fork's `master` synced and `baseline` rebased onto it (2026-08-27)
    now that all of these have landed; all eight corresponding
    `claude/*` branches deleted, local + `origin`.
  - **Closed/withdrawn**: `get_prop_empty_value` (`#18983`).
  - **No PR yet**: `dnode_rele_uaf` (cluster 4), `getopt_long_permute`
    (`zfs_get_006_neg`, new this session), `mkbusy_kill_race`,
    `lzc_send_wrapper_splice_race` (three commits as of 2026-08-30),
    `ksh_alpine_prebuilt` (new this session — see below; not
    upstream-submittable as-is since it depends on a personal fork's
    GitHub release, see its own commit message).
  - **Cluster 5's real fix lives on the sibling `~/Development/ksh`
    fork** — see that project's own `CLAUDE.md`. Both fixes
    (`sh.save_env` dangling pointer, `staknam()` stale `sh.strbuf`
    pointer) sit on that fork's `zfs` branch, confirmed via real CI to
    resolve cluster 5, still **not yet submitted to `ksh93/ksh`**
    (deliberately deferred). **Only the `save_env` fix is load-bearing
    for CI** — the `staknam` fix was actually disproven as the trigger
    (deployed alone first, crashes continued identically) and has no
    reproducer at all, it's real hardening found by static analysis
    against the documented `sfstruse(3)` contract. Both are still
    bundled on the `zfs` branch since `staknam`'s fix is harmless to
    include.
    **ksh release updated (2026-08-27)**: now publishes three assets
    per release — dynamic tarball, static tarball, and an `.apk`
    (recommended: `apk add --allow-untrusted ./ksh93-alpine3.24-
    x86_64.apk`, cleanly upgradeable/removable unlike a bare tarball
    extract) — tagged separately for the `1.0` branch (`alpine-1.0-*`,
    marked *Latest*, what `releases/latest/download/...` resolves to)
    and `dev` (`alpine-dev-*`, pre-release). The old single-tarball
    `releases/latest/download/ksh93-alpine3.24-x86_64.tar.gz` URL
    still resolves correctly under the new release too.
    **Wired in as a real branch, not a DEBUG commit
    (2026-08-27)**: `claude/ksh_alpine_prebuilt` permanently swaps
    `qemu-3-deps-vm.sh`'s Alpine `ksh93` install step from "clone
    `ksh93/ksh` branch `1.0` and build from source" to installing the
    prebuilt `.apk`. This was a `**DEBUG**` commit on `claude/
    combined-review-10` before; promoted to its own real commit since
    it's a legitimate fix for this fork's own CI, not a throwaway
    validation hack — see the commit message on that branch for why it
    still isn't upstream-submittable to `openzfs/zfs` as-is (depends on
    a personal fork's release).
  - **Cluster 4 (zdb/dbuf teardown crash, BRT/DDT) fixed 2026-08-26,
    still validating cross-platform.** Root cause, local ASAN
    confirmation, and the original 74/74-PASS real-CI validation are
    unchanged — see `claude-notes/INVESTIGATIONS.md`. Fix branch:
    `claude/dnode_rele_uaf`, rebased onto the new `baseline`
    (2026-08-27). Real upstream-matrix run on the separate `alex-moch/
    zfs` final-QA repo (`33009036571`, `alpine/combined-review`,
    19-platform matrix): **16/19 platforms passed clean**; 3 failed on
    infra timeouts, not correctness (`ubuntu22`: `Run tests` timed out
    at 270 min; `centos-stream9`/`centos-stream10`: `Build modules`
    timed out at 30 min) — no cluster-4 signature or any other
    correctness failure in any of the three timeout logs.
    **Submitted upstream from `alex-moch/zfs`'s `alpine/dnode_rele_uaf`
    branch, open for review since 2026-08-30** (deliberately not
    written as a bare issue/PR number or head SHA here — see the
    git-identity working principle above on why). The PR itself is
    still at the pre-review commit; none of what follows has been
    pushed there yet. `ryao` approved; `behlendorf` (lead maintainer)
    suggested moving the assert whole to before `mutex_exit()` *and*
    dropping the `#ifdef ZFS_DEBUG` guard around it. The first half is
    incorporated and correct. **The second half was wrong and briefly
    shipped anyway**: `zrl_owner()` is declared only under `ZFS_DEBUG`
    in `zrlock.h` (checked via `grep`, which found the matching line
    but not the `#ifdef`/`#endif` two lines around it, so the check
    looked complete but wasn't) — dropping the guard broke
    `checkstyle`'s non-debug kernel module build with an implicit-
    declaration error, caught for real on `m68k-io/zfs` CI
    (2026-09-02), not by any local build (every local build here uses
    `--enable-debug`). Guard restored to exactly upstream's placement,
    verified this time with an actual `-UZFS_DEBUG` syntax-only
    compile, not just a header read. Commit message corrected to
    match; `claude/dnode_rele_uaf` force-pushed. `claude/combined-
    review-11` still carries the broken intermediate state and needs
    rebuilding — not done, out of scope for now (see the branch's own
    history for why). Full account, including the verbosity trim that
    preceded this: `LEARNING-dnode-rele-uaf.md` §4 and §6 (untracked,
    root of this repo).
  - **`claude/combined-review-11` (2026-08-27)**: replaces the deleted
    `combined-review-9`/`-10`. Six commits on the rebased `baseline`:
    `dnode_rele_uaf`, `getopt_long_permute`, `lzc_send_wrapper_splice_
    race`, `mkbusy_kill_race`, `send_progress_race`,
    `ksh_alpine_prebuilt` — every currently-unmerged fix plus the new
    ksh install branch, all cherry-picked clean. Real-CI results from
    the deleted `combined-review-10` (extracted before deletion, see
    `claude-notes/CI-RUN-2026-08-27-combined-review-10.md`) already
    show clusters 4 and 5 both fully resolved *in combination*: **zero
    core dumps on Alpine**, every previously-crashing test (`zfs_list_
    00[137]_pos`, `zpool_add/create_001_neg`, `alloc_class_013_pos`,
    `block_cloning_copyfilerange*`, ...) passing clean. `-11` itself
    additionally carries the `getopt_long_permute` fix that `-10`
    didn't, so `zfs_get_006_neg` should now pass too where `-10`
    correctly failed it (confirmed separately: `getopt_long_permute`'s
    own isolated run passed `zfs_get_006_neg`, see the CI-RUN file).
  - **Retracted (2026-08-27): the "new, not yet triaged" cluster below
    was a methodology error, not a real finding.** The original
    write-up grepped every raw `[FAIL]` line in the log instead of
    checking ZTS's own `Results Summary` split between "results other
    than PASS that are expected" and "...that are unexpected" (a
    distinction this file's own cluster-4/linux-stable-kernel entries
    already relied on correctly, months earlier — this was a
    regression in method, not a new gap in knowledge). Re-checked
    against a second, independent real-CI run of the same content
    (`alex-moch/zfs` run `33097895692`, Alpine leg, 2026-08-27):
    `casenorm/*`, `import_rewind_device_replaced`, `refreserv_
    004_pos`, `send_xdr_encoding/xdr_resume_bookmark_raw_with_write`,
    and `fault/auto_replace_001/002_pos`+`auto_spare_multiple` are
    **all** in ZTS's own "expected" list, each tied to a real tracked
    upstream issue (`openzfs/zfs#7633`, `#14851`, `#11889`, `#18491`)
    or an explicit "Known issue"/"not guaranteed" note — not flakiness,
    not a regression, just normal ZTS output that a correct read of
    the summary would have filtered out immediately. The **actual**
    single unexpected failure on that run: `events/zed_cksum_reported`
    (vm2 only), immediately preceded in dmesg by `sched: DL replenish
    lagged too much` — looks like VM scheduling contention, not a code
    issue, and it's a single occurrence so far. Per this file's own
    "ZTS is known to be flaky" principle: noted, not chased further
    without a second occurrence. **Lesson**: always read ZTS's own
    expected/unexpected split before treating any `[FAIL]` line as
    signal — grepping raw `[FAIL]` lines produces a majority-false
    "cluster" that looks alarming but is normal, already-tracked
    output.
  - Full annotated mapping of one specific real-CI run's failures to
    all of the above: `claude-notes/CI-RUN-2026-08-25-master.md`
    (older, going stale) and `claude-notes/CI-RUN-2026-08-27-
    combined-review-10.md` (this session's, current as of writing).
  - **Second full-matrix confirmation of `combined-review-11`'s exact
    content (2026-08-27, user-triggered on `alex-moch/zfs`).** Two
    runs, `alpine/combined-review` branch (all six fixes cherry-picked
    onto it, matching `claude/combined-review-11` exactly):
    `33097895692` (6-platform wave) and `33098018148` (10-platform
    wave). **`alpine3-24` came back fully green on the second attempt**
    (0 failures at all, expected or not) — the first attempt's
    `alpine3-24` hit `configure: error: ... CONFIG_MODULES ... no`
    during `Build modules`, a one-off VM/environment fluke (confirmed
    not a package issue: the exact same `linux-stable`/`linux-stable-
    dev 7.1.5-r0` package version had succeeded on this same run's
    other legs hours earlier) — most likely stale VM disk state from
    a re-run reusing a cached image, not reproduced on a clean retry.
    `fedora44`'s one `FAIL` (`send_xdr_encoding/xdr_bookmark_raw_with_
    write`) is tracked (`openzfs/zfs#18491`), same pattern as its
    `_resume_` sibling — confirmed via the actual Results Summary
    "unexpected" section (empty), not a raw `[FAIL]` grep, learning
    the lesson from the retraction above. **4 infra failures in the
    10-platform wave, none correctness-related**: `centos-stream9`/
    `centos-stream10` — `Build modules` timed out at 30 min, root
    cause visible in the log this time (`epel-release` package fetch
    timed out against a slow third-party mirror,
    `mirror.shomepower.com`); `ubuntu22`/`almalinux8` — `Run tests`
    timed out at 270 min. **`ubuntu22`'s 270-min timeout is now a
    repeat** — same platform, same step, same timeout, across two
    independent full-matrix runs (the earlier `33009036571` and this
    `33098018148`) — no longer just one-off noise. Plausible
    explanation, not confirmed: fixing clusters 4/5 means tests that
    used to crash out early (freeing wall-clock time for the rest of
    the suite) now run to full completion instead, so already-
    marginal platforms could be tipping over a fixed timeout budget as
    a side effect of the crash fixes working, not a regression from
    them. Zero cluster-4/5-signature failures across both runs.
- **Branch/CI hygiene pass (2026-08-27)**: user confirmed all four
  previously-open PRs (`#18994`, `#18998`, `#18999`, `#19000`) merged
  and synced this fork's `master`. Rebased `baseline` onto the new
  `master` (trivial — one commit, the permanent `**DEBUG**` runner-
  restriction commit). Deleted the four now-merged `claude/*` branches
  (local + `origin`) after confirming each via `git patch-id` (or, for
  `procfs_stale_read_portable`, by diffing directly against the merged
  commit — the review process reworded its commit message and dropped
  an inline comment, so the patch-id didn't match even though the code
  change is identical). Rebased the five remaining active fix branches
  onto the new `baseline`, force-with-leased. Deleted `claude/
  combined-review-9`/`-10` (superseded by the new `-11`) and 69 stale/
  orphaned workflow runs on `m68k-io/zfs` (old commits on rebased
  branches, and runs whose branch no longer exists at all) — `alex-
  moch/zfs`'s runs were all left alone, nothing there was redundant.
  Cleaned up 19GB of accumulated ZTS test leftovers from `/var/tmp` on
  this VM (confirmed first: no mounted ZFS datasets, no imported pools,
  no attached loop devices, no zfs-related processes — nothing was
  using any of it). `~/Development/ksh`'s unrelated in-progress
  `splice_race.c`/kernel-`do_splice()` investigation (modified
  `CLAUDE.md` + untracked file, see that project) was never touched.
- **Send-relay bugs re-investigated; root cause proven, one branch
  withdrawn (2026-08-30).** Asked to review
  `claude/lzc_send_wrapper_splice_race` and `claude/send_progress_race`
  and say whether the bug was properly fixed. It was not, in either
  branch. The proven mechanism, the corrected fix, and two further bugs
  found in the same function are written up in cluster 6 of
  `claude-notes/INVESTIGATIONS.md`; branch state is in
  `claude-notes/BRANCHES.md`. Headlines:
  - `splice()` with a `NULL` `off_out` writes back the file position it
    latched on entry **even when it moved zero bytes**, rewinding the
    caller's own output. Proven by `strace` and an isolated C repro,
    not inferred.
  - The published fix did not work — its unconditional resync `lseek()`
    re-did the same rewind (200/200 corrupt when actually measured).
    The resync is now conditional on having relayed something.
  - `claude/send_progress_race` was a misdiagnosis: the progress thread
    only ever writes to `stderr`, and the corruption is on `stdout`.
    Branch deleted; tip kept as tag `dropped/send_progress_race`.
  - Two more bugs in `lzc_send_wrapper()`, both pre-existing and both
    now fixed with their own tests: `zfs send >>file` never worked
    (`splice()` rejects `O_APPEND`), and any relay failure killed the
    send with `SIGPIPE` before the real error could be reported.
  - **`claude/combined-review-11` is stale** — it carries the withdrawn
    commit and the superseded fix. Regenerate it before use.
  - Method note worth keeping: the in-tree `zfs` binary loads
    `libzfs_core.so.3` from `/usr/lib` unless `LD_LIBRARY_PATH` points
    at `.libs`. Two A/B runs here silently tested the *installed*
    library before this was caught — always confirm with `ldd` which
    library a validation run is actually exercising.

- **PR tracker update (2026-09-02) — three more merged, fork resynced.**
  `dnode_rele_uaf` (cluster 4), `zstd_asan_decl`, and `mkbusy_kill_race`
  all merged upstream since the last sync -- confirmed via patch-id
  match against the merged commits (`dnode_rele_uaf` matched exactly;
  the other two were reworded slightly during review, confirmed
  functionally identical by checking the actual merged file content
  instead, same pattern as `procfs_stale_read_portable` before). User
  synced this fork's `master`; `baseline` rebased onto it (trivial --
  one commit, the permanent `**DEBUG**` runner-restriction commit),
  force-pushed. The three merged branches deleted, local + `origin`.
  The four remaining active branches (`getopt_long_permute`, `zfs_get_
  006_posixly_correct`, `lzc_send_wrapper_splice_race`, `ksh_alpine_
  prebuilt`) all rebased onto the new `baseline` clean, force-pushed.
  **`claude/combined-review-11` remains stale** (unchanged from the
  note above -- still carries the withdrawn `send_progress_race`
  commit, the pre-review `dnode_rele_uaf` fix, the old single-commit
  `lzc_send_wrapper_splice_race`, and `getopt_long_permute` instead of
  its replacement `zfs_get_006_posixly_correct`) -- **deliberately not
  touched**, per standing instruction to leave that branch alone.
  Current, accurate submission status:
  - **Merged**: `dnode_rele_uaf`, `zstd_asan_decl`, `mkbusy_kill_race`,
    plus everything in the 2026-08-27 snapshot above.
  - **No PR yet**: `getopt_long_permute` (superseded by `zfs_get_006_
    posixly_correct`, see that branch's entry in `claude-notes/
    BRANCHES.md` -- kept around at the user's call, not deleted),
    `zfs_get_006_posixly_correct`, `lzc_send_wrapper_splice_race`,
    `ksh_alpine_prebuilt` (not upstream-submittable as-is, see its own
    commit message).

- **Combined-review branches no longer numbered (2026-09-03).** Going
  forward there is exactly one `claude/combined-review` branch,
  force-pushed/rebuilt as needed rather than incremented
  (`-9`/`-10`/`-11`) each time -- per explicit instruction. The old
  `claude/combined-review-11` (stale, see the note above) deleted,
  local + `origin`, along with its and the meanwhile-merged
  `dnode_rele_uaf`/`zstd_asan_decl`/`mkbusy_kill_race` branches'
  orphaned workflow runs (8 total).
  `claude/ksh_alpine_prebuilt` updated: the `m68k-io/ksh` release it
  pointed at is gone (fork deleted); now installs the new vanilla
  `alex-moch/ksh` `v1.0.10` release instead (see that repo's own
  release notes -- built from the plain upstream tag with Clang, no
  patches, verified static/dynamic + apk variants all pass `bin/
  shtests` clean). This means the fork's Alpine CI **no longer
  installs a ksh with cluster 5's fixes** -- whether that bug is even
  reachable on 1.0.10 specifically was never conclusively established
  (see `claude-notes/BRANCHES.md`), and the patched-ksh release this
  depended on no longer exists. If cluster 5 resurfaces on CI, this is
  why.
  `claude/combined-review` rebuilt from `baseline` with the two
  remaining unmerged branches: `claude/ksh_alpine_prebuilt` and
  `claude/getopt_long_permute` (the forced-`+` product-code fix,
  deliberately chosen over `claude/zfs_get_006_posixly_correct` for
  this branch -- the latter stays as a separate, unused alternative,
  not deleted) and `claude/lzc_send_wrapper_splice_race` (all three
  commits). Five commits total on `baseline`, all cherry-picked clean,
  build verified.

- **`alpine/combined` on `alex-moch/zfs` confirmed fixed (2026-09-03).**
  The missing-new-file checkstyle failure (previous entry) was
  specific to how the send-relay commits landed there, not a bug in
  `claude/lzc_send_wrapper_splice_race` itself -- re-applied via
  `git cherry-pick` of the exact commits from `m68k-io/zfs` (not a
  manual/patch-based re-creation), author reset to Alexander Moch,
  `Signed-off-by:` line corrected to match. `checkstyle` now passes
  clean (12m10s). `zfs-qemu`'s `alpine3-24` leg hit the same
  `CONFIG_MODULES` stale-VM-state flake documented earlier this
  session (unrelated to any code change, same signature as before);
  the other 5 platforms were still running as of this check.

- **`alpine/combined` zfs-qemu results, as they land (2026-09-03).**
  `alpine3-24`: failed, same `CONFIG_MODULES` stale-VM infra flake as
  before -- not a regression. `freebsd15-1r`: failed, but the entire
  "unexpected" result list (both VMs) is exactly one line -- `SKIP
  rsend/send_dest_error (expected PASS)` -- and that test is
  deliberately Linux-gated (`log_unsupported`) since it exercises the
  `splice()`-based relay, which is Linux-only; it just isn't in a
  "known expected" mask yet since it's a brand-new test. Not a
  regression either. `almalinux10`/`ubuntu26`/`fedora44`/`debian13`
  still running as of this check.

- **Rebase re-run confirms it (2026-09-04).** After the branch got
  rebased and re-pushed, `checkstyle` passed again clean, and
  `freebsd15-1r` reproduced the exact same, and only, result:
  `SKIP rsend/send_dest_error` -- confirms this is a stable, correct,
  by-design result, not a fluke. Other platforms still pending.

- **Two more platforms in (2026-09-04).** `alpine3-24`: built clean
  this time (no repeat of the `CONFIG_MODULES` flake, confirming it
  really was a one-off VM-state issue). Only unexpected result: `SKIP
  cli_root/zfs_get/zfs_get_009_pos` -- unrelated to anything here,
  fallout from upstream's own `06d334b9e` "drop stale expected-failure
  masks" (already in our synced baseline) removing this test's mask
  based on glibc-only testing; that commit's own message admits it
  isn't proof against other platforms. `zfs_get_006_neg` itself
  **passed**, confirming `getopt_long_permute` works here too.
  `debian13`: one real FAIL, `fault/auto_spare_001_pos` (ZED/`zinject`
  hot-spare fault injection) -- unrelated to any of the three fixes
  in this branch, only failed on one of two VMs, matches ordinary ZTS
  flakiness rather than a regression. `fedora44`/`almalinux10`/
  `ubuntu26` still pending.

- **`alpine/combined` full-matrix validation complete, branch looks
  solid (2026-09-04).** All 6 platforms + checkstyle done. `ubuntu26`
  fully clean. Every other platform's unexpected results are single-
  occurrence, single-VM failures in subsystems this branch doesn't
  touch: `fault/auto_spare_001_pos` (debian13, hot-spare/ZED fault
  injection), `zpool_split_resilver` (fedora44), `log_spacemap_
  flushall` + `zed_synchronous_zedlet` (almalinux10, two unrelated
  areas) -- no common thread among them, consistent with ordinary ZTS
  background flakiness rather than a regression. `alpine3-24`'s only
  finding is the already-explained stale-mask fallout on `zfs_get_
  009_pos`; `zfs_get_006_neg` itself passed, directly confirming
  `getopt_long_permute`. `freebsd15-1r` reproduced its expected `send_
  dest_error` skip a second time (stable). All three new `rsend` tests
  passed on every platform that ran them, confirming `lzc_send_
  wrapper_splice_race`. **Conclusion: `claude/combined-review` (ksh_
  alpine_prebuilt + getopt_long_permute + lzc_send_wrapper_splice_
  race) is validated clean across the real upstream CI matrix.**

- **Upstream sync, full rebase, single identity (2026-09-04).**
  `master` synced from upstream to `aa26ca67b` (12 new commits, two
  of which touch `common.run`/`linux.run`); `baseline` rebased onto
  it; all six `claude/*` branches rebased onto `baseline`, no
  conflicts anywhere. **All fix commits re-authored to `Alexander
  Moch <mail@alexmoch.com>`** -- author *and* `Signed-off-by:` --
  replacing the `m68k.io <noreply@m68k.io>` convention that had been
  in force since 2026-08-30, per explicit instruction. Same
  correction applied to the `Copyright (c) 2026 by m68k.io` headers
  in the three new `rsend` test files, since those carry the identity
  upstream too. This docs branch is deliberately left on `m68k.io`:
  the instruction named the fixes, not the meta branch.

- **The `send_dest_error` FreeBSD skip was our bug, not by design --
  the two entries above are wrong (2026-09-04).** Both earlier
  entries call `SKIP rsend/send_dest_error` on `freebsd15-1r`
  correct, by-design, "just isn't in a known expected mask yet", and
  treat reproducing it as *confirmation*. It was actually a defect in
  the branch. The test is Linux-gated for a real reason (it exercises
  the Linux-only relay), but it was registered in
  `tests/runfiles/common.run`, so FreeBSD ran it and correctly
  reported the skip as unexpected. Linux-only tests belong in
  `linux.run`, which already carries a `[tests/functional/rsend:
  Linux]` section. Moved it there, folded into the commit that adds
  the test rather than tacked on afterwards. `freebsd15-1r` now
  returns **completely empty unexpected sections on both VMs**, and
  `send_dest_error` appears in the whole job log exactly once, in the
  `install -c` line -- installed, never run. Lesson worth keeping: a
  result reproducing stably is evidence it is *deterministic*, not
  evidence it is *correct*.

- **`zfs_get_009_pos`: root cause found, and it is not the stale mask
  (2026-09-04).** The entries above blame the `SKIP` on upstream's
  `06d334b9e` dropping this test's expected-SKIP mask. That is only
  the reason it became *visible*. The actual cause: the test
  self-skips via `is_kmemleak`, which was `is_linux && [ -e
  /sys/kernel/debug/kmemleak ]` -- and `kmemleak_late_init()` creates
  that debugfs file *before* it checks whether the detector came up.
  Alpine's `linux-stable` kernel is
  `CONFIG_DEBUG_KMEMLEAK=y` **plus**
  `CONFIG_DEBUG_KMEMLEAK_DEFAULT_OFF=y`, booted without
  `kmemleak=on`, so it prints "Kernel memory leak detector disabled"
  and leaves the file behind. The predicate has been reporting a
  compiled-in-but-dead kmemleak as a live one. Two collateral
  victims: `send_realloc_files` and `send_realloc_encrypted_files`
  use the same helper to *reduce their workload*, so on Alpine they
  were quietly running 100 files over 2 passes instead of 300 over 3
  -- passing, and therefore never noticed.
  Fixed on `claude/is_kmemleak_false_positive`: keep the file as a
  cheap precondition, then confirm liveness via `/proc/slabinfo`.
  `kmemleak_init()` returns ahead of creating the `kmemleak_object`
  slab cache when disabled, and `SLAB_NOLEAKTRACE` is in
  `SLAB_NEVER_MERGE`, so that cache exists under its own name exactly
  when kmemleak was started. Where slabinfo cannot be read it falls
  back to the file alone -- assuming kmemleak is on only costs
  coverage, assuming it is off risks the timeout the skip exists to
  avoid. Verified against real kernel source in
  `/home/claude/Development/linux` (both the debugfs-before-check
  ordering and the `SLAB_NEVER_MERGE` membership), and against this
  box's own running kernel: old check said ENABLED, new check says
  disabled.
  - **The asymmetry recorded here is closed (2026-09-16).** For a long
    time only the *negative* case was measured and the *positive* one
    rested on reading `mm/kmemleak.c`, because no kmemleak-enabled
    kernel was available. This box has now been booted `kmemleak=on`
    and all three branches have a measurement behind them: detector
    off, old says ENABLED and new says disabled; detector **on**, both
    say ENABLED, with `kmemleak_object` showing 1.56M live objects in
    `/proc/slabinfo`; slabinfo unreadable, the fallback returns
    enabled as documented. Note what the two CI kmemleak runs do *not*
    prove -- `zfs_get_009_pos` skipped in both, but those branches
    carry the `-m` fixes and the enablement commit, not this
    predicate, so that skip came from the old `[ -e ... ]` test and
    says nothing about the new one. Worth stating in the PR
    description, since "verified against a live detector" is exactly
    what a reviewer will ask for.

- **`claude/combined-review` is now six commits (2026-09-04),** the
  five from before plus the kmemleak fix, all on the rebased
  `baseline`. The kmemleak fix was folded in deliberately: it is the
  branch that actually gets matrix-validated, and including it is
  what proves `zfs_get_009_pos` runs rather than skips.

- **Validation: `alex-moch/zfs` `alpine/combined` vs `alpine/baseline`,
  side by side (2026-09-04).** Running the reference branch as a
  control alongside the fix branch is what made this round
  conclusive, and is worth repeating. `alpine/baseline`'s
  `alpine3-24` (plain master, no fixes) reported exactly:
  `FAIL zfs_get_006_neg`, `SKIP zfs_get_009_pos`,
  `FAIL send-c_stream_size_estimate`. `alpine/combined` on an
  identical tree to `claude/combined-review` (verified byte-identical
  before reading any results) came back **fully clean, every
  unexpected section empty on both VMs**. Per-test, combined vs
  baseline: `zfs_get_006_neg` `[00:00] PASS` vs `FAIL`;
  `zfs_get_009_pos` **`[03:08] PASS` vs `[00:00] SKIP`**;
  `send-c_stream_size_estimate` `PASS` vs `FAIL`; all three new
  `rsend` tests `PASS`; `send_realloc_files` **`[01:04]` vs
  `[00:06]`** and `send_realloc_encrypted_files` **`[01:18]` vs
  `[00:07]`**.
  The durations are the real evidence, not the verdicts.
  `zfs_get_009_pos` taking 3m08s where the commit that added the skip
  recorded **55 minutes** under a live kmemleak confirms the detector
  genuinely is not running, exactly as the new predicate claims --
  and it fits inside the ZTS timeout with room to spare. The ~10x
  jump in the two `send_realloc` tests is the restored full workload.

- **Flakes seen this round (2026-09-04).**
  `delegate/zfs_allow_003_pos` (FAIL on one m68k-io run, PASS on both
  `alex-moch` branches on an identical tree) and `fedora44` failing
  twice before passing on re-run. Neither touches any subsystem the
  six commits change.
  **Correction, same day**: `send-c_stream_size_estimate` was briefly
  listed here as a third flake. It is not. Baseline FAIL -> combined
  PASS is the *fix working*: the "don't let the send relay rewind the
  output fd" commit addresses precisely this test's corruption, where
  `splice()`'s latched-offset write-back rewinds the fd on a dry run
  and the `size` line lands on top of the `full` line. Root-caused
  10/10 deterministically (cluster 6 in `INVESTIGATIONS.md`); calling
  it flaky read a fix as noise, in the one direction that would have
  hidden a working fix.

- **The prebuilt-ksh93 step is a new single point of failure
  (2026-09-04, unresolved).** `m68k-io`'s `claude/combined-review`
  `alpine3-24` job died with `curl: (28) Failed to connect to
  github.com:443 after 134277 ms` inside the `Install ksh93
  (prebuilt)` group, after which `Install dependencies` wedged for
  its full 60-minute timeout and both VMs became unreachable. Alpine
  mirrors had installed 380 packages seconds earlier, so it was
  github.com specifically. Tests never ran -- infra, not a
  regression, but *our* step: `qemu-3-deps-vm.sh` does a single
  unretried `curl -fLO` against github.com during VM setup, where the
  from-source path it replaced never reached github.com at all.
  Adding `--retry 3 --retry-all-errors --retry-delay 5
  --connect-timeout 30` would bring it in line with the rest of the
  setup script. **Offered, not yet done.**

- **Housekeeping (2026-09-04).** Deleted all 34 cancelled workflow
  runs on `m68k-io/zfs` (`alex-moch/zfs` had none); the failed runs
  are kept, they carry comparison history. Still open, all offered
  and awaiting a call: the `curl` retry above; the
  `getopt_long_permute` commit message's now-stale line citing issue
  `#5479` as an "unrelated expected SKIP" (it is the kmemleak false
  positive, and it puts an upstream issue URL in a commit message);
  and submitting the unmerged fixes upstream.

- **Upstream issue opened: `openzfs/zfs#19052`, "The Alpine Linux CI
  Runner does not pass the ZFS Test Suite (yet)" (2026-09-04).** The
  user drafted it from a draft of mine, trimmed it heavily, and posted
  it under their own account. Live and unanswered as of this writing.
  A framing correction found while writing it, worth keeping: **Alpine
  is not in upstream's default CI matrix at all.** The support is
  merged (`qemu-2-start.sh` knows `alpine3-24`, `qemu-3-deps-vm.sh`
  has an `alpine()`, `qemu-6-tests.sh` handles it), but `alpine3-24`
  appears in none of `zfs-qemu.yml`'s four `os_selection` lists, so it
  only runs via `workflow_dispatch` with `specific_os`. The six-OS
  list that *looks* like the default matrix in a local checkout is
  this fork's own `**DEBUG**` commit. Do not repeat that mistake.
  The issue's four items and what each needs:
  - **ksh93** -- *not a blocker*, it works today. Upstream's
    `alpine()` does `git clone --depth 1 --branch 1.0`, a moving
    branch head rather than a pinned release, so CI silently tracks
    whatever lands there. Alpine has no ksh93 package at all (only
    `loksh`/`mksh`/`oksh`, pdksh derivatives), so it is the one
    platform that cannot `apk add ksh`. Posed as pinned-tag build vs.
    prebuilt personal package, with the user's own supply-chain
    objection to their own option stated in the issue.
  - **`is_kmemleak()`** -- self-serve, the user will PR it.
  - **`zfs_get_006_neg`** -- *blocked on a maintainer decision*, five
    options enumerated in the issue: `+` at all six call sites (the
    branch), `+` at `zfs_do_get` only, a `getenv("POSIXLY_CORRECT")`
    shim, a musl-scoped mask, or dropping the ten ordering cases. The
    question underneath, which is the project's to answer: **is
    `zfs get all -r` supposed to fail?**
  - **`send-c_stream_size_estimate`** -- *blocked on someone else*.
    Left in the issue as diagnostic data, explicitly not vouched for.

- **Findings deliberately kept out of that issue (2026-09-04)** --
  recorded here so they are not lost:
  - **`zfs program` mis-parses script arguments.** Script args land at
    `argv[2]` after `argc -= optind`, so `zfs program tank script.zcp
    -n` silently eats `-n` as the CLI's own dry-run flag and drops it
    from the script's argv; `-t`/`-m` additionally swallow the
    following argument. An unconditional `+` on
    `zfs_do_channel_program` fixes it and the only behaviour that
    changes is behaviour that was already broken. This is the one
    place where the `+` change fixes a real bug rather than tightening
    something that works, so it is a *supporting argument* for the
    branch's chosen option -- the user omitted it deliberately to keep
    the issue short.
  - **The `splice()` mechanism is verified against stock kernel
    source**, not just asserted. `fs/splice.c` at upstream
    `45c13f3f9e3b`: with `off_out == NULL`, `offset` is latched from
    `out->f_pos` before `do_splice_from()` and written back after it
    unconditionally, with no check on bytes moved. Relay nothing and
    the position is reset, discarding a concurrent writer's progress.
    Exactly what the branch's commit message claims.
  - **There is a kernel-side angle nobody has raised upstream.**
    `~/Development/linux` carries a local branch
    `claude/splice-fpos-race` whose HEAD ("splice: serialize
    `->f_pos` updates against read/write/lseek", 2026-08-27) patches
    this same race in the kernel. So the project has fixes at both
    layers and has never resolved which one is correct. A reviewer of
    the ZFS-side fix may reasonably ask. **Caution when reading
    `fs/splice.c` in that tree: HEAD is the patched version, not
    stock.** Check the parent commit for upstream behaviour.

- **Final CI on the posted branches (2026-09-04).** `alpine/combined`
  finished **green on all six platforms**, run conclusion `success`.
  `alpine/baseline` is red on `alpine3-24` alone, everything else
  green -- so the two run links in the issue show the contrast
  directly. `fedora44` failed twice and passed on re-run on both
  branches; `delegate/zfs_allow_003_pos` failed once on `m68k-io` and
  passed on both `alex-moch` branches on an identical tree. Both
  ordinary flakes.

- **Email sent to Brian Behlendorf (2026-09-04)** on an existing
  thread, pointing at the issue with a per-item triage: `is_kmemleak`
  self-serve, `zfs_get_006_neg` needs a decision, the send bug needs
  an owner, ksh93 works today and is only worth a discussion. The
  point of the mail was visibility, not extracting an answer -- the
  issue is long and easy to scroll past.

- **Still open (2026-09-04).** The `curl --retry` hardening for the
  prebuilt-ksh93 step. Two cosmetic nits in the posted issue body (one
  un-backticked `zfs get`) the user chose to leave. `Component: CI`
  and `Component: Test Suite` labels, if the user has rights. And the
  `alex-moch` copy of the getopt commit still carries the
  pre-correction message, which the issue links to directly -- the
  corrected commit is on `m68k-io`'s `claude/getopt_long_permute`,
  cherry-pickable without changing the tree. The user is aware and
  chose to leave it while CI is green.

## Update (2026-09-15): maintainer answered the Alpine issue; kmemleak enablement

- **Brian Behlendorf replied on the upstream Alpine issue**, covering
  all four items. The mail did its job — the issue had sat at zero
  comments until then.
  - **ksh93: accepted with a condition.** Prebuilt binaries are fine
    for "solely a test CI environment with no secrets which is
    intended to test PRs", but he wants the package hosted somewhere
    under the OpenZFS GitHub organization rather than a personal
    account. `qemu-3-deps-vm.sh` currently pulls from
    `alex-moch/ksh/releases/latest`. Deferred by the user.
  - **kmemleak: he asked a different question than the one filed** —
    "could we instead enable kmemleak at boot?" They used to build a
    custom kernel for this and the maintenance burden killed it; he
    wants leak checking back "even if it is for only one of the
    builders."
  - **`zfs_get_006_neg`: he leans to option 5**, drop the
    argument-ordering cases -- "my inclination here would be option
    5", not a ruling. His reasoning: lowest risk, won't break
    anything users depend on, and it is a single test. He also notes
    FreeBSD defaults to `POSIXLY_CORRECT`, so those cases only ever
    verified that the tests themselves pass arguments in the right
    order. `claude/zfs_get_006_posixly_correct` is that shape and is
    ready, but do not read this as settled -- earlier entries here
    said "decided" and "picked", which overstates the thread.
    - **It may not be needed at all.** If per-platform test selection
      gets built for kmemleak's sake, an Alpine runfile simply would
      not list this test, and a mask would mark it expected -- either
      subsumes it without deleting anything. So the CI question comes
      first. Note the three are not equal in coverage: dropping the
      ten cases keeps twenty running everywhere, a runfile drops all
      thirty on Alpine, and a mask keeps them running but would hide
      a genuine `zfs get` regression on musl.
  - **`send-c_stream_size_estimate`: he is taking it**, with "add
    this test to the exceptions list until we sort out the root
    cause" as the fallback. Off the user's plate.

- **The predicate fix is not load-bearing in upstream CI.** Grepping
  the *baseline* (unfixed) run per builder settles it:

  | builder | `zfs_get_009_pos` | `send_realloc_files` |
  |---|---|---|
  | ubuntu26 | `[01:10] PASS` | `[00:28] PASS` |
  | debian13 | `[03:03] PASS` | `[00:38] PASS` |
  | fedora44 | `[03:28] PASS` | `[00:38] PASS` |
  | almalinux10 | `[03:00] PASS` | `[00:38] PASS` |
  | **alpine3-24** | **`[00:00] SKIP`** | `[00:06] PASS` |

  The four glibc builders have no `/sys/kernel/debug/kmemleak` at all,
  so `is_kmemleak()` already answers correctly there. Alpine is the
  only builder that false-positives, and with one Alpine runner and
  kmemleak genuinely enabled the predicate would answer correctly too.
  The fix still matters — `libtest.shlib` ships to everyone running
  ZTS on a `DEBUG_KMEMLEAK=y` + `DEFAULT_OFF=y` kernel, and it is what
  lets one builder differ from the rest — but it does not unblock
  anything in this CI. Earlier notes overstated its CI impact.

- **The trade nobody had named.** The tests guarded by `is_kmemleak`
  skip *because kmemleak makes them ruinously slow*. So enabling
  kmemleak on the only Alpine runner re-skips exactly the coverage the
  predicate fix restored (`zfs_get_009_pos` back to `00:00`,
  `send_realloc_files` back to `00:06`). Leak checking across ~1900
  tests or three tests on one builder — probably the right trade, but
  a trade, and it means the two changes pull in opposite directions on
  that one runner. It also means "enable kmemleak now, fix the
  predicate later" loses nothing: Alpine already behaves as though
  kmemleak is on.

- **ZTS's `-m` option has been broken since 2022-03-14.** kmemleak
  support landed 2022-02-24 ("Add Linux kmemleak support to ZTS",
  Damian Szuberski) driving `/sys/kernel/debug/kmemleak` through three
  `echo X | sudo tee FILE` pipelines. Three weeks later a cleanup
  commit ("tests: clean out unused/single-use/useless commands from
  the list") rewrote all three as `sudo sh -c "echo X > FILE"` and
  dropped the `sh` on one — the `scan=0` that disables the periodic
  scan before the run. `sudo` has no `-c` (only `-C/--close-from`),
  so it exits with a usage error, `check_output()` raises
  `CalledProcessError`, and the run dies before the first test case.
  Nobody has used `-m` in three and a half years.

- **Leaks do surface, as FAILs.** `test-runner.py.in`:
  `elif len(self.kmemleak) > 0: self.result = 'FAIL'`. A non-empty
  report turns that test into a FAIL and writes the report into the
  test's outputdir. An earlier read of this file wrongly concluded
  nothing consumed the output. The flip side: false positives become
  FAILs too, and the original commit is explicit that they happen —
  "unavoidable potential false positives coming from kernel areas
  other than OpenZFS module", with a `btrfs` leak in its own example
  run and 98.3% passed.

- **Cost is documented, not guessed.** That same commit message:
  "The ZTS with kmemleak enabled duration is increased by ~50%".
  Alpine's ZTS currently ends at `03:02:52`, so expect roughly
  **4h40**. The `Run tests` step cap is `timeout-minutes: 300` — it
  fits, barely. The real ceiling is GitHub's 6h cap on the whole job,
  which also carries the ~1h build.

- **Kernel side confirmed on the dev box** (`7.1.5-0-stable`, the same
  flavour the CI boots): `CONFIG_DEBUG_KMEMLEAK=y`,
  `CONFIG_DEBUG_KMEMLEAK_DEFAULT_OFF=y`,
  `CONFIG_DEBUG_KMEMLEAK_AUTO_SCAN=y`, `CONFIG_SLUB_DEBUG=y`. So
  `kmemleak=on` on the command line is all it takes — no custom
  kernel, which is precisely the burden that drove the project off
  kmemleak in the first place. Alpine is the only OS in the matrix
  that carries the option at all, which makes it the one runner where
  leak checking is cheap.

- **Latent hazard, deliberately not fixed.** The per-test scan runs
  *inside* the timeout window — `t.cancel()` sits in the `finally`,
  after the `echo scan` and `cat`. A test whose runtime plus scan
  exceeds its runfile timeout has `kill_cmd` fired at an
  already-exited process and is recorded `KILLED`. At a ~5.6s suite
  average this probably never fires, but tests near their 600s limit
  could flip to spurious KILLEDs. Fixing it means restructuring the
  `try`/`finally`; left for the user to decide.

## Update (2026-09-15, later): first working kmemleak run, and the leak it found

- **Reply posted to the upstream issue.** Three numbers in the draft were
  wrong and were corrected before sending: the baseline Alpine time is
  **3:01:37** (vm2's own `Running Time`; vm1 was 2:05:34, and the merged
  summary's `05:07:11` is the two VMs *summed*, not wall time); vm2 had
  **179** tests left, not 190, because the figure had been read off a
  counter line printed 26 minutes before the cap; and the step timeout
  should be raised to **330**, not 360, since the six-hour ceiling covers
  the whole job and the build consumes about 25 minutes of it. A 360
  minute step timeout can never be reached.

- **`-m` needed three fixes, not one.** Beyond the missing `sh` in the
  `scan=0` invocation: `kmemleak_cb()` tested for the file with
  `os.path.exists()`, but debugfs is mounted `drwx------ root:root`, so
  an unprivileged caller cannot stat anything below it and the check
  fails on a kernel where the detector is demonstrably running. Spelling
  it `sudo -n test -e` then failed too, because `zfs-tests.sh` runs the
  runner as `PATH=$STF_PATH`, a constrained directory built from
  `commands.cfg` -- which carries `sh`, `sudo` and `cat` but **not
  `test`**. Every other kmemleak command in that file is `sudo sh -c` or
  `sudo cat`; the existence check was the only one that reached outside
  the whitelist. Each bug hid the next, which is what three and a half
  years of nobody running `-m` looks like.

- **The run completed on one VM and was killed on the other.** vm1:
  `04:17:39`, 1162 PASS / 7 FAIL / 10 SKIP, two unexpected
  (`zfs_receive_-e`, `send-c_stream_size_estimate`). vm2: killed at the
  300 minute step cap having finished **769 of 948**. `Prepare
  artifacts` carries `if: always()`, so the artifacts survived.

- **Measured cost, from the 1890 tests present in both runs**: 272 min
  of baseline work became 537 min, so **roughly 2x**, against the ~50%
  the original ZTS kmemleak commit advertised. The overhead is *not*
  flat -- the ratio falls as tests get heavier:

  | baseline duration | n | added | ratio |
  |---|---|---|---|
  | 0-2s | 1228 | +2.5s | 19.6x |
  | 2-5s | 178 | +6.1s | 3.2x |
  | 5-15s | 241 | +10.9s | 2.3x |
  | 15-60s | 170 | +28.4s | 2.0x |
  | 60-300s | 70 | +62.0s | 1.6x |

  This matters for any runtime-balanced split: for long tests the cost
  is near-proportional, so a runtime balance survives, but the ~1200
  sub-two-second tests each gain about 2.5s regardless of weight. That
  is ~50 minutes distributed by test *count*, invisible to a timing
  database built from runs without kmemleak.

- **Five kmemleak reports across ~2029 executed tests, and all five are
  the same leak.** Zero false positives -- the original commit's warning
  about "unavoidable potential false positives from kernel areas other
  than OpenZFS" did not materialise here at all. `zfs_receive_-e` on
  vm1; `raidz_001_neg`, `zfs_change-key_format`, `zfs_copies_001_pos`
  and `zfs_channel_program_support` on vm2. A FAIL caused by a leak
  report is indistinguishable from an ordinary FAIL in the summary --
  the discriminator is a `kmemleak` file in the test's outputdir.

- **The leak: `zio_crypt_key_unwrap()` skips its cleanup on failure.**
  It allocates a pair of iovec buffers via `zio_crypt_uios_init_os()`
  and releases them with `zio_crypt_uios_fini_os()` after the keys are
  decrypted -- but `zio_decrypt_os()` failing jumps to the error label
  ahead of that release. Every key unwrap that does not authenticate
  leaks 64 bytes twice, so repeated `zfs load-key` with a wrong
  passphrase grows kernel memory without bound. `zio_crypt_key_wrap()`
  forty lines earlier frees unconditionally on both paths, which is the
  shape the unwrap path should have had. Not Linux specific: the code
  is shared and FreeBSD's `zio_crypt_uios_init_os()` allocates through
  `allocuio()`.
  - **It is one day old in master.** The introducing commit was authored
    2026-05-24 but *committed* 2026-09-14, and is not an ancestor of the
    old baseline -- it arrived with today's 90-commit sync and has never
    been in a release. It is also why the module that was loaded on the
    dev box (built from the pre-rebase baseline) did not have it and a
    fresh build was needed to reproduce.
  - **Audited rather than assumed isolated**: `zio_crypt_key_wrap` and
    `zio_do_crypt_data` both free correctly, including in the latter's
    `error:` label, and none of the three `zio_crypt_init_uios_*`
    helpers can return an error before calling `init_os`, so the
    caller's error path never frees uninitialised uios.

- **Verified on the dev box under a live kmemleak**, not by reading
  code. 200 failed unwraps reported **204** leaked objects before the
  fix and **0** after; a control run performing no unwraps reported 1.
  Intermediate fixed-module runs gave 6 at N=20 and 2 at N=60 --
  uncorrelated with attempt count, i.e. kmemleak's own noise floor,
  where the unfixed module was linear at ~1 object per attempt. The 29
  tests in `crypto,zfs_load-key,zfs_change-key,zfs_unload-key,hkdf` pass
  100% with the fix applied.

- **Two corrections to earlier entries in this file.**
  - The claim that master had gained ~200 tests is **wrong**. The
    runfiles grew by **13** between the two master commits. The
    executed-test difference (1929 to 2127) is almost entirely a change
    in *tag coverage*: modelling the baseline run's own tag lists leaves
    ~179 runfile entries matching neither VM, while the current lists
    leave none. Tests were not added; tests that previously ran on
    neither VM now run.
  - The `N(a|b)` figure in the runner's progress line is a **live
    snapshot**, not a final total -- the first number tracks vm1 and the
    second vm2. Reading a pasted mid-run line as if it were final is
    what produced the wrong "190 remaining". For final counts use the
    summary, or the last counter line in the completed job log.

- **Minor CI quirk found while modelling the split**: `acl/posix-sa`
  matches both VMs' tag lists (`posix-sa` is in one, `acl` in the
  other), so its 6 entries execute twice per run, once on each VM. That
  is the entire discrepancy between the 2121 distinct runfile entries
  and the 2127 executions the model predicts.

## Update (2026-09-15, evening): triage of the run's other failures

- **Every FAIL in the kmemleak run is now accounted for.** 25 across
  both VMs, in five groups:
  - **12 masked known issues** — vm1's `auto_replace_001/002_pos`,
    `auto_spare_multiple` and both `xdr_*_raw_with_write`; vm2's six
    `casenorm/*` and `import_rewind_device_replaced`.
  - **5 kmemleak reports** — the crypto leak, one site.
  - **1 known Alpine failure** — `zfs_get_006_neg`, expected, since
    this branch is baseline plus kmemleak only and carries no getopt
    fix.
  - **1 known send bug** — `send-c_stream_size_estimate`, fix lives on
    another branch.
  - **6 in one cascade** — `mount_loopback` plus five bystanders. See
    cluster 8 in `claude-notes/INVESTIGATIONS.md`; fixed on
    `claude/mount_loopback_losetup_show`.

- **Lesson from the cascade, worth generalising.** One test aborting
  while holding a loop device open left `testpool2` permanently busy,
  and every later test that called `destroy_pool` failed after a ~31
  second retry backoff. Five failures in unrelated subsystems, in one
  time window, all reported independently by the summary with nothing
  linking them. When a block of unrelated-looking failures clusters in
  time, look for a single earlier test that leaked state rather than
  triaging each one separately — and sort failures by timestamp first,
  which is what made this obvious.

- **A wrong hypothesis worth recording, since it was stated with some
  confidence.** The `mount_loopback` failure was first attributed to a
  udev race widened by kmemleak's ~2x slowdown. It is not a race at
  all: Alpine's `/dev/loop` directory is built once at boot with eight
  entries, and no amount of `udevadm settle` adds more. The correct
  read only came from testing the settle rather than assuming it would
  help. The general form of the mistake — reaching for "slower machine
  widened a race" when a run is slower than usual — is worth
  distrusting.

## Update (2026-09-15, late): correcting the leak measurement, and how kmemleak misleads

The 2026-09-15 entry above records "200 failed unwraps reported 204
leaked objects before this change and none after, against one object on
a control run". **Those figures are not a clean before-and-after.** The
fix is right and the conclusion stands, but the measurement behind it
was wrong in three ways, each worth knowing before anyone measures with
kmemleak again.

- **A single `cat` of `/sys/kernel/debug/kmemleak` returns a partial
  list.** Three consecutive reads with no scan in between gave 82, then
  120, then 130. The "204" was one such read. Count by reading
  repeatedly until the number stops growing.

- **`kmemleak_clear()` only greys objects already flagged
  `OBJECT_REPORTED`:**

  ```c
  if ((object->flags & OBJECT_REPORTED) && unreferenced_object(object))
          __paint_it(object, KMEMLEAK_GREY);
  ```

  Anything that leaked but was never *reported* stays white and remains
  eligible for any later scan, forever. So `echo clear` does **not**
  give a clean slate: every run inherits an unreported backlog from
  every previous run on that boot. This is what produced the wild
  spread of 13, 14, 70, 76, 78, 82, 97, 187 and 225 across runs of 10 to
  200 attempts, and it is why one unfixed run reported 2.80 objects per
  unwrap when the code can only allocate 2.

- **`unreferenced_object()` measures age against `jiffies_last_scan`,
  not the current time**, with `MSECS_MIN_AGE` of 5000 ms. Anything
  allocated in the five seconds before a scan is invisible to that scan.
  The original script slept only 3 seconds before scanning, so the tail
  of every run was excluded by construction.

**How to tell a straggler from a real leak**: compare the `jiffies` and
`pid` fields against the run that reported them. Objects reported by
later runs here consistently carry *lower* jiffies and *lower* PIDs than
objects reported by earlier ones -- they predate the run reporting them.
That is the single most useful check, and it is what settled this.

**What the corrected measurement shows.** Unfixed, with repeated reads
and an 8-second settle: 70 objects from 25 unwraps, 187 from 100 -- call
it ~2 per unwrap, matching the two `kmem_zalloc` calls in
`zio_crypt_uios_init_os()`. The two allocation sites reported 307 and
278 objects across all runs, when the code cannot execute one without
the other; that 10% gap is the false-negative rate, measured directly.
Fixed, from a drained baseline, six runs of 200 unwraps each: 0, 2, 2,
1, 0, 1 -- every reported object belonging to a process older than the
run that reported it.

**The claim that actually carries the fix is the code**, not the
counts: after the change there is no path through
`zio_crypt_key_unwrap()` that allocates the uios and does not free
them. The only airtight measurement would be a reboot with the fixed
module loaded first, where no backlog can exist; that was not done.

**Method note for next time**: a `pgrep -f "[l]eakrepro"` wait loop
deadlocked two background jobs against each other, because each job's
own command line contained the pattern. The `[l]` trick only stops
`pgrep` matching itself, not sibling jobs that mention the same script.

## Update (2026-09-16): kmemleak on the Alpine runner is off the table

Brian asked for leak checking back "even if it is for only one of the
builders". The answer, after two full experiments, is **not on the
current CI shape**. The detail is in `claude-notes/INVESTIGATIONS.md`
cluster 9; the short form:

- The balanced run hit the 330-minute step cap with vm1 unfinished and
  left the job at **5h 58m 51s of the six-hour ceiling**. Raising the
  step cap is not available — the job cap binds first, and a job killed
  at six hours never reaches `Prepare artifacts`, so the evidence is
  lost with it. The true step ceiling is ~331 min, or ~334 with the
  ksh93 source build removed.
- Tony Hutter's split is sound: it divided the halves to within **three
  database seconds**. The imbalance is that the per-group kmemleak
  multiplier runs from **0.99x to 5.07x**, so a database built without
  the detector cannot balance a run with it.
- Even a perfect split needs **334.7 min** against **333.8** available.
  One minute over, with nothing left that has headroom.

**Consequences for the plan.** The three low-risk commits go first and
are unaffected: dropping the argument-ordering cases from
`zfs_get_006_neg`, the `is_kmemleak()` predicate fix, and the `-m`
availability check. The `-m` fixes are worth landing on their own —
they are what makes `zfs-tests.sh -m` usable at all after three and a
half years — and only `CI: turn on kmemleak leak checking for the
Alpine runner` is blocked.

**If it is ever revisited**, the levers with real headroom are the 19m
50s module build, whatever the `zio_crypt_key_unwrap` fix takes off
the detector's scan cost (never measured — the balanced branch does
not carry the fix), and the shape of the job itself. A recalibrated
timing database is necessary but not sufficient, and would have to be
a second database selected when `-m` is on, since replacing the
generic one would mis-balance the five builders that run without the
detector.

## Update (2026-09-17): the CI question is back with the maintainer

Posted a reply on the upstream Alpine issue putting the capacity
question to Brian rather than proceeding on assumptions.

- **kmemleak does not fit, and the reply says so plainly.** Three runs
  with `kmemleak=on`: plain master at a 300-minute step limit, and
  twice with the balancing PR and 330. In all three one VM finished
  and the other was still running when the limit hit. On the latest,
  the finishing VM took 5h 02m and the other had **202 tests / ~38.5
  min** left.
- **The ask is an Alpine-specific runfile or equivalent** -- fewer
  tests on Alpine, more CI work, in exchange for leak checking on one
  runner. Explicitly framed as his call.
- **`zfs_get_006_neg` is deliberately held.** Whatever selection
  mechanism comes out of the CI decision may subsume it, so the ten
  cases are not being dropped ahead of that.
- `mount_loopback` and the `CONFIG_MODULES` flake went in as FYIs, no
  answer requested.

**A trap worth remembering: masking in `zts-report.py.in` saves no
time.** It post-processes the results file after the suite has run
(`zfs-tests.sh` builds `REPORT_FILE` and runs the report at the end),
so it reclassifies a failure as expected without preventing the test
from running. Only *not running* tests -- a runfile subset, tag
selection, or a test that self-skips -- reduces the runtime. The draft
originally offered "mask or runfile, same result, different mechanics"
and that would not have survived review.

## Update (2026-10-11): three PRs open, Alpine enablement drafted

- **Three PRs opened upstream, all from `alex-moch/zfs`, each one
  commit on master.** The 2026-09-18 batch (`#19132`, `#19135`,
  `#19136`, `#19138`, `#19139`) and the AMX workaround (`#19150`) are
  all merged; nothing else of the user's is open.
  - `#19347` -- CI: Update Alpine Linux to 3.24.2 and its Limine boot
    (`alpine/3_24_2`; local `claude/alpine_3_24_2_limine`, same code).
    3.24.2 ships only a hybrid image booting through Limine, with the
    kernels on a ~113 MB FAT `/boot`. The commit points the static
    `limine.conf` entry at `-stable`, drops the `kms` mkinitfs feature
    (the ~90 MB initramfs filled `/boot`), and writes the limine
    updater configs with both old and new key names before the upgrade
    (with the old names only, the BIOS hook broke the boot sector and
    the EFI hook made apk exit non-zero).
  - `#19348` -- ZTS: mark send-c_stream_size_estimate as a known
    failure (`alpine/splice-zts-probe`; local `claude/splice-zts-probe`,
    same code). Takes the maintainer up on his offer in `#19052`.
  - `#19349` -- CI: Add Alpine Linux to the default runners
    (`alpine/default`), **draft**, one line in `zfs-qemu.yml`. Its
    description says it is blocked by `#19347` and `#19348` and leaves
    draft once both merge. Not stacked on them: one commit, so the
    review stays in one place.
- **The send relay will not be submitted.** `claude/lzc_send_wrapper_
  splice_race` does fix the test in userspace (green on real CI since
  2026-09-04), but the bug is the kernel's, and the user does not want
  ZFS carrying a workaround for it. The kernel fix is being prepared
  separately (`~/Development/kernel-findings/splice-fpos`). So the mask
  is the plan, and the branch stays as a reference.
- **Why only musl shows it is now pinned down** -- cluster 14 in
  `claude-notes/INVESTIGATIONS.md`. Short form: musl's `stdout` is
  line-buffered until its first write, so the "full" line reaches the
  file while the relay's `splice()` is still blocked; glibc writes
  both lines at exit, after the relay has finished.
- **Next, once both blockers merge:** take `#19349` out of draft and
  check its own CI. Then delete `claude/splice-zts-probe` and
  `claude/alpine_3_24_2_limine` here -- after the *merge*, not on
  approval.

## Update (2026-10-12): both blockers merged, Alpine enablement in review

- **`#19347` and `#19348` merged on 2026-10-12** (~16:59 UTC), both
  approved by behlendorf. His note on `#19348`: the mask can stay "for
  now"; once the kernel fix lands and reaches Alpine, revert it. The
  CI failures on both PRs were on other distros (almalinux9, debian13,
  ubuntu26 and the Detect job on `#19347`; freebsd16-0c on `#19348`),
  not Alpine.
- **`#19349` is out of draft.** behlendorf asked for the rebase; the
  user rebased it on master (head `77c1a220bab8`, one commit) and
  commented with the 20-runner check run 38169227892 on alex-moch
  (2026-10-11, the two PRs cherry-picked): 19 of 20 Alpine jobs green.
  The one failure, `alpine3-24-03`, was a 300-minute step timeout, not
  a test result: vm1 finished with nothing unexpected, vm2 stopped
  printing at 21:35 after `removal/removal_with_dedup`, so it most
  likely hung in `removal/removal_with_errors`. Not investigated
  further; the log artifact was not downloadable. If it repeats on
  Alpine, that is the place to start. The PR's own CI was still running
  at 18:15 local; review not yet requested back.
- **Cleanup is now unblocked** for `claude/splice-zts-probe` and
  `claude/alpine_3_24_2_limine` here and `alpine/3_24_2`,
  `alpine/splice-zts-probe` on alex-moch, but not done yet: waiting on
  the user's go-ahead.
- **Open follow-up:** revert the `send-c_stream_size_estimate` entry in
  `zts-report.py.in` once a kernel with the splice fix ships in Alpine.

## Update (2026-10-12, evening): kmemleak variant, draft PR `#19359`

- **`#19359` -- CI: Add an alpine3-24-kmemleak variant**, draft, from
  `alex-moch:alpine/kmemleak` (`1c170efce`, one commit). Answers
  behlendorf's "could we enable kmemleak at boot?" in `#19052` as an
  optional, by-hand runner. Three small changes:
  `qemu-2-start.sh` matches `alpine3-24*`; `qemu-3-deps-vm.sh` gives
  Alpine its own case branch and, for names containing `kmemleak`,
  appends `kmemleak=on` to the `cmdline:` line of
  `/boot/limine/limine.conf` (the 3.24.2 image has exactly one such
  line, verified in the image); `qemu-6-tests.sh` passes `-m` for the
  same names. Started with `specific_os=alpine3-24-kmemleak`; on
  openzfs/zfs itself the qemu job skips `workflow_dispatch`, so this
  only runs in a fork. The suffix scheme is meant to grow `edge`
  (commented-out sed already in `qemu-2-start.sh`; needs
  `--enable-linux-experimental` once edge passes `Linux-Maximum`) and
  `llvm` (userspace only: Alpine kernels are GCC-built and a clang
  module build against them fails on GCC-only flags, tested locally).
- **First run, m68k-io 38292211323:** attempt 1 failed in `Setup
  testing machines` -- both test VMs booted with `kmemleak=on` and the
  detector initialised, reached the login prompt, but never answered
  ssh, and the 5-minute step limit hit. Same CPU as a normal job (EPYC
  7763, no AMX), boot messages identical apart from kmemleak's own; the
  build VM also ran with kmemleak on and ssh worked throughout.
  Attempt 2, same commit, got through setup in 37 s and is running
  ZTS. So far a fluke, but one failure in two.
- **Instrumented DEBUG branch ready, not pushed:**
  `claude/alpine_kmemleak_debug` (`cd4a2ea1d`, worktree
  `~/Development/zfs-kmemleak-debug`). Ten `alpine3-24-kmemleak-NN`
  runners plus two plain controls, everything else dispatch-only, and
  a `qemu-wait-for-vm.sh` that bounds and logs each ssh attempt and
  dumps host, guest-agent and SysRq state at 90/240/480 s; setup
  limit 15 min. The user asked for it only if the setup failure
  repeats.
- Local branches: `claude/alpine_kmemleak` (`55f7ef29e`, worktree
  `~/Development/zfs-kmemleak`) is the m68k-io copy; the PR commit is
  the user's reworded version of it, same behaviour.

## Update (2026-10-12, night): kmemleak setup hang root-caused -- two dhcpcd

- **Symptom:** with kmemleak on, some test VMs booted to the login
  prompt but never answered ssh; `Setup testing machines` timed out.
  3 of 10 kmemleak runners in one instrumented run, 0 of 2 plain ones,
  and 0 of 20 plain runners on 2026-10-11.
- **Cause:** two `dhcpcd` at boot. `networking` brings up `eth0` via
  ifupdown-ng, whose DHCP executor runs `/sbin/dhcpcd eth0` when dhcpcd
  is installed; `qemu-3-deps-vm.sh` also did `rc-update add dhcpcd`
  (added with the original Alpine runner, reason not recorded). The
  service's dhcpcd daemonises before its privsep control socket is
  ready; networking's dhcpcd then forwards to the half-initialised
  master ("sending commands to dhcpcd process"), fails with
  `dhcpcd_control_read: Invalid argument`, and the master logs garbage
  errnos ("Out of memory" with 7.8 GB free, "No error information")
  and exits or times out. eth0 never gets an address; sshd was
  listening throughout. kmemleak slows allocation-heavy startup and so
  widens the window; the 2-vCPU test VMs hit it, the 4-vCPU build VM
  never did. The garbage-errno failure looks like a dhcpcd robustness
  bug worth reporting upstream; not done.
- **Images:** 3.24.1 ships `/etc/network/interfaces` with eth0 dhcp;
  3.24.2 ships only `lo` and cloud-init's `eni` renderer adds eth0 at
  the build VM's first boot. Runlevels identical, neither enables the
  dhcpcd service, ifupdown-ng's executor identical. CI upgrades dhcpcd
  to 10.5.2 on both (the September 3.24.1 kmemleak run did too). So
  the double start predates 3.24.2.
- **Fix verified:** dropping `rc-update add dhcpcd` -> 20/20 jobs,
  40/40 test VMs up within 27 s, 36 of them with kmemleak. Logs:
  `~/Development/logs/kmemleak-debug-38298003682` (before) and
  `~/Development/logs/kmemleak-fix-38302427025` (after). The after-run's
  dhcpcd probe was flawed (`ps` without `-e`; syslog `head` showed the
  build VM's earlier boots, since test disks are clones) -- the result
  rests on reachability and `rc-status`, not on the probe.
- **Current branch:** `claude/alpine_dhcpcd` (worktree
  `~/Development/zfs-dhcpcd`) on upstream master `68188d1ff`: DEBUG
  (10 plain + 10 kmemleak runners, all other workflows dispatch-only),
  cherry-pick of `#19359`'s commit, and the dhcpcd fix (authored
  Alexander Moch). Pushed to m68k-io; run 38305777607.
- **Cleanup done:** m68k-io now holds only `baseline`, `claude-meta`,
  `master`, `claude/alpine_dhcpcd`; all other runs deleted. Locally
  deleted the merged/superseded `alpine_3_24_2_limine`,
  `splice-zts-probe`, `alpine_kmemleak(_debug)`, `kmemleak_alpine`,
  `pr_kmemleak`, `getopt_long_permute`, `zfs_get_006_posixly_correct`
  and their worktrees. `~/Development/zfs` is detached at `2bed45688`
  because its 12 pre-existing `config/*.m4` edits block switching to
  master. alex-moch's runs and branches untouched.

## Update (2026-10-13): four Alpine PRs open, kmemleak runner validated

**Open upstream PRs (all from `alex-moch/zfs`, one commit each, on
master `b060bcb1d`):**
- `#19359` CI: Add an alpine3-24-kmemleak variant (`alpine/kmemleak`,
  `1c170efce`) -- out of draft, ready for review. The user commented
  with the 40-runner run (no leaks; Intel runners finish; the only
  unexpected result is the `zfs_get_009_pos` SKIP).
- `#19363` CI: start only one dhcpcd on the Alpine runner
  (`alpine/dhcpcd`, `d27829373`). Root cause in the 2026-10-12 night
  entry above; 196 test VMs up since the fix.
- `#19382` ZTS: expect zfs_get_009_pos to SKIP under kmemleak
  (`alpine/zfs_get_009_pos`, `4251f951f`): Linux `maybe` entry with a
  new `kmemleak_reason`. The skip is Behlendorf's own (`c6ced7261`,
  2016, 55:43 with kmemleak).
- `#19349` (Alpine in the default runners) merged 2026-10-12 22:42 UTC:
  `alpine3-24` now runs on every upstream PR.

**Ready, no PR yet:** `claude/zpool_get_006_snapshot` (`71c7ea005`),
"ZTS: read zpool_get_006_pos class properties together" -- cluster 16.
Validation run m68k-io **38427626308** (`claude/zpool_get_006_kmemleak_x20`
= master + #19359 + #19363 + #19382 + the 006 fix + DEBUG 20 kmemleak
runners) started ~16:05 UTC, **not yet analysed**; the user shut down
rather than wait. Expect: 006 fails 0/20 (was 21/60), finished VMs no
longer list the 009 SKIP as unexpected, 40/40 VMs up. Analyse with
`claude-notes/kmemleak-fetch.sh` (adjust run ids) and the method in
`claude-notes/CI-RUN-2026-10-13-kmemleak-x60.md`.

**Other findings this session (details in claude-notes):**
- 60 kmemleak jobs: no leaks, 89.6% coverage, only Intel runners finish
  -- `CI-RUN-2026-10-13-kmemleak-x60.md`.
- `zarcsummary_001_pos` flake = ksh93 socketpair pipes giving
  `ECONNRESET` without SIGPIPE; also hits fedora43 upstream; ksh93/ksh
  #741 -- cluster 15, reproducers in `claude-notes/ksh-socketpair/`.
  One-line zarcsummary fix (catch `ConnectionResetError`) **not
  committed yet**. ksh93 fix designed (feature test + `tee(2)` peek),
  **not implemented**; ksh checkout `~/Development/ksh` is the old
  m68k-io fork, branch fresh from upstream `dev` if picked up.
- Further kmemleak-only flakes, not pursued: `mmap_ftruncate` (soft
  lockups), `redundancy_draid_spare4` (KILLED), `raidz_expand_001_pos`.

**Environment state:** ZFS module (installed 2.4.99-1097 build, Sep 17)
was loaded on this box for the local 006 test (`sudo modprobe zfs`); no
pools left. `~/Development/zfs` (main checkout) is detached at
`2bed45688` because its 12 pre-existing `config/*.m4` edits block a
switch to master. Patch file for the 40-runner setup:
`~/Development/alpine-kmemleak-x40.patch` (local branch
`claude/alpine_kmemleak_x40`).

**Next steps:**
1. Read run 38427626308; if 006 is clean, open the 006 PR (evidence:
   21/60 before, 0/20 after; local 324-check comparison).
2. Commit the zarcsummary one-liner; possibly comment on ksh93/ksh#741
   with the kernel analysis; ksh fix if wanted.
3. Cleanup once merged: m68k-io branches `claude/alpine_dhcpcd`
   (run 38305777607 is linked from #19363 -- keep until merged),
   `claude/alpine_kmemleak_x20`, `claude/zfs_get_009_kmemleak`,
   `claude/zpool_get_006_*`, their worktrees, and the runs; alex-moch
   `alpine/kmemleak_x40`, `alpine/final-x20` and older `alpine/*`
   branches of merged PRs (`3_24_2`, `splice-zts-probe`, `default`);
   alex-moch has ~120 old runs, cleanup offered but not decided.

## Update (2026-10-13, evening): `zfs_get_009_pos` runtime under kmemleak measured

- behlendorf asked on `#19382` how long `zfs_get_009_pos` takes with
  kmemleak today (the skip is from `c6ced7261`, 2016: 55:43). Measured
  on alex-moch run 38435131549 (`alpine/zfs_get_009_pos-timing_x40`,
  from `~/Development/zfs-get009-kmemleak-runtime-x40.patch`, local
  branch `claude/zfs_get_009_runtime_x40`): master + `#19359` +
  `#19363` + DEBUG (skip removed, only this test via `zfs-tests.sh -t`,
  single-test timeout raised 600 s -> 3 h, 40 kmemleak runners).
- 80/80 PASS. Min 5:24, median 17:46, max 22:50. By CPU (min/median/max):
  Intel 6973P-C 5:24/5:38/5:48 (4), 8573C 7:22/7:42/7:54 (4), 8370C
  7:48/8:17/8:45 (2); AMD 9V74 13:39/15:18/20:47 (22), 9V45
  13:25/15:58/17:49 (6), 7763 15:51/18:54/22:50 (42). All 70 AMD runs
  exceed the 600 s runfile timeout, no Intel run does.
- Without kmemleak (10 plain runners of m68k-io 38305777607, in-suite,
  not like-for-like): Intel 0:43-1:03, AMD 2:05-2:58 -- roughly a 7x
  kmemleak factor on every CPU, and AMD already ~2.5-3x slower on this
  test. My prediction beforehand (5-7 min) held only for Intel.
- Conclusion: the skip stays, `#19382`'s `maybe` entry is the right fix.
  The user posted the table on `#19382` (2026-10-13 17:58 UTC).
  Logs + `analyze.sh`: `~/Development/logs/zfs_get_009-timing-38435131549`.

## Update (2026-10-13, night): SRSO "Safe RET" explains the AMD slowdown

- behlendorf on `#19382` (18:17 UTC): "Indeed, way too long." Suggests
  trimming `zfs_get_009_pos` under kmemleak (e.g. fewer `all_props`),
  as `send_realloc_*` do, and the same for other long tests. Read as a
  general idea, not a condition for `#19382`. Note for later: the call
  count depends on `prop_numb` (16 combos x 5 depths x 2 calls) and the
  cost per call on the tree (39 fs + 39 zvols, `DS_COUNT`), not only on
  `all_props`.
- **Cause of the Intel/AMD spread found.** All AMD guests (7763, 9V74,
  and even Zen 5 9V45) boot with SRSO "Safe RET" (`srso_alias_return_thunk`
  / `srso_return_thunk`, "Vulnerable: Safe RET, no microcode"); Intel
  guests use the cheap ITS `its_return_thunk`. alex-moch run 38444757601
  (`alpine/zfs_get_009_pos-mitigations_x40`, patch
  `~/Development/zfs-get009-kmemleak-mitigations-x40.patch`): 20
  runners `spec_rstack_overflow=off`, 20 `mitigations=off`, only
  `zfs_get_009_pos`, skip removed. 80/80 PASS; parameters verified in
  the boot log (no return thunk with SRSO off; no retpolines with
  mitigations off). AMD median 17:58 (all mitigations) -> 8:30 (SRSO
  off) -> 8:02 (all off); Intel 7:27 -> 7:13 -> 6:41. Over 600 s: 70/80
  -> 0/40 -> 2/40. SRSO alone accounts for the AMD gap; the other
  mitigations add ~10-15% on Intel. (My estimate beforehand put full
  closure at only 20-30% -- wrong.) Tables per CPU were given to the
  user in the #19382 style; logs + `analyze.sh` in
  `~/Development/logs/zfs_get_009-mitigations-38444757601`.
- **New suffixes** (user's naming): `*nosrso*` -> `spec_rstack_overflow=off`,
  `*nomit*` -> `mitigations=off`, in the Alpine branch of
  `qemu-3-deps-vm.sh` after the kmemleak check. Commit "CI: add nosrso
  and nomit variants for the Alpine runner" (`3605e5bc7`, signed off,
  written as a possible PR) on local `claude/kmemleak_nomit_x40`.
- **Running, not yet analysed:** alex-moch run **38451666300**
  (`alpine/kmemleak-nomit-full_x40`, started 19:02 UTC, from
  `~/Development/kmemleak-nomit-full-x40.patch`): alex-moch master
  `b060bcb1d` + #19363 + #19359 + #19382 + suffix commit + DEBUG, 40
  `alpine3-24-kmemleak-nomit-NN` runners, **full suite**. Question:
  does a kmemleak run fit into 300 min on AMD without mitigations?
  Baseline with mitigations: 6/60 jobs finished both VMs (all Intel),
  89.6% of tests ran, vm2 median 813/1101. Analyse with
  `~/Development/logs/kmemleak-nomit-38451666300/analyze.sh` (copy in
  `claude-notes/kmemleak-nomit-analyze.sh`, adjust the path).
- Possible upstream follow-ups once measured: the suffix commit as a PR;
  `mitigations=off` or `spec_rstack_overflow=off` for the disposable
  CI test VMs in general (AMD runners ~2.5-3x slower on kernel-heavy
  tests even without kmemleak); trimmed `zfs_get_009_pos`.

## Update (2026-10-14): kmemleak with `mitigations=off` fits; `#19382` options

- **Two full-suite kmemleak runs with `mitigations=off`** (both on
  alex-moch master `b060bcb1d`, 40 `alpine3-24-kmemleak-nomit-NN`
  runners, `kmemleak=on mitigations=off` verified in every boot log):
  - **38451666300** (`alpine/kmemleak-nomit-full_x40`: #19363 + #19359 +
    #19382 + nosrso/nomit commit + DEBUG): 34/40 jobs success, both VMs
    finished in 39/40, 99.5% of tests ran, 0 kmemleak report files.
    Slower VM per job min/median/max 2h54/4h03/4h54. Failures:
    `zpool_get_006_pos` x2 (no fix in this run), `dio_write_verify`,
    `large_dnode_008_pos`, `zed_slow_io_many_vdevs` + `zed_slow_io`
    KILLED (single occurrences, look like flakes), and one timeout.
  - **38527329846** (`alpine/kmemleak-nomit-zpool_get_006_pos-x40`: the
    same + the 006 fix, same patch as `71c7ea005`): **40/40 success**,
    both VMs finished everywhere, 100% of tests, 0 leak reports, no
    unexpected results. Slower VM 2h44/3h47/4h44. -> validates the 006
    fix (0/40 vs 2/40 without it under nomit; 21/60 with mitigations).
  - Compare mitigations on (CI-RUN-2026-10-13-kmemleak-x60.md): 6/60
    jobs finished both VMs, 89.6% of tests.
- **Hang found (nomit-16, EPYC 7763, vm2):** `cli_root/zpool_offline/
  zpool_offline_spare` hung at 1h30 after `zpool online testpool2
  file-vdev-3`, i.e. in the next step `zpool offline -f` on the spare
  that had just been used by `zpool replace`. KILLED after 10 min; vm2
  then cascaded (18 KILLED, 65 FAIL) until the 300-min limit. The test
  took ~3 s in the other 79 jobs. No kernel messages (Alpine has no
  hung-task detector) -> cause unknown; possibly a real ZFS hang, watch
  for a repeat. Log: `~/Development/logs/kmemleak-nomit-38451666300/
  alpine3-24-kmemleak-nomit-16.log` + artifact.
- **User's comment on `#19382`** (2026-10-14 07:33 UTC, issuecomment-
  6163304080): reports the nomit run (34/40, one timeout, ~4 h), argues
  no security risk in CI, could be scoped to the kmemleak runner;
  proposes (1) drop the PR and the `is_kmemleak` skip, or (2) keep the
  PR and skip only with `is_kmemleak && ! is_mitigation` (leans to 2).
  Checked: claims correct; the timeout was the hang above, not
  slowness; +10 min for 009 would exceed 300 min only for the slowest
  job (4h54). `is_mitigation` does not exist in libtest.shlib -- my
  suggestion: read `/sys/devices/system/cpu/vulnerabilities/
  spec_rstack_overflow` and skip only on "Safe RET" (covers nosrso,
  nomit, and Intel). Waiting for behlendorf.
- **Next steps:** behlendorf's answer on #19382; PR for the 006 fix
  (evidence: 21/60 -> 0/40, local 324-check comparison); possibly PR
  the nosrso/nomit commit (`3605e5bc7`) and `mitigations=off` for the
  kmemleak runner; trimmed `zfs_get_009_pos` (his suggestion); still
  open from before: zarcsummary one-liner, ksh93 fix, cleanup.
- Analysis scripts: `~/Development/logs/kmemleak-nomit-*/analyze.sh`,
  copy in `claude-notes/kmemleak-nomit-analyze.sh` (fixed 2026-10-14:
  `grep -c` exit 1 on zero leaks made `|| echo "?"` print every job
  twice).

## Update (2026-10-15): 120 kmemleak jobs with zfs_get_009_pos enabled

- **Runs:** alex-moch **38609815452** (`alpine/kmemleak-nomit-009-full-x40`,
  base b060bcb1d + dhcpcd + kmemleak + new 009 commit (`has_mitigations`,
  `timeout = 900`) + 006 fix + nosrso/nomit + DEBUG x40) and m68k-io
  **38617630151** (`claude/kmemleak_nomit_upstream_x20`, same on upstream
  master 465d86a78, x20). The user re-ran both: attempt 1 started ~18:00
  UTC, attempt 2 ~02:00 UTC -> 120 jobs. Re-runs replace artifacts with
  the same name, so attempt-1 artifacts are mostly gone; jobs API needs
  `/attempts/N/jobs`. Logs + scripts: `~/Development/logs/
  kmemleak-nomit-{009-38609815452,upstream-38617630151}/a{1,2}/`,
  `analyze.sh <repo> <run> <attempt>`, `summarize.py`, `failcause.py`
  (first non-SUCCESS line of a failed test from the Test Summary group;
  none = FAIL came from kmemleak).
- **Outcome:** 104 success (86.7%), 9 ran to the end with unexpected
  results, 5 hit the 300-min step, 1 build timeout (overloaded host),
  1 lost runner. Attempt 1: 50/60, attempt 2: 54/60. Without the 4
  infrastructure failures: 12/116 = 10.3% not green (summarize.py fixed
  2026-10-15: a job without log was counted as success).
- **zfs_get_009_pos:** always on vm1. 116 PASS, min/median/max
  3:32 / 6:24 / 9:34, none over 600 s. 2 KILLED at 15:03/15:04 (900 s
  limit) - both on the two overloaded hosts of attempt 1 (jobs 15, 25,
  build 26/30 min, everything ~3x slow), which hit 300 min anyway.
  Per CPU medians: 9V45 4:07, 9V74 5:14, 8573C 6:05, 8370C 7:03, 7763 7:15.
- **VM times (113 jobs, both finished):** vm1 2:51/3:37/4:15, vm2
  2:35/3:58/4:58; vm1 slower in only 28. vm2 is the bottleneck and its
  max 4:58 is at the 300-min edge.
- **Leaks:** 1 report in 73 jobs with artifacts: alex-moch attempt 2
  job 13, vm2, `zpool_import_errata4` (test itself passed). 64-byte
  `spa_log_sm_t` from `spa_log_sm_alloc()` <- `spa_generate_syncing_log_sm()`
  <- `spa_flush_metaslabs()`, comm txg_sync; hex: sm_obj 11, txg 708,
  nblocks 1, **mscount 1**. Both free paths (`spa_cleanup_old_sm_logs`,
  `spa_unload_log_sm_metadata` with VERIFY0(mscount)) look complete and
  mscount 1 says it was still in use -> possibly a kmemleak false
  positive; not investigated further. Report saved in
  `logs/kmemleak-nomit-009-38609815452/a2/leak-13/`.
- **Hangs:**
  - `zpool_offline_spare` hung again (m68k-io attempt 2 job 09, 8573C,
    vm2: KILLED 10:02, then 18 KILLED) - 2nd occurrence after nomit-16
    on 13 Oct, same cascade. Reproducible at ~1 in 100 jobs.
  - **New:** alex-moch attempt 2 job 33 (9V74), vm2 froze in
    `removal_with_errors` right after `removal_with_dedup`; no output
    for 2.5 h, test-runner never printed KILLED (600 s kill did not
    work), sysrq "backtrace of all active CPUs" printed nothing (no CPU
    busy -> blocked tasks, not a spin). No dmesg collected.
  - The 3rd non-slow-host timeout (alex-moch attempt 1 job 31, 9V45) was
    just slow: vm2 still progressing at 4:59.
- **Real (non-leak) failures, singles unless noted:** `raidz_expand_001_pos`
  x3 (check_pool_status errors + "unable to open vdev tree"),
  `zpool_expand_001_pos`/`_006_pos` (same job: "never expanded"),
  `dio_read_verify_decline` ("Direct I/O was not declined: 89 direct
  reads"), `large_dnode_008_pos` ("Holes in dnode array: pct empty 6 > 5",
  2nd time), `ctime_001_pos`, `zarcsummary_001_pos` (ksh, cluster 15).
- **Infra:** m68k-io attempt 1 job 14 lost its runner after ~3 h ("The
  hosted runner lost communication with the server"), no log.
  Pushing master to m68k-io starts every push workflow; cancel them AND
  wait until they are completed before pushing a debug branch, else the
  cancelled zfs-qemu run's always() Cleanup job queues behind the new
  jobs (fix: `gh api -X POST .../runs/<id>/force-cancel`).
- **Plan agreed 2026-10-15:** Brian chose option 1: plain `alpine3-24`
  boots with `kmemleak=on mitigations=off` by default, with suffixes
  `-kmemleak`, `-nokmemleak`, `-mit`, `-nomit` as overrides. Sequence:
  wait for attempt 3 of both runs (started 2026-10-15 ~08:00 UTC) and
  for #19382 + #19401 (both approved) to merge; then rebase master and
  write the CI commit. Pitfalls noted: match suffixes with the leading
  dash (`*kmemleak*` also matches `nokmemleak`), and let
  qemu-6-tests.sh decide `-m` from the VM's kmemleak state, not the
  name. Running-time summary for the switch: slower VM 2:51/3:58/4:58,
  6 of 113 jobs >= 4:30; recommend Run tests step 300 -> 330 min.
  Upstream baseline (since 1 Oct, no kmemleak): 79/3772 jobs failed in
  Run tests (2.1%), ours 3/116 (2.6%) without overloaded hosts; data in
  `~/Development/logs/upstream-baseline-202610/jobs.tsv`.
- **m68k-io 38617630151 attempt 3** (started 2026-10-15 08:00 UTC,
  European morning): 19/20 green, no timeouts, 0 leak files, slower VM
  2:53/4:00/4:15, zfs_get_009_pos 20 PASS (max 7:51). The one red job
  (03, 9V74) had `mmp_active_import` + `raidz_expand_001_pos` FAIL, cause
  unknown: Test Summary groups were "0 KiB" and the artifact has no vm1
  test output (also missing in 2 other artifacts: alex-moch a1-35 both
  VMs, a2-16 vm2, so leak counts there are incomplete). vm1 console:
  "soft lockup - CPU#0/#1 stuck for 46s" at uptime 5008 s (~09:44), a
  host stall ~40 min before the mmp test. `raidz_expand_001_pos` is now
  4 of 140 jobs, the most frequent failure. Totals after 140 jobs:
  123 green. Combination run (DEBUG, 5x each of alpine3-24,
  -nokmemleak, -mitigations, -nokmemleak-mitigations on top of
  alex-moch alpine/kmemleak-default): m68k-io 38736940076, branch
  claude/kmemleak_default_combos_x20, started 2026-10-15 ~12:10 UTC.
- **alex-moch 38609815452 attempt 3** (2026-10-15 08:00 UTC): 37/40
  green. Job 16 (9V74): **`zpool_offline_spare` hang, 3rd time** (vm2
  KILLED 10:01 at 01:23, then 20 KILLED, step hit 300 min). Job 27:
  "Start build machine" timed out after 10 min with no output from
  qemu-2-start.sh (image download or VM start, infra). Job 35:
  `autotrim_config` FAIL (in #19341 as "fix ready"). 0 leak files, 009
  39 PASS max 8:01, slower VM 2:55/3:59/4:34.
- **Totals, 180 jobs:** 160 green (88.9%). Per attempt: evening 50/60,
  night 54/60, morning 56/60. Slower VM 2:51/3:58/4:58 (171 jobs).
  Timeouts 6: 2 overloaded hosts, 3 hangs (offline_spare x2,
  removal_with_errors x1), 1 slow 9V45. zfs_get_009_pos 175 PASS, max
  9:34. Leak reports: 1 (errata4). zpool_offline_spare hang: 3 of ~220
  jobs incl. 13 Oct.
- **First matrix run of the new default** (alex-moch 38731367139, push
  of `alpine/kmemleak-default`, 2026-10-15 12:00 UTC): plain
  `alpine3-24` booted with `kmemleak=on mitigations=off`, vm1 3:48 /
  vm2 4:06, zfs_get_009_pos PASS 7:21, only unexpected result
  `ctime_001_pos` -> job red. almalinux10 red only from the Lustre
  build (`modprobe lustre`: Cannot allocate memory, lustre-exitcode 1),
  debian12 red from `dbufstats_002_pos` + `autotrim_config` (both in
  #19341). Logs: `~/Development/logs/kmemleak-default-38731367139/`.
- **ctime_001_pos on Alpine = musl time() vs coarse inode clock** (2 of
  ~181 kmemleak jobs): "st_atime: BAD time change: t1(..880),
  t2(..882), expected t2 within [..883, ..883]". ctime.c (8486ea36f,
  1d73c26c2, gmelikov) requires t2 >= time(NULL)+2 taken before the
  sleep. ZFS stamps with `gethrestime()` = `ktime_get_coarse_real_ts64`
  (include/os/linux/spl/sys/time.h:69), which advances per tick. glibc
  `time()` on x86_64 is `__vdso_time` = coarse basetime
  (lib/vdso/gettimeofday.c:408), so it agrees with the inode clock.
  musl `time()` is `clock_gettime(CLOCK_REALTIME)` (src/time/time.c),
  up to one tick ahead. Right after a second boundary musl says N while
  the inode gets N-1. Not kmemleak-specific, musl-specific. Fix idea:
  take `before` (and the wait loop) from CLOCK_REALTIME_COARSE where
  available. Not reported anywhere yet (#19341 has crtime_001, a
  different test).
- **ctime_001_pos fix built** (2026-10-15): branch `claude/ctime_coarse_clock`
  (`380af7778`, worktree `~/Development/zfs-ctime`, on upstream master
  22013c391), patch `~/Development/0001-ZTS-compare-ctime_001_pos-
  timestamps-with-the-coarse.patch`. `coarse_time()` reads
  CLOCK_REALTIME_COARSE (fallback time()) for `before` and the wait,
  `after` stays time(). Introduced by 8486ea36f (gmelikov, 3 Sep), which
  replaced the t2-t1 check (same clock) with a time() window. Evidence
  in `~/Development/ctime-repro/`: `boundary.c` (touch right after the
  clock ticks over: musl time() 30/30 stamped a second early, coarse
  0/30), `align.c` + `run-compare.sh` (start the binary right after a
  second boundary, on a file pool): old 10/40 failed with the CI
  message, new 0/40, plus 0/5 with xattr=on. cstyle clean, applies to
  master. Not pushed, no PR yet.
- **failmode_dio_unwritable fails on every Alpine run** (2026-10-16):
  new test from 602c474a2 (#19346, patrickdk77, merged 15 Oct) checks
  `grep -q "Input/output error"` on stride_dd's perror() output. musl
  says "I/O error" (src/errno/__strerror.h:40), glibc "Input/output
  error" (errlist.h:34). Seen in alex-moch 38803003863 (rebased
  kmemleak-default, the only unexpected result, write did return EIO).
  Fix: branch `claude/failmode_dio_musl_eio` (worktree
  `~/Development/zfs-dio-eio`), `grep -qE "Input/output error|I/O error"`
  like 75c6fb77b (procfs_list_stale_read), patch in ~/Development.
  Verified locally 2026-10-16: built master + fix in the worktree, loaded
  with scripts/zfs.sh, in-tree zfs-tests.sh -t. Upstream copy FAIL with
  the CI message, fixed version PASS ("write: I/O error"), modules
  unloaded afterwards. Logs ~/Development/logs/dio-eio-*.txt.
- **240 jobs + combination run evaluated (2026-10-16):** see
  `claude-notes/CI-RUN-2026-10-16-kmemleak-240-and-combos.md`. 211/240
  green, slower VM median 3:59, max 4:58; `removal_with_errors` hung a
  2nd time, new `zvol_stress` hang; all four suffix combinations boot
  with the intended options.
- **`#19426` opened 2026-10-16 05:25 UTC** -- CI: make kmemleak and no CPU
  mitigations the Alpine default (`alex-moch:alpine/kmemleak-default`,
  `fd62344af`, on master 602c474a2). Description quotes the 240-run
  stats and the combination run. Expected red on its own Alpine job:
  `failmode_dio_unwritable` (musl EIO string, separate PR planned from
  `claude/failmode_dio_musl_eio`) and possibly `ctime_001_pos` (fix on
  `claude/ctime_coarse_clock`, no PR yet). The user will explain the
  first in a PR comment.
