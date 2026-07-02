#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]}"
bin_dir="."
if [[ "$script_source" == */* ]]; then
  bin_dir="${script_source%/*}"
fi
bin_dir="$(cd -- "$bin_dir" && pwd -P)"

TMUX_CLIENT_LIVE=0

tmux_client_is_live() {
  [[ -n "${TMUX:-}" ]] || return 1
  tmux display-message -p '#{client_tty}' >/dev/null 2>&1
}

is_ssh_session() {
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]
}

tmux_cmd() {
  if [[ "$TMUX_CLIENT_LIVE" == "1" || -z "${TMUX:-}" ]]; then
    tmux "$@"
  else
    (unset TMUX; tmux "$@")
  fi
}

display_tmux_message() {
  local message="$1"

  if [[ "$TMUX_CLIENT_LIVE" == "1" || -n "${TMUX:-}" ]]; then
    tmux_cmd display-message "$message" 2>/dev/null || printf '%s\n' "$message" >&2
  else
    printf '%s\n' "$message" >&2
  fi
}

socket_can_be_probed() {
  command -v nc >/dev/null 2>&1
}

socket_is_live() {
  local socket="${1:-}"

  [[ -S "$socket" ]] || return 1
  socket_can_be_probed || return 0
  nc -z -U "$socket" >/dev/null 2>&1
}

list_vscode_socket_candidates() {
  local socket_dir="$1" socket nullglob_was_set=0

  if command -v find >/dev/null 2>&1; then
    if command -v sort >/dev/null 2>&1; then
      find "$socket_dir" -maxdepth 1 -type s -name 'vscode-ipc-*.sock' -print 2>/dev/null | sort -r
    else
      find "$socket_dir" -maxdepth 1 -type s -name 'vscode-ipc-*.sock' -print 2>/dev/null
    fi
    return
  fi

  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  for socket in "$socket_dir"/vscode-ipc-*.sock; do
    [[ -S "$socket" ]] && printf '%s\n' "$socket"
  done
  if [[ "$nullglob_was_set" == "0" ]]; then
    shopt -u nullglob
  fi
}

list_vscode_browser_helpers() {
  local server_root="$1" helper nullglob_was_set=0

  if command -v find >/dev/null 2>&1; then
    if command -v sort >/dev/null 2>&1 && command -v tail >/dev/null 2>&1; then
      find "$server_root" -path '*/server/bin/helpers/browser.sh' -type f -perm -u+x -print 2>/dev/null | sort | tail -n 1
    else
      find "$server_root" -path '*/server/bin/helpers/browser.sh' -type f -perm -u+x -print 2>/dev/null
    fi
    return
  fi

  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  for helper in "$server_root"/*/server/bin/helpers/browser.sh; do
    [[ -x "$helper" ]] && printf '%s\n' "$helper"
  done
  if [[ "$nullglob_was_set" == "0" ]]; then
    shopt -u nullglob
  fi
}

browser_command=()
editor_command=()
split_command_words_result=()

split_command_words() {
  local input="$1"
  local index=0 char next quote="" word="" have_word=0

  split_command_words_result=()
  while ((index < ${#input})); do
    char="${input:index:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$char" == "$quote" ]]; then
        quote=""
        have_word=1
      elif [[ "$quote" == '"' && "$char" == "\\" ]]; then
        index=$((index + 1))
        if ((index < ${#input})); then
          next="${input:index:1}"
          word+="$next"
        else
          word+="\\"
        fi
        have_word=1
      else
        word+="$char"
        have_word=1
      fi
    else
      if [[ "$char" =~ [[:space:]] ]]; then
        if [[ "$have_word" == "1" ]]; then
          split_command_words_result+=("$word")
          word=""
          have_word=0
        fi
      elif [[ "$char" == "'" || "$char" == '"' ]]; then
        quote="$char"
        have_word=1
      elif [[ "$char" == "\\" ]]; then
        index=$((index + 1))
        if ((index < ${#input})); then
          next="${input:index:1}"
          word+="$next"
        else
          word+="\\"
        fi
        have_word=1
      else
        word+="$char"
        have_word=1
      fi
    fi
    index=$((index + 1))
  done

  [[ -z "$quote" ]] || return 1
  if [[ "$have_word" == "1" ]]; then
    split_command_words_result+=("$word")
  fi
}

resolve_browser_command() {
  local browser="${BROWSER:-}"
  local candidate word
  local -a browser_candidates

  browser_command=()

  [[ -n "$browser" ]] || return 1
  if [[ "$browser" == */* ]]; then
    if [[ -x "$browser" ]]; then
      browser_command=("$browser")
      return 0
    fi
  fi

  IFS=: read -r -a browser_candidates <<<"$browser"
  for candidate in "${browser_candidates[@]}"; do
    browser_command=()
    [[ -n "$candidate" ]] || continue

    if [[ "$candidate" == */* && -x "$candidate" ]]; then
      browser_command=("$candidate")
      return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
      while IFS= read -r word; do
        browser_command+=("$word")
      done < <(
        BROWSER_VALUE="$candidate" python3 - <<'PY' 2>/dev/null
import os
import shlex
import sys

try:
    words = shlex.split(os.environ["BROWSER_VALUE"])
except ValueError:
    sys.exit(1)

for word in words:
    print(word)
PY
      )
    fi

    if [[ "${#browser_command[@]}" -eq 0 ]]; then
      if split_command_words "$candidate"; then
        browser_command=("${split_command_words_result[@]}")
      else
        read -r -a browser_command <<<"$candidate"
      fi
    fi

    [[ "${#browser_command[@]}" -gt 0 ]] || continue
    if [[ "${browser_command[0]}" == */* ]]; then
      [[ -x "${browser_command[0]}" ]] && return 0
    else
      command -v -- "${browser_command[0]}" >/dev/null 2>&1 && return 0
    fi
  done

  browser_command=()
  return 1
}

