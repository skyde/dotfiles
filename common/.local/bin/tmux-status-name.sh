#!/bin/bash

# Get the current path and command from arguments
current_path="$1"
current_command="$2"

workspace=""

if [[ "$current_path" =~ ^/google/src/cloud/[^/]+/([^/]+) ]]; then
  workspace="${BASH_REMATCH[1]}"
fi

# 2. Detect Git workspace
if [ -z "$workspace" ]; then
  git_dir=$(git -C "$current_path" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_dir" ]; then
    workspace=$(basename "$git_dir")
  fi
fi

# 3. Fallback to current directory name
if [ -z "$workspace" ]; then
  workspace=$(basename "$current_path")
fi

# Process command
cmd="$current_command"
# Ignore common shells
if [[ "$cmd" =~ ^(bash|zsh|fish)$ ]]; then
  cmd=""
fi

# Output the result
if [ -n "$cmd" ]; then
  echo "${workspace}:${cmd}"
else
  echo "${workspace}"
fi
