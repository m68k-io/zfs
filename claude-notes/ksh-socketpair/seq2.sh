# Usage: ksh seq2.sh | sort | uniq -c ; bash seq2.sh | sort | uniq -c
# Result 2026-10-13 (GNU seq 9.11): ksh 36/500 "seq: write error:
# Connection reset by peer" (rc=1), 464 killed by SIGPIPE (rc=269);
# bash 500/500 killed by SIGPIPE (rc=141).
set -o pipefail
n=0
while [ $n -lt 500 ]; do
  n=$((n+1))
  seq 1 200000 2>./seqerr | head -1 > /dev/null
  echo "rc=$? $(head -c 80 ./seqerr)"
done
