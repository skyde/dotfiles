# Install

Use a single chezmoi command to install the config.

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
```

# Linux Container

You can try running the config in a container (in progress).

```sh
docker run --rm -it debian:latest bash -c "apt-get update && apt-get install -y curl git && sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- init --apply skyde && bash"
```
