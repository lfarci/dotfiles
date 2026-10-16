FROM ubuntu:24.04

ARG REPO_URL
ARG REPO_REF=main

RUN apt-get update && apt-get install -y sudo git ca-certificates python3

RUN useradd -m -s /bin/bash tester \
  && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester

USER tester
WORKDIR /home/tester

RUN git clone "$REPO_URL" dotfiles \
  && git -C dotfiles checkout "$REPO_REF"

WORKDIR /home/tester/dotfiles

# Drive the real scripts/update.sh and scripts/cleanup.sh end to end against
# throwaway HOME directories and local git remotes, then run the real
# bootstrap.sh (network: packages/CLIs) to create genuine backups for the
# cleanup scenario. This is why the job lives in the weekly/manual Docker home.
RUN python3 tests/e2e/run_update_cleanup.py --real-bootstrap
