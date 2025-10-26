----------------------------------------------------------------------------------------------------
--  ATTENDANCE ADDON (Ashita v4) — Clean & Simple + Att (launcher)
--  v3.0
--    • Authors: Nils, literallywho
--    • /attend row: [tiny number field] [+] [-] "Delay (sec)" [Refresh] [Use LS2]
--    • Removed "Close after start" feature entirely
--    • Fixed-width, non-scaling delay input; clamps 0..99
--    • Auto-refresh suggestions when the player changes zones; manual Refresh button
----------------------------------------------------------------------------------------------------
addon.name      = 'att'
addon.author    = 'Nils, literallywho'
addon.version   = '3.0'
addon.desc      = 'Attendance manager (clean) with /att launcher + categories'

require('common')
local imgui   = require('imgui')
local chat    = require('chat')
local struct  = require('struct')

----------------------------------------------------------------------------------------------------
-- STATE / RESOURCES
----------------------------------------------------------------------------------------------------
local attZoneList       = {}   -- [zid] = zoneName
local attJobList        = {}   -- [jobId] = abbr
local attShortNames     = {}   -- [alias:lower] = Full Event Name (preserve case)
local attCreditNames    = {}   -- [Event] = { "Zone Name", ... }   (UI display)
local attCreditZoneIds  = {}   -- [Event] = { [zid]=true, ... }     (filtering)
local attSearchArea     = {}   -- [Event] = "Area" for /sea <area> linkshell

local zoneRoster            = {}   -- [name] = { jobsMain, jobsSub, zone, zid }
local attendanceData        = {}   -- { {name, jobsMain, jobsSub, zone, zid, time}, ... }

local g_LSMode              = nil  -- 'ls'|'ls2'|nil
local g_SAMode              = false
local selfAttendanceStart   = nil
local selectedMode          = 'HNM' -- 'HNM'|'Event'

local isAttendanceWindowOpen = false
local isAttendLauncherOpen   = false
local isHelpWindowOpen       = false

-- SA timer (from resources/satimers.txt)
local saTimerDuration     = 300     -- seconds
local saReminderIntervals = {}      -- descending checkpoints (in seconds remaining)
local confirm_commands    = { 'here', 'present', 'herebrother' }

-- Write/announce targets (filled on demand)
local pendingEventName      = nil
local pendingFilePath       = nil
local pendingLSMessage      = nil

-- /attend state
local attendUseLS2       = false
local attendDelaySec     = 2        -- default 2s

-- Delayed /att after /sea (armed by /attend click; fired in d3d_present)
local pendingAttend = nil  -- { eventName=string, useLS2=bool, fireAt=number }

-- /attend → /att "force event" bridge
local attForcedEventName = nil

-- UI refresh after running /att
local attForceRefreshAt  = nil      -- number (os.clock time) to refresh /attend display
local attDetectedCache   = nil      -- { evs={ev1,ev2,...}, zone=string, zid=number }

-- Auto-refresh when the player’s zone changes
local lastDetectedZid    = nil

-- Categories derived from creditnames.txt
local attendCategories       = {}   -- [category] = {event1, event2, ...} (file order)
local attendCategoriesOrder  = {}   -- {category1, category2, ...}        (file order)
local eventToCategory        = {}   -- [event] = category
local uncategorizedEvents    = {}   -- {event,...} for events without a category (file order)

-- Scan layout (robust)
local STRIDE_CANDIDATES = { 0x4C, 0x50 }   -- 76, 80
local NAME_OFFSETS       = { 0x08, 0x04 }  -- name field offsets
local ZONE_OFFSETS       = { 0x2C, 0x28 }  -- zone id offsets
local MJ_OFFSETS         = { 0x24, 0x20 }  -- main job id offsets
local SJ_OFFSETS         = { 0x25, 0x21 }  -- sub job id offsets
local NAME_LENGTHS       = { 16, 15 }      -- name lengths to read

-- Zone name -> zid(s)
local zoneNameToIds = {}  -- normName -> { [zid]=true, ... }

