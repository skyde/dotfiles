# ~/.config/lf/pv.sh
#!/usr/bin/env bash
f="$1"
mime=$(file --mime-type -Lb "$f")

case "$mime" in
  text/*|application/json|application/xml)
    exec bat --color=always --paging=never --style=numbers,changes "$f"
    ;;
  *)  # fallback
    exec file -b "$f"
    ;;
esac
