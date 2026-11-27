#!/usr/bin/env bash
# ==============================================================================
#  Quickshell Atelier - Dotfiles Installer
#
#  Usage:  ./install.sh [--dotfiles-only] [--no-greeter] [--dry-run] [--help]
#
#    --dotfiles-only, -d, --skip-pkgs   only the user side: links, seeds, themes, plugins
#                                       (no pacman/AUR, no /etc files, no services, no sudo)
#    --no-greeter                       don't install/enable the Quickshell login screen
#    --dry-run, -n                      print what would happen, change nothing
#
#  This folder is the source of truth. Copy it anywhere (keep hypr/wall/ for the
#  wallpapers), run ./install.sh, reboot - and the machine matches this one.
#
#  What it does, in order:
#    system   enable [multilib], install packages (+ GPU drivers by detected hardware,
#             + headers for every installed kernel), copy system/etc/* into /etc
#             (camera v4l2loopback, ntsync, zram, NVIDIA), enable services
#    user     symlink every config in LINKS into this repo, copy setup/seed/ files once
#             (files apps rewrite themselves), unpack GTK themes, build the qt6ct
#             plugin, install VS Code extensions, apply the current Atelier theme
#    greeter  greeter/install.sh --enable (greetd + the Quickshell login screen)
#
#  Strategy: every config is a symlink from ~/.config/... into this repo, so
#  editing either side edits the same file. Anything already at a target is
#  moved to ~/.config/atelier-backups/backup_<timestamp>/ first (never deleted).
#  Re-running is safe: links that already point here are left alone.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"

SKIP_PKGS=false
DRY_RUN=false
GREETER=true
for arg in "$@"; do
    case "$arg" in
        --skip-pkgs|--dotfiles-only|-d) SKIP_PKGS=true ;;
        --no-greeter) GREETER=false ;;
        --dry-run|-n) DRY_RUN=true ;;
        -h|--help) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
    esac
done

C_RESET="\033[0m"; C_BOLD="\033[1m"; C_CYAN="\033[36m"; C_GREEN="\033[32m"
C_YELLOW="\033[33m"; C_RED="\033[31m"; C_MAGENTA="\033[35m"

log_info()    { echo -e "${C_CYAN}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }
run()         { if $DRY_RUN; then echo -e "${C_MAGENTA}[dry-run]${C_RESET} $*"; else "$@"; fi; }

# repo path (relative to this script)  ->  link location
# Each pair becomes:  <link location>  ->  <repo path>
LINKS=(
    # the desktop
    "quickshell:$CONF/quickshell"
    "hypr:$CONF/hypr"
    "theming/atelier-theme:$BIN/atelier-theme"
    # config/<name> -> ~/.config/<name>
    "config/kitty:$CONF/kitty"
    "config/ghostty:$CONF/ghostty"
    "config/nvim:$CONF/nvim"                       # NamiConfig (Neovim)
    "config/fastfetch:$CONF/fastfetch"
    "config/zellij:$CONF/zellij"
    "config/zed:$CONF/zed"
    "config/gtk-3.0:$CONF/gtk-3.0"
    "config/gtk-4.0:$CONF/gtk-4.0"
    "config/qt5ct:$CONF/qt5ct"
    "config/qt6ct:$CONF/qt6ct"
    "config/Kvantum:$CONF/Kvantum"
    "config/btop:$CONF/btop"
    "config/cava:$CONF/cava"
    "config/swappy:$CONF/swappy"
    "config/zathura:$CONF/zathura"
    "config/environment.d:$CONF/environment.d"     # QT_QPA_PLATFORMTHEME=qt6ct for every app
    "config/vesktop/settings:$CONF/vesktop/settings"   # Vencord plugins + quick CSS
    "config/scripts:$CONF/scripts"
    "config/starship.toml:$CONF/starship.toml"
    "config/zsh:$CONF/zsh"
    "config/zsh/.zshrc:$HOME/.zshrc"
    # local/<path> -> ~/.local/<path>
    "local/bin/prime-run:$BIN/prime-run"
    "local/bin/audiotube:$BIN/audiotube"
    "local/bin/atelier-music:$BIN/atelier-music"   # YouTube Music app (apps/music)
    "config/scripts/adguard-dns.sh:$BIN/adguard-dns"
    "local/share/kio/servicemenus/atelier-airdrop.desktop:$HOME/.local/share/kio/servicemenus/atelier-airdrop.desktop"   # Dolphin: Send with AirDrop
    "local/share/nautilus-python/extensions/atelier-open-terminal.py:$HOME/.local/share/nautilus-python/extensions/atelier-open-terminal.py"   # Nautilus: Open in Terminal (needs nautilus-python)
)

print_banner() {
    echo -e "${C_CYAN}==============================================================================${C_RESET}"
    echo -e "${C_BOLD}  Quickshell Atelier  -  Hyprland + Quickshell dotfiles${C_RESET}"
    echo -e "${C_CYAN}==============================================================================${C_RESET}"
    $DRY_RUN && log_warn "DRY RUN: nothing will be changed."
    return 0
}

check_user() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this as root. It calls sudo itself when needed."
        exit 1
    fi
}

