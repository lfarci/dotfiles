# ~/.bashrc

# Load aliases
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi

# Bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi

# Powerline prompt
if [ -f /usr/share/powerline/bindings/bash/powerline.sh ]; then
  . /usr/share/powerline/bindings/bash/powerline.sh
fi
