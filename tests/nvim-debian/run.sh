#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd -P)
container_engine_kind=
podman_rootless=
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
  WORKLOAD_TIMEOUT_SECONDS, TIMEOUT_KILL_AFTER_SECONDS

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
for command_name in git rsync tar; do
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

source_snapshot=$(mktemp -d "$artifact_parent/nvim-source-$run_id.XXXXXXXX")
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
  printf 'repo_root=%s\n' "$repo_root"
  printf 'artifact_parent=%s\n' "$artifact_parent"
  printf 'artifact_dir=%s\n' "$artifact_dir"
  printf 'repo_commit=%s\n' "$source_commit"
  printf 'source_snapshot=%s\n' "$source_snapshot"
  printf 'source_archive_sha256=%s\n' "$source_archive_sha256"
} >"$artifact_dir/host-run.env"

printf 'Artifacts: %s\n' "$artifact_dir"

if ((build_image)); then
  printf 'Building %s from Debian testing...\n' "$image"
  set +e
  "$container_engine" build \
    --platform "$platform" \
    --file "$source_snapshot/tests/nvim-debian/Dockerfile" \
    --tag "$image" \
    "$source_snapshot/tests/nvim-debian" 2>&1 | tee "$artifact_dir/image-build.log"
  build_pipeline_status=("${PIPESTATUS[@]}")
  build_status=${build_pipeline_status[0]}
  build_log_status=${build_pipeline_status[1]}
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
  if [[ $podman_rootless == true ]]; then
    # Rootless Podman needs an explicit identity mapping for a mode-0700 host
    # bind mount. Numeric --user alone selects a subordinate, unmapped ID.
    container_user_mode=rootless-podman-keep-id
    container_user_args=(--userns=keep-id --user "$container_uid:$container_gid")
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
{
  printf 'container_engine_kind=%s\n' "$container_engine_kind"
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

restore_artifacts() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if [[ -n $child_pid ]]; then
    kill -TERM -- "-$child_pid" 2>/dev/null
    for _ in $(seq 1 50); do
      kill -0 "$child_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL -- "-$child_pid" 2>/dev/null
    wait "$child_pid" 2>/dev/null
  fi
  chown -R 0:0 "$artifact_dir"
  exit "$status"
}

relay_signal() {
  local signal=$1
  local status=$2
  if [[ -n $child_pid ]]; then
    kill "-$signal" -- "-$child_pid" 2>/dev/null || true
  fi
  exit "$status"
}

trap restore_artifacts EXIT
trap "relay_signal INT 130" INT
trap "relay_signal TERM 143" TERM

chown -R tester:tester "$artifact_dir"
setsid /usr/bin/setpriv --reuid=tester --regid=tester --init-groups -- "$@" &
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

restore_artifact_owner() {
  "$container_engine" run --rm \
    --platform "$platform" \
    --user 0:0 \
    "${container_security_args[@]}" \
    --volume "$artifact_dir:/artifacts" \
    "$image_id" \
    /bin/chown -R 0:0 /artifacts >/dev/null 2>&1
}

artifact_handoff_active=$container_needs_artifact_handoff
cleanup_artifact_handoff() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if ((artifact_handoff_active)); then
    restore_artifact_owner
  fi
  exit "$status"
}
if ((artifact_handoff_active)); then
  trap cleanup_artifact_handoff EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

# Open the host log before a handoff wrapper can transfer ownership of the
# mode-0700 artifact directory to the unprivileged container user.
exec {container_log_fd}>"$artifact_dir/container.log"
set +e
"$container_engine" run --rm \
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
  --env "TIMEOUT_KILL_AFTER_SECONDS=${TIMEOUT_KILL_AFTER_SECONDS:-5}" \
  --env "NVIM_DEBIAN_TIMEOUT_SELFTEST=${NVIM_DEBIAN_TIMEOUT_SELFTEST:-0}" \
  --env "REPO_ROOT=/workspace/dotfiles" \
  --env "ARTIFACT_DIR=/artifacts" \
  --env "SOURCE_COMMIT=$source_commit" \
  --env "SOURCE_IMAGE_ID=$image_id" \
  --env "GIT_CONFIG_COUNT=1" \
  --env "GIT_CONFIG_KEY_0=safe.directory" \
  --env "GIT_CONFIG_VALUE_0=/workspace/dotfiles" \
  --volume "$source_snapshot:/workspace/dotfiles:ro" \
  --volume "$artifact_dir:/artifacts" \
  "$image_id" \
  "${container_command[@]}" 2>&1 | tee "/dev/fd/$container_log_fd"
suite_pipeline_status=("${PIPESTATUS[@]}")
suite_status=${suite_pipeline_status[0]}
container_log_status=${suite_pipeline_status[1]}
set -e
exec {container_log_fd}>&-

if ((artifact_handoff_active)); then
  if ! restore_artifact_owner; then
    printf 'error: could not restore host ownership of durable artifacts: %s\n' \
      "$artifact_dir" >&2
    exit 1
  fi
  unexpected_owner=$(
    find "$artifact_dir" \
      \( ! -user "$container_uid" -o ! -group "$container_gid" \) \
      -print -quit
  )
  if [[ -n $unexpected_owner ]]; then
    printf 'error: artifact ownership was not restored to host UID/GID %s:%s: %s\n' \
      "$container_uid" "$container_gid" "$unexpected_owner" >&2
    exit 1
  fi
  artifact_handoff_active=0
  trap - EXIT INT TERM
fi

printf 'finished_utc=%s\nstatus=%s\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$suite_status" >>"$artifact_dir/host-run.env"

if ((suite_status != 0)); then
  printf 'Debian Neovim suite failed with status %d; artifacts: %s\n' "$suite_status" "$artifact_dir" >&2
  exit "$suite_status"
fi
if ((container_log_status != 0)); then
  printf 'Container log capture failed with status %d; artifacts: %s\n' \
    "$container_log_status" "$artifact_dir" >&2
  exit "$container_log_status"
fi
if [[ ! -r $artifact_dir/summary.env ]]; then
  printf 'error: suite passed but durable container artifacts were not mounted back to the host: %s\n' \
    "$artifact_dir" >&2
  exit 1
fi

printf 'Debian Neovim suite passed; artifacts: %s\n' "$artifact_dir"
