# CI runs, 2026-10-14 to 2026-10-16: 240 kmemleak jobs and the option combinations

## Setup

- alex-moch **38609815452** (`alpine/kmemleak-nomit-009-full-x40`, base
  b060bcb1d) and m68k-io **38617630151** (`claude/kmemleak_nomit_upstream_x20`,
  upstream 465d86a78), each run four times (attempts started 14 Oct
  ~18:00 UTC, 15 Oct ~02:00, ~08:00, ~19:15). 60 jobs per attempt, all
  `kmemleak=on mitigations=off`, all with the `zfs_get_009_pos`
  (`has_mitigations`, timeout 900) and `zpool_get_006_pos` fixes.
- m68k-io **38736940076** (`claude/kmemleak_default_combos_x20`, on
  alex-moch `alpine/kmemleak-default` = the default-enablement commit):
  5 runners each of `alpine3-24`, `-nokmemleak`, `-mitigations`,
  `-nokmemleak-mitigations`.
- Logs and scripts: `~/Development/logs/kmemleak-nomit-{009-38609815452,
  upstream-38617630151}/a{1..4}/`, `.../kmemleak-default-combos-38736940076/`.
  `analyze.sh <repo> <run> <attempt>`, `summarize.py`, `failcause.py`
  live in the 009 directory.

## 240 jobs, same configuration

| | jobs |
|---|---|
| green | 211 (87.9%) |
| ran to the end, unexpected results | 18 |
| Run tests hit 300 min | 8 |
| build timeout / VM never started / runner lost | 1 / 1 / 1 |

Per attempt green: 50, 54, 56, 51 of 60. Slower VM per attempt (median):
3:59, 3:55, 3:59, 4:00. Time of day makes little difference; the outliers
are individual overloaded hosts.

**Slower VM (229 jobs, both finished):** 2:49 / 3:59 / 4:58. vm1 (holds
`zfs_get_009_pos`) 2:49 / 3:38 / 4:15, vm2 2:30 / 3:59 / 4:58. vm1 slower
in 57 of 229.

**`zfs_get_009_pos`:** 235 PASS, 3:24 / 6:27 / 9:34, none over 600 s.
2 KILLED at the 900 s limit, both on the overloaded hosts of attempt 1.
Medians per CPU: 9V45 3:59, 6973P-C 4:18, 9V74 5:16, 8573C 5:50, 8370C
7:06, 7763 7:17.

