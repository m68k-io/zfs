# Draft: reply in the Alpine kmemleak enablement thread (2026-10-17)

Status: draft, not posted. Audience: OpenZFS maintainers. The user wants
to say that kmemleak exposes races more often and give statistics.
Numbers checked against `CI-RUN-2026-10-16-kmemleak-240-and-combos.md`
(300 jobs, clean table) and the smoke run (test body times).

---

A word of caution about this runner once kmemleak is on by default.

Without kmemleak, the Alpine job is one of the fastest Linux runners. With
kmemleak it becomes the slowest, because every allocation is tracked and
memory is scanned after each test. That widens race windows considerably.
In `zpool_offline_spare`, for example, the test itself runs about three
times slower with kmemleak. Timing-dependent bugs that rarely show up
elsewhere therefore tend to surface here first.

So far, every failure of this kind I traced also reproduced on other
distributions when run often enough. When this job fails and the others
pass, please don't assume it is an Alpine problem. It is more likely an
existing race that kmemleak made visible.

Some numbers from 300 runs with `kmemleak=on mitigations=off`, spread
over two forks:

- None was too slow for the 300 minute step limit. Eight hit the limit
  for other reasons: three assertions (two in `zpool_offline_spare`, one
  in `zvol_stress`), two hangs in `removal_with_errors` (#19332) and three
  slow or overloaded hosts.
- Of the remaining 289 runs, 92% were green. The rest failed on known
  flakes, mostly the races mentioned above.
- The test step took 225 minutes at the median. The slowest CPU type
  (Xeon 8370C, about 3% of the runners) came closest to the limit, at up
  to 298 minutes.
- kmemleak itself reported one possible leak in 193 runs, which may be a
  false positive.

---

## Optional additions (user to choose)

1. Fixes are coming (offline_spare, large_dnode_008_pos,
   send_encrypted_freeobjects), sent separately. No PR numbers until the
   PRs exist. My advice: include, after the overnight run.
2. Tight headroom on the slowest CPU and the way out: kmemleak off on the
   slowest CPU types loses kmemleak coverage in only ~10% of runs. My
   advice: include.
3. Scan creep: scans ~3x slower by hour 3 of a run, ~9-10% of runtime,
   `drop_caches` per test group as a follow-up. My advice: wait for the
   overnight -dropcaches data.
4. Why `mitigations=off` (SRSO on the AMD runners, kmemleak scans ~30%
   faster without). Only if the PR does not explain it already.

Sources: test body 1.47 s (kml) vs 0.51 s (nokml), smoke run 39029609364,
`evaluate.py`. Scan creep: `~/Development/logs/scan-drift-300/`.
