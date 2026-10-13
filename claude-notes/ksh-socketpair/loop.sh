# Usage: ksh loop.sh / bash loop.sh  (run from this directory)
# Result 2026-10-13: ksh 4/300 ConnectionResetError, bash 0/300; with the
# handler also catching ConnectionResetError, ksh 0/600.
set -o pipefail
n=0; f=0; e=""
while [ $n -lt 300 ]; do
  n=$((n+1))
  python3 ./fake.py 2>./err | head > /dev/null || { f=$((f+1)); e="$e $(cat ./err)"; }
done
echo "failed $f/300:$e" | tr -s ' ' | cut -c1-200