----------------------------------------------------------------------------------------------------
-- STRING HELPERS (binding-safe)
----------------------------------------------------------------------------------------------------
local function trim(s) return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1')) end
local function endswith(s, suf) s=tostring(s or ''); suf=tostring(suf or ''); return suf=='' or s:sub(-#suf)==suf end
local function trimend(s, ch)
    s=tostring(s or '')
    local patt = (ch and ch~='') and (ch:gsub('(%W)','%%%1')) or '%s'
    return (s:gsub('['..patt..']+$',''))
end

local function strip_colors_if_any(s)
    if type(s) ~= 'string' then return '' end
    if s.strip_colors then s = s:strip_colors() end
    if s.strip_translate then s = s:strip_translate(true) end
    s = s:gsub('\031.', ''):gsub('\030.', '')
    return s
end

local function clean_str(str)
    if not str then return '' end
    local cm = AshitaCore and AshitaCore:GetChatManager()
    if cm and cm.ParseAutoTranslate then
        str = cm:ParseAutoTranslate(str, true)
    end
    str = strip_colors_if_any(str)
    while endswith(str, '\n') or endswith(str, '\r') do
        str = trimend(trimend(str, '\n'), '\r')
    end
    return str:gsub(string.char(0x07), '\n')
end

local function norm(s)
    s = trim(s or ''):lower()
    s = s:gsub("[%s%-%.'’_]+", "")
    return s
end

local function is_plausible_name(s)
    s = tostring(s or '')
    return #s >= 2 and #s <= 15 and (not s:find('[%z\001-\008\011\012\014-\031]'))
end

local function sanitize_name(raw)
    if not raw then return '' end
    raw = raw:gsub('%z+$',''):gsub('[\r\n]+','')
    return trim(raw)
end

local function parse_time_string(timeStr)
    if not timeStr then return 0 end
    local minutes, seconds = timeStr:match('^(%d+):(%d+)$')
    if minutes and seconds then return tonumber(minutes) * 60 + tonumber(seconds) end
    local mins = tonumber(timeStr); if mins then return mins * 60 end
    return 0
end

-- tiny helpers (no math.* needed)
local function clamp_0_99(n)
    n = tonumber(n) or 0
    if n < 0 then return 0 end
    if n > 99 then return 99 end
    return n
end

----------------------------------------------------------------------------------------------------
-- SMALL UTILITIES
----------------------------------------------------------------------------------------------------
local function ls_prefix()
    return (g_LSMode == 'ls2') and '/l2 ' or '/l '
end

local function prep_write_targets(mode, eventName)
    local dateStr = os.date('%A %d %B %Y')
    local timeStr = os.date('%H.%M.%S')
    local baseDir, msg
    if mode == 'HNM' then
        baseDir = addon.path .. 'HNM Logs\\'
        msg     = 'HNM Attendance taken for: ' .. eventName
    else
        baseDir = addon.path .. 'Event Logs\\'
        msg     = 'Event Attendance taken for: ' .. eventName
    end
    return (baseDir .. dateStr .. ' ' .. timeStr .. '.csv'), msg
end

local function sortAttendance()
    table.sort(attendanceData, function(a, b)
        local an = (a.name or ''):gsub('^X%s+', ''):lower()
        local bn = (b.name or ''):gsub('^X%s+', ''):lower()
        return an < bn
    end)
end

----------------------------------------------------------------------------------------------------
-- SATimers
----------------------------------------------------------------------------------------------------
local function loadSATimers()
    saTimerDuration = 300
    saReminderIntervals = {}
    local durationStr = "5"
    local intervalStr = "1"

    local filePath = addon.path .. 'resources/satimers.txt'
    local f = io.open(filePath, 'r')
    if f then
        for line in f:lines() do
            local key, val = line:match('^(%a+):%s*(%d+[:%d+]*)$')
            if key and val then
                key = key:lower()
                if key == 'minutes' then durationStr = val
                elseif key == 'interval' then intervalStr = val end
            end
        end
        f:close()
    end
    local dur = parse_time_string(durationStr); if dur <= 0 then dur = 300 end
    local int = parse_time_string(intervalStr); if int <= 0 then int = 60 end

    saTimerDuration     = dur
    saReminderIntervals = {}
    local nextReminder = int
    while nextReminder < dur do
        table.insert(saReminderIntervals, dur - nextReminder)
        nextReminder = nextReminder + int
    end
end

----------------------------------------------------------------------------------------------------
-- RESOURCES: zones, jobs, shortnames, creditnames (with categories)
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'att_load_cb', function()
    -- zones.csv -> "id,name,..."
    for line in io.lines(addon.path .. 'resources/zones.csv') do
        local idx, nm = line:match('^(%d+),%s*(.-),')
        if idx and nm then
            local zid = tonumber(idx)
            attZoneList[zid] = nm
            local key = norm(nm)
            zoneNameToIds[key] = zoneNameToIds[key] or {}
            zoneNameToIds[key][zid] = true
        end
    end

    -- jobs.csv -> "id,abbr,..."
    for line in io.lines(addon.path .. 'resources/jobs.csv') do
        local idx, nm = line:match('^(%d+),%s*(.-),')
        if idx and nm then
            attJobList[tonumber(idx)] = nm
        end
    end

    -- shortnames.txt -> "alias,Full Event Name"
    for line in io.lines(addon.path .. 'resources/shortnames.txt') do
        local alias, fullname = line:match('^(.-),(.*)$')
        if alias and fullname then
            attShortNames[trim(alias):lower()] = trim(fullname)
        end
    end

    -- creditnames.txt:
    --   Category header lines: "-- HNMS," or "-- HNMS"
    --   Event lines: "Event,Zone[,Area]"
    local currentCategory = nil
    local function ensure_category(cat)
        if not attendCategories[cat] then
            attendCategories[cat] = {}
            table.insert(attendCategoriesOrder, cat)
        end
    end

    for raw in io.lines(addon.path .. 'resources/creditnames.txt') do
        local line = trim(raw)
        if line ~= '' then
            local cat = line:match('^%-%-%s*(.-)%s*,%s*$') or line:match('^%-%-%s*(.-)%s*$')
            if cat and cat ~= '' then
                currentCategory = cat
                ensure_category(currentCategory)
            else
                local a,b,c = line:match('^([^,]+)%s*,%s*([^,]*)%s*,?%s*(.*)$')
                if a then
                    local ev   = trim(a)
                    local zone = trim(b or '')
                    local area = trim(c or '')

                    attCreditNames[ev]   = attCreditNames[ev]   or {}
                    attCreditZoneIds[ev] = attCreditZoneIds[ev] or {}

                    if zone ~= '' then
                        table.insert(attCreditNames[ev], zone)
                        local key = norm(zone)
                        if zoneNameToIds[key] then
                            for zid,_ in pairs(zoneNameToIds[key]) do
                                attCreditZoneIds[ev][zid] = true
                            end
                        end
                    end

                    if area ~= '' then
                        attSearchArea[ev] = area
                    elseif (not attSearchArea[ev]) and zone ~= '' then
                        attSearchArea[ev] = zone
                    end

                    if ev ~= 'Current Zone' then
                        if currentCategory then
                            table.insert(attendCategories[currentCategory], ev)
                            eventToCategory[ev] = currentCategory
                        else
                            table.insert(uncategorizedEvents, ev)
                        end
                    end
                end
            end
        end
    end

    if #uncategorizedEvents > 0 then
        attendCategories["Other"] = attendCategories["Other"] or {}
        for _,ev in ipairs(uncategorizedEvents) do
            table.insert(attendCategories["Other"], ev)
            eventToCategory[ev] = "Other"
        end
        table.insert(attendCategoriesOrder, "Other")
    end
end)

