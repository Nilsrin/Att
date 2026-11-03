-- ui.lua
-- Modern, sleek, HXBars-inspired Attendance Manager UI
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

local ImGuiTabItemFlags_SetSelected = ImGuiTabItemFlags_SetSelected or 1
local ImGuiWindowFlags_NoCollapse   = ImGuiWindowFlags_NoCollapse or 32

--------------------------------------------------------------------------------
-- Theme Palette & Styling Tokens (HXBars Design System)
--------------------------------------------------------------------------------
local colors = {
    gold            = { 0.95, 0.78, 0.35, 1.00 },
    goldHover       = { 1.00, 0.85, 0.45, 1.00 },
    goldDim         = { 0.65, 0.52, 0.22, 1.00 },
    cyan            = { 0.38, 0.75, 0.98, 1.00 },
    cyanDim         = { 0.22, 0.48, 0.65, 1.00 },
    greenActive     = { 0.28, 0.85, 0.45, 1.00 },
    greenDim        = { 0.18, 0.55, 0.30, 1.00 },
    amber           = { 1.00, 0.75, 0.35, 1.00 },
    danger          = { 0.95, 0.45, 0.45, 1.00 },
    header          = { 1.00, 0.75, 0.55, 1.00 },
    subHeader       = { 0.60, 0.82, 1.00, 1.00 },
    textNormal      = { 0.90, 0.92, 0.96, 1.00 },
    textMuted       = { 0.58, 0.62, 0.70, 1.00 },
    textDim         = { 0.42, 0.46, 0.54, 1.00 },

    -- Backgrounds & Borders
    bgDark          = { 0.08, 0.09, 0.11, 0.96 },
    bgCard          = { 0.12, 0.14, 0.17, 0.90 },
    bgCardHover     = { 0.15, 0.17, 0.22, 0.95 },
    bgBanner        = { 0.10, 0.14, 0.20, 0.92 },
    borderDark      = { 0.22, 0.25, 0.32, 0.80 },
    borderHighlight = { 0.35, 0.42, 0.55, 0.90 },
    titleBg         = { 0.10, 0.12, 0.16, 0.95 },
    titleBgActive   = { 0.16, 0.20, 0.28, 0.98 },
}

-- Unified Button Themes (4 States: Idle, Hover, Active, Text, Border)
local buttonThemes = {
    primary = {
        idle   = { 0.18, 0.24, 0.35, 0.90 },
        hover  = { 0.28, 0.38, 0.54, 1.00 },
        active = { 0.34, 0.46, 0.64, 1.00 },
        text   = { 0.90, 0.94, 1.00, 1.00 },
        border = { 0.28, 0.38, 0.54, 0.85 },
    },
    success = {
        idle   = { 0.16, 0.28, 0.22, 0.90 },
        hover  = { 0.24, 0.42, 0.32, 1.00 },
        active = { 0.30, 0.52, 0.40, 1.00 },
        text   = { 0.88, 0.96, 0.90, 1.00 },
        border = { 0.26, 0.50, 0.36, 0.85 },
    },
    danger = {
        idle   = { 0.28, 0.16, 0.18, 0.90 },
        hover  = { 0.44, 0.22, 0.24, 1.00 },
        active = { 0.56, 0.26, 0.28, 1.00 },
        text   = { 0.95, 0.75, 0.75, 1.00 },
        border = { 0.56, 0.26, 0.28, 0.85 },
    },
    accent = {
        idle   = { 0.25, 0.21, 0.12, 0.92 },
        hover  = { 0.38, 0.32, 0.18, 1.00 },
        active = { 0.48, 0.40, 0.22, 1.00 },
        text   = { 1.00, 0.90, 0.55, 1.00 },
        border = { 0.65, 0.52, 0.22, 0.85 },
    },
    info = {
        idle   = { 0.12, 0.22, 0.28, 0.90 },
        hover  = { 0.18, 0.34, 0.44, 1.00 },
        active = { 0.24, 0.44, 0.56, 1.00 },
        text   = { 0.75, 0.92, 1.00, 1.00 },
        border = { 0.28, 0.50, 0.66, 0.85 },
    },
    muted = {
        idle   = { 0.14, 0.16, 0.20, 0.80 },
        hover  = { 0.22, 0.26, 0.34, 0.95 },
        active = { 0.28, 0.32, 0.42, 1.00 },
        text   = { 0.78, 0.82, 0.90, 1.00 },
        border = { 0.24, 0.28, 0.36, 0.80 },
    },
}

-- Themes for the floating Quick Attendance Popout
local popoutThemes = {
    ['Slate'] = {
        name = 'Slate (HXBars Dark)',
        idle = { 0.14, 0.18, 0.26, 0.92 },
        hover = { 0.24, 0.34, 0.48, 1.00 },
        active = { 0.32, 0.44, 0.62, 1.00 },
        text = { 0.92, 0.96, 1.00, 1.00 },
        border = { 0.28, 0.40, 0.58, 0.85 },
    },
    ['Gold'] = {
        name = 'Gold / Amber (Elite)',
        idle = { 0.22, 0.17, 0.10, 0.92 },
        hover = { 0.38, 0.28, 0.14, 1.00 },
        active = { 0.48, 0.36, 0.18, 1.00 },
        text = { 1.00, 0.90, 0.55, 1.00 },
        border = { 0.85, 0.68, 0.28, 0.90 },
    },
    ['Cyan'] = {
        name = 'Cyan / Crystal',
        idle = { 0.10, 0.20, 0.26, 0.92 },
        hover = { 0.16, 0.34, 0.46, 1.00 },
        active = { 0.22, 0.44, 0.58, 1.00 },
        text = { 0.65, 0.92, 1.00, 1.00 },
        border = { 0.32, 0.72, 0.92, 0.85 },
    },
    ['Crimson'] = {
        name = 'Crimson / Fire',
        idle = { 0.24, 0.12, 0.14, 0.92 },
        hover = { 0.40, 0.18, 0.22, 1.00 },
        active = { 0.52, 0.24, 0.28, 1.00 },
        text = { 1.00, 0.80, 0.80, 1.00 },
        border = { 0.80, 0.32, 0.38, 0.85 },
    },
    ['Emerald'] = {
        name = 'Emerald / Jade',
        idle = { 0.12, 0.22, 0.16, 0.92 },
        hover = { 0.20, 0.36, 0.26, 1.00 },
        active = { 0.26, 0.46, 0.34, 1.00 },
        text = { 0.75, 1.00, 0.82, 1.00 },
        border = { 0.32, 0.80, 0.48, 0.85 },
    },
    ['Midnight'] = {
        name = 'Midnight / Glass',
        idle = { 0.08, 0.09, 0.12, 0.85 },
        hover = { 0.18, 0.20, 0.26, 0.95 },
        active = { 0.26, 0.28, 0.36, 1.00 },
        text = { 0.95, 0.95, 0.95, 1.00 },
        border = { 0.38, 0.40, 0.48, 0.75 },
    },
}

