local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CollapsibleSection = ns.CollapsibleSection
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Player = ns.Api.Player
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

local SPELL_ID_DIGITS = 9
local MAX_STACKS_DIGITS = 3
-- Lightweight editor title block: spell icon + name/subtitle column, then a 1px divider.
local EDITOR_HEADER_ICON_SIZE = 32
local EDITOR_HEADER_TITLE_HEIGHT = 22
local EDITOR_HEADER_SUBTITLE_HEIGHT = 14
local EDITOR_HEADER_BODY_HEIGHT =
    math.max(EDITOR_HEADER_ICON_SIZE, EDITOR_HEADER_TITLE_HEIGHT + EDITOR_HEADER_SUBTITLE_HEIGHT)
local EDITOR_HEADER_HEIGHT = EDITOR_HEADER_BODY_HEIGHT + Spacing.SMALL + Sizes.BORDER

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

local TEXTURE_LABELS = {
    flat = L.AURA_TRACKER_TEXTURE_FLAT,
    default = L.AURA_TRACKER_TEXTURE_DEFAULT,
    raid = L.AURA_TRACKER_TEXTURE_RAID,
}

local sharedMediaListening = false

---@return boolean
function UI.CanEditSelected()
    return AuraTracker:IsEnabled() and UI.ResolveSelectedTrackerId() ~= nil
end

---@return DropdownItem[]
local function BuildTextureItems()
    local items = {}
    for _, textureId in ipairs(AuraTracker:ListTextureIds()) do
        items[#items + 1] = {
            value = textureId,
            text = TEXTURE_LABELS[textureId] or textureId,
        }
    end
    return items
end

---@return DropdownItem[]
local function BuildTimeFontItems()
    local items = {}
    for _, fontId in ipairs(AuraTracker:ListTimeFontIds()) do
        items[#items + 1] = {
            value = fontId,
            text = fontId == AuraTracker.TIME_FONT_DEFAULT and L.AURA_TRACKER_TIME_FONT_DEFAULT or fontId,
        }
    end
    return items
end

local function RefreshTextureDropdown()
    if not UI.textureDropdown then
        return
    end
    UI.textureDropdown:SetItems(BuildTextureItems())
    local trackerId = UI.ResolveSelectedTrackerId()
    if trackerId then
        UI.textureDropdown:SetSelected(AuraTracker:GetTexture(trackerId))
    end
end

local function RefreshTimeFontDropdown()
    if not UI.timeFontDropdown then
        return
    end
    UI.timeFontDropdown:SetItems(BuildTimeFontItems())
    local trackerId = UI.ResolveSelectedTrackerId()
    if trackerId then
        UI.timeFontDropdown:SetSelected(AuraTracker:GetTimeFont(trackerId))
    end
end

function UI.RefreshTimePositionControls()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local vertical = AuraTracker:GetVertical(trackerId)
    local position = AuraTracker:GetTimePosition(trackerId)
    if UI.timePositionHorizontal then
        UI.timePositionHorizontal:SetShown(not vertical)
        if not vertical then
            UI.timePositionHorizontal:SetSelected(position)
        end
    end
    if UI.timePositionVertical then
        UI.timePositionVertical:SetShown(vertical)
        if vertical then
            UI.timePositionVertical:SetSelected(position)
        end
    end
end

---When vertical, stored width is the on-screen height and stored height is the on-screen width.
function UI.RefreshSizeLabels()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local vertical = AuraTracker:GetVertical(trackerId)
    if UI.widthSlider and UI.widthSlider._label then
        UI.widthSlider._label:SetText(vertical and L.AURA_TRACKER_HEIGHT or L.AURA_TRACKER_WIDTH)
    end
    if UI.heightSlider and UI.heightSlider._label then
        UI.heightSlider._label:SetText(vertical and L.AURA_TRACKER_WIDTH or L.AURA_TRACKER_HEIGHT)
    end
end

---LibSharedMedia fires this after a successful Register; refresh the texture/font picker lists.
---@param _ any
---@param mediaType string
local function OnSharedMediaRegistered(_, mediaType)
    if mediaType == "statusbar" then
        RefreshTextureDropdown()
    elseif mediaType == "font" then
        RefreshTimeFontDropdown()
    end
end

