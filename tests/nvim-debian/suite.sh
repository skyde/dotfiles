#!/usr/bin/env bash
set -euo pipefail

repo_root=${REPO_ROOT:-/workspace/dotfiles}
artifact_dir=${ARTIFACT_DIR:-/artifacts}
soak_seconds=${SOAK_SECONDS:-0}
if [[ ${SHORT+x} ]]; then
  short_mode=$SHORT
elif [[ $soak_seconds =~ ^[1-9][0-9]*$ ]]; then
  short_mode=0
else
  short_mode=1
fi
concurrency=${CONCURRENCY:-4}
short_batches=${SHORT_BATCHES:-7}
resource_sample_seconds=${RESOURCE_SAMPLE_SECONDS:-5}
setup_timeout_seconds=${SETUP_TIMEOUT_SECONDS:-1800}
startup_timeout_seconds=${STARTUP_TIMEOUT_SECONDS:-120}
workload_timeout_seconds=${WORKLOAD_TIMEOUT_SECONDS:-300}
timeout_kill_after_seconds=${TIMEOUT_KILL_AFTER_SECONDS:-5}
timeout_selftest=${NVIM_DEBIAN_TIMEOUT_SELFTEST:-0}

case $short_mode in
  0 | 1) ;;
  *)
    printf 'error: SHORT must be 0 or 1 (got %s)\n' "$short_mode" >&2
    exit 2
    ;;
esac
if [[ ! $soak_seconds =~ ^[0-9]+$ ]]; then
  printf 'error: SOAK_SECONDS must be a non-negative integer (got %s)\n' "$soak_seconds" >&2
  exit 2
fi
if [[ $short_mode == 0 && $soak_seconds == 0 ]]; then
  printf 'error: non-short mode requires SOAK_SECONDS greater than zero\n' >&2
  exit 2
fi
for value_name in \
  concurrency \
  short_batches \
  resource_sample_seconds \
  setup_timeout_seconds \
  startup_timeout_seconds \
  workload_timeout_seconds \
  timeout_kill_after_seconds
do
  value=${!value_name}
  if [[ ! $value =~ ^[1-9][0-9]*$ ]]; then
    printf 'error: %s must be a positive integer (got %s)\n' "$value_name" "$value" >&2
    exit 2
  fi
done
case $timeout_selftest in
  0 | 1) ;;
  *)
    printf 'error: NVIM_DEBIAN_TIMEOUT_SELFTEST must be 0 or 1 (got %s)\n' \
      "$timeout_selftest" >&2
    exit 2
    ;;
esac
if [[ ! -r $repo_root/apply.sh || ! -r $repo_root/common/.config/nvim/lazy-lock.json ]]; then
  printf 'error: REPO_ROOT does not look like the dotfiles repository: %s\n' "$repo_root" >&2
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  printf 'error: GNU timeout is required by the Debian harness\n' >&2
  exit 127
fi

mkdir -p -- "$artifact_dir/logs" "$artifact_dir/errors" "$artifact_dir/nvim-state"
runtime_root=$(mktemp -d /tmp/nvim-debian.XXXXXXXX)
export HOME="$runtime_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export TMPDIR="$runtime_root/tmp"
mkdir -p -- "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$TMPDIR"

startup_attempts=0
startup_failures=0
workload_attempts=0
workload_failures=0
completed_batches=0
soak_elapsed=0
resource_samples=0
timeout_failures=0
sampler_pid=
p4d_pid=
p4d_log=
bounded_deadline=0
active_phase_pids=()
suite_started=$(date +%s)
unexpected_error_pattern='(^|[^[:alpha:]])(error|fatal|panic|traceback|segmentation fault|assertion failed)([^[:alpha:]]|$)'

monotonic_seconds() {
  awk '{ printf "%d\n", $1 }' /proc/uptime
}

register_phase_pid() {
  active_phase_pids+=("$1")
}

unregister_phase_pid() {
  local target=$1
  local pid
  local -a remaining=()
  for pid in "${active_phase_pids[@]}"; do
    if [[ $pid != "$target" ]]; then
      remaining+=("$pid")
    fi
  done
  active_phase_pids=("${remaining[@]}")
}

