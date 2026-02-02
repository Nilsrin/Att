-- comp.lua
local comp = {}
local resources = require('resources')

comp.isOpen = false
comp.currentEvent = nil
comp.results = nil
comp.show_parties = false
comp.party_results = nil

-- Check if a job string matches a role definition
-- roleName: 'Tank', 'Support', etc. (case insensitive lookup in attRoleDefinitions)
-- jobMain: 'PLD', 'WAR', etc.
-- jobSub: 'NIN', 'DRK', etc.
local function matches_role(roleName, jobMain, jobSub)
    local defs = resources.attRoleDefinitions[roleName:lower()]
    if not defs then return false end

    for _, req in ipairs(defs) do
        -- logic: 
        -- If req has '/', it means Main/Sub (e.g. RDM/DRK)
        -- If req has no '/', it matches Main Job OR Sub Job? 
        -- Wait, usually "Tank = PLD and NIN" implies Main Job PLD or Main Job NIN? 
        -- Or does it imply PLD/WAR is tank, WAR/NIN is tank?
        -- The request says: "Stunner = DRK, BLM or RDM/DRK"
        -- This implies: DRK (Main), BLM (Main), OR RDM (Main) / DRK (Sub).
        
        if req:find('/') then
            local m, s = req:match('^(%w+)/(%w+)$')
            if m and s then
                if jobMain == m and jobSub == s then return true end
            end
        else
            -- Single job specified. Usually implies Main Job.
            -- However, NIN is listed as Tank. NIN main is tank.
            -- Does WAR/NIN count? Usually not in HNM context unless specified.
            -- Let's assume Main Job match for single entries.
            if jobMain == req then return true end
        end
    end
    return false
end

-- Normalize job strings to upper case just in case
local function normalize_job(j)
    return (j or 'NONE'):upper()
end

function comp.evaluate(eventName, roster)
    local compDef = resources.compositions[eventName]
    if not compDef then
        return nil, "No composition defined for " .. eventName
    end

    local result = {
        eventName = eventName,
        required = {},
        suggested = {},
        unassigned = {}
    }

    -- Create a pool of players to assign
    local selfName = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    
    -- Create a pool of players to assign
    local pool = {}
    for _, p in ipairs(roster) do
        -- Filter out 'X ' prefix (SA mode)
        local cleanName = p.name:gsub('^X%s+', '')
        
        -- Exclude self by default as requested
        if cleanName ~= selfName then
            table.insert(pool, {
                name = cleanName,
                jobMain = normalize_job(p.jobsMain),
                jobSub  = normalize_job(p.jobsSub),
                assigned = false
            })
        end
    end

    -- Assign to roles
    -- Priority: Required -> Suggested
    -- Within Required: Order defined in comps.txt (handled by array order)
    
    local function fill_section(sectionDef, outputTable)
        for _, reqEntry in ipairs(sectionDef) do
            local roleName = reqEntry.role
            local needed   = reqEntry.count
            
            -- If the role contains comma, it might be "WHM, RDM".
            -- The parsing in resources.lua split by "1: Role". 
            -- But "WHM, RDM" was captured as the role string.
            -- We need to check if ANY of those match.
            -- attRoleDefinitions keys are single words like 'support'.
            -- If comps.txt says "1: WHM, RDM", it likely means "1 person who is WHM OR RDM".
            -- We should treat "WHM, RDM" as an ad-hoc role list if it's not a predefined key.
            
            local assignedAttendees = {}
            
            -- Try to fill 'needed' spots
            for i = 1, needed do
                -- Find best candidate in pool
                for _, player in ipairs(pool) do
                    if not player.assigned then
                        local isMatch = false
                        
                        -- Check if roleName is a predefined category (e.g. Tank)
                        if resources.attRoleDefinitions[roleName:lower()] then
                            if matches_role(roleName, player.jobMain, player.jobSub) then
                                isMatch = true
                            end
                        else
                            -- Not a predefined category, likely a specific job list "WHM, RDM, SMN"
                            -- Check if player.jobMain appears in the list
                            for jobStr in roleName:gmatch('[^,]+') do
                                local j = jobStr:match('^%s*(.-)%s*$'):upper()
                                if j == player.jobMain then
                                    isMatch = true
                                    break
                                end
                            end
                        end
                        
                        if isMatch then
                            player.assigned = true
                            table.insert(assignedAttendees, player)
                            break -- Filled this slot
                        end
                    end
                end
            end
            
            table.insert(outputTable, {
                role = roleName,
                needed = needed,
                filled = assignedAttendees
            })
        end
    end

    fill_section(compDef.required, result.required)
    fill_section(compDef.suggested, result.suggested)

    -- Remaining
    for _, p in ipairs(pool) do
        if not p.assigned then
            table.insert(result.unassigned, p)
        end
    end

    comp.results = result
    comp.party_results = nil -- Clear old party build
    comp.currentEvent = eventName
    comp.isOpen = true
    return result
