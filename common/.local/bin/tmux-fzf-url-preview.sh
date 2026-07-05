#!/usr/bin/env bash
set -euo pipefail

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

is_external_uri() {
  local value="$1"

  [[ "$value" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// || "$value" =~ ^mailto: ]]
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
  local raw="$1" base_dir path

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

  printf '%s\n' "$raw"
}

preview_with_shell() {
  local path="$1" line="$2" start end
  local number=0 text marker

  if [[ -n "$line" ]]; then
    start=$((line > 8 ? line - 8 : 1))
    end=$((line + 8))
  else
    start=1
    end=120
  fi

  while IFS= read -r text || [[ -n "$text" ]]; do
    number=$((number + 1))
    ((number < start)) && continue
    ((number > end)) && break
    marker=" "
    [[ "$number" == "${line:-0}" ]] && marker=">"
    printf '%s%6d  %s\n' "$marker" "$number" "$text"
  done <"$path"
}

preview_with_awk() {
  local path="$1" line="$2" start end

  if ! command -v awk >/dev/null 2>&1; then
    preview_with_shell "$path" "$line"
    return
  fi

  if [[ -n "$line" ]]; then
    start=$((line > 8 ? line - 8 : 1))
    end=$((line + 8))
  else
    start=1
    end=120
  fi

  awk -v start="$start" -v end="$end" -v selected="${line:-0}" '
    NR < start { next }
    NR > end { exit }
    {
      marker = (NR == selected) ? ">" : " "
      printf "%s%6d  %s\n", marker, NR, $0
    }
  ' "$path"
}

preview_file() {
  local path="$1" line="$2" bat_cmd start end

  if command -v bat >/dev/null 2>&1; then
    bat_cmd="bat"
  elif command -v batcat >/dev/null 2>&1; then
    bat_cmd="batcat"
  else
    bat_cmd=""
  fi

  if [[ -n "$bat_cmd" ]]; then
    if [[ -n "$line" ]]; then
      start=$((line > 8 ? line - 8 : 1))
      end=$((line + 8))
      "$bat_cmd" --color=always --style=numbers --line-range "${start}:${end}" --highlight-line "$line" "$path" \
        || preview_with_awk "$path" "$line"
    else
      "$bat_cmd" --color=always --style=numbers --line-range ":120" "$path" || preview_with_awk "$path" "$line"
    fi
  else
    preview_with_awk "$path" "$line"
  fi
}

limit_lines() {
  local max="$1" count=0 line

  while IFS= read -r line; do
    [[ "$count" -lt "$max" ]] || break
    printf '%s\n' "$line"
    count=$((count + 1))
  done
}

list_directory_paths() {
  local path="$1" entry nullglob_was_set=0 dotglob_was_set=0

  if command -v find >/dev/null 2>&1; then
    find "$path" -maxdepth 1 -mindepth 1 -print 2>/dev/null || true
    return
  fi

  shopt -q nullglob && nullglob_was_set=1
  shopt -q dotglob && dotglob_was_set=1
  shopt -s nullglob dotglob
  for entry in "$path"/*; do
    printf '%s\n' "$entry"
  done
  if [[ "$nullglob_was_set" == "0" ]]; then
    shopt -u nullglob
  fi
  if [[ "$dotglob_was_set" == "0" ]]; then
    shopt -u dotglob
  fi
}

print_directory_entry_names() {
  local path="$1" prefix line

  prefix="$path/"
  while IFS= read -r line; do
    if [[ "$line" == "$prefix"* ]]; then
      printf '%s\n' "${line#"$prefix"}"
    else
      printf '%s\n' "$line"
    fi
  done
}

preview_directory() {
  local path="$1"

  printf '%s/\n\n' "$path"
  if command -v sort >/dev/null 2>&1; then
    list_directory_paths "$path" | print_directory_entry_names "$path" | sort | limit_lines 120 || true
  else
    list_directory_paths "$path" | print_directory_entry_names "$path" | limit_lines 120 || true
  fi
}

target="${1:-}"
if [[ -z "$target" ]]; then
  exit 0
fi

if [[ "$target" =~ ^file:// ]]; then
  file_target="$target"
  if ! target="$(file_url_to_path "$file_target")"; then
    printf '%s\n' "$file_target"
    exit 0
  fi
fi

if [[ "$target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://file/ ]]; then
  editor_file_target="$target"
  if ! target="$(editor_file_url_to_path "$editor_file_target")"; then
    printf '%s\n' "$editor_file_target"
    exit 0
  fi
fi

if [[ "$target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://vscode-remote/[^/]+/ ]]; then
  editor_remote_target="$target"
  if ! target="$(editor_remote_url_to_path "$editor_remote_target")"; then
    printf '%s\n' "$editor_remote_target"
    exit 0
  fi
fi

if is_external_uri "$target"; then
  printf '%s\n' "$target"
  exit 0
fi

path_target="$(location_from_diagnostic_line "$target")"
line=""

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
  if ! path_target="$(editor_file_url_to_path "$editor_file_target")"; then
    path_target="$editor_file_target"
  fi
elif [[ "$path_target" =~ ^(vscode|vscode-insiders|cursor|windsurf)://vscode-remote/[^/]+/ ]]; then
  editor_remote_target="$path_target"
  if ! path_target="$(editor_remote_url_to_path "$editor_remote_target")"; then
    path_target="$editor_remote_target"
  fi
fi

if [[ "$path_target" =~ ^(.+):[[:space:]]+line[[:space:]]+([0-9]+)(:|[[:space:]]|$) ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+)\|([0-9]+)([[:space:]]+col[[:space:]]+[0-9]+)?\| ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+)\(([0-9]+),([0-9]+)\): ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+)\(([0-9]+)\): ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+)\(([0-9]+),([0-9]+)\)$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+)\(([0-9]+)\)$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
fi

if [[ "$path_target" =~ ^(.+):([0-9]+):[0-9]+:[[:space:]].*$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+):([0-9]+):[[:space:]].*$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+):([0-9]+)-[0-9]+$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
elif [[ "$path_target" =~ ^(.+):([0-9]+)$ ]]; then
  path_target="${BASH_REMATCH[1]}"
  line="${BASH_REMATCH[2]}"
fi

if [[ "$path_target" =~ ^(.+\.py)::.+$ ]]; then
  path_target="${BASH_REMATCH[1]}"
fi

path="$(normalize_path "$path_target")"

if [[ -d "$path" ]]; then
  preview_directory "$path"
elif [[ -f "$path" ]]; then
  printf '%s\n\n' "$path"
  preview_file "$path" "$line"
else
  printf 'No preview available:\n%s\n' "$target"
fi
