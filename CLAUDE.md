# OpenZFS on Alpine — CI enablement project

## Goal

Get the GitHub Actions **Alpine CI runner** (`zfs-qemu.yml`, matrix entry
`alpine3-24`) passing the ZFS Test Suite (ZTS) on this fork,
`https://github.com/m68k-io/zfs`. Upstream is `openzfs/zfs`; `master` here
tracks upstream `master`.

## Working principles

- **Small, targeted fixes.** One narrow cause per branch/commit, same
  shape as the three existing `claude/*` branches (one file, one root
  cause, one commit each).
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
  an interrupted test run wedged the (`--enable-debug`) kernel module
  into a hang with nothing captured in pstore, and required an external
  hard reboot to recover (2026-08-23). If a pool/process/unmount reports
  busy: stop, investigate (`fuser`, lingering test processes), or let
  the test harness's own cleanup/interrupt path handle it — don't force
  it.
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
  token configured yet, so no push/PR/API access — ask before assuming
  it's available.
- `master` — mirrors upstream `openzfs/zfs` master, unmodified.
- `baseline` — the base branch for all future work. All new branches
  fork from `baseline` and are named `claude/<topic>` (e.g.
  `claude/mmp`). `baseline` itself + `master` + Alpine/musl build fixes:
  - `4cac946ce` — `alignas(type)` is C11; musl's `stdalign.h` exposes it
    unconditionally (unlike glibc, which gates it behind C11), so it broke
    the `-std=gnu99` build. Fixed with `alignas(__alignof__(uint64_t))`.
  - `493476596` — fixed stale CDDL boilerplate in the FIDEDUPERANGE tests
    that broke `spdxcheck.pl`.
  - `0abdab84f` — **DEBUG**, intentionally permanent on this staging fork:
    restricts CI to a runner subset (`alpine3-24, almalinux10, debian13,
    fedora44, freebsd15-1r, ubuntu26`) to save cycles while iterating.
    Stays here — see "This fork is a staging area" above.
- Three unmerged, one-commit fix branches, each stacked directly on
  `baseline` and each targeting one known Alpine-specific ZTS failure
  cluster (see below). Not yet merged into `baseline`, not yet re-tested
  in CI:
  - `origin/claude/mmp` (`a4283ddbe`) — musl's `gethostid()` ignores
    `/etc/hostid` and always returns 0, so `mmp_set_hostid` (used by ~13
    `mmp/*` tests) never matched. Fix falls back to reading the hostid file
    directly with `od` when `hostid` disagrees.
  - `origin/claude/history_uncompress` (`8ce47cb1b`) — Alpine has no
    `uncompress` binary; swapped in `gunzip` (handles `.Z`, accepts `-f`)
    in `history_001_pos`/`history_007_pos`.
  - `origin/claude/user_namespace` (`8ae2ff41c`) — `readlink -f` on
    Alpine resolves `touch`/`chmod` through the `busybox` symlink to the
    `/bin/coreutils` multi-call binary, losing the `argv[0]` BusyBox uses
    to pick the applet ("unknown program"). Fix drops the `readlink -f`.

  These three branches likely need to be rebased together onto one branch,
  validated locally (see below), and merged into `baseline`.

## Latest CI run: `logs/qemu-alpine3-24_20260713/`

From GitHub's Alpine 3.24 runner, **on `baseline` (i.e. without the three
fix branches above)**. Build succeeded (`build-exitcode.txt` = 0).
`summary.txt`: **1951 PASS / 58 FAIL / 49 SKIP (94.80%)**, split into
tests with known/expected non-PASS results (unrelated to Alpine) and
tests that are unexpectedly non-PASS on Alpine — the latter is the actual
target list. Full per-test output is in `failed.txt`
(`<summary>test_name</summary><pre>...</pre>` blocks, ripgrep-friendly).

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
6. **Note for later, not yet acted on**: `zfs-tests.sh` reports `Missing
   util(s): capsh groupadd groupdel groupmod useradd userdel usermod` on
   this VM — the `shadow` package (has `useradd`/`groupadd`/etc.) is
   available in the Alpine repos but genuinely isn't in CI's `alpine()`
   dep list either, so this isn't a local-environment gap, it's true of
   the real CI runner too. Deliberately left uninstalled to keep this VM
   matching CI's environment exactly. Plausibly related to the
   `zoned_uid_*` failures in cluster 6 (untriaged) — worth checking
   whether those tests skip or fail because of it, next time that
   cluster is investigated.

## Current status / next steps

- Basics are done: `baseline` builds and installs cleanly, kernel module
  loads, ZTS runs (both file-vdev and real-disk modes confirmed with a
  single smoke test). Not yet run the full suite locally, and not yet
  dug into any specific failure cluster — waiting on direction for what
  to do next (full local run to confirm parity with the logged CI
  failures? validate the three `claude/*` fix branches against their
  targeted tests? something else?).
- The three unmerged `claude/*` fix branches (mmp, history_uncompress,
  user_namespace) still need local validation before merging into
  `baseline`, per user's preference.
- GitHub token not yet available — user may add one later.
