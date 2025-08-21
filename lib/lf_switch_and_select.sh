#!/bin/bash

# Script to switch LF to current directory and select the current file
# Usage: Called from VS Code tasks with VSC_CWD and VSC_FILE environment variables

# Navigate LF to the current directory
echo "send cd \"${VSC_CWD:-${WORKSPACE:-$PWD}}\""
lf -remote "send cd \"${VSC_CWD:-${WORKSPACE:-$PWD}}\""

# Select the current file (basename only since we're already in the directory)
if [ -n "$VSC_FILE" ]; then
    echo "send select \"$(basename "$VSC_FILE")\""
    lf -remote "send select \"$(basename "$VSC_FILE")\""
fi
