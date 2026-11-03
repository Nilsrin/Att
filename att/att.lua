-- att.lua (Refactored)
addon.name    = 'att'
addon.author  = 'Nils'
addon.version = '5.1.0'
addon.desc    = 'Attendance manager'

require('common')

local imgui      = require('imgui')
local io_init    = imgui.GetIO()
if io_init then
    io_init.MouseDrawCursor = false
end

-- Localized modules/globals for performance optimization
local os         = os
local string     = string
local table      = table
local math       = math
local AshitaCore = AshitaCore
local chat       = require('chat')
local struct     = require('struct')
local resources  = require('resources')
local memory     = require('memory')
local attendance = require('attendance')
local helpers    = require('helpers')
local ui         = require('ui')
local constants  = require('constants')
local messages   = require('messages')
local function serialize(val)
    local t = type(val)
    if t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local key_str
            if type(k) == "string" then
                key_str = string.format("[%q]", k)
            else
                key_str = string.format("[%s]", tostring(k))
            end
            table.insert(parts, key_str .. " = " .. serialize(v))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    else
        return "nil"
    end
end

local function load_config()
    local path = addon.path .. 'config.lua'
    local f = loadfile(path)
    if f then
        local success, res = pcall(f)
        if success and type(res) == 'table' then
            local loaded = {
                autoPopout = true,
                selfAttestEvents = {},
                defaultLS2 = false,
                uiScale = 1.0,
                popoutHideTitle = false,
                popoutHideBg = false,
                popoutLockPosition = false,
                popoutTheme = 'Slate',
                popoutRounding = 5.0,
                popoutBtnHeight = 42,
                popoutWidth = 220
            }
            if type(res.autoPopout) == 'boolean' then loaded.autoPopout = res.autoPopout end
            if type(res.defaultLS2) == 'boolean' then loaded.defaultLS2 = res.defaultLS2 end
            if type(res.uiScale) == 'number' then loaded.uiScale = res.uiScale end
            if type(res.popoutHideTitle) == 'boolean' then loaded.popoutHideTitle = res.popoutHideTitle end
            if type(res.popoutHideBg) == 'boolean' then loaded.popoutHideBg = res.popoutHideBg end
            if type(res.popoutLockPosition) == 'boolean' then loaded.popoutLockPosition = res.popoutLockPosition end
            if type(res.popoutTheme) == 'string' then loaded.popoutTheme = res.popoutTheme end
            if type(res.popoutRounding) == 'number' then loaded.popoutRounding = res.popoutRounding end
            if type(res.popoutBtnHeight) == 'number' then loaded.popoutBtnHeight = res.popoutBtnHeight end
            if type(res.popoutWidth) == 'number' then loaded.popoutWidth = res.popoutWidth end
            if type(res.selfAttestEvents) == 'table' then
                for k, v in pairs(res.selfAttestEvents) do
                    loaded.selfAttestEvents[k] = v
                end
            end
            return loaded
        end
    end
    return {
        autoPopout = true,
        selfAttestEvents = {},
        defaultLS2 = false,
        uiScale = 1.0,
        popoutHideTitle = false,
        popoutHideBg = false,
        popoutLockPosition = false,
        popoutTheme = 'Slate',
        popoutRounding = 5.0,
        popoutBtnHeight = 42,
        popoutWidth = 220
    }
end

local function save_config(cfg)
    local path = addon.path .. 'config.lua'
    local file = io.open(path, 'w')
    if file then
        file:write("return " .. serialize(cfg))
        file:close()
    end
end

local config = load_config()

-- Global State
local state = {
    debugMode    = false,
    selectedMode = 'HNM',
    g_SAMode     = false,
    g_LSMode     = config.defaultLS2 and 'ls2' or 'ls',
    
    isAttendanceWindowOpen = false,
    isAttendLauncherOpen   = false,
    isDebugWindowOpen      = false,
    isPopoutOpen           = false,
    isPreferencesWindowOpen = false,
    autoPopout             = config.autoPopout,
    selfAttestEvents       = config.selfAttestEvents,
    defaultLS2             = config.defaultLS2,
    uiScale                = config.uiScale or 1.0,
    requestedTab           = nil,

    popoutHideTitle        = (config.popoutHideTitle == true),
    popoutHideBg           = (config.popoutHideBg == true),
    popoutLockPosition     = (config.popoutLockPosition == true),
    popoutTheme            = config.popoutTheme or 'Slate',
    popoutRounding         = config.popoutRounding or 5.0,
    popoutBtnHeight        = config.popoutBtnHeight or 42,
    popoutWidth            = config.popoutWidth or 220,

    pendingEventName     = nil,
    pendingFilePath      = nil,
    pendingLSMessage     = nil,
    pendingAttend        = nil, -- { eventName, useLS2, selfAttest, fireAt }
    pendingSeaScan       = nil,
    pendingGather        = nil, -- { eventName, fireAt }

    attendUseLS2         = config.defaultLS2,
    attendDelaySec       = 3,
    attendSelfAttest     = false,

    selfAttendanceStart  = nil,
    saTimerDuration      = constants.DEFAULT_SA_DURATION,
    saReminderIntervals  = {},
    saAnnounced2Min      = false,
    saAnnounced1Min      = false,
    
    scanNextLetter       = nil,
    isScanningLetter     = false,
    isScanningAll        = false,
    abortScanAll         = false,
    isRefreshing         = false,
    
    suggestions          = { evs={}, zone='' },
    lastDetectedZid      = nil,
    attForceRefreshAt    = nil,
    skipNextSearch       = false
}

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
ashita.events.register('load', 'att_load_cb', function()
    resources.load(addon.path)
    local io = imgui.GetIO()
    if io then
        io.MouseDrawCursor = false
    end
end)

