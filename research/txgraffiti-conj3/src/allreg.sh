#!/usr/bin/env bash
# Exhaustive sweep over ALL regular graphs of order n, every degree r >= 1.
#
#   ./allreg.sh <n_from> <n_to>
#
# For r <= (n-1)/2 nauty-geng generates the r-regular graphs directly; for
# denser r it is far cheaper to generate the (n-1-r)-regular graphs and take
# complements.  The dense branch also picks up disconnected regular graphs,
# which is harmless (Lemma 1) and gives extra coverage.
set -u
from=$1; to=$2
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; mkdir -p "$logs"
out="$logs/allreg.summary"

for ((n = from; n <= to; n++)); do
  for ((r = 1; r < n; r++)); do
    (( (n * r) % 2 )) && continue
    s=$((n - 1 - r))
    if (( r <= s )); then
      gen="nauty-geng -qc -d$r -D$r $n"
    else
      gen="nauty-geng -q -d$s -D$s $n"
    fi
    start=$(date +%s)
    if (( r <= s )); then
      res=$($gen 2>/dev/null | "$here/search" --stats 2>&1 >/dev/null)
    else
      res=$($gen 2>/dev/null | nauty-complg -q 2>/dev/null | "$here/search" --stats 2>&1 >/dev/null)
    fi
    end=$(date +%s)
    line=$(echo "$res" | awk -v n="$n" -v r="$r" -v t="$((end - start))" '
      /^read=/  {split($2,b,"="); split($3,c,"="); tested=b[2]; ce=c[2]}
      /^maxi /  {mi=$2; mm=$4; ties=$6}
      END {printf "n=%-3d r=%-3d graphs=%-12d counterexamples=%-3d max_i=%-3d min_mu*=%-3d ties=%-10d %ds",
                  n, r, tested, ce, mi, mm, ties, t}')
    echo "$line" | tee -a "$out"
  done
done
