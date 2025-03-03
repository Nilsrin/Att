----------------------------------------------------------------------------------------------------
--  ATTENDANCE ADDON (Ashita v4)
----------------------------------------------------------------------------------------------------
addon.name      = 'att'
addon.author    = 'literallywho, edited by Nils'
addon.version   = '2.1'
addon.desc      = 'Takes attendance; user can remove entries before writing; LS message on finalize.'

require('common')
local imgui = require('imgui')
local chat  = require('chat')

--------------------------------------------------------------------------------
-- Global variables
--------------------------------------------------------------------------------

local zoneList    = {}
local jobList     = {}
local shortNames  = {}
local creditNames = {}
local gdi         = require('gdifonts.include')

-- [LS2 FIX] We add a global to remember if user typed ls or ls2:
local g_LSMode = nil  -- can be 'ls', 'ls2', or nil

local isAttendanceWindowOpen = false
local isHelpWindowOpen       = false
local helpData               = {}

local attendanceData   = {}
local pendingEventName = nil
local pendingShortAlias = nil

-- Instead of deciding "HNM" or "Event" from commands, user picks it in GUI.
local selectedMode     = 'HNM'  -- can be 'Event' or 'HNM'

local pendingFilePath  = nil
local pendingLSMessage = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Load external resource files
--------------------------------------------------------------------------------

local function loadShortNames()
    local path = string.format('%sresources/shortnames.txt', addon.path)
    local file = io.open(path, 'r')
    if not file then
        print(string.format('Could not load shortnames.txt at path: %s', path))
        return
    end

    for line in file:lines() do
        local alias, fullname = line:match('^(.-),(.*)$')
        if alias and fullname then
            alias    = alias:match('^%s*(.-)%s*$')
            fullname = fullname:match('^%s*(.-)%s*$')
            shortNames[alias:lower()] = fullname
        end
    end
    file:close()
end

local function loadCreditNames()
    local path = string.format('%sresources/creditnames.txt', addon.path)
    local file = io.open(path, 'r')
    if not file then
        print(string.format('Could not load creditnames.txt at path: %s', path))
        return
    end

    for line in file:lines() do
        local fullname, zone = line:match('^(.-),(.*)$')
        if fullname then
            fullname = fullname:match('^%s*(.-)%s*$')
            zone     = zone:match('^%s*(.-)%s*$')

            if not creditNames[fullname] then
                creditNames[fullname] = {}
            end
            if zone ~= '' and zone ~= nil then
                table.insert(creditNames[fullname], zone)
            end
        end
    end
    file:close()
end

--------------------------------------------------------------------------------
-- Gathering Functions
--------------------------------------------------------------------------------

local function gatherAllianceData()
    local partyMgr = AshitaCore:GetMemoryManager():GetParty()
    for i = 0, 17 do
        local name = partyMgr:GetMemberName(i)
        if (name ~= nil and name ~= '') then
            local zoneId   = partyMgr:GetMemberZone(i)
            local zoneName = zoneList[zoneId] or 'UnknownZone'

            local mainJobId = partyMgr:GetMemberMainJob(i)
            local subJobId  = partyMgr:GetMemberSubJob(i)
            local mainJob   = jobList[mainJobId] or ''
            local subJob    = jobList[subJobId] or ''

            if creditNames[pendingEventName] and has_value(creditNames[pendingEventName], zoneName) then
                table.insert(attendanceData, {
                    name     = name,
                    jobsMain = mainJob,
                    jobsSub  = subJob,
                    zone     = zoneName,
                    time     = os.date('%H:%M:%S')
                })
            end
        end
    end
end

