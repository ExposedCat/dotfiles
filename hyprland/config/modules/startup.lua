-- UWSM manages the graphical session and its activation environment.
-- Services belong to graphical-session.target and stop when the session ends.
-- Start only at login; the install helper reconciles services after a reload.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.on("hyprland.start", function()
    hl.exec_cmd(require("modules.programs").helper .. " session-start")
end)
