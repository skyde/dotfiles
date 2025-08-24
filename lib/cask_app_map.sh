#!/usr/bin/env bash
set -euo pipefail

# Echo two fields: system-wide /Applications path and user ~/Applications path
# If no mapping exists, echo empty strings for both.
cask_app_paths() {
    local cask="${1:-}"
    case "$cask" in
        fluor)
            echo "/Applications/Fluor.app" "$HOME/Applications/Fluor.app"
            ;;
        hammerspoon)
            echo "/Applications/Hammerspoon.app" "$HOME/Applications/Hammerspoon.app"
            ;;
        alt-tab)
            echo "/Applications/AltTab.app" "$HOME/Applications/AltTab.app"
            ;;
        betterdisplay)
            echo "/Applications/BetterDisplay.app" "$HOME/Applications/BetterDisplay.app"
            ;;
        kitty)
            echo "/Applications/kitty.app" "$HOME/Applications/kitty.app"
            ;;
        *)
            echo "" ""
            ;;
    esac
}