end

function comp.build_parties(eventName, roster)
    local compDef = resources.compositions[eventName]
    if not compDef or not compDef.parties or next(compDef.parties) == nil then
        return nil, "No party definitions for " .. eventName
    end

    -- 1. Create Pool (fresh, ignoring current comp assignment)
    -- Actually, usually you want to use the people who are present.
    -- We can use the SAME pool logic as evaluate.
    local pool = {}
    for _, p in ipairs(roster) do
        local cleanName = p.name:gsub('^X%s+', '')
        table.insert(pool, {
            name = cleanName,
            jobMain = normalize_job(p.jobsMain),
            jobSub  = normalize_job(p.jobsSub),
            assigned = false,
            original = p
        })
    end

    -- 2. Sort Parties (P1, P2...)
    local pIndices = {}
    for k in pairs(compDef.parties) do table.insert(pIndices, k) end
    table.sort(pIndices)
    
    local parties = {}

    -- 2. Sort Parties (P1, P2...)
    local pIndices = {}
    for k in pairs(compDef.parties) do table.insert(pIndices, k) end
    table.sort(pIndices)
    
    local initialParties = {}
    -- Initialize Party Objects with Config
    for _, pIdx in ipairs(pIndices) do
        local roleList = compDef.parties[pIdx]
        local partyObj = { name = 'Party ' .. pIdx, members = {}, defs = roleList }
        for i = 1, 6 do
            if i <= #roleList then
                 partyObj.members[i] = { role = roleList[i], empty = true }
            else
                 partyObj.members[i] = nil
            end
        end
        table.insert(initialParties, partyObj)
    end

    -- Create Alliance Structure
    local alliances = {
        { name = 'Alliance 1', parties = initialParties }
    }

    -- Helper: Assign
    local function assign(partyObj, slotIdx, candidate)
        partyObj.members[slotIdx] = {
             name = candidate.name,
             jobMain = candidate.jobMain,
             jobSub  = candidate.jobSub,
             role    = partyObj.members[slotIdx].role,
             empty   = false
        }
        candidate.assigned = true
    end

    -- Logic for filling parties (Scoped to a specific party list)
    local function auto_fill_parties(partyList, pool)
        -- Pass 1: Specific
        for _, p in ipairs(partyList) do
            for i = 1, 6 do
                local slot = p.members[i]
                if slot and slot.role ~= 'Any' and slot.empty then
                    for _, cand in ipairs(pool) do
                        if not cand.assigned then
                             local isMatch = false
                             local r = slot.role
                             if resources.attRoleDefinitions[r:lower()] then
                                 if matches_role(r, cand.jobMain, cand.jobSub) then isMatch = true end
                             else
                                 if r:upper() == cand.jobMain then isMatch = true end
                             end
                             if isMatch then
                                 assign(p, i, cand)
                                 break
                             end
                        end
                    end
                end
            end
        end
        -- Pass 2: Any
        for _, p in ipairs(partyList) do
            for i = 1, 6 do
                local slot = p.members[i]
                if slot and slot.role == 'Any' and slot.empty then
                     for _, cand in ipairs(pool) do
                         if not cand.assigned then
                             assign(p, i, cand)
                             break
                         end
                     end
                end
            end
        end
    end

    -- Auto-fill the initial alliance
    auto_fill_parties(alliances[1].parties, pool)
    
    -- Unassigned
    local unassigned = {}
    for _, c in ipairs(pool) do
        if not c.assigned then table.insert(unassigned, c) end
    end
    
    comp.party_results = { alliances = alliances, unassigned = unassigned }
    comp.show_parties = true
    return comp.party_results
end

