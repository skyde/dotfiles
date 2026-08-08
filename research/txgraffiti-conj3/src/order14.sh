#!/usr/bin/env bash
# Every regular graph of order 14, all degrees.
#
# For each s = 0..6 the s-regular graphs on 14 vertices are generated once and
# used twice: directly (degree s) and complemented (degree 13-s).  Generation
# dominates the cost, so generating each class once instead of twice halves
# the work.  Disconnected regular graphs are included, which is extra coverage
# beyond what Lemma 1 requires.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; work="$here/../data"; mkdir -p "$logs" "$work"
n=14
out="$logs/order14.summary"; : > "$out"

run() {   # run <degree> <file>
  local r=$1 f=$2 res
  res=$("$here/search" --stats < "$f" 2>&1 >/dev/null)
  echo "$res" | awk -v n=$n -v r="$r" '
    /^read=/ {split($2,b,"="); split($3,c,"="); tested=b[2]; ce=c[2]}
    /^maxi / {mi=$2; mm=$4; ties=$6}
    END {printf "n=%-3d r=%-3d graphs=%-12d counterexamples=%-3d max_i=%-3d min_mu*=%-3d ties=%d\n",
                n, r, tested, ce, mi, mm, ties}' | tee -a "$out"
}

for s in 0 1 2 3 4 5 6; do
  f="$work/reg${n}_$s.g6"
  [ -s "$f" ] || nauty-geng -q -d$s -D$s $n 2>/dev/null > "$f"
  c="$work/reg${n}_$((13 - s)).g6"
  nauty-complg -q < "$f" > "$c" 2>/dev/null
  run "$s" "$f" &
  run "$((13 - s))" "$c" &
  wait
  rm -f "$c"
  [ "$s" -ge 5 ] && rm -f "$f"      # the big files, reclaim space
done
sort -t= -k2 -n "$out" -o "$out"
echo "--- order 14 done ---"
