#!/bin/bash

# Script to open LF file manager
# Usage: Called from VS Code tasks with VSC_FILE environment variable

# If a file is provided, open LF in the file's directory and select it
if [ -n "$VSC_FILE" ]; then
    # Get the directory containing the file
    file_dir=$(dirname "$VSC_FILE")
    
    # Start LF in the file's directory
    cd "$file_dir" || exit 1
    lf "$VSC_FILE"
else
    # If no file provided, just open LF in current directory
    lf
fi
