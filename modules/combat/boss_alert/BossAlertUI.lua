local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ColorSwatch = ns.ColorSwatch
local Dropdown = ns.Dropdown
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Slider = ns.Slider
local Checkbox = ns.Checkbox
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local BossAlert = ns.Modules.Get("BossAlert")

local function ApplyCalloutAppearance()
    ns.CalloutMessage.SetAppearance(BossAlert:GetCalloutAppearance())
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.MEDIUM,
    })

    local callout = FeatureSection.Create(body, {
        title = L.BOSS_ALERT_CALLOUT,
        tooltip = L.BOSS_ALERT_CALLOUT_SUBTITLE,
        toggle = false,
        divider = true,
    })
    local calloutBody = Layout.Stack(callout.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    local scaleRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local scaleLabel = Widgets.CreateLabel(scaleRow, Fonts.BODY, L.BOSS_ALERT_CALLOUT_SCALE)
    local scaleSlider = Slider.Create(
        scaleRow,
        BossAlert.CALLOUT_SCALE_MIN,
        BossAlert.CALLOUT_SCALE_MAX,
        BossAlert.CALLOUT_SCALE_STEP,
        { percentage = true }
    )
    scaleSlider:SetValue(BossAlert:GetCalloutScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        BossAlert:SetCalloutScale(rawValue)
    end)
    Layout.PlaceSlider(scaleRow, scaleLabel, scaleSlider)

    local fontRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontCell, fontColorCell = Layout.SplitRow(fontRow, Spacing.MEDIUM)
    local alertFontDropdown
    alertFontDropdown = Dropdown.CreateFont(fontCell, L.BOSS_ALERT_CALLOUT_ALERT_FONT, function(font)
        BossAlert:SetCalloutAlertFont(font)
        alertFontDropdown:SetSelected(font)
    end)
    alertFontDropdown:SetSelected(BossAlert:GetCalloutAlertFont())

    local alertFontColorLabel = Widgets.CreateLabel(fontColorCell, Fonts.BODY, L.BOSS_ALERT_CALLOUT_ALERT_FONT_COLOR)
    alertFontColorLabel:SetJustifyH("LEFT")
    local alertFontColorSwatch
    alertFontColorSwatch = ColorSwatch.Create(fontColorCell, BossAlert:GetCalloutAlertFontColor(), function(color)
        BossAlert:SetCalloutAlertFontColor(color)
        alertFontColorSwatch:SetColor(BossAlert:GetCalloutAlertFontColor())
    end)
    Layout.Row(fontColorCell, { alertFontColorLabel, alertFontColorSwatch }, Spacing.LARGE)

    local countdownFontSizeRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local countdownFontSizeLabel =
        Widgets.CreateLabel(countdownFontSizeRow, Fonts.BODY, L.BOSS_ALERT_CALLOUT_COUNTDOWN_FONT_SIZE)
    local countdownFontSizeSlider = Slider.Create(
        countdownFontSizeRow,
        BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_MIN,
        BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_MAX,
        BossAlert.CALLOUT_COUNTDOWN_FONT_SIZE_STEP
    )
    countdownFontSizeSlider:SetValue(BossAlert:GetCalloutCountdownFontSize())
    countdownFontSizeSlider:SetScript("OnValueChanged", function(_, rawValue)
        BossAlert:SetCalloutCountdownFontSize(rawValue)
    end)
    Layout.PlaceSlider(countdownFontSizeRow, countdownFontSizeLabel, countdownFontSizeSlider)

    local ttsRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local ttsBox = Checkbox.Create(ttsRow)
    ttsBox:SetChecked(BossAlert:IsCalloutTtsEnabled())
    ttsBox:SetScript("OnClick", function(self)
        BossAlert:SetCalloutTtsEnabled(self:GetChecked())
        self:SetChecked(BossAlert:IsCalloutTtsEnabled())
    end)
    local ttsLabel = Widgets.CreateLabel(ttsRow, Fonts.BODY, L.BOSS_ALERT_CALLOUT_TTS)
    ttsLabel:SetJustifyH("LEFT")
    ttsLabel:SetWordWrap(false)
    Layout.Row(ttsRow, { ttsBox, ttsLabel }, Spacing.SMALL)
    ttsBox:SetHitRectInsets(0, -(ttsLabel:GetStringWidth() + Spacing.SMALL), 0, 0)

    ns.SharedMedia.OnFontsRegistered(function()
        alertFontDropdown:RefreshItems()
        alertFontDropdown:SetSelected(BossAlert:GetCalloutAlertFont())
        ApplyCalloutAppearance()
    end)

    local resetButton = Widgets.CreateTextButton(callout, L.BOSS_ALERT_CALLOUT_RESET, function()
        BossAlert:ResetCalloutAppearance()
        scaleSlider:SetValue(BossAlert:GetCalloutScale())
        countdownFontSizeSlider:SetValue(BossAlert:GetCalloutCountdownFontSize())
        alertFontDropdown:RefreshItems()
        alertFontDropdown:SetSelected(BossAlert:GetCalloutAlertFont())
        alertFontColorSwatch:SetColor(BossAlert:GetCalloutAlertFontColor())
    end)
    callout:SetHeaderAction(resetButton)

    callout:SetContentHeight(calloutBody:GetHeight())
    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    return BuildContent(container)
end

function BossAlert:OnCalloutAppearanceChanged()
    ApplyCalloutAppearance()
end

function BossAlert:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.BOSS_ALERT_TITLE,
        group = ns.PanelGroups.COMBAT,
        subtitle = L.BOSS_ALERT_CALLOUT_SUBTITLE,
        build = Build,
    })
    ApplyCalloutAppearance()
    self:ListenForCalloutTts()
end
