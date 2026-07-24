#!/usr/bin/env bash

# Populate container_engine_kind, podman_rootless, podman_native_cli,
# engine_security_options, and engine_server_metadata for either a native CLI
# or a Docker-compatible client. Podman's Docker API exposes "Podman Engine"
# in the server component metadata and reports rootless mode through
# SecurityOptions.
# shellcheck disable=SC2034 # These variables are the function's caller-visible outputs.
nvim_debian_detect_container_engine() {
  local engine=$1
  local native_podman_rootless

  container_engine_kind=docker
  podman_rootless=false
  podman_native_cli=false
  native_podman_rootless=$(
    "$engine" info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true
  )
  engine_security_options=$(
    "$engine" info --format '{{json .SecurityOptions}}' 2>/dev/null || true
  )
  engine_server_metadata=$(
    "$engine" version --format '{{json .Server}}' 2>/dev/null || true
  )

  case $native_podman_rootless in
    true | false)
      container_engine_kind=podman
      podman_rootless=$native_podman_rootless
      podman_native_cli=true
      ;;
  esac

  # A Docker CLI connected to podman system service cannot render Podman's
  # native .Host.Security.Rootless field. Its Docker-compatible /version
  # response identifies the first server component as "Podman Engine".
  if [[ $engine_server_metadata == *Podman\ Engine* ]]; then
    container_engine_kind=podman
  fi

  if [[ $container_engine_kind == podman && $native_podman_rootless != true \
    && $native_podman_rootless != false ]]
  then
    if [[ $engine_security_options == *rootless* ]]; then
      podman_rootless=true
    else
      podman_rootless=false
    fi
  fi
}