local function gatherZoneData()
    local basePointerAddr = ashita.memory.read_int32(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0)
    )
    basePointerAddr       = basePointerAddr + 12
    local numResults      = ashita.memory.read_int32(basePointerAddr)
    basePointerAddr       = basePointerAddr + 20
    local listPointerAddr = ashita.memory.read_int32(basePointerAddr)

    for i = 0, (numResults - 1) do
        local name    = ashita.memory.read_string(listPointerAddr + 0x04 + 0x4, 15)
        local zoneId  = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x28)
        local zone    = zoneList[zoneId] or 'UnknownZone'
        local mainId  = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x20)
        local subId   = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x21)
        local mainJob = jobList[mainId] or ''
        local subJob  = jobList[subId] or ''

        if creditNames[pendingEventName] and has_value(creditNames[pendingEventName], zone) then
            table.insert(attendanceData, {
                name     = name,
                jobsMain = mainJob,
                jobsSub  = subJob,
                zone     = zone,
                time     = os.date('%H:%M:%S')
            })
        end

        listPointerAddr = listPointerAddr + 76
    end

    print(string.format('Found %d characters in range (zone-based).', #attendanceData))
end

--------------------------------------------------------------------------------
-- Writes the final attendanceData to CSV
--------------------------------------------------------------------------------
local function writeAttendanceFile()
    if (not pendingFilePath) or (not pendingEventName) then
        print('No pending file path or event name to write!')
        return
    end

    local file = io.open(pendingFilePath, 'a')
    if not file then
        print('Error: Could not open attendance log file for writing: ' .. pendingFilePath)
        return
    end

    for _, row in ipairs(attendanceData) do
        file:write(string.format('%s,%s,%s,%s,%s,%s\n',
            row.name,
            row.jobsMain,
            os.date('%m/%d/%Y'),
            os.date('%H:%M:%S'),
            row.zone,
            pendingEventName
        ))
    end

    file:close()
    print(string.format('Wrote %d entries to: %s', #attendanceData, pendingFilePath))
end

--------------------------------------------------------------------------------
-- GUI helpers
--------------------------------------------------------------------------------
local function ShowAttendanceWindow()
    isAttendanceWindowOpen = true
end

local function ShowHelpWindow()
    isHelpWindowOpen = true
end

local function gatherHelpDataForCurrentZone()
    helpData = {}

    local currZoneId = ashita.memory.read_uint8(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0)
    )
    local currZone = zoneList[currZoneId] or 'UnknownZone'

    for alias, eventName in pairs(shortNames) do
        if creditNames[eventName] and has_value(creditNames[eventName], currZone) then
            table.insert(helpData, { alias = alias, name = eventName })
        end
    end

    if #helpData == 0 then
        print(string.format('No shortnames found for your current zone: %s', currZone))
    else
        print(string.format('%d shortnames found for zone: %s', #helpData, currZone))
    end
end

--------------------------------------------------------------------------------
-- Ashita Events
--------------------------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    -- cleanup if needed
end)

ashita.events.register('load', 'load_cb', function()
    -- Load zone data
    local zpath = addon.path .. 'resources/zones.csv'
    for line in io.lines(zpath) do
        local index, name = line:match('%i*(.-),%s*(.-),')
        if index and name then
            table.insert(zoneList, index, name)
        end
    end

    -- Load job data
    local jpath = addon.path .. 'resources/jobs.csv'
    for line in io.lines(jpath) do
        local index, name = line:match('%i*(.-),%s*(.-),')
        if index and name then
            table.insert(jobList, index, name)
        end
    end

    loadShortNames()
    loadCreditNames()
end)

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if (#args == 0 or args[1]:lower() ~= '/att') then
        return
    end

    e.blocked = true

    if (#args == 2 and args[2]:lower() == 'help') then
        gatherHelpDataForCurrentZone()
        ShowHelpWindow()
        return
    end

    attendanceData     = {}
    pendingFilePath    = nil
    pendingLSMessage   = nil
    selectedMode       = 'HNM'
    pendingShortAlias  = nil

    local time      = os.date('*t')
    local printTime = os.date(('%02d.%02d.%02d'):format(time.hour, time.min, time.sec))

    -- [LS2 FIX] local variable
    local lsMode          = nil
    local directWriteMode = nil
    local shortArg        = nil

    for i = 2, #args do
        local a = args[i]:lower()
        if a == 'ls' then
            lsMode = 'ls'
        elseif a == 'ls2' then
            lsMode = 'ls2'  -- store it
        elseif a == 'h' then
            directWriteMode = 'HNM'
        elseif a == 'e' then
            directWriteMode = 'Event'
        else
            shortArg = a
        end
    end

    -- [LS2 FIX] Store lsMode in the global so we can use it in the GUI:
    g_LSMode = lsMode

    pendingEventName = 'Current Zone'
    if shortArg ~= nil then
        local mapped = shortNames[shortArg:lower()]
        if mapped then
            pendingEventName = mapped
        else
            print(string.format(
                'Alias "%s" not found in shortnames.txt; defaulting event name to "Current Zone".',
                shortArg
            ))
        end
        pendingShortAlias = shortArg
    end

    local currZoneId = ashita.memory.read_uint8(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0)
    )
    local currZone = zoneList[currZoneId] or 'UnknownZone'
    if not creditNames['Current Zone'] then
        creditNames['Current Zone'] = {}
    end
    creditNames['Current Zone'][1] = currZone

    if lsMode == 'ls' or lsMode == 'ls2' then
        print('Running in zone-based mode..')
        gatherZoneData()
    else
        print('Running in alliance-based mode..')
        gatherAllianceData()
    end

    print(string.format('Loaded %d attendees.', #attendanceData))

    -- If user used h/e, skip GUI
    if directWriteMode ~= nil then
        selectedMode = directWriteMode

        local dateStr = os.date('%A %d %B %Y')
        local timeStr = os.date('%H.%M.%S')

        if selectedMode == 'HNM' then
            pendingFilePath  = string.format('%sHNM Logs\\%s %s.csv', addon.path, dateStr, timeStr)
            pendingLSMessage = string.format('HNM Attendance has been taken for: %s', pendingEventName)
        else
            pendingFilePath  = string.format('%sEvent Logs\\%s %s.csv', addon.path, dateStr, timeStr)
            pendingLSMessage = string.format('Event Attendance has been taken for: %s', pendingEventName)
        end

        writeAttendanceFile()

        if (pendingLSMessage ~= nil) then
            -- [LS2 FIX] check lsMode
            if lsMode == 'ls2' then
                AshitaCore:GetChatManager():QueueCommand(1, '/l2 ' .. pendingLSMessage)
            else
                AshitaCore:GetChatManager():QueueCommand(1, '/l ' .. pendingLSMessage)
            end
        end

        return
    end

    print('Open the GUI to remove entries or finalize writing. Use "Write & Close" button in the UI.')
    ShowAttendanceWindow()
end)

--------------------------------------------------------------------------------
-- d3d_present (the GUI rendering)
--------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    if isAttendanceWindowOpen then
        imgui.SetNextWindowSize({1050, 600}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendanceWindowOpen }
        if imgui.Begin('Attendance Results', openPtr) then

            imgui.Text('Select Mode:')
            imgui.SameLine()
            if imgui.RadioButton('HNM', (selectedMode == 'HNM')) then
                selectedMode = 'HNM'
            end
            imgui.SameLine()
            if imgui.RadioButton('Event', (selectedMode == 'Event')) then
                selectedMode = 'Event'
            end

            imgui.Separator()
            imgui.Text(string.format('Attendance Name: %s', pendingEventName))
            imgui.Separator()

            imgui.Text(string.format('Attendees in credited zone(s): %d', #attendanceData))

            local childHeight = -50
            imgui.BeginChild('att_list_region', {0, childHeight}, true)

            for i = #attendanceData, 1, -1 do
                local row = attendanceData[i]
                if imgui.Button('Remove##' .. tostring(i)) then
                    table.remove(attendanceData, i)
                end
                imgui.SameLine()
                imgui.Text(string.format('%s (%s | %s/%s)',
                    row.name, row.zone, row.jobsMain, row.jobsSub
                ))
            end

            imgui.EndChild()
            imgui.Separator()

            if imgui.Button('Write & Close') then
                local dateStr = os.date('%A %d %B %Y')
                local timeStr = os.date('%H.%M.%S')

                if selectedMode == 'HNM' then
                    pendingFilePath  = string.format('%sHNM Logs\\%s %s.csv', addon.path, dateStr, timeStr)
                    pendingLSMessage = string.format('HNM Attendance has been taken for: %s', pendingEventName)
                else
                    pendingFilePath  = string.format('%sEvent Logs\\%s %s.csv', addon.path, dateStr, timeStr)
                    pendingLSMessage = string.format('Event Attendance has been taken for: %s', pendingEventName)
                end

                writeAttendanceFile()

                if (pendingLSMessage ~= nil) then
                    -- [LS2 FIX] Now we check the global g_LSMode to decide /l or /l2
                    if g_LSMode == 'ls2' then
                        AshitaCore:GetChatManager():QueueCommand(1, '/l2 ' .. pendingLSMessage)
                    else
                        -- If g_LSMode == 'ls' or nil, use normal /l
                        AshitaCore:GetChatManager():QueueCommand(1, '/l ' .. pendingLSMessage)
                    end
                    coroutine.sleep(1.5)
                end

                isAttendanceWindowOpen = false
            end

            imgui.SameLine()
            if imgui.Button('Cancel') then
                isAttendanceWindowOpen = false
                print('Canceled attendance writing. No linkshell message was sent.')
            end

            imgui.End()
        end

        if not openPtr[1] then
            isAttendanceWindowOpen = false
            print('Window closed without writing or sending LS message.')
        end
    end

    if isHelpWindowOpen then
        local helpOpenPtr = { isHelpWindowOpen }
        if imgui.Begin('Attendance Help - Current Zone', helpOpenPtr) then
            imgui.Text('Shortnames that match your current zone:')
            imgui.Separator()

            local childHeight = -30
            imgui.BeginChild('help_list_region', {0, childHeight}, true)

            for _, entry in ipairs(helpData) do
                imgui.Text(string.format('Alias: %s   ->   %s', entry.alias, entry.name))
            end

            imgui.EndChild()

            if imgui.Button('Close##help') then
                isHelpWindowOpen = false
            end

            imgui.End()
        end

        if not helpOpenPtr[1] then
            isHelpWindowOpen = false
        end
    end
end)
