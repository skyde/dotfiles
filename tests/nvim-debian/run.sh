#!/usr/bin/env bash
set -euo pipefail
umask 077

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd -P)
container_engine_kind=
podman_rootless=
podman_native_cli=
engine_security_options=
engine_server_metadata=
# shellcheck disable=SC1091 # Resolved relative to this script at runtime.
source "$script_dir/container-engine.sh"

container_engine=${CONTAINER_ENGINE:-docker}
image=${NVIM_DEBIAN_IMAGE:-dotfiles-nvim-debian:testing}
platform=${NVIM_DEBIAN_PLATFORM:-}
soak_seconds=${SOAK_SECONDS:-0}
if [[ ${SHORT+x} ]]; then
  short_mode=$SHORT
elif [[ $soak_seconds =~ ^[1-9][0-9]*$ ]]; then
  short_mode=0
else
  short_mode=1
fi
concurrency=${CONCURRENCY:-4}
artifact_sync_seconds=${ARTIFACT_SYNC_SECONDS:-600}
artifact_sync_timeout_seconds=${ARTIFACT_SYNC_TIMEOUT_SECONDS:-30}
artifact_finalize_grace_seconds=${ARTIFACT_FINALIZE_GRACE_SECONDS:-300}
timeout_kill_after_seconds=${TIMEOUT_KILL_AFTER_SECONDS:-5}
artifact_handoff_selftest=${NVIM_DEBIAN_ARTIFACT_HANDOFF_SELFTEST:-0}
build_image=1
artifact_parent=${ARTIFACT_DIR:-}

usage() {
  cat <<'EOF'
Usage: tests/nvim-debian/run.sh [options]

Build the Debian-testing image and run the isolated Neovim validation suite.

Options:
  --short                  Run the bounded smoke/stress suite (default).
  --soak SECONDS           Run concurrent startup checks for SECONDS.
  --10h                    Run the 10-hour soak (equivalent to --soak 36000).
  --concurrency COUNT      Concurrent Neovim startups per batch (default: 4).
  --artifact-dir PATH      Existing parent for a unique durable output directory.
  --image NAME             Container image name/tag.
  --no-build               Reuse an already-built image.
  -h, --help               Show this help.

Environment equivalents:
  CONTAINER_ENGINE, NVIM_DEBIAN_IMAGE, NVIM_DEBIAN_PLATFORM, SHORT,
  SOAK_SECONDS, CONCURRENCY, ARTIFACT_DIR, SHORT_BATCHES,
  RESOURCE_SAMPLE_SECONDS, SETUP_TIMEOUT_SECONDS, STARTUP_TIMEOUT_SECONDS,
  WORKLOAD_TIMEOUT_SECONDS, TIMEOUT_KILL_AFTER_SECONDS, ARTIFACT_SYNC_SECONDS,
  ARTIFACT_SYNC_TIMEOUT_SECONDS, ARTIFACT_FINALIZE_GRACE_SECONDS,
  NVIM_DEBIAN_ARTIFACT_HANDOFF_SELFTEST

NVIM_DEBIAN_PLATFORM defaults to the container engine's native architecture.
EOF
}

require_value() {
  local option=$1
  local value=${2:-}
  if [[ -z $value ]]; then
    printf 'error: %s requires a value\n' "$option" >&2
    usage >&2
    exit 2
  fi
}

while (($# > 0)); do
  case $1 in
    --short)
      short_mode=1
      soak_seconds=0
      shift
      ;;
    --soak)
      require_value "$1" "${2:-}"
      short_mode=0
      soak_seconds=$2
      shift 2
      ;;
    --10h)
      short_mode=0
      soak_seconds=36000
      shift
      ;;
    --concurrency)
      require_value "$1" "${2:-}"
      concurrency=$2
      shift 2
      ;;
    --artifact-dir)
      require_value "$1" "${2:-}"
      artifact_parent=$2
      shift 2
      ;;
    --image)
      require_value "$1" "${2:-}"
      image=$2
      shift 2
      ;;
    --no-build)
      build_image=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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
  printf 'error: a non-short run requires SOAK_SECONDS greater than zero\n' >&2
  exit 2
