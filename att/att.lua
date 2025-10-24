----------------------------------------------------------------------------------------------------
--  ATTENDANCE ADDON (Ashita v4) — Clean & Simple + Att (launcher)
--  v4.0
--    • Removed Filter UI from /attend
--    • Zone-aware quick buttons (multiple suggestions) under "Close after start"
--    • Suggested buttons show event name only (no prefix text)
--    • Window title "Att" (was "Attend Launcher")
--    • Removed helper text line in /attend
--    • Default delay set to 2s
--    • Robust /att alias parsing (multi-word / quoted names)
--    • Forced event override from /attend → /att (attForcedEventName)
--    • After firing /att, auto-refresh the /attend UI’s zone suggestion
--    • "Write" button in Attendance window (writes without closing)
----------------------------------------------------------------------------------------------------
addon.name      = 'att'
addon.author    = 'Nils, literallywho'
addon.version   = '3.0'
addon.desc      = 'Attendance manager'

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

local zoneRoster            = {}   -- [name] = { jobsMain, jobsSub, zone, zid }
local g_LSMode              = nil  -- 'ls'|'ls2'|nil
local g_SAMode              = false
local selfAttendanceStart   = nil

local isAttendanceWindowOpen = false
local isHelpWindowOpen       = false

local attendanceData        = {}   -- { {name, jobsMain, jobsSub, zone, zid, time}, ... }
local pendingEventName      = nil
local selectedMode          = 'HNM' -- 'HNM'|'Event'
local pendingFilePath       = nil
local pendingLSMessage      = nil
local confirm_commands      = { 'here', 'present', 'herebrother' }

-- SA timer (from resources/satimers.txt)
local saTimerDuration     = 300
local saReminderIntervals = {}

-- Att launcher state
local isAttendLauncherOpen = false
local attendUseLS2         = false
local attendDelaySec       = 2      -- default 2s
local attendCloseOnStart   = true
local attSearchArea        = {}     -- [Event] = "Area" for /sea <area> linkshell

-- Delayed /att after /sea (armed by /attend click; fired in d3d_present)
local pendingAttend = nil  -- { eventName=string, useLS2=bool, fireAt=number }

-- /attend → /att "force event" bridge
local attForcedEventName = nil

-- UI refresh after running /att
local attForceRefreshAt  = nil      -- number (os.clock time) to refresh /attend display
-- cache now supports multiple events for the zone
local attDetectedCache   = nil      -- { evs={ev1,ev2,...}, zone=string, zid=number }

-- Categories derived from creditnames.txt
local attendCategories       = {}   -- [category] = {event1, event2, ...} (file order)
local attendCategoriesOrder  = {}   -- {category1, category2, ...}        (file order)
local eventToCategory        = {}   -- [event] = category
local uncategorizedEvents    = {}   -- {event,...} for events without a category (file order)

----------------------------------------------------------------------------------------------------
-- SCAN LAYOUT (minimal but robust)
----------------------------------------------------------------------------------------------------
local STRIDE_CANDIDATES = { 0x4C, 0x50 }   -- 76, 80
local NAME_OFFSETS       = { 0x08, 0x04 }  -- name field offsets
local ZONE_OFFSETS       = { 0x2C, 0x28 }  -- zone id offsets
local MJ_OFFSETS         = { 0x24, 0x20 }  -- main job id offsets
local SJ_OFFSETS         = { 0x25, 0x21 }  -- sub job id offsets
local NAME_LENGTHS       = { 16, 15 }      -- name lengths to read

----------------------------------------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end

local function sanitize_name(raw)
    if not raw then return '' end
    raw = raw:gsub('%z+$',''):gsub('[\r\n]+','')
    return trim(raw)
end

local function is_plausible_name(s)
    return #s >= 2 and #s <= 15 and (not s:find('[%z\001-\008\011\012\014-\031]'))
end

local function norm(s)
    s = trim(s or ''):lower()
    s = s:gsub("[%s%-%.'’_]+", "")
    return s
end

local function parse_time_string(timeStr)
    if not timeStr then return 0 end
    local minutes, seconds = timeStr:match('^(%d+):(%d+)$')
    if minutes and seconds then return tonumber(minutes) * 60 + tonumber(seconds) end
    local mins = tonumber(timeStr); if mins then return mins * 60 end
    return 0
