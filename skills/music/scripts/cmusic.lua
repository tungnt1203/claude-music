-- cmusic.lua — loaded into mpv by music.sh (--script). Runs the parts that must outlive the
-- shell command: fades, timers, radio, ducking, the end-of-task swell, lyrics and history. music.sh talks to it with `script-message cmusic-*`
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

-- While Claude waits for the user (Notification hook), play at `duck_ratio` of the level.
local ducked, duck_ratio = false, 0.3
local function target() return ducked and level * duck_ratio or level end

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
        fade(target(), FADE_IN)
    end
end)

mp.register_script_message("cmusic-volume", function(v)
    if fade_timer then fade_timer:kill(); fade_timer = nil end
    ducked = false -- setting the volume means the user is back
    set_level(tonumber(v) or level)
    mp.set_property_number("volume", level)
end)

mp.register_script_message("cmusic-duck", function(percent)
    duck_ratio = math.max(0, math.min(100, tonumber(percent) or 30)) / 100
    if not ducked and not mp.get_property_bool("pause") then ducked = true; fade(target(), 0.6) end
end)
mp.register_script_message("cmusic-unduck", function()
    if ducked then ducked = false; fade(target(), 0.6) end
end)

-- End-of-task swell (Stop hook): briefly raise the volume if the turn took `min_secs` or more.
local turn_start
mp.register_script_message("cmusic-turn-start", function() turn_start = os.time() end)
mp.register_script_message("cmusic-celebrate", function(min_secs)
    local long = turn_start and os.time() - turn_start >= (tonumber(min_secs) or 60)
    turn_start = nil
    if not long or ducked or fade_timer or mp.get_property_bool("pause") then return end
    fade(math.min(130, level * 1.4, level + 25), 0.8, function()
        mp.add_timeout(1.5, function() if not fade_timer then fade(target(), 1.5) end end)
    end)
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

-- Radio ---------------------------------------------------------------------------------
-- When the last queued track starts, append unplayed songs from its YouTube Mix
-- (list=RD<id>, no API key), so playback never runs out.
local radio, played, fetching = mp.get_opt("cmusic-radio") == "yes", {}, false

local function video_id(path)
    return path and (path:match("[?&]v=([%w_-]+)") or path:match("youtu%.be/([%w_-]+)"))
end

local function refill()
    local pos, count = mp.get_property_number("playlist-pos", 0), mp.get_property_number("playlist-count", 0)
    local id = video_id(mp.get_property("path"))
    if not radio or fetching or not id or pos < count - 1 then return end
    fetching = true
    mp.command_native_async({
        name = "subprocess", capture_stdout = true, playback_only = false,
        args = { "yt-dlp", "--no-warnings", "--flat-playlist", "--playlist-end", "25", "--print", "%(id)s %(title)s",
                 "https://www.youtube.com/watch?v=" .. id .. "&list=RD" .. id },
    }, function(_, r)
        fetching = false
        local m3u, n = { "#EXTM3U" }, 0
        for line in ((r and r.stdout) or ""):gmatch("[^\n]+") do
            local vid, title = line:match("^(%S+) (.*)$")
            if vid and not played[vid] and n < 10 then
                played[vid] = true -- also stops the same song being queued twice
                m3u[#m3u + 1] = "#EXTINF:0," .. title
                m3u[#m3u + 1] = "https://www.youtube.com/watch?v=" .. vid
                n = n + 1
            end
        end
        if n > 0 then mp.commandv("loadlist", "memory://" .. table.concat(m3u, "\n"), "append") end
    end)
end

mp.register_event("file-loaded", function()
    local id = video_id(mp.get_property("path"))
    if id then played[id] = true end
    refill()
end)

mp.register_script_message("cmusic-radio", function(on)
    radio = on == "on"
    publish("radio", radio and "on" or "off")
    refill()
end)

-- Lyrics --------------------------------------------------------------------------------
-- `lyrics`: look the current track up on lrclib.net (free, no key). Publishes
-- lyrics-status (loading|ok|none|error), lyrics (plain text) and, for synced lyrics,
-- lyrics-line (the line being sung) and lyrics-lrc ("<seconds>\t<line>" per line).
-- lyrics-offset: how many seconds late the lyrics run on this track, set by hand (a music
-- video often opens with a scene the audio release doesn't have). lyrics-lrc stays as
-- lrclib gave it: readers shift it themselves.
local utils = require "mp.utils"
local lyrics_cache, synced, line_observer = {}, nil, nil
local offsets, offset = {}, 0 -- per track (path), for this mpv session

-- "NƠI NÀY CÓ ANH | OFFICIAL MUSIC VIDEO | SƠN TÙNG M-TP" -> "NƠI NÀY CÓ ANH SƠN TÙNG M-TP"
local function ci(word) return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)) end
local NOISE = { "official music video", "official lyric video", "official video", "official audio", "official mv",
                "music video", "lyric video", "lyrics", "lyric", "visualizer", "audio", "mv", "m/v", "4k", "hd",
                "remastered", "remaster" }
local function clean_title(t)
    -- Some titles arrive decomposed (NFD: a letter, then its accents as combining marks
    -- U+0300–U+036F), which lrclib's search can't match. Lua can't recompose them, but
    -- lrclib matches unaccented text fine, so drop the marks. Composed (NFC) text has none.
    t = t:gsub("\204[\128-\191]", ""):gsub("\205[\128-\175]", "")
    t = " " .. t:gsub("%b()", " "):gsub("%b[]", " "):gsub("【.-】", " "):gsub("｜", " "):gsub("[|/]", " ") .. " "
    for _, w in ipairs(NOISE) do t = t:gsub("%f[%w]" .. ci(w):gsub("/", "%%/"):gsub(" ", "%%s+") .. "%f[%W]", " ") end
    return (t:gsub(" %- ", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function parse_lrc(lrc)
    local lines = {}
    for line in lrc:gmatch("[^\n]+") do
        local m, sec, text = line:match("^%[(%d+):(%d+%.?%d*)%]%s*(.*)$")
        if m then lines[#lines + 1] = { t = tonumber(m) * 60 + tonumber(sec), text = text } end
    end
    return #lines > 0 and lines or nil
end

local function stop_line_observer()
    if line_observer then mp.unobserve_property(line_observer); line_observer = nil end
    synced = nil
    publish("lyrics-line", "")
    publish("lyrics-lrc", "")
end

local function show(entry)
    stop_line_observer()
    publish("lyrics", entry.text or "")
    publish("lyrics-status", entry.status)
    synced = entry.synced
    if not synced then return end
    local lrc = {}
    for _, l in ipairs(synced) do lrc[#lrc + 1] = ("%.2f\t%s"):format(l.t, (l.text:gsub("\t", " "))) end
    publish("lyrics-lrc", table.concat(lrc, "\n"))
    local current
    line_observer = function(_, pos)
        if not pos then return end
        local text = ""
        for _, l in ipairs(synced) do if l.t + offset <= pos + 0.3 then text = l.text else break end end
        if text ~= current then current = text; publish("lyrics-line", text) end
    end
    mp.observe_property("time-pos", "number", line_observer)
end

-- For comparing names: Vietnamese letters folded to plain ASCII, lowercase, punctuation as
-- spaces, padded so a plain find of " name " only matches whole words.
local FOLD = {}
for base, letters in pairs({
    a = "àáạảãâầấậẩẫăằắặẳẵÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ", e = "èéẹẻẽêềếệểễÈÉẸẺẼÊỀẾỆỂỄ", i = "ìíịỉĩÌÍỊỈĨ",
    o = "òóọỏõôồốộổỗơờớợởỡÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ", u = "ùúụủũưừứựửữÙÚỤỦŨƯỪỨỰỬỮ", y = "ỳýỵỷỹỲÝỴỶỸ", d = "đĐ",
}) do
    for ch in letters:gmatch("[\192-\244][\128-\191]*") do FOLD[ch] = base end
end
local function fold(s)
    s = s:gsub("\204[\128-\191]", ""):gsub("\205[\128-\175]", ""):gsub("[\192-\244][\128-\191]*", FOLD)
    return " " .. s:lower():gsub("[%c%p%s]+", " ") .. " "
end

-- Best result: synced lyrics first, then lrclib's own ranking, and only then the closest
-- duration (a music video runs longer than the song, so duration alone picks the wrong
-- song). A result whose song name isn't in the title is another song: better no lyrics.
local function pick(results, duration, title)
    local best, best_score
    title = fold(title)
    for i, r in ipairs(results or {}) do
        local name = fold(clean_title(r.trackName or ""))
        if (r.syncedLyrics or r.plainLyrics) and name ~= "  " and title:find(name, 1, true) then
            local score = (r.syncedLyrics and 0 or 1000) + i * 10
                + math.min(60, math.abs((tonumber(r.duration) or 0) - (duration or 0)))
            if not best or score < best_score then best, best_score = r, score end
        end
    end
    return best
end

-- "THÀNH ĐẠT x ĐÔNG THIÊN ĐỨC" -> "THÀNH ĐẠT": a collab makes the query too specific.
local function main_artist(s)
    return (s:gsub("%s+[xX&]%s.*$", ""):gsub("%s+[fF][eE]?[aA]?[tT]%.?%s.*$", ""):gsub("%s*,.*$", ""))
end

-- Search queries from most to least specific: the whole cleaned title, its first and last
-- "|" segments (song and artist, or a subtitle), the first alone, then the two sides of the
-- first segment's "SONG - ARTIST" (or "ARTIST - SONG") with collab artists dropped,
-- together and each alone.
local function queries_for(title)
    local segs = {}
    -- "｜" is three bytes: inside [] each byte alone would match, splitting letters like "Ờ".
    for seg in title:gsub("｜", "|"):gmatch("[^|]+") do
        if #clean_title(seg) > 1 then segs[#segs + 1] = seg end
    end
    local list, seen = {}, {}
    local function add(q) if q and q ~= "" and not seen[q] then seen[q] = true; list[#list + 1] = q end end
    add(clean_title(title))
    if not segs[1] then return list end
    if #segs > 1 then add(clean_title(segs[1]) .. " " .. clean_title(segs[#segs])) end
    add(clean_title(segs[1]))
    local a, b = segs[1]:gsub(" – ", " - "):gsub(" — ", " - "):match("^(.-)%s+%-%s+(.+)$")
    if a then
        a, b = clean_title(main_artist(a)), clean_title(main_artist(b))
        add(a .. " " .. b); add(a); add(b)
    end
    return list
end

local function lyrics_entry(best, query)
    if not best then return { status = "none", text = query } end
    local entry = { status = "ok", synced = best.syncedLyrics and parse_lrc(best.syncedLyrics) }
    local plain = best.plainLyrics
    if not plain and entry.synced then
        local t = {}
        for _, l in ipairs(entry.synced) do t[#t + 1] = l.text end
        plain = table.concat(t, "\n")
    end
    local name, artist = best.trackName or "", best.artistName or ""
    local head = name:find(artist, 1, true) and name or (name .. " — " .. artist)
    entry.text = head .. "\n\n" .. (plain or "")
    return entry
end

-- Until a track has loaded, media-title is still its URL, which finds nothing: a lookup
-- asked for then (the lyrics plugin asks as soon as a track starts) waits for file-loaded.
local track_loaded, lookup_waiting = false, false

local function lookup()
    local path = mp.get_property("path")
    if lyrics_cache[path] then return show(lyrics_cache[path]) end
    stop_line_observer()
    publish("lyrics-status", "loading")
    if not track_loaded then lookup_waiting = true; return end
    local title, duration = mp.get_property("media-title", ""), mp.get_property_number("duration")
    local queries = queries_for(title)

    local function try(i)
        mp.command_native_async({
            name = "subprocess", capture_stdout = true, playback_only = false,
            args = { "curl", "-sfG", "--max-time", "10", "-A", "cmusic (https://github.com/tungnt1203/cmusic)",
                     "https://lrclib.net/api/search", "--data-urlencode", "q=" .. queries[i] },
        }, function(_, r)
            if mp.get_property("path") ~= path then return end -- the track changed meanwhile
            if not r or r.status ~= 0 then return publish("lyrics-status", "error") end
            local best = pick(utils.parse_json(r.stdout or ""), duration, title)
            if not best and queries[i + 1] then return try(i + 1) end
            local entry = lyrics_entry(best, queries[1])
            if entry.status == "ok" then lyrics_cache[path] = entry end -- "none" may be a blip: retry later
            show(entry)
        end)
    end
    try(1)
end

mp.register_script_message("cmusic-lyrics", lookup)

-- "+5" / "-5": move the lyrics 5 s later / earlier. "5": set the offset. "0": reset.
mp.register_script_message("cmusic-lyrics-offset", function(arg)
    local path, n = mp.get_property("path"), tonumber((arg or ""):match("^[+-]?([%d.]+)$"))
    if not path or not n then return end
    if arg:sub(1, 1) == "-" then n = -n end
    offset = arg:match("^[+-]") and offset + n or n
    offsets[path] = offset ~= 0 and offset or nil
    publish("lyrics-offset", ("%g"):format(offset))
    if line_observer then line_observer(nil, mp.get_property_number("time-pos")) end
end)
mp.register_event("file-loaded", function()
    track_loaded = true
    if lookup_waiting then lookup_waiting = false; lookup() end
end)

mp.register_event("start-file", function()
    track_loaded, lookup_waiting = false, false
    offset = offsets[mp.get_property("path")] or 0
    publish("lyrics-offset", ("%g"):format(offset))
    stop_line_observer()
    publish("lyrics-status", "")
    publish("lyrics", "")
end)

-- History (opt-in: music.sh passes the file only when CMUSIC_HISTORY=1) --------------------
local history_file = mp.get_opt("cmusic-history")
if history_file and history_file ~= "" then
    mp.register_event("file-loaded", function()
        local f = io.open(history_file, "a")
        if not f then return end
        local title = mp.get_property("media-title", ""):gsub("[\t\n]", " ")
        f:write(os.date("%Y-%m-%d %H:%M"), "\t", title, "\t", mp.get_property("path", ""), "\n")
        f:close()
    end)
end

publish("radio", radio and "on" or "off")
set_level(level)
publish("ready", "yes")
