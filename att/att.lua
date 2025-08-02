--  ATTENDANCE ADDON (Ashita v4) — with Self-Attendance and Composition
addon.name      = 'att'
addon.author    = 'Nils'
addon.version   = '2.2'
addon.desc      = 'Attendance manager'

require('common')
local imgui   = require('imgui')
local chat    = require('chat')
local struct  = require('struct')

-- Shared data split for attendance and composition
local attZoneList           = {}
local attJobList            = {}
local attShortNames         = {}
local attCreditNames        = {}

local compZoneList          = {}
local compJobList           = {}
local compShortNames        = {}
local compCreditNames       = {}

local zoneRoster            = {}
local g_LSMode              = nil
local g_SAMode              = false
local selfAttendanceStart   = nil

local isAttendanceWindowOpen = false
local attendanceData        = {}
local pendingEventName      = nil
local selectedMode          = 'HNM'
local pendingFilePath       = nil
local pendingLSMessage      = nil
local confirm_commands      = { 'here', 'present', 'herebrother' }

local saTimerDuration = 300 -- fallback
local saReminderIntervals = {}

local function parse_time_string(timeStr)
    if not timeStr then return 0 end
    local minutes, seconds = timeStr:match('^(%d+):(%d+)$')
    if minutes and seconds then
        return tonumber(minutes) * 60 + tonumber(seconds)
    end
    local mins = tonumber(timeStr)
    if mins then
        return mins * 60
    end
    return 0
end

local function loadSATimers()
    saTimerDuration = 300
    saReminderIntervals = {}
    local durationStr = "5"
    local intervalStr = "1"

    local filePath = addon.path .. 'resources/satimers.txt'
    local f = io.open(filePath, 'r')
    if not f then
        print('SATimers.txt not found. Using default 5 minutes / 1 minute interval.')
        return
    end

    for line in f:lines() do
        local key, val = line:match('^(%a+):%s*(%d+[:%d+]*)$')
        if key and val then
            key = key:lower()
            if key == 'minutes' then
                durationStr = val
            elseif key == 'interval' then
                intervalStr = val
            end
        end
    end
    f:close()

    saTimerDuration = parse_time_string(durationStr)
    local intervalSec = parse_time_string(intervalStr)

    saReminderIntervals = {}
    local nextReminder = intervalSec
    while nextReminder < saTimerDuration do
        table.insert(saReminderIntervals, saTimerDuration - nextReminder)
        nextReminder = nextReminder + intervalSec
    end
end

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function clean_str(str)
    str = AshitaCore:GetChatManager():ParseAutoTranslate(str, true)
    str = str:strip_colors():strip_translate(true)
    while str:endswith('\n') or str:endswith('\r') do
        str = str:trimend('\n'):trimend('\r')
    end
    return str:gsub(string.char(0x07), '\n')
end

local function has_value(tab, val)
    for _, v in ipairs(tab) do
        if v == val then return true end
    end
    return false
end

local function buildCreditRoster()
    zoneRoster = {}
    local baseAddr = ashita.memory.read_int32(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0)
    ) + 12
    local count    = ashita.memory.read_int32(baseAddr)
    local ptr      = ashita.memory.read_int32(baseAddr + 20)
    for i = 0, count - 1 do
        local name = ashita.memory.read_string(ptr + 0x08, 15)
        if name ~= '' then
            local zid   = ashita.memory.read_uint8(ptr + 0x2C)
            local zname = attZoneList[zid] or 'UnknownZone'
            if attCreditNames[pendingEventName]
               and has_value(attCreditNames[pendingEventName], zname)
            then
                local mj = attJobList[ashita.memory.read_uint8(ptr + 0x24)] or 'NONE'
                local sj = attJobList[ashita.memory.read_uint8(ptr + 0x25)] or 'NONE'
                zoneRoster[name] = {
                    jobsMain = mj,
                    jobsSub  = sj,
                    zone     = zname
                }
            end
        end
        ptr = ptr + 76
    end
    print(string.format('Credit roster built: %d eligible players',
        table.length(zoneRoster)))
end

