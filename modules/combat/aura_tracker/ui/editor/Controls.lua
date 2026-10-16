local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets
local Schema = ns.AuraTrackerSchema

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

---@class AuraTrackerEditorControls
local Controls = {}
UI.Controls = Controls

local PENDING_CLOCK_SIZE = 10

---Small clock just after a label. Hidden until that saved field is waiting on the live bar.
---The gap before the control is Spacing.LARGE, so the icon sits in that gap without moving the row.
---@param label FontString
---@param key string
function Controls.AttachPendingClock(label, key)
    local clock = CreateFrame("Frame", nil, label:GetParent())
    clock:SetSize(PENDING_CLOCK_SIZE, PENDING_CLOCK_SIZE)
    clock:SetPoint("LEFT", label, "RIGHT", 1, 0)
    clock:EnableMouse(true)
    local icon = clock:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas(Assets.Icons.CLOCK)
    local muted = Assets.Colors.TEXT_MUTED
    icon:SetVertexColor(muted.r, muted.g, muted.b, 1)
    Widgets.AttachTooltip(clock, "ANCHOR_RIGHT", function(tooltip)
        tooltip:SetText(L.AURA_TRACKER_PENDING_FIELD)
    end)
    clock:Hide()
    UI.pendingClocks = UI.pendingClocks or {}
    UI.pendingClocks[key] = clock
end

---Builds a labeled slider into `parent` (a full row or a SplitRow cell).
---@param parent Frame
---@param labelText string
---@param min number
---@param max number
---@param step number
---@param getValue fun(trackerId: integer): number
---@param setValue fun(trackerId: integer, value: number)
---@param percentage boolean|nil  When true, the value box shows percent units with a "%" suffix.
---@param pendingKey string|nil  Shown with a clock while this field is waiting to reach the live bar.
---@return Slider
function Controls.AddSlider(parent, labelText, min, max, step, getValue, setValue, percentage, pendingKey)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    if pendingKey then
        Controls.AttachPendingClock(label, pendingKey)
    end
    local slider = Widgets.CreateSlider(parent, min, max, step, {
        percentage = percentage,
    })
    local trackerId = UI.ResolveSelectedTrackerId()
    local initial = trackerId and getValue(trackerId) or min
    slider:SetValue(initial)
    slider:SetScript("OnValueChanged", function(_, rawValue)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local id = UI.ResolveSelectedTrackerId()
        if not id then
            return
        end
        setValue(id, rawValue)
    end)
    slider._label = label
    slider._getValue = getValue
    Layout.Row(parent, { label }, 0)
    slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    return slider
end

---Builds a labeled checkbox into `parent`.
---@param parent Frame
---@param text string
---@param getChecked fun(trackerId: integer): boolean
---@param setChecked fun(trackerId: integer, checked: boolean)
---@param pendingKey string|nil
---@return CheckButton
function Controls.AddCheckbox(parent, text, getChecked, setChecked, pendingKey)
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
    if pendingKey then
        Controls.AttachPendingClock(label, pendingKey)
    end
    Layout.Row(parent, { box, label }, Spacing.SMALL)
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    return box
end

---Builds a labeled color swatch into `parent`.
---@param parent Frame
---@param labelText string
---@param getColor fun(trackerId: integer): AuraTrackerColor
---@param setColor fun(trackerId: integer, color: AuraTrackerColor)
---@param pendingKey string|nil
---@return ColorSwatch swatch
function Controls.AddColor(parent, labelText, getColor, setColor, pendingKey)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    if pendingKey then
        Controls.AttachPendingClock(label, pendingKey)
    end
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
---@param pendingKey string|nil
---@return Dropdown dropdown
function Controls.AddDropdown(parent, labelText, items, getValue, setValue, pendingKey)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", parent, "LEFT")
    if pendingKey then
        Controls.AttachPendingClock(label, pendingKey)
    end

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

---@param parent Frame
---@param labelText string
---@param items SegmentedControlItem[]
---@param onSelect fun(value: any)
---@return SegmentedControl
function Controls.AddSegmentedRow(parent, labelText, items, onSelect)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", parent, "LEFT")
    local control = Widgets.CreateSegmentedControl(parent, items, onSelect)
    control:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
    return control
end

---Labeled [-] number [+] for one text offset.
---@param parent Frame
---@param labelText string
---@param getValue fun(trackerId: integer): number
---@param setValue fun(trackerId: integer, value: number)
---@param pendingKey string|nil
---@return NumberStepper
function Controls.AddOffsetStepper(parent, labelText, getValue, setValue, pendingKey)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    if pendingKey then
        Controls.AttachPendingClock(label, pendingKey)
    end
    -- Declared first so the commit callback closes over this local. A `local stepper =`
    -- on the CreateNumberStepper call would still see a global here.
    local stepper
    stepper = Widgets.CreateNumberStepper(
        parent,
        Schema.TEXT_OFFSET_MIN,
        Schema.TEXT_OFFSET_MAX,
        Schema.TEXT_OFFSET_STEP,
        function(value)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local id = UI.ResolveSelectedTrackerId()
            if not id then
                return
            end
            setValue(id, value)
            stepper:SetValue(getValue(id))
        end
    )
    local trackerId = UI.ResolveSelectedTrackerId()
    stepper:SetValue(trackerId and getValue(trackerId) or 0)
    stepper._getValue = getValue
    Layout.Row(parent, { label, stepper }, Spacing.LARGE)
    return stepper
end

---@param slider Slider|nil
---@param trackerId integer
function Controls.SyncSlider(slider, trackerId)
    if not slider or not slider._getValue then
        return
    end
    slider:SetValue(slider._getValue(trackerId))
end

---@param stepper NumberStepper|nil
---@param trackerId integer
function Controls.SyncOffsetStepper(stepper, trackerId)
    if not stepper or not stepper._getValue then
        return
    end
    stepper:SetValue(stepper._getValue(trackerId))
end
