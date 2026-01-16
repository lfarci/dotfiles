FROM ubuntu:24.04

RUN apt-get update && apt-get install -y sudo

RUN useradd -m -s /bin/bash tester \
  && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester

COPY . /home/tester/dotfiles
RUN chown -R tester:tester /home/tester/dotfiles

USER tester
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
