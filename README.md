# Install

### Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply skyde
```

### Linux

```
sudo apt-get update -qq && sudo apt-get install -y curl && \
mkdir -p ~/.local/bin && \
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && export PATH="$HOME/.local/bin:$PATH" && \
curl -fsSL get.chezmoi.io | BINDIR="$HOME/.local/bin" bash -s -- init --apply skyde
```

### Windows

```ps
winget install twpayne.chezmoi
chezmoi init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian:testing bash -c 'apt update && apt install -y curl git && curl -fsSL get.chezmoi.io | bash -s -- init --apply skyde && exec bash'
```

### WSL Installation

```ps
wsl --install -d Debian && wsl --set-default Debian && wsl -d Debian -- bash -lc 'sudo sed -i "s/bookworm/trixie/g" /etc/apt/sources.list && sudo apt update && sudo apt full-upgrade -y && curl -fsLS get.chezmoi.io | bash -s -- init --apply skyde'
```
