#!/bin/bash
# scan.sh REPO RUN_ID: print "<run> <job name> <zarcsummary_001_pos results>" per qemu job
repo=$1; run=$2
gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq '.jobs[]|select(.name|test("qemu-x86"))|"\(.id)\t\(.name)\t\(.conclusion)"' |
while IFS=$'\t' read -r id name concl; do
  r=$(gh api --allow-escape-sequences "repos/$repo/actions/jobs/$id/logs" 2>/dev/null |
      sed 's/\x1b\[[0-9;]*m//g' |
      grep -aoE 'zarcsummary_001_pos \(run as [a-z]+\) \[[0-9:]+\] \[[A-Z]+\]' |
      grep -oE '\[[A-Z]+\]$' | tr -d '[]' | sort | uniq -c | tr -s ' ' | tr '\n' ' ')
  echo -e "$run\t$name\t$concl\t${r:-none}"
done
