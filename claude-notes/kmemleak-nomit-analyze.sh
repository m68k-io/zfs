#!/bin/bash
# analyze.sh: full-suite kmemleak run with mitigations=off (alex-moch run
# 38451666300). Downloads job logs and artifacts, then prints per job:
# CPU, kernel parameters, whether each VM finished, tests run, leak
# report files, and unexpected results. Compare with
# claude-notes/CI-RUN-2026-10-13-kmemleak-x60.md (same setup, mitigations on).
cd "$(dirname "$0")"
repo=alex-moch/zfs; run=38451666300
gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" \
  --jq '.jobs[]|select(.name|test("qemu-x86"))|"\(.id) \(.name)"' |
while read -r id name; do
  n=$(echo "$name" | sed -E 's/.*\((.*)\)/\1/')
  [ -s "$n.log" ] || gh api --allow-escape-sequences \
    "repos/$repo/actions/jobs/$id/logs" > "$n.log" 2>/dev/null
done
gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" \
  --jq '.artifacts[]|"\(.id) \(.name)"' |
while read -r id name; do
  [ -s "$name" ] || gh api "repos/$repo/actions/artifacts/$id/zip" > "$name" 2>/dev/null
done
echo "job|cpu|cmdline|finished VMs|tests run (of 2156)|leak reports|unexpected"
for f in alpine3-24-*.log; do
  s=$(sed 's/\x1b\[[0-9;]*m//g' "$f")
  cpu=$(echo "$s" | grep -aom1 'vm1: \[ *[0-9.]*\] smpboot: CPU0: .*(family' |
    sed -E 's/.*CPU0: //; s/ *\(family//; s/\(R\)|\(TM\)|CPU|Processor|@.*//g; s/ +/ /g; s/ $//')
  cmd=$(echo "$s" | grep -aom1 'vm1: \[ *[0-9.]*\] Command line: .*' |
    grep -oE '(kmemleak|mitigations|spec_rstack_overflow)=[a-z]+' | tr '\n' ' ')
  fin=$(echo "$s" | grep -aoE 'vm[12]: Running Time:' | sort -u | wc -l)
  last=$(echo "$s" | grep -aoE '\[vm[12]: [0-9:]+ +[0-9]+\([0-9]+\|[0-9]+\)\]' | tail -1 |
    grep -oE '\(([0-9]+)\|([0-9]+)\)' | tr -d '()' | awk -F'|' '{print $1+$2}')
  a="qemu-${f%.log}.tar.bz2"
  leaks=$( [ -s "$a" ] && tar -tjf "$a" 2>/dev/null | grep -c '/kmemleak$' || echo "?")
  unexp=$(echo "$s" | grep -aoE ' vm[12]: +(FAIL|SKIP|KILLED|PASS) +[^ ]+ +\(expected [A-Z]+\)' |
    sed -E 's/ +/ /g; s/^ //' | sort -u | tr '\n' ';')
  echo "${f%.log}|${cpu:-?}|${cmd:-?}|$fin|${last:-?}|$leaks|$unexp"
done