function UI.ListenForSharedMedia()
    if sharedMediaListening or LibStub == nil then
        return
    end
    local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok or not lsm or not lsm.RegisterCallback then
        return
    end
    sharedMediaListening = true
    lsm.RegisterCallback(AuraTracker, "LibSharedMedia_Registered", OnSharedMediaRegistered)
end

---@param scope string
---@param savedTarget integer|string|nil
---@return string
local function FormatScopeSegmentLabel(scope, savedTarget)
    if scope == AuraTracker.SCOPE_ALWAYS then
        return L.AURA_TRACKER_SCOPE_ALWAYS
    end
    if scope == AuraTracker.SCOPE_SPECIALIZATION then
        return Player.GetSpecializationName(savedTarget)
            or Player.GetSpecializationName(Player.GetSpecializationId())
            or "-"
    end
    if scope == AuraTracker.SCOPE_CLASS then
        return Player.GetClassName(savedTarget) or Player.GetClassName(Player.GetClassFile()) or "-"
    end
    if scope == AuraTracker.SCOPE_ROLE then
        local role = savedTarget or Player.GetRole()
        return (role and ROLE_LABELS[role]) or "-"
    end
    return "-"
end

---Toggle segments in order: specialization → class → role → always.
---Selected scope uses the aura's saved target; others preview the current character.
---@param trackerId integer|nil
---@return SegmentedControlItem[]
local function BuildActivationScopeItems(trackerId)
    local scope, target
    if trackerId then
        scope, target = AuraTracker:GetActivationScope(trackerId)
    end
    return {
        {
            value = AuraTracker.SCOPE_SPECIALIZATION,
            text = FormatScopeSegmentLabel(
                AuraTracker.SCOPE_SPECIALIZATION,
                scope == AuraTracker.SCOPE_SPECIALIZATION and target or nil
            ),
        },
        {
            value = AuraTracker.SCOPE_CLASS,
            text = FormatScopeSegmentLabel(AuraTracker.SCOPE_CLASS, scope == AuraTracker.SCOPE_CLASS and target or nil),
        },
        {
            value = AuraTracker.SCOPE_ROLE,
            text = FormatScopeSegmentLabel(AuraTracker.SCOPE_ROLE, scope == AuraTracker.SCOPE_ROLE and target or nil),
        },
        {
            value = AuraTracker.SCOPE_ALWAYS,
            text = FormatScopeSegmentLabel(AuraTracker.SCOPE_ALWAYS),
        },
    }
end

---Assigns a new scope using the current character's identifiers; same-scope reselection keeps the saved target.
---@param trackerId integer
---@param scope string
local function AssignActivationScope(trackerId, scope)
    local currentScope = AuraTracker:GetActivationScope(trackerId)
    if currentScope == scope then
        return
    end
    if scope == AuraTracker.SCOPE_ALWAYS then
        AuraTracker:SetActivationScope(trackerId, scope, nil)
        return
    end
    if scope == AuraTracker.SCOPE_SPECIALIZATION then
        local specializationId = Player.GetSpecializationId()
        if specializationId then
            AuraTracker:SetActivationScope(trackerId, scope, specializationId)
        end
        return
    end
    if scope == AuraTracker.SCOPE_CLASS then
        local classFile = Player.GetClassFile()
        if classFile then
            AuraTracker:SetActivationScope(trackerId, scope, classFile)
        end
        return
    end
    if scope == AuraTracker.SCOPE_ROLE then
        local role = Player.GetRole()
        if role then
            AuraTracker:SetActivationScope(trackerId, scope, role)
        end
    end
end

local function RefreshActivationScopeControl()
    if not UI.activationScopeControl then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    UI.activationScopeControl:SetItems(BuildActivationScopeItems(trackerId))
    UI.activationScopeControl:SetSelected(AuraTracker:GetActivationScope(trackerId))
end

local function CommitSpellIdFromBox()
    if UI.refreshingControls or not UI.spellIdBox then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local raw = UI.spellIdBox:GetNumber()
    local spellId = (type(raw) == "number" and raw > 0) and math.floor(raw) or 0
    AuraTracker:SetSpellId(trackerId, spellId)
    UI.spellIdBox:SetText(spellId > 0 and tostring(spellId) or "")
    UI.RefreshEditorHeader(trackerId)
    UI.RefreshTrackerList()
end