function comp.manual_assign(playerName, allianceIdx, partyIdx, targetSlotIdx)
    if not comp.party_results then return end
    
    -- 1. Find Player Source
    local playerObj = nil
    local sourceLocation = nil -- { type='unassigned', idx=... } or { type='party', aIdx=..., pIdx=..., sIdx=... }
    
    -- Check Unassigned
    for i, p in ipairs(comp.party_results.unassigned) do
        if p.name == playerName then
            playerObj = p
            sourceLocation = { type='unassigned', idx=i }
            break
        end
    end
    
    -- Check Alliances for Source
    if not playerObj then
        for aIdx, alliance in ipairs(comp.party_results.alliances) do
            for pIdx, party in ipairs(alliance.parties) do
                for sIdx, member in pairs(party.members) do
                     if member and not member.empty and member.name == playerName then
                         playerObj = member
                         sourceLocation = { type='party', aIdx=aIdx, pIdx=pIdx, sIdx=sIdx }
                         goto found
                     end
                end
            end
        end
        ::found::
    end
    
    if not playerObj then return end 
    
    -- 2. Identify Target
    local targetAlliance = comp.party_results.alliances[allianceIdx]
    if not targetAlliance then return end
    local targetParty = targetAlliance.parties[partyIdx]
    if not targetParty then return end
    local targetSlot = targetParty.members[targetSlotIdx]
    
    -- 3. Execute Move
    if targetSlot and targetSlot.empty then
        -- Move to Empty
        targetSlot.name = playerObj.name
        targetSlot.jobMain = playerObj.jobMain
        targetSlot.jobSub = playerObj.jobSub
        targetSlot.empty = false
        
        -- Remove Source
        if sourceLocation.type == 'unassigned' then
            table.remove(comp.party_results.unassigned, sourceLocation.idx)
        elseif sourceLocation.type == 'party' then
            local srcSlot = comp.party_results.alliances[sourceLocation.aIdx].parties[sourceLocation.pIdx].members[sourceLocation.sIdx]
            srcSlot.name = nil
            srcSlot.jobMain = nil
            srcSlot.jobSub = nil
            srcSlot.empty = true
        end
    else
        -- Swap
        local targetOccupant = {
            name = targetSlot.name,
            jobMain = targetSlot.jobMain,
            jobSub = targetSlot.jobSub
        }
        
        targetSlot.name = playerObj.name
        targetSlot.jobMain = playerObj.jobMain
        targetSlot.jobSub = playerObj.jobSub
        
        if sourceLocation.type == 'unassigned' then
             comp.party_results.unassigned[sourceLocation.idx] = targetOccupant
        elseif sourceLocation.type == 'party' then
             local srcSlot = comp.party_results.alliances[sourceLocation.aIdx].parties[sourceLocation.pIdx].members[sourceLocation.sIdx]
             srcSlot.name = targetOccupant.name
             srcSlot.jobMain = targetOccupant.jobMain
             srcSlot.jobSub = targetOccupant.jobSub
             srcSlot.empty = false
        end
    end
end

function comp.unassign_player(playerName)
    if not comp.party_results then return end
    
    for _, alliance in ipairs(comp.party_results.alliances) do
        for _, party in ipairs(alliance.parties) do
            for _, member in pairs(party.members) do
                 if member and not member.empty and member.name == playerName then
                     -- Add to Unassigned
                     local pObj = {
                         name = member.name,
                         jobMain = member.jobMain,
                         jobSub = member.jobSub,
                         assigned = false
                     }
                     table.insert(comp.party_results.unassigned, pObj)
                     -- Clear Slot
                     member.name = nil
                     member.jobMain = nil
                     member.jobSub = nil
                     member.empty = true
                     return
                 end
            end
        end
    end
end