fi
if [[ ! $concurrency =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: CONCURRENCY must be a positive integer (got %s)\n' "$concurrency" >&2
  exit 2
fi
if [[ ! $artifact_sync_seconds =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: ARTIFACT_SYNC_SECONDS must be a positive integer (got %s)\n' \
    "$artifact_sync_seconds" >&2
  exit 2
fi
if ((artifact_sync_seconds < 300)); then
  printf 'error: ARTIFACT_SYNC_SECONDS must be at least 300 (got %s)\n' \
    "$artifact_sync_seconds" >&2
  exit 2
fi
if [[ ! $artifact_sync_timeout_seconds =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: ARTIFACT_SYNC_TIMEOUT_SECONDS must be a positive integer (got %s)\n' \
    "$artifact_sync_timeout_seconds" >&2
  exit 2
fi
if [[ ! $artifact_finalize_grace_seconds =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: ARTIFACT_FINALIZE_GRACE_SECONDS must be a positive integer (got %s)\n' \
    "$artifact_finalize_grace_seconds" >&2
  exit 2
fi
if [[ ! $timeout_kill_after_seconds =~ ^[1-9][0-9]*$ ]]; then
  printf 'error: TIMEOUT_KILL_AFTER_SECONDS must be a positive integer (got %s)\n' \
    "$timeout_kill_after_seconds" >&2
  exit 2
fi
case $artifact_handoff_selftest in
  0 | 1) ;;
  *)
    printf 'error: NVIM_DEBIAN_ARTIFACT_HANDOFF_SELFTEST must be 0 or 1 (got %s)\n' \
      "$artifact_handoff_selftest" >&2
    exit 2
    ;;
esac
minimum_finalize_grace=$((7 * (artifact_sync_timeout_seconds + timeout_kill_after_seconds) + 30))
if ((artifact_finalize_grace_seconds < minimum_finalize_grace)); then
  printf 'error: ARTIFACT_FINALIZE_GRACE_SECONDS must be at least %d for current timeouts (got %s)\n' \
    "$minimum_finalize_grace" "$artifact_finalize_grace_seconds" >&2
  exit 2
fi
if ! command -v "$container_engine" >/dev/null 2>&1; then
  printf 'error: container engine not found: %s\n' "$container_engine" >&2
  exit 127
fi
if [[ -z $platform ]]; then
  engine_architecture=$(
    "$container_engine" info --format '{{.Architecture}}' 2>/dev/null || true
  )
  if [[ -z $engine_architecture ]]; then
    engine_architecture=$(
      "$container_engine" info --format '{{.Host.Arch}}' 2>/dev/null || true
    )
  fi
  case $engine_architecture in
    amd64 | x86_64) platform=linux/amd64 ;;
    arm64 | aarch64) platform=linux/arm64 ;;
    *)
      printf 'error: unsupported container engine architecture: %s\n' \
        "$engine_architecture" >&2
      exit 2
      ;;
  esac
fi
for command_name in git python3 rsync tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required host command not found: %s\n' "$command_name" >&2
    exit 127
  fi
done
case $platform in
  linux/amd64 | linux/arm64) ;;
  *)
    printf 'error: NVIM_DEBIAN_PLATFORM must be linux/amd64 or linux/arm64 (got %s)\n' \
      "$platform" >&2
  exit 2
    ;;
esac

run_id=$(date -u '+%Y%m%dT%H%M%SZ')
if [[ -z $artifact_parent ]]; then
  host_cache_root=${XDG_CACHE_HOME:-${HOME:?HOME must be set}/.cache}
  artifact_parent="$host_cache_root/dotfiles/nvim-debian-artifacts"
  mkdir -p -- "$artifact_parent"
elif [[ $artifact_parent != /* ]]; then
  artifact_parent="$PWD/$artifact_parent"
fi
if [[ ! -d $artifact_parent ]]; then
  printf 'error: --artifact-dir must name an existing directory: %s\n' "$artifact_parent" >&2
  exit 2
fi
artifact_parent=$(CDPATH='' cd -- "$artifact_parent" && pwd -P)
if [[ $artifact_parent == / ]]; then
  printf 'error: the filesystem root cannot be used as the artifact parent\n' >&2
  exit 2
fi
if [[ $artifact_parent == "$repo_root" || $artifact_parent == "$repo_root/"* ]]; then
  printf 'error: place soak artifacts outside the source repository: %s\n' "$artifact_parent" >&2
  exit 2
fi
artifact_dir=$(mktemp -d "$artifact_parent/nvim-debian-$run_id.XXXXXXXX")
artifact_suffix=${artifact_dir##*.}
container_name=$(
  printf 'dotfiles-nvim-debian-%s-%s' "$run_id" "$artifact_suffix" |
    tr '[:upper:]' '[:lower:]'
)

source_snapshot=
source_snapshot_cleanup_active=0
build_transport_root=
build_fifo=
build_engine_pid=
build_engine_reaped=0
build_log_pid=
build_log_reaped=0
build_launch_started=0
transport_root=
container_fifo=
container_cidfile=

cleanup_source_snapshot() {
  if ((source_snapshot_cleanup_active == 0)); then
    return 0
  fi
  case $source_snapshot in
    "$artifact_parent"/nvim-source-*)
      if rm -rf -- "$source_snapshot"; then
        source_snapshot_cleanup_active=0
        return 0
      fi
      ;;
    *)
      printf 'error: refusing to remove unexpected source snapshot path: %s\n' \
        "$source_snapshot" >&2
      ;;
  esac
  return 1
}

wait_for_early_child() {
  local child_pid=$1
  local output_variable=$2
  local child_status

  while :; do
    if wait "$child_pid"; then
      child_status=0
    else
      child_status=$?
    fi
    if kill -0 "$child_pid" 2>/dev/null; then
      continue
    fi
    printf -v "$output_variable" '%s' "$child_status"
    return 0
  done
}

terminate_early_child() {
  local child_pid=$1
  local output_variable=$2
  local deadline=$((SECONDS + 10))

  kill -TERM "$child_pid" 2>/dev/null || true
  while kill -0 "$child_pid" 2>/dev/null && ((SECONDS < deadline)); do
    sleep 0.1
  done
  if kill -0 "$child_pid" 2>/dev/null; then
    kill -KILL "$child_pid" 2>/dev/null || true
  fi
  wait_for_early_child "$child_pid" "$output_variable"
}

cleanup_build_transport() {
  local cleanup_status=0
  if [[ -n $build_fifo ]]; then
    rm -f -- "$build_fifo" || cleanup_status=1
  fi
  if [[ -n $build_transport_root ]]; then
    rmdir "$build_transport_root" 2>/dev/null || cleanup_status=1
  fi
  build_fifo=
  build_transport_root=
  return "$cleanup_status"
}

cleanup_early_main_transport() {
  local cleanup_status=0
  if [[ -n $container_fifo ]]; then
    rm -f -- "$container_fifo" || cleanup_status=1
  fi
  if [[ -n $container_cidfile ]]; then
    rm -f -- "$container_cidfile" || cleanup_status=1
  fi
  if [[ -n $transport_root ]]; then
    rmdir "$transport_root" 2>/dev/null || cleanup_status=1
  fi
  return "$cleanup_status"
}

early_runner_cleanup() {
  local status=$?
  local ignored_status

  trap - EXIT
  trap '' INT TERM
  set +e
  if [[ -n $build_engine_pid ]] && ((build_engine_reaped == 0)); then
    terminate_early_child "$build_engine_pid" ignored_status
  fi
  if [[ -n $build_log_pid ]] && ((build_log_reaped == 0)); then
    terminate_early_child "$build_log_pid" ignored_status
  fi
  : "${ignored_status:-}"
  cleanup_build_transport || true
  cleanup_early_main_transport || true
  cleanup_source_snapshot || true
  exit "$status"
}

on_early_signal() {
  local signal_name=$1
  local signal_status=$2
  local child_pid=

  trap '' INT TERM
  if ((build_launch_started)); then
    child_pid=${build_engine_pid:-$!}
    build_engine_pid=$child_pid
    [[ -n $build_engine_pid ]] && kill -TERM "$build_engine_pid" 2>/dev/null || true
  fi
  if [[ -n $build_log_pid ]]; then
    kill -TERM "$build_log_pid" 2>/dev/null || true
  fi
  printf 'Received %s before validation launch; cleaning up the source snapshot...\n' \
    "$signal_name" >&2
  exit "$signal_status"
}

trap early_runner_cleanup EXIT
trap 'on_early_signal INT 130' INT
trap 'on_early_signal TERM 143' TERM

source_snapshot=$(mktemp -d "$artifact_parent/nvim-source-$run_id.XXXXXXXX")
source_snapshot_cleanup_active=1
source_manifest="$artifact_dir/source-manifest.nul"
source_manifest_after="$artifact_dir/source-manifest-after.nul"
source_candidates="$artifact_dir/source-candidates.nul"
source_candidates_after="$artifact_dir/source-candidates-after.nul"

build_source_manifest() {
  local candidates=$1
  local manifest=$2
  local relative_path
  local -a local_excludes=(
    --exclude='.jj/'
    --exclude='.jj/**'
    --exclude='.claude/'
    --exclude='.claude/**'
    --exclude='.zoekt/'
    --exclude='.zoekt/**'
    --exclude='helpers/chrome/.vscode/chrome-user-data/'
    --exclude='helpers/chrome/.vscode/chrome-user-data/**'
    --exclude='.DS_Store'
    --exclude='**/.DS_Store'
    --exclude='.dotfiles_backup_*'
    --exclude='.dotfiles_backup_*/**'
  )

  git -C "$repo_root" ls-files --cached --others --exclude-standard \
    "${local_excludes[@]}" -z >"$candidates"
  : >"$manifest"
  while IFS= read -r -d '' relative_path; do
    if [[ -e $repo_root/$relative_path || -L $repo_root/$relative_path ]]; then
      printf '%s\0' "$relative_path" >>"$manifest"
    fi
  done <"$candidates"
}

if git -C "$repo_root" ls-files --stage | awk '$1 == "160000" { found = 1 } END { exit !found }'; then
  printf 'error: the Debian snapshot does not support Git submodules\n' >&2
  exit 2
fi

source_commit_before=$(git -C "$repo_root" rev-parse HEAD)
git -C "$repo_root" status --porcelain=v1 --untracked-files=all >"$artifact_dir/source-status-before.txt"
git -C "$repo_root" diff --binary HEAD >"$artifact_dir/source-tracked-before.patch"
build_source_manifest "$source_candidates" "$source_manifest"

rsync -a --from0 --files-from="$source_manifest" --relative -- "$repo_root/" "$source_snapshot/"

source_commit_after=$(git -C "$repo_root" rev-parse HEAD)
git -C "$repo_root" status --porcelain=v1 --untracked-files=all >"$artifact_dir/source-status-after.txt"
git -C "$repo_root" diff --binary HEAD >"$artifact_dir/source-tracked-after.patch"
build_source_manifest "$source_candidates_after" "$source_manifest_after"
rsync -a --checksum --dry-run --itemize-changes --omit-dir-times \
  --from0 --files-from="$source_manifest" --relative \
  -- "$repo_root/" "$source_snapshot/" |
  awk 'substr($0, 2, 1) != "d"' >"$artifact_dir/source-drift.txt"

if
  [[ $source_commit_before != "$source_commit_after" ]] \
    || ! cmp -s "$artifact_dir/source-status-before.txt" "$artifact_dir/source-status-after.txt" \
    || ! cmp -s "$artifact_dir/source-tracked-before.patch" "$artifact_dir/source-tracked-after.patch" \
    || ! cmp -s "$source_manifest" "$source_manifest_after" \
    || [[ -s $artifact_dir/source-drift.txt ]]
then
  printf 'error: source changed while the isolated snapshot was being created; retry this run\n' >&2
  printf 'incomplete snapshot artifacts: %s\n' "$artifact_dir" >&2
  exit 75
fi

source_commit=$source_commit_before
cp -p -- "$artifact_dir/source-status-before.txt" "$artifact_dir/source-status.txt"
cp -p -- "$artifact_dir/source-tracked-before.patch" "$artifact_dir/source-tracked.patch"
while IFS= read -r -d '' relative_path; do
  printf '%q\n' "$relative_path"
done <"$source_manifest" >"$artifact_dir/source-manifest.txt"

chmod -R a+rX "$source_snapshot"
tar -C "$source_snapshot" -cf "$artifact_dir/source-snapshot.tar" .
if command -v sha256sum >/dev/null 2>&1; then
  source_archive_sha256=$(sha256sum "$artifact_dir/source-snapshot.tar" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then
  source_archive_sha256=$(shasum -a 256 "$artifact_dir/source-snapshot.tar" | awk '{ print $1 }')
else
  printf 'error: sha256sum or shasum is required to fingerprint the source snapshot\n' >&2
  exit 127
fi

{
  printf 'run_id=%s\n' "$run_id"
  printf 'started_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'container_engine=%s\n' "$container_engine"
  printf 'image=%s\n' "$image"
  printf 'platform=%s\n' "$platform"
  printf 'short=%s\n' "$short_mode"
  printf 'soak_seconds=%s\n' "$soak_seconds"
  printf 'concurrency=%s\n' "$concurrency"
  printf 'artifact_sync_seconds=%s\n' "$artifact_sync_seconds"
  printf 'artifact_sync_timeout_seconds=%s\n' "$artifact_sync_timeout_seconds"
  printf 'artifact_finalize_grace_seconds=%s\n' "$artifact_finalize_grace_seconds"
  printf 'timeout_kill_after_seconds=%s\n' "$timeout_kill_after_seconds"
  printf 'repo_root=%s\n' "$repo_root"
  printf 'artifact_parent=%s\n' "$artifact_parent"
  printf 'artifact_dir=%s\n' "$artifact_dir"
  printf 'container_name=%s\n' "$container_name"
  printf 'repo_commit=%s\n' "$source_commit"
  printf 'source_snapshot=%s\n' "$source_snapshot"
  printf 'source_archive_sha256=%s\n' "$source_archive_sha256"
} >"$artifact_dir/host-run.env"

printf 'Artifacts: %s\n' "$artifact_dir"

if ((build_image)); then
  printf 'Building %s from Debian testing...\n' "$image"
  build_transport_root=$(mktemp -d "${TMPDIR:-/tmp}/nvim-debian-build.XXXXXXXX")
  build_fifo="$build_transport_root/build.out"
  mkfifo -m 600 "$build_fifo"
  build_cleanup_status=0
  build_status=1
  build_log_status=1
  set +e
  tee "$artifact_dir/image-build.log" <"$build_fifo" &
  build_log_pid=$!
  build_launch_started=1
  "$container_engine" build \
    --platform "$platform" \
    --file "$source_snapshot/tests/nvim-debian/Dockerfile" \
    --tag "$image" \
    "$source_snapshot/tests/nvim-debian" >"$build_fifo" 2>&1 &
  build_engine_pid=$!
  wait_for_early_child "$build_engine_pid" build_status
  build_engine_reaped=1
  wait_for_early_child "$build_log_pid" build_log_status
  build_log_reaped=1
  cleanup_build_transport || build_cleanup_status=$?
  set -e
  if ((build_status != 0)); then
    printf 'Image build failed with status %d; see %s\n' "$build_status" "$artifact_dir/image-build.log" >&2
    exit "$build_status"
  fi
  if ((build_log_status != 0)); then
    printf 'Image build log capture failed with status %d; see %s\n' \
      "$build_log_status" "$artifact_dir/image-build.log" >&2
    exit "$build_log_status"
  fi
  if ((build_cleanup_status != 0)); then
    printf 'Image build transport cleanup failed; artifacts: %s\n' \
      "$artifact_dir" >&2
    exit "$build_cleanup_status"
  fi
fi

if ! image_id=$("$container_engine" image inspect --format '{{.Id}}' "$image"); then
  printf 'error: unable to inspect container image: %s\n' "$image" >&2
  exit 1
fi
if [[ -z $image_id ]]; then
  printf 'error: container image inspection returned no immutable image ID: %s\n' "$image" >&2
  exit 1
fi
image_os=$("$container_engine" image inspect --format '{{.Os}}' "$image")
image_architecture=$("$container_engine" image inspect --format '{{.Architecture}}' "$image")
expected_image_architecture=${platform#linux/}
if [[ $image_os != linux || $image_architecture != "$expected_image_architecture" ]]; then
  printf 'error: image platform is %s/%s, expected %s\n' \
    "$image_os" "$image_architecture" "$platform" >&2
  exit 1
fi
image_created=$("$container_engine" image inspect --format '{{.Created}}' "$image")
image_repo_digests=$(
  "$container_engine" image inspect --format '{{json .RepoDigests}}' "$image" 2>/dev/null || printf 'unavailable'
)
{
  printf 'image_id=%s\n' "$image_id"
  printf 'image_os=%s\n' "$image_os"
  printf 'image_architecture=%s\n' "$image_architecture"
  printf 'image_created=%s\n' "$image_created"
  printf 'image_repo_digests=%s\n' "$image_repo_digests"
} >>"$artifact_dir/host-run.env"

printf 'Running Debian Neovim suite (SHORT=%s SOAK_SECONDS=%s CONCURRENCY=%s)...\n' \
  "$short_mode" "$soak_seconds" "$concurrency"

container_uid=$(id -u)
container_gid=$(id -g)
if [[ ! $container_uid =~ ^[0-9]+$ || ! $container_gid =~ ^[0-9]+$ ]]; then
  printf 'error: host UID/GID must be numeric (got %s:%s)\n' \
    "$container_uid" "$container_gid" >&2
  exit 1
fi

container_user_mode=host-id
container_user_args=(--user "$container_uid:$container_gid")
container_security_args=()
container_needs_artifact_handoff=0
nvim_debian_detect_container_engine "$container_engine"

if [[ $container_engine_kind == podman ]]; then
  # These are disposable, isolated bind mounts. Disabling SELinux labeling for
  # the container avoids mutating the source tree's labels while still letting
  # enforcing Fedora/RHEL hosts write the artifact mount.
  container_security_args=(--security-opt label=disable)
  if [[ $podman_rootless == true && $podman_native_cli == true ]]; then
    # Rootless Podman needs an explicit identity mapping for a mode-0700 host
    # bind mount. Numeric --user alone selects a subordinate, unmapped ID.
    container_user_mode=rootless-podman-keep-id
    container_user_args=(--userns=keep-id --user "$container_uid:$container_gid")
  elif [[ $podman_rootless == true ]]; then
    # Docker's CLI rejects Podman's `--userns=keep-id` value before contacting
    # a Docker-compatible Podman service. Container root still maps to the
    # invoking user, so use the same unprivileged handoff as rootless Docker.
    container_user_mode=rootless-podman-docker-cli-handoff
    container_user_args=(--user 0:0)
    container_needs_artifact_handoff=1
  fi
else
  engine_security_options=$(
    "$container_engine" info --format '{{json .SecurityOptions}}' 2>/dev/null || true
  )
  if [[ $engine_security_options == *rootless* ]]; then
    # Rootless Docker maps container root to the invoking host user. Start a
    # root wrapper only to hand the mode-0700 artifact mount to `tester`; the
    # validation workload itself remains unprivileged.
    container_user_mode=rootless-docker-handoff
    container_user_args=(--user 0:0)
    container_needs_artifact_handoff=1
  elif [[ $engine_security_options == *userns* ]]; then
    printf '%s\n' \
      'error: Docker userns-remap cannot safely write the mode-0700 host artifact directory.' \
      'Use rootless Docker, rootless Podman, or a non-remapped Docker daemon.' >&2
    exit 2
  fi
fi
if [[ $container_uid == 0 ]]; then
  # A root caller would otherwise run every validation with DAC override
  # capabilities. Keep the suite representative by using the same ownership
  # handoff and `tester` execution path as rootless Docker.
  container_user_mode=root-caller-handoff
  container_user_args=(--user 0:0)
  container_needs_artifact_handoff=1
fi
if ((artifact_handoff_selftest)); then
  # Exercise the root-wrapper/ownership-restoration path on a conventional
  # daemon without requiring a separate rootless engine in CI.
  container_user_mode=artifact-handoff-selftest
  container_user_args=(--user 0:0)
  container_needs_artifact_handoff=1
fi
{
  printf 'container_engine_kind=%s\n' "$container_engine_kind"
  printf 'podman_native_cli=%s\n' "$podman_native_cli"
  printf 'container_engine_server_metadata=%s\n' "$engine_server_metadata"
  printf 'container_engine_security_options=%s\n' "$engine_security_options"
  printf 'container_uid=%s\n' "$container_uid"
  printf 'container_gid=%s\n' "$container_gid"
  printf 'container_user_mode=%s\n' "$container_user_mode"
} >>"$artifact_dir/host-run.env"

container_command=(/bin/bash /workspace/dotfiles/tests/nvim-debian/suite.sh)
if ((container_needs_artifact_handoff)); then
  # The wrapper is evaluated by the container's Bash, not this host shell.
  # shellcheck disable=SC2016
  container_command=(
    /bin/bash
    -c
    '
set -euo pipefail
artifact_dir=$1
shift
child_pid=
signal_relayed=0
artifact_finalize_grace_seconds=${ARTIFACT_FINALIZE_GRACE_SECONDS:?}

restore_artifacts() {
  local status=$?
  local child_status=0
  local deadline
  trap - EXIT
  trap "" INT TERM
  set +e
  if [[ -n $child_pid ]]; then
    if ((signal_relayed == 0)); then
      kill -TERM -- "-$child_pid" 2>/dev/null
    fi
    deadline=$((SECONDS + artifact_finalize_grace_seconds))
    while ((SECONDS < deadline)); do
      kill -0 "$child_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$child_pid" 2>/dev/null; then
      kill -KILL -- "-$child_pid" 2>/dev/null
    fi
    wait "$child_pid" 2>/dev/null || child_status=$?
    if ((signal_relayed)); then
      status=$child_status
    fi
  fi
  chown -R 0:0 "$artifact_dir"
  exit "$status"
}

relay_signal() {
  local signal=$1
  local status=$2
  signal_relayed=1
  if [[ -n $child_pid ]]; then
    kill "-$signal" -- "-$child_pid" 2>/dev/null || true
  fi
  exit "$status"
}

trap restore_artifacts EXIT
trap "relay_signal INT 130" INT
trap "relay_signal TERM 143" TERM

chown -R tester:tester "$artifact_dir"
setsid /usr/bin/setpriv --reuid=tester --regid=tester --init-groups -- \
  /usr/bin/env --default-signal=INT,QUIT -- "$@" &
child_pid=$!
set +e
wait "$child_pid"
status=$?
set -e
child_pid=
exit "$status"
'
    nvim-artifact-handoff
    /artifacts
    /bin/bash
    /workspace/dotfiles/tests/nvim-debian/suite.sh
  )
fi

artifact_handoff_active=$container_needs_artifact_handoff
engine_stop_timeout_seconds=$((artifact_finalize_grace_seconds + 30))
container_run_label_key=dotfiles.nvim.run-id
container_run_label_value="$run_id-$artifact_suffix"
owner_restore_name="$container_name-owner"
owner_restore_label_value="$container_run_label_value-owner"
owner_restore_timeout_seconds=60
transport_root=$(mktemp -d "${TMPDIR:-/tmp}/nvim-debian-run.XXXXXXXX")
container_fifo="$transport_root/container.out"
container_cidfile="$transport_root/container.cid"
mkfifo -m 600 "$container_fifo"

host_signal_status=0
host_signal_name=
host_stop_failed=0
container_engine_pid=
container_engine_reaped=0
container_log_pid=
container_log_reaped=0
container_log_fd_open=0
engine_launch_started=0
container_post_reap_settle_complete=0
engine_status=125
container_log_status=1
runner_cleanup_complete=0

wait_for_child() {
  local child_pid=$1
  local output_variable=$2
  local child_status

  while :; do
    if wait "$child_pid"; then
      child_status=0
    else
      child_status=$?
    fi
    if kill -0 "$child_pid" 2>/dev/null; then
      continue
    fi
    printf -v "$output_variable" '%s' "$child_status"
    return 0
  done
}

run_host_command_bounded() {
  local timeout_seconds=$1
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
process = subprocess.Popen(sys.argv[2:])
try:
    status = process.wait(timeout=timeout_seconds)
except subprocess.TimeoutExpired:
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    status = 124
sys.exit(status)
PY
}

run_engine_bounded() {
  local timeout_seconds=$1
  shift
  run_host_command_bounded "$timeout_seconds" "$container_engine" "$@"
}

owned_container_ref() {
  local candidate
  local label
  local -a candidates=()

  if [[ -s $container_cidfile ]] && IFS= read -r candidate <"$container_cidfile"; then
    [[ -n $candidate ]] && candidates+=("$candidate")
  fi
  candidates+=("$container_name")

  for candidate in "${candidates[@]}"; do
    label=$(
      run_engine_bounded 5 inspect \
        --format '{{ index .Config.Labels "dotfiles.nvim.run-id" }}' \
        "$candidate" 2>/dev/null
    ) || continue
    if [[ $label == "$container_run_label_value" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

container_state() {
  run_engine_bounded 5 inspect --format '{{.State.Status}}' "$1" 2>/dev/null
}

container_is_active() {
  case $1 in
    dead | exited | stopped) return 1 ;;
    *) return 0 ;;
  esac
}

terminate_container_engine_cli() {
  local deadline
  if [[ -n $container_engine_pid ]] \
    && ((container_engine_reaped == 0)) \
    && kill -0 "$container_engine_pid" 2>/dev/null
  then
    kill -TERM "$container_engine_pid" 2>/dev/null || true
    deadline=$((SECONDS + 10))
    while kill -0 "$container_engine_pid" 2>/dev/null && ((SECONDS < deadline)); do
      sleep 0.1
    done
    if kill -0 "$container_engine_pid" 2>/dev/null; then
      kill -KILL "$container_engine_pid" 2>/dev/null || true
    fi
  fi
}

stop_owned_container() {
  local requested_signal=${1:-TERM}
  local post_reap=${2:-0}
  local ref=
  local state=
  local missing_samples=0
  local deadline=$((SECONDS + 10))

  if ((engine_launch_started == 0)); then
    return 0
  fi
  if ((post_reap && container_post_reap_settle_complete)); then
    return 0
  fi
  while ! ref=$(owned_container_ref); do
    if ((post_reap == 0)) \
      && [[ -n $container_engine_pid ]] \
      && ! kill -0 "$container_engine_pid" 2>/dev/null
    then
      break
    fi
    if ((SECONDS >= deadline)); then
      break
    fi
    sleep 0.1
  done
  if ((post_reap)); then
    # This bounded, post-client poll closes the Create-RPC/cidfile race even
    # when the engine CLI has already exited.
    container_post_reap_settle_complete=1
  fi

  if [[ -z $ref ]]; then
    # The client may be stuck before writing its cidfile. Terminating this
    # exact child is safe; the common path reinspects the unique label after
    # reaping it to catch a daemon-create/client-write race.
    if [[ -n $container_engine_pid ]] \
      && kill -0 "$container_engine_pid" 2>/dev/null
    then
      kill -TERM "$container_engine_pid" 2>/dev/null || true
    fi
    return 0
  fi

  state=$(container_state "$ref" || true)
  if [[ $state == created || $state == configured || $state == initialized ]]; then
    deadline=$((SECONDS + 10))
    while
      [[ $state == created || $state == configured || $state == initialized ]] \
        && ((SECONDS < deadline))
    do
      if [[ -n $container_engine_pid ]] \
        && ! kill -0 "$container_engine_pid" 2>/dev/null
      then
        break
      fi
      sleep 0.1
      state=$(container_state "$ref" || true)
    done
    if [[ $state == created || $state == configured || $state == initialized ]]; then
      if ! run_engine_bounded 10 rm -f "$ref" >/dev/null 2>&1; then
        host_stop_failed=1
      fi
      terminate_container_engine_cli
      return 0
    fi
  fi
  container_is_active "$state" || return 0

  if [[ $state == paused ]]; then
    run_engine_bounded 10 unpause "$ref" >/dev/null 2>&1 || true
    state=$(container_state "$ref" || true)
  fi
  if [[ $state != stopping && $state != removing ]]; then
    run_engine_bounded 10 kill --signal "$requested_signal" "$ref" >/dev/null 2>&1 || true
  fi

  deadline=$((SECONDS + engine_stop_timeout_seconds))
  while ((SECONDS < deadline)); do
    state=$(container_state "$ref" || true)
    container_is_active "$state" || return 0
    if [[ -z $state ]]; then
      missing_samples=$((missing_samples + 1))
      if ((missing_samples >= 20)) && ! owned_container_ref >/dev/null; then
        return 0
      fi
    else
      missing_samples=0
    fi
    sleep 0.1
  done

  if owned_container_ref >/dev/null; then
    run_engine_bounded 10 kill --signal KILL "$ref" >/dev/null 2>&1 || true
  fi
  deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    state=$(container_state "$ref" || true)
    container_is_active "$state" || return 0
    sleep 0.1
  done
  host_stop_failed=1
  terminate_container_engine_cli
  printf 'error: validation container did not stop: %s\n' "$ref" >&2
  return 1
}

on_host_signal() {
  local signal_name=$1
  local signal_status=$2

  if ((host_signal_status != 0)); then
    return
  fi
  host_signal_name=$signal_name
  host_signal_status=$signal_status
  trap '' INT TERM
  printf 'Received %s; stopping validation container and preserving artifacts...\n' \
    "$signal_name" >&2
  stop_owned_container "$signal_name" 0 || true
  terminate_container_engine_cli
}

restore_artifact_owner() {
  local restore_pid
  local restore_status=1

  python3 - \
    "$owner_restore_timeout_seconds" \
    "$container_engine" \
    "$owner_restore_name" \
    "$container_run_label_key" \
    "$owner_restore_label_value" \
    "$container_engine" run \
    --name "$owner_restore_name" \
    --label "$container_run_label_key=$owner_restore_label_value" \
    --platform "$platform" \
    --user 0:0 \
    "${container_security_args[@]}" \
    --volume "$artifact_dir:/artifacts" \
    "$image_id" \
    /bin/chown -R 0:0 /artifacts >/dev/null 2>&1 <<'PY' &
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
engine, helper_name, label_key, label_value = sys.argv[2:6]
command = sys.argv[6:]


def run_capture(arguments, timeout):
    try:
        return subprocess.run(
            arguments,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def helper_label():
    result = run_capture(
        [
            engine,
            "inspect",
            "--format",
            '{{ index .Config.Labels "' + label_key + '" }}',
            helper_name,
        ],
        5,
    )
    if result is None or result.returncode != 0:
        return None
    return result.stdout.strip()


def remove_owned_helper():
    label = helper_label()
    if label is None:
        return True
    if label != label_value:
        return False
    result = run_capture([engine, "rm", "-f", helper_name], 10)
    return result is not None and result.returncode == 0


# A retry can encounter a helper from an earlier bounded attempt. Remove only
# the exact, per-run labeled container; never act on a same-name collision.
if not remove_owned_helper():
    sys.exit(125)

process = subprocess.Popen(
    command,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
try:
    run_status = process.wait(timeout=timeout_seconds)
except subprocess.TimeoutExpired:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    run_status = 124

# Close the killed-client/Create-RPC race without any unbounded engine call.
settle_deadline = time.monotonic() + 10
label = helper_label()
while label is None and time.monotonic() < settle_deadline:
    time.sleep(0.1)
    label = helper_label()

helper_exit_status = None
if label == label_value:
    result = run_capture(
        [engine, "inspect", "--format", "{{.State.ExitCode}}", helper_name],
        5,
    )
    if result is not None and result.returncode == 0:
        try:
            helper_exit_status = int(result.stdout.strip())
        except ValueError:
            pass
elif label is not None:
    # The unique name unexpectedly belongs to something else. Preserve it.
    sys.exit(125)

removed = remove_owned_helper()
if run_status == 0 and helper_exit_status == 0 and removed:
    sys.exit(0)
sys.exit(run_status if run_status != 0 else 1)
PY
  restore_pid=$!
  wait_for_child "$restore_pid" restore_status
  return "$restore_status"
}

cleanup_transport() {
  local cleanup_status=0

  if ((container_log_fd_open)); then
    exec {container_log_fd}>&-
    container_log_fd_open=0
  fi
  rm -f -- "$container_fifo" "$container_cidfile" || cleanup_status=1
  rmdir "$transport_root" 2>/dev/null || cleanup_status=1
  cleanup_source_snapshot || cleanup_status=1
  return "$cleanup_status"
}

emergency_runner_cleanup() {
  local status=$?
  local ignored_status

  trap - EXIT
  trap '' INT TERM
  set +e
  if ((runner_cleanup_complete == 0)); then
    stop_owned_container TERM 0
    if [[ -n $container_engine_pid ]] && ((container_engine_reaped == 0)); then
      terminate_container_engine_cli
      wait_for_child "$container_engine_pid" ignored_status
      container_engine_reaped=1
    fi
    stop_owned_container TERM 1
    if [[ -n $container_log_pid ]] && ((container_log_reaped == 0)); then
      if kill -0 "$container_log_pid" 2>/dev/null; then
        kill -TERM "$container_log_pid" 2>/dev/null || true
      fi
      wait_for_child "$container_log_pid" ignored_status
      container_log_reaped=1
    fi
    : "$ignored_status"
    if ((artifact_handoff_active)); then
      restore_artifact_owner || true
    fi
    cleanup_transport || true
  fi
  exit "$status"
}

# Open the host log before a handoff wrapper can transfer ownership of the
# mode-0700 artifact directory to the unprivileged container user.
exec {container_log_fd}>"$artifact_dir/container.log"
container_log_fd_open=1
trap emergency_runner_cleanup EXIT
trap 'on_host_signal INT 130' INT
trap 'on_host_signal TERM 143' TERM

set +e
tee "/dev/fd/$container_log_fd" <"$container_fifo" &
container_log_pid=$!

if ((host_signal_status == 0)); then
  engine_launch_started=1
  "$container_engine" run \
    --name "$container_name" \
    --cidfile "$container_cidfile" \
    --label "$container_run_label_key=$container_run_label_value" \
    --stop-timeout "$engine_stop_timeout_seconds" \
    --platform "$platform" \
    "${container_user_args[@]}" \
    "${container_security_args[@]}" \
    --workdir /tmp \
    --env "SHORT=$short_mode" \
    --env "SOAK_SECONDS=$soak_seconds" \
    --env "CONCURRENCY=$concurrency" \
    --env "SHORT_BATCHES=${SHORT_BATCHES:-7}" \
    --env "RESOURCE_SAMPLE_SECONDS=${RESOURCE_SAMPLE_SECONDS:-5}" \
    --env "SETUP_TIMEOUT_SECONDS=${SETUP_TIMEOUT_SECONDS:-1800}" \
    --env "STARTUP_TIMEOUT_SECONDS=${STARTUP_TIMEOUT_SECONDS:-120}" \
    --env "WORKLOAD_TIMEOUT_SECONDS=${WORKLOAD_TIMEOUT_SECONDS:-300}" \
    --env "TIMEOUT_KILL_AFTER_SECONDS=$timeout_kill_after_seconds" \
    --env "ARTIFACT_SYNC_SECONDS=$artifact_sync_seconds" \
    --env "ARTIFACT_SYNC_TIMEOUT_SECONDS=$artifact_sync_timeout_seconds" \
    --env "ARTIFACT_FINALIZE_GRACE_SECONDS=$artifact_finalize_grace_seconds" \
    --env "NVIM_DEBIAN_TIMEOUT_SELFTEST=${NVIM_DEBIAN_TIMEOUT_SELFTEST:-0}" \
    --env "REPO_ROOT=/workspace/dotfiles" \
    --env "ARTIFACT_DIR=/artifacts" \
    --env "STAGING_ROOT=/var/tmp/nvim-debian-stage" \
    --env "SOURCE_COMMIT=$source_commit" \
    --env "SOURCE_IMAGE_ID=$image_id" \
    --env "GIT_CONFIG_COUNT=1" \
    --env "GIT_CONFIG_KEY_0=safe.directory" \
    --env "GIT_CONFIG_VALUE_0=/workspace/dotfiles" \
    --volume "$source_snapshot:/workspace/dotfiles:ro" \
    --volume "$artifact_dir:/artifacts" \
    "$image_id" \
    "${container_command[@]}" >"$container_fifo" 2>&1 &
  container_engine_pid=$!
  if ((host_signal_status != 0)); then
    stop_owned_container "$host_signal_name" 0 || true
    terminate_container_engine_cli
  fi
  wait_for_child "$container_engine_pid" engine_status
  container_engine_reaped=1
else
  engine_status=$host_signal_status
fi

stop_owned_container "${host_signal_name:-TERM}" 1 || true

if [[ -n $container_log_pid ]]; then
  if [[ -z $container_engine_pid ]] && kill -0 "$container_log_pid" 2>/dev/null; then
    kill -TERM "$container_log_pid" 2>/dev/null || true
  fi
  wait_for_child "$container_log_pid" container_log_status
  container_log_reaped=1
fi
if ((container_log_fd_open)); then
  exec {container_log_fd}>&-
  container_log_fd_open=0
fi
set -e

validation_container_ref=$(owned_container_ref || true)
validation_container_state=
if [[ -n $validation_container_ref ]]; then
  validation_container_state=$(container_state "$validation_container_ref" || true)
fi

if [[ -n $validation_container_ref ]] \
  && ! container_is_active "$validation_container_state"
then
  suite_status=$(
    run_engine_bounded 5 inspect \
      --format '{{.State.ExitCode}}' \
      "$validation_container_ref" 2>/dev/null || printf '%s' "$engine_status"
  )
else
  suite_status=$engine_status
fi
if [[ ! $suite_status =~ ^[0-9]+$ ]]; then
  printf 'error: container returned an invalid exit status: %s\n' "$suite_status" >&2
  suite_status=1
fi

artifact_owner_status=0
if ((artifact_handoff_active)); then
  if ! restore_artifact_owner; then
    printf 'error: could not restore host ownership of durable artifacts: %s\n' \
      "$artifact_dir" >&2
    artifact_owner_status=1
  else
    unexpected_owner=$(
      find "$artifact_dir" \
        \( ! -user "$container_uid" -o ! -group "$container_gid" \) \
        -print -quit
    )
    if [[ -n $unexpected_owner ]]; then
      printf 'error: artifact ownership was not restored to host UID/GID %s:%s: %s\n' \
        "$container_uid" "$container_gid" "$unexpected_owner" >&2
      artifact_owner_status=1
    else
      artifact_handoff_active=0
    fi
  fi
fi

final_export_valid=0
final_export_marker="$artifact_dir/final-export-complete.env"
if [[ -r $final_export_marker && -r $artifact_dir/summary.env ]]; then
  marker_complete=$(awk -F= '$1 == "complete" { print $2 }' "$final_export_marker")
  marker_status=$(awk -F= '$1 == "status" { print $2 }' "$final_export_marker")
  marker_summary_sha256=$(
    awk -F= '$1 == "summary_sha256" { print $2 }' "$final_export_marker"
  )
  marker_repo_commit=$(
    awk -F= '$1 == "repo_commit" { print $2 }' "$final_export_marker"
  )
  marker_image_id=$(
    awk -F= '$1 == "container_image_id" { print $2 }' "$final_export_marker"
  )
  summary_status=$(awk -F= '$1 == "status" { print $2 }' "$artifact_dir/summary.env")
  if command -v sha256sum >/dev/null 2>&1; then
    durable_summary_sha256=$(sha256sum "$artifact_dir/summary.env" | awk '{ print $1 }')
  else
    durable_summary_sha256=$(shasum -a 256 "$artifact_dir/summary.env" | awk '{ print $1 }')
  fi
  if
    [[ $marker_complete == 1 ]] \
      && [[ $marker_status == "$summary_status" ]] \
      && [[ $marker_status == "$suite_status" ]] \
      && [[ $marker_summary_sha256 == "$durable_summary_sha256" ]] \
      && [[ $marker_repo_commit == "$source_commit" ]] \
      && [[ $marker_image_id == "$image_id" ]]
  then
    final_export_valid=1
  fi
fi

container_remove_status=0
container_retained=0
validation_container_ref=$(owned_container_ref || true)
if ((final_export_valid)); then
  if [[ -z $validation_container_ref ]]; then
    printf '%s\n' \
      'error: final export is valid but validation-container identity/removal could not be verified' >&2
    container_remove_status=1
  elif ! run_engine_bounded 10 rm "$validation_container_ref" >/dev/null; then
    printf 'error: could not remove completed validation container: %s\n' \
      "$validation_container_ref" >&2
    container_remove_status=1
    container_retained=1
  fi
else
  if [[ -n $validation_container_ref ]]; then
    container_retained=1
    validation_container_state=$(container_state "$validation_container_ref" || true)
    printf 'error: final staged-artifact export was not verified; retained %s container %s\n' \
      "${validation_container_state:-unknown-state}" "$validation_container_ref" >&2
    printf 'recovery: %s cp %s:/var/tmp/nvim-debian-stage/artifacts/. %s/\n' \
      "$container_engine" "$validation_container_ref" "$artifact_dir" >&2
  else
    printf '%s\n' \
      'error: final staged-artifact export was not verified and no owned container remains' >&2
  fi
fi

engine_transport_failed=0
if [[ -n $validation_container_ref || $final_export_valid == 1 ]] \
  && ((engine_status != suite_status))
then
  engine_transport_failed=1
fi

runner_status=$suite_status
if ((engine_transport_failed && engine_status != 0 && host_signal_status == 0)); then
  runner_status=$engine_status
fi
if ((container_log_status != 0 && runner_status == 0)); then
  runner_status=$container_log_status
fi
if ((artifact_owner_status != 0 || host_stop_failed != 0 || container_remove_status != 0)) \
  && ((runner_status == 0))
then
  runner_status=1
fi
if ((final_export_valid == 0 && runner_status == 0)); then
  runner_status=1
fi
if ((suite_status == 0)) && [[ ! -r $artifact_dir/summary.env ]]; then
  printf 'error: suite passed but durable container artifacts were not mounted back to the host: %s\n' \
    "$artifact_dir" >&2
  runner_status=1
fi
if ((host_signal_status != 0)); then
  runner_status=$host_signal_status
fi

if ((artifact_handoff_active)); then
  if restore_artifact_owner; then
    artifact_handoff_active=0
  elif ((runner_status == 0)); then
    runner_status=1
  fi
fi
if ! cleanup_transport && ((runner_status == 0)); then
  runner_status=1
fi
# No tracked process or temporary tree remains. Ignore any later signal during
# the tiny provenance-write/exit tail, then reconcile one that arrived during
# final cleanup before freezing the runner status.
trap '' INT TERM
if ((host_signal_status != 0)); then
  runner_status=$host_signal_status
fi

{
  printf 'finished_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'status=%s\n' "$runner_status"
  printf 'engine_status=%s\n' "$engine_status"
  printf 'suite_status=%s\n' "$suite_status"
  printf 'container_log_status=%s\n' "$container_log_status"
  printf 'host_signal_status=%s\n' "$host_signal_status"
  printf 'engine_transport_failed=%s\n' "$engine_transport_failed"
  printf 'host_stop_failed=%s\n' "$host_stop_failed"
  printf 'artifact_owner_status=%s\n' "$artifact_owner_status"
  printf 'final_export_valid=%s\n' "$final_export_valid"
  printf 'container_retained=%s\n' "$container_retained"
} >>"$artifact_dir/host-run.env"

runner_cleanup_complete=1
trap - EXIT

if ((runner_status != 0)); then
  if ((host_signal_status != 0)); then
    printf 'Debian Neovim suite interrupted with status %d; artifacts: %s\n' \
      "$runner_status" "$artifact_dir" >&2
  else
    printf 'Debian Neovim suite failed with status %d; artifacts: %s\n' \
      "$runner_status" "$artifact_dir" >&2
  fi
  exit "$runner_status"
fi

printf 'Debian Neovim suite passed; artifacts: %s\n' "$artifact_dir"