browser_is_available() {
  resolve_browser_command
}

replace_browser_placeholder() {
  local word="$1"
  local target="$2"
  local output="" prefix rest

  rest="$word"
  while [[ "$rest" == *%s* ]]; do
    prefix="${rest%%\%s*}"
    output+="$prefix$target"
    rest="${rest#*%s}"
  done

  printf '%s\n' "$output$rest"
}

open_with_browser() {
  local target="$1"
  local arg replaced=0
  local -a command=()

  resolve_browser_command || return 1
  for arg in "${browser_command[@]}"; do
    if [[ "$arg" == *%s* ]]; then
      command+=("$(replace_browser_placeholder "$arg" "$target")")
      replaced=1
    else
      command+=("$arg")
    fi
  done

  if [[ "$replaced" == "1" ]]; then
    "${command[@]}" >/dev/null 2>&1 &
  else
    "${command[@]}" "$target" >/dev/null 2>&1 &
  fi
}

is_external_uri() {
  local value="$1"

  [[ "$value" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// || "$value" =~ ^mailto: ]]
}

strip_wrapping_location_quotes() {
  local value="$1" quote rest path suffix

  quote="${value:0:1}"
  if [[ "$quote" != "'" && "$quote" != '"' ]]; then
    printf '%s\n' "$value"
    return
  fi

  rest="${value:1}"
  path="${rest%%"$quote"*}"
  if [[ "$path" == "$rest" ]]; then
    printf '%s\n' "$value"
    return
  fi

  suffix="${rest#*"$quote"}"
  printf '%s%s\n' "$path" "$suffix"
}

editor_for_url() {
  local url="$1"

  case "$url" in
    vscode-insiders://*) printf '%s\n' "code-insiders" ;;
    cursor://*) printf '%s\n' "cursor" ;;
    windsurf://*) printf '%s\n' "windsurf" ;;
    vscode://*) printf '%s\n' "code" ;;
  esac
}

editor_is_available() {
  local editor="$1"

  [[ -n "$editor" ]] || return 1
  if [[ "$editor" == */* ]]; then
    [[ -x "$editor" ]]
  else
    command -v -- "$editor" >/dev/null 2>&1
  fi
}

resolve_editor_command() {
  local editor="$1" word

  editor_command=()
  [[ -n "$editor" ]] || return 1

  if [[ "$editor" == */* && -x "$editor" ]]; then
    editor_command=("$editor")
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r word; do
      editor_command+=("$word")
    done < <(
      EDITOR_VALUE="$editor" python3 - <<'PY' 2>/dev/null
import os
import shlex
import sys

try:
    words = shlex.split(os.environ["EDITOR_VALUE"])
except ValueError:
    sys.exit(1)

for word in words:
    print(word)
PY
    )
  fi

  if [[ "${#editor_command[@]}" -eq 0 ]]; then
    if split_command_words "$editor"; then
      editor_command=("${split_command_words_result[@]}")
    else
      read -r -a editor_command <<<"$editor"
    fi
  fi

  [[ "${#editor_command[@]}" -gt 0 ]] || return 1
  if [[ "${editor_command[0]}" == */* ]]; then
    [[ -x "${editor_command[0]}" ]]
  else
    command -v -- "${editor_command[0]}" >/dev/null 2>&1
  fi
}

open_with_editor() {
  local editor="$1"
  local target="$2"
  local has_line="$3"

  resolve_editor_command "$editor" || return 1
  if [[ "$has_line" == "1" ]]; then
    "${editor_command[@]}" -g "$target" && return 0
  else
    "${editor_command[@]}" "$target" && return 0
  fi
}

url_position_suffix() {
  local query="$1" fragment="$2" line="" column=""

  if [[ "$fragment" =~ ^L([0-9]+)(C([0-9]+))?(-L[0-9]+(C[0-9]+)?)?$ ]]; then
    line="${BASH_REMATCH[1]}"
    column="${BASH_REMATCH[3]:-}"
  elif [[ "$fragment" =~ ^L?([0-9]+)([:,-]?C?([0-9]+))?$ ]]; then
    line="${BASH_REMATCH[1]}"
    column="${BASH_REMATCH[3]:-}"
  fi

  if [[ -z "$line" && "$query" =~ (^|[&\;])line=([0-9]+) ]]; then
    line="${BASH_REMATCH[2]}"
  fi
  if [[ -z "$column" && "$query" =~ (^|[&\;])col=([0-9]+) ]]; then
    column="${BASH_REMATCH[2]}"
  elif [[ -z "$column" && "$query" =~ (^|[&\;])column=([0-9]+) ]]; then
    column="${BASH_REMATCH[2]}"
  fi

  if [[ -n "$line" ]]; then
    printf ':%s' "$line"
    [[ -n "$column" ]] && printf ':%s' "$column"
  fi
}

url_decode() {
  local value="$1" decoded="" char hex decoded_char index=0

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$value"
  else
    while ((index < ${#value})); do
      char="${value:index:1}"
      if [[ "$char" == "%" && "${value:index+1:2}" =~ ^[0-9A-Fa-f]{2}$ ]]; then
        hex="${value:index+1:2}"
        printf -v decoded_char '%b' "\\x$hex"
        decoded+="$decoded_char"
        index=$((index + 3))
      else
        decoded+="$char"
        index=$((index + 1))
      fi
    done
    printf '%s\n' "$decoded"
  fi
}

github_annotation_to_path() {
  local annotation="$1" props part key value
  local path="" line="" column=""

  case "$annotation" in
    "::debug "*::* | "::notice "*::* | "::warning "*::* | "::error "*::*) ;;
    *) return 1 ;;
  esac

  props="${annotation#::}"
  props="${props#* }"
  props="${props%%::*}"

  IFS=',' read -ra parts <<<"$props"
  for part in "${parts[@]}"; do
    [[ "$part" == *=* ]] || continue
    key="${part%%=*}"
    value="${part#*=}"
    key="${key//[[:space:]]/}"

    case "$key" in
      file)
        path="$(url_decode "$value")"
        ;;
      line | startLine)
        [[ -z "$line" ]] && line="$value"
        ;;
      col | column | startColumn)
        [[ -z "$column" ]] && column="$value"
        ;;
    esac
  done

  [[ -n "$path" && "$path" != *"://"* ]] || return 1

  if [[ "$line" =~ ^[0-9]+$ ]]; then
    printf '%s:%s' "$path" "$line"
    [[ "$column" =~ ^[0-9]+$ ]] && printf ':%s' "$column"
    printf '\n'
  else
    printf '%s\n' "$path"
  fi
}

location_from_diagnostic_line() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"

  if [[ "$value" =~ ^(error|warning|warn|note|fatal|panic):[[:space:]]+(.+)$ ]]; then
    value="${BASH_REMATCH[2]}"
  fi

  if [[ "$value" =~ ^--\>[[:space:]]+(.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^thread[[:space:]].*panicked[[:space:]]+at[[:space:]]+(.+:[0-9]+(:[0-9]+)?):?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^at[[:space:]].*\(((file|vscode|vscode-insiders|cursor|windsurf)://[^[:space:]]+)\)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^at[[:space:]]+((file|vscode|vscode-insiders|cursor|windsurf)://[^[:space:]]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^at[[:space:]].*\((.+:[0-9]+(:[0-9]+)?)\)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^at[[:space:]]+(.+:[0-9]+(:[0-9]+)?)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^File[[:space:]]+\"([^\"]+)\"\,?[[:space:]]+line[[:space:]]+([0-9]+) ]]; then
    printf '%s:%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$value" =~ ^((/|~|\./|\.\./|[A-Za-z0-9_.-]+/).*\.[A-Za-z0-9_+.-]{1,12}:[0-9]+(:[0-9]+)?)([[:space:]]|\+|$) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$value"
  fi
}

resolve_vscode_socket() {
  local current_socket="${VSCODE_IPC_HOOK_CLI:-}"

  if [[ -n "$current_socket" && -S "$current_socket" ]]; then
    if socket_can_be_probed; then
      socket_is_live "$current_socket" && return
    else
      return 0
    fi
  fi
  unset VSCODE_IPC_HOOK_CLI

  local socket socket_dir

  socket_can_be_probed || return 0

  socket_dir="${TMUX_OPEN_HELPER_VSCODE_SOCKET_DIR:-/run/user/$UID}"
  [[ -d "$socket_dir" ]] || return 0

  while IFS= read -r socket; do
    if socket_is_live "$socket"; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      return
    fi
  done < <(list_vscode_socket_candidates "$socket_dir")
}

resolve_vscode_browser() {
  browser_is_available && return
  local candidate helper="" server_root

  server_root="$HOME/.vscode-server/cli/servers"
  [[ -d "$server_root" ]] || return 0
  while IFS= read -r candidate; do
    [[ -n "$candidate" && -x "$candidate" ]] && helper="$candidate"
  done < <(list_vscode_browser_helpers "$server_root")
  [[ -n "$helper" ]] && export BROWSER="$helper"
  return 0
}

copy_or_fail() {
  local value="$1" label="$2"
  local helper=""

  if [[ -x "$bin_dir/osc-copy" ]]; then
    helper="$bin_dir/osc-copy"
  elif [[ -x "${HOME:-}/.local/bin/osc-copy" ]]; then
    helper="${HOME:-}/.local/bin/osc-copy"
  elif [[ -x "${HOME:-}/dotfiles/common/.local/bin/osc-copy" ]]; then
    helper="${HOME:-}/dotfiles/common/.local/bin/osc-copy"
  elif helper="$(command -v -- osc-copy 2>/dev/null)"; then
    :
  fi

  if [[ -n "$helper" ]]; then
    if ! printf '%s' "$value" | "$helper"; then
      echo "Error: failed to copy $label to clipboard" >&2
      display_tmux_message "Unable to copy $label to clipboard"
      exit 1
    fi
  elif ! is_ssh_session && [[ "$(uname -s)" == "Darwin" ]] && command -v pbcopy >/dev/null 2>&1; then
    if ! printf '%s' "$value" | pbcopy; then
      echo "Error: failed to copy $label to clipboard" >&2
      display_tmux_message "Unable to copy $label to clipboard"
      exit 1
    fi
  elif ! is_ssh_session && command -v wl-copy >/dev/null 2>&1; then
    if ! printf '%s' "$value" | wl-copy; then
      echo "Error: failed to copy $label to clipboard" >&2
      display_tmux_message "Unable to copy $label to clipboard"
      exit 1
    fi
  elif ! is_ssh_session && command -v xclip >/dev/null 2>&1; then
    if ! printf '%s' "$value" | xclip -selection clipboard; then
      echo "Error: failed to copy $label to clipboard" >&2
      display_tmux_message "Unable to copy $label to clipboard"
      exit 1
    fi
  else
    echo "Error: cannot open $label and no clipboard helper is available" >&2
    exit 1
  fi

  display_tmux_message "Copied $label to clipboard"
}

file_url_to_path() {
  local url="$1" path query="" fragment="" decoded suffix

  path="${url#file://}"
  if [[ "$path" == *#* ]]; then
    fragment="${path#*#}"
    path="${path%%#*}"
  fi
  if [[ "$path" == *\?* ]]; then
    query="${path#*\?}"
    path="${path%%\?*}"
  fi
  if [[ "$path" == localhost/* ]]; then
    path="/${path#localhost/}"
  fi

  [[ "$path" == /* ]] || return 1
  suffix="$(url_position_suffix "$query" "$fragment")"

  decoded="$(url_decode "$path")"
  printf '%s%s\n' "$decoded" "$suffix"
}

editor_file_url_to_path() {
  local url="$1" path query="" fragment="" decoded suffix

  [[ "$url" =~ ^(vscode|vscode-insiders|cursor|windsurf)://file/ ]] || return 1
  path="${url#*://file}"
  if [[ "$path" == *#* ]]; then
    fragment="${path#*#}"
    path="${path%%#*}"
  fi
  if [[ "$path" == *\?* ]]; then
    query="${path#*\?}"
    path="${path%%\?*}"
  fi
  while [[ "$path" == //* ]]; do
    path="/${path#//}"
  done
  [[ "$path" == /* ]] || return 1
  suffix="$(url_position_suffix "$query" "$fragment")"

  decoded="$(url_decode "$path")"
  printf '%s%s\n' "$decoded" "$suffix"
}

editor_remote_url_to_path() {
  local url="$1" remote path query="" fragment="" decoded suffix

  [[ "$url" =~ ^(vscode|vscode-insiders|cursor|windsurf)://vscode-remote/[^/]+/ ]] || return 1
  remote="${url#*://vscode-remote/}"
  path="/${remote#*/}"
  if [[ "$path" == *#* ]]; then
    fragment="${path#*#}"
    path="${path%%#*}"
  fi
  if [[ "$path" == *\?* ]]; then
    query="${path#*\?}"
    path="${path%%\?*}"
  fi
  [[ "$path" == /* && "$path" != "/" ]] || return 1
  suffix="$(url_position_suffix "$query" "$fragment")"

  decoded="$(url_decode "$path")"
  printf '%s%s\n' "$decoded" "$suffix"
}

normalize_path() {
  local raw="$1" base_dir dir base path

  case "$raw" in
    "~") raw="$HOME" ;;
    \~/*) raw="$HOME/${raw#\~/}" ;;
  esac

  if [[ "$raw" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s\n' "$raw"
    return
  fi
  if [[ "$raw" == \\\\* ]]; then
    printf '%s\n' "$raw"
    return
  fi

  if [[ "$raw" != /* ]]; then
    base_dir="${TMUX_FZF_URL_BASE_DIR:-$PWD}"
    raw="$base_dir/$raw"
  fi

  if command -v realpath >/dev/null 2>&1 && path="$(realpath "$raw" 2>/dev/null)"; then
    printf '%s\n' "$path"
    return
  fi

  if command -v grealpath >/dev/null 2>&1 && path="$(grealpath -m "$raw" 2>/dev/null)"; then
    printf '%s\n' "$path"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$raw"
    return
  fi

  if [[ "$raw" == */* ]]; then
    dir="${raw%/*}"
    base="${raw##*/}"
    [[ -n "$dir" ]] || dir="/"
  else
    dir="."
    base="$raw"
  fi

  if [[ -d "$dir" ]]; then
    (cd -- "$dir" && printf '%s/%s\n' "$PWD" "$base")
  elif [[ "$raw" = /* ]]; then
    printf '%s\n' "$raw"
  else
    printf '%s/%s\n' "$PWD" "$raw"
  fi
}

target="${1:?usage: tmux-open-helper.sh <url|path>}"
preferred_editor=""

if tmux_client_is_live; then
  TMUX_CLIENT_LIVE=1
fi

resolve_vscode_socket
resolve_vscode_browser

target="$(strip_wrapping_location_quotes "$target")"

if [[ "$target" =~ ^file:// ]]; then
  file_target="$target"
  if ! target="$(file_url_to_path "$file_target")"; then
    copy_or_fail "$file_target" file-url
  fi
fi

if [[ "$target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://file/ ]]; then
  editor_file_target="$target"
  preferred_editor="$(editor_for_url "$editor_file_target")"
  if ! target="$(editor_file_url_to_path "$editor_file_target")"; then
    copy_or_fail "$editor_file_target" editor-file-url
  fi
fi

if [[ "$target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://vscode-remote/[^/]+/ ]]; then
  editor_remote_target="$target"
  preferred_editor="$(editor_for_url "$editor_remote_target")"
  if ! target="$(editor_remote_url_to_path "$editor_remote_target")"; then
    copy_or_fail "$editor_remote_target" editor-remote-url
  fi
fi

if is_external_uri "$target"; then
  if open_with_browser "$target"; then
    :
  elif ! is_ssh_session && [[ "$(uname -s)" == "Darwin" ]] && command -v open >/dev/null 2>&1; then
    open "$target" >/dev/null 2>&1 &
  elif ! is_ssh_session && command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$target" >/dev/null 2>&1 &
  else
    copy_or_fail "$target" link
  fi
else
  path_target="$(location_from_diagnostic_line "$target")"
  line=""
  column=""

  if annotation_target="$(github_annotation_to_path "$path_target")"; then
    path_target="$annotation_target"
  fi

  if [[ "$path_target" =~ ^file:// ]]; then
    file_target="$path_target"
    if ! path_target="$(file_url_to_path "$file_target")"; then
      path_target="$file_target"
    fi
  elif [[ "$path_target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://file/ ]]; then
    editor_file_target="$path_target"
    preferred_editor="$(editor_for_url "$editor_file_target")"
    if ! path_target="$(editor_file_url_to_path "$editor_file_target")"; then
      path_target="$editor_file_target"
    fi
  elif [[ "$path_target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://vscode-remote/[^/]+/ ]]; then
    editor_remote_target="$path_target"
    preferred_editor="$(editor_for_url "$editor_remote_target")"
    if ! path_target="$(editor_remote_url_to_path "$editor_remote_target")"; then
      path_target="$editor_remote_target"
    fi
  fi

  if [[ "$path_target" =~ ^(.+):[[:space:]]+line[[:space:]]+([0-9]+)(:|[[:space:]]|$) ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  elif [[ "$path_target" =~ ^(.+)\|([0-9]+)([[:space:]]+col[[:space:]]+([0-9]+))?\| ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    column="${BASH_REMATCH[4]:-}"
  elif [[ "$path_target" =~ ^(.+)\(([0-9]+),([0-9]+)\): ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    column="${BASH_REMATCH[3]}"
  elif [[ "$path_target" =~ ^(.+)\(([0-9]+)\): ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  elif [[ "$path_target" =~ ^(.+)\(([0-9]+),([0-9]+)\)$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    column="${BASH_REMATCH[3]}"
  elif [[ "$path_target" =~ ^(.+)\(([0-9]+)\)$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi

  if [[ "$path_target" =~ ^(.+):([0-9]+):([0-9]+):[[:space:]].*$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    column="${BASH_REMATCH[3]}"
  elif [[ "$path_target" =~ ^(.+):([0-9]+):[[:space:]].*$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  elif [[ "$path_target" =~ ^(.+):([0-9]+)-[0-9]+$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  elif [[ "$path_target" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    column="${BASH_REMATCH[3]}"
  elif [[ "$path_target" =~ ^(.+):([0-9]+)$ ]]; then
    path_target="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi

  if [[ "$path_target" =~ ^(.+\.py)::.+$ ]]; then
    path_target="${BASH_REMATCH[1]}"
  fi

  path="$(normalize_path "$path_target")"
  open_target="$path"
  if [[ -n "$line" ]]; then
    open_target="${open_target}:${line}"
    [[ -n "$column" ]] && open_target="${open_target}:${column}"
  fi

  editor_candidates=()
  [[ -n "${TMUX_OPEN_EDITOR:-}" ]] && editor_candidates+=("$TMUX_OPEN_EDITOR")
  [[ -n "$preferred_editor" ]] && editor_candidates+=("$preferred_editor")
  editor_candidates+=(code code-insiders cursor windsurf)

  seen_editors=" "
  for editor in "${editor_candidates[@]}"; do
    [[ -n "$editor" ]] || continue
    if [[ "$seen_editors" == *" $editor "* ]]; then
      continue
    fi
    seen_editors="${seen_editors}${editor} "

    if [[ -n "$line" ]]; then
      open_with_editor "$editor" "$open_target" 1 && exit 0
    else
      open_with_editor "$editor" "$open_target" 0 && exit 0
    fi
  done

  if [[ -z "$line" ]]; then
    if ! is_ssh_session && [[ "$(uname -s)" == "Darwin" ]] && command -v open >/dev/null 2>&1; then
      open "$open_target" >/dev/null 2>&1 && exit 0
    elif ! is_ssh_session && command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$open_target" >/dev/null 2>&1 && exit 0
    fi
  fi

  copy_or_fail "$open_target" path
fi