----------------------------------------------------------------------------------------------------
-- SCANNING (robust)
----------------------------------------------------------------------------------------------------
local function detect_stride(count, listPtr)
    local bestStride, bestScore = STRIDE_CANDIDATES[1], -1
    for _, stride in ipairs(STRIDE_CANDIDATES) do
        local seen, uniq = {}, 0
        for i = 0, (count > 0 and count - 1 or 0) do
            local entry = listPtr + (i * stride)
            local name = ''
            for _, noff in ipairs(NAME_OFFSETS) do
                for _, nlen in ipairs(NAME_LENGTHS) do
                    local cand = sanitize_name(ashita.memory.read_string(entry + noff, nlen))
                    if is_plausible_name(cand) then name = cand break end
                end
                if name ~= '' then break end
            end
            if name ~= '' and not seen[name] then seen[name] = true; uniq = uniq + 1 end
        end
        if uniq > bestScore then bestScore = uniq; bestStride = stride end
    end
    return bestStride
end

local function read_cell(entry)
    local name = ''
    for _, noff in ipairs(NAME_OFFSETS) do
        for _, nlen in ipairs(NAME_LENGTHS) do
            local cand = sanitize_name(ashita.memory.read_string(entry + noff, nlen))
            if is_plausible_name(cand) then name = cand; break end
        end
        if name ~= '' then break end
    end

    local zid = 0
    for _, zoff in ipairs(ZONE_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + zoff)
        if v ~= nil then zid = v break end
    end

    local mj, sj = 0, 0
    for _, moff in ipairs(MJ_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + moff)
        if v ~= nil then mj = v break end
    end
    for _, soff in ipairs(SJ_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + soff)
        if v ~= nil then sj = v break end
    end
    return name, zid, mj, sj
end

local function is_header_row(name, zid, mj, sj)
    return (name == '' and zid == 0 and mj == 0 and sj == 0)
end

local function scan_inclusive(count, listPtr, stride)
    local out = {}
    local function try_index(i)
        local entry = listPtr + (i * stride)
        local name, zid, mj, sj = read_cell(entry)
        if is_header_row(name, zid, mj, sj) then return end
        if name ~= '' and not out[name] then
            out[name] = { zid = zid, mj = mj, sj = sj }
        end
    end
    for i = 0, count do try_index(i) end
    try_index(count + 1)
    return out
end

