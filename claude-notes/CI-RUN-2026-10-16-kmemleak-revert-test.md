# CI run 2026-10-16: deliberate leak, kmemleak default runner

m68k-io **38856309105**, branch `claude/kmemleak_revert_test_x20` (see
BRANCHES.md): upstream master a9418818b + EIO fix + kmemleak default +
revert of the `zio_crypt_key_unwrap()` uio fix, 20 `alpine3-24-NN`
runners, `-T zfs_change-key` on both VMs. Logs and artifacts:
`~/Development/logs/kmemleak-revert-38856309105/`.

- **20/20 jobs red, 40/40 VMs report the leak.** Every VM has exactly
  one test with a `kmemleak` file, FAIL as unexpected.
- **78 unreferenced objects, all 78 with `zio_crypt_uios_init_os()` <-
  `zio_crypt_key_unwrap()` <- `dsl_crypto_key_open()` <-
  `spa_keystore_load_wkey()` <- `zfs_ioc_load_key()`**, comm "zfs",
  64 bytes each. 18 jobs report 4 objects (2 per VM, as expected), 2
  jobs report 3 (kmemleak false negative, seen before).
- **`zfs_change-key` itself PASSes in all 40 VMs.** It is the only test
  in the group with a failed load-key (`log_mustnot` with the old
  passphrase), but the leak is younger than kmemleak's 5 s minimum age
  at its own scan, so a later test reports it:
  `zfs_change-key_inherit` (most), `_load`, once `_location`. Running
  the whole group instead of the one test was necessary.
- Conclusion for Brian: the default runner catches a real, deliberately
  reintroduced leak in every run, but attributes it to a following
  test. Read the backtrace, not the test name.