end

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
    saTimerDuration = (parse_time_string(durationStr) > 0) and parse_time_string(durationStr) or 300
    local intervalSec = (parse_time_string(intervalStr) > 0) and parse_time_string(intervalStr) or 60

    saReminderIntervals = {}
    local nextReminder = intervalSec
    while nextReminder < saTimerDuration do
        table.insert(saReminderIntervals, saTimerDuration - nextReminder)
        nextReminder = nextReminder + intervalSec
    end
end

local function clean_str(str)
    str = AshitaCore:GetChatManager():ParseAutoTranslate(str, true)
    str = str:strip_colors():strip_translate(true)
    while str:endswith('\n') or str:endswith('\r') do
        str = str:trimend('\n'):trimend('\r')
    end
    return str:gsub(string.char(0x07), '\n')
end

-- Always keep GUI list A→Z (ignoring any leading "X ")
local function sortAttendance()
    table.sort(attendanceData, function(a, b)
        local an = (a.name or ''):gsub('^X%s+', ''):lower()
        local bn = (b.name or ''):gsub('^X%s+', ''):lower()
        return an < bn
    end)
end

----------------------------------------------------------------------------------------------------
-- RESOURCE LOADING (zones, jobs, shortnames, creditnames with categories)
----------------------------------------------------------------------------------------------------
local zoneNameToIds = {}  -- normName -> { [zid]=true, ... }

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

    -- creditnames.txt supports category headers: lines like "-- HNMS,"
    -- Event lines remain "Event,Zone[,Area]"
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
            -- Category header? e.g., "-- HNMS," or "-- HNMS"
            local cat = line:match('^%-%-%s*(.-)%s*,%s*$') or line:match('^%-%-%s*(.-)%s*$')
            if cat and cat ~= '' then
                currentCategory = cat
                ensure_category(currentCategory)
            else
                -- Normal entry: "Event,Zone[,Area]" (Zone/Area may be blank)
                local a,b,c = line:match('^([^,]+)%s*,%s*([^,]*)%s*,?%s*(.*)$')
                if a then
                    local ev   = trim(a)
                    local zone = trim(b or '')
                    local area = trim(c or '')

                    -- Build credit maps
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
                    else
                        if (not attSearchArea[ev]) and zone ~= '' then
                            attSearchArea[ev] = zone
                        end
                    end

                    -- Categorize (skip the special helper line "Current Zone")
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

    -- If we have uncategorized events, expose them as a category "Other" (last)
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
-- SCAN CORE (inclusive + overflow)
----------------------------------------------------------------------------------------------------
local function detect_stride(count, listPtr)
    local bestStride, bestScore = STRIDE_CANDIDATES[1], -1
    for _, stride in ipairs(STRIDE_CANDIDATES) do
        local seen, uniq = {}, 0
        for i = 0, math.max(count - 1, 0) do
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
    for i = 0, count do try_index(i) end   -- inclusive last
    try_index(count + 1)                   -- one overflow peek
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
-- CSV WRITE
----------------------------------------------------------------------------------------------------
local function writeAttendanceFile()
    if not pendingFilePath or not pendingEventName then
        print('No pending file or event to write!'); return
    end
    local f = io.open(pendingFilePath, 'a')
    if not f then print('Could not open file: ' .. pendingFilePath); return end
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
    print(string.format('Wrote %d entries to %s', count, pendingFilePath))
end