local function zid_in_credit(eventName, zid)
    if not eventName then return false end
    local set = attCreditZoneIds[eventName]
    if set and next(set) ~= nil then return set[zid] == true end
    local zname = attZoneList[zid] or 'UnknownZone'
    local list = attCreditNames[eventName]
    if not list then return false end
    for _, s in ipairs(list) do if norm(s) == norm(zname) then return true end end
    return false
end

----------------------------------------------------------------------------------------------------
-- DATA BUILDERS
----------------------------------------------------------------------------------------------------
local function buildCreditRoster()
    zoneRoster = {}
    local base = ashita.memory.read_int32(ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0))
    if base == 0 then print('[att] credit: base=0'); return end

    local baseAddr = base + 12
    local count    = ashita.memory.read_int32(baseAddr)
    local listPtr  = ashita.memory.read_int32(baseAddr + 20)
    if (count or 0) <= 0 or listPtr == 0 then
        print('[att] credit: no list')
        return
    end

    local stride  = detect_stride(count, listPtr)
    local entries = scan_inclusive(count, listPtr, stride)

    local added = 0
    for name, info in pairs(entries) do
        if zid_in_credit(pendingEventName, info.zid) then
            zoneRoster[name] = {
                jobsMain = attJobList[info.mj] or 'NONE',
                jobsSub  = attJobList[info.sj] or 'NONE',
                zone     = attZoneList[info.zid] or 'UnknownZone',
                zid      = info.zid
            }
            added = added + 1
        end
    end
    print(string.format('[att] credit roster: %d eligible', added))
end

local function gatherAllianceData()
    local pm = AshitaCore:GetMemoryManager():GetParty()
    for i = 0, 17 do
        local name = pm:GetMemberName(i)
        if name ~= '' then
            local zid   = pm:GetMemberZone(i)
            local zname = attZoneList[zid] or 'UnknownZone'
            if zid_in_credit(pendingEventName, zid) then
                table.insert(attendanceData, {
                    name     = name,
                    jobsMain = attJobList[pm:GetMemberMainJob(i)] or 'NONE',
                    jobsSub  = attJobList[pm:GetMemberSubJob(i)]  or 'NONE',
                    zone     = zname,
                    zid      = zid,
                    time     = os.date('%H:%M:%S')
                })
            end
        end
    end
    sortAttendance()
end

local function gatherZoneData()
    local base = ashita.memory.read_int32(ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0))
    if base == 0 then print('[att] gather: base=0'); return end

    local baseAddr = base + 12
    local count    = ashita.memory.read_int32(baseAddr)
    local listPtr  = ashita.memory.read_int32(baseAddr + 20)
    if (count or 0) <= 0 or listPtr == 0 then
        print('[att] gather: no list')
        return
    end

    local stride  = detect_stride(count, listPtr)
    local entries = scan_inclusive(count, listPtr, stride)

    local seen = {}
    for _, row in ipairs(attendanceData) do
        seen[row.name:gsub('^X%s+',''):lower()] = true
    end

    local added = 0
    for name, info in pairs(entries) do
        local key = name:lower()
        if not seen[key] and zid_in_credit(pendingEventName, info.zid) then
            table.insert(attendanceData, {
                name     = name,
                jobsMain = attJobList[info.mj] or 'NONE',
                jobsSub  = attJobList[info.sj] or 'NONE',
                zone     = attZoneList[info.zid] or 'UnknownZone',
                zid      = info.zid,
                time     = os.date('%H:%M:%S')
            })
            seen[key] = true
            added = added + 1
        end
    end
    print(string.format('[att] gather: added %d', added))
    sortAttendance()
end

----------------------------------------------------------------------------------------------------
-- WRITE CSV
----------------------------------------------------------------------------------------------------
local function writeAttendanceFile()
    if not pendingFilePath or not pendingEventName then
        print('[att] No pending file or event to write!'); return
    end
    local f = io.open(pendingFilePath, 'a')
    if not f then print('[att] Could not open file: ' .. pendingFilePath); return end
    local count = 0
    for _, row in ipairs(attendanceData) do
        if not row.name:match('^X ') then
            f:write(string.format(
                '%s,%s,%s,%s,%s,%s\n',
                row.name,
                row.jobsMain,
                os.date('%m/%d/%Y'),
                os.date('%H:%M:%S'),
                row.zone,
                pendingEventName
            ))
            count = count + 1
        end
    end
    f:close()
    print(string.format('[att] Wrote %d entries to %s', count, pendingFilePath))
end

