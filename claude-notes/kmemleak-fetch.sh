#!/bin/bash
# fetch.sh: download qemu job logs and artifacts of both kmemleak runs
cd "$(dirname "$0")"
for spec in "m68k-io/zfs 38346336842 m" "alex-moch/zfs 38346882272 a"; do
  set -- $spec; repo=$1; run=$2; tag=$3
  gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" \
    --jq '.jobs[]|select(.name|test("qemu-x86"))|"\(.id) \(.name)"' |
  while read -r id name; do
    os=$(echo "$name" | sed -E 's/.*\((.*)\)/\1/')
    echo "$repo $id $tag-$os.log"
  done
  gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" \
    --jq '.artifacts[]|"\(.id) \(.name)"' |
  while read -r id name; do
    echo "$repo ART$id $tag-$name"
  done
done > list.txt
while read -r repo id out; do
  if [[ $id == ART* ]]; then
    echo "gh api repos/$repo/actions/artifacts/${id#ART}/zip > $out"
  else
    echo "gh api --allow-escape-sequences repos/$repo/actions/jobs/$id/logs > $out"
  fi
done < list.txt | xargs -P 8 -I{} bash -c '{} 2>/dev/null'
