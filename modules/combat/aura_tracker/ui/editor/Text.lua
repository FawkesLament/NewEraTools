local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CollapsibleSection = ns.CollapsibleSection
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Media = ns.AuraTrackerMedia
local Schema = ns.AuraTrackerSchema

local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

local Controls = UI.Controls

---@class AuraTrackerTextDisplayEditor
---@field kind string
---@field collapsible CollapsibleSection
---@field feature FeatureSection
---@field fontDropdown Dropdown
---@field fontSizeSlider Slider
---@field offsetXStepper NumberStepper
---@field offsetYStepper NumberStepper

---@type table<string, AuraTrackerTextDisplayEditor>
local textDisplayEditors = {}

---@return DropdownItem[]
local function BuildTextFontItems()
    local items = {}
    for _, fontId in ipairs(Media.ListTimeFontIds()) do
        items[#items + 1] = {
            value = fontId,
            text = fontId == Schema.TEXT_FONT_DEFAULT and L.AURA_TRACKER_TEXT_FONT_DEFAULT or fontId,
        }
    end
    return items
end

function UI.RefreshTextFontDropdowns()
    local items = BuildTextFontItems()
    local trackerId = UI.ResolveSelectedTrackerId()
    for _, editor in pairs(textDisplayEditors) do
        if editor.fontDropdown then
            editor.fontDropdown:SetItems(items)
            if trackerId then
                editor.fontDropdown:SetSelected(AuraTracker:GetTextDisplayFont(trackerId, editor.kind))
            end
        end
    end
end

function UI.RefreshTextDisplayControls()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    for _, editor in pairs(textDisplayEditors) do
        if editor.feature then
            editor.feature:SetEnabled(AuraTracker:IsTextDisplayEnabled(trackerId, editor.kind))
        end
        if editor.fontDropdown then
            editor.fontDropdown:SetSelected(AuraTracker:GetTextDisplayFont(trackerId, editor.kind))
        end
        Controls.SyncSlider(editor.fontSizeSlider, trackerId)
        Controls.SyncOffsetStepper(editor.offsetXStepper, trackerId)
        Controls.SyncOffsetStepper(editor.offsetYStepper, trackerId)
    end
end

---Font / size / position controls for one text kind; greyed out while the FeatureSection is off.
---@param content Frame
---@param editor AuraTrackerTextDisplayEditor
---@return number
local function BuildTextDisplayStyleContent(content, editor)
    local kind = editor.kind
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local fontRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontCell, sizeCell = Layout.SplitRow(fontRow, Spacing.MEDIUM)
    editor.fontDropdown = Controls.AddDropdown(
        fontCell,
        L.AURA_TRACKER_TEXT_FONT,
        BuildTextFontItems(),
        function(trackerId)
            return AuraTracker:GetTextDisplayFont(trackerId, kind)
        end,
        function(trackerId, fontId)
            AuraTracker:SetTextDisplayFont(trackerId, kind, fontId)
        end,
        "text." .. kind .. ".font"
    )
    editor.fontSizeSlider = Controls.AddSlider(
        sizeCell,
        L.AURA_TRACKER_TEXT_FONT_SIZE,
        Schema.FONT_SIZE_MIN,
        Schema.FONT_SIZE_MAX,
        Schema.FONT_SIZE_STEP,
        function(trackerId)
            return AuraTracker:GetTextDisplayFontSize(trackerId, kind)
        end,
        function(trackerId, value)
            AuraTracker:SetTextDisplayFontSize(trackerId, kind, value)
        end,
        nil,
        "text." .. kind .. ".fontSize"
    )

    local offsetRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local offsetXCell, offsetYCell = Layout.SplitRow(offsetRow, Spacing.MEDIUM)
    editor.offsetXStepper = Controls.AddOffsetStepper(offsetXCell, L.AURA_TRACKER_TEXT_OFFSET_X, function(trackerId)
        return AuraTracker:GetTextDisplayOffsetX(trackerId, kind)
    end, function(trackerId, value)
        AuraTracker:SetTextDisplayOffsetX(trackerId, kind, value)
    end, "text." .. kind .. ".offsetX")
    editor.offsetYStepper = Controls.AddOffsetStepper(offsetYCell, L.AURA_TRACKER_TEXT_OFFSET_Y, function(trackerId)
        return AuraTracker:GetTextDisplayOffsetY(trackerId, kind)
    end, function(trackerId, value)
        AuraTracker:SetTextDisplayOffsetY(trackerId, kind, value)
    end, "text." .. kind .. ".offsetY")

    return body:GetHeight()
end

---Collapsible section with a Show FeatureSection and shared style controls for one text kind.
---@param parentStack LayoutStack
---@param title string
---@param kind string
---@param expandedKey string
---@param onEditorHeightChanged fun()
---@return AuraTrackerTextDisplayEditor
local function CreateTextDisplaySection(parentStack, title, kind, expandedKey, onEditorHeightChanged)
    ---@type AuraTrackerTextDisplayEditor
    local editor = { kind = kind }
    textDisplayEditors[kind] = editor

    editor.collapsible = CollapsibleSection.Create(parentStack, {
        title = title,
        expanded = UI[expandedKey] == true,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = onEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI[expandedKey] = expanded
        end,
    })

    local body = Layout.Stack(editor.collapsible.content, { spacing = Spacing.SMALL })
    local selectedId = UI.ResolveSelectedTrackerId()
    editor.feature = FeatureSection.Create(body, {
        title = L.AURA_TRACKER_TEXT_SHOW,
        enabled = selectedId ~= nil and AuraTracker:IsTextDisplayEnabled(selectedId, kind) or false,
        onStackHeightChanged = function()
            editor.collapsible:SetContentHeight(body:GetHeight())
            onEditorHeightChanged()
        end,
        onEnabledChanged = function(enabled)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local trackerId = UI.ResolveSelectedTrackerId()
            if trackerId then
                AuraTracker:SetTextDisplayEnabled(trackerId, kind, enabled)
            end
        end,
    })
    editor.feature:SetContentHeight(BuildTextDisplayStyleContent(editor.feature.content, editor))
    if editor.feature.titleLabel then
        Controls.AttachPendingClock(editor.feature.titleLabel, "text." .. kind .. ".enabled")
    end
    editor.feature:RefreshContentInteractive()
    editor.collapsible:SetContentHeight(body:GetHeight())
    return editor
end

---@param parentStack LayoutStack
---@param onEditorHeightChanged fun()
function UI.BuildTextSections(parentStack, onEditorHeightChanged)
    CreateTextDisplaySection(
        parentStack,
        L.AURA_TRACKER_SECTION_DURATION_TEXT,
        Schema.TEXT_DURATION,
        "editorDurationTextExpanded",
        onEditorHeightChanged
    )
    CreateTextDisplaySection(
        parentStack,
        L.AURA_TRACKER_SECTION_STACKS_TEXT,
        Schema.TEXT_STACKS,
        "editorStacksTextExpanded",
        onEditorHeightChanged
    )
end
