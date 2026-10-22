local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets
local Schema = Internals.Schema

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

local MAX_STACKS_DIGITS = 3

---@class AuraTrackerUI
local UI = Internals.UI

local function CommitMaxStacksFromBox()
    if UI.refreshingControls or not UI.maxStacksBox then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local raw = UI.maxStacksBox:GetNumber()
    local maxStacks = (type(raw) == "number" and raw > 0) and math.floor(raw) or Schema.MAX_STACKS_MIN
    AuraTracker:SetMaxStacks(trackerId, maxStacks)
    UI.maxStacksBox:SetText(tostring(AuraTracker:GetMaxStacks(trackerId)))
end

function UI.RefreshTrackingModeControls()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local stacksMode = AuraTracker:IsStacksMode(trackerId)
    if UI.trackingModeControl then
        UI.trackingModeControl:SetSelected(AuraTracker:GetProgressMode(trackerId))
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

---@param content Frame
---@return number
function UI.BuildTrackingSection(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local modeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local modeCell, maxStacksCell = Layout.SplitRow(modeRow, Spacing.MEDIUM)
    UI.maxStacksCell = maxStacksCell
    local modeLabel = Widgets.CreateLabel(modeCell, Fonts.BODY, L.AURA_TRACKER_TRACKING_MODE)
    modeLabel:SetJustifyH("LEFT")
    modeLabel:SetPoint("LEFT", modeCell, "LEFT")
    UI.Controls.AttachPendingClock(modeLabel, "progressMode")
    UI.trackingModeControl = Widgets.CreateSegmentedControl(modeCell, {
        { value = Schema.PROGRESS_MODE_DURATION, text = L.AURA_TRACKER_MODE_DURATION },
        { value = Schema.PROGRESS_MODE_STACKS, text = L.AURA_TRACKER_MODE_STACKS },
    }, function(mode)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        AuraTracker:SetProgressMode(trackerId, mode)
        UI.RefreshTrackingModeControls()
        UI.RelayoutSettings()
    end)
    UI.trackingModeControl:SetPoint("LEFT", modeLabel, "RIGHT", Spacing.LARGE, 0)

    local maxStacksLabel = Widgets.CreateLabel(maxStacksCell, Fonts.BODY, L.AURA_TRACKER_MAX_STACKS)
    maxStacksLabel:SetJustifyH("LEFT")
    UI.Controls.AttachPendingClock(maxStacksLabel, "maxStacks")
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