stop_active_phases() {
  local pid
  local have_active=0
  for pid in "${active_phase_pids[@]}"; do
    if [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
      have_active=1
      kill -TERM "$pid" 2>/dev/null || true
      kill -TERM -- "-$pid" 2>/dev/null || true
    fi
  done
  if ((have_active)); then
    sleep "$timeout_kill_after_seconds"
  fi
  for pid in "${active_phase_pids[@]}"; do
    if [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
      kill -KILL -- "-$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  done
  active_phase_pids=()
}

phase_budget() {
  local cap=$1
  local remaining
  if ((bounded_deadline == 0)); then
    printf '%d\n' "$cap"
    return
  fi
  remaining=$((bounded_deadline - $(monotonic_seconds)))
  if ((remaining <= 0)); then
    printf '0\n'
  elif ((remaining < cap)); then
    printf '%d\n' "$remaining"
  else
    printf '%d\n' "$cap"
  fi
}

start_bounded() {
  local pid_variable=$1
  local seconds=$2
  local label=$3
  local command_name
  local started_pid
  local -a command=()
  shift 3

  if ((seconds <= 0)); then
    printf 'error: %s was not started because its hard deadline expired\n' "$label" >&2
    printf -v "$pid_variable" '%s' 0
    return 124
  fi
  command_name=${1:-}
  if declare -F "$command_name" >/dev/null 2>&1; then
    export -f "${command_name?}"
    command=(/bin/bash -c 'set -euo pipefail; "$@"' nvim-debian-bounded-function "$@")
  else
    command=("$@")
  fi

  timeout \
    --verbose \
    --signal=TERM \
    --kill-after="${timeout_kill_after_seconds}s" \
    "${seconds}s" \
    "${command[@]}" &
  started_pid=$!
  register_phase_pid "$started_pid"
  printf -v "$pid_variable" '%s' "$started_pid"
}

wait_bounded() {
  local pid=$1
  local label=$2
  local status=0
  if ((pid == 0)); then
    timeout_failures=$((timeout_failures + 1))
    return 124
  fi
  if wait "$pid"; then
    status=0
  else
    status=$?
  fi
  unregister_phase_pid "$pid"
  if ((status == 124 || status == 137)); then
    timeout_failures=$((timeout_failures + 1))
    printf 'error: %s exceeded its bounded execution time (status %d)\n' \
      "$label" "$status" >&2
  fi
  return "$status"
}

run_logged() {
  local name=$1
  local bounded_pid=0
  local command_rc=0
  local display_rc=0
  local log_file="$artifact_dir/logs/$name.log"
  shift
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$name"
  if start_bounded bounded_pid "$setup_timeout_seconds" "setup phase '$name'" "$@" \
    >"$log_file" 2>&1
  then
    if wait_bounded "$bounded_pid" "setup phase '$name'" >>"$log_file" 2>&1; then
      command_rc=0
    else
      command_rc=$?
    fi
  else
    command_rc=$?
  fi
  sed -n '1,$p' "$log_file" || display_rc=$?
  if ((command_rc != 0)); then
    return "$command_rc"
  fi
  return "$display_rc"
}

run_apply() {
  local root=$1
  shift
  (
    cd "$root"
    ./apply.sh "$@"
  )
}

run_repo_test() {
  local kind=$1
  local test_file=$2
  (
    cd "$HOME"
    case $kind in
      lua) nvim --headless -u NONE -i NONE -l "$test_file" ;;
      full-lua)
        nvim --headless -i NONE \
          -c "luafile $test_file" \
          -c 'if v:errmsg != "" | cquit 1 | endif' +qa
        ;;
      plain-buffer-lua)
        nvim --headless -i NONE /etc/hosts \
          -c "luafile $test_file" \
          -c 'if v:errmsg != "" | cquit 1 | endif' +qa
        ;;
      shell) bash "$test_file" ;;
    esac
  )
}

resource_sampler() {
  while :; do
    local sampled_at
    sampled_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    {
      printf '\n# %s\n' "$sampled_at"
      ps -eo pid=,ppid=,stat=,%cpu=,%mem=,rss=,vsz=,etime=,comm=,args= |
        awk 'BEGIN { print "pid\tppid\tstat\tcpu\tmem\trss_kib\tvsz_kib\tetime\tcommand\targs" }
          /[n]vim|[l]ua-language-server|[n]ode|[p]ython|[c]langd|[g]it|[j]j|[p]4d?/ {
            gsub(/^ +/, "")
            gsub(/ +/, "\t", $0)
            print
          }'
    } >>"$artifact_dir/resources.tsv"
    {
      printf '%s\t' "$sampled_at"
      awk '{ printf "%s\t%s\t%s\t%s\t%s\t", $1, $2, $3, $4, $5 }' /proc/loadavg
      awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { available = $2 }
        END { printf "%d\t%d", total, available }
      ' /proc/meminfo
      printf '\t%s\t%s\n' \
        "$(du -sk "$XDG_DATA_HOME" 2>/dev/null | awk '{ print $1 }')" \
        "$(find /proc -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | wc -l)"
    } >>"$artifact_dir/system-resources.tsv"
    sleep "$resource_sample_seconds"
  done
}

assert_resource_sampler() {
  if [[ -n $sampler_pid ]] && kill -0 "$sampler_pid" 2>/dev/null; then
    return
  fi

  local sampler_rc=1
  if [[ -n $sampler_pid ]]; then
    wait "$sampler_pid" || sampler_rc=$?
  fi
  sampler_pid=
  printf 'error: resource sampler stopped unexpectedly (status %d)\n' "$sampler_rc" >&2
  return 1
}

contains_unexpected_error() {
  local log_file
  for log_file in "$@"; do
    if [[ -s $log_file ]] && grep -qEi "$unexpected_error_pattern" "$log_file"; then
      return 0
    fi
  done
  return 1
}

stop_p4_server() {
  if [[ -z $p4d_pid ]] || ! kill -0 "$p4d_pid" 2>/dev/null; then
    p4d_pid=
    return
  fi

  kill "$p4d_pid" 2>/dev/null
  for _ in $(seq 1 100); do
    if ! kill -0 "$p4d_pid" 2>/dev/null; then
      p4d_pid=
      return
    fi
    sleep 0.02
  done

  kill -KILL "$p4d_pid" 2>/dev/null
  p4d_pid=
}

