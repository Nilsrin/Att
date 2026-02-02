-- attendance.lua
local attendance = {}
local attendance = {}

local resources = require('resources')
local memory    = require('memory')
local helpers   = require('helpers')
local helpers   = require('helpers')
local constants = require('constants')
local messages  = require('messages')

attendance.data = {} -- entries: { name, jobsMain, jobsSub, zone, zid, time }
attendance.zoneRoster = {} -- for SA mode

-- Helper: Check if zid is in event credit
local function zid_in_credit(eventName, zid)
    -- DEBUG
    local set = resources.attCreditZoneIds[eventName]
    -- print(string.format('[att-debug] Check: Ev="%s" ZID=%s InSet=%s', eventName, tostring(zid), tostring(set and set[zid])))
    
    if not eventName then return false end
    if eventName == 'Global Search' then return true end

    local set = resources.attCreditZoneIds[eventName]
    if set and next(set) ~= nil then
        return set[zid] == true
    end

    -- Fallback: compare normalized names
    local zname = resources.attZoneList[zid] or 'UnknownZone'
    local list  = resources.attCreditNames[eventName]
    if not list then return false end

    local nz = helpers.norm(zname)
    for _, s in ipairs(list) do
        if helpers.norm(s) == nz then return true end
    end

    return false
end

function attendance.clear()
    attendance.data = {}
    attendance.zoneRoster = {}
end

function attendance.sort()
    table.sort(attendance.data, function(a, b)
        local an = (a.name or ''):gsub('^X%s+', ''):lower()
        local bn = (b.name or ''):gsub('^X%s+', ''):lower()
        return an < bn
    end)
end

function attendance.add_entry(name, mj_id, sj_id, zid, force_time)
    local zname = resources.attZoneList[zid] or 'UnknownZone'
    local jobsMain = resources.attJobList[mj_id] or 'NONE'
    local jobsSub  = resources.attJobList[sj_id] or 'NONE'
    
    table.insert(attendance.data, {
        name     = name,
        jobsMain = jobsMain,
        jobsSub  = jobsSub,
        zone     = zname,
        zid      = zid,
        time     = force_time or os.date('%H:%M:%S')
    })
end

-- function attendance.gather_alliance(eventName) -- Removed
-- end

function attendance.gather_zone(eventName)
    local entries = memory.scan_zone_list()
    local seen = {}
    for _, row in ipairs(attendance.data) do
        seen[row.name:gsub('^X%s+', ''):lower()] = true
    end

    local added = 0
    for name, info in pairs(entries) do
        local key = name:lower()
        local is_seen = seen[key]
        local is_credit = zid_in_credit(eventName, info.zid)
        
        if attendance.debug then
            print(string.format('[att-dbg] Candidate: "%s" (ZID:%d) | Seen:%s | Credit:%s', name, info.zid, tostring(is_seen), tostring(is_credit)))
        end

        if not is_seen and is_credit then
            attendance.add_entry(name, info.mj, info.sj, info.zid)
            seen[key] = true
            added = added + 1
        end
    end
    attendance.sort()
    print(string.format('[att] gather: added %d', added))
    return added
end

-- For SA mode
function attendance.build_credit_roster(eventName)
    attendance.zoneRoster = {}
    local entries = memory.scan_zone_list()
    local added = 0
    for name, info in pairs(entries) do
        if zid_in_credit(eventName, info.zid) then
            attendance.zoneRoster[name] = {
                jobsMain = resources.attJobList[info.mj] or 'NONE',
                jobsSub  = resources.attJobList[info.sj] or 'NONE',
                zone     = resources.attZoneList[info.zid] or 'UnknownZone',
                zid      = info.zid
            }
            added = added + 1
        end
    end
    print(string.format('[att] credit roster: %d eligible', added))
    return added
end

function attendance.populate_sa_start(eventName, hostName)
    -- Everyone in roster gets 'X ' prefix
    for name, info in pairs(attendance.zoneRoster) do
        table.insert(attendance.data, {
            name     = 'X ' .. name,
            jobsMain = info.jobsMain,
            jobsSub  = info.jobsSub,
            zone     = info.zone,
            zid      = info.zid,
            time     = os.date('%H:%M:%S')
        })
    end

    -- Mark host as present
    if hostName and hostName ~= '' then
        local exists = false
        for _, row in ipairs(attendance.data) do
            if row.name:gsub('^X ', ''):lower() == hostName:lower() then
                row.name = hostName -- remove X
                exists = true
                break
            end
        end
        if not exists then
             -- Add host if not found (unexpected but possible if host is not in zone list yet?)
             -- Try to find in zone roster again (safe check)
             local hostInfo = attendance.zoneRoster[hostName] -- already in roster but maybe name casing?
             -- If not found, just add with current zone/unknown jobs
             if hostInfo then
                  attendance.add_entry(hostName, hostInfo.mj, hostInfo.sj, hostInfo.zid)
             else
                  attendance.add_entry(hostName, 0, 0, memory.get_current_zone_id())
             end
        end
    end
    
    attendance.sort()
end

function attendance.write_file(addon_path, mode, eventName)
    local dateStr = os.date('%A %d %B %Y')
    local timeStr = os.date('%H.%M.%S')
    local dir, msg

    if mode == 'HNM' then
        dir = addon_path .. 'HNM Logs\\'
        msg = string.format(messages.HNM_TAKEN, eventName)
    else
        dir = addon_path .. 'Event Logs\\'
        msg = string.format(messages.EVENT_TAKEN, eventName)
    end

    local filePath = dir .. dateStr .. ' ' .. timeStr .. '.csv'
    
    local f = io.open(filePath, 'a')
    if not f then
        return nil, 'Could not open file: ' .. filePath
    end

    local count = 0
    for _, row in ipairs(attendance.data) do
        if not row.name:match('^X ') then
            f:write(string.format(
                '%s,%s,%s,%s,%s,%s\n',
                row.name,
                row.jobsMain,
                os.date('%m/%d/%Y'),
                os.date('%H:%M:%S'),
                row.zone,
                eventName
            ))
            count = count + 1
        end
    end
    f:close()
    
    return count, msg
end

function attendance.resolve_events_for_zone(zid)
    local zname = resources.attZoneList[zid] or 'UnknownZone'
    
    -- Explicit mappings
    local evs_by_id = {}
    for eventName, zoneIdSet in pairs(resources.attCreditZoneIds) do
        if zoneIdSet[zid] then
            table.insert(evs_by_id, eventName)
        end
    end
    if #evs_by_id > 0 then
        return evs_by_id, zname
    end

    -- Name mapping
    local nz   = helpers.norm(zname)
    local evs  = {}
    for eventName, zoneList in pairs(resources.attCreditNames) do
        for _, zone in ipairs(zoneList) do
            if helpers.norm(zone) == nz then
                table.insert(evs, eventName)
                break
            end
        end
    end
    
    return evs, zname
end

return attendance