----------------------------------------------------------------------------------------------------
-- SA CHAT HOOK (!here / !present / !herebrother / !addme)
----------------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'att_sa_packet_in', function(e)
    if not g_SAMode or e.id ~= 0x017 then return end

    local char = struct.unpack('c15', e.data_modified, 0x08 + 1):trimend('\0')
    local raw  = struct.unpack('s',  e.data_modified, 0x17 + 1)
    local msg  = clean_str(raw):lower()

    for _, trigger in ipairs(confirm_commands) do
        if msg:match('^!' .. trigger) then
            local info = zoneRoster[char]
            if not info then return end

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

    -- /att here
    if #args == 2 and args[2]:lower() == 'here' then
        local zid = ashita.memory.read_uint8(ashita.memory.find("FFXiMain.dll", 0, "??", 0x452818, 0))
        local currentZone = attZoneList[zid] or "UnknownZone"

        local matchedEvent = nil
        for eventName, zoneIdSet in pairs(attCreditZoneIds) do
            if zoneIdSet[zid] then matchedEvent = eventName; break end
        end
        if not matchedEvent then
            for eventName, zoneList in pairs(attCreditNames) do
                for _, zone in ipairs(zoneList) do
                    if norm(zone) == norm(currentZone) then matchedEvent = eventName; break end
                end
                if matchedEvent then break end
            end
        end

        if matchedEvent then
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/att ls "%s"', matchedEvent))
        else
            print(string.format("No event found for current zone: %s", currentZone))
        end
        return
    end

    -- Reset state each call
    attendanceData        = {}
    pendingFilePath       = nil
    pendingLSMessage      = nil
    selectedMode          = 'HNM'
    g_LSMode              = nil
    g_SAMode              = false
    selfAttendanceStart   = nil
    zoneRoster            = {}

    -- Parse flags + robust alias capture (handles multi-word/quoted names)
    local lsMode, writeMode, saFlag = nil, nil, false
    local aliasParts = {}
    for i = 2, #args do
        local a = args[i]
        local al = a:lower()
        if al == 'ls' then
            lsMode = 'ls'
        elseif al == 'ls2' then
            lsMode = 'ls2'
        elseif al == 'h' then
            writeMode = 'HNM'
        elseif al == 'e' then
            writeMode = 'Event'
        elseif al == 'sa' then
            saFlag = true
        else
            table.insert(aliasParts, a)
        end
    end
    local alias = nil
    if #aliasParts > 0 then
        alias = table.concat(aliasParts, ' ')
        alias = alias:gsub('^"(.*)"$', '%1')  -- strip surrounding quotes if present
    end
    g_LSMode = lsMode

    -- Resolve event name (FORCED OVERRIDE from /attend takes precedence)
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

    -- Map "Current Zone" by ID (only when actually using "Current Zone")
    local zid = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
    if pendingEventName == 'Current Zone' then
        attCreditNames['Current Zone']    = { attZoneList[zid] or 'UnknownZone' }
        attCreditZoneIds['Current Zone']  = { [zid] = true }
    end

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
        local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
        AshitaCore:GetChatManager():QueueCommand(1,
            prefix..string.format(
                'Self-attendance for %s started. You have %d minutes. Use !here (or !present, !herebrother) to confirm or !addme to opt in.',
                pendingEventName, saTimerDuration / 60
            )
        )
        return
    end

    if lsMode then
        gatherZoneData()
    else
        gatherAllianceData()
    end

    if writeMode then
        selectedMode = writeMode
        local dateStr = os.date('%A %d %B %Y')
        local timeStr = os.date('%H.%M.%S')
        if writeMode == 'HNM' then
            pendingFilePath  = addon.path..'HNM Logs\\'..dateStr..' '..timeStr..'.csv'
            pendingLSMessage = 'HNM Attendance taken for: '..pendingEventName
        else
            pendingFilePath  = addon.path..'Event Logs\\'..dateStr..' '..timeStr..'.csv'
            pendingLSMessage = 'Event Attendance taken for: '..pendingEventName
        end
        writeAttendanceFile()
        if pendingLSMessage then
            local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
            AshitaCore:GetChatManager():QueueCommand(1, prefix..pendingLSMessage)
        end
        return
    end

    sortAttendance()
    isAttendanceWindowOpen = true
end)

-- /attend opens the launcher
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
-- /attend helpers
----------------------------------------------------------------------------------------------------
local function attend_launch_for_event(eventName)
    local area = attSearchArea[eventName]
        or (attCreditNames[eventName] and attCreditNames[eventName][1])
        or ''
    if area == '' then
        print(string.format('[att] No search area found for "%s". Check creditnames.txt (3rd column or at least one zone).', eventName))
        return
    end

    -- FORCE the event for the upcoming /att command (bypasses alias parsing entirely)
    attForcedEventName = eventName

    -- 1) /sea <area> linkshell immediately
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s linkshell', area))

    -- 2) Arm a delayed /att to be executed from d3d_present
    local delaySec = tonumber(attendDelaySec) or 2
    pendingAttend = {
        eventName = eventName,
        useLS2    = attendUseLS2,
        fireAt    = os.clock() + math.max(0, delaySec),
    }

    if attendCloseOnStart then
        isAttendLauncherOpen = false
    end
end

