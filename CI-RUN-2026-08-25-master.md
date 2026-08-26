# CI run report: master @ 998eca979, Alpine 3.24 (2026-08-25)

Dated snapshot, not evergreen — this maps one specific run's failures to
known fixes/PRs as they stood on 2026-08-25. As branches merge or new
fixes land, entries here will go stale. Check current PR/branch state
before trusting an entry in this file if it's been a while.

Run: https://github.com/m68k-io/zfs/actions/runs/32901956175/job/97981041041
(user-triggered `workflow_dispatch`, full untargeted suite, Alpine only)

Base commit: `998eca979` — `master` at the time, already includes the
merged `alpine_ci_deps` PR (`#18988`: tzdata, libcap-utils, ksh93 `1.0`
branch).

## Summary

2050 PASS / 35 FAIL / 25 SKIP (97.16%), running time 5h31m.

22 of the 35 FAILs are already-known/expected (pre-existing, tracked
upstream issues unrelated to this project — casenorm, idmap_mount
kernel-version gates, various `openzfs/zfs#NNNN`-tracked flakes). Not
itemized here; see `summary.txt` in the run's artifact if needed.

The 21 **unexpected** FAILs, annotated:

## Cluster 4 — zdb/dbuf teardown crash (BRT/DDT), unresolved

Real product bug, no fix exists anywhere (not merely unmerged — nothing
has been attempted, since ~185+ local reproduction attempts across a
prior session never reproduced it; see `CLAUDE.md`'s cluster 4 section
for the full static-analysis writeup and why local repro was abandoned).

- `block_cloning/block_cloning_fideduperange_compress` — new instance,
  confirmed via `get_same_blocks`/`zdb` "Memory fault" + identical
  `dbuf_destroy → brt_vdevs_free → brt_unload → spa_unload` backtrace.
- `block_cloning/block_cloning_replay`
- `dedup/dedup_fdt_create`
- `dedup/dedup_fdt_import`
- `dedup/dedup_fdt_pacing` — new instance, confirmed via identical
  `dbuf_destroy → ddt_table_free → ddt_unload → spa_unload` backtrace,
  triggered via a `zpool sync` path rather than the `get_same_blocks`
  helper (same underlying bug, different call site).
- `dedup/dedup_legacy_create`
- `dedup/dedup_prune`
- `gang_blocks/gang_blocks_ddt_copies`
- `cli_root/zfs_rewrite/zfs_rewrite_skip_clone` — new instance, same
  crash signature, not previously catalogued (the affected-test list in
  `CLAUDE.md` has never claimed to be exhaustive).

## Cluster 5 — ksh93 `sh.save_env` dangling pointer, fixed but not yet upstreamed

Root-caused and fixed on `m68k-io/ksh` branch
`claude/upstream-save-env-fix` (real CI confirmed zero crashes with this
fix applied — see `~/Development/ksh/CLAUDE.md`). `master` still fails
these because the merged `alpine_ci_deps` PR builds ksh93 from
`ksh93/ksh`'s own `1.0` branch, which does not include this fix (only
the `m68k-io/ksh` fork does). Will not clear until the fix lands
upstream in `ksh93/ksh` (or CI is pointed at the fork, which was
deliberately avoided — see the opinion given 2026-08-25 on why pinning
CI to an unreviewed personal fork branch is a worse posture than
building plain upstream `1.0`).

- `cli_user/misc/zpool_add_001_neg` — confirmed via matching musl
  segfault in `ld-musl-x86_64.so.1` in dmesg.
- `cli_user/misc/zpool_create_001_neg` — same, confirmed via dmesg.
- `cli_user/zfs_list/zfs_list_001_pos` — new instance. Same
  instant-fail, no-ASSERTION-line shape as 003/007 below; no dmesg
  segfault line survived the ring buffer for this specific one, so
  treat as highly probable rather than dmesg-confirmed.
- `cli_user/zfs_list/zfs_list_003_pos` — confirmed via dmesg.
- `cli_user/zfs_list/zfs_list_007_pos` — confirmed via dmesg (fired
  twice, once per VM).

## Fix exists on an m68k-io branch, no PR opened yet

- `exec/exec_001_pos` → `claude/exec_001_pos_multicall`
- `user_namespace/user_namespace_001` → `claude/user_namespace`
- `cli_root/zfs_destroy/zfs_destroy_001_pos` → `claude/mkbusy_kill_race`
  (confirmed via `pgrep -fl mkbusy unexpectedly exited 0` in the log)
- `cli_root/zfs_destroy/zfs_destroy_005_neg` → `claude/mkbusy_kill_race`
- `procfs/procfs_list_stale_read` → `claude/procfs_stale_read_portable`
  (fixed 2026-08-25, `grep -E` widened to match both GNU's and Alpine's
  wording, restoring the original test's specificity)
- `rsend/send-c_stream_size_estimate` → `claude/lzc_send_wrapper_splice_race`
  (the actual root-cause fix) / `claude/send_progress_race` (an
  independent, harmless mitigation, also unmerged)

## Open PR, not yet merged

- `mmp/mmp_write_uberblocks` → PR `#18994` (`claude/getopt_permute`)

## Root-caused, deliberately not fixed

- `cli_root/zfs_get/zfs_get_006_neg` — musl `getopt_long()`
  unconditionally permutes `argv`, ignoring `POSIXLY_CORRECT`; the
  portable fix (`+` prefix on `zfs_main.c`'s optstring) is a genuine
  user-facing CLI parsing behavior change for `zfs get` on *every*
  platform, not an Alpine-specific test-portability fix — deliberately
  not implemented without an explicit go-ahead, since it's a product
  decision, not a bug fix.

## Bottom line

Cluster 4 is the only failure class here with no fix in hand at all.
Everything else just needs a PR opened (already in progress) or, for
cluster 5, the ksh93 upstream submission whenever that happens.
