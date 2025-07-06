# Install

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian:latest bash -c "apt-get update && apt-get install -y curl git && sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- init --apply skyde && bash"
```