function comp.add_group(eventName)
    if not comp.party_results then return end
    local compDef = resources.compositions[eventName]
    if not compDef then return end
    
    local allianceCount = #comp.party_results.alliances
    
    -- Sort Config Indices
    local pIndices = {}
    for k in pairs(compDef.parties) do table.insert(pIndices, k) end
    table.sort(pIndices)
    
    -- Create New Parties
    local newParties = {}
    for _, pIdx in ipairs(pIndices) do
        local roleList = compDef.parties[pIdx]
        local partyObj = { name = 'Party ' .. pIdx, members = {}, defs = roleList }
        for j = 1, 6 do
            if j <= #roleList then
                 partyObj.members[j] = { role = roleList[j], empty = true } 
            else
                 partyObj.members[j] = nil
            end
        end
        table.insert(newParties, partyObj)
    end
    
    local newAlliance = {
        name = 'Alliance ' .. (allianceCount + 1),
        parties = newParties
    }
    
    -- Auto-Fill NEW Alliance from Unassigned Pool
    local pool = comp.party_results.unassigned
    local function mock_assign(partyObj, slotIdx, candidate, poolIdx)
        partyObj.members[slotIdx] = {
             name = candidate.name,
             jobMain = candidate.jobMain,
             jobSub  = candidate.jobSub,
             role    = partyObj.members[slotIdx].role,
             empty   = false
        }
        candidate.assigned = true 
    end
    
    -- Logic replicated for new group
    -- Pass 1
    for _, p in ipairs(newAlliance.parties) do
        for i = 1, 6 do
            local slot = p.members[i]
            if slot and slot.role ~= 'Any' and slot.empty then
                for _, cand in ipairs(pool) do
                    if not cand.assigned then
                         local isMatch = false
                         local r = slot.role
                         if resources.attRoleDefinitions[r:lower()] then
                             if matches_role(r, cand.jobMain, cand.jobSub) then isMatch = true end
                         else
                             if r:upper() == cand.jobMain then isMatch = true end
                         end
                         if isMatch then
                             mock_assign(p, i, cand)
                             break
                         end
                    end
                end
            end
        end
    end
    -- Pass 2
    for _, p in ipairs(newAlliance.parties) do
        for i = 1, 6 do
            local slot = p.members[i]
            if slot and slot.role == 'Any' and slot.empty then
                 for _, cand in ipairs(pool) do
                     if not cand.assigned then
                         mock_assign(p, i, cand)
                         break
                     end
                 end
            end
        end
    end
    
    -- Update Unassigned List (Remove Assigned)
    local newUnassigned = {}
    for _, c in ipairs(pool) do
        if not c.assigned then
            table.insert(newUnassigned, c)
        else
            c.assigned = false 
        end
    end
    comp.party_results.unassigned = newUnassigned
    
    table.insert(comp.party_results.alliances, newAlliance)
    return true
end

function comp.remove_alliance(idx)
    if not comp.party_results or not comp.party_results.alliances[idx] then return end
    
    local alliance = comp.party_results.alliances[idx]
    
    -- 1. Move all members to unassigned
    for _, party in ipairs(alliance.parties) do
        for _, member in pairs(party.members) do
            if member and not member.empty and member.name then
                 table.insert(comp.party_results.unassigned, {
                     name = member.name,
                     jobMain = member.jobMain,
                     jobSub = member.jobSub,
                     assigned = false
                 })
            end
        end
    end
    
    -- 2. Remove Alliance
    table.remove(comp.party_results.alliances, idx)
    
    -- 3. Rename remaining
    for i, a in ipairs(comp.party_results.alliances) do
        a.name = 'Alliance ' .. i
    end
end

function comp.refresh_unassigned(new_roster)
    if not comp.party_results then return end

    -- 1. Gather all currently assigned names
    local assigned_names = {}
    for _, alliance in ipairs(comp.party_results.alliances) do
        for _, party in ipairs(alliance.parties) do
            for _, member in pairs(party.members) do
                if member and not member.empty and member.name then
                    assigned_names[member.name] = true
                end
            end
        end
    end

    -- 2. Build new unassigned list from new_roster
    local new_unassigned = {}
    -- Need self name to exclude (logic matches evaluate)
    local selfName = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)

    for _, p in ipairs(new_roster) do
        local cleanName = p.name:gsub('^X%s+', '')
        
        if cleanName ~= selfName and not assigned_names[cleanName] then
             table.insert(new_unassigned, {
                 name = cleanName,
                 jobMain = normalize_job(p.jobsMain),
                 jobSub  = normalize_job(p.jobsSub),
                 assigned = false
             })
        end
    end

    comp.party_results.unassigned = new_unassigned
end

function comp.clear()
    comp.results = nil
    comp.party_results = nil
    comp.currentEvent = nil
    comp.isOpen = false
    comp.show_parties = false
end

return comp
