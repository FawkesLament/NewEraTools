local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ColorSwatch = ns.ColorSwatch
local Dropdown = ns.Dropdown
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Slider = ns.Slider
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local BossAlert = ns.Modules.Get("BossAlert")

local function ApplyCalloutAppearance()
    ns.CalloutMessage.SetAppearance(BossAlert:GetCalloutAppearance())
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

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local callout = FeatureSection.Create(body, {
        title = L.BOSS_ALERT_CALLOUT,
        tooltip = L.BOSS_ALERT_CALLOUT_TOOLTIP,
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
    PlaceSlider(scaleRow, scaleLabel, scaleSlider)

    local fontRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontCell, fontSizeCell = Layout.SplitRow(fontRow, Spacing.MEDIUM)
    local fontDropdown
    fontDropdown = Dropdown.CreateFont(fontCell, L.BOSS_ALERT_CALLOUT_FONT, function(font)
        BossAlert:SetCalloutFont(font)
        fontDropdown:SetSelected(font)
    end)
    fontDropdown:SetSelected(BossAlert:GetCalloutFont())

    local fontSizeLabel = Widgets.CreateLabel(fontSizeCell, Fonts.BODY, L.BOSS_ALERT_CALLOUT_FONT_SIZE)
    local fontSizeSlider = Slider.Create(
        fontSizeCell,
        BossAlert.CALLOUT_FONT_SIZE_MIN,
        BossAlert.CALLOUT_FONT_SIZE_MAX,
        BossAlert.CALLOUT_FONT_SIZE_STEP
    )
    fontSizeSlider:SetValue(BossAlert:GetCalloutFontSize())
    fontSizeSlider:SetScript("OnValueChanged", function(_, rawValue)
        BossAlert:SetCalloutFontSize(rawValue)
    end)
    PlaceSlider(fontSizeCell, fontSizeLabel, fontSizeSlider)

    local fontColorRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontColorLabel = Widgets.CreateLabel(fontColorRow, Fonts.BODY, L.BOSS_ALERT_CALLOUT_FONT_COLOR)
    fontColorLabel:SetJustifyH("LEFT")
    local fontColorSwatch
    fontColorSwatch = ColorSwatch.Create(fontColorRow, BossAlert:GetCalloutFontColor(), function(color)
        BossAlert:SetCalloutFontColor(color)
        fontColorSwatch:SetColor(BossAlert:GetCalloutFontColor())
    end)
    Layout.Row(fontColorRow, { fontColorLabel, fontColorSwatch }, Spacing.LARGE)

    local ttsRow = calloutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local ttsBox = Widgets.CreateCheckbox(ttsRow)
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
        fontDropdown:RefreshItems()
        fontDropdown:SetSelected(BossAlert:GetCalloutFont())
        ApplyCalloutAppearance()
    end)

    local resetButton = Widgets.CreateTextButton(callout, L.BOSS_ALERT_CALLOUT_RESET, function()
        BossAlert:ResetCalloutAppearance()
        scaleSlider:SetValue(BossAlert:GetCalloutScale())
        fontSizeSlider:SetValue(BossAlert:GetCalloutFontSize())
        fontDropdown:RefreshItems()
        fontDropdown:SetSelected(BossAlert:GetCalloutFont())
        fontColorSwatch:SetColor(BossAlert:GetCalloutFontColor())
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
        tooltip = L.BOSS_ALERT_CALLOUT_TOOLTIP,
        build = Build,
    })
    ApplyCalloutAppearance()
    self:ListenForCalloutTts()
end
