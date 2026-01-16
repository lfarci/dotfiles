FROM ubuntu:24.04

ARG REPO_URL
ARG REPO_REF=main

RUN apt-get update && apt-get install -y sudo git ca-certificates

RUN useradd -m -s /bin/bash tester \
  && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester

USER tester
WORKDIR /home/tester

RUN git clone "$REPO_URL" dotfiles \
  && git -C dotfiles checkout "$REPO_REF"

WORKDIR /home/tester/dotfiles

RUN ./bootstrap.sh

RUN command -v git \
  && command -v curl \
  && command -v fzf \
  && command -v rg \
  && command -v powerline \
  && test -f /usr/share/bash-completion/bash_completion \
  && test -L "$HOME/.bashrc" \
  && test -L "$HOME/.bash_aliases"