-- Detect ALL matching events for the current zone (ID preferred, fallback name)
local function detect_events_for_current_zone()
    local zid = ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))
    local zname = attZoneList[zid] or 'UnknownZone'

    local evs_by_id = {}
    for eventName, zoneIdSet in pairs(attCreditZoneIds) do
        if zoneIdSet[zid] then table.insert(evs_by_id, eventName) end
    end

    if #evs_by_id > 0 then
        return evs_by_id, zname, zid
    end

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

-- Keep a stable display order for suggested events: by category/file order where possible
local function sort_events_by_category_order(evlist)
    -- Build order map from category lists
    local order = {}
    local idx = 1
    for _, cat in ipairs(attendCategoriesOrder) do
        for _, ev in ipairs(attendCategories[cat] or {}) do
            order[ev] = idx
            idx = idx + 1
        end
    end
    table.sort(evlist, function(a, b)
        local oa = order[a] or 999999
        local ob = order[b] or 999999
        if oa ~= ob then return oa < ob end
        return a < b
    end)
end

-- Update detection cache now
local function update_att_detect_cache()
    local evs, zname, zid = detect_events_for_current_zone()
    if evs and #evs > 1 then sort_events_by_category_order(evs) end
    attDetectedCache = { evs = evs or {}, zone = zname, zid = zid }
end

