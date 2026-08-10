-- ui.lua
local ui = {}
local imgui = require('imgui')

-- Ashita 4.3 / ImGui 1.90+ detection
local use43 = false
local PM = AshitaCore:GetPluginManager()
if PM then
    local Addons = PM:Get('addons')
    if Addons then
        use43 = (Addons:GetInterfaceVersion() >= 4.3)
    end
end
local orig_BeginChild = imgui.BeginChild
imgui.BeginChild = function(id, size, border, flags)
    local cflags = border
    if use43 then
        if border == true then
            cflags = ImGuiChildFlags_Borders
        elseif border == false or border == nil then
            cflags = ImGuiChildFlags_None
        end
    end
    if flags ~= nil then
        return orig_BeginChild(id, size, cflags, flags)
    elseif cflags ~= nil then
        return orig_BeginChild(id, size, cflags)
    else
        return orig_BeginChild(id, size)
    end
end
local ffi = require('ffi')
local helpers = require('helpers')
local resources = require('resources')

-- Persistent filter state
local filterPtr = { '' }

local function get_sa_flags(state)
    local is_sa = state.g_SAMode
    local is_late = false
    if is_sa and state.selfAttendanceStart then
        local elapsed = os.time() - state.selfAttendanceStart
        if state.saTimerDuration - elapsed <= 30 then
            is_late = true
        end
    end
    return is_sa, is_late
end

function ui.draw_attendance_window(is_open, att_module, state, callbacks)
    if not is_open then return false end
    
    imgui.SetNextWindowSize({ 1050, 600 }, ImGuiCond_FirstUseEver)

    local openPtr = { is_open }
    local isOpen = imgui.Begin('Attendance Results', openPtr)
    if isOpen then

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

        imgui.SameLine()
        imgui.Text('  |  ')
        imgui.SameLine()
        
        -- Late checkbox
        local latePtr = { state.attendForceLate }
        if imgui.Checkbox('Force Late', latePtr) then
            state.attendForceLate = latePtr[1]
        end
        
        imgui.SameLine()
        imgui.Text('  |  ')
        imgui.SameLine()

        local is_sa, is_late = get_sa_flags(state)
        if imgui.Button('Gather Zone') then
            att_module.clear()
            att_module.gather_zone(state.pendingEventName, is_sa, is_late)
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
        
        -- Helper function to render a category
        local function draw_section(header, filter_fn)
            local header_drawn = false
            local i = 1
            while i <= #att_module.data do
                local r = att_module.data[i]
                if filter_fn(r) then
                    if not header_drawn then
                        if header ~= '' then
                            imgui.TextColored({1.0, 0.8, 0.4, 1.0}, header)
                            imgui.Separator()
                        end
                        header_drawn = true
                    end
                    if imgui.Button('Remove##' .. i) then
                        table.remove(att_module.data, i)
                    else
                        imgui.SameLine()
                        imgui.Text(string.format('%s (%s | %s/%s)', r.name, r.late and 'Late' or 'Present', r.jobsMain or '?', r.jobsSub or '?'))
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            end
            if header_drawn then
                imgui.Spacing()
            end
        end

        -- Present
        draw_section('Present', function(r)
            return not r.name:match('^X ') and not r.late
        end)

        -- Late
        draw_section('Late', function(r)
            return r.late == true
        end)

        -- Pending (only show if not late and starts with X)
        draw_section('Pending', function(r)
            return r.name:match('^X ') and not r.late
        end)

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
    end

    imgui.End()
    return openPtr[1]
end

function ui.draw_launcher(is_open, state, callbacks)
    if not is_open then return false end

    imgui.SetNextWindowSize({ 600, 560 }, ImGuiCond_FirstUseEver)
    local openPtr = { is_open }
    local isOpen = imgui.Begin('Att', openPtr)
    if isOpen then
        
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
    end
    imgui.End()
    return openPtr[1]
end


-- Composition window removed

function ui.draw_popout(is_open, state, callbacks)
    if not is_open then return false end

    local evs = state.suggestions and state.suggestions.evs
    local firstEvent = (evs and #evs > 0) and evs[1] or "No Event"

    local btnHeight = 45
    local winHeight = 35
    if evs and #evs > 0 then
        winHeight = winHeight + btnHeight + 10
        if #evs > 1 then
            winHeight = winHeight + (#evs - 1) * (btnHeight + 10)
        end
    else
        winHeight = 80
    end

    imgui.SetNextWindowSize({ 220, winHeight }, ImGuiCond_Always)

    local openPtr = { is_open }
    local isOpen = imgui.Begin('{Attend}###ZonePopout', openPtr)
    if isOpen then
        if evs and #evs > 0 then
            if imgui.Button(firstEvent .. '##popout_ev_1', { -1, btnHeight }) then
                if callbacks.on_launch_event then callbacks.on_launch_event(firstEvent) end
            end

            if #evs > 1 then
                imgui.Separator()
                for i = 2, #evs do
                    if imgui.Button(evs[i] .. '##popout_ev_' .. i, { -1, btnHeight }) then
                        if callbacks.on_launch_event then callbacks.on_launch_event(evs[i]) end
                    end
                end
            end
        else
            imgui.TextDisabled('No events for this zone.')
        end
    end
    imgui.End()
    return openPtr[1]
end

function ui.draw_preferences_window(is_open, state, callbacks)
    if not is_open then return false end

    imgui.SetNextWindowSize({ 380, 260 }, ImGuiCond_FirstUseEver)
    
    local openPtr = { is_open }
    local isOpen = imgui.Begin('ATT Preferences###att_preferences', openPtr)
    if isOpen then
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Interface Settings')
        imgui.Separator()
        
        local autoPopoutPtr = { state.autoPopout }
        if imgui.Checkbox('Enable Quick Attendance Window (Auto-Popout)', autoPopoutPtr) then
            if callbacks.on_auto_popout_change then
                callbacks.on_auto_popout_change(autoPopoutPtr[1])
            end
        end
        imgui.TextDisabled('Automatically opens a small event listing window when entering a zone.')
        
        local defaultLS2Ptr = { state.defaultLS2 }
        if imgui.Checkbox('Default to LS2', defaultLS2Ptr) then
            if callbacks.on_default_ls2_change then
                callbacks.on_default_ls2_change(defaultLS2Ptr[1])
            end
        end
        imgui.TextDisabled('Uses LS2 by default for searches and announcements.')
        
        imgui.Spacing()
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Self Attest Settings')
        imgui.Separator()
        
        if imgui.BeginCombo('Self Attest Events##sa_events_combo', 'Select Events...') then
            for _, cat in ipairs(resources.attendCategoriesOrder) do
                local events = resources.attendCategories[cat] or {}
                if #events > 0 then
                    if imgui.TreeNode(cat .. '##sa_cat_' .. cat) then
                        for _, ev in ipairs(events) do
                            local isChecked = { state.selfAttestEvents[ev] == true }
                            if imgui.Checkbox(ev .. '##sa_pref_' .. ev, isChecked) then
                                state.selfAttestEvents[ev] = isChecked[1] and true or nil
                                if callbacks.on_self_attest_change then
                                    callbacks.on_self_attest_change()
                                end
                            end
                        end
                        imgui.TreePop()
                    end
                end
            end
            imgui.EndCombo()
        end
        imgui.TextDisabled('Checked events will automatically launch in Self-Attest mode.')
    end
    imgui.End()
    return openPtr[1]
end

return ui
