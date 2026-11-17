# ==============================================================================
#  Quickshell Atelier - Zsh Aliases & Helper Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Navigation & Directory Listing (with eza support)
# ------------------------------------------------------------------------------
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -lh --icons --group-directories-first'
    alias la='eza -lah --icons --group-directories-first'
    alias lt='eza --tree --level=2 --icons'
    alias lta='eza --tree --level=3 -lah --icons'
else
    alias ls='ls --color=auto'
    alias ll='ls -lh --color=auto'
    alias la='ls -lah --color=auto'
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Quick directory creation + enter
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# ------------------------------------------------------------------------------
# Modern CLI Replacements
# ------------------------------------------------------------------------------
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never --style=plain'
    alias catp='bat'
fi

if command -v btop >/dev/null 2>&1; then
    alias top='btop'
fi

alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'

# ------------------------------------------------------------------------------
# Git Workflow Aliases
# ------------------------------------------------------------------------------
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull --rebase'
alias gst='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias glog='git log --graph --oneline --decorate --all'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gbr='git branch'

# ------------------------------------------------------------------------------
# Antigravity & AI Development
# ------------------------------------------------------------------------------
alias agy='antigravity'
alias agy-code='antigravity code'
alias agy-new='antigravity create'
alias agy-list='antigravity list'
alias agy-status='antigravity status'

# ------------------------------------------------------------------------------
# Python Development
# ------------------------------------------------------------------------------
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv .venv'
alias va='[ -f .venv/bin/activate ] && source .venv/bin/activate || ([ -f venv/bin/activate ] && source venv/bin/activate || echo "No .venv found. Run '\''venv'\'' first.")'
alias vd='deactivate'
alias req='pip install -r requirements.txt'
alias freeze='pip freeze > requirements.txt'
alias pyclean='find . -type d -name "__pycache__" -exec rm -rf {} +; find . -type f -name "*.pyc" -delete'
alias pytest='pytest -v'
alias ruff-fix='ruff check --fix . && ruff format .'

# ------------------------------------------------------------------------------
# React Native & Android Development
# ------------------------------------------------------------------------------
alias rn='npx react-native'
alias rns='npx react-native start --reset-cache'
alias rna='npx react-native run-android'
alias rni='npx react-native run-ios'
alias expo='npx expo'
alias expos='npx expo start -c'
alias expoa='npx expo run:android'

# Android ADB & Device Mirror (scrcpy)
alias adbl='adb devices -l'
alias adbr='adb reverse tcp:8081 tcp:8081 && echo "✓ Port 8081 reversed to Android device."'
alias adbkill='adb kill-server && adb start-server'
alias adblog='adb logcat -v color'
alias sc='scrcpy --stay-awake --turn-screen-off --show-touches'
alias scrcpy-rec='scrcpy --record screen_$(date +%s).mp4'
alias clean-android='cd android && ./gradlew clean && cd ..'

# ------------------------------------------------------------------------------
# iOS Device & Cloud Tools (Linux)
# ------------------------------------------------------------------------------
alias ios-devices='ideviceinfo -s'
alias ios-logs='idevicesyslog'
alias ios-install='ideviceinstaller -i'
alias eas-ios='npx eas-cli build --platform ios'
alias usbmuxd-restart='sudo systemctl restart usbmuxd'

# ------------------------------------------------------------------------------
# Lightweight Workspace, Editor & Terminal Tools
# ------------------------------------------------------------------------------
alias zed='zed'
alias zj='zellij'
alias y='yazi'
alias rg='ripgrep'

# ------------------------------------------------------------------------------
# Node.js & Package Managers
# ------------------------------------------------------------------------------
alias ni='npm install'
alias nr='npm run'
alias ns='npm start'
alias nb='npm run build'
alias nt='npm test'
alias yi='yarn install'
alias pi='pnpm install'
alias bi='bun install'
alias clean-modules='rm -rf node_modules package-lock.json pnpm-lock.yaml yarn.lock && npm install'

# ------------------------------------------------------------------------------
# Arch Linux / Package Management Shortcuts
# ------------------------------------------------------------------------------
if command -v yay >/dev/null 2>&1; then
    alias update='yay -Syu'
    alias in='yay -S'
    alias un='yay -Rns'
    alias search='yay -Ss'
    alias info='yay -Si'
    alias orphans='yay -Qdt'
    alias cleanorphans='yay -Rns $(yay -Qdtq)'
elif command -v pacman >/dev/null 2>&1; then
    alias update='sudo pacman -Syu'
    alias in='sudo pacman -S'
    alias un='sudo pacman -Rns'
    alias search='pacman -Ss'
    alias info='pacman -Si'
    alias orphans='pacman -Qdt'
    alias cleanorphans='sudo pacman -Rns $(pacman -Qdtq)'
fi

# ------------------------------------------------------------------------------
# Atelier Quickshell & Hyprland Controls
# ------------------------------------------------------------------------------
alias qs-reload='pkill quickshell; quickshell &'
alias qs-stop='pkill quickshell'
alias qs-logs='journalctl --user -u quickshell -f 2>/dev/null || quickshell'
alias hypr-reload='hyprctl reload'
alias hypr-logs='cat $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log'
alias theme='$HOME/.config/hypr/scripts/theme-switch.sh'
alias shot='$HOME/.config/hypr/scripts/screenshot.sh area'
alias shot-full='$HOME/.config/hypr/scripts/screenshot.sh full'
alias power='$HOME/.config/hypr/scripts/powermenu.sh'
alias clip='$HOME/.config/hypr/scripts/clipmanager.sh'
alias fetch='fastfetch'

# ------------------------------------------------------------------------------
# System, Network & Safety
# ------------------------------------------------------------------------------
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias df='df -h'
alias free='free -m'

# Find listening ports
alias ports='netstat -tulanp 2>/dev/null || ss -tulpn'

# Public & Local IP
alias myip='curl -s https://ipinfo.io/ip && echo'
alias localip='ip route get 1 | awk "{print \$7;exit}"'

# Top 5 memory / CPU consuming processes
alias mem5='ps aux --sort=-%mem | head -n 6'
alias cpu5='ps aux --sort=-%cpu | head -n 6'

# Reload Zsh configuration
alias zshreload='source ~/.zshrc && echo "⚡ ~/.zshrc reloaded!"'