----------------------------------------------------------------------------------------------------
-- ZONE/EVENT RESOLUTION + DETECTION CACHE
----------------------------------------------------------------------------------------------------
local function resolve_events_for_current_zone()
    local zid = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
    local zname = attZoneList[zid] or 'UnknownZone'

    -- Prefer ID matches
    local evs_by_id = {}
    for eventName, zoneIdSet in pairs(attCreditZoneIds) do
        if zoneIdSet[zid] then table.insert(evs_by_id, eventName) end
    end
    if #evs_by_id > 0 then
        return evs_by_id, zname, zid
    end

    -- Fallback by normalized zone name
    local nz = norm(zname)
    local evs_by_name = {}
    for eventName, zoneList in pairs(attCreditNames) do
        for _, zone in ipairs(zoneList) do
            if norm(zone) == nz then
                table.insert(evs_by_name, eventName)
                break
            end
        end
    end
    return evs_by_name, zname, zid
end

local function sort_events_by_category_order(evlist)
    local order, idx = {}, 1
    for _, cat in ipairs(attendCategoriesOrder) do
        for _, ev in ipairs(attendCategories[cat] or {}) do
            order[ev] = idx; idx = idx + 1
        end
    end
    table.sort(evlist, function(a, b)
        local oa = order[a] or 999999
        local ob = order[b] or 999999
        if oa ~= ob then return oa < ob end
        return a < b
    end)
end

local function update_att_detect_cache()
    local evs, zname, zid = resolve_events_for_current_zone()
    if evs and #evs > 1 then sort_events_by_category_order(evs) end
    attDetectedCache = { evs = evs or {}, zone = zname, zid = zid }
end

----------------------------------------------------------------------------------------------------
-- /attend helpers
----------------------------------------------------------------------------------------------------
local function attend_launch_for_event(eventName)
    local area = attSearchArea[eventName]
        or (attCreditNames[eventName] and attCreditNames[eventName][1])
        or ''
    if area == '' then
        print(string.format('[att] No search area found for "%s". Check creditnames.txt.', eventName))
        return
    end

    -- Force the event for the upcoming /att (bypasses alias parsing)
    attForcedEventName = eventName

    -- 1) /sea <area> linkshell immediately
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s linkshell', area))

    -- 2) Arm a delayed /att to be executed from d3d_present
    local delaySec = tonumber(attendDelaySec) or 2
    if delaySec < 0 then delaySec = 0 end
    pendingAttend = {
        eventName = eventName,
        useLS2    = attendUseLS2,
        fireAt    = os.clock() + delaySec,
    }

    -- (No more auto-close; "Close after start" was removed)
end

----------------------------------------------------------------------------------------------------
-- PACKET: SA chat (!here / !present / !herebrother / !addme)
----------------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'att_sa_packet_in', function(e)
    if not g_SAMode or e.id ~= 0x017 then return end

    local char = struct.unpack('c15', e.data_modified, 0x08 + 1):gsub('%z+$','')
    local raw  = struct.unpack('s',  e.data_modified, 0x17 + 1)
    local msg  = clean_str(raw):lower()

    -- Confirmations remove 'X ' prefix
    for _, trigger in ipairs(confirm_commands) do
        if msg:match('^!' .. trigger) then
            local zid = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
            if not zid_in_credit(pendingEventName, zid) then return end

            for _, row in ipairs(attendanceData) do
                if row.name == ('X ' .. char) then
                    row.name = char
                    row.time = os.date('%H:%M:%S')
                    sortAttendance()
                    return
                end
            end
        end
    end

    -- Manual opt-in
    if msg:match('^!addme') then
        for _, row in ipairs(attendanceData) do
            if row.name:gsub("^X ", ""):lower() == char:lower() then return end
        end
        local zid   = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
        local zname = attZoneList[zid] or 'UnknownZone'
        table.insert(attendanceData, {
            name     = char,
            jobsMain = 'IN',
            jobsSub  = 'IN',
            zone     = zname,
            zid      = zid,
            time     = os.date('%H:%M:%S')
        })
        sortAttendance()
        return
    end
end)

