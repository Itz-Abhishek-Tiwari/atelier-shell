-- Window rules and layer rules.
-- There are deliberately NO per-app opacity rules: every app gets the one opacity/blur from
-- appearance.lua. The only exceptions are the "solid" ones below.
local any_of = require("conf.lib").any_of

-- Solid (fully opaque): video, image viewers, games, creative apps, fullscreen.
-- Delete an app from this list if you want it see-through like everything else.
-- Settings → Appearance → Windows can switch both off (every app translucent and blurred); the
-- handles live in the global `atelier_solid` so the shell toggles them without a reload.
local lwin = require("conf.lib").win
atelier_solid = {}
atelier_solid.apps = hl.window_rule({
    name   = "solid-apps",
    match  = { class = any_of({
        "mpv", "vlc", "com.github.rafostar.Clapper", "io.github.celluloid_player.Celluloid",
        "imv", "org.gnome.Loupe", "eog", "feh", "steam", "steam_app_.*", "gamescope",
        "com.obsproject.Studio", "gimp", "krita", "org.inkscape.Inkscape", "Blender",
    }) },
    opaque = true,
})
atelier_solid.fullscreen = hl.window_rule({ name = "solid-fullscreen", match = { fullscreen = true }, opaque = true })
function atelier_apply_solid(t)
    pcall(function() atelier_solid.apps:set_enabled(t.solid_apps ~= false) end)
    pcall(function() atelier_solid.fullscreen:set_enabled(t.solid_fullscreen ~= false) end)
end
atelier_apply_solid(lwin)

-- Don't let hypridle dim/lock/suspend while something is fullscreen (video, games, slides)
hl.window_rule({ name = "idle-inhibit-fullscreen", match = { class = ".*" }, idle_inhibit = "fullscreen" })

-- Games may tear for lower latency (only takes effect while Game mode allows tearing)
hl.window_rule({ name = "games-immediate", match = { class = any_of({ "steam_app_.*", "gamescope" }) }, immediate = true })

