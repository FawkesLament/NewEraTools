local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Media = ns.AuraTrackerMedia
local Schema = ns.AuraTrackerSchema

local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

local TEXTURE_LABELS = {
    flat = L.AURA_TRACKER_TEXTURE_FLAT,
    default = L.AURA_TRACKER_TEXTURE_DEFAULT,
    raid = L.AURA_TRACKER_TEXTURE_RAID,
}

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

local Controls = UI.Controls

---@return DropdownItem[]
local function BuildTextureItems()
    local items = {}
    for _, textureId in ipairs(Media.ListTextureIds()) do
        items[#items + 1] = {
            value = textureId,
            text = TEXTURE_LABELS[textureId] or textureId,
        }
    end
    return items
end

function UI.RefreshTextureDropdown()
    if not UI.textureDropdown then
        return
    end
    UI.textureDropdown:SetItems(BuildTextureItems())
    local trackerId = UI.ResolveSelectedTrackerId()
    if trackerId then
        UI.textureDropdown:SetSelected(AuraTracker:GetTexture(trackerId))
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

---Builds the texture dropdown into `parent`, stretching to the cell width.
---@param parent Frame
---@return Dropdown dropdown
local function AddTexture(parent)
    return Controls.AddDropdown(parent, L.AURA_TRACKER_TEXTURE, BuildTextureItems(), function(trackerId)
        return AuraTracker:GetTexture(trackerId)
    end, function(trackerId, textureId)
        AuraTracker:SetTexture(trackerId, textureId)
    end, "texture")
end

---@param content Frame
---@return number
function UI.BuildAppearanceSection(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local sizeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local widthCell, heightCell = Layout.SplitRow(sizeRow, Spacing.MEDIUM)
    UI.widthSlider = Controls.AddSlider(
        widthCell,
        L.AURA_TRACKER_WIDTH,
        Schema.WIDTH_MIN,
        Schema.WIDTH_MAX,
        Schema.WIDTH_STEP,
        function(trackerId)
            return AuraTracker:GetWidth(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetWidth(trackerId, value)
        end,
        nil,
        "width"
    )
    UI.heightSlider = Controls.AddSlider(
        heightCell,
        L.AURA_TRACKER_HEIGHT,
        Schema.HEIGHT_MIN,
        Schema.HEIGHT_MAX,
        Schema.HEIGHT_STEP,
        function(trackerId)
            return AuraTracker:GetHeight(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetHeight(trackerId, value)
        end,
        nil,
        "height"
    )

    local fillTextureRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fillCell, textureCell = Layout.SplitRow(fillTextureRow, Spacing.MEDIUM)
    UI.fillSwatch = Controls.AddColor(fillCell, L.AURA_TRACKER_FILL_COLOR, function(trackerId)
        return AuraTracker:GetFillColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetFillColor(trackerId, color)
    end, "fillColor")
    UI.textureDropdown = AddTexture(textureCell)

    local backgroundRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local backgroundCell, opacityCell = Layout.SplitRow(backgroundRow, Spacing.MEDIUM)
    UI.backgroundSwatch = Controls.AddColor(backgroundCell, L.AURA_TRACKER_BACKGROUND_COLOR, function(trackerId)
        return AuraTracker:GetBackgroundColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetBackgroundColor(trackerId, color)
    end, "backgroundColor")
    UI.opacitySlider = Controls.AddSlider(
        opacityCell,
        L.AURA_TRACKER_BACKGROUND_OPACITY,
        Schema.OPACITY_MIN,
        Schema.OPACITY_MAX,
        Schema.OPACITY_STEP,
        function(trackerId)
            return AuraTracker:GetBackgroundOpacity(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetBackgroundOpacity(trackerId, value)
        end,
        true,
        "backgroundOpacity"
    )

    local fillToggleRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    local reverseCell, verticalCell = Layout.SplitRow(fillToggleRow, Spacing.MEDIUM)
    UI.reverseCheckbox = Controls.AddCheckbox(reverseCell, L.AURA_TRACKER_REVERSE_FILL, function(trackerId)
        return AuraTracker:GetReverseFill(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetReverseFill(trackerId, checked)
    end, "reverseFill")
    UI.verticalCheckbox = Controls.AddCheckbox(verticalCell, L.AURA_TRACKER_VERTICAL, function(trackerId)
        return AuraTracker:GetVertical(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetVertical(trackerId, checked)
        UI.RefreshTextDisplayControls()
        UI.RefreshSizeLabels()
    end, "vertical")

    return body:GetHeight()
end
