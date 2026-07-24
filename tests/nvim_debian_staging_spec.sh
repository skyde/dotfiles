#!/usr/bin/env bash
# shellcheck disable=SC2016 # These assertions intentionally match literal shell source.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd -P)
suite="$repo_root/tests/nvim-debian/suite.sh"
runner="$repo_root/tests/nvim-debian/run.sh"

require_line() {
  local file=$1
  local line=$2
  if ! grep -Fq -- "$line" "$file"; then
    printf 'missing Debian staging invariant in %s: %s\n' "$file" "$line" >&2
    exit 1
  fi
}

reject_line() {
  local file=$1
  local line=$2
  if grep -Fq -- "$line" "$file"; then
    printf 'unsafe Debian staging path returned in %s: %s\n' "$file" "$line" >&2
    exit 1
  fi
}

bash -n "$suite" "$runner"

require_line "$suite" 'artifact_dir="$runtime_root/artifacts"'
require_line "$suite" 'repo_root="$runtime_root/repo"'
require_line "$suite" 'rsync -a -- "$source_repo_root/" "$repo_root/"'
require_line "$suite" 'output_file="$startup_log_root/startup-$startup_id.log"'
require_line "$suite" 'nvim_log_file="$startup_log_root/nvim-startup-$startup_id.log"'
require_line "$suite" 'exec rsync -a --inplace -- "$source_dir/" "$destination_dir/"'
require_line "$suite" 'for marker_name in "$@"; do'
require_line "$suite" 'sync_artifacts checkpoint-complete.env final-export-complete.env'
require_line "$runner" '--env "ARTIFACT_SYNC_SECONDS=$artifact_sync_seconds"'
require_line "$runner" '--env "ARTIFACT_SYNC_TIMEOUT_SECONDS=$artifact_sync_timeout_seconds"'
require_line "$runner" '--env "STAGING_ROOT=/var/tmp/nvim-debian-stage"'
require_line "$runner" '--name "$container_name"'
require_line "$runner" '--cidfile "$container_cidfile"'
require_line "$runner" '--label "$container_run_label_key=$container_run_label_value"'
require_line "$runner" 'minimum_finalize_grace=$((7 * (artifact_sync_timeout_seconds + timeout_kill_after_seconds) + 30))'
require_line "$runner" '/usr/bin/env --default-signal=INT,QUIT -- "$@" &'
require_line "$runner" 'terminate_container_engine_cli'
require_line "$runner" 'if [[ $podman_rootless == true && $podman_native_cli == true ]]; then'
require_line "$runner" 'container_user_mode=rootless-podman-docker-cli-handoff'
require_line "$suite" 'publish_final_export_marker "$status"'

reject_line "$suite" 'output_file="$artifact_dir/logs/startup-$startup_id.log"'
reject_line "$suite" 'nvim_log_file="$artifact_dir/logs/nvim-startup-$startup_id.log"'

printf 'nvim Debian local-staging invariants passed\n'