-- Floating utilities and dialogs
hl.window_rule({
    name  = "float-apps",
    match = { class = any_of({
        "vlc", "kvantummanager", "qt5ct", "qt6ct", "nwg-look", "org.kde.ark",
        "org.pulseaudio.pavucontrol", "waypaper", "blueman-manager", "nm-applet",
        "nm-connection-editor", "org.kde.polkit-kde-authentication-agent-1",
        "Signal", "com.github.rafostar.Clapper", "app.drey.Warp",
        "net.davidotek.pupgui2", "yad", "eog", "io.github.alainm23.planify",
        "io.gitlab.theevilskeleton.Upscaler", "com.github.unrud.VideoDownloader",
        "io.gitlab.adhami3310.Impression", "io.missioncenter.MissionCenter",
    }) },
    float = true,
})
-- Image viewers: a floating, centred window instead of half the screen (opening a photo
-- shouldn't re-tile everything else)
hl.window_rule({
    name   = "float-image-viewers",
    match  = { class = any_of({ "org.gnome.Loupe", "imv", "feh", "eog", "org.kde.gwenview", "swayimg" }) },
    float  = true,
    center = true,
})
hl.window_rule({
    name  = "float-dolphin-progress",
    match = { class = "^(org.kde.dolphin)$", title = "^(Progress Dialog|Copying) — Dolphin$" },
    float = true,
})
-- Steam's side windows float at their own size (the main "Steam" window stays tiled)
hl.window_rule({
    name  = "float-steam-dialogs",
    match = { class = "^(steam)$", title = "^(Steam Settings|Friends List|Steam - News.*|Screenshot Manager|Properties - .*)$" },
    float = true,
})
hl.window_rule({
    name  = "float-firefox-library",
    match = { class = "^(firefox)$", title = "^(Library)$" },
    float = true,
})
hl.window_rule({
    name  = "float-terminal-monitors",
    match = { class = any_of({ "kitty", "com.mitchellh.ghostty" }), title = "^(top|btop|htop)$" },
    float = true,
})

-- Picture-in-Picture (any browser): floating, solid, keeps its video shape
hl.window_rule({
    name              = "pip",
    match             = { title = "^(Picture-in-Picture)$" },
    float             = true,
    opaque            = true,
    keep_aspect_ratio = true,
})

-- Android emulator (config/scripts/android-emulator.sh): the phone window and its side toolbar
-- are separate windows that size themselves; tiled, the phone drew in a corner of a big empty
-- tile. Floating at their own size, solid (no translucency over the phone screen), no shadow.
hl.window_rule({
    name     = "android-emulator",
    match    = { class = "^(Emulator)$" },
    float    = true,
    opaque   = true,
    no_shadow = true,
    -- the Pixel 9 frame (~/Android/Sdk/skins/pixel_9) is the window's edge: no border/rounding
    border_size = 0,
    rounding    = 0,
})

-- (Settings is a drawer inside quickshell-drawers now; it needs no window rule)

-- Apps can't maximize themselves (keeps tiling in charge)
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix XWayland dragging
hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Layer rules
-- Blur threshold for the shell's glass: just under its surface opacity, so only pixels that are
-- fully inside a drawer/frame get blur. The soft (anti-aliased) edge pixels are below it and
-- blend straight into the window behind; at 0.5 they were blurred too and, with xray, showed the
-- wallpaper as a 1-px coloured line along every drawer edge.
local glass_cut = math.max(0.3, math.min(0.97, (require("conf.lib").win.shell_glass or 0.92) - 0.03))
local layer_rules = {
    -- Quickshell (every "quickshell*" namespace): no compositor animation (the shell animates
    -- its own drawers), and a high alpha threshold so shadows are not blurred.
    -- xray = true: the frame/bar only ever has the wallpaper behind it, so it reuses the cached
    -- wallpaper blur. Real blur here was re-blurring the frame on every app redraw (measured:
    -- the GPU went from ~10% to 57%+ busy at idle with VS Code on screen).
    { ns = "quickshell.*",               ignore_alpha = glass_cut, xray = true,  no_anim = true },
    -- the drawer/pop-up host: xray like the frame (2026-11-20). Drawers grow out of the frame, so
    -- they blur the same wallpaper and match it at any glass opacity; with real blur a drawer over
    -- a bright window came out a different colour from the bar it is attached to. It shrinks to
    -- 1x1 px while nothing shows (DrawerHost.qml). A rule change applies only to newly mapped
    -- layers: restart the shell after changing it.
    { ns = "quickshell-drawers",         ignore_alpha = glass_cut, xray = true,  no_anim = true },
    -- the shell's glass blur on its own rule, so Settings → Appearance can switch it live
    -- (atelier_apply_shell_blur); it must come before the desktop widget's blur = false
    { ns = "quickshell.*",               blur = true, id = "shell-blur" },
    -- desktop widget: plain text on the wallpaper, NO blur. With blur, every pixel of the text's
    -- soft shadow above ignore_alpha got a frosted wallpaper patch behind it = a pale outline
    -- around the clock digits (user-reported 2026-11-20).
    { ns = "quickshell-desktop-widgets", blur = false, no_anim = true },
    -- edge spectrum: thin bars redrawn at 60 fps while music plays; blur behind them would be
    -- re-run on every frame, and they don't need it
    { ns = "quickshell-spectrum",        blur = false, no_anim = true },
    { ns = "atelier-wallpaper",          no_anim = true },
    { ns = "notifications",              blur = true, ignore_alpha = 0.2 },
    { ns = "logout_dialog",              blur = true },
    { ns = "waybar",                     blur = true },
}
atelier_layer = {}
for _, rule in ipairs(layer_rules) do
    local h = hl.layer_rule({
        name         = rule.id or ("layer-" .. rule.ns:gsub("[^%w]", "-")),
        match        = { namespace = "^(" .. rule.ns .. ")$" },
        blur         = rule.blur,
        ignore_alpha = rule.ignore_alpha,
        no_anim      = rule.no_anim,
        xray         = rule.xray,
    })
    if rule.id then atelier_layer[rule.id] = h end
end
function atelier_apply_shell_blur(t)
    pcall(function() atelier_layer["shell-blur"]:set_enabled(t.shell_blur ~= false) end)
end
atelier_apply_shell_blur(require("conf.lib").win)