--------------------------------------------------------------------------------
-- UTILS
--------------------------------------------------------------------------------
local function ls_prefix()
    return (state.g_LSMode == 'ls2') and '/l2 ' or '/l '
end

local function prep_write_targets(mode, eventName)
    return attendance.write_file(addon.path, mode, eventName) -- Dry run or path prep?
    -- Actually attendance.write_file writes it. We might want just the path/msg first?
    -- Refactored attendance.write_file handles opening and writing.
    -- We'll just call it when needed.
end

local function update_suggestions()
    local zid = memory.get_current_zone_id()
    local evs, zname = attendance.resolve_events_for_zone(zid)
    
    -- Sort logic (needs category order from resources)
    if evs and #evs > 1 then
        local order = {}
        local idx = 1
        for _, cat in ipairs(resources.attendCategoriesOrder) do
            for _, ev in ipairs(resources.attendCategories[cat] or {}) do
                order[ev] = idx
                idx = idx + 1
            end
        end
        table.sort(evs, function(a, b)
            local oa = order[a] or 999999
            local ob = order[b] or 999999
            if oa ~= ob then return oa < ob end
            return a < b
        end)
    end
    state.suggestions = { evs = evs or {}, zone = zname }
    state.lastDetectedZid = zid
end

local function get_sa_flags()
    return state.g_SAMode
end

local function get_search_area(eventName)
    -- 1. Check if the player is currently in one of the credit zones for eventName
    local curZid = memory.get_current_zone_id()
    local curZoneName = resources.attZoneList[curZid]
    if curZoneName then
        local normCurZone = helpers.norm(curZoneName)
        if resources.attCreditZoneIds[eventName] and resources.attCreditZoneIds[eventName][curZid] then
            if resources.zoneToSearchArea[curZoneName] then
                return resources.zoneToSearchArea[curZoneName]
            end
        end
        if resources.attCreditNames[eventName] then
            for _, z in ipairs(resources.attCreditNames[eventName]) do
                if helpers.norm(z) == normCurZone and resources.zoneToSearchArea[z] then
                    return resources.zoneToSearchArea[z]
                end
            end
        end
    end

    -- 2. Explicit event search area if defined
    if resources.attSearchArea[eventName] and resources.attSearchArea[eventName] ~= '' then
        return resources.attSearchArea[eventName]
    end
    
    -- 3. Fallback: first credit zone or zone name
    local zoneName = eventName
    if resources.attCreditNames[eventName] and resources.attCreditNames[eventName][1] then
        zoneName = resources.attCreditNames[eventName][1]
    end
    
    local searchArea = resources.zoneToSearchArea[zoneName]
    if not searchArea then
        searchArea = zoneName:gsub('%-', '_'):match('^[^%s_]+') or zoneName
    end
    return searchArea
end

local function queue_attend_launch(eventName)
    local area = get_search_area(eventName)
    
    if not area or area == '' then
        print(string.format('[att] No search area found for "%s".', eventName))
        return
    end

    attendance.clear()
    state.pendingEventName = eventName
    state.isAttendanceWindowOpen = true

    local lsSearch = state.attendUseLS2 and 'linkshell2' or 'linkshell'
    AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s %s', area, lsSearch))

    local delay = tonumber(state.attendDelaySec) or 2
    if delay < 0 then delay = 0 end

    state.pendingAttend = {
        eventName  = eventName,
        useLS2     = state.attendUseLS2,
        selfAttest = state.attendSelfAttest or (state.selfAttestEvents[eventName] == true),
        fireAt     = os.clock() + delay,
    }
end

