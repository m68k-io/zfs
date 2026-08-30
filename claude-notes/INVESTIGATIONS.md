# ZFS Alpine CI investigations (m68k-io/zfs)

Moved out of `CLAUDE.md` on 2026-08-26 to keep that file focused on
current status. This is the historical root-cause narrative for
every failure cluster investigated in this project — local
validation results, real CI run summaries, and the full per-cluster
deep-dives (clusters 1-7). Mostly append-only; consult
`CLAUDE.md`'s "Current status" section for what's actually
outstanding right now, and dated `CI-RUN-*.md` snapshots for the
latest real-CI pass/fail state.

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
   - **ROOT CAUSE CONFIRMED (2026-08-26), via a local ASAN build after
     the "stop chasing local repro" call above — revisited when a
     targeted real-CI diagnostic run (see below) showed the crash
     isn't actually rare at all.** Two threads: (1) a fresh CI
     diagnostic branch (`claude/combined-review-7-cluster4-diag`,
     off `combined-review-6-saveenv-fix`) restricted the matrix to
     `alpine3-24` only, ran just the `block_cloning`/`dedup`/
     `alloc_class`/`gang_blocks` groups repeated via `-I`, and
     disabled `zdb`'s own `sig_handler()` (`cmd/zdb/zdb.c`) — it
     re-raises the caught signal after printing its own backtrace,
     which meant the one real CI core captured back on 2026-08-24
     (`core.zdb.10856`) showed `sig_handler()`'s/`raise()`'s own
     stack, not the original fault, explaining why it "added little
     beyond confirming the already-known mechanism" per that
     writeup. (2) In parallel, a local `--enable-asan --enable-ubsan`
     rebuild (uncommitted local reconfigure, never part of any
     branch) ran the same test groups in a loop.
     **First real-CI run (`-I 20`, run `32993678233`) showed the
     crash is not rare on real CI hardware at all**: roughly half of
     every test in `block_cloning`/`dedup` FAILed within the very
     first iteration on both `vm1`/`vm2`, all with the identical
     `Memory fault` in `get_same_blocks`/`log_must zdb` signature
     (confirmed via the run's downloaded artifact — every single one
     of ~39 FAILs was `zdb` itself segfaulting, no unrelated
     failures). This finally squares the "cores likely matter"
     theory from 2026-08-24 with reality: it was never a
     hundreds-of-attempts-rare race, just one that essentially never
     fires on this dev VM's 16 idle cores. Cancelled that run early
     (20 iterations of a now-clearly-frequent crash was pure waste)
     and found two more gaps before the numbers were usable: sudo
     (1.9.17) unconditionally zeros the *soft* `RLIMIT_CORE` of any
     command it runs regardless of `core_pattern` (confirmed via
     `strace`: `prlimit64(0, RLIMIT_CORE, NULL, {rlim_cur=0,
     rlim_max=RLIM64_INFINITY})`) — fixed by having
     `test-runner.py.in`'s `update_cmd_privs()` wrap the privileged
     command in a shell that raises its own soft limit back to
     unlimited before `exec`ing (allowed since sudo leaves the hard
     limit alone); and even with real cores landing (a `-I 3` run,
     `32997899467`, confirmed 30+ genuine `core.zdb.<pid>` files on
     `vm1` alone via the "Prepare artifacts" step log), every single
     one failed retrieval with `scp: remote open ...: Permission
     denied` — cores are written root-owned `0600` (crashes happen
     as root) but `qemu-7-prepare.sh` pulls them back as the
     unprivileged `zfs` user, fixed with a `sudo chmod 644
     /var/tmp/core.*` right after the test run, still as root.
     **The local ASAN build reproduced it independently, twice, with
     a full report, before the CI fix even needed to prove itself**:

     ```
     AddressSanitizer: heap-use-after-free
     READ of size 8 in zrl_owner (module/zfs/zrlock.c:170)
       dnode_rele_and_unlock (module/zfs/dnode.c:1795)
       dbuf_destroy -> dbuf_destroy (recursive, dbuf.c:3367 / 3397)
       brt_vdevs_free (module/zfs/brt.c:851)
       brt_unload -> spa_unload -> spa_evict_all -> spa_fini -> kernel_fini
     freed by a taskq worker thread in
       dnode_buf_evict_async (module/zfs/dnode.c:1393)
     ```

     Both hits (`block_cloning_clone_mmap_cached`,
     `block_cloning_replay_encrypted`, ~10 local iterations apart)
     show the byte-for-byte identical stack, same file/line numbers
     throughout, different addresses/threads — this is the exact
     mechanism theorized on 2026-08-24 ("a rare race between BRT/DDT's
     held-dnode teardown and something else touching the same dbuf
     around the same time — a background ARC/dbuf-cache eviction
     thread being the most likely suspect, not yet checked"), now
     directly proven rather than inferred from static analysis: the
     main thread's `brt_vdevs_free()` releases BRT's last hold on a
     dnode via `dnode_rele_and_unlock()`, which calls `zrl_owner()`
     on that dnode's zrlock — but a taskq thread running
     `dnode_buf_evict_async()` can free the underlying dnode buffer
     (allocated back in `dsl_pool_init` at pool load, via
     `dmu_objset_open_impl`) concurrently, so the read lands in
     already-freed heap memory. This is precisely the hazard
     `dnode_rele_and_unlock()`'s own comment warns about
     ("releasing the last hold could result in the dnode's parent
     dbuf evicting its dnode handles ... must first drop the dnode
     handle") — `brt_vdevs_free()`'s hold/release sequencing doesn't
     actually guard against it.
     **FIXED and cross-validated against real CI (2026-08-26, same
     day).** The corrected `-I 1` diagnostic run
     (`claude/combined-review-7-cluster4-diag`, run `33001855475`)
     landed 16 real `core.zdb.<pid>` files (the earlier permission
     bug — cores land root-owned `0600`, `qemu-7-prepare.sh` pulls
     them back as the unprivileged `zfs` user — was fixed first).
     Every one of the 16 crashed at the identical instruction offset
     (`0x24b800` in `libzpool.so.7.0.0`), matching the original
     2026-08-23/24 dmesg captures exactly — confirmed via `dmesg`'s
     raw segfault lines across the whole run
     (`grep -rh "segfault at" | sed -E 's/^[0-9T:.,+-]+ //' | sort |
     uniq`), not just one core. A `gdb`/`addr2line` attempt to
     symbolize one core against a freshly-built matching-commit
     binary hit the same build-id-mismatch limitation the 2026-08-24
     session ran into (resolved to a nonsensical `zio_inject_fault`)
     — not trusted, but unnecessary given the offset consistency
     above plus the ASAN mechanism below already fully explain it.

     **Root cause, confirmed via a local `--enable-asan
     --enable-ubsan` rebuild** (uncommitted local reconfigure of
     `zdb`/`libzpool`, never part of any branch — `--enable-asan`
     already existed in this tree's `configure`, just never used
     here before): two independent hits
     (`block_cloning_clone_mmap_cached`,
     `block_cloning_replay_encrypted`, ~10 iterations apart) with
     **byte-for-byte identical stacks**:

     ```
     AddressSanitizer: heap-use-after-free
     READ of size 8 in zrl_owner (module/zfs/zrlock.c:170)
       dnode_rele_and_unlock (module/zfs/dnode.c:1795)
       dbuf_destroy -> dbuf_destroy (recursive, dbuf.c:3367 / 3397)
       brt_vdevs_free (module/zfs/brt.c:851)
       brt_unload -> spa_unload -> spa_evict_all -> spa_fini -> kernel_fini
     freed by a taskq worker thread in
       dnode_buf_evict_async (module/zfs/dnode.c:1393)
     ```

     `dnode_rele_and_unlock()`'s `ZFS_DEBUG`-only assert
     (`ASSERT(refs > 0 || zrl_owner(&dnh->dnh_zrlock) != curthread)`)
     read `dnh->dnh_zrlock` *after* `mutex_exit(&dn->dn_mtx)` —
     directly contradicting the comment two lines above it ("dnode
     could get destroyed at this point, so don't use it anymore").
     `dnh` (the dnode's handle) lives in the `dnode_children_t` array
     attached to the dnode's shared parent block dbuf, and is freed
     *all at once, for every dnode slot in that block* by
     `dnode_buf_evict_async()` when that dbuf's own refcount drops to
     zero — which the trace shows can happen due to a **different**
     dnode's hold in the same block being released concurrently on
     another thread, independent of this dnode's own hold count. If
     that eviction runs between this thread's `mutex_exit()` and its
     use of `dnh`, the assert dereferences already-freed memory. This
     is exactly the mechanism theorized on 2026-08-24 ("a rare race
     between BRT/DDT's held-dnode teardown and something else
     touching the same dbuf... a background ARC/dbuf-cache eviction
     thread being the most likely suspect, not yet checked"), now
     directly proven with full allocation/free provenance rather than
     inferred from static analysis alone.

     **Fix** (`claude/dnode_rele_uaf`): capture the zrlock-ownership
     check while `dn_mtx` is still held and `dnh` is guaranteed live
     (per the "Get while the hold prevents the dnode from moving"
     comment a few lines up) — at that point this dnode's own hold,
     and the `dbuf_add_ref(db, dnh)` reference it carries (added when
     the hold was first acquired in `dnode_hold_impl()`), is still
     outstanding, which provably keeps the parent block's `dnh` alive
     regardless of what any other thread/dnode sharing that block is
     doing concurrently. `#ifdef ZFS_DEBUG` only — no non-debug/
     production behavior changes either way, so this is a
     conservative fix for the *proven* crash site; whether the same
     race could independently threaten the later
     `dbuf_rele_and_unlock(db, dnh, evicting)` call a few lines down
     was considered but not confirmed one way or the other (no crash
     evidence points there).

     **Validated**: local ASAN, 15 iterations x 2 of the two tests
     that crashed above — 60/60 PASS, 0 crashes (was 2/62 crashes
     before the fix). Real CI (`claude/combined-review-8-cluster4-fix`
     -> superseded by `claude/dnode_rele_uaf`, run `33003416194`),
     same `block_cloning`/`dedup`/`alloc_class`/`gang_blocks` test
     groups that FAILed at roughly 50% on the unpatched branch — 74/74
     PASS, 0 crashes, 0 core files, 0 `segfault` mentions anywhere in
     the logs.

     **Open question**: why real CI hits this so much more readily
     than this dev VM (essentially a coin-flip on the very first
     real-CI attempt, vs. needing ASAN's own allocation-overhead
     perturbation to catch it at all locally across ~185+ prior
     non-ASAN attempts). Leading theory, not confirmed: the dbuf
     eviction taskq always has exactly one worker thread
     (`taskq_create("dbu_evict", 1, ...)`, unscaled by CPU count — 
     checked directly in `module/zfs/dbuf.c`), so the race is always
     "one main thread vs. one dedicated evictor," and what determines
     a collision is purely whether the scheduler preempts the main
     thread inside the narrow unprotected window — far more likely on
     real CI's 2-4 contended vCPUs than this VM's 16 idle ones, where
     both threads usually just run to completion uninterrupted.
     Separately, this cluster has only ever been observed on musl
     (Alpine); the leading theory there is that glibc's per-thread
     tcache keeps freed memory thread-local and unreused for a while,
     so the same cross-thread stale read likely still happens on
     glibc but silently reads still-coherent old bytes instead of
     corrupted ones — meaning the race is probably universal, not
     Alpine-specific, and glibc's allocator just happens to usually
     mask the symptom. Neither theory independently confirmed.

     **Cross-platform validation done (2026-08-26, later the same
     day)**: the "never break other platforms" scrutiny above was
     the one gap this VM genuinely couldn't close locally. Three real
     CI runs, triggered via `workflow_dispatch` (manual re-trigger on
     an existing branch tip, no new commit needed):
     - `claude/dnode_rele_uaf` alone, full m68k-io matrix (alpine3-24,
       almalinux10, debian13, fedora44, freebsd15-1r, ubuntu26) — 5/6
       platforms clean; alpine3-24's only unexpected FAILs are
       already-known gaps unrelated to this fix (cluster 5's ksh bug,
       not fixed in this fork's build; other branches' fixes simply
       not stacked on this single-topic branch, as intended).
     - `claude/combined-review-9` (all 8 unmerged patches stacked,
       including this fix), same matrix — same 5/6 clean, and
       alpine3-24 narrows to *just* cluster 5's known gap once the
       other branches' fixes are actually present.
     - **The real test**: a full 16-platform run on the separate
       final-QA repo (`alex-moch/zfs`, `alpine/combined-review`
       branch, run `33009036571`) — the *complete* upstream CI matrix
       (centos-stream9/10, almalinux8/9/10, ubuntu22/24/26,
       fedora43/44, freebsd14-4r/15-1r/15-1s/16-0c, debian12/13).
       15/16 clean. `fedora44` showed FAILs but its own "unexpected"
       bucket was empty (all FAILs landed in ZTS's own "expected"/
       known-flaky category; non-zero exit code regardless, matching
       already-documented behavior). One genuinely unexpected
       failure: `alloc_class/alloc_class_016_pos` on `ubuntu26` —
       every assertion in the test actually passed (pool create,
       writes, sync all `SUCCESS`); the failure was `cannot destroy
       'testpool': pool is busy` at cleanup. Not cluster 4's
       signature (no `zdb`, no `get_same_blocks`, no segfault, no
       BRT/DDT/dnode involvement at all) — looks like the kind of
       background ZTS flake the "ZTS is known to be flaky" working
       principle already covers, but not independently confirmed via
       a rerun yet.
     **Zero cluster-4-signature failures anywhere** across all three
     runs (28 platform-legs total): no `zdb` segfaults, no `Memory
     fault` in `get_same_blocks`, no `core.zdb.*` files, no
     heap-use-after-free reports. This is real confirmation the fix
     doesn't regress any platform, not just Alpine.
     **Not yet done**: submitting `claude/dnode_rele_uaf` upstream,
     and confirming the `alloc_class_016_pos`/`ubuntu26` lead is
     actually flaky (rerun that one leg) rather than assuming it.
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
     **FIX CONFIRMED (2026-08-25)**: `claude/save_env_dangling_environ_ptr`
     on `m68k-io/ksh` (`import1var()` copies via `sh_strdup()` instead
     of aliasing `environ` directly). First CI validation of that alone
     (commit `2adcbd04`) still crashed identically — a second real bug
     in `sh_envgen()` itself was also repointing `sh.save_env[i]` at
     short-lived `stkalloc()` memory on every call, undoing the fix
     after the first external-command exec. Fixed in a follow-up commit
     (`31c80ef1`, that loop now only writes to the returned `er[]`
     array, never back into `sh.save_env[i]`). Full disassembly/
     register-state evidence for both rounds is in the sibling
     `~/Development/ksh` fork's `CLAUDE.md`.
     Re-ran `claude/combined-review-6-saveenv-fix` (`gh run rerun` on
     run `32824560746`, confirmed via build log it picked up `31c80ef1`)
     with this complete fix: **zero core dumps** (artifact size alone
     — 252 KB vs. 2.3-8.9 MB in every prior run — was the first sign).
     Every test that used to crash now passes clean: `zpool_iostat_-c_*`
     (all 3), `zpool_status_-c_*` (all 3), `zpool_add_001_neg`,
     `zpool_create_001_neg`, `zfs_list_003_pos`/`_007_pos`. Remaining
     failures in that run are entirely cluster 4 (the separate,
     unrelated `zdb`/dedup crash) and the two already-tracked issues
     (`zfs_get_006_neg`, `send-c_stream_size_estimate`) — **nothing
     left attributable to cluster 5**. This closes out cluster 5 after
     350+ failed local reproduction attempts across two investigations
     — it ultimately required real CI + core dumps + disassembly +
     register-state analysis, never local repro, since the trigger (an
     invalid-named env var present in CI's musl images but not this
     dev VM, combined with `sh_envgen()` running more than once) never
     lined up in any synthetic local attempt.
     **Not yet done**: getting this fix actually merged/used. It lives
     on `m68k-io/ksh`, a downstream fork — the real next step is either
     upstreaming it to `ksh93/ksh` (the maintainers own far more
     context on `sh.save_env`/`environ` lifetime than reconstructable
     from source reading alone) or, at minimum, pinning this fork's own
     `qemu-3-deps-vm.sh` to build from this fork+branch instead of
     plain upstream `ksh93/ksh` if this project wants cluster 5 to stay
     fixed outside of the diagnostic `combined-review-*` branches. The
     current `**DEBUG**`-commit staging branches used for validation are
     not meant to persist — see "This fork is a staging area" above.

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
     - **Root cause finally proven, and both fixes above corrected
       (2026-08-30).** The 2026-08-23 writeup left the mechanism "not
       fully pinned down" and flagged a contradiction between the
       observed thread ordering and `estimate_size()`'s source. That
       contradiction is resolved: the `lzc_send_wrapper()` in play is
       not the inner one reached through
       `lzc_send_space_resume_redacted()` at all.
       `zfs_send_one()`/`zfs_send()` wrap the *whole* operation
       (`libzfs_sendrecv.c:2880` and `:2578`), and the inner wrapper
       no-ops because it is handed the relay pipe, which is a FIFO.
       So the relay's `splice()` sits blocked across the entire send,
       including while `estimate_size()` prints to that same fd.
       `strace -f` shows it directly:

           lseek(1, 0, SEEK_CUR) = 0
           splice(5, NULL, 1, NULL, ...) <unfinished ...>
           writev(1, ["full\tpool/fs@snap1\t8416880","\n"]) = 31
           <... splice resumed>) = 0
           writev(1, ["size\t8416880\n"]) = 13

       `splice()` with a `NULL` `off_out` latches `out->f_pos` on
       entry and writes that latched value back on return — **even
       when it transfers zero bytes**. A dry run relays nothing, so
       the write-back rewinds fd 1 from 31 back to 0 and the "size"
       line lands on top of the "full" line. Reproduced in isolation
       with a small C program (block a `splice()`, `write()`
       concurrently, close the pipe: `f_pos` goes 21 → 0), so this is
       ordinary documented `splice()` behaviour, not a ZFS or musl
       quirk, and not Alpine-specific.
     - **The 2026-08-23 fix as committed did not actually work.** Its
       unconditional `lseek(orig_fd, ctx.pos, SEEK_SET)` resync after
       `pthread_join()` re-did the exact rewind the explicit offset
       had just prevented: the caller had already advanced the fd to
       31 while the relay was blocked, and the resync put it back to
       `ctx.pos` (still 0, nothing having been relayed). Measured on
       a rebuilt tree: **200/200 still corrupt** with that version.
       The resync is only correct when the relay actually moved
       bytes, so it is now conditional on `ctx.pos != start`. The
       earlier "40/40 clean" cannot have come from the mechanism it
       was attributed to. Note for any future A/B in this repo: the
       in-tree `zfs` binary resolves `libzfs_core.so.3` from
       `/usr/lib` unless `LD_LIBRARY_PATH` points at `.libs`, so it
       is easy to "test" installed code by accident — two runs here
       did exactly that before it was caught.
     - **`claude/send_progress_race` was a misdiagnosis and is
       withdrawn.** `send_progress_thread()` writes to `stderr` and
       nothing else — all five of its `fprintf()` calls are
       hardcoded to it — while the corrupted output is on `stdout`
       (`fout = flags->dryrun ? stdout : stderr`). It cannot have
       touched the corrupted stream; the correlation noted in 2026-
       08-23 really was only that. Branch deleted (remote and local);
       tip preserved locally as tag `dropped/send_progress_race`
       (`0e74dc641`). It was also not free as a "harmless
       improvement": it changed two `dgettext` msgids (orphaning
       existing translations), dropped the upstream GCC/UBSan
       `-Wformat-overflow` pragma, and discarded `write(2)`'s return
       value at all three sites.
     - **Two further bugs in the same function, found while fixing
       this (2026-08-30), each now its own commit and ZTS test.**
       - `splice()` refuses an `O_APPEND` destination outright,
         `EINVAL`, with or without an explicit `off_out` (all four
         combinations checked). So `zfs send >>file` never worked
         through the relay: the first `splice()` failed, the worker
         closed the pipe, and the send died of `SIGPIPE` — exit 141,
         zero stream bytes, no message. **Pre-existing, not caused by
         the offset change**: unpatched `baseline` fails identically.
         Fixed by relaying `O_APPEND` destinations with a
         `read()`/`write()` loop instead. Path selection verified by
         syscall counts: `>` gives 171 `splice()` and 0 `write(1,)`,
         `>>` gives 0 and 135.
       - When the relay fails for *any* reason it closes its end of
         the pipe under the still-writing send, which is then killed
         by `SIGPIPE` before the real error can be reported — so
         `zfs send >/dev/full` gave exit 141 and complete silence
         instead of `ENOSPC`. Fixed by blocking `SIGPIPE` across the
         relay so the write fails `EPIPE` instead, consuming the
         signal we provoked before restoring the caller's mask, and
         letting the relay's error win over whatever `func()`
         returned. FIFO destinations return long before any of this
         and keep ordinary pipe semantics, SIGPIPE included
         (confirmed: `zfs send | head -c 100` still exits 141).
         - Deliberately left imperfect: `dmu_send.c` collapses every
           output failure to `SET_ERROR(EINTR)` (`dmu_send.c:278` and
           ~9 similar sites), destroying the real errno kernel-side,
           and libzfs prints its warning from inside `func()` —
           before the relay is joined and its error is known. So the
           message still reads "signal received" or "Broken pipe"
           rather than "No space left on device". Fixing that means
           plumbing the real errno out of `dmu_send()` and moving the
           report outside the relay: a `module/` + `lib/` change,
           not attempted.
     - **Validation (2026-08-30).** Each of the three commits has a
       ZTS regression test that fails without it and passes with it,
       the other two unaffected — so all three are independently
       demonstrated, not just collectively: `rsend/
       send_dryrun_parsable` (base 300/300 corrupt, patched 0/300),
       `rsend/send_append_redirect` (base exits 269 under ksh, i.e.
       SIGPIPE), `rsend/send_dest_error` (base exit 141 and silent;
       Linux-gated with `log_unsupported`, since the relay is
       Linux-only). A 26-test `rsend` batch: 25 PASS, 1 SKIP
       (`rsend_008_pos`, known), 1 FAIL (`send-c_verify_contents`) —
       which fails on base identically and passes in isolation, i.e.
       pre-existing order dependence, not a regression. The base run
       also failed `send-c_stream_size_estimate`, the original CI
       symptom, which these fixes repair. All three commits pass
       `scripts/commitcheck.sh`. Non-regression on glibc/FreeBSD
       still cannot be verified locally, same limitation as every
       other core-code change here.
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

