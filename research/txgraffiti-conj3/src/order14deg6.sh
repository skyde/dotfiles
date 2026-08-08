#!/usr/bin/env bash
# The two remaining degrees at order 14: r = 6, and r = 7 as its complement.
# These are the expensive classes (about 21.6 million graphs each), so the
# 6-regular graphs are generated once and reused.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; work="$here/../data"
f="$work/reg14_6.g6"; c="$work/reg14_7.g6"

rm -f "$f" "$c"
nauty-geng -q -d6 -D6 14 2>/dev/null > "$f"
nauty-complg -q < "$f" > "$c" 2>/dev/null

for pair in "6 $f" "7 $c"; do
  set -- $pair
  r=$1; file=$2
  res=$("$here/search" --stats < "$file" 2>&1 >/dev/null)
  echo "$res" | awk -v r="$r" '
    /^read=/ {split($2,b,"="); split($3,cc,"="); tested=b[2]; ce=cc[2]}
    /^maxi / {mi=$2; mm=$4; ties=$6}
    END {printf "n=14  r=%-3d graphs=%-12d counterexamples=%-3d max_i=%-3d min_mu*=%-3d ties=%d\n",
                r, tested, ce, mi, mm, ties}' | tee -a "$logs/order14.summary"
done
rm -f "$f" "$c"
echo "--- order 14 complete ---" >> "$logs/order14.summary"
