-- Autostart (once, at login)
hl.on("hyprland.start", function()
    hl.exec_cmd("quickshell")                -- bar, wallpaper, OSD, notifications, lock screen
    hl.exec_cmd("hypridle")                  -- dim / lock / screen off / suspend (hypridle.conf)
    hl.exec_cmd("hyprctl setcursor macOS 24")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("systemctl --user start plasma-polkit-agent")   -- password prompts for pkexec/gparted (polkit-kde-agent)
    -- let root (only the local root user) draw on XWayland, so pkexec'd X11 apps like gparted can open :0
    hl.exec_cmd("sh -c 'command -v xhost >/dev/null && xhost +SI:localuser:root'")
    hl.exec_cmd("kdeconnect-indicator")
end)