----------------------------------------------------------------------------------------------------
-- COMMANDS: /att (main), /attend (launcher), /atthelp
----------------------------------------------------------------------------------------------------
ashita.events.register('command', 'att_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/att' then return end
    e.blocked = true

    if #args == 2 and args[2]:lower() == 'help' then
        isHelpWindowOpen = true
        return
    end

    -- /att here → detect event by current zone and launch /att ls "<event>"
    if #args == 2 and args[2]:lower() == 'here' then
        local evs, currentZone = resolve_events_for_current_zone()
        local matchedEvent = evs and evs[1] or nil
        if matchedEvent then
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/att ls "%s"', matchedEvent))
        else
            print(string.format("[att] No event found for current zone: %s", currentZone or 'Unknown'))
        end
        return
    end

    -- Reset state each /att call
    attendanceData        = {}
    pendingFilePath       = nil
    pendingLSMessage      = nil
    selectedMode          = 'HNM'
    g_LSMode              = nil
    g_SAMode              = false
    selfAttendanceStart   = nil
    zoneRoster            = {}

    -- Parse flags + robust alias capture (multi-word/quoted)
    local lsMode, writeMode, saFlag = nil, nil, false
    local aliasParts = {}
    for i = 2, #args do
        local a = args[i]
        local al = a:lower()
        if     al == 'ls'  then lsMode = 'ls'
        elseif al == 'ls2' then lsMode = 'ls2'
        elseif al == 'h'   then writeMode = 'HNM'
        elseif al == 'e'   then writeMode = 'Event'
        elseif al == 'sa'  then saFlag = true
        else
            table.insert(aliasParts, a)
        end
    end
    local alias = nil
    if #aliasParts > 0 then
        alias = table.concat(aliasParts, ' '):gsub('^"(.*)"$', '%1')
    end
    g_LSMode = lsMode

    -- Resolve event (forced override from /attend takes precedence)
    if attForcedEventName and attForcedEventName ~= '' then
        pendingEventName = attForcedEventName
        attForcedEventName = nil
    else
        if alias and alias ~= '' then
            pendingEventName = attShortNames[alias:lower()] or alias
        else
            pendingEventName = 'Current Zone'
        end
    end

    -- Map "Current Zone" dynamically when used
    local zid = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
    if pendingEventName == 'Current Zone' then
        attCreditNames['Current Zone']    = { attZoneList[zid] or 'UnknownZone' }
        attCreditZoneIds['Current Zone']  = { [zid] = true }
    end

    -- SA mode
    if saFlag then
        loadSATimers()
        g_SAMode            = true
        selfAttendanceStart = os.time()
        buildCreditRoster()
        for name, info in pairs(zoneRoster) do
            table.insert(attendanceData, {
                name     = 'X ' .. name,
                jobsMain = info.jobsMain,
                jobsSub  = info.jobsSub,
                zone     = info.zone,
                zid      = info.zid,
                time     = os.date('%H:%M:%S')
            })
        end
        sortAttendance()
        isAttendanceWindowOpen = true
        AshitaCore:GetChatManager():QueueCommand(1,
            ls_prefix() .. string.format(
                'Self-attendance for %s started. You have %d minutes. Use !here (or !present, !herebrother) to confirm or !addme to opt in.',
                pendingEventName, saTimerDuration / 60
            )
        )
        return
    end

    -- Population mode
    if lsMode then
        gatherZoneData()
    else
        gatherAllianceData()
    end

    -- Immediate write mode
    if writeMode then
        selectedMode      = writeMode
        pendingFilePath, pendingLSMessage = prep_write_targets(writeMode, pendingEventName)
        writeAttendanceFile()
        if pendingLSMessage then
            AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. pendingLSMessage)
        end
        return
    end

    sortAttendance()
    isAttendanceWindowOpen = true
end)

ashita.events.register('command', 'att_attend_cmd', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/attend' then return end
    e.blocked = true
    isAttendLauncherOpen = true
end)

ashita.events.register('command', 'att_help_cb', function(e)
    local args = e.command:args()
    if #args >= 1 and args[1]:lower() == '/atthelp' then
        isHelpWindowOpen = true
        e.blocked = true
    end
end)

