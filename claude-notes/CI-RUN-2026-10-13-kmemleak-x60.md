# CI run analysis: 60 kmemleak jobs (2026-10-13)

Runs: m68k-io 38346336842 (`claude/alpine_kmemleak_x20`, 20 jobs) and
alex-moch 38346882272 (`alpine/kmemleak_x40`, 40 jobs, from
`~/Development/alpine-kmemleak-x40.patch`). Both: master `b060bcb1d` +
#19359 (kmemleak variant) + #19363 (single dhcpcd) + DEBUG (only
zfs-qemu, all runners `alpine3-24-kmemleak-NN`). Logs and artifacts:
`~/Development/logs/kmemleak-x60` (276 MB; `fetch.sh` there, copy in
`claude-notes/kmemleak-fetch.sh`). Earlier comparison run with 10 plain
+ 10 kmemleak runners: `~/Development/logs/alpine-dhcpcd-38305777607`.

## Results

- **Setup:** 60/60 jobs, 120/120 test VMs up -> dhcpcd fix holds
  (196 test VMs since the fix, none stuck).
- **Leaks:** none. No `kmemleak` report file in any of the 60 artifacts
  (a file is only written for a non-empty report; `-m` was on, detector
  initialised on every VM).
- **Coverage:** 89.6% of all tests ran. Both VMs finished in 6 jobs;
  vm1 finished in 53 (median 4h47), 7 cut 10-12 tests short; vm2 cut
  off in 54 (median 813 of 1101, best 1014). The test split is balanced
  for runs without kmemleak, so vm2 takes more of the slowdown.

## Why some finish: runner CPU

| runner CPU | jobs | both VMs finished | median tests run (of 2156) |
|---|---|---|---|
| AMD EPYC 7763 | 36 | 0 | 1853 |
| AMD EPYC 9V74 | 7 | 0 | 1955 |
| AMD EPYC 9V45 | 10 | 0 | 2055 |
| Intel Xeon Platinum 8573C | 4 | 3 | all |
| Intel Xeon 6973P-C | 2 | 2 | all |
| Intel Xeon Platinum 8370C | 1 | 1 | all |

Intel runners are already 15-30% faster without kmemleak (plain run:
Intel 99-145 min per VM, AMD 128-160); kmemleak roughly doubles both
(1.6-2.4x), pushing AMD past the 300-minute step limit. CPU taken from
the test VMs' `smpboot: CPU0:` boot line. About 1 in 8 jobs gets Intel.
Not selectable on standard hosted runners.

## Failures

Always failing on all 60, all also failing on plain runners (expected
list): `casenorm/*` (6), `fault/auto_replace_001/002_pos`,
`fault/auto_spare_multiple`, `refreserv/refreserv_004_pos`.

kmemleak only (all PASS on the 10 plain runners):

| test | failed / ran | cause |
|---|---|---|
| `cli_root/zpool_get/zpool_get_006_pos` | 21/60 | test race, cluster 16; fixed on `claude/zpool_get_006_snapshot` |
| `mmap/mmap_ftruncate` | 6/60 | kernel soft lockups 52-159 s + RCU stalls (2 vCPUs, kmemleak, 2 GB mmap); test itself prints SUCCESS |
| `redundancy/redundancy_draid_spare4` | 4/55 KILLED | runfile timeout on the slowed VM |
| `raidz/raidz_expand_001_pos` | 2/60 | `check_pool_status` errors after expansion, timing |
| `io/sync`, `fault/auto_spare_shared` | 1/60 each | not investigated |

`cli_root/zfs_get/zfs_get_009_pos` SKIPs on every kmemleak VM by design
(`is_kmemleak` -> `log_unsupported`, added in `c6ced7261`, 2016, after
55:43 with kmemleak). It was the *only* unexpected result on the three
alex-moch jobs that finished; fixed by #19382 (`maybe` entry).
