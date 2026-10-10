local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CombatLogReminder = ns.Modules.Get("CombatLogReminder")

local TITLE_ROW_HEIGHT = 22
local HINT_ROW_HEIGHT = 16
local FOOTER_ROW_HEIGHT = 14
local ICON_SIZE = 18

local WINDOW_BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileEdge = true,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local window
local CreateWarningWindow
local UpdateWindow

local function EnsureWindow()
    window = window or CreateWarningWindow()
    return window
end

local function ApplyWindowScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

function UpdateWindow()
    local shouldShow = CombatLogReminder:ShouldRemind()
    if not shouldShow then
        if window and window:IsShown() then
            window:Hide()
        end
        return
    end

    local frame = EnsureWindow()
    frame:SetWindowScale(CombatLogReminder:GetScale())
    if not frame:IsShown() then
        frame:Show()
    end
    frame:Raise()
end

function CreateWarningWindow()
    local frame = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "CombatLogReminder",
        scale = CombatLogReminder:GetScale(),
        position = CombatLogReminder:GetPosition(),
        dragEntireFrame = true,
        onClick = function()
            CombatLogReminder:EnableLogging()
        end,
        onPositionChanged = function(position)
            CombatLogReminder:SetPosition(position)
        end,
    })
    frame:SetBackdrop(WINDOW_BACKDROP)
    frame:SetBackdropColor(Widgets.UnpackColor(Colors.BG_WARNING))
    frame:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER_WARNING))

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.MEDIUM,
        paddingY = Spacing.MEDIUM,
        spacing = Spacing.TINY,
    })

    local titleRow = stack:AddRow(TITLE_ROW_HEIGHT)
    local icon = titleRow:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetTexture(Assets.Icons.WARNING)
    icon:SetPoint("LEFT", titleRow, "LEFT")

    local title = Widgets.CreateLabel(titleRow, Fonts.BODY, L.COMBAT_LOG_REMINDER_WARNING_TITLE)
    title:SetTextColor(Widgets.UnpackColor(Colors.WARNING))
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetPoint("LEFT", icon, "RIGHT", Spacing.SMALL, 0)

    local hintRow = stack:AddRow(HINT_ROW_HEIGHT)
    local hint = Widgets.CreateLabel(hintRow, Fonts.BODY, L.COMBAT_LOG_REMINDER_WARNING_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetPoint("LEFT", hintRow, "LEFT")

    local footerRow = stack:AddRow(FOOTER_ROW_HEIGHT)
    local footer = Widgets.CreateLabel(footerRow, Fonts.TINY_MUTED, L.COMBAT_LOG_REMINDER_WARNING_FOOTER)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(false)
    footer:SetPoint("LEFT", footerRow, "LEFT")

    local contentWidth = math.max(
        ICON_SIZE + Spacing.SMALL + title:GetStringWidth(),
        hint:GetStringWidth(),
        footer:GetStringWidth()
    )
    title:SetPoint("RIGHT", titleRow, "RIGHT")
    hint:SetPoint("RIGHT", hintRow, "RIGHT")
    footer:SetPoint("RIGHT", footerRow, "RIGHT")
    frame:SetSize(contentWidth + 2 * Spacing.MEDIUM, stack:GetHeight())
    return frame
end

---@param parent Frame
---@param text string
---@param getChecked fun(): boolean
---@param setChecked fun(checked: boolean)
---@return Frame row
local function AddCheckboxRow(parent, text, getChecked, setChecked)
    local row = CreateFrame("Frame", nil, parent)
    local box = Widgets.CreateCheckbox(row)
    box:SetChecked(getChecked())
    box:SetScript("OnClick", function(self)
        if not CombatLogReminder:IsEnabled() then
            self:SetChecked(getChecked())
            return
        end
        setChecked(self:GetChecked())
        self:SetChecked(getChecked())
    end)

    local label = Widgets.CreateLabel(row, Fonts.BODY, text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    Layout.Row(row, { box, label }, Spacing.SMALL)
    -- Extend the clickable area over the label.
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    return row
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local locationsRow = body:AddRow(14)
    local locationsLabel = Widgets.CreateLabel(locationsRow, Fonts.SMALL_MUTED, L.COMBAT_LOG_REMINDER_LOCATIONS)
    locationsLabel:SetJustifyH("LEFT")
    locationsLabel:SetPoint("LEFT", locationsRow, "LEFT")

    local raidRow = AddCheckboxRow(content, L.COMBAT_LOG_REMINDER_RAIDS, function()
        return CombatLogReminder:GetRemindRaids()
    end, function(checked)
        CombatLogReminder:SetRemindRaids(checked)
    end)
    body:Add(raidRow, Sizes.CONTROL_HEIGHT)

    local mythicRow = AddCheckboxRow(content, L.COMBAT_LOG_REMINDER_MYTHIC_DUNGEONS, function()
        return CombatLogReminder:GetRemindMythicDungeons()
    end, function(checked)
        CombatLogReminder:SetRemindMythicDungeons(checked)
    end)
    body:Add(mythicRow, Sizes.CONTROL_HEIGHT)

    local scaleRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.MEDIUM)
    local scaleLabel = Widgets.CreateLabel(scaleRow, Fonts.BODY, L.COMBAT_LOG_REMINDER_SCALE)
    scaleLabel:SetJustifyH("LEFT")
    local scaleValue = Widgets.CreateLabel(scaleRow, Fonts.SMALL_MUTED)
    scaleValue:SetWidth(Sizes.SLIDER_VALUE_WIDTH)
    scaleValue:SetJustifyH("RIGHT")
    local scaleSlider = Widgets.CreateSlider(
        scaleRow,
        CombatLogReminder.SCALE_MIN,
        CombatLogReminder.SCALE_MAX,
        CombatLogReminder.SCALE_STEP
    )
    Widgets.AttachTooltip(scaleSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.COMBAT_LOG_REMINDER_SCALE_TOOLTIP)
    end)
    local function ShowScaleValue(scale)
        scaleValue:SetFormattedText(L.MAIN_PANEL_SCALE_PERCENT, math.floor(scale * 100 + 0.5))
    end
    scaleSlider:SetValue(CombatLogReminder:GetScale())
    ShowScaleValue(CombatLogReminder:GetScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not CombatLogReminder:IsEnabled() then
            return
        end
        CombatLogReminder:SetScale(rawValue)
        local scale = CombatLogReminder:GetScale()
        ShowScaleValue(scale)
        ApplyWindowScale(scale)
    end)
    Layout.Row(scaleRow, { scaleLabel }, 0)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", Spacing.LARGE, 0)
    scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", Spacing.MEDIUM, 0)

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    local section = FeatureSection.Create(container, {
        title = L.COMBAT_LOG_REMINDER_ENABLED,
        tooltip = L.COMBAT_LOG_REMINDER_HINT,
        enabled = CombatLogReminder:IsEnabled(),
        onEnabledChanged = function(enabled)
            CombatLogReminder:SetEnabled(enabled)
        end,
    })

    section:SetContentHeight(BuildContent(section.content))
    section:RefreshContentInteractive()
    stack:Add(section, section:GetHeight())

    return stack:GetHeight()
end

function CombatLogReminder:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.COMBAT_LOG_REMINDER_TITLE,
        group = ns.PanelGroups.COMBAT_MONITORING,
        build = Build,
    })
    self:StartMonitoring()
    UpdateWindow()
end

function CombatLogReminder:OnDisplayChanged()
    UpdateWindow()
end
