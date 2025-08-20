# FZF look & feel similar to LazyVim's dropdown
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --layout=reverse
  --border=rounded
  --height=60%
  --info=inline
  --margin=1,3
  --no-separator
  --pointer='❯'
  --marker='✓'
  --ansi
  --bind=ctrl-j:down,ctrl-k:up,alt-j:down,alt-k:up,ctrl-u:half-page-up,ctrl-d:half-page-down,alt-p:toggle-preview
  --color=fg:#c0caf5,bg:#1a1b26,hl:#7aa2f7,fg+:#c0caf5,bg+:#24283b,hl+:#7aa2f7,info:#7aa2f7,prompt:#7dcfff,pointer:#ff9e64,marker:#9ece6a,spinner:#bb9af7,header:#565f89,border:#3b4261
"
