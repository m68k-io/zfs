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
- **PR tracker (2026-08-26)** — every `claude/*` fix branch's upstream
  status as of this writing (see `claude-notes/BRANCHES.md` for the
  per-branch technical detail; this is just the submission status):
  - **Merged**: `alpine_ci_deps` (`openzfs/zfs#18988`), `mmp`
    (`#18979`), `linux-stable-kernel` (`#18980`), `history_uncompress`
    (`#18981`).
  - **Closed/withdrawn**: `get_prop_empty_value` (`#18983` — no
    confirmed real trigger, see cluster 6 above).
  - **Open**: `getopt_permute` / `mmp_write_uberblocks` (`#18994`),
    `procfs_stale_read_portable` (`#18998`), `user_namespace`
    (`#18999`), `exec_001_pos_multicall` (`#19000`).
  - **No PR yet**: `mkbusy_kill_race`, `send_progress_race`,
    `lzc_send_wrapper_splice_race`.
  - **Cluster 5's real fix (`sh.save_env` dangling pointer) lives on
    the sibling `~/Development/ksh` fork**, not this repo — see that
    project's own `CLAUDE.md`. Two clean, independent, upstream-ready
    branches exist there (`claude/upstream-save-env-fix`,
    `claude/upstream-staknam-fix`), confirmed via real CI to fully
    resolve cluster 5, but **not yet submitted to `ksh93/ksh`**
    (deliberately deferred). Until that lands, `zpool_add_001_neg`,
    `zpool_create_001_neg`, and `zfs_list_001/003/007_pos` will keep
    failing on real CI even after every branch above merges, since
    this fork's CI builds ksh93 from plain upstream `1.0`, which
    doesn't have the fix.
  - **Cluster 4 (zdb/dbuf teardown crash, BRT/DDT) fixed 2026-08-26**
    — root cause confirmed via a local ASAN build (real
    heap-use-after-free, two independent hits, identical stack both
    times), then cross-validated against 16 real cores pulled from an
    unpatched real-CI run (all 16 crashed at the identical instruction
    offset) and a patched real-CI run of the same test groups
    (74/74 PASS, 0 crashes, vs. ~50% FAIL/16-crash rate without the
    fix). Fix branch: `claude/dnode_rele_uaf`. **Not yet submitted
    upstream** — this is a real core-code fix (not a test-portability
    one), so give it the "never break other platforms" scrutiny above
    before submitting; this VM can't verify non-Alpine legs locally,
    only via real CI. See cluster 4 in `claude-notes/INVESTIGATIONS.md`
    for the full mechanism, stack traces, and validation detail.
  - **Fork synced and branches cleaned up again (2026-08-26).**
    `origin/master` confirmed byte-identical to `openzfs/zfs`'s master
    tip (`998eca979`) via direct SHA comparison; fast-forwarded local
    `master` (3 commits), rebased `baseline` onto it (trivial — only
    the permanent `**DEBUG**` commit sits on top of `master` now) and
    force-with-leased to `origin/baseline`. `claude/alpine_ci_deps`
    (merged as `#18988`) deleted, local + `origin`. All eight
    `combined-review-*` staging branches (`2` through
    `8-cluster4-fix`, the last two being this session's cluster-4
    diagnostic branches) deleted too, local + `origin` — superseded by
    a fresh `claude/combined-review-9`, built by cherry-picking every
    currently-unmerged real branch (the four open-PR ones below, the
    three no-PR-yet ones, and the new `dnode_rele_uaf` fix) onto the
    rebased `baseline`. All cherry-picks applied clean, no conflicts.
    **Update, same session**: the seven individual branches
    (`getopt_permute`, `procfs_stale_read_portable`, `user_namespace`,
    `exec_001_pos_multicall`, `mkbusy_kill_race`, `send_progress_race`,
    `lzc_send_wrapper_splice_race`) were rebased onto the new
    `baseline` too, all clean (each collapsed to its single real
    commit, same as the 2026-08-24 rebase round), force-with-leased.
    `combined-review-9` was then rebuilt from their fresh tips
    (deleted and recreated, same 8-patch cherry-pick as before). Every
    one of these pushes (7 individual branches + the rebuild) triggered
    a real CI run as usual; **per explicit instruction this round, all
    were cancelled immediately** via `gh run cancel` (confirmed via
    `gh run list` showing none left `in_progress`/`queued`) — same kind
    of deliberate one-off deferral as the 2026-08-24 16-run cancellation
    above, not a standing policy change.
  - Full annotated mapping of one specific real-CI run's failures to
    all of the above: `claude-notes/CI-RUN-2026-08-25-master.md`
    (dated snapshot, already going stale as the three open PRs above
    resolve — re-check PR state before trusting it, per the note-taking
    convention above).
