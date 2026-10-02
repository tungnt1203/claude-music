-- cmusic.lua — loaded into mpv by music.sh (--script). Runs the parts that must outlive the
-- shell command: fades and, later, timers. music.sh talks to it with `script-message cmusic-*`
-- and reads its state from `user-data/cmusic/*`.

local FADE_IN, FADE_OUT = 1.5, 1.0

-- The volume the user asked for. The real `volume` property dips below it during fades.
local level = mp.get_property_number("volume", 100)
local fade_timer

local function publish(key, value) mp.set_property("user-data/cmusic/" .. key, tostring(value)) end

-- Ramp the volume to `to` over `secs`, then call `done`. A new fade replaces a running one.
local function fade(to, secs, done)
    if fade_timer then fade_timer:kill() end
    local from = mp.get_property_number("volume", 0)
    local steps, i = math.max(1, math.floor(secs * 25)), 0
    fade_timer = mp.add_periodic_timer(secs / steps, function()
        i = i + 1
        mp.set_property_number("volume", from + (to - from) * i / steps)
        if i >= steps then
            fade_timer:kill(); fade_timer = nil
            if done then done() end
        end
    end)
end

local function set_level(v)
    level = math.max(0, math.min(130, v))
    publish("level", math.floor(level + 0.5))
end

-- Every track starts silent and fades in once audio actually starts.
local pending_fade_in = false
mp.register_event("start-file", function()
    if fade_timer then fade_timer:kill(); fade_timer = nil end
    mp.set_property_number("volume", 0)
    pending_fade_in = true
end)
mp.register_event("playback-restart", function()
    if pending_fade_in then
        pending_fade_in = false
        fade(level, FADE_IN)
    end
end)

mp.register_script_message("cmusic-volume", function(v)
    if fade_timer then fade_timer:kill(); fade_timer = nil end
    set_level(tonumber(v) or level)
    mp.set_property_number("volume", level)
end)

mp.register_script_message("cmusic-stop", function()
    fade(0, FADE_OUT, function() mp.command("quit") end)
end)

set_level(level)
publish("ready", "yes")
