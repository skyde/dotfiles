# Install

### Mac / Linux

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
```

### Windows


```ps
winget install twpayne.chezmoi
chezmoi init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian bash -c 'apt update && apt install -y curl git && curl -fsSL get.chezmoi.io | bash -s -- init --apply skyde && exec bash'

```

# CI

This repository uses GitHub Actions to run a dry-run `chezmoi apply` and `chezmoi doctor` on each push and pull request.

# Auto-update

These dotfiles automatically pull in the latest changes on each login. Both zsh and PowerShell profiles run `chezmoi update --init` so your environment stays current.
