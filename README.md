# Install

### Mac

```sh
sudo apt update
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
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

```
wsl --install -d Debian; wsl -d Debian -- bash -lc "sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list && sudo apt update && sudo apt full-upgrade -y"
wsl --set-default Debian
```