---@param trackerId integer
function UI.RefreshEditorHeader(trackerId)
    local spellId = AuraTracker:GetSpellId(trackerId)
    if UI.editorSpellIcon then
        UI.ApplySpellIcon(UI.editorSpellIcon, spellId)
    end
    if UI.editorNameLabel then
        UI.editorNameLabel:SetText(AuraTracker:GetDisplayName(trackerId))
    end
    if UI.editorSubtitleLabel then
        local spellText = spellId > 0 and tostring(spellId) or "-"
        UI.editorSubtitleLabel:SetText(string.format(L.AURA_TRACKER_EDITOR_SUBTITLE, spellText))
    end
end

local function CommitMaxStacksFromBox()
    if UI.refreshingControls or not UI.maxStacksBox then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local raw = UI.maxStacksBox:GetNumber()
    local maxStacks = (type(raw) == "number" and raw > 0) and math.floor(raw) or AuraTracker.MAX_STACKS_MIN
    AuraTracker:SetMaxStacks(trackerId, maxStacks)
    UI.maxStacksBox:SetText(tostring(AuraTracker:GetMaxStacks(trackerId)))
end

local function RelayoutValueSection()
    if not UI.valueBody or not UI.valueSection then
        return
    end
    UI.valueSection:SetContentHeight(UI.valueBody:GetHeight())
end

function UI.RefreshTrackingModeControls()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local stacksMode = AuraTracker:IsStacksMode(trackerId)
    if UI.trackingModeControl then
        UI.trackingModeControl:SetSelected(AuraTracker:GetTrackingMode(trackerId))
    end
    if UI.maxStacksCell then
        UI.maxStacksCell:SetShown(stacksMode)
    end
    if UI.maxStacksBox and stacksMode then
        UI.maxStacksBox:SetText(tostring(AuraTracker:GetMaxStacks(trackerId)))
    end
    if UI.stackDividerCell then
        UI.stackDividerCell:SetShown(stacksMode)
    end
end

---Builds a labeled slider into `parent` (a full row or a SplitRow cell).
---@param parent Frame
---@param labelText string
---@param min number
---@param max number
---@param step number
---@param getValue fun(trackerId: integer): number
---@param setValue fun(trackerId: integer, value: number)
---@param formatValue fun(value: number): string
---@return Slider
local function AddSlider(parent, labelText, min, max, step, getValue, setValue, formatValue)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    local valueLabel = Widgets.CreateLabel(parent, Fonts.SMALL_MUTED)
    valueLabel:SetWidth(Sizes.SLIDER_VALUE_WIDTH + 8)
    valueLabel:SetJustifyH("RIGHT")
    local slider = Widgets.CreateSlider(parent, min, max, step)
    local trackerId = UI.ResolveSelectedTrackerId()
    local initial = trackerId and getValue(trackerId) or min
    slider:SetValue(initial)
    valueLabel:SetText(formatValue(initial))
    slider:SetScript("OnValueChanged", function(_, rawValue)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local id = UI.ResolveSelectedTrackerId()
        if not id then
            return
        end
        setValue(id, rawValue)
        valueLabel:SetText(formatValue(getValue(id)))
    end)
    slider._label = label
    slider._valueLabel = valueLabel
    slider._getValue = getValue
    slider._formatValue = formatValue
    Layout.Row(parent, { label }, 0)
    slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    valueLabel:SetPoint("LEFT", slider, "RIGHT", Spacing.MEDIUM, 0)
    return slider
end

