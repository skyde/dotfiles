#!/bin/bash

# Script to open Ranger file manager (replacing LF)
# Usage: Called from VS Code tasks with VSC_FILE environment variable

# If a file is provided, open LF in the file's directory and select it
if [ -n "$VSC_FILE" ]; then
    # Get the directory containing the file
    file_dir=$(dirname "$VSC_FILE")
    
    # Start Ranger in the file's directory and select the file
    cd "$file_dir" || exit 1
    if command -v ranger >/dev/null 2>&1; then
        ranger --selectfile="$VSC_FILE"
    else
        echo "ranger is not installed. Install with: brew install ranger" >&2
        exit 127
    fi
else
    # If no file provided, just open Ranger in current directory
    if command -v ranger >/dev/null 2>&1; then
        ranger
    else
        echo "ranger is not installed. Install with: brew install ranger" >&2
        exit 127
    fi
fi
