umask 077
export PATH="$HOME/.local/bin:$HOME/.local/share/dev-tools/node/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
export EDITOR=vim
export STARSHIP_CONFIG="$HOME/.config/dev-terminal/starship.toml"
HISTFILE="$HOME/.local/state/dev-terminal/history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_SPACE HIST_IGNORE_ALL_DUPS SHARE_HISTORY AUTO_CD INTERACTIVE_COMMENTS
bindkey -e
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
autoload -Uz compinit
compinit -d "$HOME/.local/state/dev-terminal/zcompdump"
zstyle ':completion:*' menu select
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline -15'
alias sessions='dev'
[[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
eval "$("$HOME/.local/share/dev-tools/starship-bin/starship" init zsh)"
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
