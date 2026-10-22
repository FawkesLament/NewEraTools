local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Schema = Internals.Schema

local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

---@class AuraTrackerUI
local UI = Internals.UI

local Controls = UI.Controls

---@param content Frame
---@return number
function UI.BuildBorderSection(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local borderRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    local borderCell, dividerCell = Layout.SplitRow(borderRow, Spacing.MEDIUM)
    UI.stackDividerCell = dividerCell
    UI.borderCheckbox = Controls.AddCheckbox(borderCell, L.AURA_TRACKER_BORDER, function(trackerId)
        return AuraTracker:GetShowBorder(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetShowBorder(trackerId, checked)
    end, "showBorder")
    UI.stackDividerCheckbox = Controls.AddCheckbox(dividerCell, L.AURA_TRACKER_STACK_DIVIDERS, function(trackerId)
        return AuraTracker:GetShowStackDividers(trackerId)
    end, function(trackerId, checked)
        AuraTracker:SetShowStackDividers(trackerId, checked)
    end, "showStackDividers")

    local lineRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local colorCell, thicknessCell = Layout.SplitRow(lineRow, Spacing.MEDIUM)
    UI.lineSwatch = Controls.AddColor(colorCell, L.AURA_TRACKER_LINE_COLOR, function(trackerId)
        return AuraTracker:GetLineColor(trackerId)
    end, function(trackerId, color)
        AuraTracker:SetLineColor(trackerId, color)
    end, "lineColor")
    UI.lineThicknessSlider = Controls.AddSlider(
        thicknessCell,
        L.AURA_TRACKER_LINE_THICKNESS,
        Schema.LINE_THICKNESS_MIN,
        Schema.LINE_THICKNESS_MAX,
        Schema.LINE_THICKNESS_STEP,
        function(trackerId)
            return AuraTracker:GetLineThickness(trackerId)
        end,
        function(trackerId, value)
            AuraTracker:SetLineThickness(trackerId, value)
        end,
        nil,
        "lineThickness"
    )

    return body:GetHeight()
end
