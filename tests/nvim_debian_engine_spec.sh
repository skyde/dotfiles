#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=tests/nvim-debian/container-engine.sh
source "$repo_root/tests/nvim-debian/container-engine.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_probe() {
  local command_name=$1
  local expected_kind=$2
  local expected_rootless=$3
  local expected_security=$4

  nvim_debian_detect_container_engine "$command_name"
  [[ $container_engine_kind == "$expected_kind" ]] ||
    fail "$command_name kind: expected $expected_kind, got $container_engine_kind"
  [[ $podman_rootless == "$expected_rootless" ]] ||
    fail "$command_name rootless: expected $expected_rootless, got $podman_rootless"
  [[ $engine_security_options == "$expected_security" ]] ||
    fail "$command_name security options were not preserved"
}

native_podman_rootless() {
  case $1:$2 in
    info:--format)
      case $3 in
        *Host.Security.Rootless*) printf 'true\n' ;;
        *SecurityOptions*) printf '%s\n' '["name=selinux","name=rootless"]' ;;
      esac
      ;;
    version:--format) printf '%s\n' '{"Components":[{"Name":"Podman Engine"}]}' ;;
  esac
}

native_podman_rootful() {
  case $1:$2 in
    info:--format)
      case $3 in
        *Host.Security.Rootless*) printf 'false\n' ;;
        *SecurityOptions*) printf '%s\n' '["name=selinux"]' ;;
      esac
      ;;
    version:--format) printf '%s\n' '{"Components":[{"Name":"Podman Engine"}]}' ;;
  esac
}

docker_cli_podman_rootless() {
  case $1:$2 in
    info:--format)
      case $3 in
        *Host.Security.Rootless*) return 1 ;;
        *SecurityOptions*) printf '%s\n' '["name=selinux","name=rootless"]' ;;
      esac
      ;;
    version:--format) printf '%s\n' '{"Components":[{"Name":"Podman Engine"}]}' ;;
  esac
}

docker_cli_podman_rootful() {
  case $1:$2 in
    info:--format)
      case $3 in
        *Host.Security.Rootless*) return 1 ;;
        *SecurityOptions*) printf '%s\n' '["name=selinux"]' ;;
      esac
      ;;
    version:--format) printf '%s\n' '{"Components":[{"Name":"Podman Engine"}]}' ;;
  esac
}

native_docker_rootless() {
  case $1:$2 in
    info:--format)
      case $3 in
        *Host.Security.Rootless*) return 1 ;;
        *SecurityOptions*) printf '%s\n' '["name=seccomp","name=rootless"]' ;;
      esac
      ;;
    version:--format)
      printf '%s\n' '{"Platform":{"Name":"Docker Engine - Community"}}'
      ;;
  esac
}

assert_probe \
  native_podman_rootless podman true '["name=selinux","name=rootless"]'
assert_probe native_podman_rootful podman false '["name=selinux"]'
assert_probe \
  docker_cli_podman_rootless podman true '["name=selinux","name=rootless"]'
assert_probe docker_cli_podman_rootful podman false '["name=selinux"]'
assert_probe \
  native_docker_rootless docker false '["name=seccomp","name=rootless"]'

printf 'nvim Debian container-engine detection tests passed\n'
