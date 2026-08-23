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
  - `4cac946ce` — `alignas(type)` is C11; musl's `stdalign.h` exposes it
    unconditionally (unlike glibc, which gates it behind C11), so it broke
    the `-std=gnu99` build. Fixed with `alignas(__alignof__(uint64_t))`.
  - `493476596` — fixed stale CDDL boilerplate in the FIDEDUPERANGE tests
    that broke `spdxcheck.pl`.
  - `0abdab84f` — **DEBUG**, intentionally permanent on this staging fork:
    restricts CI to a runner subset (`alpine3-24, almalinux10, debian13,
    fedora44, freebsd15-1r, ubuntu26`) to save cycles while iterating.
    Stays here — see "This fork is a staging area" above.
- Five one-commit fix branches, each stacked directly on `baseline` and
  each targeting one root cause. Not meant to be merged into `baseline`
  (see above) — meant to go to upstream `openzfs/zfs` independently.
  **All five validated locally as of 2026-08-23** (see "Local validation
  results" below for the actual run output), not yet re-tested in CI:
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
  - `claude/tzdata` (`c5edaf6cd`, new 2026-08-23, found while validating
    `claude/history_uncompress`) — Alpine doesn't ship zoneinfo data by
    default (unlike glibc distros, which bundle it). `history_007_pos`
    sets `TZ=America/Denver` before formatting a timestamp for comparison
    against a pre-recorded expected value; without `tzdata` installed,
    the `TZ` setting silently has no effect and timestamps come out in
    UTC, 6 hours off. This is a CI-provisioning fix (`tzdata` added to
    `qemu-3-deps-vm.sh`'s `alpine()` package list), not a test-script fix
    — confirmed via `grep -rl "TZ=" tests/zfs-tests/tests/functional/`
    that `history_007_pos` is the only test affected.

  Next for these five: the user submits them upstream independently
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
  (`mmp_write_uberblocks`) needs `claude/getopt_permute` too.
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

Not yet done: submitting these five upstream, a full local ZTS run, and
re-running through actual CI.

## Latest CI runs: `logs/qemu-alpine3-24_20260713/` and `_20260823/`

Both from GitHub's Alpine 3.24 runner, **on `baseline` (i.e. without any
of the five fix branches above)**. Build succeeded both times
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
   glibc's. Root cause **not yet investigated**. Affects at least:
   `block_cloning_copyfilerange`, `block_cloning_lwb_buffer_overflow`,
   `dedup_bclone`, `dedup_fdt_import`, `dedup_legacy_create`,
   `dedup_legacy_fdt_upgrade`, likely `gang_blocks_ddt_copies`. This is
   the highest-value cluster to dig into (6-7 tests, looks like a real bug
   rather than a test-portability issue).
5. **musl `SIGILL` in `ld-musl-x86_64.so.1`** — `zpool_iostat`/
   `zpool_status` `-c` (custom command) variants and their plain
   `_005_pos`/`_003_pos` siblings crash with `trap invalid opcode` /
   `segfault ... in ld-musl-x86_64.so.1`, reported via dmesg (`libshell.so`
   involved). Distinct from cluster 4 (different crash signature). Root
   cause **not yet investigated**.
6. **Unexplained, not yet triaged**: `zfs_destroy_001_pos`/`_005_neg`,
   `zfs_get_006_neg`, `zpool_split_props`, `zfs_unmount_001_neg`,
   `zfs_list_002_pos`/`_003_pos`, `zpool_list_001_pos`, `rsend/
   send-c_stream_size_estimate`, `zoned_uid_023/025/026_pos`,
   `procfs_list_stale_read`.
7. **SKIPs that should be PASS**: `zpool_expand_*` (3), `zpool_reopen_*`
   (7), `zpool_split_wholedisk`, `zpool_import_aux_paths`, `fault/auto_*`
   (8), `procfs/pool_state`. The logged CI VM only had two disks
   (`/dev/vda` system, `/dev/vdb` `/var/tmp` scratch — see
   `vm1/df-prerun.txt`), no extra block devices, which plausibly makes
   these tests skip themselves (they need real/removable/expandable
   disks, not just loopback files). **Working theory, not confirmed** —
   needs checking against each test's skip condition. Our local VM has
   six extra scratch disks (see below), which may let us reproduce and
   fix this.

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

- Basics are done: `baseline` builds and installs cleanly, kernel module
  loads, ZTS runs (both file-vdev and real-disk modes confirmed).
- All five `claude/*` fix branches are locally validated (see "Local
  validation results" above), ready for the user to submit upstream
  independently — not this fork's job to merge or combine them (see
  "Repo layout" above for the actual flow: upstream PR -> update this
  fork's `master` -> rebase `baseline`).
- Not yet run the full test suite locally, and not yet dug into any of
  the still-untriaged failure clusters (4/5/6/7 above) — the
  `claude/getopt_permute` discovery is the closest lead into cluster 6,
  worth a dedicated sweep for other flags-after-positional-arg instances
  across the test suite.
- GitHub push/PR/API access is now working (2026-08-23) — the user
  configured credentials and `gh`. Do not write credential details,
  token values, or where they're stored into this file or anywhere else
  persistent; just that access works. All eight branches (`baseline`,
  `master`, `claude-meta`, `claude/mmp`, `claude/history_uncompress`,
  `claude/user_namespace`, `claude/getopt_permute`, `claude/tzdata`) are
  pushed and match `origin` exactly (verified via `git ls-remote`,
  2026-08-23). `claude/mmp` needed `--force-with-lease` since its commit
  was amended locally after the original push.
