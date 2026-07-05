#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]}"
bin_dir="."
if [[ "$script_source" == */* ]]; then
  bin_dir="${script_source%/*}"
fi
bin_dir="$(cd -- "$bin_dir" && pwd -P)"
extract="$bin_dir/tmux-fzf-url-helper.py"
open="$bin_dir/tmux-open-helper.sh"
preview="$bin_dir/tmux-fzf-url-preview.sh"
TMUX_CLIENT_LIVE=0

display_tmux_message() {
  local message="$1"

  if inside_tmux_client; then
    tmux_cmd display-message "$message" 2>/dev/null || printf '%s\n' "$message" >&2
  else
    printf '%s\n' "$message" >&2
  fi
}

current_tmux_pane_id() {
  local pane_id

  [[ -n "${TMUX:-}" ]] || return 1
  pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null)" || return 1
  [[ -n "$pane_id" ]] || return 1
  printf '%s\n' "$pane_id"
}

inside_tmux_client() {
  [[ "$TMUX_CLIENT_LIVE" == "1" ]]
}

tmux_cmd() {
  if [[ "$TMUX_CLIENT_LIVE" == "1" || -z "${TMUX:-}" ]]; then
    tmux "$@"
  else
    (unset TMUX; tmux "$@")
  fi
}

is_ssh_session() {
  [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]
}

copy_with_host_clipboard() {
  local value="$1"
  local attempted=0 os_name=""

  os_name="$(uname -s 2>/dev/null || true)"

  if [[ "$os_name" == "Darwin" ]] && command -v pbcopy >/dev/null 2>&1; then
    attempted=1
    printf '%s' "$value" | pbcopy && return 0
  fi

  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
    attempted=1
    printf '%s' "$value" | wl-copy && return 0
  fi

  if [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
    attempted=1
    printf '%s' "$value" | xclip -selection clipboard && return 0
  fi

  if [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then
    attempted=1
    printf '%s' "$value" | xsel --clipboard --input && return 0
  fi

  [[ "$attempted" == "1" ]] && return 2
  return 1
}

copy_candidate() {
  local value="$1"
  local helper="" status=0

  if [[ -x "$bin_dir/osc-copy" ]]; then
    helper="$bin_dir/osc-copy"
  elif [[ -n "${HOME:-}" && -x "$HOME/.local/bin/osc-copy" ]]; then
    helper="$HOME/.local/bin/osc-copy"
  elif [[ -n "${HOME:-}" && -x "$HOME/dotfiles/common/.local/bin/osc-copy" ]]; then
    helper="$HOME/dotfiles/common/.local/bin/osc-copy"
  elif helper="$(command -v -- osc-copy 2>/dev/null)"; then
    :
  fi

  if [[ -n "$helper" ]]; then
    if ! printf '%s' "$value" | "$helper"; then
      display_tmux_message "Unable to copy selection"
      return 1
    fi
  elif ! is_ssh_session; then
    if copy_with_host_clipboard "$value"; then
      :
    else
      status=$?
      if [[ "$status" == "2" ]]; then
        display_tmux_message "Unable to copy selection"
      else
        display_tmux_message "No clipboard helper available"
      fi
      return 1
    fi
  else
    display_tmux_message "No clipboard helper available"
    return 1
  fi

  display_tmux_message "Copied selection"
}

require_helper() {
  local helper_path="$1"
  local message="$2"

  if [[ -x "$helper_path" ]]; then
    return 0
  fi

  display_tmux_message "$message"
  return 1
}

is_candidate() {
  local value="$1"
  local candidate

  while IFS= read -r candidate || [[ -n "$candidate" ]]; do
    [[ "$candidate" == "$value" ]] && return 0
  done <<<"$candidates"

  return 1
}

fzf_supports() {
  local option="$1"

  fzf_help
  [[ "$__TMUX_FZF_URL_HELP_CACHE" == *"$option"* ]]
}

fzf_help() {
  if [[ -z "${__TMUX_FZF_URL_HELP_CACHE+x}" ]]; then
    __TMUX_FZF_URL_HELP_CACHE="$(fzf --help 2>/dev/null || true)"
  fi
}

fzf_supports_preview_threshold() {
  fzf_help
  [[ "$__TMUX_FZF_URL_HELP_CACHE" == *SIZE_THRESHOLD* ]]
}

tmux_supports_display_popup() {
  local command_name

  while IFS= read -r command_name; do
    [[ "$command_name" == display-popup* ]] && return 0
  done < <(tmux_cmd list-commands 2>/dev/null)

  return 1
}

script_path() {
  local source="${BASH_SOURCE[0]}"
  local source_dir source_base

  case "$source" in
    */*)
      source_dir="${source%/*}"
      source_base="${source##*/}"
      (cd -- "$source_dir" && printf '%s/%s\n' "$PWD" "$source_base")
      ;;
    *)
      if [[ -e "$source" ]]; then
        printf '%s/%s\n' "$PWD" "$source"
      else
        command -v -- "$source"
      fi
      ;;
  esac
}