---Builds a labeled checkbox into `parent`.
---@param parent Frame
---@param text string
---@param getChecked fun(trackerId: integer): boolean
---@param setChecked fun(trackerId: integer, checked: boolean)
---@return CheckButton
local function AddCheckbox(parent, text, getChecked, setChecked)
    local box = Widgets.CreateCheckbox(parent)
    local trackerId = UI.ResolveSelectedTrackerId()
    box:SetChecked(trackerId and getChecked(trackerId) or false)
    box:SetScript("OnClick", function(self)
        if UI.refreshingControls or not UI.CanEditSelected() then
            local id = UI.ResolveSelectedTrackerId()
            self:SetChecked(id and getChecked(id) or false)
            return
        end
        local id = UI.ResolveSelectedTrackerId()
        if not id then
            return
        end
        setChecked(id, self:GetChecked())
        self:SetChecked(getChecked(id))
    end)

    local label = Widgets.CreateLabel(parent, Fonts.BODY, text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    Layout.Row(parent, { box, label }, Spacing.SMALL)
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    return box
end

---Builds a labeled color swatch into `parent`.
---@param parent Frame
---@param labelText string
---@param getColor fun(trackerId: integer): AuraTrackerColor
---@param setColor fun(trackerId: integer, color: AuraTrackerColor)
---@return ColorSwatch swatch
local function AddColor(parent, labelText, getColor, setColor)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    local trackerId = UI.ResolveSelectedTrackerId()
    local swatch = Widgets.CreateColorSwatch(
        parent,
        trackerId and getColor(trackerId) or { r = 1, g = 1, b = 1 },
        function(color)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local id = UI.ResolveSelectedTrackerId()
            if id then
                setColor(id, color)
            end
        end
    )
    Layout.Row(parent, { label, swatch }, Spacing.LARGE)
    return swatch
end

---Builds a labeled dropdown into `parent`, stretching to the cell width.
---@param parent Frame
---@param labelText string
---@param items DropdownItem[]
---@param getValue fun(trackerId: integer): any
---@param setValue fun(trackerId: integer, value: any)
---@return Dropdown dropdown
local function AddDropdown(parent, labelText, items, getValue, setValue)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", parent, "LEFT")

    local dropdown
    dropdown = Widgets.CreateDropdown(parent, items, function(value)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local id = UI.ResolveSelectedTrackerId()
        if not id then
            return
        end
        setValue(id, value)
        dropdown:SetSelected(getValue(id))
    end)
    -- Explicit width from the cell (avoids LEFT+RIGHT fighting a leftover SetWidth from auto-sizing).
    dropdown:SetAutoWidth(false)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    dropdown:SetHeight(Sizes.CONTROL_HEIGHT)
    local function SyncDropdownWidth()
        local parentWidth = parent:GetWidth()
        if parentWidth <= 0 then
            return
        end
        local width = parentWidth - label:GetStringWidth() - Spacing.LARGE
        dropdown:SetWidth(math.max(width, Sizes.DROPDOWN_MIN_WIDTH))
    end
    parent:HookScript("OnSizeChanged", SyncDropdownWidth)
    SyncDropdownWidth()
    local trackerId = UI.ResolveSelectedTrackerId()
    if trackerId then
        dropdown:SetSelected(getValue(trackerId))
    end
    return dropdown
end

---Builds the texture dropdown into `parent`, stretching to the cell width.
---@param parent Frame
---@return Dropdown dropdown
local function AddTexture(parent)
    return AddDropdown(parent, L.AURA_TRACKER_TEXTURE, BuildTextureItems(), function(trackerId)
        return AuraTracker:GetTexture(trackerId)
    end, function(trackerId, textureId)
        AuraTracker:SetTexture(trackerId, textureId)
    end)
end

---@param slider Slider|nil
---@param trackerId integer
local function SyncSlider(slider, trackerId)
    if not slider or not slider._getValue then
        return
    end
    local value = slider._getValue(trackerId)
    slider:SetValue(value)
    if slider._valueLabel and slider._formatValue then
        slider._valueLabel:SetText(slider._formatValue(value))
    end
end

---Builds font / size / position controls shown while remaining time is enabled.
---@param content Frame
---@return number
local function BuildTimeContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local fontRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontCell, sizeCell = Layout.SplitRow(fontRow, Spacing.MEDIUM)
    UI.timeFontDropdown = AddDropdown(fontCell, L.AURA_TRACKER_TIME_FONT, BuildTimeFontItems(), function(trackerId)
        return AuraTracker:GetTimeFont(trackerId)
    end, function(trackerId, fontId)
        AuraTracker:SetTimeFont(trackerId, fontId)
    end)
    UI.fontSizeSlider = AddSlider(
        sizeCell,
        L.AURA_TRACKER_TIME_FONT_SIZE,
        AuraTracker.FONT_SIZE_MIN,
        AuraTracker.FONT_SIZE_MAX,
        AuraTracker.FONT_SIZE_STEP,
        function(trackerId)
            return AuraTracker:GetTimeFontSize(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetTimeFontSize(trackerId, value)
        end,
        function(value)
            return tostring(math.floor(value + 0.5))
        end
    )

    local positionRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local positionLabel = Widgets.CreateLabel(positionRow, Fonts.BODY, L.AURA_TRACKER_TIME_POSITION)
    positionLabel:SetJustifyH("LEFT")
    positionLabel:SetPoint("LEFT", positionRow, "LEFT")

    UI.timePositionHorizontal = Widgets.CreateSegmentedControl(positionRow, {
        { value = "left", text = L.AURA_TRACKER_TIME_POSITION_LEFT },
        { value = "center", text = L.AURA_TRACKER_TIME_POSITION_MIDDLE },
        { value = "right", text = L.AURA_TRACKER_TIME_POSITION_RIGHT },
    }, function(position)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId or not AuraTracker:GetShowTime(trackerId) then
            return
        end
        AuraTracker:SetTimePosition(trackerId, position)
        UI.timePositionHorizontal:SetSelected(AuraTracker:GetTimePosition(trackerId))
    end)
    UI.timePositionHorizontal:SetPoint("LEFT", positionLabel, "RIGHT", Spacing.LARGE, 0)

    UI.timePositionVertical = Widgets.CreateSegmentedControl(positionRow, {
        { value = "top", text = L.AURA_TRACKER_TIME_POSITION_TOP },
        { value = "center", text = L.AURA_TRACKER_TIME_POSITION_MIDDLE },
        { value = "bottom", text = L.AURA_TRACKER_TIME_POSITION_BOTTOM },
    }, function(position)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId or not AuraTracker:GetShowTime(trackerId) then
            return
        end
        AuraTracker:SetTimePosition(trackerId, position)
        UI.timePositionVertical:SetSelected(AuraTracker:GetTimePosition(trackerId))
    end)
    UI.timePositionVertical:SetPoint("LEFT", positionLabel, "RIGHT", Spacing.LARGE, 0)
    UI.RefreshTimePositionControls()

    return body:GetHeight()
end

---@param content Frame
---@return number
local function BuildBasicContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local spellRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local spellLabel = Widgets.CreateLabel(spellRow, Fonts.BODY, L.AURA_TRACKER_SPELL_ID)
    spellLabel:SetJustifyH("LEFT")
    spellLabel:EnableMouse(true)
    Widgets.AttachTooltip(spellLabel, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.AURA_TRACKER_SPELL_ID_TOOLTIP)
    end)
    UI.spellIdBox = Widgets.CreateNumberBox(spellRow, SPELL_ID_DIGITS)
    UI.spellIdBox:SetScript("OnEnterPressed", function(self)
        CommitSpellIdFromBox()
        self:ClearFocus()
    end)
    UI.spellIdBox:HookScript("OnEditFocusLost", function()
        CommitSpellIdFromBox()
    end)
    Widgets.AttachTooltip(UI.spellIdBox, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.AURA_TRACKER_SPELL_ID_TOOLTIP)
    end)
    Layout.Row(spellRow, { spellLabel, UI.spellIdBox }, Spacing.LARGE)

    local scopeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local scopeLabel = Widgets.CreateLabel(scopeRow, Fonts.BODY, L.AURA_TRACKER_ACTIVATION_SCOPE)
    scopeLabel:SetJustifyH("LEFT")
    scopeLabel:SetPoint("LEFT", scopeRow, "LEFT")
    UI.activationScopeControl = Widgets.CreateSegmentedControl(
        scopeRow,
        BuildActivationScopeItems(UI.ResolveSelectedTrackerId()),
        function(scope)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local trackerId = UI.ResolveSelectedTrackerId()
            if not trackerId then
                return
            end
            AssignActivationScope(trackerId, scope)
            RefreshActivationScopeControl()
        end
    )
    UI.activationScopeControl:SetPoint("LEFT", scopeLabel, "RIGHT", Spacing.LARGE, 0)
    local selectedId = UI.ResolveSelectedTrackerId()
    if selectedId then
        UI.activationScopeControl:SetSelected(AuraTracker:GetActivationScope(selectedId))
    end

    return body:GetHeight()
