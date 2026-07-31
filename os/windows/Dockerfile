FROM ubuntu:24.04

ARG REPO_URL
ARG REPO_REF=main

# Force the Windows/WSL code path in bootstrap.sh
ENV DOTFILES_OS=windows

RUN apt-get update && apt-get install -y sudo git ca-certificates

COPY tests/fixtures/code-stub.bash /usr/local/bin/code
RUN chmod +x /usr/local/bin/code

ENV DOTFILES_CODE_LOG=/tmp/vscode-extension-installs.log

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
  && test -f /usr/share/bash-completion/bash_completion \
  && test -L "$HOME/.bashrc" \
  && test -L "$HOME/.bash_aliases" \
  && test "$(wc -l < "$DOTFILES_CODE_LOG")" -eq 9 \
  && grep -Fqx -- "--install-extension catppuccin.catppuccin-vsc --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension catppuccin.catppuccin-vsc-icons --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension PKief.material-icon-theme --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension ms-dotnettools.csharp --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension stackbreak.comment-divider --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension github.vscode-github-actions --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension github.vscode-pull-request-github --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension codezombiech.gitignore --force" "$DOTFILES_CODE_LOG" \
  && grep -Fqx -- "--install-extension mermaidchart.vscode-mermaid-chart --force" "$DOTFILES_CODE_LOG"