----------------------------------------------------------------------------------------------------
-- TICK / UI
----------------------------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'att_present_cb', function()
    -- Fire delayed /att from /attend when ready
    if pendingAttend and os.clock() >= pendingAttend.fireAt then
        local lsFlag = pendingAttend.useLS2 and 'ls2' or 'ls'
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/att %s "%s"', lsFlag, pendingAttend.eventName))
        attForceRefreshAt = os.clock() + 0.05
        pendingAttend = nil
    end

    -- Auto-refresh suggestions when the player changes zones
    do
        local zidNow = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
        if zidNow ~= nil then
            if lastDetectedZid == nil then
                lastDetectedZid = zidNow
            elseif zidNow ~= lastDetectedZid then
                lastDetectedZid = zidNow
                update_att_detect_cache()
            end
        end
    end

    -- Run the refresh if scheduled
    if attForceRefreshAt and os.clock() >= attForceRefreshAt then
        update_att_detect_cache()
        attForceRefreshAt = nil
    end

    -- SA reminders + auto-submit
    if g_SAMode and selfAttendanceStart then
        local elapsed = os.time() - selfAttendanceStart

        for i = #saReminderIntervals, 1, -1 do
            if elapsed >= saReminderIntervals[i] then
                local pending = {}
                for _, r in ipairs(attendanceData) do
                    if r.name:match('^X ') then table.insert(pending, r.name:sub(3)) end
                end
                if #pending > 0 then
                    AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. ('Pending confirmation: ' .. table.concat(pending, ', ')))
                end
                table.remove(saReminderIntervals, i)
            end
        end

        if elapsed >= saTimerDuration then
            pendingFilePath, pendingLSMessage = prep_write_targets(selectedMode, pendingEventName)
            writeAttendanceFile()
            if pendingLSMessage then
                AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. pendingLSMessage)
            end
            isAttendanceWindowOpen = false
            g_SAMode               = false
            selfAttendanceStart    = nil
            return
        end
    end

    -- Attendance Results window
    if isAttendanceWindowOpen then
        imgui.SetNextWindowSize({1050,600}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendanceWindowOpen }
        if imgui.Begin('Attendance Results', openPtr) then

            if g_SAMode and selfAttendanceStart then
                local elapsed   = os.time() - selfAttendanceStart
                local remaining = saTimerDuration - elapsed
                if remaining < 0 then remaining = 0 end
                local mins = (remaining - (remaining % 60)) / 60
                local secs = (remaining % 60)
                imgui.Text(string.format('Time until auto-submit: %02d:%02d', mins, secs))
                imgui.Separator()
            end

            if g_SAMode then
                if imgui.Button('Show Pending') then
                    local pending = {}
                    for _, r in ipairs(attendanceData) do
                        if r.name:match('^X ') then table.insert(pending, r.name:sub(3)) end
                    end
                    if #pending > 0 then
                        AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. ('Pending confirmation: ' .. table.concat(pending, ', ')))
                    else
                        print('[att] No one left with X prefix.')
                    end
                end
                imgui.SameLine()
                if imgui.Button('Refresh Data') then
                    buildCreditRoster()
                    local added = 0
                    local addedNames = {}
                    for name, info in pairs(zoneRoster) do
                        local exists = false
                        for _, row in ipairs(attendanceData) do
                            if row.name:gsub("^X ", ""):lower() == name:lower() then exists = true break end
                        end
                        if not exists then
                            table.insert(attendanceData, {
                                name     = name,
                                jobsMain = info.jobsMain,
                                jobsSub  = info.jobsSub,
                                zone     = info.zone,
                                zid      = info.zid,
                                time     = os.date('%H:%M:%S')
                            })
                            table.insert(addedNames, name)
                            added = added + 1
                        end
                    end
                    if added > 0 then
                        print(string.format('[att] Added %d new attendees: %s', added, table.concat(addedNames, ', ')))
                    else
                        print('[att] No new attendees added.')
                    end
                    sortAttendance()
                end
                imgui.Separator()
            end

            imgui.Text('Select Mode:') imgui.SameLine()
            if imgui.RadioButton('HNM',   selectedMode=='HNM')   then selectedMode='HNM'   end
            imgui.SameLine()
            if imgui.RadioButton('Event', selectedMode=='Event') then selectedMode='Event' end

            imgui.Separator()
            imgui.Text('Attendance for: ' .. (pendingEventName or ''))
            local znames = attCreditNames[pendingEventName]
            imgui.Text('Credit Zones: ' .. (((znames and #znames > 0) and table.concat(znames, ", ")) or "UnknownZone"))
            imgui.Separator()

            imgui.Text('Attendees: ' .. #attendanceData)
            imgui.BeginChild('att_list', {0, -50}, true)

            local i = 1
            while i <= #attendanceData do
                local r = attendanceData[i]
                if imgui.Button('Remove##' .. i) then
                    table.remove(attendanceData, i)
                else
                    imgui.SameLine()
                    imgui.Text(string.format('%s (%s | %s/%s)', r.name, r.zone, r.jobsMain, r.jobsSub))
                    i = i + 1
                end
            end

            imgui.EndChild()
            imgui.Separator()

            -- Buttons: Write / Write & Close / Cancel
            if imgui.Button('Write') then
                pendingFilePath, pendingLSMessage = prep_write_targets(selectedMode, pendingEventName)
                writeAttendanceFile()
                if pendingLSMessage then
                    AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. pendingLSMessage)
                end
            end

            imgui.SameLine()

            if imgui.Button('Write & Close') then
                pendingFilePath, pendingLSMessage = prep_write_targets(selectedMode, pendingEventName)
                writeAttendanceFile()
                if pendingLSMessage then
                    AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. pendingLSMessage)
                end
                isAttendanceWindowOpen = false
                openPtr[1] = false
                g_SAMode = false
            end

            imgui.SameLine()

            if imgui.Button('Cancel') then
                isAttendanceWindowOpen = false
                openPtr[1] = false
                g_SAMode = false
            end

            imgui.End()
        end
        isAttendanceWindowOpen = openPtr[1]
        if not isAttendanceWindowOpen then
            g_SAMode = false
        end
    end

    -- Help window
    if isHelpWindowOpen then
        imgui.SetNextWindowSize({600, 300}, ImGuiCond_FirstUseEver)
        local open = { true }
        if imgui.Begin("ATT Addon Help", open) then
            imgui.Text("Commands:")
            imgui.BulletText("/att ls {alias}      — Attendance via LS1")
            imgui.BulletText("/att ls2 {alias}     — Attendance via LS2")
            imgui.BulletText("/att sa {alias}      — Self-attendance")
            imgui.BulletText("/att h               — Write now as HNM")
            imgui.BulletText("/att e               — Write now as Event")
            imgui.BulletText("/att here            — Detect event by your current zone")
            imgui.BulletText("/attend              — Open Att (buttons)")
            imgui.BulletText("/atthelp             — Show this help window")
            imgui.Text(" ")
            imgui.Text("Self-attendance chat:")
            imgui.BulletText("!here / !present / !herebrother — confirm (remove X)")
            imgui.BulletText("!addme                           — opt in manually")
            if imgui.Button("Close##help") then isHelpWindowOpen = false end
            imgui.End()
        end
        if not open[1] then isHelpWindowOpen = false end
    end

    -- Att UI (/attend) with requested row layout
    if isAttendLauncherOpen then
        imgui.SetNextWindowSize({600, 560}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendLauncherOpen }
        if imgui.Begin('Att', openPtr) then
            -- ROW: [short number] [+] [-] "Delay (sec)" [Refresh] [Use LS2]
            do
                local delayPtr = { attendDelaySec }
                imgui.PushItemWidth(32)  -- tiny fixed width (no scaling)
                if imgui.InputInt('##delay', delayPtr, 0, 0) then
                    attendDelaySec = clamp_0_99(delayPtr[1])
                end
                imgui.PopItemWidth()

                imgui.SameLine()
                if imgui.SmallButton('+##delay_inc') then
                    attendDelaySec = clamp_0_99((attendDelaySec or 0) + 1)
                end

                imgui.SameLine()
                if imgui.SmallButton('-##delay_dec') then
                    attendDelaySec = clamp_0_99((attendDelaySec or 0) - 1)
                end

                imgui.SameLine()
                imgui.Text('Delay (sec)')

                imgui.SameLine()
                if imgui.Button('Refresh') then
                    update_att_detect_cache()
                end

                imgui.SameLine()
                local ls2Ptr = { attendUseLS2 }
                if imgui.Checkbox('Use LS2', ls2Ptr) then
                    attendUseLS2 = ls2Ptr[1]
                end
            end

            -- Suggested events (zone-aware)
            do
                local evs, zname
                if attDetectedCache then
                    evs, zname = attDetectedCache.evs or {}, attDetectedCache.zone
                else
                    local e2, z2 = resolve_events_for_current_zone()
                    evs, zname = e2 or {}, z2
                    if evs and #evs > 1 then sort_events_by_category_order(evs) end
                end

                if evs and #evs > 0 then
                    for idx, ev in ipairs(evs) do
                        if idx > 1 then imgui.SameLine() end
                        if imgui.Button(string.format('%s##attend_suggest_%d', ev, idx)) then
                            attend_launch_for_event(ev)
                        end
                    end
                    imgui.SameLine()
                    imgui.TextDisabled(string.format('Zone: %s', zname or 'UnknownZone'))
                else
                    imgui.TextDisabled('No event mapping found for current zone.')
                    imgui.SameLine()
                    imgui.TextDisabled('(Zone: ' .. (zname or 'Unknown') .. ')')
                end
            end

            imgui.Separator()

            -- Category groups (in file order)
            imgui.BeginChild('attend_list', {0, -40}, true)

            for _, cat in ipairs(attendCategoriesOrder) do
                local events = attendCategories[cat] or {}
                if #events > 0 then
                    local header = string.format('%s (%d)', cat, #events)
                    if imgui.CollapsingHeader(header) then
                        for _, ev in ipairs(events) do
                            local area = attSearchArea[ev] or (attCreditNames[ev] and attCreditNames[ev][1]) or ''
                            if imgui.Button(string.format('%s##btn_%s', ev, ev)) then
                                attend_launch_for_event(ev)
                            end
                            if area ~= '' then
                                imgui.SameLine()
                                imgui.TextDisabled(string.format(' /sea %s linkshell', area))
                            end
                        end
                    end
                end
            end

            imgui.EndChild()

            imgui.Separator()
            if imgui.Button('Close##attend') then
                isAttendLauncherOpen = false
                openPtr[1] = false
            end

            imgui.End()
        end
        isAttendLauncherOpen = openPtr[1]
    end
end)