local popoutThemeOrder = { 'Slate', 'Gold', 'Cyan', 'Crimson', 'Emerald', 'Midnight' }

--------------------------------------------------------------------------------
-- Button & Window Helpers
--------------------------------------------------------------------------------
local function ButtonStyled(label, themeType, size, rounding)
    local theme = buttonThemes[themeType] or buttonThemes.primary
    rounding = rounding or 4.0

    imgui.PushStyleColor(ImGuiCol_Button, theme.idle)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, theme.hover)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, theme.active)
    imgui.PushStyleColor(ImGuiCol_Text, theme.text)
    imgui.PushStyleColor(ImGuiCol_Border, theme.border)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, rounding)
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0)

    local btnSize
    if type(size) == 'table' then
        btnSize = { size[1] or 0, size[2] or 0 }
    elseif type(size) == 'number' then
        btnSize = { 0, size }
    end

    local clicked
    if btnSize then
        clicked = imgui.Button(label, btnSize)
    else
        clicked = imgui.Button(label)
    end

    imgui.PopStyleVar(2)
    imgui.PopStyleColor(5)
    return clicked
end

local function SmallButtonStyled(label, themeType, rounding)
    local theme = buttonThemes[themeType] or buttonThemes.primary
    rounding = rounding or 3.0

    imgui.PushStyleColor(ImGuiCol_Button, theme.idle)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, theme.hover)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, theme.active)
    imgui.PushStyleColor(ImGuiCol_Text, theme.text)
    imgui.PushStyleColor(ImGuiCol_Border, theme.border)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, rounding)
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 6.0, 2.0 })

    local clicked = imgui.Button(label)

    imgui.PopStyleVar(3)
    imgui.PopStyleColor(5)
    return clicked
end

local function push_window_style(scale)
    scale = scale or 1.0
    local tabActiveCol = ImGuiCol_TabActive or ImGuiCol_TabSelected or 36

    imgui.PushStyleColor(ImGuiCol_WindowBg, colors.bgDark)
    imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
    imgui.PushStyleColor(ImGuiCol_TitleBg, colors.titleBg)
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, colors.titleBgActive)
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, colors.titleBg)
    imgui.PushStyleColor(ImGuiCol_Separator, colors.borderDark)
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.12, 0.14, 0.18, 0.85 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { 0.18, 0.22, 0.28, 0.95 })
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.22, 0.28, 0.36, 1.00 })
    imgui.PushStyleColor(ImGuiCol_Tab, { 0.12, 0.14, 0.18, 0.75 })
    imgui.PushStyleColor(ImGuiCol_TabHovered, { 0.28, 0.38, 0.54, 1.00 })
    imgui.PushStyleColor(tabActiveCol, { 0.20, 0.28, 0.40, 0.95 })
    imgui.PushStyleColor(ImGuiCol_Header, { 0.16, 0.20, 0.28, 0.80 })
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, { 0.24, 0.32, 0.44, 0.95 })
    imgui.PushStyleColor(ImGuiCol_HeaderActive, { 0.30, 0.40, 0.54, 1.00 })
    imgui.PushStyleColor(ImGuiCol_Text, colors.textNormal)
    imgui.PushStyleColor(ImGuiCol_TextDisabled, colors.textMuted)
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, { 0.08, 0.09, 0.11, 0.60 })
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, { 0.22, 0.26, 0.34, 0.80 })
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, { 0.30, 0.36, 0.46, 0.95 })
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, { 0.38, 0.46, 0.58, 1.00 })

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, math.floor(6.0 * scale))
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, math.floor(4.0 * scale))
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, math.floor(5.0 * scale))
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { math.floor(8 * scale), math.floor(6 * scale) })
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { math.floor(8 * scale), math.floor(4 * scale) })
end

local function pop_window_style()
    imgui.PopStyleVar(8)
    imgui.PopStyleColor(21)
end

--------------------------------------------------------------------------------
-- Font Scaling Helpers
--------------------------------------------------------------------------------
local baseFontSize = nil

local function get_base_font_size()
    if baseFontSize ~= nil then
        return baseFontSize
    end
    local ok, style = pcall(imgui.GetStyle)
    if ok and style ~= nil and type(style.FontSizeBase) == 'number' and style.FontSizeBase > 0 then
        baseFontSize = style.FontSizeBase
        return baseFontSize
    end
    local ok2, sz = pcall(imgui.GetFontSize)
    if ok2 and type(sz) == 'number' and sz > 4 and sz < 64 then
        baseFontSize = sz
        return baseFontSize
    end
    baseFontSize = 14.0
    return baseFontSize
end

local function push_font_scale(scale)
    scale = scale or 1.0
    local pushed = false
    local base = get_base_font_size()
    local targetSize = base * scale

    if type(imgui.PushFont) == 'function' then
        local font = (type(imgui.GetFont) == 'function' and imgui.GetFont()) or nil
        if font ~= nil then
            local ok = pcall(imgui.PushFont, font, targetSize)
            if ok then pushed = true end
        end
        if not pushed then
            local ok = pcall(imgui.PushFont, nil, targetSize)
            if ok then pushed = true end
        end
    end

    if type(imgui.SetWindowFontScale) == 'function' then
        pcall(imgui.SetWindowFontScale, scale)
    end

    return pushed
end

local function pop_font_scale(pushed)
    if pushed and type(imgui.PopFont) == 'function' then
        pcall(imgui.PopFont)
    end
    if type(imgui.SetWindowFontScale) == 'function' then
        pcall(imgui.SetWindowFontScale, 1.0)
    end
end

-- Persistent filter and input state
local manualAddBuffer = { '' }
local manualAddMessage = nil
local manualAddMessageTime = 0

