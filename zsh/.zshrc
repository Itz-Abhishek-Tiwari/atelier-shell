# ~/.zshrc — quickshell-atelier
# Plain zsh + starship (oh-my-zsh is not installed, so it is no longer loaded).
# Colours for syntax highlighting / suggestions / fzf / bat follow the system theme
# (~/.config/atelier/theme.zsh, written by `atelier-theme apply <id>`).

### --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_VERIFY

### --- Options ---
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS NO_BEEP CORRECT
setopt EXTENDED_GLOB GLOB_DOTS

### --- Completion (cached; rebuilt at most once a day) ---
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then compinit; else compinit -C; fi
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'   # case-insensitive, fuzzy-ish
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{8}-- %d --%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh/compcache

### --- Key bindings ---
bindkey -e
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search      # Up: history matching what you've typed
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[1;5C' forward-word                   # Ctrl+Right
bindkey '^[[1;5D' backward-word                  # Ctrl+Left
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

### --- Editor ---
[[ -n $SSH_CONNECTION ]] && export EDITOR='vim' || export EDITOR='nvim'

### --- Environment Variables ---
export NODE_ENV=development
export QT_STYLE_OVERRIDE=qt5ct
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export ANDROID_HOME=$HOME/Android/Sdk
export GOPATH=${GOPATH:-$HOME/go}            # was `$(go env GOPATH)`, which ran go on every shell start
typeset -U path                               # no duplicate PATH entries
path=(./node_modules/.bin $HOME/.local/bin $JAVA_HOME/bin
      $ANDROID_HOME/platform-tools $ANDROID_HOME/cmdline-tools/latest/bin $ANDROID_HOME/emulator
      $path $GOPATH/bin)

### --- Theme colours (syntax highlighting, suggestions, fzf, bat) ---
[[ -r ~/.config/atelier/theme.zsh ]] && source ~/.config/atelier/theme.zsh
: ${BAT_THEME:="Catppuccin Mocha"}; export BAT_THEME

### --- Plugins (system packages) ---
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh   # Ctrl+R, Ctrl+T, Alt+C
[[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh

### --- Prompt & tools ---
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"     # `z <dir>` jumps to frequent dirs
command -v rbenv    >/dev/null && eval "$(rbenv init -)"

### --- Safety Aliases ---
alias rm="rm -i"
alias cp="cp -i"
alias mv="mv -i"

### --- Git Shortcuts ---
alias gs="git status"
alias gp="git push"
alias gl="git pull"
alias ga="git add"
alias gc="git commit"
alias gd="git diff"
alias glog="git log --oneline --graph --decorate -20"

### --- NPM/Yarn Shortcuts ---
alias serve="npx serve"
alias start="npm start"
alias test="npm test"
alias lint="npm run lint"
alias dev="npm run dev"
alias py="python3"
alias pipi="pip install"

### --- Directory Shortcuts ---
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias c='clear'

### --- Listing Aliases (Eza) ---
alias ls="eza --icons=always --group-directories-first --color=always"
alias ll="eza -lah --icons=always"
alias la="eza -a --icons=always"
alias l="eza -CF --icons=always"

### --- Network Tools ---
alias ping="ping -c 5"
alias myip="curl ifconfig.me"
alias ports="sudo lsof -i -P -n | grep LISTEN"

### --- Pacman Shortcuts ---
alias update="sudo pacman -Syu"
alias upgrade="sudo pacman -Syu"
alias install="sudo pacman -S"
alias remove="sudo pacman -Rns"
alias search="pacman -Ss"
alias files="pacman -Ql"
alias info="pacman -Si"

### --- Yay Shortcuts ---
alias ya="yay"
alias yau="yay -Syu"
alias yai="yay -S"
alias yar="yay -Rns"
alias yas="yay -Ss"

### --- System Info & Cleanup ---
# single quotes: the $(pacman ...) parts now run when you use the alias, not at every shell start
alias orphan="pacman -Qdt"
alias remove-orphan='sudo pacman -Rns $(pacman -Qdtq)'
alias foreign="pacman -Qm"
alias explicit="pacman -Qe"
alias bigpkgs='pacman -Qq | xargs pacman -Qi | awk "/^Name/ {name=\$3} /^Installed Size/ {print \$4, \$5, name}" | sort -h | tail -20'
alias badpkg="pacman -Qk"
alias paccheck='paccache -r && sudo pacman -D --asdeps $(pacman -Qdtq) && sudo pacman -Qk'

### --- System Control ---
alias reboot="sudo systemctl reboot"
alias poweroff="sudo systemctl poweroff"
alias suspend="systemctl suspend"

### --- Disk Usage ---
alias dfh="df -h"
alias duh="du -h --max-depth=1"

### --- Theme ---
alias theme="atelier-theme"                    # theme list | theme apply tokyo-night | theme toggle-mode

### --- Syntax highlighting must be sourced last ---
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
