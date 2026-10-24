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

local RLToolbar = ns.Modules.Get("RLToolbar")

local BUTTON_SIZE = 28
local ICON_SIZE = 18
local CLOSE_MARK_PAD = 4
local CLOSE_MARK_THICKNESS = 2
local PRESS_ALPHA = 0.16
local LAYOUT_ID = "RLToolbar:1"

local WINDOW_BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BUTTONS = {
    {
        action = "readyCheck",
        tooltip = L.RL_TOOLBAR_READY_CHECK,
        icon = Assets.Icons.READY_CHECK_READY,
    },
    {
        action = "countdown5",
        tooltip = L.RL_TOOLBAR_COUNTDOWN_5,
        label = L.RL_TOOLBAR_COUNTDOWN_5_LABEL,
    },
    {
        action = "countdown10",
        tooltip = L.RL_TOOLBAR_COUNTDOWN_10,
        label = L.RL_TOOLBAR_COUNTDOWN_10_LABEL,
    },
    {
        action = "countdown15",
        tooltip = L.RL_TOOLBAR_COUNTDOWN_15,
        label = L.RL_TOOLBAR_COUNTDOWN_15_LABEL,
    },
    {
        action = "cancelCountdown",
        tooltip = L.RL_TOOLBAR_CANCEL_COUNTDOWN,
        closeMark = true,
        danger = true,
    },
}

local window
---@type table<string, Button>
local buttonsByAction = {}
---@type Frame|nil
local buttonRow
local layoutRegistered = false
local layoutEditing = false
local CreateToolbar
local LayoutToolbarButtons
local UpdateWindow
local RegisterLayoutElement

local function EnsureWindow()
    window = window or CreateToolbar()
    return window
end

local function AccentColor(danger)
    if danger then
        return Colors.ERROR
    end
    return Colors.ACCENT
end

---Two diagonal strokes, so the cancel mark is geometrically centered (the × glyph is not).
---@param parent Frame
---@param color table
local function CreateCloseMark(parent, color)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", parent, "CENTER")
    local x1, x2 = CLOSE_MARK_PAD, ICON_SIZE - CLOSE_MARK_PAD
    local strokes = {
        { x1, x1, x2, x2 },
        { x2, x1, x1, x2 },
    }
    for _, stroke in ipairs(strokes) do
        local line = icon:CreateLine(nil, "ARTWORK")
        line:SetThickness(CLOSE_MARK_THICKNESS)
        line:SetColorTexture(Widgets.UnpackColor(color))
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetStartPoint("TOPLEFT", icon, stroke[1], -stroke[2])
        line:SetEndPoint("TOPLEFT", icon, stroke[3], -stroke[4])
    end
end

---@param parent Frame
---@param spec table
---@return Button
local function CreateToolbarButton(parent, spec)
    local accent = AccentColor(spec.danger)
    local button = Widgets.CreateFlatButton(parent, spec.danger and "secondary" or "accent", function()
        if layoutEditing then
            return
        end
        RLToolbar:RunAction(spec.action)
    end)
    if spec.danger then
        Widgets.ApplyBackdrop(button, Colors.SURFACE_RAISED, accent)
    end
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    Widgets.AttachTooltip(button, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(spec.tooltip)
    end)

    if spec.icon then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("CENTER", button, "CENTER")
        icon:SetTexture(spec.icon)
        -- Ready-check art has transparent padding; crop so the mark fills the square.
        icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    elseif spec.closeMark then
        CreateCloseMark(button, accent)
    elseif spec.label then
        local label = Widgets.CreateLabel(button, Fonts.EMPHASIS, spec.label)
        -- Fill the button so LEFT-default font strings cannot sit off-center.
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(false)
        label:SetPoint("TOPLEFT")
        label:SetPoint("BOTTOMRIGHT")
        label:SetTextColor(Widgets.UnpackColor(accent))
    end

    local wash = button:CreateTexture(nil, "ARTWORK")
    wash:SetAllPoints()
    local r, g, b = Widgets.UnpackColor(accent)
    wash:SetColorTexture(r, g, b, PRESS_ALPHA)
    wash:Hide()
    button:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            wash:Show()
        end
    end)
    button:HookScript("OnMouseUp", function()
        wash:Hide()
    end)
    button:HookScript("OnLeave", function()
        wash:Hide()
    end)
    button:HookScript("OnDisable", function()
        wash:Hide()
    end)
    return button
end

