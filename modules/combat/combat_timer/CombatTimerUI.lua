local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Slider = ns.Slider
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CombatTimer = ns.Modules.Get("CombatTimer")

-- Compact enough for MM:SS + a short status line; tooltip border supplies slight rounding.
local WINDOW_WIDTH = 148
local TIMER_ROW_HEIGHT = 34
local STATUS_ROW_HEIGHT = 16

local WINDOW_BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local LAYOUT_ID = "CombatTimer:1"

local window
local timeLabel
local statusLabel
local layoutRegistered = false
local layoutEditing = false
local CreateTimerWindow
local UpdateDisplay
local UpdateWindow
local RegisterLayoutElement

local function EnsureWindow()
    window = window or CreateTimerWindow()
    return window
end

local function ApplyWindowScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

function UpdateDisplay()
    if not timeLabel then
        return
    end
    timeLabel:SetText(CombatTimer:FormatElapsed(CombatTimer:GetDisplayElapsed()))
    if CombatTimer:IsInCombat() then
        statusLabel:SetText(L.COMBAT_TIMER_IN_COMBAT)
        statusLabel:SetTextColor(Widgets.UnpackColor(Colors.SUCCESS))
    else
        statusLabel:SetText(L.COMBAT_TIMER_ENDED)
        statusLabel:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
    end
end

function UpdateWindow()
    if layoutEditing then
        return
    end
    if not CombatTimer:IsEnabled() then
        if window and window:IsShown() then
            window:Hide()
        end
        return
    end
    local frame = EnsureWindow()
    UpdateDisplay()
    if not frame:IsShown() then
        frame:Show()
    end
    frame:Raise()
end

function CreateTimerWindow()
    local frame = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "CombatTimer",
        scale = CombatTimer:GetScale(),
        position = CombatTimer:GetPosition(),
        -- Positioning is handled by LayoutEditor; the window must not steal clicks in combat.
        draggable = false,
        dragEntireFrame = true,
        onPositionChanged = function(position)
            CombatTimer:SetPosition(position)
        end,
    })
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(Widgets.UnpackColor(Colors.BG_TRANSLUCENT))
    frame:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER_SUBTLE))

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.MEDIUM,
        paddingY = Spacing.MEDIUM,
        spacing = Spacing.SMALL,
    })

    local timerRow = stack:AddRow(TIMER_ROW_HEIGHT)
    timeLabel = Widgets.CreateLabel(timerRow, Fonts.DISPLAY)
    timeLabel:SetJustifyH("CENTER")
    timeLabel:SetWordWrap(false)
    timeLabel:SetPoint("CENTER", timerRow, "CENTER")

    local statusRow = stack:AddRow(STATUS_ROW_HEIGHT)
    statusLabel = Widgets.CreateLabel(statusRow, Fonts.SMALL_MUTED)
    statusLabel:SetJustifyH("CENTER")
    statusLabel:SetWordWrap(false)
    statusLabel:SetPoint("CENTER", statusRow, "CENTER")

    frame:SetSize(WINDOW_WIDTH, stack:GetHeight())
    -- Tick only while shown and in combat; out-of-combat text is static.
    frame:SetScript("OnUpdate", function()
        if CombatTimer:IsInCombat() then
            UpdateDisplay()
        end
    end)
    RegisterLayoutElement(frame)
    return frame
end

function RegisterLayoutElement(frame)
    if layoutRegistered then
        return
    end
    layoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.COMBAT_TIMER_TITLE,
        frame = frame,
        global = true,
        isEnabled = function()
            return CombatTimer:IsEnabled()
        end,
        getPosition = function()
            return CombatTimer:GetPosition()
        end,
        setPosition = function(position)
            CombatTimer:SetPosition(position)
        end,
        getDefaultPosition = function()
            return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 }
        end,
        onEditBegin = function()
            layoutEditing = true
            local win = EnsureWindow()
            UpdateDisplay()
            win:Show()
            win:Raise()
        end,
        onEditEnd = function()
            layoutEditing = false
            UpdateWindow()
        end,
    })
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    local controlsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local formatCell, scaleCell = Layout.SplitRow(controlsRow, Spacing.MEDIUM)

    local formatLabel = Widgets.CreateLabel(formatCell, Fonts.BODY, L.COMBAT_TIMER_FORMAT)
    formatLabel:SetJustifyH("LEFT")
    local formatControl
    formatControl = Widgets.CreateSegmentedControl(formatCell, {
        { value = CombatTimer.FORMAT_MMSS, text = L.COMBAT_TIMER_FORMAT_MMSS },
        { value = CombatTimer.FORMAT_SECONDS, text = L.COMBAT_TIMER_FORMAT_SECONDS },
    }, function(format)
        if not CombatTimer:IsEnabled() then
            return
        end
        CombatTimer:SetFormat(format)
        formatControl:SetSelected(format)
        UpdateDisplay()
    end)
    formatControl:SetSelected(CombatTimer:GetFormat())
    Layout.Row(formatCell, { formatLabel, formatControl }, Spacing.LARGE)

    local scaleLabel = Widgets.CreateLabel(scaleCell, Fonts.BODY, L.COMBAT_TIMER_SCALE)
    scaleLabel:SetJustifyH("LEFT")
    local scaleSlider = Slider.Create(
        scaleCell,
        CombatTimer.SCALE_MIN,
        CombatTimer.SCALE_MAX,
        CombatTimer.SCALE_STEP,
        { percentage = true }
    )
    Widgets.AttachTooltip(scaleSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.COMBAT_TIMER_SCALE_TOOLTIP)
    end)
    scaleSlider:SetValue(CombatTimer:GetScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not CombatTimer:IsEnabled() then
            return
        end
        CombatTimer:SetScale(rawValue)
        ApplyWindowScale(CombatTimer:GetScale())
    end)
    Layout.Row(scaleCell, { scaleLabel }, 0)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", Spacing.LARGE, 0)

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    container:RefreshContentInteractive()
    return height
end

function CombatTimer:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.COMBAT_TIMER_TITLE,
        group = ns.PanelGroups.COMBAT,
        tooltip = L.COMBAT_TIMER_HINT,
        enabled = CombatTimer:IsEnabled(),
        onEnabledChanged = function(enabled)
            CombatTimer:SetEnabled(enabled)
        end,
        build = Build,
    })
    self:ListenForCombat()
    -- Register with the layout editor even before the window is first shown.
    EnsureWindow()
    UpdateWindow()
end

function CombatTimer:OnEnabledChanged()
    UpdateWindow()
end

function CombatTimer:OnCombatChanged()
    UpdateDisplay()
end
