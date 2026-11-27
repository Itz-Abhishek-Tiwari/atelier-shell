#!/usr/bin/env bash
# ==============================================================================
#  Atelier greeter: use Quickshell as the login screen (replaces SDDM)
#
#    sudo greeter/install.sh             install greetd + cage + the greeter files
#                                          (does NOT change your current login manager)
#    sudo greeter/install.sh --enable    ...and switch the login manager SDDM -> greetd
#    sudo greeter/install.sh --refresh   update the greeter files + re-sync theme/wallpaper
#    sudo greeter/install.sh --quiet-boot  hide kernel/systemd text at boot (/etc/kernel/cmdline)
#    sudo greeter/install.sh --uninstall switch back to SDDM and remove the greeter
#    greeter/install.sh --demo           preview the UI fullscreen (no root, no changes; Esc)
#
#  How it works:  greetd (login daemon)  ->  cage (tiny kiosk compositor)
#                 ->  quickshell running greeter/shell.qml  ->  session.sh  ->  your session
#
#  After installing, Settings → Login screen controls it: /var/lib/atelier-greeter belongs to
#  you, and the shell keeps its options, theme, wallpaper and avatar there (no root needed).
#
#  Safety: nothing is switched until you pass --enable, and --uninstall restores SDDM.
#  If a login ever fails, press Ctrl+Alt+F3 for a TTY and run:
#      sudo systemctl disable greetd && sudo systemctl enable --force sddm && sudo reboot
# ==============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # this file lives in greeter/
DEST=/etc/greetd/atelier-greeter
CACHE=/var/cache/atelier-greeter
DATA=/var/lib/atelier-greeter

MODE=install
for a in "$@"; do
    case "$a" in
        --enable) MODE=enable ;;
        --refresh) MODE=refresh ;;
        --uninstall) MODE=uninstall ;;
        --quiet-boot) MODE=quietboot ;;
        --demo) MODE=demo ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $a (try --help)"; exit 2 ;;
    esac
done

info() { echo -e "\033[36m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[32m[OK]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }
die()  { echo -e "\033[31m[ERROR]\033[0m $*" >&2; exit 1; }

# The person whose theme/wallpaper the greeter should copy (works under sudo)
OWNER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"

if [ "$MODE" = demo ]; then
    exec quickshell -p "$REPO/greeter/shell.qml"
fi

[ "$EUID" -eq 0 ] || exec sudo -E "$0" "$@"

# ---- greeter files (root-owned) + data folder (yours) ------------------------
install_files() {
    install -d -m 755 "$DEST"
    install -m 644 "$REPO/greeter/shell.qml" "$DEST/shell.qml"
    install -m 755 "$REPO/greeter/session.sh" "$DEST/session.sh"
    install -m 755 "$REPO/greeter/kiosk.sh" "$DEST/kiosk.sh"
    # the lock-screen styles (modules/lock = the shell's own files, through symlinks) and the
    # stand-ins they read (config/, services/, components/); -L copies the real files
    rm -rf "$DEST/config" "$DEST/services" "$DEST/components" "$DEST/modules" "$DEST/scripts"
    cp -rL "$REPO/greeter/config" "$REPO/greeter/services" "$REPO/greeter/components" \
           "$REPO/greeter/modules" "$DEST/"
    chmod -R u=rwX,go=rX "$DEST"
    # older versions kept these next to shell.qml; they now live in $DATA
    rm -f "$DEST/colors.json" "$DEST/wallpaper"
    ok "Installed greeter UI to $DEST"
}

# theme colours, wallpaper, avatar, clock font: copied because the greeter cannot read $HOME.
# The folder is handed to you so Settings → Login screen can update it without root.
refresh_assets() {
    install -d -m 755 -o "$OWNER" -g "$(id -gn "$OWNER")" "$DATA"
    chown -R "$OWNER:$(id -gn "$OWNER")" "$DATA"
    if sudo -u "$OWNER" -H "$REPO/quickshell/scripts/greeter-sync.sh" "$DATA" | sed 's/^/        /'; then
        ok "Theme, wallpaper and avatar synced to $DATA"
    else
        warn "Could not sync to $DATA; the greeter will use its built-in colours."
    fi
}

write_config() {
    install -d -m 755 /etc/greetd
    if [ -f /etc/greetd/config.toml ] && ! grep -q atelier-greeter /etc/greetd/config.toml; then
        cp -a /etc/greetd/config.toml "/etc/greetd/config.toml.bak-$(date +%Y%m%d%H%M%S)"
        info "Backed up existing /etc/greetd/config.toml"
    fi
    cat > /etc/greetd/config.toml <<EOF
# Written by quickshell-atelier/greeter/install.sh
[terminal]
vt = 1

[default_session]
# cage = single-window kiosk compositor; quickshell draws the login screen
# QT_WAYLAND_DISABLE_WINDOWDECORATION + cage -d: no title bar / min-max-close buttons
# kiosk.sh switches every screen but the laptop panel off, then starts quickshell
command = "env QT_WAYLAND_DISABLE_WINDOWDECORATION=1 cage -s -d -m extend -- $DEST/kiosk.sh"
user = "greeter"
EOF
    ok "Wrote /etc/greetd/config.toml"
}

case "$MODE" in
install|enable)
    command -v pacman >/dev/null || die "This installer targets Arch Linux (pacman not found)."
    info "Installing greetd, cage and wlr-randr..."
    pacman -S --needed --noconfirm greetd cage wlr-randr
    # make sure the 'greeter' system user exists (greetd ships a sysusers entry)
    systemd-sysusers 2>/dev/null || true
    id greeter >/dev/null 2>&1 || die "User 'greeter' is missing; create it: useradd -M -G video -s /usr/bin/nologin greeter"
    usermod -aG video,render greeter 2>/dev/null || true

    install_files
    refresh_assets
    install -d -m 755 -o greeter -g greeter "$CACHE"
    write_config

    if [ "$MODE" = enable ]; then
        info "Switching login manager: SDDM -> greetd"
        systemctl disable sddm.service 2>/dev/null || true
        systemctl enable --force greetd.service
        ok "greetd enabled. It takes over at the next boot (or: sudo systemctl stop sddm && sudo systemctl start greetd)."
        warn "Keep a TTY escape: Ctrl+Alt+F3, log in, then run the recovery line in this script's header."
    else
        info "Login manager NOT changed. Preview first:  greeter/install.sh --demo"
        info "When happy:  sudo greeter/install.sh --enable"
    fi
    ;;