ashita.events.register('load', 'load_cb', function()
    for line in io.lines(addon.path .. 'resources/zones.csv') do
        local idx, nm = line:match('^(%d+),%s*(.-),')
        if idx and nm then
            attZoneList[tonumber(idx)] = nm
            compZoneList[tonumber(idx)] = nm
        end
    end

    for line in io.lines(addon.path .. 'resources/jobs.csv') do
        local idx, nm = line:match('^(%d+),%s*(.-),')
        if idx and nm then
            attJobList[tonumber(idx)] = nm
            compJobList[tonumber(idx)] = nm
        end
    end

    for line in io.lines(addon.path .. 'resources/shortnames.txt') do
        local alias, fullname = line:match('^(.-),(.*)$')
        if alias and fullname then
            alias = alias:match('^%s*(.-)%s*$'):lower()
            fullname = fullname:match('^%s*(.-)%s*$')
            attShortNames[alias]  = fullname
            compShortNames[alias] = fullname
        end
    end

    for line in io.lines(addon.path .. 'resources/creditnames.txt') do
        local ev, zone = line:match('^(.-),(.*)$')
        if ev then
            ev = ev:match('^%s*(.-)%s*$')
            zone = zone:match('^%s*(.-)%s*$')
            attCreditNames[ev]  = attCreditNames[ev] or {}
            compCreditNames[ev] = compCreditNames[ev] or {}
            if zone ~= '' then
                table.insert(attCreditNames[ev], zone)
                table.insert(compCreditNames[ev], zone)
            end
        end
    end
end)

local function gatherAllianceData()
    local pm = AshitaCore:GetMemoryManager():GetParty()
    for i = 0, 17 do
        local name = pm:GetMemberName(i)
        if name ~= '' then
            local zid   = pm:GetMemberZone(i)
            local zname = attZoneList[zid] or 'UnknownZone'
            if attCreditNames[pendingEventName]
               and has_value(attCreditNames[pendingEventName], zname)
            then
                table.insert(attendanceData, {
                    name     = name,
                    jobsMain = attJobList[pm:GetMemberMainJob(i)] or 'NONE',
                    jobsSub  = attJobList[pm:GetMemberSubJob(i)]  or 'NONE',
                    zone     = zname,
                    time     = os.date('%H:%M:%S')
                })
            end
        end
    end
end

local function gatherZoneData()
    local baseAddr = ashita.memory.read_int32(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0)
    ) + 12
    local count    = ashita.memory.read_int32(baseAddr)
    local ptr      = ashita.memory.read_int32(baseAddr + 20)
    for i = 0, count - 1 do
        local name  = ashita.memory.read_string(ptr + 0x08, 15)
        local zid   = ashita.memory.read_uint8(ptr + 0x2C)
        local zname = attZoneList[zid] or 'UnknownZone'
        if attCreditNames[pendingEventName]
           and has_value(attCreditNames[pendingEventName], zname)
        then
            table.insert(attendanceData, {
                name     = name,
                jobsMain = attJobList[ashita.memory.read_uint8(ptr + 0x24)] or 'NONE',
                jobsSub  = attJobList[ashita.memory.read_uint8(ptr + 0x25)] or 'NONE',
                zone     = zname,
                time     = os.date('%H:%M:%S')
            })
        end
        ptr = ptr + 76
    end
end

local function writeAttendanceFile()
    if not pendingFilePath or not pendingEventName then
        print('No pending file or event to write!')
        return
    end
    local f = io.open(pendingFilePath, 'a')
    if not f then
        print('Could not open file: ' .. pendingFilePath)
        return
    end
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

ashita.events.register('packet_in', 'sa_packet_in', function(e)
    if not g_SAMode or e.id ~= 0x017 then return end
    local char = struct.unpack('c15', e.data_modified, 0x08+1):trimend('\0')
    local raw  = struct.unpack('s',  e.data_modified, 0x17+1)
    local msg  = clean_str(raw)
    local cmd  = msg:lower()

    for _, trigger in ipairs(confirm_commands) do
        if cmd:match('^!' .. trigger) then
            local info = zoneRoster[char]
            if not info then return end
            local zid   = ashita.memory.read_uint8(
                ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0)
            )
           local zname = attZoneList[zid] or 'UnknownZone'
			if not (attCreditNames[pendingEventName]
					and has_value(attCreditNames[pendingEventName], zname))

            then return end
            for _, row in ipairs(attendanceData) do
                if row.name == ('X ' .. char) then
                    row.name = char
                    row.time = os.date('%H:%M:%S')
                    return
                end
            end
        end
    end

    if cmd:match('^!addme') then
			for _, row in ipairs(attendanceData) do
				if row.name:gsub("^X ", ""):lower() == char:lower() then return end
			end

        local zid   = ashita.memory.read_uint8(
            ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0)
        )
        local zname = attZoneList[zid] or 'UnknownZone'
        table.insert(attendanceData, {
            name     = char,
            jobsMain = 'IN',
            jobsSub  = 'IN',
            zone     = zname,
            time     = os.date('%H:%M:%S')
        })
        return
    end
