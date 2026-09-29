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
local manualAddBuffer = { '' }
local manualAddMessage = nil
local manualAddMessageTime = 0

local function get_sa_flags(state)
    return state.g_SAMode
end

function ui.draw_attendance_window(is_open, att_module, state, callbacks)
    if not is_open then return false end
    
    imgui.SetNextWindowSize({ 1050, 600 }, ImGuiCond_FirstUseEver)

    local openPtr = { is_open }
    local isOpen = imgui.Begin('Attendance Results', openPtr)
    if isOpen then

        if state.g_SAMode and state.selfAttendanceStart then
            local headerText = 'Self-Attendance Active'
            if state.pendingEventName and state.pendingEventName ~= '' then
                headerText = headerText .. ' - ' .. state.pendingEventName
            end
            imgui.TextColored({1.0, 0.8, 0.2, 1.0}, headerText)
            
            local elapsed = os.time() - state.selfAttendanceStart
            local remaining = math.max(0, (state.saTimerDuration or 300) - elapsed)
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            imgui.SameLine()
            imgui.TextDisabled(string.format('(%02d:%02d remaining)', mins, secs))
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
            imgui.SameLine()
            if imgui.Button('Check In All Pending') then
                att_module.confirm_all_pending()
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

        local is_sa = get_sa_flags(state)
        if imgui.Button('Gather Zone') then
            att_module.clear()
            att_module.gather_zone(state.pendingEventName, is_sa)
        end
        imgui.SameLine()
        
        -- Scan Letter logic
        if not state.scanNextLetter then
             -- Simple heuristic if none set
             local last = att_module.data[#att_module.data]
             local cleanLast = last and helpers.strip_prefix(last.name)
             local ch = (cleanLast and cleanLast ~= '') and cleanLast:match('^(%a)') or 'A'
             state.scanNextLetter = ch:upper()
         end

        if imgui.Button('Scan ' .. state.scanNextLetter) then
             if callbacks.on_scan_letter then callbacks.on_scan_letter(state.scanNextLetter) end
             state.scanNextLetter = helpers.get_next_letter(state.scanNextLetter)
        end

        imgui.Separator()

        -- Manual Add Player bar
        imgui.Text('Add Player:')
        imgui.SameLine()
        imgui.PushItemWidth(140)
        local enterFlag = ImGuiInputTextFlags_EnterReturnsTrue or 32
        local enterPressed = imgui.InputText('##manual_add_name', manualAddBuffer, 32, enterFlag)
        imgui.PopItemWidth()
        imgui.SameLine()
        local addClicked = imgui.Button('Add Person##btn_add_player')
        
        if (enterPressed or addClicked) and manualAddBuffer[1] and manualAddBuffer[1] ~= '' then
            local success, msg = att_module.manual_add_player(manualAddBuffer[1])
            if success then
                manualAddBuffer[1] = ''
                manualAddMessage = msg
            else
                manualAddMessage = msg or 'Could not add player'
            end
            manualAddMessageTime = os.clock() + 3
        end

        if manualAddMessage and os.clock() < manualAddMessageTime then
            imgui.SameLine()
            imgui.TextDisabled(string.format('(%s)', manualAddMessage))
        end

        imgui.Separator()

        -- Calculate Present, Pending, and Unlisted Counts
        local present_count = 0
        local pending_count = 0
        local unlisted_count = 0
        for _, r in ipairs(att_module.data) do
            if helpers.is_pending(r.name) then
                pending_count = pending_count + 1
            elseif helpers.is_unlisted(r.name) then
                unlisted_count = unlisted_count + 1
            else
                present_count = present_count + 1
            end
        end

        -- Summary Bar above Present area
        imgui.Text('Attendance:')
        imgui.SameLine()
        imgui.Text(string.format('Total: %d', #att_module.data))
        imgui.SameLine()
        imgui.TextDisabled('|')
        imgui.SameLine()
        imgui.TextColored({0.4, 1.0, 0.4, 1.0}, string.format('Confirmed: %d', present_count))
        imgui.SameLine()
        imgui.TextDisabled('|')
        imgui.SameLine()
        imgui.TextColored({1.0, 0.65, 0.4, 1.0}, string.format('Pending: %d', pending_count))
        if unlisted_count > 0 then
            imgui.SameLine()
            imgui.TextDisabled('|')
            imgui.SameLine()
            imgui.TextColored({0.4, 0.8, 1.0, 1.0}, string.format('Unlisted: %d', unlisted_count))
        end
        imgui.Separator()

        imgui.BeginChild('att_list', { 0, -50 }, true)
        
        -- 1. Present Section
        if present_count > 0 or (pending_count == 0 and unlisted_count == 0) then
            imgui.TextColored({0.4, 1.0, 0.4, 1.0}, string.format('Present (%d)', present_count))
            imgui.Separator()
            local i = 1
            while i <= #att_module.data do
                local r = att_module.data[i]
                if not helpers.is_unconfirmed(r.name) then
                    if imgui.Button('Remove##present_' .. i) then
                        table.remove(att_module.data, i)
                    else
                        imgui.SameLine()
                        imgui.TextColored({0.4, 1.0, 0.4, 1.0}, r.name)
                        imgui.SameLine()
                        imgui.TextDisabled(string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                        if r.zone and r.zone ~= '' then
                            imgui.SameLine()
                            imgui.TextDisabled(string.format('[%s]', r.zone))
                        end
                        if r.time and r.time ~= '' then
                            imgui.SameLine()
                            imgui.TextDisabled(string.format('@ %s', r.time))
                        end
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            end
            imgui.Spacing()
        end

        -- 2. Pending Section (Initial zone roster eligible players who haven't checked in)
        if pending_count > 0 then
            imgui.TextColored({1.0, 0.8, 0.4, 1.0}, string.format('Pending (%d)', pending_count))
            imgui.SameLine()
            if imgui.Button('Check In All##pending_all_sec') then
                att_module.confirm_all_pending()
            end
            imgui.Separator()

            local i = 1
            while i <= #att_module.data do
                local r = att_module.data[i]
                if helpers.is_pending(r.name) then
                    if imgui.Button('Check In##pending_' .. i) then
                        att_module.confirm_entry(i)
                    else
                        imgui.SameLine()
                        if imgui.Button('Remove##pending_rm_' .. i) then
                            table.remove(att_module.data, i)
                        else
                            imgui.SameLine()
                            local displayName = helpers.strip_prefix(r.name)
                            imgui.TextColored({1.0, 0.65, 0.4, 1.0}, displayName)
                            imgui.SameLine()
                            imgui.TextDisabled(string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                            if r.zone and r.zone ~= '' then
                                imgui.SameLine()
                                imgui.TextDisabled(string.format('[%s]', r.zone))
                            end
                            i = i + 1
                        end
                    end
                else
                    i = i + 1
                end
            end
            imgui.Spacing()
        end

        -- 3. Unlisted Requests / Needs Approval Section (People not on initial roster who typed !here)
        if unlisted_count > 0 then
            imgui.TextColored({0.4, 0.8, 1.0, 1.0}, string.format('Unlisted Requests / Needs Approval (%d)', unlisted_count))
            imgui.SameLine()
            if imgui.Button('Approve All##unlisted_all_sec') then
                att_module.approve_all_unlisted()
            end
            imgui.Separator()

            local i = 1
            while i <= #att_module.data do
                local r = att_module.data[i]
                if helpers.is_unlisted(r.name) then
                    if imgui.Button('Approve##unlisted_' .. i) then
                        att_module.confirm_entry(i)
                    else
                        imgui.SameLine()
                        if imgui.Button('Remove##unlisted_rm_' .. i) then
                            table.remove(att_module.data, i)
                        else
                            imgui.SameLine()
                            local displayName = helpers.strip_prefix(r.name)
                            imgui.TextColored({0.4, 0.8, 1.0, 1.0}, displayName)
                            imgui.SameLine()
                            imgui.TextDisabled(string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                            if r.zone and r.zone ~= '' then
                                imgui.SameLine()
                                imgui.TextDisabled(string.format('[%s]', r.zone))
                            end
                            if r.time and r.time ~= '' then
                                imgui.SameLine()
                                imgui.TextDisabled(string.format('@ %s', r.time))
                            end
                            i = i + 1
                        end
                    end
                else
                    i = i + 1
                end
            end
            imgui.Spacing()
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
    end

    imgui.End()
    return openPtr[1]
end

-- Main Menu State
local eventSearchFilter = { '' }
local customEventName   = { '' }
local customSearchArea  = { '' }
local customUseLS2      = false
local customSelfAttest  = false

function ui.draw_launcher(is_open, state, callbacks)
    if not is_open then return false end

    imgui.SetNextWindowSize({ 650, 600 }, ImGuiCond_FirstUseEver)
    local openPtr = { is_open }
    local isOpen = imgui.Begin('ATT - Main Menu###att_main_menu', openPtr)
    if isOpen then
        if imgui.BeginTabBar('##att_main_tab_bar') then
            
            -- =================================================================
            -- TAB 1: Events Launcher
            -- =================================================================
            if imgui.BeginTabItem('Events') then
                -- Quick Settings Bar
                local ls2Ptr = { state.attendUseLS2 }
                if imgui.Checkbox('Use LS2', ls2Ptr) then state.attendUseLS2 = ls2Ptr[1] end
                imgui.SameLine()
                local saPtr = { state.attendSelfAttest }
                if imgui.Checkbox('Self Attest (SA)', saPtr) then state.attendSelfAttest = saPtr[1] end
                imgui.SameLine()
                
                local delayPtr = { state.attendDelaySec }
                imgui.PushItemWidth(35)
                if imgui.InputInt('##delay', delayPtr, 0, 0) then
                    state.attendDelaySec = helpers.clamp_0_99(delayPtr[1])
                end
                imgui.PopItemWidth()
                imgui.SameLine()
                imgui.Text('Delay (s)')
                imgui.SameLine()
                if imgui.Button('Update Zone') then
                    if callbacks.on_update_zone then callbacks.on_update_zone() end
                end
                imgui.SameLine()
                if imgui.Button('Take Attendance Here') then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att here')
                end
                imgui.Separator()

                -- Current Zone Suggestions
                do
                    local evs, zname = state.suggestions.evs, state.suggestions.zone
                    imgui.TextColored({0.4, 0.8, 1.0, 1.0}, string.format('Current Zone: %s', zname or 'UnknownZone'))
                    if evs and #evs > 0 then
                        for idx, ev in ipairs(evs) do
                            if idx > 1 then imgui.SameLine() end
                            if imgui.Button(string.format('%s##attend_suggest_%d', ev, idx)) then
                                if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                            end
                        end
                    else
                        imgui.TextDisabled('No event presets configured for this zone.')
                    end
                end
                imgui.Separator()

                -- Search / Filter bar for events
                imgui.Text('Filter Events:')
                imgui.SameLine()
                imgui.PushItemWidth(200)
                imgui.InputText('##event_search_filter', eventSearchFilter, 32)
                imgui.PopItemWidth()
                if eventSearchFilter[1] and eventSearchFilter[1] ~= '' then
                    imgui.SameLine()
                    if imgui.Button('Clear##clear_ev_search') then
                        eventSearchFilter[1] = ''
                    end
                end

                local filterText = helpers.trim(eventSearchFilter[1] or ''):lower()

                -- Categorized Events Child Window
                imgui.BeginChild('attend_events_list', { 0, -35 }, true)
                for _, cat in ipairs(resources.attendCategoriesOrder) do
                    local events = resources.attendCategories[cat] or {}
                    if #events > 0 then
                        local matchingEvents = {}
                        for _, ev in ipairs(events) do
                            if filterText == '' or ev:lower():find(filterText, 1, true) or cat:lower():find(filterText, 1, true) then
                                table.insert(matchingEvents, ev)
                            end
                        end

                        if #matchingEvents > 0 then
                            local headerFlags = (filterText ~= '') and ImGuiTreeNodeFlags_DefaultOpen or 0
                            if imgui.CollapsingHeader(string.format('%s (%d)###cat_%s', cat, #matchingEvents, cat), headerFlags) then
                                for _, ev in ipairs(matchingEvents) do
                                    local area = resources.attSearchArea[ev] or (resources.attCreditNames[ev] and resources.attCreditNames[ev][1]) or ''
                                    local isSA = state.selfAttestEvents[ev] == true
                                    
                                    if imgui.Button(string.format('%s##btn_%s', ev, ev)) then
                                         if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                                    end
                                    if isSA then
                                        imgui.SameLine()
                                        imgui.TextColored({1.0, 0.8, 0.2, 1.0}, '[SA]')
                                    end
                                    if area ~= '' then
                                        imgui.SameLine()
                                        imgui.TextDisabled(string.format('/sea %s linkshell%s', area, state.attendUseLS2 and '2' or ''))
                                    end
                                end
                            end
                        end
                    end
                end
                imgui.EndChild()

                imgui.EndTabItem()
            end

            -- =================================================================
            -- TAB 2: Preferences & Settings
            -- =================================================================
            if imgui.BeginTabItem('Preferences') then
                imgui.BeginChild('attend_pref_child', { 0, -35 }, true)

                imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Interface Settings')
                imgui.Separator()
                
                local autoPopoutPtr = { state.autoPopout }
                if imgui.Checkbox('Enable Quick Attendance Window (Auto-Popout)', autoPopoutPtr) then
                    if callbacks.on_auto_popout_change then
                        callbacks.on_auto_popout_change(autoPopoutPtr[1])
                    end
                end
                imgui.TextDisabled('Automatically opens a small event listing popup when entering an event zone.')
                
                imgui.Spacing()
                local defaultLS2Ptr = { state.defaultLS2 }
                if imgui.Checkbox('Default to LS2', defaultLS2Ptr) then
                    if callbacks.on_default_ls2_change then
                        callbacks.on_default_ls2_change(defaultLS2Ptr[1])
                    end
                end
                imgui.TextDisabled('Uses Linkshell 2 by default for searches, check-in announcements, and logs.')
                
                imgui.Spacing()
                imgui.Separator()
                imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Self-Attendance (SA) Default Events')
                imgui.TextDisabled('Checked events will automatically launch in Self-Attendance check-in mode.')
                imgui.Separator()

                if imgui.Button('Select All Events') then
                    for _, cat in ipairs(resources.attendCategoriesOrder) do
                        for _, ev in ipairs(resources.attendCategories[cat] or {}) do
                            state.selfAttestEvents[ev] = true
                        end
                    end
                    if callbacks.on_self_attest_change then callbacks.on_self_attest_change() end
                end
                imgui.SameLine()
                if imgui.Button('Clear All Events') then
                    state.selfAttestEvents = {}
                    if callbacks.on_self_attest_change then callbacks.on_self_attest_change() end
                end

                imgui.Spacing()

                for _, cat in ipairs(resources.attendCategoriesOrder) do
                    local events = resources.attendCategories[cat] or {}
                    if #events > 0 then
                        if imgui.TreeNode(cat .. '##sa_pref_cat_' .. cat) then
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

                imgui.EndChild()
                imgui.EndTabItem()
            end

            -- =================================================================
            -- TAB 3: Tools & Custom Launch
            -- =================================================================
            if imgui.BeginTabItem('Tools & Custom') then
                imgui.BeginChild('attend_tools_child', { 0, -35 }, true)

                imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Global & Quick Searches')
                imgui.Separator()
                if imgui.Button('Scan All Linkshell Members (/sea all linkshell)') then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att all')
                end
                imgui.Spacing()
                if imgui.Button('Take Attendance Here (/att here)') then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att here')
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Custom Event Launch')
                imgui.TextDisabled('Launch attendance for an unlisted event or custom search area.')
                imgui.Separator()

                imgui.Text('Event Name:')
                imgui.SameLine()
                imgui.PushItemWidth(220)
                imgui.InputText('##custom_ev_name', customEventName, 64)
                imgui.PopItemWidth()

                imgui.Text('Search Area:')
                imgui.SameLine()
                imgui.PushItemWidth(220)
                imgui.InputText('##custom_sea_area', customSearchArea, 64)
                imgui.PopItemWidth()

                local cLS2Ptr = { customUseLS2 }
                if imgui.Checkbox('Use LS2##custom_ls2', cLS2Ptr) then customUseLS2 = cLS2Ptr[1] end
                imgui.SameLine()
                local cSAPtr = { customSelfAttest }
                if imgui.Checkbox('Self-Attendance##custom_sa', cSAPtr) then customSelfAttest = cSAPtr[1] end

                if imgui.Button('Launch Custom Event##launch_custom_btn') then
                    local ev = helpers.trim(customEventName[1] or '')
                    local area = helpers.trim(customSearchArea[1] or '')
                    if ev ~= '' then
                        if area ~= '' then
                            resources.attSearchArea[ev] = area
                        end
                        state.attendUseLS2 = customUseLS2
                        state.attendSelfAttest = customSelfAttest
                        if callbacks.on_launch_event then
                            callbacks.on_launch_event(ev)
                        end
                    end
                end

                imgui.EndChild()
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end

        imgui.Separator()
        if imgui.Button('Close##attend_main_close') then openPtr[1] = false end
    end
    imgui.End()
    return openPtr[1]
end

function ui.draw_preferences_window(is_open, state, callbacks)
    -- Maintained for backwards compatibility: opens the main menu
    return ui.draw_launcher(is_open, state, callbacks)
end

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

return ui