refresh)
    [ -d "$DEST" ] || die "Greeter not installed yet. Run: sudo greeter/install.sh"
    # kiosk.sh needs it to keep the login screen on the laptop panel
    command -v wlr-randr >/dev/null || pacman -S --needed --noconfirm wlr-randr
    install_files
    refresh_assets
    write_config
    ok "Done. The new login screen shows at your next login."
    ;;
quietboot)
    # Hide kernel + systemd boot text (it can show on the login VT). This machine boots a UKI
    # whose command line comes from /etc/kernel/cmdline; GRUB's GRUB_CMDLINE_* is not used.
    params="quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=auto"
    if [ -f /etc/kernel/cmdline ]; then
        cur="$(cat /etc/kernel/cmdline)"
        new="$cur"
        for p in $params; do
            case " $new " in *" ${p%%=*}="*|*" $p "*) ;; *) new="$new $p" ;; esac
        done
        if [ "$new" = "$cur" ]; then ok "Already quiet: $cur"; exit 0; fi
        cp -a /etc/kernel/cmdline "/etc/kernel/cmdline.bak-$(date +%Y%m%d%H%M%S)"
        printf '%s\n' "$new" > /etc/kernel/cmdline
        ok "Kernel command line: $new"
        info "Rebuilding the boot images (mkinitcpio -P)..."
        mkinitcpio -P
        ok "Quiet boot takes effect at the next boot (backup of the old cmdline in /etc/kernel)."
    elif [ -f /etc/default/grub ]; then
        warn "No /etc/kernel/cmdline. For GRUB add '$params' to GRUB_CMDLINE_LINUX_DEFAULT in"
        warn "/etc/default/grub, then run: grub-mkconfig -o /boot/grub/grub.cfg"
    else
        die "Unknown boot setup: add '$params' to your kernel command line by hand."
    fi
    ;;
uninstall)
    info "Switching login manager back to SDDM..."
    systemctl disable greetd.service 2>/dev/null || true
    if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
        systemctl enable --force sddm.service
        ok "SDDM re-enabled."
    else
        warn "SDDM is not installed; install it (pacman -S sddm) before rebooting."
    fi
    rm -rf "$DEST" "$CACHE" "$DATA"
    for f in /etc/greetd/config.toml; do
        [ -f "$f" ] && grep -q atelier-greeter "$f" && rm -f "$f"
    done
    ok "Greeter files removed (greetd/cage packages left installed; remove with: pacman -Rns greetd cage)."
    ;;
esac
