-- resources.lua
local resources = {}

-- Data tables
resources.attZoneList       = {} -- [zid] = zone name
resources.attJobList        = {} -- [jobId] = job abbrev
resources.attShortNames     = {} -- [alias:lower] = Full Event Name
resources.attCreditNames    = {} -- [Event] = { zone1, zone2, ... }
resources.attCreditZoneIds  = {} -- [Event] = { [zid]=true, ... }
resources.attSearchArea     = {} -- [Event] = "Area"
resources.zoneNameToIds     = {} -- [normZoneName] = { [zid]=true, ... }

resources.attendCategories      = {} -- [category] = { event1, ... }
resources.attendCategoriesOrder = {} -- { category1, ... }
resources.uncategorizedEvents   = {}

resources.compositions          = {} -- [EventName] = { required = {}, suggested = {}, parties = {} }
resources.attRoleDefinitions    = {
    ['tank']    = { 'PLD', 'NIN' },
    ['support'] = { 'WHM', 'RDM', 'SMN', 'BRD' },
    ['stunner'] = { 'DRK', 'BLM', 'RDM/DRK' },
    ['damage']  = { 'DRK', 'WAR', 'DRG', 'RNG', 'MNK', 'SAM', 'THF', 'BST' },
    ['thf']     = { 'THF' }
}