end

---@param content Frame
---@return number
local function BuildTrackingContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local modeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local modeCell, maxStacksCell = Layout.SplitRow(modeRow, Spacing.MEDIUM)
    UI.maxStacksCell = maxStacksCell
    local modeLabel = Widgets.CreateLabel(modeCell, Fonts.BODY, L.AURA_TRACKER_TRACKING_MODE)
    modeLabel:SetJustifyH("LEFT")
    modeLabel:SetPoint("LEFT", modeCell, "LEFT")
    UI.trackingModeControl = Widgets.CreateSegmentedControl(modeCell, {
        { value = AuraTracker.TRACKING_MODE_DURATION, text = L.AURA_TRACKER_MODE_DURATION },
        { value = AuraTracker.TRACKING_MODE_STACKS, text = L.AURA_TRACKER_MODE_STACKS },
    }, function(mode)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        AuraTracker:SetTrackingMode(trackerId, mode)
        UI.RefreshTrackingModeControls()
        UI.RelayoutSettings()
    end)
    UI.trackingModeControl:SetPoint("LEFT", modeLabel, "RIGHT", Spacing.LARGE, 0)

    local maxStacksLabel = Widgets.CreateLabel(maxStacksCell, Fonts.BODY, L.AURA_TRACKER_MAX_STACKS)
    maxStacksLabel:SetJustifyH("LEFT")
    UI.maxStacksBox = Widgets.CreateNumberBox(maxStacksCell, MAX_STACKS_DIGITS)
    UI.maxStacksBox:SetScript("OnEnterPressed", function(self)
        CommitMaxStacksFromBox()
        self:ClearFocus()
    end)
    UI.maxStacksBox:HookScript("OnEditFocusLost", function()
        CommitMaxStacksFromBox()
    end)
    Layout.Row(maxStacksCell, { maxStacksLabel, UI.maxStacksBox }, Spacing.LARGE)

    return body:GetHeight()