----------------------------------------------------------------------------------------------------
-- TICK / UI
----------------------------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'att_present_cb', function()
    -- Fire delayed /att from /attend when ready
    if pendingAttend and os.clock() >= pendingAttend.fireAt then
        local lsFlag = pendingAttend.useLS2 and 'ls2' or 'ls'
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/att %s "%s"', lsFlag, pendingAttend.eventName))
        -- Schedule a UI refresh tick (so /attend shows correct zone immediately after)
        attForceRefreshAt = os.clock() + 0.05
        pendingAttend = nil
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
                    local msg = 'Pending confirmation: ' .. table.concat(pending, ', ')
                    local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
                    AshitaCore:GetChatManager():QueueCommand(1, prefix .. msg)
                end
                table.remove(saReminderIntervals, i)
            end
        end

        if elapsed >= saTimerDuration then
            local dateStr = os.date('%A %d %B %Y')
            local timeStr = os.date('%H.%M.%S')
            if selectedMode == 'HNM' then
                pendingFilePath  = addon.path..'HNM Logs\\'..dateStr..' '..timeStr..'.csv'
                pendingLSMessage = 'HNM Attendance taken for: '..pendingEventName
            else
                pendingFilePath  = addon.path..'Event Logs\\'..dateStr..' '..timeStr..'.csv'
                pendingLSMessage = 'Event Attendance taken for: '..pendingEventName
            end
            writeAttendanceFile()
            if pendingLSMessage then
                local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
                AshitaCore:GetChatManager():QueueCommand(1, prefix..pendingLSMessage)
            end
            isAttendanceWindowOpen = false
            g_SAMode               = false
            selfAttendanceStart    = nil
            return
        end
    end

    -- Attendance Window
    if isAttendanceWindowOpen then
        imgui.SetNextWindowSize({1050,600}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendanceWindowOpen }
        if imgui.Begin('Attendance Results', openPtr) then

            if g_SAMode and selfAttendanceStart then
                local elapsed   = os.time() - selfAttendanceStart
                local remaining = math.max(0, saTimerDuration - elapsed)
                imgui.Text(string.format('Time until auto-submit: %02d:%02d',
                    math.floor(remaining/60), remaining%60))
                imgui.Separator()
            end

            if g_SAMode then
                if imgui.Button('Show Pending') then
                    local pending = {}
                    for _, r in ipairs(attendanceData) do
                        if r.name:match('^X ') then table.insert(pending, r.name:sub(3)) end
                    end
                    if #pending > 0 then
                        local msg = 'Pending confirmation: ' .. table.concat(pending, ', ')
                        local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
                        AshitaCore:GetChatManager():QueueCommand(1, prefix .. msg)
                    else
                        print('No one left with X prefix.')
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
                        print(string.format('Added %d new attendees: %s', added, table.concat(addedNames, ', ')))
                    else
                        print('No new attendees added.')
                    end
                    sortAttendance()
                end
                imgui.Separator()
            end

            imgui.Text('Select Mode:') imgui.SameLine()
            if imgui.RadioButton('HNM',    selectedMode=='HNM') then selectedMode='HNM' end
            imgui.SameLine()
            if imgui.RadioButton('Event',  selectedMode=='Event') then selectedMode='Event' end

            imgui.Separator()
            imgui.Text('Attendance for: ' .. (pendingEventName or ''))
            local znames = attCreditNames[pendingEventName]
            imgui.Text('Credit Zones: ' .. (((znames and #znames > 0) and table.concat(znames, ", ")) or "UnknownZone"))
            imgui.Separator()

            -- Sorted attendee list (forward loop; safe removal)
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

            -- Buttons: Write / Write & Close / Cancel (in that order)
            if imgui.Button('Write') then
                local dateStr = os.date('%A %d %B %Y')
                local timeStr = os.date('%H.%M.%S')
                if selectedMode == 'HNM' then
                    pendingFilePath  = addon.path..'HNM Logs\\'..dateStr..' '..timeStr..'.csv'
                    pendingLSMessage = 'HNM Attendance taken for: '..pendingEventName
                else
                    pendingFilePath  = addon.path..'Event Logs\\'..dateStr..' '..timeStr..'.csv'
                    pendingLSMessage = 'Event Attendance taken for: '..pendingEventName
                end
                writeAttendanceFile()
                if pendingLSMessage then
                    local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
                    AshitaCore:GetChatManager():QueueCommand(1, prefix..pendingLSMessage)
                end
                -- keep window open
            end

            imgui.SameLine()

            if imgui.Button('Write & Close') then
                local dateStr = os.date('%A %d %B %Y')
                local timeStr = os.date('%H.%M.%S')
                if selectedMode == 'HNM' then
                    pendingFilePath  = addon.path..'HNM Logs\\'..dateStr..' '..timeStr..'.csv'
                    pendingLSMessage = 'HNM Attendance taken for: '..pendingEventName
                else
                    pendingFilePath  = addon.path..'Event Logs\\'..dateStr..' '..timeStr..'.csv'
                    pendingLSMessage = 'Event Attendance taken for: '..pendingEventName
                end
                writeAttendanceFile()
                if pendingLSMessage then
                    local prefix = (g_LSMode=='ls2') and '/l2 ' or '/l '
                    AshitaCore:GetChatManager():QueueCommand(1, prefix..pendingLSMessage)
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

    -- Att UI (/attend) with categories
    if isAttendLauncherOpen then
        imgui.SetNextWindowSize({600, 560}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendLauncherOpen }
        if imgui.Begin('Att', openPtr) then
            -- Controls
            local ls2Ptr = { attendUseLS2 }
            if imgui.Checkbox('Use LS2', ls2Ptr) then
                attendUseLS2 = ls2Ptr[1]
            end

            imgui.SameLine()

            local delayPtr = { attendDelaySec }
            if imgui.InputInt('Delay (sec)', delayPtr) then
                attendDelaySec = math.max(0, tonumber(delayPtr[1]) or 0)
            end

            local closePtr = { attendCloseOnStart }
            if imgui.Checkbox('Close after start', closePtr) then
                attendCloseOnStart = closePtr[1]
            end

            -- Multiple zone-aware quick action buttons (under controls)
            do
                local evs, zname
                if attDetectedCache then
                    evs, zname = attDetectedCache.evs or {}, attDetectedCache.zone
                else
                    local e2, z2 = detect_events_for_current_zone()
                    evs, zname = e2 or {}, z2
                    if evs and #evs > 1 then sort_events_by_category_order(evs) end
                end

                if evs and #evs > 0 then
                    -- Render one button per suggested event (name only)
                    for idx, ev in ipairs(evs) do
                        if idx > 1 then imgui.SameLine() end
                        if imgui.Button(string.format('%s##attend_suggest_%d', ev, idx)) then
                            attend_launch_for_event(ev)
                        end
                    end
                    imgui.SameLine()
                    imgui.TextDisabled(string.format('Zone: %s', zname or 'UnknownZone'))
                else
                    imgui.TextDisabled(string.format('No event mapping found for current zone.'))
                    imgui.SameLine()
                    imgui.TextDisabled('(Zone: ' .. (zname or 'Unknown') .. ')')
                end
            end

            imgui.Separator()

            -- Category groups (in file order), unfiltered listing
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