-- Helper to normalize zone names (local copy to avoid dependency issues)
local function norm(s)
    s = (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1')):lower()
    s = s:gsub("[%s%-%.'’_]+", "")
    return s
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

function resources.load(addon_path)
    local resPath = addon_path .. 'resources\\'
    
    -- zones.csv
    for line in io.lines(resPath .. 'zones.csv') do
        -- Support both "id,name," and "id,name"
        local idx, nm = line:match('^(%d+),%s*([^,]+)')
        if idx and nm then
            nm = trim(nm)
            local zid = tonumber(idx)
            resources.attZoneList[zid] = nm
            
            local key = norm(nm)
            resources.zoneNameToIds[key] = resources.zoneNameToIds[key] or {}
            resources.zoneNameToIds[key][zid] = true
        end
    end

    -- jobs.csv
    for line in io.lines(resPath .. 'jobs.csv') do
        local idx, ab = line:match('^(%d+),%s*(.-),')
        if idx and ab then
            resources.attJobList[tonumber(idx)] = ab
        end
    end

    -- shortnames.txt
    for line in io.lines(resPath .. 'shortnames.txt') do
        local alias, fullname = line:match('^(.-),(.*)$')
        if alias and fullname then
            resources.attShortNames[trim(alias):lower()] = trim(fullname)
        end
    end

    -- creditnames.txt
    local currentCategory = nil
    
    -- Track loaded count
    resources.loadedInfo = {
        zones = 0,
        jobs = 0,
        shortNames = 0,
        creditEvents = 0,
        compositions = 0
    }
    
    local function ensure_category(cat)
        if not resources.attendCategories[cat] then
            resources.attendCategories[cat] = {}
            table.insert(resources.attendCategoriesOrder, cat)
        end
    end

    for raw in io.lines(resPath .. 'creditnames.txt') do
        local line = trim(raw)
        if line ~= '' then
            -- Category header
            local cat = line:match('^%-%-%s*(.-)%s*,%s*$') or
                        line:match('^%-%-%s*(.-)%s*$')
            if cat and cat ~= '' then
                currentCategory = cat
                ensure_category(cat)
            else
                -- Event line
                local ev, zone, area = line:match('^([^,]+)%s*,%s*([^,]*)%s*,?%s*(.*)$')
                if ev then
                    ev   = trim(ev)
                    zone = trim(zone or '')
                    area = trim(area or '')
                    
                    resources.loadedInfo.creditEvents = resources.loadedInfo.creditEvents + 1
                    resources.attCreditNames[ev]   = resources.attCreditNames[ev]   or {}
                    resources.attCreditZoneIds[ev] = resources.attCreditZoneIds[ev] or {}

                    if zone ~= '' then
                        table.insert(resources.attCreditNames[ev], zone)
                        local key = norm(zone)
                        local idSet = resources.zoneNameToIds[key]
                        
                        -- Fuzzy match fallback (e.g. "Uleguerand" -> "Uleguerand_Range")
                        if not idSet then
                            for k, v in pairs(resources.zoneNameToIds) do
                                -- Bidirectional check
                                if k:find(key, 1, true) or key:find(k, 1, true) then
                                    idSet = v
                                    -- SILENCED: print(string.format('[att] Fuzzy matched zone "%s" to "%s" for event "%s"', zone, resources.attZoneList[next(v) or 0] or '?', ev))
                                    break
                                end
                            end
                        end

                        if idSet then
                            for zid,_ in pairs(idSet) do
                                resources.attCreditZoneIds[ev][zid] = true
                            end
                        else
                             -- SILENCED: print(string.format('[att] Warning: Could not resolve zone "%s" for event "%s"', zone, ev))
                        end
                    end

                    if area ~= '' then
                        resources.attSearchArea[ev] = area
                        
                        -- Also try to resolve this area to a ZoneID for credit
                        -- This helps if the 2nd column 'zone' name is slightly off but 'area' is correct/shortname
                        local key = norm(area)
                        local idSet = resources.zoneNameToIds[key]
                        
                         -- Fuzzy match fallback
                        if not idSet then
                            for k, v in pairs(resources.zoneNameToIds) do
                                -- Bidirectional check: k contains key OR key contains k
                                if k:find(key, 1, true) or key:find(k, 1, true) then
                                    idSet = v
                                    -- SILENCED: print(string.format('[att] Fuzzy matched search area "%s" to "%s" for event "%s"', area, resources.attZoneList[next(v) or 0] or '?', ev))
                                    break
                                end
                            end
                        end
                         
                        if idSet then
                             for zid,_ in pairs(idSet) do
                                 resources.attCreditZoneIds[ev][zid] = true
                             end
                        end

                    elseif (not resources.attSearchArea[ev]) and zone ~= '' then
                        resources.attSearchArea[ev] = zone
                    end

                    if ev ~= 'Current Zone' then
                        if currentCategory then
                            table.insert(resources.attendCategories[currentCategory], ev)
                        else
                            table.insert(resources.uncategorizedEvents, ev)
                        end
                    end
                end
            end
        end
    end

    if #resources.uncategorizedEvents > 0 then
        local cat = 'Other'
        resources.attendCategories[cat] = resources.attendCategories[cat] or {}
        for _, ev in ipairs(resources.uncategorizedEvents) do
            table.insert(resources.attendCategories[cat], ev)
        end
        table.insert(resources.attendCategoriesOrder, cat)
    end

    -- comps.txt
    local currentCompEvent = nil
    local currentCompSection = nil -- 'Required' or 'Suggested' or specific Party
    local currentPartyIndex = nil -- Track P1, P2 context
    
    local parse_role_line = function(line)
        local count, role = line:match('^(%d+):%s*(.+)$')
        if count and role then
            return tonumber(count), trim(role)
        end
        return nil, nil
    end

    -- Load Compositions from Resources/Comps/*.txt
    local compsDir = resPath .. 'Comps\\'
    -- SILENCED: print('[att] Scanning for compositions in: ' .. compsDir)
    
    local function get_files(path)
        -- Helper to list files
        local i, t, popen = 0, {}, io.popen
        local pfile = popen('dir /b "'..path..'"')
        if not pfile then return nil end
        for filename in pfile:lines() do
            if filename:match('%.txt$') then
                i = i + 1
                t[i] = filename
            end
        end
        pfile:close()
        return t
    end
    
    local files = get_files(compsDir)
    if files then
        for _, filename in ipairs(files) do
            local eventKey = filename:gsub('%.txt$', '')
            -- Capitalize first letter for display niceness
            eventKey = eventKey:sub(1,1):upper() .. eventKey:sub(2)
            
            -- SILENCED: print('[att] Parsing comp file: ' .. filename .. ' -> ' .. eventKey)
            
            resources.compositions[eventKey] = { required = {}, suggested = {}, parties = {} }
            resources.loadedInfo.compositions = resources.loadedInfo.compositions + 1
            
            currentCompEvent = eventKey
            currentCompSection = nil
            currentPartyIndex = nil
            
            for raw in io.lines(compsDir .. filename) do
                local line = trim(raw)
                if line ~= '' then
                    -- Parsing Logic for File-Per-Event (using --Header and P1:)
                    
                    if line:match('^%-%-.*:$') then
                        -- Section Header: --Required:, --Suggested:, --Parties:
                        local secHeader = line:match('^%-%-(.-):$')
                        if secHeader == 'Required' then
                            currentCompSection = 'required'
                        elseif secHeader == 'Suggested' then
                            currentCompSection = 'suggested'
                        elseif secHeader == 'Parties' then
                            currentCompSection = 'parties'
                            currentPartyIndex = nil
                            resources.compositions[eventKey].parties = {}
                            -- SILENCED: print('[att] Found Parties Section for ' .. eventKey)
                        end
                        
                    elseif currentCompSection then
                        if currentCompSection == 'parties' then
                            -- Check for P<n>:
                            local pIdx = line:match('^[Pp](%d+):')
                            if pIdx then
                                 currentPartyIndex = tonumber(pIdx)
                                 local pt = resources.compositions[eventKey].parties
                                 pt[currentPartyIndex] = pt[currentPartyIndex] or {}
                                 -- SILENCED: print('[att] Found Party Index: ' .. pIdx)
                            elseif currentPartyIndex then
                                 -- Role Line
                                 local count, roleName = parse_role_line(line)
                                 if count and roleName then
                                     for i = 1, count do
                                         table.insert(resources.compositions[eventKey].parties[currentPartyIndex], roleName)
                                     end
                                 else
                                     if line:match('^%-%-+$') then
                                         table.insert(resources.compositions[eventKey].parties[currentPartyIndex], 'Any')
                                     else
                                         table.insert(resources.compositions[eventKey].parties[currentPartyIndex], line)
                                     end
                                 end
                            end
                        else
                            -- Required/Suggested
                            local count, roleObj = parse_role_line(line)
                            if count then
                                local entry = { count=count, role=roleObj }
                                table.insert(resources.compositions[eventKey][currentCompSection], entry)
                            end
                        end
                    end
                end
            end
            -- print('[att] Loaded comp: ' .. eventKey) -- Silenced as requested
        end
        print('[att] Comps folder loaded')
    else
        print('[att] Failed to list files in Comps directory.')
    end
end

return resources
