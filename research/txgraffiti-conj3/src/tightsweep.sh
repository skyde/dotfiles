#!/usr/bin/env bash
# Exhaustive (or sampled) search of the extremal cubic family on n = 10t
# vertices, splitting the base graphs D across parallel jobs.
#
#   ./tightsweep.sh <b> [jobs] [extra args for ./tight ...]
#
# b = |V(D)| = 4t, so the constructed graphs have n = 10t = 5b/2 vertices.
set -u
b=$1; shift
jobs=${1:-4}; shift || true
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; mkdir -p "$logs"
n=$((b * 5 / 2))
tag="tight-n${n}"
start=$(date +%s)

nauty-geng -qc -d3 -D3 "$b" 2>/dev/null > "$logs/$tag.D.g6"
total=$(wc -l < "$logs/$tag.D.g6")

for ((j = 0; j < jobs; j++)); do
  (
    awk -v j="$j" -v m="$jobs" 'NR % m == j' "$logs/$tag.D.g6" \
      | "$here/tight" "$@" > "$logs/$tag.part$j.out" 2> "$logs/$tag.part$j.err"
  ) &
done
wait

end=$(date +%s)
cat "$logs/$tag".part*.out > "$logs/$tag.out"
{
  echo "=== extremal family, n=$n (D cubic on $b vertices, $total base graphs, $((end - start))s) ==="
  awk '{split($2,a,"="); split($3,c,"="); g+=a[2]; ce+=c[2]}
       END {printf "pairings_tested=%d  counterexamples=%d\n", g, ce}' \
      "$logs/$tag".part*.err
  grep -c COUNTEREXAMPLE "$logs/$tag.out" 2>/dev/null | sed 's/^/counterexample_lines=/'
} | tee "$logs/$tag.summary"
rm -f "$logs/$tag".part*.out "$logs/$tag".part*.err
