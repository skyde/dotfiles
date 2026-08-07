#!/usr/bin/env bash
# Measure how long an interactive zsh takes to reach a prompt.
#
#   tests/zsh-startup-bench.sh                  # 20 runs against this checkout
#   tests/zsh-startup-bench.sh -n 50            # more samples
#   tests/zsh-startup-bench.sh --budget 250     # fail if the median exceeds 250ms
#   tests/zsh-startup-bench.sh --profile        # per-function breakdown (zprof)
#   tests/zsh-startup-bench.sh --real           # measure the installed ~/. instead
#
# By default this runs against a throwaway HOME whose dotfiles are symlinks into
# the checkout, the same way tests/run-zsh-specs.sh does, so the number reflects
# the config you are about to commit and is comparable between machines. The
# plugins (autosuggestions, syntax highlighting) are only measured when they are
# installed system-wide, which is also true of the real shell.
#
# The timing loop runs *inside* zsh -f: EPOCHREALTIME gives microseconds without
# needing bash 5 (macOS still ships bash 3.2) or a python3 on PATH.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
repo="$PWD"

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not found" >&2
  exit 1
fi

runs=20
budget=""
profile=false
use_real_home=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --runs)
      runs="$2"
      shift 2
      ;;
    --budget)
      budget="$2"
      shift 2
      ;;
    --profile)
      profile=true
      shift
      ;;
    --real)
      use_real_home=true
      shift
      ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if $use_real_home; then
  bench_home="$HOME"
else
  sandbox="$(mktemp -d)"
  trap 'rm -rf "$sandbox"' EXIT
  bench_home="$sandbox/home"
  mkdir -p "$bench_home"
  for entry in "$repo"/common/* "$repo"/common/.*; do
    name="$(basename "$entry")"
    case "$name" in
      . | .. | .config | '*') continue ;;
    esac
    ln -sfn "$entry" "$bench_home/$name"
  done
  mkdir -p "$bench_home/.config"
  for entry in "$repo"/common/.config/*; do
    [[ -e "$entry" ]] || continue
    ln -sfn "$entry" "$bench_home/.config/$(basename "$entry")"
  done
fi

export HOME="$bench_home"
export ZDOTDIR="$bench_home"

if $profile; then
  # zprof has to be loaded before the config runs, so the profiled shell gets a
  # ZDOTDIR of its own whose .zshrc wraps the real one. .zshenv is symlinked
  # straight through: it is part of what we want to see.
  prof_dir="$(mktemp -d)"
  trap 'rm -rf "${sandbox:-}" "$prof_dir"' EXIT
  ln -sfn "$bench_home/.zshenv" "$prof_dir/.zshenv"
  cat >"$prof_dir/.zshrc" <<EOF
zmodload zsh/zprof
source ${bench_home@Q}/.zshrc
zprof
EOF
  ZDOTDIR="$prof_dir" zsh --no-globalrcs -i -c exit
  exit "$?"
fi

# The first startups build the completion dump and warm the page cache; they are
# not what a normal shell start costs, so they are run and thrown away.
zsh --no-globalrcs -i -c exit >/dev/null 2>&1
zsh --no-globalrcs -i -c exit >/dev/null 2>&1

report="$(
  zsh -f -c '
    zmodload zsh/datetime
    integer runs=$1
    local -a samples
    integer i
    float start
    for (( i = 1; i <= runs; i++ )); do
      start=$EPOCHREALTIME
      zsh --no-globalrcs -i -c exit >/dev/null 2>&1
      samples+=( $(( (EPOCHREALTIME - start) * 1000.0 )) )
    done
    samples=( ${(on)samples} )
    integer mid=$(( (runs + 1) / 2 ))
    integer p90=$(( (runs * 9 + 9) / 10 ))
    (( p90 > runs )) && p90=runs
    float total=0
    for s in $samples; do (( total += s )); done
    printf "%.1f %.1f %.1f %.1f %.1f\n" \
      $samples[1] $samples[mid] $samples[p90] $samples[-1] $(( total / runs ))
  ' _ "$runs"
)" || {
  echo "benchmark failed" >&2
  exit 1
}

read -r bmin bmed bp90 bmax bmean <<<"$report"

printf 'zsh interactive startup over %s runs (ms)\n' "$runs"
printf '  min %8s\n  median %5s\n  p90 %8s\n  max %8s\n  mean %7s\n' \
  "$bmin" "$bmed" "$bp90" "$bmax" "$bmean"

if [[ -n "$budget" ]]; then
  # Integer comparison on the median; a shell that takes longer than the budget
  # to appear is a regression worth failing a build over.
  med_int="${bmed%.*}"
  if ((med_int > budget)); then
    printf 'FAIL: median %sms exceeds the %sms budget\n' "$bmed" "$budget" >&2
    exit 1
  fi
  printf 'OK: median %sms is within the %sms budget\n' "$bmed" "$budget"
fi