end)

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/att' then return end
    e.blocked = true

    if #args == 2 and args[2]:lower() == 'help' then
        isHelpWindowOpen = true
        return
    end

    attendanceData        = {}
    pendingFilePath       = nil
    pendingLSMessage      = nil
    selectedMode          = 'HNM'
    g_LSMode              = nil
    g_SAMode              = false
    selfAttendanceStart   = nil
    zoneRoster            = {}

    local lsMode, writeMode, alias, saFlag = nil, nil, nil, false
    for i = 2, #args do
        local a = args[i]:lower()
        if a == 'ls'   then lsMode = 'ls'
        elseif a == 'ls2' then lsMode = 'ls2'
        elseif a == 'h'   then writeMode = 'HNM'
        elseif a == 'e'   then writeMode = 'Event'
        elseif a == 'sa'  then saFlag = true
        else alias = a end
    end
    g_LSMode = lsMode

    if alias then
		pendingEventName = attShortNames[alias] or alias
	else
		pendingEventName = 'Current Zone'
	end

    local zid = ashita.memory.read_uint8(
        ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0)
    )
    attCreditNames['Current Zone'] = attCreditNames['Current Zone'] or {}
	attCreditNames['Current Zone'][1] = attZoneList[zid] or 'UnknownZone'


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
				time     = os.date('%H:%M:%S')
        })
		end
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

    isAttendanceWindowOpen = true
end)

