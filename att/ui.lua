-- ui.lua
local ui = {}
local imgui = require('imgui')
local ffi = require('ffi')
local helpers = require('helpers')
local resources = require('resources')

-- Persistent filter state
local filterPtr = { '' }

function ui.draw_attendance_window(is_open, att_module, state, callbacks)
    if not is_open then return false end
    
    imgui.SetNextWindowSize({ 1050, 600 }, ImGuiCond_FirstUseEver)

    local openPtr = { is_open }
    if imgui.Begin('Attendance Results', openPtr) then

        if state.g_SAMode and state.selfAttendanceStart then
            local elapsed   = os.time() - state.selfAttendanceStart
            local remaining = state.saTimerDuration - elapsed
            if remaining < 0 then remaining = 0 end
            local mins = (remaining - (remaining % 60)) / 60
            local secs = (remaining % 60)
            imgui.Text(string.format('Time until auto-submit: %02d:%02d', mins, secs))
            imgui.Separator()
        end

        if state.g_SAMode then
            if imgui.Button('Show Pending') then
                if callbacks.on_show_pending then callbacks.on_show_pending() end
            end
            imgui.SameLine()
            if imgui.Button('Refresh Data') then
                if callbacks.on_refresh_sa then callbacks.on_refresh_sa() end
            end
            imgui.Separator()
        end

        imgui.Text('Select Mode:')
        imgui.SameLine()
        if imgui.RadioButton('HNM', state.selectedMode == 'HNM') then
            state.selectedMode = 'HNM'
        end
        imgui.SameLine()
        if imgui.RadioButton('Event', state.selectedMode == 'Event') then
            state.selectedMode = 'Event'
        end

        imgui.Separator()
        imgui.Text('Attendance for: ' .. (state.pendingEventName or ''))
        
        local znames = resources.attCreditNames[state.pendingEventName]
        imgui.Text('Credit Zones: ' .. (((znames and #znames > 0) and table.concat(znames, ', ')) or 'UnknownZone'))
        imgui.Separator()

        imgui.Text('Attendees: ' .. #att_module.data)

        if imgui.Button('Party Only') then
            if callbacks.on_party_only then callbacks.on_party_only() end
        end
        imgui.SameLine()

        if imgui.Button('Rescan') then
            att_module.gather_zone(state.pendingEventName)
        end
        imgui.SameLine()
        
        -- Scan Letter logic
        if not state.scanNextLetter then
             -- Simple heuristic if none set
             local last = att_module.data[#att_module.data]
             local ch = (last and last.name) and last.name:match('^X?%s*(%a)') or 'A'
             state.scanNextLetter = ch:upper()
        end

        if imgui.Button('Scan ' .. state.scanNextLetter) then
             if callbacks.on_scan_letter then callbacks.on_scan_letter(state.scanNextLetter) end
             state.scanNextLetter = helpers.get_next_letter(state.scanNextLetter)
        end

        imgui.Separator()

        imgui.BeginChild('att_list', { 0, -50 }, true)
        local i = 1
        while i <= #att_module.data do
            local r = att_module.data[i]
            if imgui.Button('Remove##' .. i) then
                table.remove(att_module.data, i)
            else
                imgui.SameLine()
                imgui.Text(string.format('%s (%s | %s/%s)', r.name, r.zone, r.jobsMain, r.jobsSub))
                i = i + 1
            end
        end
        imgui.EndChild()
        imgui.Separator()

        if imgui.Button('Write') then
             if callbacks.on_write then callbacks.on_write(false) end
        end
        imgui.SameLine()
        if imgui.Button('Write & Close') then
             if callbacks.on_write then callbacks.on_write(true) end
             openPtr[1] = false
        end
        imgui.SameLine()
        if imgui.Button('Cancel') then
            openPtr[1] = false
        end

        imgui.End()
    end
    
    return openPtr[1]
end

function ui.draw_launcher(is_open, state, callbacks)
    if not is_open then return false end

    imgui.SetNextWindowSize({ 600, 560 }, ImGuiCond_FirstUseEver)
    local openPtr = { is_open }
    if imgui.Begin('Att', openPtr) then
        
        -- Settings
        local ls2Ptr = { state.attendUseLS2 }
        if imgui.Checkbox('Use LS2', ls2Ptr) then state.attendUseLS2 = ls2Ptr[1] end
        imgui.SameLine()
        local saPtr = { state.attendSelfAttest }
        if imgui.Checkbox('Self Attest', saPtr) then state.attendSelfAttest = saPtr[1] end
        imgui.SameLine()
        
        local delayPtr = { state.attendDelaySec }
        imgui.PushItemWidth(32)
        if imgui.InputInt('##delay', delayPtr, 0, 0) then
            state.attendDelaySec = helpers.clamp_0_99(delayPtr[1])
        end
        imgui.PopItemWidth()
        
        imgui.SameLine()
        imgui.Text('Delay (sec)')
        imgui.SameLine()
        if imgui.Button('Update Zone') then
            if callbacks.on_update_zone then callbacks.on_update_zone() end
        end
        imgui.Separator()
        
        -- Suggestions
        do
            local evs, zname = state.suggestions.evs, state.suggestions.zone
            if evs and #evs > 0 then
                for idx, ev in ipairs(evs) do
                    if idx > 1 then imgui.SameLine() end
                    if imgui.Button(string.format('%s##attend_suggest_%d', ev, idx)) then
                        if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                    end
                end
                imgui.SameLine()
                imgui.TextDisabled(string.format('Zone: %s', zname or 'UnknownZone'))
            else
                imgui.TextDisabled('No event mapping found for current zone.')
            end
        end
        imgui.Separator()
        
        -- Categories
        imgui.BeginChild('attend_list', { 0, -40 }, true)
        for _, cat in ipairs(resources.attendCategoriesOrder) do
            local events = resources.attendCategories[cat] or {}
            if #events > 0 then
                if imgui.CollapsingHeader(string.format('%s (%d)', cat, #events)) then
                    for _, ev in ipairs(events) do
                        local area = resources.attSearchArea[ev] or (resources.attCreditNames[ev] and resources.attCreditNames[ev][1]) or ''
                        if imgui.Button(string.format('%s##btn_%s', ev, ev)) then
                             if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                        end
                        if area ~= '' then
                            imgui.SameLine()
                            imgui.TextDisabled(string.format('/sea %s linkshell%s', area, state.attendUseLS2 and '2' or ''))
                        end
                    end
                end
            end
        end
        imgui.EndChild()
        imgui.Separator()
        
        if imgui.Button('Close##attend') then openPtr[1] = false end
        imgui.End()
    end
    return openPtr[1]
end


function ui.draw_composition_window(is_open, comp_module)
    if not is_open or not comp_module.results then return false end

    -- Calculate Required Width
    -- Req Column (300) + Padding (~30) + Alliances (Count * (310 + 8 padding))
    local allianceCount = (comp_module.party_results and comp_module.party_results.alliances) and #comp_module.party_results.alliances or 1
    local targetWidth = 340 + (allianceCount * 320)
    if targetWidth < 800 then targetWidth = 800 end -- Min width
    
    -- Dynamic Resize if count changed
    comp_module.uiState = comp_module.uiState or {}
    if comp_module.uiState.lastAllianceCount ~= allianceCount then
        imgui.SetNextWindowSize({ targetWidth, 600 }, ImGuiCond_Always)
        comp_module.uiState.lastAllianceCount = allianceCount
    else
        imgui.SetNextWindowSize({ targetWidth, 600 }, ImGuiCond_FirstUseEver)
    end

    local openPtr = { is_open }
    if imgui.Begin('Composition Check: ' .. (comp_module.currentEvent or 'Unknown'), openPtr) then
        
        local res = comp_module.results
        
        -- LEFT COLUMN: Requirements
        imgui.BeginChild('col_req', { 300, -40 }, true)
        imgui.Text('Requirements')
        imgui.Separator()
        
        local function draw_section(title, data)
            imgui.TextColored({0.4, 1.0, 0.4, 1.0}, title)
            
            for _, entry in ipairs(data) do
                local have = #entry.filled
                local need = entry.needed
                local color = (have >= need) and {0.6, 1.0, 0.6, 1.0} or {1.0, 0.4, 0.4, 1.0}
                
                imgui.TextColored(color, string.format('[%d/%d] %s', have, need, entry.role))
                if have > 0 then
                    for _, p in ipairs(entry.filled) do
                        imgui.Indent(15)
                        -- Selectable Name
                        local is_selected = (comp_module.selected_player == p.name)
                        if imgui.Selectable(string.format('%s (%s/%s)', p.name, p.jobMain, p.jobSub), is_selected) then
                            -- Toggle selection
                            if is_selected then
                                comp_module.selected_player = nil
                            else
                                comp_module.selected_player = p.name
                            end
                        end
                        imgui.Unindent(15)
                    end
                end
            end
            imgui.Spacing()
        end

        draw_section('Required', res.required)
        draw_section('Suggested', res.suggested)
        
        imgui.Separator()
        imgui.Separator()
        
        -- Persistent buffers
        comp_module.uiState.newName = comp_module.uiState.newName or { '' }
        
        -- Header
        imgui.Text('Unassigned Pool')
        imgui.Separator()

        -- Search Filter
        imgui.InputText('Filter', filterPtr, 64)
        local filter_str = (filterPtr[1] or ''):lower()
        
        imgui.Separator()
        
        -- Gather and Sort from Dynamic Party Results
        local display_list = {}
        local source_pool = (comp_module.party_results and comp_module.party_results.unassigned) or res.unassigned
        
        for _, p in ipairs(source_pool) do
            local text = string.format('%s %s/%s', p.name, p.jobMain, p.jobSub):lower()
            if filter_str == '' or text:find(filter_str) then
                table.insert(display_list, p)
            end
        end
        table.sort(display_list, function(a,b) return a.name < b.name end)
        
        -- 4. Render List
        imgui.BeginChild('unassigned_list_inner', { 0, 0 }, true) -- Fill remaining height
        for _, p in ipairs(display_list) do
            local label = string.format('%s (%s/%s)', p.name, p.jobMain, p.jobSub)
            local is_selected = (comp_module.selected_player == p.name)
            
            if imgui.Selectable(label, is_selected) then
                if is_selected then
                    comp_module.selected_player = nil
                else
                    comp_module.selected_player = p.name
                end
            end
        end
        
        -- Clickable "Blank Space" to Unassign
        -- Use { -1, -1 } to fill remaining content region
        -- Make it transparent/background color
        imgui.PushStyleColor(ImGuiCol_Button, {0,0,0,0})
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0,0,0,0})
        imgui.PushStyleColor(ImGuiCol_ButtonActive, {0,0,0,0})
        imgui.PushStyleColor(ImGuiCol_Border, {0,0,0,0})
        
        if imgui.Button('##drop_unassign', { -1, -1 }) then
             if comp_module.selected_player then
                comp_module.unassign_player(comp_module.selected_player)
                comp_module.selected_player = nil
             end
        end
        imgui.PopStyleColor(4)
        
        imgui.EndChild()
        imgui.EndChild()
        
        imgui.SameLine()
        
        -- RIGHT COLUMN: Parties
        imgui.BeginChild('col_party', { 0, -40 }, true)
        if imgui.Button('Create Alliance') then
            comp_module.add_group(comp_module.currentEvent)
        end
        imgui.Separator()
        
        if comp_module.party_results and comp_module.party_results.alliances then
            for aIdx, alliance in ipairs(comp_module.party_results.alliances) do
                if aIdx > 1 then imgui.SameLine() end
                
                -- Use Sub-Window for Alliance
                imgui.BeginChild('alliance_' .. aIdx, { 310, 0 }, true)
                imgui.TextColored({0.4, 0.8, 1.0, 1.0}, alliance.name)
                imgui.SameLine()
                if imgui.SmallButton('Delete##del_all_' .. aIdx) then
                    comp_module.remove_alliance(aIdx)
                end
                imgui.Separator()
                
                for pIdx, p in ipairs(alliance.parties) do
                    imgui.Text(p.name)
                    for i = 1, 6 do
                        if p.members[i] then
                            local m = p.members[i]
                            if m.empty then
                                -- Empty Slot
                                local label = string.format('%d. [%s] ---##%d-%d-%d', i, m.role, aIdx, pIdx, i)
                                if imgui.Selectable(label) then
                                    if comp_module.selected_player then
                                        comp_module.manual_assign(comp_module.selected_player, aIdx, pIdx, i)
                                        comp_module.selected_player = nil
                                    end
                                end
                            else
                                -- Filled Slot
                                local label = string.format('%d. [%s] %s (%s)##%d-%d-%d', i, m.role, m.name, m.jobMain, aIdx, pIdx, i)
                                local is_selected = (comp_module.selected_player == m.name)
                                if imgui.Selectable(label, is_selected) then
                                    if comp_module.selected_player and comp_module.selected_player ~= m.name then
                                        -- Swap
                                        comp_module.manual_assign(comp_module.selected_player, aIdx, pIdx, i)
                                        comp_module.selected_player = nil 
                                    else
                                        -- Select
                                        if is_selected then
                                            comp_module.selected_player = nil
                                        else
                                            comp_module.selected_player = m.name
                                        end
                                    end
                                end
                            end
                        else
                             imgui.TextDisabled(string.format('%d. ---', i))
                        end
                    end
                    imgui.Separator()
                end
                
                imgui.EndChild() -- End Alliance Window
            end
            
        else
            imgui.TextDisabled('No parties built yet. Click Create Alliance.')
        end
        
        imgui.EndChild()
        
        -- Footer Buttons
        imgui.Separator()
        
        if imgui.Button('Close') then openPtr[1] = false end
        imgui.SameLine()
        if imgui.Button('Refresh Roster') then
             -- 1. Gather (Async-like but immediate call here)
             if att_module and comp_module.currentEvent then
                att_module.gather_zone(comp_module.currentEvent)
                -- 2. Update Comp Pool
                comp_module.refresh_unassigned(att_module.data)
             end
        end

        imgui.End()
    end
    
    return openPtr[1]
end

-- Debug window removed


return ui
