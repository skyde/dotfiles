#!/usr/bin/env bash
# Measure how long an interactive zsh takes to become usable.
#
#   tests/zsh-startup-bench.sh                  # 20 runs against this checkout
#   tests/zsh-startup-bench.sh -n 50            # more samples
#   tests/zsh-startup-bench.sh --budget 250     # fail if the median exceeds 250ms
#   tests/zsh-startup-bench.sh --profile        # per-function breakdown (zprof)
#   tests/zsh-startup-bench.sh --real           # measure the installed ~/. instead
#   tests/zsh-startup-bench.sh --to-exit        # time `zsh -i -c exit` instead
#
# What is measured by default is *time to prompt*: from starting the shell to the
# line editor taking the terminal, which is the moment a keystroke would be read.
# That is the number someone opening a terminal is waiting for, and it includes
# drawing the first prompt — starship's own render is a fifth of it.
#
# `--to-exit` is the older measurement, timing `zsh -i -c exit`. It is cheaper
# and needs no python3, but it stops before the prompt is drawn and it skips
# everything the config sets up *after* the prompt, which since the plugins were
# deferred is most of what they cost. A shell that looks 22ms faster by that
# measure and identical by this one has not got faster.
#
# Both loops keep their timing inside the process being measured, so neither
# needs bash 5 (macOS still ships bash 3.2).
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
to_exit=false

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
    --to-exit)
      to_exit=true
      shift
      ;;
    -h | --help)
      sed -n '2,24p' "$0"
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

# The sandbox HOME mirrors common/ with symlinks, so ~/.local points into the
# checkout. Redirected here for the same reason as in tests/run-zsh-specs.sh: a
# tool that keeps state under ~/.local/share (zoxide does) would otherwise write
# into the working tree while being benchmarked.
if ! $use_real_home; then
  export XDG_CACHE_HOME="$bench_home/.cache"
  export XDG_DATA_HOME="$sandbox/data"
  export XDG_STATE_HOME="$sandbox/state"
  mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
fi

if $profile; then
  # zprof has to be loaded before the config runs, so the profiled shell gets a
  # ZDOTDIR of its own whose .zshrc wraps the real one. .zshenv is symlinked
  # straight through: it is part of what we want to see.
  prof_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${sandbox:-}' '$prof_dir'" EXIT
  ln -sfn "$bench_home/.zshenv" "$prof_dir/.zshenv"
  # ZDOTDIR is read from the environment by the profiled shell rather than
  # written into this file: ${var@Q} is bash 4.4 and later, and /bin/bash on
  # macOS is 3.2, where it fails with "bad substitution".
  cat >"$prof_dir/.zshrc" <<'EOF'
zmodload zsh/zprof
source $ZSH_BENCH_RC
zprof
EOF
  ZSH_BENCH_RC="$bench_home/.zshrc" ZDOTDIR="$prof_dir" zsh --no-globalrcs -i -c exit
  exit "$?"
fi

# ---- time to prompt (the default)
#
# Each run is measured inside tests/zsh_pty.py: it opens a terminal, starts the
# shell on it, and stops the clock when zle clears ICANON — the moment the prompt
# is up and a keystroke would be read. The harness's own startup is outside the
# measurement.
measure_to_prompt() {
  local i
  # The first starts build the completion dump and warm the page cache; they are
  # not what a normal shell start costs.
  python3 tests/zsh_pty.py /dev/null --time-to-prompt >/dev/null 2>&1
  python3 tests/zsh_pty.py /dev/null --time-to-prompt >/dev/null 2>&1
  for ((i = 0; i < runs; i++)); do
    python3 tests/zsh_pty.py /dev/null --time-to-prompt 2>/dev/null
  done
}

# ---- time to exit (--to-exit)
#
# The whole loop runs inside one zsh so the clock never leaves the process being
# measured. Run under a pty as well, because the config skips fzf's key bindings
# when no terminal is attached and a shell you sit in front of pays for them.
measure_to_exit() {
  local timing_script result_file
  timing_script="$(mktemp)"
  result_file="$(mktemp)"

  cat >"$timing_script" <<'SCRIPT'
zmodload zsh/datetime
integer runs=${ZSH_BENCH_RUNS:-20}
local -a samples
integer i
float start

repeat 2 zsh --no-globalrcs -i -c exit >/dev/null 2>&1

for (( i = 1; i <= runs; i++ )); do
  start=$EPOCHREALTIME
  zsh --no-globalrcs -i -c exit >/dev/null 2>&1
  samples+=( $(( (EPOCHREALTIME - start) * 1000.0 )) )
done

print -rl -- $samples >| $ZSH_BENCH_RESULT
SCRIPT

  ZSH_BENCH_RUNS="$runs" ZSH_BENCH_RESULT="$result_file" \
    ZSH_PTY_TIMEOUT=$((60 + runs * 3)) \
    python3 tests/zsh_pty.py "$timing_script" >/dev/null 2>&1

  cat "$result_file"
  rm -f "$timing_script" "$result_file"
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is needed to open a terminal to measure against" >&2
  exit 1
fi

if $to_exit; then
  measured="time to exit (\`zsh -i -c exit\`, no prompt drawn)"
  samples="$(measure_to_exit)"
else
  measured="time to prompt"
  samples="$(measure_to_prompt)"
fi

if [[ -z "$samples" ]]; then
  echo "benchmark failed: no samples" >&2
  exit 1
fi

# Statistics in awk: sorting floating point in the shell is not worth the
# trouble, and awk is on every machine this runs on.
read -r bmin bmed bp90 bmax bmean <<EOF
$(printf '%s\n' "$samples" | sort -n | awk '
  { a[NR] = $1; total += $1 }
  END {
    if (NR == 0) exit 1
    mid = int((NR + 1) / 2)
    p90 = int((NR * 9 + 9) / 10); if (p90 > NR) p90 = NR
    printf "%.1f %.1f %.1f %.1f %.1f\n", a[1], a[mid], a[p90], a[NR], total / NR
  }')
EOF

printf 'zsh %s over %s runs (ms)\n' "$measured" "$runs"
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
