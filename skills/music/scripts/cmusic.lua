-- cmusic.lua — loaded into mpv by music.sh (--script). Runs the parts that must outlive the
-- shell command: fades and timers. music.sh talks to it with `script-message cmusic-*`
-- and reads its state from `user-data/cmusic/*`.

local FADE_IN, FADE_OUT, FADE_SLEEP = 1.5, 1.0, 10

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

local function fade_quit(secs) fade(0, secs, function() mp.command("quit") end) end

mp.register_script_message("cmusic-stop", function() fade_quit(FADE_OUT) end)

-- Timers -------------------------------------------------------------------------------
-- One timer at a time. Published as "<icon>|<end epoch or 'track'>" for `now` to display.
local timer, stop_after_track = nil, false

local function clear_timer()
    if timer then timer:kill(); timer = nil end
    stop_after_track = false
    publish("timer", "")
end

-- Call `on_done` `lead` seconds before the `secs` mark, so a fade can end right on time.
local function set_timer(icon, secs, lead, on_done)
    clear_timer()
    publish("timer", icon .. "|" .. (os.time() + secs))
    timer = mp.add_timeout(math.max(0, secs - lead), function() timer = nil; on_done() end)
end

-- `stop in 30m`: fade out over the last 10 seconds, then quit.
mp.register_script_message("cmusic-sleep", function(secs)
    secs = tonumber(secs) or 0
    local f = math.min(FADE_SLEEP, secs)
    set_timer("⏲", secs, f, function() fade_quit(f) end)
end)

-- `stop after this`: fade out as the current track ends, then quit.
mp.register_script_message("cmusic-sleep-after-track", function()
    clear_timer()
    stop_after_track = true
    publish("timer", "⏲|track")
end)
mp.observe_property("time-remaining", "number", function(_, left)
    if stop_after_track and left and left <= FADE_SLEEP and not fade_timer then fade_quit(left) end
end)
mp.register_event("end-file", function(e)
    if stop_after_track and e.reason == "eof" then mp.command("quit") end
end)

mp.register_script_message("cmusic-timer-off", clear_timer)

-- Focus / Pomodoro -----------------------------------------------------------------------

-- Desktop notification with a chime, best effort (macOS osascript, Linux notify-send).
local function notify(text)
    local args
    local ok = os.execute("command -v osascript >/dev/null 2>&1")
    if ok == true or ok == 0 then -- Lua 5.1/LuaJIT return a status code, 5.2+ a boolean
        args = { "osascript", "-e", ('display notification "%s" with title "cmusic" sound name "Glass"'):format(text) }
    else
        args = { "notify-send", "cmusic", text }
    end
    mp.command_native_async({ name = "subprocess", args = args, playback_only = false }, function() end)
end

-- `focus 25`: focus music for 25 minutes, fade out, then (optionally) break music, then stop.
mp.register_script_message("cmusic-focus", function(focus_secs, break_secs, break_query)
    focus_secs, break_secs = tonumber(focus_secs) or 1500, tonumber(break_secs) or 0
    set_timer("🍅", focus_secs, FADE_SLEEP, function()
        fade(0, FADE_SLEEP, function()
            if break_secs <= 0 then
                notify("Focus session done. Nice work!")
                mp.command("quit")
                return
            end
            notify(("Break time! %d minutes."):format(math.floor(break_secs / 60 + 0.5)))
            mp.commandv("loadfile", "ytdl://ytsearch1:" .. break_query, "replace")
            set_timer("☕", break_secs, FADE_SLEEP, function()
                notify("Break's over. Back to it!")
                fade_quit(FADE_SLEEP)
            end)
        end)
    end)
end)

set_level(level)
publish("ready", "yes")
