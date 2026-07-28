FROM debian:testing-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    clang \
    clangd \
    cmake \
    curl \
    expect \
    fd-find \
    file \
    gdb \
    git \
    jq \
    lldb \
    locales \
    lua5.1 \
    luarocks \
    neovim \
    ninja-build \
    nodejs \
    npm \
    openssh-client \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    sqlite3 \
    stow \
    sudo \
    time \
    tini \
    tmux \
    unzip \
    xz-utils \
    zsh \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt-get update \
  && apt-get install -y --no-install-recommends rust-analyzer \
  && rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/fdfind /usr/local/bin/fd \
  && useradd --create-home --shell /bin/bash tester \
  && printf 'tester ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/tester \
  && chmod 0440 /etc/sudoers.d/tester

ARG TREE_SITTER_CLI_VERSION=0.26.11
RUN npm install --global "tree-sitter-cli@${TREE_SITTER_CLI_VERSION}" \
  && tree-sitter --version

ARG TARGETARCH
ARG JJ_VERSION=0.43.0
ARG JJ_AMD64_SHA256=59e5588583ac82b623239929368c65b90735931c0f26b5a16c1f04d5bb97643d
ARG JJ_ARM64_SHA256=289197b6bec60b4e57d47260624b617716f737eb02cdfd9155791b2576aa5862
RUN target_arch=${TARGETARCH:-$(dpkg --print-architecture)} \
  && case "$target_arch" in \
    amd64) jj_arch=x86_64; jj_sha256=$JJ_AMD64_SHA256 ;; \
    arm64) jj_arch=aarch64; jj_sha256=$JJ_ARM64_SHA256 ;; \
    *) printf 'unsupported jj architecture: %s\n' "$target_arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL \
      "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-${jj_arch}-unknown-linux-musl.tar.gz" \
      -o /tmp/jj.tar.gz \
  && echo "${jj_sha256}  /tmp/jj.tar.gz" | sha256sum --check --strict \
  && tar -xzf /tmp/jj.tar.gz -C /usr/local/bin ./jj \
  && chmod 0755 /usr/local/bin/jj

ARG P4_RELEASE=r25.2
ARG P4_AMD64_SHA256=ba4b931bd37a1fd073785c3194a608906934f62b52d407178121a8184bee8ae6
ARG P4D_AMD64_SHA256=fd8d8833bc8a1975d829ccee7741ab5e5593f30ac3d6777a7bf247176753e0e1
ARG P4_ARM64_SHA256=a67bcae67dd810fdc099525289457ab6af6f647f6e3aceadc0260f42d19cbc93
ARG P4D_ARM64_SHA256=faffaf2d1bdf3d963e20c67f1d3c05049e3d382216a216d39fb00537c9967a14
RUN target_arch=${TARGETARCH:-$(dpkg --print-architecture)} \
  && case "$target_arch" in \
    amd64) \
      p4_platform=linux26x86_64; \
      p4_sha256=$P4_AMD64_SHA256; \
      p4d_sha256=$P4D_AMD64_SHA256 \
      ;; \
    arm64) \
      p4_platform=linux26aarch64; \
      p4_sha256=$P4_ARM64_SHA256; \
      p4d_sha256=$P4D_ARM64_SHA256 \
      ;; \
    *) printf 'unsupported Perforce architecture: %s\n' "$target_arch" >&2; exit 1 ;; \
  esac \
  && curl -fsSL \
      "https://cdist2.perforce.com/perforce/${P4_RELEASE}/bin.${p4_platform}/p4" \
      -o /usr/local/bin/p4 \
  && curl -fsSL \
      "https://cdist2.perforce.com/perforce/${P4_RELEASE}/bin.${p4_platform}/p4d" \
      -o /usr/local/bin/p4d \
  && echo "${p4_sha256}  /usr/local/bin/p4" | sha256sum --check --strict \
  && echo "${p4d_sha256}  /usr/local/bin/p4d" | sha256sum --check --strict \
  && chmod 0755 /usr/local/bin/p4 /usr/local/bin/p4d

USER tester
WORKDIR /home/tester

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash"]