collect_artifacts() {
  local status=$1
  local elapsed
  elapsed=$(($(date +%s) - suite_started))
  if [[ -f $artifact_dir/system-resources.tsv ]]; then
    resource_samples=$(
      awk 'END { print (NR > 0 ? NR - 1 : 0) }' "$artifact_dir/system-resources.tsv"
    )
  fi

  if [[ -n $p4d_log && -f $p4d_log ]]; then
    cp -p -- "$p4d_log" "$artifact_dir/p4d.log" 2>/dev/null || true
  fi
  if [[ -d $XDG_STATE_HOME/nvim ]]; then
    rsync -a "$XDG_STATE_HOME/nvim/" "$artifact_dir/nvim-state/" 2>/dev/null || true
  fi
  find "$XDG_CACHE_HOME" "$XDG_DATA_HOME" -type f \
    \( -name '*.log' -o -name 'log' \) -print0 2>/dev/null |
    while IFS= read -r -d '' log_file; do
      relative=${log_file#"$HOME"/}
      destination="$artifact_dir/nvim-state/$relative"
      mkdir -p -- "$(dirname -- "$destination")"
      cp -p -- "$log_file" "$destination" 2>/dev/null || true
    done

  {
    find "$artifact_dir/logs" "$artifact_dir/errors" -type f -print0 2>/dev/null
    find "$artifact_dir/nvim-state" -type f \
      \( -name '*.log' -o -name 'log' \) -print0 2>/dev/null
  } |
    xargs -0 -r grep -nEi "$unexpected_error_pattern" 2>/dev/null \
      >"$artifact_dir/error-scan.log" || true

  {
    printf 'status=%s\n' "$status"
    printf 'short=%s\n' "$short_mode"
    printf 'soak_seconds=%s\n' "$soak_seconds"
    printf 'concurrency=%s\n' "$concurrency"
    printf 'elapsed_seconds=%s\n' "$elapsed"
    printf 'startup_attempts=%s\n' "$startup_attempts"
    printf 'startup_failures=%s\n' "$startup_failures"
    printf 'workload_attempts=%s\n' "$workload_attempts"
    printf 'workload_failures=%s\n' "$workload_failures"
    printf 'completed_batches=%s\n' "$completed_batches"
    printf 'completed_workload_cycles=%s\n' "$((completed_batches / 7))"
    printf 'soak_elapsed_seconds=%s\n' "$soak_elapsed"
    printf 'resource_samples=%s\n' "$resource_samples"
    printf 'timeout_failures=%s\n' "$timeout_failures"
    printf 'setup_timeout_seconds=%s\n' "$setup_timeout_seconds"
    printf 'startup_timeout_seconds=%s\n' "$startup_timeout_seconds"
    printf 'workload_timeout_seconds=%s\n' "$workload_timeout_seconds"
    printf 'finished_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$artifact_dir/summary.env"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  stop_active_phases
  if [[ -n $sampler_pid ]]; then
    kill "$sampler_pid" 2>/dev/null
    wait "$sampler_pid" 2>/dev/null
  fi
  stop_p4_server
  collect_artifacts "$status"
  rm -rf -- "$runtime_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

timeout_selftest_exit_seven() {
  printf 'ordinary bounded output\n'
  return 7
}

timeout_selftest_stubborn_tree() {
  local pid_file=$1
  local child_pid
  trap '' TERM
  sleep 30 &
  child_pid=$!
  printf '%s\n' "$child_pid" >"$pid_file"
  wait "$child_pid"
}

run_timeout_selftest() {
  local bounded_pid=0
  local child_pid
  local expired_budget
  local original_deadline=$bounded_deadline
  local ordinary_log="$artifact_dir/logs/timeout-selftest-ordinary.log"
  local status=0
  local stubborn_log="$artifact_dir/logs/timeout-selftest-stubborn.log"
  local stubborn_pid_file="$artifact_dir/timeout-selftest-child.pid"

  start_bounded bounded_pid 5 "timeout self-test ordinary exit" timeout_selftest_exit_seven \
    >"$ordinary_log" 2>&1
  if wait_bounded "$bounded_pid" "timeout self-test ordinary exit" >>"$ordinary_log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if ((status != 7)) || ! grep -Fq 'ordinary bounded output' "$ordinary_log"; then
    printf 'error: bounded execution did not preserve an ordinary status/output\n' >&2
    return 1
  fi

  bounded_pid=0
  start_bounded bounded_pid 1 "timeout self-test stubborn tree" \
    timeout_selftest_stubborn_tree "$stubborn_pid_file" >"$stubborn_log" 2>&1
  if wait_bounded "$bounded_pid" "timeout self-test stubborn tree" >>"$stubborn_log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if ((status != 124 && status != 137)); then
    printf 'error: stubborn bounded tree returned %d instead of a timeout status\n' \
      "$status" >&2
    return 1
  fi
  if [[ ! -s $stubborn_pid_file ]]; then
    printf 'error: stubborn bounded tree did not record its child\n' >&2
    return 1
  fi
  child_pid=$(<"$stubborn_pid_file")
  if [[ $child_pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$child_pid" 2>/dev/null; then
    printf 'error: bounded execution left child process %s alive\n' "$child_pid" >&2
    return 1
  fi

  bounded_deadline=$(($(monotonic_seconds) - 1))
  expired_budget=$(phase_budget 10)
  bounded_deadline=$original_deadline
  if ((expired_budget != 0)); then
    printf 'error: an expired hard deadline still returned a %s-second budget\n' \
      "$expired_budget" >&2
    return 1
  fi

  printf 'Debian harness timeout self-test passed\n'
}

if ((timeout_selftest)); then
  run_timeout_selftest
  exit 0
fi

locale_charmap=$(locale charmap)
if [[ $locale_charmap != UTF-8 ]]; then
  printf 'error: expected a UTF-8 locale, got %s\n' "$locale_charmap" >&2
  exit 1
fi

{
  printf 'started_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'repo_root=%s\n' "$repo_root"
  printf 'home=%s\n' "$HOME"
  printf 'xdg_config_home=%s\n' "$XDG_CONFIG_HOME"
  printf 'xdg_data_home=%s\n' "$XDG_DATA_HOME"
  printf 'xdg_state_home=%s\n' "$XDG_STATE_HOME"
  printf 'xdg_cache_home=%s\n' "$XDG_CACHE_HOME"
  printf 'short=%s\n' "$short_mode"
  printf 'soak_seconds=%s\n' "$soak_seconds"
  printf 'concurrency=%s\n' "$concurrency"
  printf 'setup_timeout_seconds=%s\n' "$setup_timeout_seconds"
  printf 'startup_timeout_seconds=%s\n' "$startup_timeout_seconds"
  printf 'workload_timeout_seconds=%s\n' "$workload_timeout_seconds"
  printf 'timeout_kill_after_seconds=%s\n' "$timeout_kill_after_seconds"
  printf 'repo_commit=%s\n' "${SOURCE_COMMIT:-unknown}"
  printf 'container_image_id=%s\n' "${SOURCE_IMAGE_ID:-unknown}"
  printf 'lang=%s\n' "${LANG:-}"
  printf 'lc_all=%s\n' "${LC_ALL:-}"
  printf 'locale_charmap=%s\n' "$locale_charmap"
  printf 'nvim_version='
  nvim --version | sed -n '1p'
  printf 'git_version='
  git --version
  printf 'stow_version='
  stow --version | sed -n '1p'
  printf 'rust_analyzer_version='
  rust-analyzer --version
  printf 'kernel='
  uname -a
  if [[ -r /etc/os-release ]]; then
    sed 's/^/os_release_/' /etc/os-release
  fi
} >"$artifact_dir/environment.env"

printf 'sampled_at_utc\tload_1m\tload_5m\tload_15m\trunnable\tlast_pid\tmem_total_kib\tmem_available_kib\txdg_data_kib\tprocess_count\n' \
  >"$artifact_dir/system-resources.tsv"
resource_sampler &
sampler_pid=$!

home_snapshot_before=$(find "$HOME" -mindepth 1 -printf '%P\t%y\t%l\n' | sort)
run_logged stow-dry-run run_apply "$repo_root" --no
home_snapshot_after=$(find "$HOME" -mindepth 1 -printf '%P\t%y\t%l\n' | sort)
if [[ $home_snapshot_before != "$home_snapshot_after" ]]; then
  {
    printf '%s\n' '--- before'
    printf '%s\n' "$home_snapshot_before"
    printf '%s\n' '--- after'
    printf '%s\n' "$home_snapshot_after"
  } >"$artifact_dir/errors/stow-dry-run-home-snapshot.log"
  printf 'error: stow dry-run changed the isolated HOME\n' >&2
  exit 1
fi

run_logged stow-fresh run_apply "$repo_root"
expected_init="$repo_root/common/.config/nvim/init.lua"
actual_init=$(readlink -f -- "$XDG_CONFIG_HOME/nvim/init.lua")
if [[ $actual_init != "$expected_init" ]]; then
  printf 'error: stowed init.lua resolves to %s, expected %s\n' "$actual_init" "$expected_init" >&2
  exit 1
fi
run_logged stow-restow run_apply "$repo_root" --restow

adopt_repo="$runtime_root/adopt-repo"
adopt_home="$runtime_root/adopt-home"
mkdir -p -- "$adopt_repo" "$adopt_home/.config/nvim"
rsync -a --exclude='.git/' --exclude='.artifacts/' --exclude='tests/nvim-debian/artifacts/' \
  -- "$repo_root/" "$adopt_repo/"
printf '%s\n' 'unmanaged adoption sentinel' >"$adopt_home/.config/nvim/init.lua"
source_hash_before=$(sha256sum "$adopt_repo/common/.config/nvim/init.lua")
target_hash_before=$(sha256sum "$adopt_home/.config/nvim/init.lua")
HOME="$adopt_home" run_logged stow-adopt-preview run_apply "$adopt_repo" --no --adopt
source_hash_after=$(sha256sum "$adopt_repo/common/.config/nvim/init.lua")
target_hash_after=$(sha256sum "$adopt_home/.config/nvim/init.lua")
if [[ $source_hash_before != "$source_hash_after" || $target_hash_before != "$target_hash_after" ]]; then
  printf 'error: dry-run adoption changed its source or target\n' >&2
  exit 1
fi

runtime_config_home="$runtime_root/runtime-config"
mkdir -p -- "$runtime_config_home/nvim" "$runtime_config_home/jj"
rsync -aL -- "$XDG_CONFIG_HOME/nvim/" "$runtime_config_home/nvim/"
rsync -aL -- "$XDG_CONFIG_HOME/jj/" "$runtime_config_home/jj/"
export XDG_CONFIG_HOME="$runtime_config_home"
printf 'runtime_xdg_config_home=%s\n' "$XDG_CONFIG_HOME" >>"$artifact_dir/environment.env"

lock_file="$XDG_CONFIG_HOME/nvim/lazy-lock.json"
expected_lock_file="$repo_root/common/.config/nvim/lazy-lock.json"
lazy_config_file="$XDG_CONFIG_HOME/nvim/lua/config/lazy.lua"
if ! grep -Fq 'enabled = true, -- check' "$lazy_config_file"; then
  printf 'error: could not disable lazy.nvim update checks in the runtime config\n' >&2
  exit 1
fi
sed -i 's/enabled = true, -- check/enabled = false, -- check/' "$lazy_config_file"

# The production config keeps language tools and parsers up to date in the
# background. The soak tests their configuration, but suppresses those
# unrelated network installs so every headless process exits cleanly.
cat >"$XDG_CONFIG_HOME/nvim/lua/plugins/zz-debian-harness.lua" <<'EOF'
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      for _, server in pairs(opts.servers or {}) do
        if type(server) == "table" then
          server.mason = false
        end
      end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
EOF

lock_hash_before=$(sha256sum "$lock_file")
source_lock_hash_before=$(sha256sum "$expected_lock_file")
cp -p -- "$expected_lock_file" "$artifact_dir/expected-lazy-lock.json"

lazy_dir="$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
lazy_commit=$(jq -r '."lazy.nvim".commit' "$expected_lock_file")
run_logged lazy-bootstrap \
  git clone --filter=blob:none https://github.com/folke/lazy.nvim.git "$lazy_dir"
run_logged lazy-bootstrap-checkout \
  git -C "$lazy_dir" checkout --detach "$lazy_commit"

# Seed LazyVim before parsing its imports. Otherwise the first missing-plugin
# round sees only the root spec and rewrites the runtime lockfile before the
# rest of the locked plugin graph is discoverable.
lazyvim_dir="$XDG_DATA_HOME/nvim/lazy/LazyVim"
lazyvim_commit=$(jq -r '."LazyVim".commit' "$expected_lock_file")
run_logged lazyvim-bootstrap \
  git clone --filter=blob:none https://github.com/LazyVim/LazyVim.git "$lazyvim_dir"
run_logged lazyvim-bootstrap-checkout \
  git -C "$lazyvim_dir" checkout --detach "$lazyvim_commit"

# Normal startup now sees the complete locked graph and lets lazy.nvim perform
# its synchronous missing-plugin install with the same path users exercise.
run_logged lazy-install nvim --headless -i NONE +qa
bootstrap_lock_hash=$(sha256sum "$lock_file")
if [[ $lock_hash_before != "$bootstrap_lock_hash" ]]; then
  cp -p -- "$lock_file" "$artifact_dir/bootstrap-lazy-lock.json"
  diff -u "$artifact_dir/expected-lazy-lock.json" "$artifact_dir/bootstrap-lazy-lock.json" \
    >"$artifact_dir/lazy-bootstrap-lock-drift.diff" || true
  printf 'error: initial plugin installation changed the runtime copy of lazy-lock.json\n' >&2
  exit 1
fi
run_logged lazy-restore \
  nvim --headless -i NONE '+Lazy! restore' +qa
lock_hash_after=$(sha256sum "$lock_file")
source_lock_hash_after=$(sha256sum "$expected_lock_file")
cp -p -- "$lock_file" "$artifact_dir/actual-lazy-lock.json"
if [[ $source_lock_hash_before != "$source_lock_hash_after" ]]; then
  printf 'error: plugin installation changed the repository lazy-lock.json\n' >&2
  exit 1
fi
if [[ $lock_hash_before != "$lock_hash_after" ]]; then
  diff -u "$artifact_dir/expected-lazy-lock.json" "$artifact_dir/actual-lazy-lock.json" \
    >"$artifact_dir/lazy-lock-drift.diff" || true
  printf 'error: Lazy restore changed the runtime copy of lazy-lock.json\n' >&2
  exit 1
fi

lock_failures=0
while IFS= read -r plugin_dir; do
  plugin_name=${plugin_dir##*/}
  expected_commit=$(jq -r --arg name "$plugin_name" '.[$name].commit // empty' "$expected_lock_file")
  if [[ -z $expected_commit ]]; then
    printf 'unlocked plugin directory: %s\n' "$plugin_name" | tee -a "$artifact_dir/errors/lazy-lock.log"
    lock_failures=$((lock_failures + 1))
    continue
  fi
  if [[ ! -d $plugin_dir/.git ]]; then
    printf 'installed plugin is not a Git checkout: %s (%s)\n' \
      "$plugin_name" "$plugin_dir" | tee -a "$artifact_dir/errors/lazy-lock.log"
    lock_failures=$((lock_failures + 1))
    continue
  fi
  actual_commit=$(git -C "$plugin_dir" rev-parse HEAD)
  if [[ $actual_commit != "$expected_commit" ]]; then
    printf 'locked plugin mismatch: %s expected %s got %s\n' \
      "$plugin_name" "$expected_commit" "$actual_commit" | tee -a "$artifact_dir/errors/lazy-lock.log"
    lock_failures=$((lock_failures + 1))
  fi
done < <(find "$XDG_DATA_HOME/nvim/lazy" -mindepth 1 -maxdepth 1 -type d -print | sort)
if ((lock_failures != 0)); then
  printf 'error: plugin installation did not match lazy-lock.json exactly\n' >&2
  exit 1
fi

run_logged headless-startup nvim --headless -i NONE +qa
run_logged plugin-smoke \
  nvim --headless -i NONE "+luafile $repo_root/tests/nvim-debian/smoke.lua" +qa
run_logged checkhealth \
  nvim --headless -i NONE '+checkhealth' "+silent write! $artifact_dir/health.txt" +qa

repo_test_count=0
while IFS= read -r -d '' test_file; do
  test_name=${test_file#"$repo_root/tests/"}
  test_log_name=${test_name//\//-}
  test_log_name=${test_log_name//[^[:alnum:]._-]/_}
  case $test_file in
    */nvim_p4_diffview_spec.lua | */nvim_p4_spec.lua)
      if [[ -r $repo_root/tests/nvim_p4_spec.sh ]]; then
        continue
      fi
      run_logged "repo-test-$test_log_name" run_repo_test lua "$test_file"
      ;;
    */nvim_plugin_spec.lua)
      run_logged "repo-test-$test_log_name" run_repo_test full-lua "$test_file"
      ;;
    */nvim_plain_buffer_spec.lua)
      run_logged "repo-test-$test_log_name" run_repo_test plain-buffer-lua "$test_file"
      ;;
    *.lua)
      run_logged "repo-test-$test_log_name" run_repo_test lua "$test_file"
      ;;
    *.sh)
      run_logged "repo-test-$test_log_name" run_repo_test shell "$test_file"
      ;;
  esac
  repo_test_count=$((repo_test_count + 1))
done < <(
  find "$repo_root/tests" \
    -path "$repo_root/tests/nvim-debian" -prune -o \
    -type f \( -name 'nvim*_spec.lua' -o -name 'nvim*_spec.sh' \) -print0 |
    sort -z
)
if ((repo_test_count == 0)); then
  printf 'error: no Neovim repository tests were discovered\n' >&2
  exit 1
fi
printf 'Discovered and passed %d repository Neovim tests.\n' "$repo_test_count"

workload_root="$runtime_root/workloads"
git_root="$workload_root/git repo ü [*] #%"
jj_root="$workload_root/jj repo ü [*] #%"
p4_server_root="$workload_root/p4-server"
p4d_log="$workload_root/p4d.log"
p4_root="$workload_root/p4 workspace ü"
diff_root="$workload_root/external diff ü [*] #%"
proxy_bin="$workload_root/proxy-bin"
git_file="$git_root/current file ü [*] #%.txt"
jj_file="$jj_root/current file ü [*] #%.txt"
p4_file="$p4_root/src one/current file ü [*] #%.txt"
p4_file_spec=${p4_file//%/%25}
p4_file_spec=${p4_file_spec//@/%40}
p4_file_spec=${p4_file_spec//#/%23}
p4_file_spec=${p4_file_spec//\*/%2A}
diff_left="$diff_root/left file ü [*] #%.txt"
diff_right="$diff_root/right file ü [*] #%.txt"
diff_left_dir="$diff_root/left dir ü [*] #%"
diff_right_dir="$diff_root/right dir ü [*] #%"
diff_output_dir="$diff_root/output dir ü [*] #%"
merge_output="$diff_root/merge output ü [*] #%.txt"
merge_base="$diff_root/merge base ü [*] #%.txt"
merge_left="$diff_root/merge left ü [*] #%.txt"
merge_right="$diff_root/merge right ü [*] #%.txt"
real_nvim=$(command -v nvim)
export \
  artifact_dir \
  diff_left \
  diff_left_dir \
  diff_output_dir \
  diff_right \
  diff_right_dir \
  git_file \
  git_root \
  jj_file \
  jj_root \
  merge_base \
  merge_left \
  merge_output \
  merge_right \
  p4_file \
  p4_file_spec \
  p4_root \
  p4_server_root \
  proxy_bin \
  real_nvim \
  repo_root
export P4USER=nvim-soak
export P4CLIENT=nvim-soak-client

start_p4_server() {
  local bounded_pid=0
  local launch_status=0
  local pid_file="$workload_root/p4d.pid"
  local pid_file_deadline
  local port
  local ready=0

  port=$(
    python3 -c \
      'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
  )
  export P4PORT="127.0.0.1:$port"
  rm -f -- "$pid_file"
  start_bounded bounded_pid "$setup_timeout_seconds" "persistent p4d launch" \
    p4d -q --daemonsafe \
    --pid-file="$pid_file" \
    -r "$p4_server_root" \
    -J off \
    -L "$p4d_log" \
    -p "$P4PORT"
  if wait_bounded "$bounded_pid" "persistent p4d launch"; then
    launch_status=0
  else
    launch_status=$?
  fi
  if ((launch_status != 0)); then
    return "$launch_status"
  fi

  # --daemonsafe can return just before its pidfile becomes visible. Wait for
  # the durable handoff instead of racing a direct shell redirection read.
  pid_file_deadline=$(($(monotonic_seconds) + 10))
  while [[ ! -s $pid_file ]]; do
    if (($(monotonic_seconds) >= pid_file_deadline)); then
      printf 'error: persistent p4d did not create its pidfile: %s\n' "$pid_file" >&2
      return 1
    fi
    sleep 0.02
  done
  if ! IFS= read -r p4d_pid <"$pid_file" || [[ ! $p4d_pid =~ ^[1-9][0-9]*$ ]]; then
    printf 'error: persistent p4d wrote an invalid pidfile: %s\n' "$pid_file" >&2
    p4d_pid=
    return 1
  fi

  for _ in $(seq 1 100); do
    if timeout --signal=TERM --kill-after=1s 2s p4 info >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.02
  done
  if ((ready == 0)); then
    printf 'error: persistent p4d did not become ready at %s\n' "$P4PORT" >&2
    return 1
  fi
}

setup_workload_fixtures() {
  mkdir -p -- "$git_root" "$jj_root" "$p4_server_root" "$p4_root/src one" \
    "$diff_left_dir" "$diff_right_dir" "$diff_output_dir" "$proxy_bin"

  git -C "$git_root" init --initial-branch=main
  git -C "$git_root" config user.name "Neovim Debian Soak"
  git -C "$git_root" config user.email "nvim-soak@example.invalid"
  printf 'base\n' >"$git_file"
  git -C "$git_root" add -- "$git_file"
  git -C "$git_root" commit -m base

  jj git init "$jj_root"
  jj config set --repo -R "$jj_root" user.name "Neovim Debian Soak"
  jj config set --repo -R "$jj_root" user.email "nvim-soak@example.invalid"
  printf 'base\n' >"$jj_file"
  jj -R "$jj_root" describe -m base
  jj -R "$jj_root" new

  p4 client -i <<EOF
Client: $P4CLIENT
Owner: $P4USER
Root: $p4_root
Options: noallwrite noclobber nocompress unlocked nomodtime rmdir
SubmitOptions: submitunchanged
LineEnd: local
View:
	//depot/... //$P4CLIENT/...
EOF
  printf 'base\n' >"$p4_file"
  p4 add -f "$p4_file"
  p4 submit -d "soak base"
  p4 edit "$p4_file_spec"

  printf 'left\n' >"$diff_left"
  printf 'right\n' >"$diff_right"
  printf 'left\n' >"$diff_left_dir/nested ü.txt"
  printf 'right\n' >"$diff_right_dir/nested ü.txt"
  printf 'output\n' >"$diff_output_dir/nested ü.txt"
  printf 'output\n' >"$merge_output"
  printf 'base\n' >"$merge_base"
  printf 'left\n' >"$merge_left"
  printf 'right\n' >"$merge_right"

  cat >"$proxy_bin/nvim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export NVIM_DEBIAN_SMOKE_MODE=assert-view
exec "$NVIM_DEBIAN_REAL_NVIM" --headless -i NONE "$@" \
  -c "luafile $NVIM_DEBIAN_SMOKE_LUA" -c 'qa!'
EOF
  chmod +x "$proxy_bin/nvim"
}

run_vcs_smoke() {
  local kind=$1
  local target=$2
  NVIM_VCS="$kind" \
    NVIM_DEBIAN_SMOKE_MODE=vcs \
    NVIM_DEBIAN_TARGET="$target" \
    NVIM_P4_TIMEOUT_SECONDS=10 \
    nvim --headless -i NONE "$target" \
      "+luafile $repo_root/tests/nvim-debian/smoke.lua" +qa
}

run_external_tool() {
  PATH="$proxy_bin:$HOME/.local/bin:$PATH" \
    NVIM_DEBIAN_REAL_NVIM="$real_nvim" \
    NVIM_DEBIAN_SMOKE_LUA="$repo_root/tests/nvim-debian/smoke.lua" \
    "$@"
}

workload_full() {
  NVIM_DEBIAN_SMOKE_MODE=full \
    nvim --headless -i NONE "+luafile $repo_root/tests/nvim-debian/smoke.lua" +qa
}

workload_git() {
  local batch=$1
  printf 'base\ngit batch %s\n' "$batch" >"$git_file"
  git -C "$git_root" diff --check
  run_vcs_smoke git "$git_file"
  run_external_tool git -C "$git_root" difftool --no-prompt \
    --extcmd="$HOME/.local/bin/nvim-diff" -- "$git_file"
}

workload_jj() {
  local batch=$1
  printf 'base\njj batch %s\n' "$batch" >"$jj_file"
  jj -R "$jj_root" diff --summary
  run_vcs_smoke jj "$jj_file"
  run_external_tool jj -R "$jj_root" diff --tool diffview
}

workload_p4() {
  local batch=$1
  printf 'base\np4 batch %s\n' "$batch" >"$p4_file"
  p4 diff -sa "$p4_file_spec"
  run_vcs_smoke p4 "$p4_file"
  P4DIFF=nvim-diff run_external_tool p4 diff "$p4_file_spec"
}

workload_diff_files() {
  local batch=$1
  printf 'left %s\n' "$batch" >"$diff_left"
  printf 'right %s\n' "$batch" >"$diff_right"
  run_external_tool "$HOME/.local/bin/nvim-diff" "$diff_left" "$diff_right"
}

workload_diff_dirs() {
  local batch=$1
  printf 'left %s\n' "$batch" >"$diff_left_dir/nested ü.txt"
  printf 'right %s\n' "$batch" >"$diff_right_dir/nested ü.txt"
  run_external_tool "$HOME/.local/bin/nvim-diff" \
    "$diff_left_dir" "$diff_right_dir" "$diff_output_dir"
}

workload_merge() {
  local batch=$1
  printf 'output %s\n' "$batch" >"$merge_output"
  run_external_tool "$HOME/.local/bin/nvim-merge" \
    "$merge_output" "$merge_base" "$merge_left" "$merge_right"
}

export -f \
  run_external_tool \
  run_vcs_smoke \
  workload_diff_dirs \
  workload_diff_files \
  workload_full \
  workload_git \
  workload_jj \
  workload_merge \
  workload_p4

workload_names=(full git jj p4 diff-files diff-dirs merge)
workload_functions=(
  workload_full
  workload_git
  workload_jj
  workload_p4
  workload_diff_files
  workload_diff_dirs
  workload_merge
)
workload_count=${#workload_names[@]}

run_workload() {
  local batch=$1
  local timeout_seconds=$2
  local bounded_pid=0
  local index=$(((batch - 1) % workload_count))
  local name=${workload_names[$index]}
  local function_name=${workload_functions[$index]}
  local log_file="$artifact_dir/logs/workload-$name.log"
  local started
  local status
  started=$(monotonic_seconds)
  workload_attempts=$((workload_attempts + 1))

  printf '\n[%s] batch=%d workload=%s timeout=%ss\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$batch" "$name" "$timeout_seconds" \
    >>"$log_file"
  if start_bounded bounded_pid "$timeout_seconds" "workload '$name' batch $batch" \
    "$function_name" "$batch" >>"$log_file" 2>&1
  then
    if wait_bounded "$bounded_pid" "workload '$name' batch $batch" >>"$log_file" 2>&1; then
      status=0
    else
      status=$?
    fi
  else
    status=$?
  fi

  printf '%s\t%d\t%s\t%d\t%d\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$batch" "$name" "$status" \
    "$(($(monotonic_seconds) - started))" >>"$artifact_dir/workload-progress.tsv"

  if ((status != 0)); then
    workload_failures=$((workload_failures + 1))
    cp -p -- "$log_file" "$artifact_dir/errors/workload-$batch-$name.log"
    printf 'error: workload %s failed in batch %d (status %d)\n' \
      "$name" "$batch" "$status" >&2
    return "$status"
  fi
}

mkdir -p -- "$p4_server_root"
start_p4_server
run_logged workload-fixtures setup_workload_fixtures
{
  printf 'sampled_at_utc\tbatch\tworkload\tstatus\tduration_seconds\n'
} >"$artifact_dir/workload-progress.tsv"

run_startup_batch() {
  local batch=$1
  local timeout_seconds=$2
  local bounded_pid
  local slot
  local startup_status
  local startup_id
  local output_file
  local nvim_log_file
  local startup_failed
  local -a pids=()
  local -a outputs=()

  for ((slot = 1; slot <= concurrency; slot++)); do
    startup_id=$(printf '%07d-%02d' "$batch" "$slot")
    output_file="$artifact_dir/logs/startup-$startup_id.log"
    nvim_log_file="$artifact_dir/logs/nvim-startup-$startup_id.log"
    bounded_pid=0
    if start_bounded bounded_pid "$timeout_seconds" \
      "startup $batch/$slot" \
      env "NVIM_LOG_FILE=$nvim_log_file" \
      nvim --headless -i NONE "+luafile $repo_root/tests/nvim-debian/smoke.lua" +qa \
      >"$output_file" 2>&1
    then
      :
    else
      bounded_pid=0
    fi
    pids+=("$bounded_pid")
    outputs+=("$output_file")
  done

  for ((slot = 0; slot < concurrency; slot++)); do
    startup_attempts=$((startup_attempts + 1))
    startup_failed=0
    startup_id=$(printf '%07d-%02d' "$batch" "$((slot + 1))")
    nvim_log_file="$artifact_dir/logs/nvim-startup-$startup_id.log"
    if wait_bounded "${pids[$slot]}" "startup $batch/$((slot + 1))" \
      >>"${outputs[$slot]}" 2>&1
    then
      startup_status=0
    else
      startup_status=$?
    fi
    if ((startup_status != 0)); then
      startup_failed=1
    elif contains_unexpected_error "${outputs[$slot]}" "$nvim_log_file"; then
      startup_failed=1
      printf 'error: startup %d/%d exited zero but logged an error\n' \
        "$batch" "$((slot + 1))" >&2
    fi
    if ((startup_failed)); then
      startup_failures=$((startup_failures + 1))
      cp -p -- "${outputs[$slot]}" \
        "$artifact_dir/errors/startup-$(printf '%07d-%02d' "$batch" "$((slot + 1))").log"
      if [[ -s $nvim_log_file ]]; then
        cp -p -- "$nvim_log_file" \
          "$artifact_dir/errors/nvim-$(printf '%07d-%02d' "$batch" "$((slot + 1))").log"
      fi
    fi
    rm -f -- "${outputs[$slot]}" "$nvim_log_file"
  done
}

stress_started=$(monotonic_seconds)
stress_started_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
deadline=$((stress_started + soak_seconds))
if [[ $short_mode == 0 ]]; then
  # A batch that starts just before the requested duration may finish, but its
  # startup plus workload can overrun only by these explicit phase caps.
  bounded_deadline=$((
    deadline
    + startup_timeout_seconds
    + workload_timeout_seconds
    + (2 * timeout_kill_after_seconds)
  ))
fi
batch=0
while :; do
  if [[ $short_mode == 1 ]]; then
    ((batch < short_batches)) || break
  else
    (($(monotonic_seconds) < deadline)) || break
  fi

  batch=$((batch + 1))
  assert_resource_sampler
  startup_budget=$(phase_budget "$startup_timeout_seconds")
  run_startup_batch "$batch" "$startup_budget"
  if ((startup_failures != 0)); then
    printf 'error: concurrent Neovim startup failed in batch %d\n' "$batch" >&2
    exit 1
  fi
  workload_budget=$(phase_budget "$workload_timeout_seconds")
  run_workload "$batch" "$workload_budget"
  assert_resource_sampler
  completed_batches=$batch
  soak_elapsed=$(($(monotonic_seconds) - stress_started))
  if ((batch == 1 || batch % 25 == 0)); then
    printf 'Mixed soak: batch=%d startups=%d workload_runs=%d failures=%d elapsed=%ds\n' \
      "$batch" "$startup_attempts" "$workload_attempts" \
      "$((startup_failures + workload_failures))" "$soak_elapsed"
    printf '%s\t%d\t%d\t%d\t%d\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$batch" "$startup_attempts" \
      "$startup_failures" "$soak_elapsed" \
      >>"$artifact_dir/startup-progress.tsv"
  fi
done

soak_elapsed=$(($(monotonic_seconds) - stress_started))
{
  printf 'started_utc=%s\n' "$stress_started_utc"
  printf 'finished_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'requested_seconds=%s\n' "$soak_seconds"
  printf 'elapsed_monotonic_seconds=%s\n' "$soak_elapsed"
} >"$artifact_dir/soak-duration.env"

if [[ $short_mode == 0 && $soak_elapsed -lt $soak_seconds ]]; then
  printf 'error: timed soak ended after %d seconds, before its %d-second target\n' \
    "$soak_elapsed" "$soak_seconds" >&2
  exit 1
fi
if ((startup_failures != 0)); then
  printf 'error: %d of %d concurrent Neovim startups failed\n' \
    "$startup_failures" "$startup_attempts" >&2
  exit 1
fi
assert_resource_sampler
resource_samples=$(awk 'END { print (NR > 0 ? NR - 1 : 0) }' "$artifact_dir/system-resources.tsv")
if ((resource_samples == 0)); then
  printf 'error: resource sampler produced no samples\n' >&2
  exit 1
fi

# Copy and inspect the final logs before reporting success. cleanup() collects
# them again with the true exit status.
collect_artifacts 0
if [[ -s $artifact_dir/error-scan.log ]]; then
  printf 'error: unexpected error-level output was recorded; see %s\n' \
    "$artifact_dir/error-scan.log" >&2
  exit 1
fi

printf 'Concurrent startup validation passed: %d startups in %d batches.\n' \
  "$startup_attempts" "$completed_batches"
printf 'Mixed workload validation passed: %d workloads, %d complete rotations, %ds elapsed.\n' \
  "$workload_attempts" "$((completed_batches / workload_count))" "$soak_elapsed"