**Timeouts (8):** 2 overloaded hosts (a1); hangs: `zpool_offline_spare`
x2 (m68k a2-09, alex a3-16), `removal_with_errors` x2 (alex a2-33, m68k
a4-13, both silent after `removal_with_dedup`, matches #19332),
`zvol_stress` + `zvol_stress_destroy` KILLED back to back at the end of
vm2 (alex a4-22, 8573C, new, vm2 one test short); 1 slow 9V45 (alex
a1-31, vm2 still running tests at 4:59).

**Leaks:** 1 report in 193 jobs with artifacts (alex a2-13,
`zpool_import_errata4`, `spa_log_sm_t`, possibly a false positive).
`zpool_import_errata4` ran in 177 of the first 180 jobs; its two other
FAILs were zvol devices missing on the overloaded hosts.

**Unexpected results:** `raidz_expand_001_pos` 6 (most frequent),
`ctime_001_pos` 2 (musl `time()`, fixed on `claude/ctime_coarse_clock`),
`send_encrypted_freeobjects` 2 (both a4, "Failed to create object with
number 128", new), and singles: `zarcsummary_001_pos`, `zpool_import_
errata4` (leak), `autotrim_config`, `scrub_cancel` KILLED,
`zed_synchronous_zedlet` ("file_wait_event exceeded 15.971 seconds"),
`large_dnode_008_pos`, `dio_read_verify_decline`, `zpool_expand_001/006`,
`mmp_active_import`.

## Combination run (20 jobs)

| config | cmdline | green | 009 | slower VM min/median/max |
|---|---|---|---|---|
| `alpine3-24` | kmemleak=on mitigations=off | 5/5 | PASS 4:14/7:12/8:20 | 3:03 / 4:01 / 4:13 |
| `-nokmemleak` | kmemleak=off mitigations=off | 4/5 | PASS 0:33/0:52/1:11 | 2:03 / 2:16 / 2:25 |
| `-mitigations` | kmemleak=on mitigations=auto | 1/5 | SKIP x5 (expected) | 1 finished: 4:55 |
| `-nokmemleak-mitigations` | kmemleak=off mitigations=auto | 5/5 | PASS 1:03/2:10/2:38 | 2:24 / 2:29 / 2:40 |

- Every job booted with exactly the options its name asks for.
- `-mitigations`: the only job to finish was the Intel 8573C, at 295 of
  300 min; all four AMD jobs hit the limit. SRSO again.
- Cost of kmemleak with mitigations off: median 2:16 -> 4:01 (~1.8x).
  Mitigations without kmemleak: 2:16 -> 2:29 (~10%).
- The one red `-nokmemleak` job is `zarcsummary_001_pos` (ksh, cluster 15).
- No leak reports in the two kmemleak groups.

## Fifth attempt (2026-10-16 10:27 UTC), 300 jobs per CPU

`results-a5.txt` in both directories, `per_cpu.py`, output
`kmemleak-nomit-009-38609815452/per-cpu-300.txt`.

| CPU | jobs | green | unexpected | 300 min | Run tests min (median) | slower VM (median) | zfs_get_009 (median) |
|---|---|---|---|---|---|---|---|
| EPYC 7763 | 133 | 123 (92%) | 9 | 1 | 243 | 4:03 | 7:15 |
| EPYC 9V74 | 72 | 61 (85%) | 8 | 3 | 207 | 3:27 | 5:19 |
| EPYC 9V45 | 52 | 47 (90%) | 3 | 2 | 177 | 2:58 | 3:59 |
| Xeon 8573C | 26 | 21 (81%) | 3 | 2 | 256 | 4:16 | 5:59 |
| Xeon 8370C | 8 | 8 | 0 | 0 | 274 | 4:35 | 6:57 |
| Xeon 6973P-C | 6 | 6 | 0 | 0 | 230 | 3:51 | 4:21 |
| no CPU (infra) | 3 | 1 | 0 | 0 | - | - | - |

raidz_expand_001_pos 6 (4 on 9V74), ctime 3 (all 7763), large_dnode 3,
send_encrypted_freeobjects 2, zpool_import_parallel_pos 2, others 1 each.

## 289 jobs without timeouts and infra failures (the user's definition)

"Real timeout" = the run is too slow for the limit. Hangs, panics and
overloaded hosts do not count: 0 real timeouts in 300 jobs. Removing the
8 timeouts and 3 infra failures leaves 289 jobs (`per_cpu.py --clean`,
`per-cpu-300-clean.txt`). Run tests and slower VM ZTS track each other
closely, so one of them is enough.

| CPU | Jobs | Share | Green | Unexp. | Run tests (min) | Slower VM ZTS | zfs_get_009_pos |
|---|---|---|---|---|---|---|---|
| EPYC 9V45 | 50 | 17.3% | 47 (94.0%) | 3 (6.0%) | 168 / 177 / 244 | 2:48:54 / 2:57:45 / 3:05:45 | 3:24 / 3:58 / 4:46 |
| EPYC 9V74 | 69 | 23.9% | 61 (88.4%) | 8 (11.6%) | 190 / 207 / 255 | 3:10:50 / 3:27:17 / 4:15:20 | 4:30 / 5:21 / 8:44 |
| Xeon 6973P-C | 6 | 2.1% | 6 (100%) | 0 (0.0%) | 209 / 230 / 255 | 3:29:44 / 3:50:43 / 4:15:41 | 3:57 / 4:21 / 6:04 |
| EPYC 7763 | 132 | 45.7% | 123 (93.2%) | 9 (6.8%) | 223 / 243 / 263 | 3:43:51 / 4:03:19 / 4:23:35 | 5:57 / 7:15 / 8:41 |
| Xeon 8573C | 24 | 8.3% | 21 (87.5%) | 3 (12.5%) | 215 / 255 / 291 | 3:34:59 / 4:15:57 / 4:51:47 | 4:44 / 5:57 / 7:05 |
| Xeon 8370C | 8 | 2.8% | 8 (100%) | 0 (0.0%) | 271 / 274 / 298 | 4:31:00 / 4:34:56 / 4:58:32 | 6:07 / 6:57 / 7:25 |
| Total / Average | 289 | 100% | 266 (92.0%) | 23 (8.0%) | 206 / 225 / 261 | 3:26:44 / 3:45:02 / 4:11:18 | 5:01 / 6:03 / 7:48 |

Cells min / median / max, bottom row = job-weighted average of the
per-CPU values. Share over all 300 jobs (both accounts the same mix):
7763 44.3%, 9V74 24.0%, 9V45 17.3%, 8573C 8.7%, 8370C 2.7%, 6973P-C 2.0%,
unknown 1.0%. AMD about 86%.

Run tests percentiles (min): All p10 178, p25 203, p50 239, p75 245,
p90 255, p95 266, p99 283, max 298. 9V45 p10-p95 173-185, 7763 236-255,
8573C p75 268, 8370C 271+ throughout. Without 8370C/8573C p99 would be
about 260.

## kmemleak scan creep over a run (evaluated 2026-10-17)

Scan time per test = gap between a test's last output line and its
result line in vm*/current/log. test-runner writes the result after the
kmemleak scan. Setup/cleanup are not scanned and stay at 0.01 s
(control). 250 of the 300 jobs had local artifacts (500 VMs, copies
in `~/Development/logs/scan-drift-300/local/`, from the a2..a5
directories above), script `~/Development/logs/scan-drift/scan_drift.py
<dir>`.

| hour of the run | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| median scan | 0.95 s | 1.40 s | 1.93 s | 2.66 s |

Per VM, hour 3 / hour 0 = 2.98x (p10 1.90, p90 3.70). Scans are 9% of
the runtime (p10 8%, p90 11%). The x60 run (mitigations on) went from
1.33 s to 4.49 s by hour 4 (2.29x per VM). Cause: kmemleak walks every
tracked object, and dentries/inodes left by earlier tests accumulate.
Regenerated 2026-10-17 night: per_cpu.py output and scan_drift.py
output match the numbers above (per-cpu-300.txt rewritten with the
share column the script gained later, numbers unchanged).
