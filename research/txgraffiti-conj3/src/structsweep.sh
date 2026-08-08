#!/usr/bin/env bash
# Test each structured regular graph individually, with a per-graph time limit,
# so that one hard instance cannot hide the results for all the others.
# Writes one line per graph to logs/structured.progress.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
tsv="$here/../data/structured.tsv"
log="$here/../logs/structured.progress"
: > "$log"

ok=0; to=0; ce=0
while IFS=$'\t' read -r g name nn rr; do
  [ -z "${g:-}" ] && continue
  res=$(printf '%s\n' "$g" | timeout 25 "$here/search" 2>&1)
  if printf '%s' "$res" | grep -q 'tested='; then
    ok=$((ok + 1))
    if printf '%s' "$res" | grep -q COUNTEREXAMPLE; then
      ce=$((ce + 1))
      printf 'COUNTEREX %-22s n=%-3s r=%-3s\n' "$name" "$nn" "$rr" >> "$log"
    else
      printf 'ok        %-22s n=%-3s r=%-3s\n' "$name" "$nn" "$rr" >> "$log"
    fi
  else
    to=$((to + 1))
    printf 'TIMEOUT   %-22s n=%-3s r=%-3s\n' "$name" "$nn" "$rr" >> "$log"
  fi
done < "$tsv"

printf 'TOTAL decided=%d timeouts=%d counterexamples=%d\n' "$ok" "$to" "$ce" >> "$log"