--------------------------------------------------------------------------------
-- 1. ATTENDANCE RESULTS WINDOW
--------------------------------------------------------------------------------
function ui.draw_attendance_window(is_open, att_module, state, callbacks)
    if not is_open then return false end

    local scale = state.uiScale or 1.0
    imgui.SetNextWindowSize({ math.floor(1050 * scale), math.floor(620 * scale) }, ImGuiCond_FirstUseEver)

    push_window_style(scale)
    local openPtr = { is_open }
    local isOpen = imgui.Begin('Attendance Results###AttendanceResults', openPtr, ImGuiWindowFlags_NoCollapse)
    if isOpen then
        local pushedFont = push_font_scale(scale)

        -- Top Header Bar (HXBars Style)
        imgui.BeginGroup()
        imgui.TextColored(colors.gold, 'ATT')
        imgui.SameLine(0, math.floor(5 * scale))
        imgui.TextDisabled('v5.1.0')
        imgui.SameLine(0, math.floor(12 * scale))
        imgui.TextColored(colors.subHeader, 'Attendance Results')

        if state.pendingEventName and state.pendingEventName ~= '' then
            imgui.SameLine(0, math.floor(10 * scale))
            imgui.TextDisabled('•')
            imgui.SameLine(0, math.floor(10 * scale))
            imgui.TextColored(colors.textNormal, state.pendingEventName)
        end

        if state.g_SAMode and state.selfAttendanceStart then
            local elapsed = os.time() - state.selfAttendanceStart
            local remaining = math.max(0, (state.saTimerDuration or 300) - elapsed)
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60

            imgui.SameLine(0, math.floor(14 * scale))
            imgui.TextColored(colors.gold, '● SA Active')
            imgui.SameLine(0, math.floor(4 * scale))
            imgui.TextColored(colors.amber, string.format('(%02d:%02d)', mins, secs))
        end
        imgui.EndGroup()

        -- Self-Attendance Controls Bar (When active)
        if state.g_SAMode then
            imgui.Spacing()
            imgui.PushStyleColor(ImGuiCol_ChildBg, { 0.14, 0.12, 0.08, 0.70 })
            imgui.PushStyleColor(ImGuiCol_Border, colors.goldDim)
            imgui.BeginChild('sa_toolbar_card', { 0, math.floor(38 * scale) }, true)

            imgui.TextColored(colors.gold, 'Self-Attendance:')
            imgui.SameLine(0, math.floor(10 * scale))
            if ButtonStyled('Show Pending##sa_show', 'muted', { 0, math.floor(22 * scale) }) then
                if callbacks.on_show_pending then callbacks.on_show_pending() end
            end
            imgui.SameLine(0, math.floor(6 * scale))
            if ButtonStyled('Refresh Data##sa_ref', 'primary', { 0, math.floor(22 * scale) }) then
                if callbacks.on_refresh_sa then callbacks.on_refresh_sa() end
            end
            imgui.SameLine(0, math.floor(6 * scale))
            if ButtonStyled('✓ Check In All Pending##sa_all', 'success', { 0, math.floor(22 * scale) }) then
                att_module.confirm_all_pending()
            end

            imgui.EndChild()
            imgui.PopStyleColor(2)
        end

        -- Active Scanning Banner (Immediate Feedback Indicator)
        local isScanning = (state.isScanningAll == true) or (state.isScanningLetter == true) or (state.pendingGather ~= nil) or (state.isRefreshing == true)
        if isScanning then
            imgui.Spacing()
            imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgBanner)
            imgui.PushStyleColor(ImGuiCol_Border, colors.cyan)
            imgui.BeginChild('scan_active_card', { 0, math.floor(40 * scale) }, true)

            if state.isRefreshing then
                local target = state.pendingEventName or 'Current Event'
                imgui.TextColored(colors.cyan, '↻ Refresh in Progress:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.TextColored(colors.textNormal, string.format('Closing search, re-searching members for [ %s ]... Updating attendance', target))
            elseif state.isScanningAll then
                imgui.TextColored(colors.gold, '⚡ Scanning All Letters In Progress:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.TextColored(colors.textNormal, string.format('Current target: [ %s ] (Cycling to A)', state.scanNextLetter or 'A'))
                imgui.SameLine(0, math.floor(14 * scale))
                if ButtonStyled('■ Stop Scan##btn_stop_scan_banner', 'danger', { 0, math.floor(22 * scale) }) then
                    if callbacks.on_stop_scan then callbacks.on_stop_scan() end
                end
            elseif state.isScanningLetter then
                imgui.TextColored(colors.cyan, '⚡ Scanning Letter In Progress:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.TextColored(colors.textNormal, string.format('Searching members for [ %s ]... Gathering results', state.scanNextLetter or 'A'))
            elseif state.pendingGather then
                local target = state.pendingGather.eventName or state.pendingEventName or 'Linkshell'
                imgui.TextColored(colors.cyan, '⚡ Active Scan in Progress:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.TextColored(colors.textNormal, string.format('Searching members for [ %s ]... Results will populate momentarily', target))
            end

            imgui.EndChild()
            imgui.PopStyleColor(2)
        end

        -- Action Toolbar Card (Row 1: Scanners & Refresh | Row 2: Mode & Add Player)
        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
        imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { math.floor(8 * scale), math.floor(6 * scale) })
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { math.floor(6 * scale), math.floor(5 * scale) })
        imgui.BeginChild('att_controls_card', { 0, math.floor(68 * scale) }, true, ImGuiWindowFlags_NoScrollbar or 8)

        -- ROW 1: Scan All, Scan (), Refresh
        if not state.scanNextLetter then
            local last = att_module.data[#att_module.data]
            local cleanLast = last and helpers.strip_prefix(last.name)
            local ch = (cleanLast and cleanLast ~= '') and cleanLast:match('^(%a)') or 'A'
            state.scanNextLetter = ch:upper()
        end

        if state.isScanningAll then
            if ButtonStyled('■ Stop Scan##btn_stop_scan', 'danger', { 0, math.floor(24 * scale) }) then
                if callbacks.on_stop_scan then callbacks.on_stop_scan() end
            end
        else
            if ButtonStyled('Scan all##btn_scan_all', 'accent', { 0, math.floor(24 * scale) }) then
                if not state.isScanningLetter and not state.isScanningAll and not state.isRefreshing then
                    if callbacks.on_scan_all then callbacks.on_scan_all() end
                end
            end
        end

        imgui.SameLine(0, math.floor(6 * scale))
        local scanLetterLabel = string.format('Scan (%s)##btn_scan_letter', state.scanNextLetter or 'A')
        if ButtonStyled(scanLetterLabel, 'primary', { 0, math.floor(24 * scale) }) then
            if not state.isScanningLetter and not state.isScanningAll and not state.isRefreshing then
                if callbacks.on_scan_letter then callbacks.on_scan_letter(state.scanNextLetter) end
                state.scanNextLetter = helpers.get_next_letter(state.scanNextLetter)
            end
        end

        imgui.SameLine(0, math.floor(6 * scale))
        local refreshLabel = state.isRefreshing and 'Refreshing...##btn_refresh' or 'Refresh##btn_refresh'
        local refreshTheme = state.isRefreshing and 'accent' or 'primary'
        if ButtonStyled(refreshLabel, refreshTheme, { 0, math.floor(24 * scale) }) then
            if not state.isScanningLetter and not state.isScanningAll and not state.isRefreshing then
                if callbacks.on_refresh then callbacks.on_refresh() end
            end
        end

        imgui.SameLine(0, math.floor(6 * scale))
        if ButtonStyled('Party Only##btn_party_only', 'primary', { 0, math.floor(24 * scale) }) then
            if callbacks.on_party_only then
                local remaining, removed = callbacks.on_party_only()
                if remaining and removed then
                    manualAddMessage = string.format('Trimmed to %d in party (%d removed)', remaining, removed)
                    manualAddMessageTime = os.clock() + 3
                end
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Trim attendance results to current party/alliance members only')
        end

        -- ROW 2: Mode Selector & Add Player
        imgui.TextColored(colors.subHeader, 'Mode:')
        imgui.SameLine(0, math.floor(6 * scale))
        local isHNM = (state.selectedMode == 'HNM')
        if ButtonStyled('HNM##mode_hnm', isHNM and 'accent' or 'muted', { 0, math.floor(22 * scale) }) then
            state.selectedMode = 'HNM'
        end
        imgui.SameLine(0, math.floor(4 * scale))
        local isEvent = (state.selectedMode == 'Event')
        if ButtonStyled('Event##mode_event', isEvent and 'accent' or 'muted', { 0, math.floor(22 * scale) }) then
            state.selectedMode = 'Event'
        end

        imgui.SameLine(0, math.floor(10 * scale))
        imgui.TextDisabled('|')
        imgui.SameLine(0, math.floor(10 * scale))

        -- Add Player Input Field
        imgui.TextColored(colors.subHeader, 'Add Player:')
        imgui.SameLine(0, math.floor(6 * scale))
        imgui.PushItemWidth(math.floor(130 * scale))
        local enterFlag = ImGuiInputTextFlags_EnterReturnsTrue or 32
        local enterPressed = imgui.InputText('##manual_add_name', manualAddBuffer, 32, enterFlag)
        imgui.PopItemWidth()
        imgui.SameLine(0, math.floor(6 * scale))
        local addClicked = ButtonStyled('+ Add##btn_add_player', 'primary', { 0, math.floor(22 * scale) })

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
            imgui.SameLine(0, math.floor(8 * scale))
            imgui.TextColored(colors.cyan, string.format('(%s)', manualAddMessage))
        end

        imgui.EndChild()
        imgui.PopStyleVar(2)
        imgui.PopStyleColor(2)

        -- Summary Counters
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

        imgui.Spacing()
        imgui.BeginGroup()
        imgui.TextColored(colors.gold, 'Attendance:')
        imgui.SameLine(0, math.floor(10 * scale))
        imgui.Text(string.format('Total: %d', #att_module.data))
        imgui.SameLine(0, math.floor(8 * scale))
        imgui.TextDisabled('•')
        imgui.SameLine(0, math.floor(8 * scale))
        imgui.TextColored(colors.greenActive, string.format('Confirmed: %d', present_count))
        imgui.SameLine(0, math.floor(8 * scale))
        imgui.TextDisabled('•')
        imgui.SameLine(0, math.floor(8 * scale))
        imgui.TextColored(colors.amber, string.format('Pending: %d', pending_count))

        if unlisted_count > 0 then
            imgui.SameLine(0, math.floor(8 * scale))
            imgui.TextDisabled('•')
            imgui.SameLine(0, math.floor(8 * scale))
            imgui.TextColored(colors.cyan, string.format('Unlisted: %d', unlisted_count))
        end
        imgui.EndGroup()
        imgui.Spacing()

        -- Roster Display Child Card
        imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
        imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
        imgui.BeginChild('att_list', { 0, math.floor(-48 * scale) }, true)

        if #att_module.data == 0 then
            if isScanning then
                imgui.Spacing()
                imgui.Spacing()
                imgui.TextColored(colors.gold, '    📡 Active Scan in Progress...')
                imgui.Spacing()
                imgui.TextDisabled('       Attendance window has opened. Scanned data will populate here automatically once the search completes.')
            else
                imgui.Spacing()
                imgui.Spacing()
                imgui.TextDisabled('    No attendance data recorded yet. Use the scan or add player buttons above.')
            end
        else
            -- 1. Confirmed / Present Section
            if present_count > 0 or (pending_count == 0 and unlisted_count == 0) then
                imgui.TextColored(colors.greenActive, string.format('● Confirmed Attendees (%d)', present_count))
                imgui.Separator()
                imgui.Spacing()
                local i = 1
                while i <= #att_module.data do
                    local r = att_module.data[i]
                    if not helpers.is_unconfirmed(r.name) then
                        if SmallButtonStyled('×##present_' .. i, 'danger') then
                            table.remove(att_module.data, i)
                        else
                            imgui.SameLine(0, math.floor(8 * scale))
                            imgui.TextColored(colors.greenActive, r.name)
                            imgui.SameLine(0, math.floor(8 * scale))
                            imgui.TextColored(colors.subHeader, string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                            if r.zone and r.zone ~= '' then
                                imgui.SameLine(0, math.floor(8 * scale))
                                imgui.TextDisabled(string.format('[%s]', r.zone))
                            end
                            if r.time and r.time ~= '' then
                                imgui.SameLine(0, math.floor(8 * scale))
                                imgui.TextDisabled(string.format('@ %s', r.time))
                            end
                            i = i + 1
                        end
                    else
                        i = i + 1
                    end
                end
                imgui.Spacing()
                imgui.Spacing()
            end

            -- 2. Pending Section (Initial zone roster eligible players who haven't checked in)
            if pending_count > 0 then
                imgui.TextColored(colors.amber, string.format('● Pending Check-Ins (%d)', pending_count))
                imgui.SameLine(0, math.floor(12 * scale))
                if SmallButtonStyled('✓ Check In All##pending_all_sec', 'success') then
                    att_module.confirm_all_pending()
                end
                imgui.Separator()
                imgui.Spacing()

                local i = 1
                while i <= #att_module.data do
                    local r = att_module.data[i]
                    if helpers.is_pending(r.name) then
                        if SmallButtonStyled('✓ Check In##pending_' .. i, 'success') then
                            att_module.confirm_entry(i)
                        else
                            imgui.SameLine(0, math.floor(4 * scale))
                            if SmallButtonStyled('×##pending_rm_' .. i, 'danger') then
                                table.remove(att_module.data, i)
                            else
                                imgui.SameLine(0, math.floor(8 * scale))
                                local displayName = helpers.strip_prefix(r.name)
                                imgui.TextColored(colors.amber, displayName)
                                imgui.SameLine(0, math.floor(8 * scale))
                                imgui.TextColored(colors.subHeader, string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                                if r.zone and r.zone ~= '' then
                                    imgui.SameLine(0, math.floor(8 * scale))
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
                imgui.Spacing()
            end

            -- 3. Unlisted Requests / Needs Approval Section (People who typed !here or !addme)
            if unlisted_count > 0 then
                imgui.TextColored(colors.cyan, string.format('● Unlisted Check-In Requests (%d)', unlisted_count))
                imgui.SameLine(0, math.floor(12 * scale))
                if SmallButtonStyled('✓ Approve All##unlisted_all_sec', 'info') then
                    att_module.approve_all_unlisted()
                end
                imgui.Separator()
                imgui.Spacing()

                local i = 1
                while i <= #att_module.data do
                    local r = att_module.data[i]
                    if helpers.is_unlisted(r.name) then
                        if SmallButtonStyled('✓ Approve##unlisted_' .. i, 'info') then
                            att_module.confirm_entry(i)
                        else
                            imgui.SameLine(0, math.floor(4 * scale))
                            if SmallButtonStyled('×##unlisted_rm_' .. i, 'danger') then
                                table.remove(att_module.data, i)
                            else
                                imgui.SameLine(0, math.floor(8 * scale))
                                local displayName = helpers.strip_prefix(r.name)
                                imgui.TextColored(colors.cyan, displayName)
                                imgui.SameLine(0, math.floor(8 * scale))
                                imgui.TextColored(colors.subHeader, string.format('(%s/%s)', r.jobsMain or '?', r.jobsSub or '?'))
                                if r.zone and r.zone ~= '' then
                                    imgui.SameLine(0, math.floor(8 * scale))
                                    imgui.TextDisabled(string.format('[%s]', r.zone))
                                end
                                if r.time and r.time ~= '' then
                                    imgui.SameLine(0, math.floor(8 * scale))
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
        end

        imgui.EndChild()
        imgui.PopStyleColor(2)

        -- Bottom Actions Toolbar
        imgui.Spacing()
        if ButtonStyled('💾 Write & Close##att_write_close', 'success', { 0, math.floor(28 * scale) }) then
            if callbacks.on_write then callbacks.on_write(true) end
            openPtr[1] = false
        end
        imgui.SameLine(0, math.floor(8 * scale))
        if ButtonStyled('💾 Write##att_write', 'primary', { 0, math.floor(28 * scale) }) then
            if callbacks.on_write then callbacks.on_write(false) end
        end
        imgui.SameLine(0, math.floor(8 * scale))
        if ButtonStyled('Cancel##att_cancel', 'muted', { 0, math.floor(28 * scale) }) then
            openPtr[1] = false
        end

        pop_font_scale(pushedFont)
    end
    imgui.End()
    pop_window_style()

    return openPtr[1]
end

--------------------------------------------------------------------------------
-- 2. MAIN MENU / LAUNCHER WINDOW
--------------------------------------------------------------------------------
local eventSearchFilter = { '' }
local customEventName   = { '' }
local customSearchArea  = { '' }
local customUseLS2      = false
local customSelfAttest  = false

function ui.draw_launcher(is_open, state, callbacks)
    if not is_open then return false end

    local scale = state.uiScale or 1.0
    imgui.SetNextWindowSize({ math.floor(680 * scale), math.floor(620 * scale) }, ImGuiCond_FirstUseEver)

    push_window_style(scale)
    local openPtr = { is_open }
    local isOpen = imgui.Begin('ATT - Main Menu###att_main_menu', openPtr, ImGuiWindowFlags_NoCollapse)
    if isOpen then
        local pushedFont = push_font_scale(scale)

        -- Top Header Bar
        imgui.TextColored(colors.gold, 'ATT')
        imgui.SameLine(0, math.floor(5 * scale))
        imgui.TextDisabled('v5.1.0')
        imgui.SameLine(0, math.floor(12 * scale))
        imgui.TextColored(colors.subHeader, 'Event Launcher & Configuration')
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.BeginTabBar('##att_main_tab_bar') then

            -- =================================================================
            -- TAB 1: Events Launcher
            -- =================================================================
            local eventsFlags = 0
            if state.requestedTab == 'Events' then
                eventsFlags = ImGuiTabItemFlags_SetSelected
                state.requestedTab = nil
            end
            if imgui.BeginTabItem('Events', nil, eventsFlags) then
                imgui.Spacing()

                -- Quick Settings Toolbar Card
                imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
                imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
                imgui.BeginChild('attend_quick_bar', { 0, math.floor(46 * scale) }, true)

                local ls2Ptr = { state.attendUseLS2 }
                if imgui.Checkbox('Use LS2##ls2_chk', ls2Ptr) then state.attendUseLS2 = ls2Ptr[1] end
                imgui.SameLine(0, math.floor(12 * scale))
                local saPtr = { state.attendSelfAttest }
                if imgui.Checkbox('Self Attest (SA)##sa_chk', saPtr) then state.attendSelfAttest = saPtr[1] end
                imgui.SameLine(0, math.floor(12 * scale))

                local delayPtr = { state.attendDelaySec }
                imgui.PushItemWidth(math.floor(45 * scale))
                if imgui.InputInt('##delay', delayPtr, 0, 0) then
                    state.attendDelaySec = helpers.clamp_0_99(delayPtr[1])
                end
                imgui.PopItemWidth()
                imgui.SameLine(0, math.floor(6 * scale))
                imgui.Text('Delay(s)')
                imgui.SameLine(0, math.floor(12 * scale))

                if ButtonStyled('Update Zone##upd_zone_btn', 'primary', { 0, math.floor(24 * scale) }) then
                    if callbacks.on_update_zone then callbacks.on_update_zone() end
                end
                imgui.SameLine(0, math.floor(6 * scale))
                if ButtonStyled('⚡ Here (/att here)##att_here_btn', 'accent', { 0, math.floor(24 * scale) }) then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att here')
                end

                imgui.EndChild()
                imgui.PopStyleColor(2)

                -- Current Zone Suggestions Card
                imgui.Spacing()
                imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
                imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
                imgui.BeginChild('attend_zone_card', { 0, math.floor(58 * scale) }, true)

                local evs, zname = state.suggestions.evs, state.suggestions.zone
                imgui.TextColored(colors.cyan, string.format('Current Zone: %s', zname or 'Unknown Zone'))
                if evs and #evs > 0 then
                    for idx, ev in ipairs(evs) do
                        if idx > 1 then imgui.SameLine(0, math.floor(6 * scale)) end
                        imgui.PushID(idx)
                        if ButtonStyled(string.format('%s##attend_suggest_%d', ev, idx), 'primary', { 0, math.floor(24 * scale) }) then
                            if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                        end
                        imgui.PopID()
                    end
                else
                    imgui.TextDisabled('No event presets configured for this zone.')
                end

                imgui.EndChild()
                imgui.PopStyleColor(2)

                -- Search / Filter bar for events
                imgui.Spacing()
                imgui.TextColored(colors.subHeader, 'Filter Events:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.PushItemWidth(math.floor(220 * scale))
                imgui.InputText('##event_search_filter', eventSearchFilter, 32)
                imgui.PopItemWidth()
                if eventSearchFilter[1] and eventSearchFilter[1] ~= '' then
                    imgui.SameLine(0, math.floor(6 * scale))
                    if ButtonStyled('Clear##clear_ev_search', 'muted', { 0, math.floor(22 * scale) }) then
                        eventSearchFilter[1] = ''
                    end
                end

                local filterText = helpers.trim(eventSearchFilter[1] or ''):lower()

                -- Categorized Events Child Card
                imgui.Spacing()
                imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
                imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
                imgui.BeginChild('attend_events_list', { 0, math.floor(-40 * scale) }, true)

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
                                for ev_idx, ev in ipairs(matchingEvents) do
                                    imgui.PushID(ev_idx)
                                    local area = resources.attSearchArea[ev] or (resources.attCreditNames[ev] and resources.attCreditNames[ev][1]) or ''
                                    local isSA = state.selfAttestEvents[ev] == true

                                    if ButtonStyled(string.format('%s##btn_%d', ev, ev_idx), 'primary', { 0, math.floor(24 * scale) }) then
                                        if callbacks.on_launch_event then callbacks.on_launch_event(ev) end
                                    end
                                    if isSA then
                                        imgui.SameLine(0, math.floor(6 * scale))
                                        imgui.TextColored(colors.gold, '[SA]')
                                    end
                                    if area ~= '' then
                                        imgui.SameLine(0, math.floor(6 * scale))
                                        imgui.TextDisabled(string.format('/sea %s linkshell%s', area, state.attendUseLS2 and '2' or ''))
                                    end
                                    imgui.PopID()
                                end
                                imgui.Spacing()
                            end
                        end
                    end
                end
                imgui.EndChild()
                imgui.PopStyleColor(2)

                imgui.EndTabItem()
            end

            -- =================================================================
            -- TAB 2: Preferences & Settings
            -- =================================================================
            local prefFlags = 0
            if state.requestedTab == 'Preferences' then
                prefFlags = ImGuiTabItemFlags_SetSelected
                state.requestedTab = nil
            end
            if imgui.BeginTabItem('Preferences', nil, prefFlags) then
                imgui.Spacing()
                imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
                imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
                imgui.BeginChild('attend_pref_child', { 0, math.floor(-40 * scale) }, true)

                -- Interface & Scaling Card
                imgui.TextColored(colors.gold, 'Interface & Scaling')
                imgui.Separator()
                imgui.Spacing()

                local currentScale = state.uiScale or 1.0
                local scaleSliderVal = { currentScale }

                imgui.Text('UI Scaling Factor:')
                imgui.SetNextItemWidth(math.floor(200 * scale))
                if imgui.SliderFloat('##ui_scale_slider', scaleSliderVal, 0.5, 3.0, '%.2fx') then
                    local newScale = math.floor(scaleSliderVal[1] * 100 + 0.5) / 100
                    state.uiScale = newScale
                    if callbacks.on_ui_scale_change then
                        callbacks.on_ui_scale_change(newScale)
                    end
                end

                imgui.SameLine(0, math.floor(8 * scale))
                local scalePresets = {
                    { label = '75% (0.75x)', val = 0.75 },
                    { label = '85% (0.85x)', val = 0.85 },
                    { label = '100% (1.00x - Default)', val = 1.00 },
                    { label = '115% (1.15x)', val = 1.15 },
                    { label = '125% (1.25x)', val = 1.25 },
                    { label = '135% (1.35x)', val = 1.35 },
                    { label = '150% (1.50x)', val = 1.50 },
                    { label = '175% (1.75x)', val = 1.75 },
                    { label = '200% (2.00x - 4K)', val = 2.00 },
                    { label = '225% (2.25x)', val = 2.25 },
                    { label = '250% (2.50x)', val = 2.50 },
                    { label = '300% (3.00x)', val = 3.00 },
                }

                local currentPresetLabel = string.format('Preset (%.2fx)', currentScale)
                for _, preset in ipairs(scalePresets) do
                    if math.abs(preset.val - currentScale) < 0.01 then
                        currentPresetLabel = preset.label
                        break
                    end
                end

                imgui.SetNextItemWidth(math.floor(180 * scale))
                if imgui.BeginCombo('##ui_scale_preset_combo', currentPresetLabel) then
                    for _, preset in ipairs(scalePresets) do
                        local isSelected = (math.abs(preset.val - currentScale) < 0.01)
                        if imgui.Selectable(preset.label, isSelected) then
                            state.uiScale = preset.val
                            if callbacks.on_ui_scale_change then
                                callbacks.on_ui_scale_change(preset.val)
                            end
                        end
                        if isSelected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end

                imgui.SameLine(0, math.floor(8 * scale))
                if ButtonStyled('Reset (1.0x)##reset_scale', 'muted', { 0, math.floor(22 * scale) }) then
                    state.uiScale = 1.0
                    if callbacks.on_ui_scale_change then
                        callbacks.on_ui_scale_change(1.0)
                    end
                end

                -- Quick preset buttons row
                imgui.Spacing()
                imgui.TextDisabled('Quick Presets:')
                imgui.SameLine(0, math.floor(8 * scale))
                local quickPresets = { 1.0, 1.25, 1.5, 2.0 }
                for idx, qVal in ipairs(quickPresets) do
                    if idx > 1 then imgui.SameLine(0, math.floor(6 * scale)) end
                    local qText = string.format('%d%%', math.floor(qVal * 100))
                    if qVal == 1.0 then qText = '100% (Default)' end
                    if ButtonStyled(qText .. '##qscale_' .. idx, 'primary', { 0, math.floor(22 * scale) }) then
                        state.uiScale = qVal
                        if callbacks.on_ui_scale_change then
                            callbacks.on_ui_scale_change(qVal)
                        end
                    end
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                -- Quick Attendance Popout Settings
                imgui.TextColored(colors.gold, 'Quick Attendance Popout Settings (Zone Monsters)')
                imgui.TextDisabled('Configure appearance, title bar, transparency, and button themes for the floating zone monster popout.')
                imgui.Spacing()

                local autoPopoutPtr = { state.autoPopout }
                if imgui.Checkbox('Enable Quick Attendance Popout (Auto-Open on Zone)##enable_popout', autoPopoutPtr) then
                    if callbacks.on_auto_popout_change then
                        callbacks.on_auto_popout_change(autoPopoutPtr[1])
                    end
                end

                imgui.Spacing()
                local hideTitlePtr = { state.popoutHideTitle }
                if imgui.Checkbox('Hide Title Bar##popout_hide_title', hideTitlePtr) then
                    state.popoutHideTitle = hideTitlePtr[1]
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end
                imgui.SameLine(0, math.floor(14 * scale))
                local hideBgPtr = { state.popoutHideBg }
                if imgui.Checkbox('Hide Background (Transparent)##popout_hide_bg', hideBgPtr) then
                    state.popoutHideBg = hideBgPtr[1]
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end
                imgui.SameLine(0, math.floor(14 * scale))
                local lockPosPtr = { state.popoutLockPosition }
                if imgui.Checkbox('Lock Position##popout_lock_pos', lockPosPtr) then
                    state.popoutLockPosition = lockPosPtr[1]
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end

                imgui.Spacing()

                -- Button Theme Combo Picker
                imgui.Text('Button Theme:')
                imgui.SameLine(0, math.floor(8 * scale))
                local curThemeKey = state.popoutTheme or 'Slate'
                local curThemeObj = popoutThemes[curThemeKey] or popoutThemes['Slate']
                imgui.SetNextItemWidth(math.floor(200 * scale))
                if imgui.BeginCombo('##popout_theme_combo', curThemeObj.name) then
                    for _, tKey in ipairs(popoutThemeOrder) do
                        local tObj = popoutThemes[tKey]
                        local isSelected = (tKey == curThemeKey)
                        if imgui.Selectable(tObj.name, isSelected) then
                            state.popoutTheme = tKey
                            if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                        end
                        if isSelected then
                            imgui.SetItemDefaultFocus()
                        end
                    end
                    imgui.EndCombo()
                end

                -- Rounding slider
                imgui.Text('Corner Rounding:')
                imgui.SameLine(0, math.floor(8 * scale))
                local roundingPtr = { state.popoutRounding or 5.0 }
                imgui.SetNextItemWidth(math.floor(180 * scale))
                if imgui.SliderFloat('##popout_rounding_slider', roundingPtr, 0.0, 16.0, '%.0f px') then
                    state.popoutRounding = math.floor(roundingPtr[1] + 0.5)
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end

                -- Button Height slider
                imgui.Text('Button Height:')
                imgui.SameLine(0, math.floor(8 * scale))
                local btnHeightPtr = { state.popoutBtnHeight or 42 }
                imgui.SetNextItemWidth(math.floor(180 * scale))
                if imgui.SliderInt('##popout_btn_height_slider', btnHeightPtr, 26, 64, '%d px') then
                    state.popoutBtnHeight = btnHeightPtr[1]
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end

                -- Popout Width slider
                imgui.Text('Popout Width:')
                imgui.SameLine(0, math.floor(8 * scale))
                local widthPtr = { state.popoutWidth or 220 }
                imgui.SetNextItemWidth(math.floor(180 * scale))
                if imgui.SliderInt('##popout_width_slider', widthPtr, 160, 420, '%d px') then
                    state.popoutWidth = widthPtr[1]
                    if callbacks.on_popout_config_change then callbacks.on_popout_config_change() end
                end

                imgui.Spacing()
                if ButtonStyled((state.isPopoutOpen and 'Hide Popout Preview' or 'Show Popout Preview') .. '##toggle_popout_preview', 'primary', { 0, math.floor(24 * scale) }) then
                    state.isPopoutOpen = not state.isPopoutOpen
                    if state.isPopoutOpen and callbacks.on_update_zone then
                        callbacks.on_update_zone()
                    end
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                -- Linkshell Settings
                imgui.TextColored(colors.gold, 'Linkshell Default')
                local defaultLS2Ptr = { state.defaultLS2 }
                if imgui.Checkbox('Default to Linkshell 2 (LS2)##default_ls2', defaultLS2Ptr) then
                    if callbacks.on_default_ls2_change then
                        callbacks.on_default_ls2_change(defaultLS2Ptr[1])
                    end
                end
                imgui.TextDisabled('Uses Linkshell 2 by default for searches, check-in announcements, and logs.')

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                -- Self-Attendance (SA) Default Events
                imgui.TextColored(colors.gold, 'Self-Attendance (SA) Default Events')
                imgui.TextDisabled('Checked events will automatically launch in Self-Attendance check-in mode.')
                imgui.Spacing()

                if ButtonStyled('Select All Events##sa_sel_all', 'primary', { 0, math.floor(24 * scale) }) then
                    for _, cat in ipairs(resources.attendCategoriesOrder) do
                        for _, ev in ipairs(resources.attendCategories[cat] or {}) do
                            state.selfAttestEvents[ev] = true
                        end
                    end
                    if callbacks.on_self_attest_change then callbacks.on_self_attest_change() end
                end
                imgui.SameLine(0, math.floor(8 * scale))
                if ButtonStyled('Clear All Events##sa_clr_all', 'muted', { 0, math.floor(24 * scale) }) then
                    state.selfAttestEvents = {}
                    if callbacks.on_self_attest_change then callbacks.on_self_attest_change() end
                end

                imgui.Spacing()

                for _, cat in ipairs(resources.attendCategoriesOrder) do
                    local events = resources.attendCategories[cat] or {}
                    if #events > 0 then
                        if imgui.TreeNode(cat .. '##sa_pref_cat_' .. cat) then
                            for ev_idx, ev in ipairs(events) do
                                imgui.PushID(ev_idx)
                                local isChecked = { state.selfAttestEvents[ev] == true }
                                if imgui.Checkbox(ev .. '##sa_pref_' .. ev_idx, isChecked) then
                                    state.selfAttestEvents[ev] = isChecked[1] and true or nil
                                    if callbacks.on_self_attest_change then
                                        callbacks.on_self_attest_change()
                                    end
                                end
                                imgui.PopID()
                            end
                            imgui.TreePop()
                        end
                    end
                end

                imgui.EndChild()
                imgui.PopStyleColor(2)
                imgui.EndTabItem()
            end

            -- =================================================================
            -- TAB 3: Tools & Custom Launch
            -- =================================================================
            local toolsFlags = 0
            if state.requestedTab == 'Tools' then
                toolsFlags = ImGuiTabItemFlags_SetSelected
                state.requestedTab = nil
            end
            if imgui.BeginTabItem('Tools & Custom', nil, toolsFlags) then
                imgui.Spacing()
                imgui.PushStyleColor(ImGuiCol_ChildBg, colors.bgCard)
                imgui.PushStyleColor(ImGuiCol_Border, colors.borderDark)
                imgui.BeginChild('attend_tools_child', { 0, math.floor(-40 * scale) }, true)

                imgui.TextColored(colors.gold, 'Global & Quick Searches')
                imgui.Separator()
                imgui.Spacing()
                if ButtonStyled('Scan All Linkshell Members (/sea all linkshell)##sea_all_ls', 'accent', { 0, math.floor(26 * scale) }) then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att all')
                end
                imgui.Spacing()
                if ButtonStyled('Take Attendance Here (/att here)##sea_here_ls', 'primary', { 0, math.floor(26 * scale) }) then
                    AshitaCore:GetChatManager():QueueCommand(1, '/att here')
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.TextColored(colors.gold, 'Custom Event Launch')
                imgui.TextDisabled('Launch attendance for an unlisted event or custom search area.')
                imgui.Spacing()

                imgui.TextColored(colors.subHeader, 'Event Name:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.PushItemWidth(math.floor(240 * scale))
                imgui.InputText('##custom_ev_name', customEventName, 64)
                imgui.PopItemWidth()

                imgui.TextColored(colors.subHeader, 'Search Area:')
                imgui.SameLine(0, math.floor(8 * scale))
                imgui.PushItemWidth(math.floor(240 * scale))
                imgui.InputText('##custom_sea_area', customSearchArea, 64)
                imgui.PopItemWidth()

                local cLS2Ptr = { customUseLS2 }
                if imgui.Checkbox('Use LS2##custom_ls2', cLS2Ptr) then customUseLS2 = cLS2Ptr[1] end
                imgui.SameLine(0, math.floor(14 * scale))
                local cSAPtr = { customSelfAttest }
                if imgui.Checkbox('Self-Attendance (SA)##custom_sa', cSAPtr) then customSelfAttest = cSAPtr[1] end

                imgui.Spacing()
                if ButtonStyled('Launch Custom Event##launch_custom_btn', 'success', { 0, math.floor(26 * scale) }) then
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
                imgui.PopStyleColor(2)
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end

        imgui.Spacing()
        if ButtonStyled('Close##attend_main_close', 'muted', { 0, math.floor(26 * scale) }) then
            openPtr[1] = false
        end

        pop_font_scale(pushedFont)
    end
    imgui.End()
    pop_window_style()

    return openPtr[1]
end

--------------------------------------------------------------------------------
-- 3. PREFERENCES WINDOW (ALIAS)
--------------------------------------------------------------------------------
function ui.draw_preferences_window(is_open, state, callbacks)
    return ui.draw_launcher(is_open, state, callbacks)
end

--------------------------------------------------------------------------------
-- 4. FLOATING QUICK ATTENDANCE POPOUT (ZONE MONSTERS)
--------------------------------------------------------------------------------
function ui.draw_popout(is_open, state, callbacks)
    if not is_open then return false end

    local scale = state.uiScale or 1.0
    local rawEvs = state.suggestions and state.suggestions.evs
    local evs = rawEvs
    if (not evs or #evs == 0) and state.isPopoutOpen then
        evs = { 'Sample Monster (HNM)', 'Sample Event [SA]' }
    end

    local count = (evs and #evs > 0) and #evs or 1
    local themeKey = state.popoutTheme or 'Slate'
    local theme = popoutThemes[themeKey] or popoutThemes['Slate']
    local rounding = (state.popoutRounding ~= nil) and state.popoutRounding or 5.0
    local baseBtnHeight = state.popoutBtnHeight or 42
    local btnHeight = math.floor(baseBtnHeight * scale)
    local popoutWidth = math.floor((state.popoutWidth or 220) * scale)
    local spacing = math.floor(5 * scale)
    local padding = state.popoutHideBg and math.floor(3 * scale) or math.floor(8 * scale)

    -- Dynamic window sizing
    local titleExtra = state.popoutHideTitle and 0 or math.floor(26 * scale)
    local winHeight = titleExtra + (padding * 2) + (count * btnHeight) + math.max(0, count - 1) * spacing
    imgui.SetNextWindowSize({ popoutWidth, winHeight }, ImGuiCond_Always)

    -- Window Flags
    local winFlags = ImGuiWindowFlags_AlwaysAutoResize or 64
    winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoScrollbar or 8)
    if state.popoutHideTitle then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoTitleBar or 1)
    end
    if state.popoutHideBg then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoBackground or 128)
    end
    if state.popoutLockPosition then
        winFlags = bit.bor(winFlags, ImGuiWindowFlags_NoMove or 4)
    end

    local pushedWinVars = 0
    local pushedWinCols = 0

    if not state.popoutHideBg then
        imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, math.floor(6.0 * scale))
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0)
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { padding, padding })
        pushedWinVars = 3

        imgui.PushStyleColor(ImGuiCol_WindowBg, colors.bgDark)
        imgui.PushStyleColor(ImGuiCol_Border, theme.border)
        imgui.PushStyleColor(ImGuiCol_TitleBg, theme.idle)
        imgui.PushStyleColor(ImGuiCol_TitleBgActive, theme.hover)
        pushedWinCols = 4
    else
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { padding, padding })
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0)
        pushedWinVars = 2
    end

    local openPtr = { is_open }
    local isOpen = imgui.Begin('{Attend}###ZonePopout', openPtr, winFlags)
    if isOpen then
        local pushedFont = push_font_scale(scale)

        -- Push Hxbars-inspired button styles
        imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, math.floor(rounding * scale))
        imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0)
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, spacing })

        imgui.PushStyleColor(ImGuiCol_Button, theme.idle)
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, theme.hover)
        imgui.PushStyleColor(ImGuiCol_ButtonActive, theme.active)
        imgui.PushStyleColor(ImGuiCol_Text, theme.text)
        imgui.PushStyleColor(ImGuiCol_Border, theme.border)

        if evs and #evs > 0 then
            for idx, ev in ipairs(evs) do
                local isSA = state.selfAttestEvents[ev] == true or ev:find('%[SA%]')
                local label = ev
                if not label:find('%[SA%]') and state.selfAttestEvents[ev] == true then
                    label = label .. '  [SA]'
                end
                label = label .. '##popout_ev_' .. idx

                if imgui.Button(label, { -1, btnHeight }) then
                    if callbacks.on_launch_event and rawEvs and #rawEvs > 0 then
                        callbacks.on_launch_event(ev)
                    end
                end
            end
        else
            imgui.TextDisabled('No events for this zone.')
        end

        imgui.PopStyleColor(5)
        imgui.PopStyleVar(3)

        pop_font_scale(pushedFont)
    end
    imgui.End()

    if pushedWinCols > 0 then imgui.PopStyleColor(pushedWinCols) end
    if pushedWinVars > 0 then imgui.PopStyleVar(pushedWinVars) end

    return openPtr[1]
end

return ui