end

---@param content Frame
---@return number
local function BuildAppearanceContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local sizeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local widthCell, heightCell = Layout.SplitRow(sizeRow, Spacing.MEDIUM)
    UI.widthSlider = AddSlider(
        widthCell,
        L.AURA_TRACKER_WIDTH,
        AuraTracker.WIDTH_MIN,
        AuraTracker.WIDTH_MAX,
        AuraTracker.WIDTH_STEP,
        function(trackerId)
            return AuraTracker:GetWidth(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetWidth(trackerId, value)
        end,
        function(value)
            return tostring(math.floor(value + 0.5))
        end
    )
    UI.heightSlider = AddSlider(
        heightCell,
        L.AURA_TRACKER_HEIGHT,
        AuraTracker.HEIGHT_MIN,
        AuraTracker.HEIGHT_MAX,
        AuraTracker.HEIGHT_STEP,
        function(trackerId)
            return AuraTracker:GetHeight(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetHeight(trackerId, value)
        end,
        function(value)
            return tostring(math.floor(value + 0.5))
        end
    )

    local fillTextureRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fillCell, textureCell = Layout.SplitRow(fillTextureRow, Spacing.MEDIUM)
    UI.fillSwatch = AddColor(fillCell, L.AURA_TRACKER_FILL_COLOR, function(trackerId)
        return AuraTracker:GetFillColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetFillColor(trackerId, color)
    end)
    UI.textureDropdown = AddTexture(textureCell)

    local backgroundRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local backgroundCell, opacityCell = Layout.SplitRow(backgroundRow, Spacing.MEDIUM)
    UI.backgroundSwatch = AddColor(backgroundCell, L.AURA_TRACKER_BACKGROUND_COLOR, function(trackerId)
        return AuraTracker:GetBackgroundColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetBackgroundColor(trackerId, color)
    end)
    UI.opacitySlider = AddSlider(
        opacityCell,
        L.AURA_TRACKER_BACKGROUND_OPACITY,
        AuraTracker.OPACITY_MIN,
        AuraTracker.OPACITY_MAX,
        AuraTracker.OPACITY_STEP,
        function(trackerId)
            return AuraTracker:GetBackgroundOpacity(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetBackgroundOpacity(trackerId, value)
        end,
        function(value)
            return string.format("%d%%", math.floor(value * 100 + 0.5))
        end
    )

    local fillToggleRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    local reverseCell, verticalCell = Layout.SplitRow(fillToggleRow, Spacing.MEDIUM)
    UI.reverseCheckbox = AddCheckbox(reverseCell, L.AURA_TRACKER_REVERSE_FILL, function(trackerId)
        return AuraTracker:GetReverseFill(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetReverseFill(trackerId, checked)
    end)
    UI.verticalCheckbox = AddCheckbox(verticalCell, L.AURA_TRACKER_VERTICAL, function(trackerId)
        return AuraTracker:GetVertical(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetVertical(trackerId, checked)
        UI.RefreshTimePositionControls()
        UI.RefreshSizeLabels()
    end)

    return body:GetHeight()
end

---@param content Frame
---@return number
local function BuildBorderContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local borderRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    local borderCell, dividerCell = Layout.SplitRow(borderRow, Spacing.MEDIUM)
    UI.stackDividerCell = dividerCell
    UI.borderCheckbox = AddCheckbox(borderCell, L.AURA_TRACKER_BORDER, function(trackerId)
        return AuraTracker:GetShowBorder(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetShowBorder(trackerId, checked)
    end)
    UI.stackDividerCheckbox = AddCheckbox(dividerCell, L.AURA_TRACKER_STACK_DIVIDERS, function(trackerId)
        return AuraTracker:GetShowStackDividers(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetShowStackDividers(trackerId, checked)
    end)

    local lineRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local colorCell, thicknessCell = Layout.SplitRow(lineRow, Spacing.MEDIUM)
    UI.lineSwatch = AddColor(colorCell, L.AURA_TRACKER_LINE_COLOR, function(trackerId)
        return AuraTracker:GetLineColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetLineColor(trackerId, color)
    end)
    UI.lineThicknessSlider = AddSlider(
        thicknessCell,
        L.AURA_TRACKER_LINE_THICKNESS,
        AuraTracker.LINE_THICKNESS_MIN,
        AuraTracker.LINE_THICKNESS_MAX,
        AuraTracker.LINE_THICKNESS_STEP,
        function(trackerId)
            return AuraTracker:GetLineThickness(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetLineThickness(trackerId, value)
        end,
        function(value)
            return tostring(math.floor(value + 0.5))
        end
    )

    return body:GetHeight()
end

---@param content Frame
---@return number
local function BuildValueContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })
    UI.valueBody = body

    -- Subfeature: value text (remaining time or stacks); font/size/position dim when off.
    UI.timeSection = FeatureSection.Create(body, {
        title = L.AURA_TRACKER_SHOW_VALUE,
        enabled = false,
        onStackHeightChanged = function()
            RelayoutValueSection()
            UI.RelayoutSettings()
        end,
        onEnabledChanged = function(enabled)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local trackerId = UI.ResolveSelectedTrackerId()
            if trackerId then
                AuraTracker:SetShowTime(trackerId, enabled)
            end
        end,
    })
    UI.timeSection:SetContentHeight(BuildTimeContent(UI.timeSection.content))
    UI.timeSection:RefreshContentInteractive()

    return body:GetHeight()
end

---@param content Frame
---@return number
function UI.BuildEditorContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })
    UI.editorStack = body

    local function OnEditorHeightChanged()
        UI.RelayoutSettings()
    end

    -- Panel title for the selected aura; not another list-style selectable row.
    local header = body:Add(CreateFrame("Frame", nil, content), EDITOR_HEADER_HEIGHT)

    UI.editorSpellIcon = header:CreateTexture(nil, "ARTWORK")
    UI.editorSpellIcon:SetSize(EDITOR_HEADER_ICON_SIZE, EDITOR_HEADER_ICON_SIZE)
    UI.editorSpellIcon:SetPoint("TOPLEFT", header, "TOPLEFT")
    UI.ApplySpellIcon(UI.editorSpellIcon, 0)

    UI.editorNameLabel = Widgets.CreateLabel(header, Fonts.TITLE, L.AURA_TRACKER_UNTITLED)
    UI.editorNameLabel:SetJustifyH("LEFT")
    UI.editorNameLabel:SetWordWrap(false)
    UI.editorNameLabel:SetPoint("TOPLEFT", UI.editorSpellIcon, "TOPRIGHT", Spacing.SMALL, 0)
    UI.editorNameLabel:SetHeight(EDITOR_HEADER_TITLE_HEIGHT)

    local deleteButton = Widgets.CreateTextButton(header, L.AURA_TRACKER_DELETE, function()
        if not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        UI.PromptDeleteTracker(trackerId)
    end, Fonts.LINK_DANGER)
    deleteButton:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -(EDITOR_HEADER_TITLE_HEIGHT - Sizes.CONTROL_HEIGHT) / 2)

    -- No dedicated copy icon in shared widgets; match Delete as a compact text action.
    local duplicateButton = Widgets.CreateTextButton(header, L.AURA_TRACKER_DUPLICATE, function()
        if not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        local newId = AuraTracker:DuplicateTracker(trackerId)
        UI.selectedTrackerId = newId
        UI.RefreshTrackerList()
        UI.RefreshSelectedEditor()
    end)
    duplicateButton:SetPoint("RIGHT", deleteButton, "LEFT", -Spacing.MEDIUM, 0)
    UI.editorNameLabel:SetPoint("RIGHT", duplicateButton, "LEFT", -Spacing.MEDIUM, 0)

    UI.editorSubtitleLabel = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, "")
    UI.editorSubtitleLabel:SetJustifyH("LEFT")
    UI.editorSubtitleLabel:SetWordWrap(false)
    UI.editorSubtitleLabel:SetPoint("TOPLEFT", UI.editorNameLabel, "BOTTOMLEFT")
    UI.editorSubtitleLabel:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    UI.editorSubtitleLabel:SetHeight(EDITOR_HEADER_SUBTITLE_HEIGHT)

    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(Sizes.BORDER)
    divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    UI.basicSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BASIC,
        expanded = UI.editorBasicExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorBasicExpanded = expanded
        end,
    })
    UI.basicSection:SetContentHeight(BuildBasicContent(UI.basicSection.content))

    UI.trackingSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_TRACKING,
        expanded = UI.editorTrackingExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorTrackingExpanded = expanded
        end,
    })
    UI.trackingSection:SetContentHeight(BuildTrackingContent(UI.trackingSection.content))

    UI.appearanceSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BAR_APPEARANCE,
        expanded = UI.editorAppearanceExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorAppearanceExpanded = expanded
        end,
    })
    UI.appearanceSection:SetContentHeight(BuildAppearanceContent(UI.appearanceSection.content))

    UI.borderSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BORDER,
        expanded = UI.editorBorderExpanded == true,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorBorderExpanded = expanded
        end,
    })
    UI.borderSection:SetContentHeight(BuildBorderContent(UI.borderSection.content))

    UI.valueSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_VALUE,
        expanded = UI.editorValueExpanded == true,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorValueExpanded = expanded
        end,
    })
    UI.valueSection:SetContentHeight(BuildValueContent(UI.valueSection.content))

    UI.RefreshTrackingModeControls()

    return body:GetHeight()
