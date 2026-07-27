# shellcheck shell=sh
# Tokyo Night Night for fzf. The orange pointer is the repository's cursor accent.
export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }\
  --info=inline-right \
  --ansi \
  --layout=reverse \
  --no-cycle \
  --border=none \
  --color=bg+:#283457 \
  --color=bg:#16161e \
  --color=border:#27a1b9 \
  --color=fg:#c0caf5 \
  --color=gutter:#16161e \
  --color=header:#ff9e64 \
  --color=hl+:#2ac3de \
  --color=hl:#2ac3de \
  --color=info:#545c7e \
  --color=marker:#9ece6a \
  --color=pointer:#ff5000 \
  --color=prompt:#7aa2f7 \
  --color=query:#c0caf5:regular \
  --color=scrollbar:#27a1b9 \
  --color=separator:#ff9e64 \
  --color=spinner:#bb9af7"