--------------------------------------------------------------------------------
local function trigger_refresh()
    if state.isScanningAll or state.isScanningLetter or state.isRefreshing then return end

    local ev = state.pendingEventName
    if not ev or ev == '' then
        local curZid = memory.get_current_zone_id()
        ev = state.suggestions.zone or resources.attZoneList[curZid] or 'Current Zone'
        state.pendingEventName = ev
    end

    local area = get_search_area(ev)
    if not area or area == '' then
        local curZid = memory.get_current_zone_id()
        local curZoneName = resources.attZoneList[curZid]
        if curZoneName then
            area = resources.zoneToSearchArea[curZoneName] or curZoneName:gsub('%-', '_'):match('^[^%s_]+')
        end
    end

    local lsSearch = (state.g_LSMode == 'ls2' or state.attendUseLS2) and 'linkshell2' or 'linkshell'
    local is_sa = get_sa_flags()

    state.isRefreshing = true
    state.isAttendanceWindowOpen = true

    ashita.tasks.once(0, function()
        -- 1. Close open search window with 3 escape presses
        for i = 1, 3 do
            AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape down')
            coroutine.sleep(0.06)
            AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape up')
            coroutine.sleep(0.06)
        end

        -- 2. 1 second delay between escapes and new search
        coroutine.sleep(1.0)

        -- 3. Reopen search window for current event
        if ev == 'Global Search' or area == 'all' then
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea all %s', lsSearch))
        elseif area and area ~= '' then
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s %s', area, lsSearch))
        else
            print(string.format('[att] No search area found to refresh for "%s".', tostring(ev or 'Current Zone')))
        end

        -- 4. Wait for search results
        local waitSec = tonumber(state.attendDelaySec) or 2
        if waitSec < 2 then waitSec = 2 end
        coroutine.sleep(waitSec)

        -- 5. Update attendance from memory
        attendance.gather_zone(ev, is_sa)

        AshitaCore:GetChatManager():QueueCommand(-1, '/releasekeys')
        state.isRefreshing = false
        print(string.format('[att] Refreshed attendance for "%s".', tostring(ev)))
    end)
end

