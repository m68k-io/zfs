# CI run analysis: `claude/combined-review-10`, 2026-08-27

Dated snapshot — see `CLAUDE.md`'s note-taking convention. This branch
and its runs were deleted after this data was extracted; kept here as
the permanent record.

Run `33045199439` (`m68k-io/zfs`, second push, commit `b639740a8` --
"install prebuilt ksh93 release instead of building from source").
Overall conclusion: **failure**, but the failures are all accounted
for below; the two things this run existed to validate (cluster 4 +
cluster 5, in combination) both came back clean.

**Correction (2026-08-27, later same day)**: the original version of
this file treated every raw `[FAIL]` line as a real failure instead of
checking ZTS's own `Results Summary` split between "expected" and
"unexpected" non-PASS results. A second independent run of the same
6-fix content (`alex-moch/zfs` run `33097895692`, Alpine leg) hit
nearly the identical raw-`[FAIL]` list, and checking *that* run's own
Results Summary showed **every one of them is in ZTS's "expected"
list**, each tied to a real tracked upstream issue or an explicit
known-limitation note (`openzfs/zfs#7633` casenorm, `#14851`/"Known
issue" fault/auto_replace, `#11889` auto_spare_multiple, `#18491`
xdr_resume_bookmark_raw_with_write, "Arbitrary pool rewind is not
guaranteed" for import_rewind_device_replaced, "Known issue" for
refreserv_004_pos) -- not flakiness, not a regression, just normal ZTS
output. This run's own source log and branch are already deleted, so
the Alpine list below can't be re-verified line-for-line against a
Results Summary the same way, but given the near-total overlap with
the second run's list, treat everything under "Alpine leg" and
"FreeBSD leg" below as **very likely all expected/tracked, not a real
finding** -- the "Not yet explained" framing was wrong methodology,
not a real open question. See `CLAUDE.md`'s matching retraction for
the full account.

## What this branch carried

`combined-review-9`'s 8-commit stack (the four then-open-PR fixes, the
three no-PR-yet fixes, `dnode_rele_uaf`) plus one `**DEBUG**` commit
redirecting the Alpine ksh93 install to `m68k-io/ksh`'s `zfs` branch
(both cluster-5 fixes) via a prebuilt release. **Did not** include
`claude/getopt_long_permute` (didn't exist yet as of this push) -- so
`zfs_get_006_neg` failing on this run is expected, not a regression.

## Alpine leg (job `98427527223`) -- the one that matters for clusters 4/5

**Zero core dumps.** Every test that clusters 4 and 5 are known to
crash appeared nowhere in the failure list:
`zfs_list_001_pos`/`_003_pos`/`_007_pos`, `zpool_add_001_neg`,
`zpool_create_001_neg` (cluster 5 signature), `alloc_class_013_pos`,
`block_cloning_copyfilerange`/`_copyfilerange_fallback` (cluster 4
signature) -- all passed clean.

Actual `[FAIL]` list on this leg:
- `zfs_get_006_neg` -- expected, see above.
- `casenorm/mixed_formd_delete`, `mixed_formd_lookup`,
  `mixed_formd_lookup_ci`, `mixed_none_lookup_ci`,
  `sensitive_formd_delete`, `sensitive_formd_lookup` (all 6 casenorm
  tests).
- `cli_root/zpool_import/import_rewind_device_replaced`
- `fault/auto_replace_001_pos`, `auto_replace_002_pos`,
  `auto_spare_multiple`
- `refreserv/refreserv_004_pos`
- `send_xdr_encoding/xdr_bookmark_raw_with_write`,
  `xdr_resume_bookmark_raw_with_write`
- `vdev_zaps/vdev_zaps_007_pos`

None of these match cluster 4 or cluster 5's signature (no core dumps,
no `strlen`/`sh_envgen`/`dnode_rele_and_unlock` involvement anywhere in
the log).

## FreeBSD leg (job `98427527295`) -- same run, different platform

Also failed, with a **partially overlapping** failure list despite
sharing no musl/ksh/dnode code path with the Alpine leg:
`import_rewind_device_replaced`, `refreserv_004_pos`,
`xdr_bookmark_raw_with_write`, `xdr_resume_bookmark_raw_with_write`,
`vdev_zaps_007_pos` -- identical test names to four of Alpine's
non-cluster-4/5 failures, plus FreeBSD-only ones (`zpool_initialize_
multiple_pools`, both `casenorm` variants FreeBSD also runs,
`receive-o-x_props_override`).

**Superseded by the correction above.** Originally framed as "not yet
explained"; given the second run's confirmation that the same test
names on Alpine are all ZTS-expected/tracked, the far more likely
explanation is that these are the normal cross-platform expected-
failure set for casenorm/xdr/refreserv/import_rewind, not flakiness or
contention. Not independently re-confirmed for FreeBSD specifically
(source log gone), but no longer treated as an open mystery.

## Other legs

`ubuntu26`, `fedora44`, `debian13`, `almalinux10` all passed clean.

## Cross-reference

- `zfs_get_006_neg`'s own fix and isolated validation:
  `claude/getopt_long_permute` in `claude-notes/BRANCHES.md`.
- Cluster 4 root cause: `claude-notes/INVESTIGATIONS.md`.
- Cluster 5 root cause: `~/Development/ksh`'s own `CLAUDE.md`.
- Current combined-review branch (this one's replacement):
  `claude/combined-review-11`.
