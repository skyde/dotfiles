# Install

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian bash -c 'apt update && apt install -y curl git && curl -fsSL get.chezmoi.io | bash -s -- init --apply skyde && exec bash'

```
