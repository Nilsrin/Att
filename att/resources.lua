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
resources.zoneToSearchArea  = {} -- [ZoneName] = "SearchArea"

resources.attendCategories      = {} -- [category] = { event1, ... }
resources.attendCategoriesOrder = {} -- { category1, ... }
resources.uncategorizedEvents   = {}

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
        creditEvents = 0
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
                    
                    if zone ~= '' and area ~= '' then
                        resources.zoneToSearchArea[zone] = area
                    end
                    
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
end

return resources