end

function UI.RefreshSelectedEditor()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        UI.RelayoutSettings()
        return
    end

    if not UI.editorBuilt then
        UI.BuildEditorContent(UI.editorHost)
        UI.editorBuilt = true
    end

    UI.refreshingControls = true

    UI.RefreshEditorHeader(trackerId)
    if UI.spellIdBox then
        local spellId = AuraTracker:GetSpellId(trackerId)
        UI.spellIdBox:SetText(spellId > 0 and tostring(spellId) or "")
    end
    RefreshActivationScopeControl()
    if UI.fillSwatch then
        UI.fillSwatch:SetColor(AuraTracker:GetFillColor(trackerId))
    end
    if UI.backgroundSwatch then
        UI.backgroundSwatch:SetColor(AuraTracker:GetBackgroundColor(trackerId))
    end
    if UI.lineSwatch then
        UI.lineSwatch:SetColor(AuraTracker:GetLineColor(trackerId))
    end
    if UI.textureDropdown then
        UI.textureDropdown:SetSelected(AuraTracker:GetTexture(trackerId))
    end
    if UI.timeFontDropdown then
        UI.timeFontDropdown:SetSelected(AuraTracker:GetTimeFont(trackerId))
    end
    SyncSlider(UI.widthSlider, trackerId)
    SyncSlider(UI.heightSlider, trackerId)
    SyncSlider(UI.opacitySlider, trackerId)
    SyncSlider(UI.lineThicknessSlider, trackerId)
    SyncSlider(UI.fontSizeSlider, trackerId)
    if UI.reverseCheckbox then
        UI.reverseCheckbox:SetChecked(AuraTracker:GetReverseFill(trackerId))
    end
    if UI.verticalCheckbox then
        UI.verticalCheckbox:SetChecked(AuraTracker:GetVertical(trackerId))
    end
    if UI.borderCheckbox then
        UI.borderCheckbox:SetChecked(AuraTracker:GetShowBorder(trackerId))
    end
    if UI.stackDividerCheckbox then
        UI.stackDividerCheckbox:SetChecked(AuraTracker:GetShowStackDividers(trackerId))
    end
    if UI.timeSection then
        UI.timeSection:SetEnabled(AuraTracker:GetShowTime(trackerId))
    end
    UI.RefreshTrackingModeControls()
    UI.RefreshTimePositionControls()
    UI.RefreshSizeLabels()

    UI.refreshingControls = false
    UI.RelayoutSettings()
end
