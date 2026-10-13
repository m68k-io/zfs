# ksh93 socketpair pipes: ECONNRESET instead of SIGPIPE (2026-10-13)

Root cause of the intermittent `cli_user/misc/zarcsummary_001_pos`
failure, and a design for fixing it in ksh93. Write-up: cluster 15 in
`../INVESTIGATIONS.md`.

| file | what |
|---|---|
| `fake.py`, `loop.sh` | zarcsummary's exact exception handler; `ksh loop.sh` vs `bash loop.sh` |
| `seq2.sh` | the same with GNU `seq \| head -1`, tallies how seq ends |
| `resetcheck.c` | proposed extra check for ksh's `pipe_socketpair` feature test |
| `peek.c` | line reads from a pipe: byte-wise vs `tee(2)` peek vs `recv(MSG_PEEK)` |
| `zarcsummary-scan.sh` | counts zarcsummary_001_pos results per job of a CI run |

Upstream: ksh93/ksh#741 (open since 2024-04-05) is this bug; #327 is a
related /dev/stdin symptom of the same socketpair pipes.
