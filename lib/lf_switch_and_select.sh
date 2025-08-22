#!/bin/bash

#!/bin/bash
# Script to launch/switch Ranger to current directory and preselect the current file
# Usage: Called from VS Code tasks with VSC_CWD and VSC_FILE environment variables

cd "${VSC_CWD:-${WORKSPACE:-$PWD}}" || exit 1

if command -v ranger >/dev/null 2>&1; then
    # If a ranger instance is running in the terminal, just start normally; --selectfile preserves UX
    if [ -n "$VSC_FILE" ] && [ -e "$VSC_FILE" ]; then
        exec ranger --selectfile="$VSC_FILE"
    else
        exec ranger
    fi
else
    echo "ranger is not installed. Install with: brew install ranger" >&2
    exit 127
fi
