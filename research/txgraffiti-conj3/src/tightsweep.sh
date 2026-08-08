#!/usr/bin/env bash
# Exhaustive (or sampled) search of the extremal cubic family on n = 10t
# vertices, splitting the base graphs D across parallel jobs.
#
#   ./tightsweep.sh <b> [jobs] [extra args for ./tight ...]
#
# b = |V(D)| = 4t, so the constructed graphs have n = 10t = 5b/2 vertices.
# D ranges over ALL loopless cubic multigraphs on b vertices, connected or
# not: parallel edges still give a simple G, and the pairing can join
# components of D while G stays connected (see notes.md, Theorem 3).
set -u
b=$1; shift
jobs=${1:-4}; shift || true
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; mkdir -p "$logs"
n=$((b * 5 / 2))
tag="tight-n${n}"
start=$(date +%s)

if [ ! -s "$logs/$tag.D.multig" ]; then
  nauty-geng -q -d1 -D3 "$b" 2>/dev/null \
    | nauty-multig -q -r3 -T > "$logs/$tag.D.multig"
fi
total=$(wc -l < "$logs/$tag.D.multig")

for ((j = 0; j < jobs; j++)); do
  (
    awk -v j="$j" -v m="$jobs" 'NR % m == j' "$logs/$tag.D.multig" \
      | "$here/tight" "$@" > "$logs/$tag.part$j.out" 2> "$logs/$tag.part$j.err"
  ) &
done
wait

end=$(date +%s)
cat "$logs/$tag".part*.out > "$logs/$tag.out"
{
  echo "=== extremal cubic family, n=$n  (D = loopless cubic multigraphs on $b vertices)"
  echo "    base graphs=$total   elapsed=$((end - start))s"
  awk '/^base_graphs=/ {split($2,a,"="); split($3,c,"="); split($4,d,"=");
                        g+=a[2]; ce+=c[2]; ns+=d[2]}
       /^min_covering/ {split($1,m,"="); if (mc=="" || m[2]<mc) mc=m[2]}
       END {printf "    pairings tested=%d   counterexamples=%d   pairings with no covering transversal=%d\n", g, ce, ns;
            if (mc!="") printf "    min number of covering transversals over all pairings = %s\n", mc}' \
      "$logs/$tag".part*.err
} | tee "$logs/$tag.summary"
grep -h COUNTEREXAMPLE "$logs/$tag.out" 2>/dev/null | head
rm -f "$logs/$tag".part*.out "$logs/$tag".part*.err