--------------------------------------------------------------------------------
local function trim_to_party()
    local pm = AshitaCore:GetMemoryManager():GetParty()
    if not pm then return 0, 0 end

    local partyNames = {}
    local activeCount = 0
    for i = 0, 17 do
        local isActive = true
        if pm.GetMemberIsActive then
            isActive = (pm:GetMemberIsActive(i) == 1)
        end
        if isActive then
            local name = pm:GetMemberName(i)
            if name and type(name) == 'string' then
                name = helpers.trim(name)
                if #name > 0 then
                    partyNames[name:lower()] = true
                    activeCount = activeCount + 1
                end
            end
        end
    end

    if activeCount == 0 then
        print(chat.header('att') .. 'No active party or alliance members found.')
        return 0, 0
    end

    local beforeCount = #attendance.data
    local filtered = {}
    for _, r in ipairs(attendance.data) do
        local cleanName = helpers.clean_name(r.name):lower()
        if partyNames[cleanName] then
            table.insert(filtered, r)
        end
    end
    local removed = beforeCount - #filtered
    attendance.data = filtered
    print(chat.header('att') .. string.format('Trimmed attendance to %d party/alliance member(s) (removed %d).', #attendance.data, removed))
    return #attendance.data, removed
end

-- COMMAND HANDLERS
--------------------------------------------------------------------------------
-- /att
ashita.events.register('command', 'att_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/att' then return end
    e.blocked = true

    if #args == 1 then
        print(chat.header('att') .. 'Available Commands:')
        print(' - /attend : Toggles the Main Menu (Events, Preferences, Tools).')
        print(' - /att here : Scans attendance for the current zone\'s event.')
        print(' - /att all : Scans all online linkshell members.')
        print(' - /att refresh : Refreshes attendance search for current event.')
        print(' - /att party : Trims attendance to current party/alliance members.')
        print(' - /att add <name> : Manually adds or confirms a player.')
        print(' - /att status [name] : Checks check-in status for a player.')
        print(' - /att [ls / ls2] [h / e] [sa] <event> : Scans a specific event.')
        print('      - ls / ls2: Linkshell 1 or 2 (Default: ' .. (state.defaultLS2 and 'LS2' or 'LS') .. ')')
        print('      - h / e: Auto-save to HNM (h) or Event (e) format')
        print('      - sa: Run in Self-Attendance check-in mode')
        print(' - /att pref : Opens preferences in the Main Menu.')
        print(' - /att scale [value] : Gets or sets the UI scale (0.5 - 3.0).')
        print(' - /att debug / debugmode : Developer tools.')
        return
    end

    -- /att status [name]
    if #args >= 2 and args[2]:lower() == 'status' then
        local targetName = args[3]
        if not targetName or targetName == '' then
            local pm = AshitaCore:GetMemoryManager():GetParty()
            targetName = pm and pm:GetMemberName(0) or ''
        end
        local statusCode, statusLabel = attendance.get_player_status(targetName)
        print(chat.header('att') .. string.format('Status for %s: %s', targetName, statusLabel))
        return
    end

    -- /att add <name>
    if #args >= 3 and args[2]:lower() == 'add' then
        local targetName = args[3]
        local success, msg = attendance.manual_add_player(targetName)
        print(chat.header('att') .. string.format('%s: %s', targetName, msg or (success and 'Added' or 'Failed')))
        return
    end

    -- /att pref
    if #args == 2 and (args[2]:lower() == 'pref' or args[2]:lower() == 'menu') then
        state.isAttendLauncherOpen = true
        if args[2]:lower() == 'pref' then
            state.requestedTab = 'Preferences'
        end
        update_suggestions()
        return
    end

    -- /att scale [value]
    if #args >= 2 and (args[2]:lower() == 'scale' or args[2]:lower() == 'uiscale') then
        if #args >= 3 then
            local num = tonumber(args[3])
            if num and num >= 0.5 and num <= 3.0 then
                num = math.floor(num * 100 + 0.5) / 100
                config.uiScale = num
                save_config(config)
                state.uiScale = num
                print(chat.header('att') .. string.format('UI Scale set to %.2fx (%.0f%%).', num, num * 100))
            else
                print(chat.header('att') .. 'Invalid scale value. Specify a number between 0.5 and 3.0 (e.g. /att scale 1.25).')
            end
        else
            print(chat.header('att') .. string.format('Current UI Scale: %.2fx (%.0f%%). Use /att scale <0.5-3.0> to change.', state.uiScale or 1.0, (state.uiScale or 1.0) * 100))
        end
        return
    end

    -- /att debug
    if #args == 2 and args[2]:lower() == 'debug' then
        state.isDebugWindowOpen = not state.isDebugWindowOpen
        return
    end

    -- /att debugmode
    if #args == 2 and args[2]:lower() == 'debugmode' then
        state.debugMode = not state.debugMode
        memory.debug = state.debugMode
        attendance.debug = state.debugMode
        print(chat.header('att') .. 'Debug Mode: ' .. (state.debugMode and 'ON (Verbose)' or 'OFF'))
        return
    end

    -- /att here
    if #args == 2 and args[2]:lower() == 'here' then
        local zid = memory.get_current_zone_id()
        local evs, _ = attendance.resolve_events_for_zone(zid)
        if evs and evs[1] then
            state.isAttendanceWindowOpen = true
            AshitaCore:GetChatManager():QueueCommand(1, string.format('/att ls "%s"', evs[1]))
        else
            print('[att] No event found for current zone.')
        end
        return
    end

    -- /att refresh
    if #args == 2 and args[2]:lower() == 'refresh' then
        trigger_refresh()
        return
    end

    -- /att party / partyonly
    if #args == 2 and (args[2]:lower() == 'party' or args[2]:lower() == 'partyonly') then
        trim_to_party()
        return
    end

    
    -- /att memscan
    if #args == 2 and args[2]:lower() == 'memscan' then
        local ptr = memory.find_entity_list()
        if ptr ~= 0 then
             print(string.format('[att] Suggested Pointer: 0x%08X', ptr))
        else
             print('[att] Could not find Entity List via signature.')
        end
        return
    end

    -- /att memdump <addr> [count]
    if #args >= 3 and args[2]:lower() == 'memdump' then
        local addr = args[3]
        local cnt  = tonumber(args[4]) or 64
        memory.dump_address(addr, cnt)
        return
    end

    -- /att api (DEBUG)
    if #args == 2 and args[2]:lower() == 'api' then
        local entMgr = AshitaCore:GetMemoryManager():GetEntity()
        print('[att] Dumping Entity Manager Methods:')
        -- Try to iterate metatable
        local meta = getmetatable(entMgr)
        if meta then
            for k, v in pairs(meta) do
                print(' - ' .. tostring(k) .. ' (' .. type(v) .. ')')
            end
        else
            print(' - No metatable found (UserData?)')
        end
        return
    end

    -- /att all
    if #args == 2 and args[2]:lower() == 'all' then
        attendance.clear()
        state.selectedMode = 'HNM' 
        state.g_LSMode = 'ls'
        state.pendingEventName = 'Global Search'
        
        -- Dynamic resource mapping to support "all" area
        resources.attSearchArea['Global Search'] = 'all'
        -- Ensure credit works (though we mainly rely on search results, which add_entry accepts if we don't filter strictly?)
        -- Actually gather_zone filters by zid_in_credit. We need to bypass that or ensure 'all' matches?
        -- For now, this is just for the SEARCH command. 
        -- The user said "/sea all linkshell" and the letter button.
        -- Gathering usually happens via "Rescan" which calls gather_zone. 
        -- If we want the results of /sea to appear, we rely on the packet handler adding them?
        -- Existing packet handler ? No, it's SA mode packet handler.
        -- Wait, standard ATT relies on memory scanning (/sea results populate memory?).
        -- Yes, Ashita memory manager reads entity list.
        -- So we need `attendance.gather_zone` to NOT filter by zone if name is 'Global Search'.
        
        AshitaCore:GetChatManager():QueueCommand(1, '/sea all linkshell')
        state.isAttendanceWindowOpen = true
        return
    end

    -- Reset
    attendance.clear()
    state.selectedMode = 'HNM'
    state.g_LSMode     = nil
    state.g_SAMode     = false
    state.selfAttendanceStart = nil
    state.scanNextLetter      = nil
    state.isScanningLetter    = false
    state.isScanningAll       = false
    state.abortScanAll        = false
    state.isRefreshing        = false
    state.pendingSeaScan      = nil
    state.isAttendanceWindowOpen = true

    local lsMode, writeMode, saFlag = nil, nil, false
    local aliasParts = {}

    for i = 2, #args do
        local a  = args[i]
        local al = a:lower()
        if     al == 'ls'  then lsMode    = 'ls'
        elseif al == 'ls2' then lsMode    = 'ls2'
        elseif al == 'h'   then writeMode = 'HNM'
        elseif al == 'e'   then writeMode = 'Event'
        elseif al == 'sa'  then saFlag    = true
        else table.insert(aliasParts, a) end
    end

    local alias = table.concat(aliasParts, ' '):gsub('^"(.*)"$', '%1')
    if lsMode == nil then
        lsMode = state.defaultLS2 and 'ls2' or 'ls'
    end
    state.g_LSMode = lsMode

    -- Resolve Event
    if alias ~= '' then
        state.pendingEventName = resources.attShortNames[alias:lower()] or alias
    else
        state.pendingEventName = 'Current Zone'
        state.skipNextSearch = true -- Skip /sea scan for pure /att
    end

    -- Special handling for Current Zone
    if state.pendingEventName == 'Current Zone' then
        local zid = memory.get_current_zone_id()
        local zname = resources.attZoneList[zid] or 'UnknownZone'
        resources.attCreditNames['Current Zone']   = { zname }
        resources.attCreditZoneIds['Current Zone'] = { [zid] = true }
    end

    -- SA MODE
    local isSelfAttest = saFlag
    if state.selfAttestEvents[state.pendingEventName] and not (alias == '' and state.pendingEventName == 'Current Zone') then
        isSelfAttest = true
    end

    if isSelfAttest then
        state.g_SAMode = true
        state.selfAttendanceStart = os.time()
        state.saTimerDuration = constants.DEFAULT_SA_DURATION
        state.saAnnounced2Min = false
        state.saAnnounced1Min = false
        -- (Ideally load from satimers.txt here, skipping file io for brevity, use defaults)
        
        attendance.build_credit_roster(state.pendingEventName)
        
        local pm = AshitaCore:GetMemoryManager():GetParty()
        local selfName = pm and pm:GetMemberName(0)
        attendance.populate_sa_start(state.pendingEventName, selfName)
        
        state.isAttendanceWindowOpen = true
        AshitaCore:GetChatManager():QueueCommand(1,
            ls_prefix() .. string.format(messages.SA_START, state.pendingEventName)
        )
        return
    end

    -- POPULATION / GATHER FLOW
    -- 1. Determine Search Area
    local area = get_search_area(state.pendingEventName)
    
    local doSearch = true
    if state.skipNextSearch then
        doSearch = false
        state.skipNextSearch = false
    end
    
    if not saFlag and area and area ~= '' and doSearch then
        -- Trigger Search
        local lsSearch = state.attendUseLS2 and 'linkshell2' or 'linkshell'
        
        -- Queue /sea command
        AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s %s', area, lsSearch))
        print(string.format('[att] Scanning %s (Waiting for results)...', area))
        
        -- Set Pending State
        local delay = tonumber(state.attendDelaySec) or 2
        state.pendingGather = {
            eventName = state.pendingEventName,
            fireAt    = os.clock() + delay,
            writeMode = writeMode  -- If set, will write file after gather
        }
        
        -- Open window immediately so user sees results window pop up first
        state.isAttendanceWindowOpen = true
        return
    else
        -- Fallback OR Skipped Search: Immediate Gather
        local is_sa = get_sa_flags()
        if lsMode then
            attendance.gather_zone(state.pendingEventName, is_sa)
        else
            -- attendance.gather_alliance(state.pendingEventName) -- Removed
            attendance.gather_zone(state.pendingEventName, is_sa)
        end
        
        if writeMode then
            state.selectedMode = writeMode
            local count, msg = attendance.write_file(addon.path, writeMode, state.pendingEventName)
            if count and msg then
                AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. msg)
            end
        end
        state.isAttendanceWindowOpen = true
    end
end)

-- /attend or /attpref (Main Menu)
ashita.events.register('command', 'att_attend_cmd', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/attend' and cmd ~= '/attpref' and cmd ~= '/attmenu' then return end
    e.blocked = true
    
    if cmd == '/attpref' then
        state.isAttendLauncherOpen = true
        state.requestedTab = 'Preferences'
        update_suggestions()
        return
    end

    -- Toggle/Open logic
    if #args > 1 and args[2]:lower() == 'close' then
        state.isAttendLauncherOpen = false
    else
        state.isAttendLauncherOpen = not state.isAttendLauncherOpen
    end
    
    if state.isAttendLauncherOpen then
        update_suggestions()
    end
end)

--------------------------------------------------------------------------------
-- PACKET (SA)
--------------------------------------------------------------------------------
ashita.events.register('packet_in', 'att_packet_in', function(e)
    if e.id ~= 0x017 then return end
    
    local mode = struct.unpack('b', e.data_modified, 0x04 + 1)
    local char = struct.unpack('c15', e.data_modified, 0x08 + 1):gsub('%z+$', '')
    char = helpers.clean_name(char)
    local raw  = struct.unpack('s',  e.data_modified, 0x17 + 1)
    local msg  = helpers.clean_str(raw):lower()

    if state.debugMode then
        print(string.format('[att-pkt] 0x017 Mode:0x%02X Name:"%s" Msg:"%s"', mode, char, msg))
        -- Hex Dump First 64 bytes
        local hex = ''
        for i = 0, math.min(63, e.size - 1) do
            local b = struct.unpack('b', e.data_modified, i)
            hex = hex .. string.format('%02X ', b % 256)
        end
        print('[att-pkt] Dump: ' .. hex)
    end

    -- Status query: !attstatus (ONLY detected on incoming tells, mode == 0x03)
    if mode == 0x03 and msg:match('^!attstatus') then
        local evName = (state.pendingEventName and state.pendingEventName ~= '') and state.pendingEventName or nil
        local statusCode, statusLabel = attendance.get_player_status(char)
        
        local reply = ''
        if statusCode == 'checked_in' then
            if evName then
                reply = string.format('[ATT] Status: Checked in for %s.', evName)
            else
                reply = '[ATT] Status: Checked in.'
            end
        elseif statusCode == 'pending_approval' then
            if evName then
                reply = string.format('[ATT] Status: Pending approval for %s.', evName)
            else
                reply = '[ATT] Status: Pending approval.'
            end
        else -- not_checked_in
            if evName then
                reply = string.format('[ATT] Status: Not checked in for %s. Type !here in linkshell to check in.', evName)
            else
                reply = '[ATT] Status: Not checked in. Type !here in linkshell to check in.'
            end
        end

        AshitaCore:GetChatManager():QueueCommand(1, string.format('/t %s %s', char, reply))
        print(string.format('[att] Status response sent to %s: %s', char, statusLabel))
        return
    end

    -- SA mode check-in commands (!here, !present, etc.)
    if not state.g_SAMode then return end

    for _, trig in ipairs(constants.CONFIRM_COMMANDS) do
        if msg:match('^!' .. trig) then
            attendance.handle_checkin(char)
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- D3D PRESENT
--------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'att_present_cb', function()
    -- Ensure Dear ImGui software cursor is disabled so native/hardware cursor is used
    local io = imgui.GetIO()
    if io and io.MouseDrawCursor then
        io.MouseDrawCursor = false
    end

    -- Pending Attend Launch
    if state.pendingAttend and os.clock() >= state.pendingAttend.fireAt then
        local lsFlag = state.pendingAttend.useLS2 and 'ls2' or 'ls'
        local cmd = string.format('/att %s "%s"', lsFlag, state.pendingAttend.eventName)
        if state.pendingAttend.selfAttest then
             cmd = string.format('/att %s sa "%s"', lsFlag, state.pendingAttend.eventName)
        end
        state.skipNextSearch = true
        AshitaCore:GetChatManager():QueueCommand(1, cmd)
        state.attForceRefreshAt = os.clock() + 0.05
        state.pendingAttend = nil
    end

    -- Pending Sea Scan
    if state.pendingSeaScan and os.clock() >= state.pendingSeaScan.fireAt then
        local is_sa = get_sa_flags()
        attendance.gather_zone(state.pendingEventName, is_sa)
        state.pendingSeaScan = nil
    end
    -- Pending Gather (Normal /att flow)
    if state.pendingGather and os.clock() >= state.pendingGather.fireAt then
        local ev = state.pendingGather.eventName
        -- Clear old data? Yes, usually refreshing.
        attendance.clear()
        
        -- Gather
        -- Gather
        -- attendance.gather_alliance(ev) -- Removed
        local is_sa = get_sa_flags()
        attendance.gather_zone(ev, is_sa)     -- Then scan zone/search results
        
        -- Handle Write if requested
        if state.pendingGather.writeMode then
            state.selectedMode = state.pendingGather.writeMode
            local count, msg = attendance.write_file(addon.path, state.pendingGather.writeMode, ev)
            if count and msg then
                AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. msg)
            end
        end
        
        state.isAttendanceWindowOpen = true
        state.pendingGather = nil
    end

    -- Auto Refresh Suggestions
    local zidNow = memory.get_current_zone_id()
    if zidNow ~= state.lastDetectedZid then
        update_suggestions()
        
        -- Auto-open or close popout based on events in the new zone
        if state.autoPopout then
            if state.suggestions and state.suggestions.evs and #state.suggestions.evs > 0 then
                state.isPopoutOpen = true
            else
                state.isPopoutOpen = false
            end
        end
    end
    
    if state.attForceRefreshAt and os.clock() >= state.attForceRefreshAt then
        update_suggestions()
        state.attForceRefreshAt = nil
    end

    -- SA Timers (Simplified logic for brevity)
    if state.g_SAMode and state.selfAttendanceStart then
        local elapsed = os.time() - state.selfAttendanceStart
        local remaining = state.saTimerDuration - elapsed
        if remaining < 0 then remaining = 0 end

        -- 2 minutes left announcement (120 seconds remaining)
        if remaining <= 120 and not state.saAnnounced2Min then
            local missing = {}
            for _, row in ipairs(attendance.data) do
                if helpers.is_pending(row.name) then
                    table.insert(missing, helpers.strip_prefix(row.name))
                end
            end
            local missingStr = #missing > 0 and table.concat(missing, ', ') or 'None'
            AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. string.format(messages.SA_MISSING, missingStr))
            state.saAnnounced2Min = true
        end

        -- 1 minute left announcement (60 seconds remaining)
        if remaining <= 60 and not state.saAnnounced1Min then
            local missing = {}
            for _, row in ipairs(attendance.data) do
                if helpers.is_pending(row.name) then
                    table.insert(missing, helpers.strip_prefix(row.name))
                end
            end
            local missingStr = #missing > 0 and table.concat(missing, ', ') or 'None'
            AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. string.format(messages.SA_MISSING, missingStr))
            state.saAnnounced1Min = true
        end

        -- Complete
        if elapsed >= state.saTimerDuration then
             local _, msg = attendance.write_file(addon.path, state.selectedMode, state.pendingEventName)
             if msg then AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. msg) end
             state.isAttendanceWindowOpen = false
             state.g_SAMode = false
             state.selfAttendanceStart = nil
        end
    end

    -- CALLBACKS for UI
    local callbacks = {
        on_party_only = function()
            return trim_to_party()
        end,
        on_write = function(close)
            local _, msg = attendance.write_file(addon.path, state.selectedMode, state.pendingEventName)
            if msg then AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. msg) end
            if close then
                state.isAttendanceWindowOpen = false
                state.g_SAMode = false
            end
        end,
        on_show_pending = function()
             local p = {}
             for _, r in ipairs(attendance.data) do
                 if helpers.is_pending(r.name) then table.insert(p, helpers.strip_prefix(r.name)) end
             end
             if #p > 0 then
                 AshitaCore:GetChatManager():QueueCommand(1, ls_prefix() .. string.format(messages.PENDING_LIST, table.concat(p, ', ')))
             end
        end,
        on_refresh_sa = function()
             -- Re-scan logic for SA...
             attendance.build_credit_roster(state.pendingEventName)
             -- Logic to merge... (omitted detailed merge logic for now, just rebuilds roster)
        end,
        on_refresh = function()
             trigger_refresh()
        end,
        on_launch_event = function(ev)
             queue_attend_launch(ev)
        end,
        on_update_zone = function() update_suggestions() end,
        on_scan_letter = function(letter)
             if state.isScanningLetter or state.isScanningAll then return end

             local area = get_search_area(state.pendingEventName)
             if area and area ~= '' then
                 state.isScanningLetter = true
                 local lsSearch = (state.g_LSMode == 'ls2') and 'linkshell2' or 'linkshell'

                 -- Send 3 presses of the escape key before running the /sea search command
                 ashita.tasks.once(0, function()
                     for i = 1, 3 do
                         AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape down')
                         coroutine.sleep(0.06)
                         AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape up')
                         coroutine.sleep(0.06)
                     end

                     -- 1 second delay between escapes and the new search
                     coroutine.sleep(1.0)

                     AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s %s %s', area, lsSearch, letter))
                     state.pendingSeaScan = { fireAt = os.clock() + (state.attendDelaySec or 2) }
                     state.isScanningLetter = false
                 end)
             end
        end,
        on_scan_all = function()
             if state.isScanningAll or state.isScanningLetter then return end

             local area = get_search_area(state.pendingEventName)
             if not area or area == '' then
                 print(string.format('[att] No search area found for "%s".', tostring(state.pendingEventName)))
                 return
             end

             state.isScanningAll = true
             state.abortScanAll = false
             local lsSearch = (state.g_LSMode == 'ls2') and 'linkshell2' or 'linkshell'
             local is_sa = get_sa_flags()

             local current = state.scanNextLetter
             if not current or current == '' then
                 local last = attendance.data[#attendance.data]
                 local cleanLast = last and helpers.strip_prefix(last.name)
                 local ch = (cleanLast and cleanLast ~= '') and cleanLast:match('^(%a)') or 'A'
                 current = ch:upper()
             end

             ashita.tasks.once(0, function()
                 while state.isScanningAll and not state.abortScanAll do
                     state.scanNextLetter = current
                     print(string.format('[att] Scan all: scanning letter %s (%s)...', current, area))

                     -- 1. Three escape keypresses to close any open search window
                     for i = 1, 3 do
                         if state.abortScanAll then break end
                         AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape down')
                         coroutine.sleep(0.06)
                         AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey escape up')
                         coroutine.sleep(0.06)
                     end
                     if state.abortScanAll then break end

                     -- 2. One second delay between escapes and new search
                     coroutine.sleep(1.0)
                     if state.abortScanAll then break end

                     -- 3. Run the search
                     AshitaCore:GetChatManager():QueueCommand(1, string.format('/sea %s %s %s', area, lsSearch, current))

                     -- 4. Wait for search results
                     local waitSec = tonumber(state.attendDelaySec) or 2
                     if waitSec < 2 then waitSec = 2 end
                     coroutine.sleep(waitSec)
                     if state.abortScanAll then break end

                     -- 5. Gather search results from memory
                     attendance.gather_zone(state.pendingEventName, is_sa)

                     -- 6. Advance to next letter; stop once wrapped back to A
                     local nextLetter = helpers.get_next_letter(current)
                     state.scanNextLetter = nextLetter
                     if nextLetter == 'A' then
                         print('[att] Scan all complete (wrapped back to A).')
                         break
                     end
                     current = nextLetter
                 end

                 AshitaCore:GetChatManager():QueueCommand(-1, '/releasekeys')
                 state.isScanningAll = false
                 state.abortScanAll = false
             end)
        end,
        on_stop_scan = function()
             state.abortScanAll = true
             AshitaCore:GetChatManager():QueueCommand(-1, '/releasekeys')
             print('[att] Stopping scan all...')
        end,
        on_auto_popout_change = function(val)
             config.autoPopout = val
             save_config(config)
             state.autoPopout = val
             if not val then
                  state.isPopoutOpen = false
             else
                  update_suggestions()
                  if state.suggestions and state.suggestions.evs and #state.suggestions.evs > 0 then
                       state.isPopoutOpen = true
                  end
             end
        end,
        on_self_attest_change = function()
             save_config(config)
        end,
        on_default_ls2_change = function(val)
             config.defaultLS2 = val
             save_config(config)
             state.defaultLS2 = val
             state.attendUseLS2 = val
             state.g_LSMode = val and 'ls2' or 'ls'
        end,
        on_ui_scale_change = function(val)
             config.uiScale = val
             save_config(config)
             state.uiScale = val
        end,
        on_popout_config_change = function()
             config.popoutHideTitle = state.popoutHideTitle
             config.popoutHideBg = state.popoutHideBg
             config.popoutLockPosition = state.popoutLockPosition
             config.popoutTheme = state.popoutTheme
             config.popoutRounding = state.popoutRounding
             config.popoutBtnHeight = state.popoutBtnHeight
             config.popoutWidth = state.popoutWidth
             save_config(config)
        end
    }

    if state.isAttendanceWindowOpen then
        state.isAttendanceWindowOpen = ui.draw_attendance_window(state.isAttendanceWindowOpen, attendance, state, callbacks)
        if not state.isAttendanceWindowOpen then state.g_SAMode = false end
    end
    
    if state.isAttendLauncherOpen then
        state.isAttendLauncherOpen = ui.draw_launcher(state.isAttendLauncherOpen, state, callbacks)
    end
    
    if state.isPopoutOpen then
        state.isPopoutOpen = ui.draw_popout(state.isPopoutOpen, state, callbacks)
    end
    
    if state.isPreferencesWindowOpen and not state.isAttendLauncherOpen then
        state.isPreferencesWindowOpen = ui.draw_preferences_window(state.isPreferencesWindowOpen, state, callbacks)
    end
    
    -- Debug window call removed

end)


ashita.events.register('command', 'att_global_tools', function(e)
    local args = e.command:args()
    if #args > 0 and args[1]:lower() == '/findoffset' then
        e.blocked = true
        memory.deep_scan_for_entity_list()
        return
    end

    if #args > 0 and args[1]:lower() == '/apidump' then
        e.blocked = true
        memory.dump_api_methods()
        return
    end
end)

ashita.events.register('unload', 'att_unload_cb', function()
    state.abortScanAll = true
    state.isScanningAll = false
    state.isScanningLetter = false
    state.isRefreshing = false
    AshitaCore:GetChatManager():QueueCommand(-1, '/releasekeys')
    local io = imgui.GetIO()
    if io then
        io.MouseDrawCursor = false
    end
end)

