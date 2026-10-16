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