ashita.events.register('d3d_present', 'present_cb', function()
    if g_SAMode and selfAttendanceStart then
    local elapsed = os.time() - selfAttendanceStart

    -- Reminder logic
    for i = #saReminderIntervals, 1, -1 do
        if elapsed >= saReminderIntervals[i] then
            local pending = {}
            for _, r in ipairs(attendanceData) do
                if r.name:match('^X ') then
                    table.insert(pending, r.name:sub(3))
                end
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
            g_SAMode              = false
            selfAttendanceStart   = nil
            return
        end
    end

    if isAttendanceWindowOpen then
        imgui.SetNextWindowSize({1050,600}, ImGuiCond_FirstUseEver)
        local openPtr = { isAttendanceWindowOpen }
        if imgui.Begin('Attendance Results', openPtr) then

            if g_SAMode and selfAttendanceStart then
                local elapsed   = os.time() - selfAttendanceStart
                local remaining = math.max(0, saTimerDuration - elapsed)
                imgui.Text(string.format(
					'Time until auto-submit: %02d:%02d',
					math.floor(remaining/60), remaining%60
				))
                imgui.Separator()
            end

            if g_SAMode then
                if imgui.Button('Show Pending') then
                    local pending = {}
                    for _, r in ipairs(attendanceData) do
                        if r.name:match('^X ') then
                            table.insert(pending, r.name:sub(3))
                        end
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
							local cleanRowName = row.name:gsub("^X ", ""):lower()
							if cleanRowName == name:lower() then
						exists = true
						break
					end
				end

				if not exists then
					table.insert(attendanceData, {
						name     = name,
						jobsMain = info.jobsMain,
						jobsSub  = info.jobsSub,
						zone     = info.zone,
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
		end

                imgui.Separator()
            end

            imgui.Text('Select Mode:') imgui.SameLine()
            if imgui.RadioButton('HNM',    selectedMode=='HNM') then selectedMode='HNM' end
            imgui.SameLine()
            if imgui.RadioButton('Event',  selectedMode=='Event') then selectedMode='Event' end

            imgui.Separator()
			imgui.Text('Attendance for: ' .. pendingEventName)

			-- Show zone associated with this event
			local creditZone = attCreditNames[pendingEventName] and attCreditNames[pendingEventName][1] or "UnknownZone"
			imgui.Text('Credit Zone: ' .. creditZone)

			imgui.Separator()

            imgui.Text('Attendees: ' .. #attendanceData)

            imgui.BeginChild('att_list', {0, -50}, true)
            for i = #attendanceData, 1, -1 do
                local r = attendanceData[i]
                if imgui.Button('Remove##' .. i) then table.remove(attendanceData, i) end
                imgui.SameLine()
                imgui.Text(string.format(
                    '%s (%s | %s/%s)',
                    r.name, r.zone, r.jobsMain, r.jobsSub
                ))
            end
            imgui.EndChild()
            imgui.Separator()

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
                g_SAMode              = false
            end
            imgui.SameLine()
            if imgui.Button('Cancel') then
                isAttendanceWindowOpen = false
                g_SAMode              = false
            end

            imgui.End()
        end
        if not openPtr[1] then
            isAttendanceWindowOpen = false
            g_SAMode              = false
        end
    end
end)




-- COMPOSITION ADDON SECTION
local compWindowOpen = { value = false }
local g_compBreakdown  = {}
local g_compData       = {}
local g_compName       = ""

local function getEffective(job)
    if job:find("/") then
        return trim(job:match("^(.-)/")):lower()
    else
        return trim(job):lower()
    end
end

local function getJobGroup(job, subjob)
    local effective = getEffective(job)
    local subEff = getEffective(subjob)
    if effective == "none" or effective == "" then
        return "Anon", effective
    elseif effective == "pld" or effective == "nin" then
        return "Tanks", effective
    elseif effective == "smn" or effective == "brd" or effective == "whm" or effective == "rdm" then
        return "Supports", effective
    elseif effective == "thf" then
        return "Thieves", effective
    elseif effective == "blm" then
        return "Spell Damage", effective
    elseif effective == "drk" or effective == "war" or effective == "drg" or effective == "sam" or effective == "mnk" or effective == "bst" or effective == "rng" then
        return "Melee", effective
    end
    if effective == "blm" or effective == "drk" then
        return "Stunners", effective
    elseif effective == "rdm" and subEff == "drk" then
        return "Stunners", "rdm/drk"
    end
    return nil, effective
end

local function gatherCompData(compName)
    local data = {}
    local basePointerAddr = ashita.memory.read_int32(ashita.memory.find("FFXiMain.dll", 0, "??", 0x62D014, 0))
    basePointerAddr = basePointerAddr + 12
    local numResults = ashita.memory.read_int32(basePointerAddr)
    basePointerAddr = basePointerAddr + 20
    local listPointerAddr = ashita.memory.read_int32(basePointerAddr)
    for i = 0, (numResults - 1) do
        local name = ashita.memory.read_string(listPointerAddr + 0x04 + 0x4, 15)
        local zoneId = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x28)
        local zone = compZoneList[zoneId] or "UnknownZone"
        local mainId = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x20)
        local subId = ashita.memory.read_uint8(listPointerAddr + 0x04 + 0x21)
        local mainJob = compJobList[mainId] or ""
        local subJob = compJobList[subId] or ""
        if compCreditNames[compName] and has_value(compCreditNames[compName], zone) then
            table.insert(data, {
                name     = name,
                jobsMain = mainJob,
                jobsSub  = subJob,
                zone     = zone,
                time     = os.date("%H:%M:%S")
            })
        end
        listPointerAddr = listPointerAddr + 76
    end
    print(string.format("Found %d characters for linkshell: %s", #data, compName))
    return data
end

local function refreshCompositionData()
    g_compData = gatherCompData(g_compName)
    g_compBreakdown = {
        ["Tanks"] = {},
        ["Supports"] = {},
        ["Stunners"] = {},
        ["Thieves"] = {},
        ["Spell Damage"] = {},
        ["Melee"] = {},
        ["Anon"] = {}
    }
    for _, entry in ipairs(g_compData) do
        local group, effective = getJobGroup(entry.jobsMain, entry.jobsSub)
        if group then
            table.insert(g_compBreakdown[group], entry.name .. " (" .. effective .. ")")
        else
            table.insert(g_compBreakdown["Anon"], entry.name .. " (none)")
        end
    end
end

ashita.events.register('command', 'comp_command_cb', function(e)
    local args = e.command:args()
    if (#args == 0 or args[1]:lower() ~= '/comp') then
        return
    end
    e.blocked = true
    if not args[2] then
        print("Usage: /comp {alias}")
        return
    end
    local compAlias = args[2]:lower()
	local compName = compShortNames[compAlias] or compAlias
	g_compName = compName
	g_compData = gatherCompData(compName)
    g_compBreakdown = {
        ["Tanks"] = {},
        ["Supports"] = {},
        ["Stunners"] = {},
        ["Thieves"] = {},
        ["Spell Damage"] = {},
        ["Melee"] = {},
        ["Anon"] = {}
    }
    for _, entry in ipairs(g_compData) do
        local group, effective = getJobGroup(entry.jobsMain, entry.jobsSub)
        if group then
            table.insert(g_compBreakdown[group], entry.name .. " (" .. effective .. ")")
        else
            table.insert(g_compBreakdown["Anon"], entry.name .. " (none)")
        end
    end
    local currZoneId = ashita.memory.read_uint8(ashita.memory.find("FFXiMain.dll", 0, "??", 0x452818, 0))
	local currZone = compZoneList[currZoneId] or "UnknownZone"
	compCreditNames[compName] = { currZone }
    compWindowOpen.value = true
end)

ashita.events.register('d3d_present', 'comp_present_cb', function()
    if compWindowOpen.value then
        imgui.SetNextWindowSize({600, 500}, ImGuiCond_FirstUseEver)
        
		local openPtr = { compWindowOpen.value }
		if imgui.Begin("Composition Results", openPtr) then
            imgui.Text("Event: " .. g_compName)
            imgui.SameLine()
            if imgui.Button("Refresh") then
                refreshCompositionData()
            end
            imgui.Separator()
            local groupOrder = {"Tanks", "Supports", "Stunners", "Thieves", "Spell Damage", "Melee", "Anon"}
            for _, group in ipairs(groupOrder) do
                local names = g_compBreakdown[group]
                if names and #names > 0 then
                    imgui.Text(string.format("%s: %d", group, #names))
                    for _, entry in ipairs(names) do
                        imgui.BulletText(entry)
                    end
                    imgui.Separator()
                end
            end

            local missingRequired = {}
            local missingSuggested = {}
            if not compsData[g_compName] then
                imgui.Separator()
                imgui.Text("No comp entry")
            else
                local counts = {}
                for _, entry in ipairs(g_compData) do
                    local mainEff = getEffective(entry.jobsMain)
                    local subEff = getEffective(entry.jobsSub)
                    counts[mainEff] = (counts[mainEff] or 0) + 1
                    if mainEff == "blm" or mainEff == "drk" or (mainEff == "rdm" and subEff == "drk") then
                        counts["stunner"] = (counts["stunner"] or 0) + 1
                    end
                end
                for _, req in ipairs(compsData[g_compName].required or {}) do
                    local sum = 0
                    for _, role in ipairs(req.roles) do
                        sum = sum + (counts[role] or 0)
                    end
                    local missing = req.count - sum
                    if missing > 0 then
                        table.insert(missingRequired, string.format("%d: %s", missing, table.concat(req.roles, " or ")))
                    end
                end
                for _, sug in ipairs(compsData[g_compName].suggested or {}) do
                    local sum = 0
                    for _, role in ipairs(sug.roles) do
                        sum = sum + (counts[role] or 0)
                    end
                    local missing = sug.count - sum
                    if missing > 0 then
                        table.insert(missingSuggested, string.format("%d: %s", missing, table.concat(sug.roles, " or ")))
                    end
                end
                if (#missingRequired > 0 or #missingSuggested > 0) then
                    imgui.Separator()
                    imgui.Text("Missing Composition:")
                    if #missingRequired > 0 then
                        for _, line in ipairs(missingRequired) do
                            imgui.BulletText(line)
                        end
                    end
                    if #missingSuggested > 0 then
                        for _, line in ipairs(missingSuggested) do
                            imgui.BulletText(line)
                        end
                    end
                else
                    imgui.Separator()
                    imgui.Text("Missing Composition: Good")
                end
            end

            imgui.Separator()
            if imgui.Button("Announce Missing (LS)") then
                local missingItems = {}
                if compsData[g_compName] then
                    if #missingRequired > 0 then
                        for _, line in ipairs(missingRequired) do
                            table.insert(missingItems, line)
                        end
                    end
                    if #missingSuggested > 0 then
                        for _, line in ipairs(missingSuggested) do
                            table.insert(missingItems, line)
                        end
                    end
                else
                    table.insert(missingItems, "No comp entry")
                end
                local msgBody = ""
                if #missingItems > 0 then
                    local lines = {}
                    for i = 1, #missingItems, 2 do
                        local line = missingItems[i]
                        if missingItems[i+1] then
                            line = line .. "   |   " .. missingItems[i+1]
                        end
                        table.insert(lines, line)
                    end
                    msgBody = table.concat(lines, "\n")
                else
                    msgBody = "Good"
                end
                local msg = "Missing Comp: " .. g_compName .. "\n" .. msgBody
                AshitaCore:GetChatManager():QueueCommand(1, "/l " .. msg)
            end
            imgui.SameLine()
            if imgui.Button("Announce Missing (LS2)") then
                local missingItems = {}
                if compsData[g_compName] then
                    if #missingRequired > 0 then
                        for _, line in ipairs(missingRequired) do
                            table.insert(missingItems, line)
                        end
                    end
                    if #missingSuggested > 0 then
                        for _, line in ipairs(missingSuggested) do
                            table.insert(missingItems, line)
                        end
                    end
                else
                    table.insert(missingItems, "No comp entry")
                end
                local msgBody = ""
                if #missingItems > 0 then
                    local lines = {}
                    for i = 1, #missingItems, 2 do
                        local line = missingItems[i]
                        if missingItems[i+1] then
                            line = line .. "   |   " .. missingItems[i+1]
                        end
                        table.insert(lines, line)
                    end
                    msgBody = table.concat(lines, "\n")
                else
                    msgBody = "Good"
                end
                local msg = "Missing Comp: " .. g_compName .. "\n" .. msgBody
                AshitaCore:GetChatManager():QueueCommand(1, "/l2 " .. msg)
            end
            if imgui.Button("Close##comp") then
                compWindowOpen.value = false
            end
            imgui.End()
        end
		compWindowOpen.value = openPtr[1]
	end
end)

-- Placeholder compsData table in case external data is not loaded
compsData = compsData or {
    ["Default"] = {
        required = {
            { count = 1, roles = { "pld", "nin" } },
            { count = 1, roles = { "whm" } },
            { count = 1, roles = { "blm", "drk", "rdm" } }
        },
        suggested = {
            { count = 1, roles = { "brd", "smn" } },
            { count = 1, roles = { "rdm/drk" } }
        }
    }
}

-- Optional: Add help display toggle command
local isHelpWindowOpen = false
ashita.events.register('command', 'help_command_cb', function(e)
    local args = e.command:args()
    if #args >= 1 and args[1]:lower() == '/atthelp' then
        isHelpWindowOpen = true
        e.blocked = true
    end
end)

-- Optional: Help window UI
ashita.events.register('d3d_present', 'help_present_cb', function()
    if not isHelpWindowOpen then return end
    imgui.SetNextWindowSize({600, 300}, ImGuiCond_FirstUseEver)
    local open = { true }
    if imgui.Begin("ATT Addon Help", open) then
        imgui.Text("Commands:")
        imgui.BulletText("/att ls {alias}      — Normal attendance via Linkshell 1")
        imgui.BulletText("/att ls2 {alias}     — Normal attendance via Linkshell 2")
        imgui.BulletText("/att sa {alias}      — Self-attendance for 5 minutes")
        imgui.BulletText("/att h               — Write as HNM type")
        imgui.BulletText("/att e               — Write as Event type")
        imgui.BulletText("/comp {alias}        — Group composition check")
        imgui.BulletText("/atthelp             — Show this help window")
        imgui.Text(" ")
        imgui.Text("During self-attendance, players should type:")
        imgui.BulletText("!here or !present or !herebrother to confirm attendance")
        imgui.BulletText("!addme to join manually with default job values")
        if imgui.Button("Close##help") then
            isHelpWindowOpen = false
        end
        imgui.End()
    end
    if not open[1] then
        isHelpWindowOpen = false
    end
end)