-- Fallback for additional displays.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Match the display rather than the GPU connector name.
-- Dell above HP, centered horizontally, with 1:1 scaling.
hl.monitor({
    output = "desc:HP Inc. OMEN 27i IPS 6CM1290P75",
    mode = "2560x1440@164.83",
    position = "0x1080",
    scale = 1,
})
hl.monitor({
    output = "desc:Dell Inc. DELL S2721H 9P8HZ13",
    mode = "1920x1080@60",
    position = "320x0",
    scale = 1,
})
