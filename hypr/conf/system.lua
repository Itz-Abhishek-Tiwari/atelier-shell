-- Rendering, cursor, XWayland and misc behaviour

hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        -- if the shell's lock screen ever crashes while locked, another locker (hyprlock,
        -- run from a TTY) may take over the lock instead of leaving a red "locked" screen
        allow_session_lock_restore = true,
        -- adaptive sync for fullscreen apps only (games/video on the 120 Hz panel);
        -- never on the desktop, where it can make the cursor judder
        vrr = 2,
        -- wake the screen after hypridle's DPMS-off on any input, not just a key press
        key_press_enables_dpms  = true,
        mouse_move_enables_dpms = true,
    },

    render = {
        new_render_scheduling = true,  -- adaptive triple buffering: fewer dropped frames on the iGPU
        direct_scanout        = 2,     -- fullscreen games/video bypass compositing (lower latency)
    },

    cursor = {
        -- 2 = auto: hardware cursor on the AMD-driven laptop panel (no pointer stutter
        -- while things animate), software fallback only where needed (NVIDIA HDMI)
        no_hardware_cursors = 2,
    },

    xwayland = {
        force_zero_scaling = true,
    },
})