line_count() {
  local value="$1"
  local line
  local count=0

  [[ -n "$value" ]] || {
    printf '0\n'
    return
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    count=$((count + 1))
  done <<<"$value"

  printf '%s\n' "$count"
}

run_in_tmux_popup() {
  local popup_target quoted_script quoted_target

  popup_target="${target_pane:-}"
  if [[ -z "$popup_target" ]]; then
    popup_target="$(current_tmux_pane_id || true)"
  fi
  [[ -n "$popup_target" ]] || return 1

  printf -v quoted_script '%q' "$(script_path)"
  printf -v quoted_target '%q' "$popup_target"
  tmux_cmd display-popup -E -w 80% -h 40% -T ' open ' \
    "TMUX_FZF_URL_POPUP=1 TMUX_FZF_URL_TARGET_PANE=$quoted_target $quoted_script"
}

inside_tmux=0
current_pane=""
if current_pane="$(current_tmux_pane_id)"; then
  inside_tmux=1
  TMUX_CLIENT_LIVE=1
fi

target_pane="${TMUX_FZF_URL_TARGET_PANE:-}"
if [[ -z "$target_pane" && "$inside_tmux" == "1" ]]; then
  target_pane="$current_pane"
fi

base_dir="${TMUX_FZF_URL_BASE_DIR:-}"
if [[ -z "$base_dir" && -n "$target_pane" ]]; then
  base_dir="$(tmux_cmd display-message -p -t "$target_pane" '#{pane_current_path}' 2>/dev/null || true)"
fi

if [[ "$inside_tmux" != "1" && -z "$target_pane" ]]; then
  display_tmux_message "tmux URL/path picker must be run inside tmux"
  exit 0
fi

history_lines="${TMUX_FZF_URL_HISTORY_LINES:-2000}"
if [[ ! "$history_lines" =~ ^[0-9]+$ || "$history_lines" == "0" ]]; then
  history_lines=2000
fi

capture_args=(-J -p -S "-$history_lines")
if [[ -n "$target_pane" ]]; then
  capture_args+=(-t "$target_pane")
fi

require_helper "$extract" "tmux URL extractor is unavailable" || exit 1
if ! pane_text="$(tmux_cmd capture-pane "${capture_args[@]}")"; then
  display_tmux_message "Unable to capture tmux pane"
  exit 0
fi

if ! candidates=$(printf '%s\n' "$pane_text" | "$extract"); then
  display_tmux_message "Unable to extract URLs or file paths"
  exit 1
fi

if [[ -z "$candidates" ]]; then
  display_tmux_message "No URLs or file paths found"
  exit 0
fi

if [[ "$(line_count "$candidates")" == "1" && -z "${TMUX_FZF_URL_ALWAYS_PICK:-}" ]]; then
  require_helper "$open" "tmux open helper is unavailable" || exit 1
  TMUX_FZF_URL_BASE_DIR="$base_dir" "$open" "$candidates"
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  display_tmux_message "fzf is required for tmux URL/path picker"
  exit 0
fi

require_helper "$preview" "tmux URL preview helper is unavailable" || exit 1
if [[ "$inside_tmux" == "1" && -z "${TMUX_FZF_URL_POPUP:-}" ]] && ! fzf_supports '--tmux'; then
  if tmux_supports_display_popup; then
    if ! run_in_tmux_popup; then
      display_tmux_message "Unable to open tmux URL/path popup"
      exit 1
    fi
  else
    display_tmux_message "fzf does not support --tmux and tmux popups are unavailable"
  fi
  exit 0
fi

printf -v quoted_preview '%q' "$preview"
printf -v quoted_base_dir '%q' "$base_dir"
preview_window="right:60%:wrap"
if fzf_supports_preview_threshold; then
  preview_window="right:60%:wrap,<100(down:45%:wrap)"
fi
fzf_header="enter open | ctrl-y copy | esc cancel"
if fzf_supports '--bind'; then
  fzf_header="enter open | ctrl-y copy | ctrl-/ toggle preview | esc cancel"
fi

  fzf_args=(
    --exit-0
    +m
    --prompt="Open> "
    --header="$fzf_header"
    --expect=ctrl-y
    --preview="TMUX_FZF_URL_BASE_DIR=$quoted_base_dir $quoted_preview {}"
    --preview-window="$preview_window"
  )
if fzf_supports '--print-query'; then
  fzf_args+=(--print-query)
fi
if fzf_supports '--bind'; then
  fzf_args+=(--bind='ctrl-/:toggle-preview')
fi
if [[ "$inside_tmux" == "1" && -z "${TMUX_FZF_URL_POPUP:-}" ]] && fzf_supports '--tmux'; then
  fzf_args+=(--tmux 'center,80%,40%')
fi

set +e
selection=$(printf '%s\n' "$candidates" | fzf "${fzf_args[@]}")
fzf_status=$?
set -e
if [[ "$fzf_status" -ne 0 ]]; then
  exit 0
fi
key=""
chosen=""
query=""

while IFS= read -r line; do
  case "$line" in
    ctrl-y)
      key="ctrl-y"
      ;;
    "" | enter) ;;
    *)
      if is_candidate "$line"; then
        chosen="$line"
      elif [[ -z "$query" ]]; then
        query="$line"
      fi
      ;;
  esac
done <<<"$selection"

if [[ -z "$chosen" && -n "$query" ]]; then
  chosen="$query"
fi

if [[ -z "$chosen" ]]; then
  exit 0
fi

if [[ "$key" == "ctrl-y" ]]; then
  copy_candidate "$chosen" || exit 0
else
  require_helper "$open" "tmux open helper is unavailable" || exit 1
  TMUX_FZF_URL_BASE_DIR="$base_dir" "$open" "$chosen"
fi