preflight() {
    local missing=0
    for item in "${LINKS[@]}"; do
        if [ ! -e "$SCRIPT_DIR/${item%%:*}" ]; then
            log_error "Missing in repo: ${item%%:*}"; missing=1
        fi
    done
    [ "$missing" -eq 0 ] || exit 1
    [ -d "$SCRIPT_DIR/hypr/wall" ] || log_warn "hypr/wall/ (wallpapers) is not in this folder; copy it over from the old machine."
    return 0
}

# ---- hardware ------------------------------------------------------------------
has_gpu() { command -v lspci >/dev/null 2>&1 && lspci -nn | grep -E 'VGA|3D|Display' | grep -Eqi "$1"; }

# ---- packages ----------------------------------------------------------------
enable_multilib() {
    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        log_success "[multilib] already enabled."
        return
    fi
    log_info "Enabling [multilib] (Steam, 32-bit Vulkan/gamemode/mangohud)..."
    run sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
    run sudo pacman -Sy
}

setup_aur_helper() {
    AUR_HELPER=""
    if command -v yay >/dev/null 2>&1; then AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then AUR_HELPER="paru"
    else
        log_info "No AUR helper found. Installing yay-bin..."
        run sudo pacman -S --needed --noconfirm base-devel git
        if ! $DRY_RUN; then
            local tmp; tmp="$(mktemp -d)"
            git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
            (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
            rm -rf "$tmp"
        fi
        AUR_HELPER="yay"
    fi
}

read_list() { grep -vE '^\s*(#|$)' "$1"; }

pacman_install() {
    if ! run sudo pacman -S --needed --noconfirm "$@"; then
        log_warn "Bulk install failed; retrying one by one..."
        local p
        for p in "$@"; do
            run sudo pacman -S --needed --noconfirm "$p" || log_warn "Could not install: $p"
        done
    fi
}

install_packages() {
    echo ""
    if ! command -v pacman >/dev/null 2>&1; then
        log_warn "pacman not found (not Arch). Skipping packages; install dependencies manually."
        return
    fi
    enable_multilib
    setup_aur_helper
    run sudo pacman -S --needed --noconfirm pciutils >/dev/null || true

    local PAC=()
    [ -f "$SCRIPT_DIR/setup/packages/pacman.txt" ] && mapfile -t PAC < <(read_list "$SCRIPT_DIR/setup/packages/pacman.txt")

    # headers for every installed kernel (DKMS builds v4l2loopback / NVIDIA against them)
    local pb kern
    for pb in /usr/lib/modules/*/pkgbase; do
        [ -f "$pb" ] || continue
        kern="$(cat "$pb")"
        PAC+=("${kern}-headers")
    done

    # GPU drivers by detected hardware
    local vendor
    for vendor in nvidia amd intel; do
        local pat="$vendor"; [ "$vendor" = amd ] && pat='AMD|ATI|Radeon'
        if has_gpu "$pat" && [ -f "$SCRIPT_DIR/setup/packages/gpu-$vendor.txt" ]; then
            log_info "Detected a $vendor GPU: adding setup/packages/gpu-$vendor.txt"
            mapfile -t -O "${#PAC[@]}" PAC < <(read_list "$SCRIPT_DIR/setup/packages/gpu-$vendor.txt")
        fi
    done

    log_info "Installing official packages..."
    pacman_install "${PAC[@]}"

    if [ -f "$SCRIPT_DIR/setup/packages/aur.txt" ] && [ -n "$AUR_HELPER" ]; then
        log_info "Installing AUR packages via $AUR_HELPER..."
        mapfile -t AUR < <(read_list "$SCRIPT_DIR/setup/packages/aur.txt")
        local flags=(--needed --noconfirm)
        [ "$AUR_HELPER" = "yay" ] && flags+=(--answerclean None --answerdiff None)
        if ! run "$AUR_HELPER" -S "${flags[@]}" "${AUR[@]}"; then
            log_warn "Bulk AUR install failed; retrying one by one..."
            for p in "${AUR[@]}"; do
                run "$AUR_HELPER" -S "${flags[@]}" "$p" || log_warn "Could not install: $p"
            done
        fi
    fi
}

# ---- system files (/etc) -------------------------------------------------------
# install_system_tree <dir>: <dir>/etc/<path> -> /etc/<path>
#   system/        always (camera v4l2loopback, ntsync, zram, AirDrop stick + owly, bluetoothd --experimental)
#   system/nvidia/ only with an NVIDIA GPU (DRM modeset, early KMS)
# Real copies (root-owned), not links. A different existing file is backed up first.
install_system_tree() {
    local root="$1" f rel dest
    [ -d "$root/etc" ] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$root"/}"            # etc/modprobe.d/v4l2loopback.conf
        dest="/$rel"
        if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
            log_success "Up to date: $dest"
            continue
        fi
        if [ -e "$dest" ]; then
            SYS_BACKUP="${SYS_BACKUP:-$CONF/atelier-backups/system_$(date +%Y%m%d_%H%M%S)}"
            run mkdir -p "$SYS_BACKUP/$(dirname "$rel")"
            run cp -a "$dest" "$SYS_BACKUP/$rel"
            log_info "Backed up $dest -> $SYS_BACKUP/$rel"
        fi
        run sudo install -Dm644 "$f" "$dest"
        log_success "Installed $dest"
        SYS_CHANGED=true
        case "$rel" in etc/mkinitcpio.conf.d/*|etc/modprobe.d/*) REBUILD_INITRAMFS=true ;; esac
    done < <(find "$root/etc" -type f -print0 | sort -z)
}

install_system_files() {
    echo ""
    log_info "Installing system files (camera, ntsync, zram, GPU)..."
    SYS_CHANGED=false; REBUILD_INITRAMFS=false
    install_system_tree "$SCRIPT_DIR/system"
    if has_gpu nvidia; then
        install_system_tree "$SCRIPT_DIR/system/nvidia"
    fi
    if $REBUILD_INITRAMFS && command -v mkinitcpio >/dev/null 2>&1; then
        log_info "Rebuilding initramfs (module options changed)..."
        run sudo mkinitcpio -P || log_warn "mkinitcpio failed; run: sudo mkinitcpio -P"
    fi
    $SYS_CHANGED && NEED_REBOOT=true
    return 0
}

enable_services() {
    echo ""
    log_info "Enabling services..."
    local s
    for s in NetworkManager bluetooth power-profiles-daemon sshd systemd-timesyncd ufw; do
        if systemctl list-unit-files "$s.service" >/dev/null 2>&1; then
            if systemctl is-enabled -q "$s.service" 2>/dev/null; then
                log_success "$s already enabled"
            else
                run sudo systemctl enable --now "$s.service" && log_success "Enabled $s"
            fi
        fi
    done
    if command -v ufw >/dev/null 2>&1 && ! grep -qs '^ENABLED=yes' /etc/ufw/ufw.conf; then
        run sudo ufw default deny incoming
        run sudo ufw default allow outgoing
        run sudo ufw --force enable
        log_success "Firewall on (deny incoming)"
    fi
    # AirDrop (owly): the receiver listens on 8771 on awdl0, link-local only. ufw skips a rule it already has.
    if command -v ufw >/dev/null 2>&1 && command -v owly >/dev/null 2>&1; then
        run sudo ufw allow in on awdl0 proto tcp from fe80::/10 to any port 8771 comment "AirDrop (owly)" >/dev/null \
            && log_success "Firewall: AirDrop receiver allowed on awdl0"
    fi
    # iPhone messages/contacts/notifications (tether-bin): the adapter must present itself as
    # A/V Hands-Free, re-applied after every bluetoothd start. The bluetoothd --experimental
    # drop-in comes from system/etc/systemd/system/bluetooth.service.d/.
    if systemctl list-unit-files 'tether-btclass@.service' >/dev/null 2>&1; then
        if systemctl is-enabled -q tether-btclass@hci0.service 2>/dev/null; then
            log_success "tether-btclass@hci0 already enabled"
        else
            run sudo systemctl enable --now tether-btclass@hci0.service && log_success "Enabled tether-btclass@hci0"
        fi
    fi
}

install_greeter() {
    $GREETER || { log_info "Skipping the login screen (--no-greeter)."; return; }
    echo ""
    if systemctl is-enabled -q greetd.service 2>/dev/null && [ -d /etc/greetd/atelier-greeter ]; then
        log_info "Refreshing the Atelier login screen..."
        run sudo "$SCRIPT_DIR/greeter/install.sh" --refresh || log_warn "Greeter refresh failed."
    else
        log_info "Installing the Atelier login screen (greetd)..."
        run sudo "$SCRIPT_DIR/greeter/install.sh" --enable || log_warn "Greeter install failed; run: sudo greeter/install.sh --enable"
    fi
}

# ---- icons: Colloid (https://github.com/vinceliuice/Colloid-icon-theme) -------
# Installs exactly the variants the Atelier themes use (see "icons" in theming/themes/*.json).
# Skipped if they are already in ~/.local/share/icons.
install_icons() {
    local dest="$HOME/.local/share/icons"
    local need=(Colloid-Dark Colloid-Light Colloid-Purple-Dark Colloid-Purple-Light
                Colloid-Purple-Catppuccin-Dark Colloid-Purple-Catppuccin-Light
                Colloid-Purple-Dracula-Dark Colloid-Green-Everforest-Dark
                Colloid-Yellow-Gruvbox-Dark Colloid-Nord-Dark)
    local missing=0 n
    for n in "${need[@]}"; do [ -d "$dest/$n" ] || missing=1; done
    if [ "$missing" -eq 0 ]; then
        log_success "Colloid icon theme already installed."
        return
    fi
    if ! command -v git >/dev/null 2>&1; then
        log_warn "git not found; skipping Colloid icon theme."
        return
    fi
    log_info "Installing Colloid icon theme (all Atelier variants)..."
    if $DRY_RUN; then echo -e "${C_MAGENTA}[dry-run]${C_RESET} git clone Colloid-icon-theme && install.sh x6 -> $dest"; return; fi
    local tmp; tmp="$(mktemp -d)"
    if git clone --depth 1 https://github.com/vinceliuice/Colloid-icon-theme "$tmp/colloid" >/dev/null 2>&1; then
        (
            cd "$tmp/colloid"
            ./install.sh -d "$dest" -s default  -t default purple
            ./install.sh -d "$dest" -s catppuccin -t purple
            ./install.sh -d "$dest" -s dracula    -t purple
            ./install.sh -d "$dest" -s everforest -t green
            ./install.sh -d "$dest" -s gruvbox    -t yellow
            ./install.sh -d "$dest" -s nord       -t default
        ) >/dev/null 2>&1 && log_success "Colloid icon theme installed to $dest" \
          || log_warn "Colloid install script reported an error; check $dest."
    else
        log_warn "Could not download Colloid (offline?). Re-run the installer later."
    fi
    rm -rf "$tmp"
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        for d in "$dest"/Colloid*; do gtk-update-icon-cache -qf "$d" 2>/dev/null || true; done
}

# ---- GTK themes: bundled (setup/gtk-themes.tar.xz -> ~/.themes) ---------------
# Colloid / Rosepine / Tokyonight GTK builds named by "gtk" in theming/themes/*.json.
install_gtk_themes() {
    local tarball="$SCRIPT_DIR/setup/gtk-themes.tar.xz"
    [ -f "$tarball" ] || return 0
    local missing
    missing="$(tar -tJf "$tarball" | awk -F/ 'NF>1 && $2!="" {print $2}' | sort -u | while read -r t; do [ -e "$HOME/.themes/$t" ] || echo "$t"; done)"
    if [ -z "$missing" ]; then
        log_success "GTK themes already installed."
        return
    fi
    log_info "Unpacking GTK themes into ~/.themes..."
    run tar -C "$HOME" --skip-old-files -xJf "$tarball"
    log_success "GTK themes installed."
}

# ---- dotfiles ----------------------------------------------------------------
link_one() {
    local src="$SCRIPT_DIR/$1" dest="$2"

    # Already correct?
    if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
        log_success "Already linked: $dest"
        return
    fi

    # Back up whatever is there
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ -z "${BACKUP_DIR:-}" ]; then
            BACKUP_DIR="$CONF/atelier-backups/backup_$(date +%Y%m%d_%H%M%S)"
            run mkdir -p "$BACKUP_DIR"
            log_info "Backing up existing configs to: $BACKUP_DIR"
        fi
        # keep the destination's identity in the backup (".zshrc", "starship.toml", ...)
        local slot; slot="$BACKUP_DIR/$(basename "$dest")"
        [ -e "$slot" ] && slot="$BACKUP_DIR/$(basename "$(dirname "$dest")")_$(basename "$dest")"
        run mv "$dest" "$slot"
        log_success "Backed up $dest"
        # remember backups so large untracked data can be restored below
        BACKED_UP+=("$dest|$slot")
    fi

    run mkdir -p "$(dirname "$dest")"
    run ln -sfn "$src" "$dest"
    log_success "Linked $dest -> $src"
}

# Wallpapers (hypr/wall) are too big to keep in git; carry them over from the backup.
restore_untracked() {
    local entry dest slot
    for entry in "${BACKED_UP[@]:-}"; do
        [ -n "$entry" ] || continue
        dest="${entry%%|*}"; slot="${entry##*|}"
        if [ "$dest" = "$CONF/hypr" ] && [ -d "$slot/wall" ] && [ ! -e "$SCRIPT_DIR/hypr/wall" ]; then
            run mv "$slot/wall" "$SCRIPT_DIR/hypr/wall"
            log_success "Restored wallpapers: $SCRIPT_DIR/hypr/wall"
        fi
    done
}

# setup/seed/config/<path> -> ~/.config/<path>, copied only when missing. These are files the app
# (or atelier-theme) rewrites itself, so a symlink would be replaced on the first save.
seed_files() {
    local root="$SCRIPT_DIR/setup/seed/config" f rel dest n=0
    [ -d "$root" ] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$root"/}"; dest="$CONF/$rel"
        [ -e "$dest" ] && continue
        run mkdir -p "$(dirname "$dest")"
        run cp -a "$f" "$dest"
        n=$((n + 1))
    done < <(find "$root" -type f -print0)
    [ "$n" -gt 0 ] && log_success "Seeded $n app settings file(s) (Atelier state, VS Code, Vesktop, default apps, Spicetify...)" \
                   || log_success "App settings already seeded."
}

# local/share/applications/*.desktop -> ~/.local/share/applications, with @HOME@ filled in.
install_desktop_entries() {
    local f dest
    for f in "$SCRIPT_DIR"/local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        dest="$APPS/$(basename "$f")"
        if [ -f "$dest" ] && cmp -s <(sed "s#@HOME@#$HOME#g" "$f") "$dest"; then continue; fi
        run mkdir -p "$APPS"
        if $DRY_RUN; then echo -e "${C_MAGENTA}[dry-run]${C_RESET} render $f -> $dest"
        else sed "s#@HOME@#$HOME#g" "$f" > "$dest"; fi
        log_success "Installed launcher $(basename "$f")"
    done
}

deploy_dotfiles() {
    BACKED_UP=()
    log_info "Linking dotfiles..."
    for item in "${LINKS[@]}"; do
        link_one "${item%%:*}" "${item#*:}"
    done
    restore_untracked

    # Machine-local state (~/.config/atelier) is seeded with the rest: setup/seed/config/atelier
    seed_files
    install_desktop_entries

    run chmod +x "$SCRIPT_DIR/theming/atelier-theme" "$SCRIPT_DIR/theming/build-qt6ct.sh" "$SCRIPT_DIR"/local/bin/* 2>/dev/null || true
    run chmod +x "$SCRIPT_DIR"/config/scripts/*.py "$SCRIPT_DIR"/config/scripts/*.sh "$SCRIPT_DIR"/hypr/scripts/*.sh "$SCRIPT_DIR"/quickshell/scripts/* 2>/dev/null || true
    run mkdir -p "$HOME/Pictures/Screenshots"

    case ":$PATH:" in
        *":$BIN:"*) ;;
        *) log_warn "$BIN is not on your PATH yet (zsh/.zshrc adds it); open a new shell." ;;
    esac
}

# ---- qt6ct plugin (Qt apps follow the theme live) --------------------------------
build_qt6ct() {
    if [ -f "$HOME/.local/lib/qt6/plugins/platformthemes/libqt6ct.so" ]; then
        log_success "qt6ct plugin already built."
        return
    fi
    if ! command -v qmake6 >/dev/null 2>&1; then
        log_warn "qmake6 not found (qt6-base); skipping the qt6ct plugin. Later: theming/build-qt6ct.sh"
        return
    fi
    log_info "Building the qt6ct plugin into ~/.local..."
    run "$SCRIPT_DIR/theming/build-qt6ct.sh" || log_warn "qt6ct build failed; re-run theming/build-qt6ct.sh"
}

install_vscode_extensions() {
    local list="$SCRIPT_DIR/setup/vscode-extensions.txt"
    [ -f "$list" ] && command -v code >/dev/null 2>&1 || return 0
    local have e n=0
    have="$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    while read -r e; do
        [ -n "$e" ] || continue
        grep -qx "$(echo "$e" | tr '[:upper:]' '[:lower:]')" <<<"$have" && continue
        run code --install-extension "$e" >/dev/null 2>&1 || log_warn "VS Code: could not install $e"
        n=$((n + 1))
    done < "$list"
    log_success "VS Code extensions: $n installed."
}

apply_theme() {
    local engine="$SCRIPT_DIR/theming/atelier-theme" cur
    command -v python3 >/dev/null 2>&1 || return 0
    cur="$(python3 "$engine" current 2>/dev/null || true)"
    [ -n "$cur" ] || cur="catppuccin-mocha"
    log_info "Applying Atelier theme: $cur (every app follows it)..."
    run python3 "$engine" apply "$cur" >/dev/null 2>&1 || log_warn "Theme apply reported an error; run: atelier-theme apply $cur"
}

setup_shell() {
    command -v zsh >/dev/null 2>&1 || return 0
    if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
        log_success "zsh is already your default shell."
        return
    fi
    log_info "Setting zsh as default shell..."
    if run chsh -s "$(command -v zsh)"; then
        log_success "Default shell set to zsh."
    else
        log_warn "Run manually: chsh -s $(command -v zsh)"
    fi
}

post_install() {
    echo ""
    echo -e "${C_GREEN}==============================================================================${C_RESET}"
    echo -e "${C_BOLD}  Done.${C_RESET}"
    echo -e "${C_GREEN}==============================================================================${C_RESET}"
    echo -e "  Configs are symlinks into: ${C_CYAN}$SCRIPT_DIR${C_RESET}"
    [ -n "${BACKUP_DIR:-}" ] && echo -e "  Previous configs saved in: ${C_CYAN}$BACKUP_DIR${C_RESET}"
    [ -n "${SYS_BACKUP:-}" ] && echo -e "  Previous /etc files saved in: ${C_CYAN}$SYS_BACKUP${C_RESET}"
    echo ""
    ${NEED_REBOOT:-false} && echo -e "  ${C_YELLOW}Reboot${C_RESET} to load the new kernel modules (iPhone camera, NVIDIA) and the login screen."
    echo -e "  Reload the shell:      ${C_MAGENTA}qs kill; quickshell -d${C_RESET}  (or restart Hyprland)"
    echo -e "  Reload Hyprland:       ${C_MAGENTA}hyprctl reload${C_RESET}"
    echo -e "  Apply a theme:         ${C_MAGENTA}atelier-theme apply <id>${C_RESET}   (list: ${C_MAGENTA}atelier-theme list${C_RESET})"
    echo ""
}

main() {
    print_banner
    check_user
    preflight
    if $SKIP_PKGS; then
        log_info "Dotfiles only: skipping packages, /etc files, services and the login screen."
    else
        install_packages
        install_system_files
        enable_services
    fi
    install_icons
    install_gtk_themes
    deploy_dotfiles
    build_qt6ct
    install_vscode_extensions
    apply_theme
    setup_shell
    $SKIP_PKGS || install_greeter
    post_install
}

main
