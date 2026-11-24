-- Autostart (once, at login)
hl.on("hyprland.start", function()
    hl.exec_cmd("quickshell")                -- bar, wallpaper, OSD, notifications, lock screen
    -- dim / lock / screen off / suspend: the shell's file from Settings → Idle & sleep, else hypridle.conf
    hl.exec_cmd([[sh -c 'c="$HOME/.config/atelier/hypridle.conf"; if [ -f "$c" ]; then exec hypridle -c "$c"; else exec hypridle; fi']])
    local t = require("conf.lib").theme
    hl.exec_cmd("hyprctl setcursor " .. (t.cursor or "Bibata-Modern-Ice") .. " " .. (t.cursor_size or 24))
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("systemctl --user start plasma-polkit-agent")   -- password prompts for pkexec/gparted (polkit-kde-agent)
    -- let root (only the local root user) draw on XWayland, so pkexec'd X11 apps like gparted can open :0
    hl.exec_cmd("sh -c 'command -v xhost >/dev/null && xhost +SI:localuser:root'")
    hl.exec_cmd("kdeconnect-indicator")
end)
