# Install

### Mac / Linux

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
```

### WSL Installation

```
wsl --install -d Debian; wsl -d Debian -- bash -lc "sudo sed -i 's/bookworm/trixie/g' /etc/apt/sources.list && sudo apt update && sudo apt full-upgrade -y"
```

### Windows (non WSL)

```ps
winget install twpayne.chezmoi
chezmoi init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian:testing bash -c 'apt update && apt install -y curl git && curl -fsSL get.chezmoi.io | bash -s -- init --apply skyde && exec bash'
```
