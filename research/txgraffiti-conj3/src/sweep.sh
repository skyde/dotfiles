#!/usr/bin/env bash
# Exhaustive sweep of all connected r-regular graphs of order n.
#
#   ./sweep.sh <r> <n> [jobs]
#
# Splits nauty-geng's search tree across `jobs` processes with res/mod and
# feeds each stream to ./search --stats.  Writes a per-run log and a merged
# gap histogram to ../logs/.
set -u
r=$1; n=$2; jobs=${3:-4}
here="$(cd "$(dirname "$0")" && pwd)"
logs="$here/../logs"; mkdir -p "$logs"
tag="r${r}n${n}"
start=$(date +%s)

for ((j = 0; j < jobs; j++)); do
  (
    nauty-geng -qc -d"$r" -D"$r" "$n" "$j/$jobs" 2>/dev/null \
      | "$here/search" --stats > "$logs/$tag.part$j.out" 2> "$logs/$tag.part$j.err"
  ) &
done
wait

end=$(date +%s)
cat "$logs/$tag".part*.out > "$logs/$tag.out"
rm -f "$logs/$tag".part*.out

{
  echo "=== r=$r n=$n  (${jobs} jobs, $((end - start))s) ==="
  awk '/^read=/    {split($1,a,"="); split($2,b,"="); split($3,c,"=");
                    read+=a[2]; tested+=b[2]; ce+=c[2]}
       /^maxi /    {if ($2>mi) mi=$2;
                    if (mm=="" || $4<mm) mm=$4; ties+=$6}
       /^gap /     {h[$2]+=$4}
       END {printf "graphs=%d  counterexamples=%d\n", tested, ce;
            printf "max i(G)=%d   min mu*(G)=%d   ties(i==mu*)=%d\n", mi, mm, ties;
            for (g in h) printf "  gap %s : %d\n", g, h[g] | "sort -k2,2n"}' \
      "$logs/$tag".part*.err
} | tee "$logs/$tag.summary"

grep -h COUNTEREXAMPLE "$logs/$tag.out" 2>/dev/null | head
rm -f "$logs/$tag".part*.err