function LayoutToolbarButtons()
    if not window or not buttonRow then
        return
    end
    local visible = {}
    for _, spec in ipairs(BUTTONS) do
        local button = buttonsByAction[spec.action]
        local shown = RLToolbar:IsButtonShown(spec.action)
        button:SetShown(shown)
        if shown then
            visible[#visible + 1] = button
        end
    end
    Layout.Row(buttonRow, visible, Spacing.SMALL)
    local count = #visible
    local width = Spacing.SMALL * 2 + BUTTON_SIZE * count + Spacing.SMALL * math.max(count - 1, 0)
    window:SetSize(width, Spacing.SMALL * 2 + BUTTON_SIZE)
end

local function ApplyWindowScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

function CreateToolbar()
    local frame = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "RLToolbar",
        scale = RLToolbar:GetScale(),
        position = RLToolbar:GetPosition(),
        -- Positioning is handled by LayoutEditor; the bar must not steal clicks in combat.
        draggable = false,
        dragEntireFrame = true,
        onPositionChanged = function(position)
            RLToolbar:SetPosition(position)
        end,
    })
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(Widgets.UnpackColor(Colors.BG_TRANSLUCENT))
    frame:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER_SUBTLE))

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })
    buttonRow = stack:AddRow(BUTTON_SIZE)
    buttonsByAction = {}
    for _, spec in ipairs(BUTTONS) do
        buttonsByAction[spec.action] = CreateToolbarButton(buttonRow, spec)
    end
    window = frame
    LayoutToolbarButtons()
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
        label = L.RL_TOOLBAR_TITLE,
        frame = frame,
        global = true,
        isEnabled = function()
            return RLToolbar:IsEnabled()
        end,
        getPosition = function()
            return RLToolbar:GetPosition()
        end,
        setPosition = function(position)
            RLToolbar:SetPosition(position)
        end,
        getDefaultPosition = function()
            return RLToolbar:GetDefaultPosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            UpdateWindow()
        end,
        onEditEnd = function()
            layoutEditing = false
            UpdateWindow()
        end,
    })
end

function UpdateWindow()
    if not RLToolbar:ShouldShow(layoutEditing) then
        if window and window:IsShown() then
            window:Hide()
        end
        return
    end
    local frame = EnsureWindow()
    if not frame:IsShown() then
        frame:Show()
    end
    frame:Raise()
end

---@param row Frame
---@param label FontString
---@param slider SliderControl
local function PlaceSlider(row, label, slider)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT")
    local box = slider.valueBox
    local suffix = slider.valueSuffix
    if suffix then
        suffix:ClearAllPoints()
        suffix:SetPoint("RIGHT", row, "RIGHT")
        box:ClearAllPoints()
        box:SetPoint("RIGHT", suffix, "LEFT", -Spacing.TINY, 0)
    else
        box:ClearAllPoints()
        box:SetPoint("RIGHT", row, "RIGHT")
    end
    slider:ClearAllPoints()
    slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -Spacing.MEDIUM, 0)
end

---@param row Frame
---@param text string
---@param get fun(): boolean
---@param set fun(shown: boolean)
---@return CheckButton
---@return FontString
local function CreateShownCheckbox(row, text, get, set)
    local box = Widgets.CreateCheckbox(row)
    box:SetChecked(get())
    box:SetScript("OnClick", function(self)
        if not RLToolbar:IsEnabled() then
            self:SetChecked(get())
            return
        end
        set(self:GetChecked())
        self:SetChecked(get())
    end)
    local label = Widgets.CreateLabel(row, Fonts.BODY, text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    Layout.Row(row, { box, label }, Spacing.SMALL)
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    return box, label
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local scaleRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local scaleLabel = Widgets.CreateLabel(scaleRow, Fonts.BODY, L.RL_TOOLBAR_SCALE)
    local scaleSlider = Slider.Create(
        scaleRow,
        RLToolbar.SCALE_MIN,
        RLToolbar.SCALE_MAX,
        RLToolbar.SCALE_STEP,
        { percentage = true }
    )
    Widgets.AttachTooltip(scaleSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.RL_TOOLBAR_SCALE_TOOLTIP)
    end)
    scaleSlider:SetValue(RLToolbar:GetScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not RLToolbar:IsEnabled() then
            return
        end
        RLToolbar:SetScale(rawValue)
        ApplyWindowScale(RLToolbar:GetScale())
    end)
    PlaceSlider(scaleRow, scaleLabel, scaleSlider)

    local buttonsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fiveCell, fifteenCell = Layout.SplitRow(buttonsRow, Spacing.MEDIUM)
    CreateShownCheckbox(fiveCell, L.RL_TOOLBAR_SHOW_COUNTDOWN_5, function()
        return RLToolbar:IsCountdown5Shown()
    end, function(shown)
        RLToolbar:SetCountdown5Shown(shown)
    end)
    CreateShownCheckbox(fifteenCell, L.RL_TOOLBAR_SHOW_COUNTDOWN_15, function()
        return RLToolbar:IsCountdown15Shown()
    end, function(shown)
        RLToolbar:SetCountdown15Shown(shown)
    end)

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    container:RefreshContentInteractive()
    return height
end

function RLToolbar:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.RL_TOOLBAR_TITLE,
        group = ns.PanelGroups.RAID_LEADER,
        enabled = RLToolbar:IsEnabled(),
        onEnabledChanged = function(enabled)
            RLToolbar:SetEnabled(enabled)
        end,
        build = Build,
    })
    self:ListenForVisibility()
    -- Register with the layout editor even before the bar is first shown.
    EnsureWindow()
    UpdateWindow()
end

function RLToolbar:OnVisibilityChanged()
    UpdateWindow()
end

function RLToolbar:OnLayoutChanged()
    LayoutToolbarButtons()
end
