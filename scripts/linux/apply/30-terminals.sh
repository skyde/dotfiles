#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
dry() { [ -n "${DOT_DRYRUN:-}" ]; }
echo "[linux-terminals]"
[ "$DOT_OS" = linux ] || exit 0

# wezterm via package manager if available
if ! has wezterm && ! dry; then
  if has apt-get; then
    if ! dpkg -s wezterm >/dev/null 2>&1; then
      sudo mkdir -p /usr/share/keyrings
      curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
      echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
      sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg
      sudo apt-get update -qq
      sudo apt-get install -y wezterm || true
    fi
  elif has dnf; then sudo dnf -y install wezterm || { sudo dnf -y copr enable wezfurlong/wezterm-nightly || true; sudo dnf -y install wezterm || sudo dnf -y install wezterm-nightly || true; }
  elif has pacman; then sudo pacman -S --noconfirm wezterm || true
  elif has flatpak; then flatpak install -y flathub org.wezfurlong.wezterm || true
  fi
fi

