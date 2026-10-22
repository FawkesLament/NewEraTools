local _, ns = ...
local Assets = ns.Assets
local Util = ns.Util
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local NumberStepper = {}
ns.NumberStepper = NumberStepper

---@class NumberStepper: Frame
---@field SetValue fun(self: NumberStepper, value: number)  Shows the clamped value; a button is disabled at its limit.
---@field SetIncreaseLimit fun(self: NumberStepper, limit: number)  Disables + below `max` without clamping the value.
---@field SetEnabled fun(self: NumberStepper, enabled: boolean)
---@field IsEnabled fun(self: NumberStepper): boolean

---[-] number box [+] for an integer range. Buttons step by `step`; typed values clamp on commit.
---@param parent Frame
---@param minValue number
---@param maxValue number
---@param step number
---@param onValueChanged fun(value: number)  After a button or a committed edit changes the value.
---@return NumberStepper
function NumberStepper.Create(parent, minValue, maxValue, step, onValueChanged)
    local stepper = CreateFrame("Frame", nil, parent) --[[@as NumberStepper]]
    local maxAbs = math.max(math.abs(minValue), math.abs(maxValue))
    local maxDigits = maxAbs < 1 and 1 or (math.floor(math.log10(maxAbs)) + 1)
    local box = Widgets.CreateNumberBox(stepper, maxDigits, { signed = minValue < 0 })
    local current = Util.Snap(minValue, minValue, maxValue, step)
    local enabled = true
    -- Optional cap tighter than `maxValue`. The value may sit above it (for example a saved draw
    -- count while the eligible pool is still loading); only the + button stops there.
    local increaseLimit = maxValue

    local function Format(value)
        return tostring(math.floor(value + 0.5))
    end

    local decrease = Widgets.CreateFlatButton(stepper, "secondary", function()
        stepper:Commit(current - step)
    end)
    decrease:SetText(Assets.Glyphs.DECREASE)
    decrease:SetNormalFontObject(Fonts.STEPPER)
    decrease:SetDisabledFontObject(Fonts.STEPPER)
    decrease:SetSize(Sizes.INPUT_HEIGHT, Sizes.INPUT_HEIGHT)
    decrease:SetPoint("LEFT")

    local increase = Widgets.CreateFlatButton(stepper, "secondary", function()
        stepper:Commit(current + step)
    end)
    increase:SetText(Assets.Glyphs.INCREASE)
    increase:SetNormalFontObject(Fonts.STEPPER)
    increase:SetDisabledFontObject(Fonts.STEPPER)
    increase:SetSize(Sizes.INPUT_HEIGHT, Sizes.INPUT_HEIGHT)

    box:SetPoint("LEFT", decrease, "RIGHT", Spacing.TINY, 0)
    increase:SetPoint("LEFT", box, "RIGHT", Spacing.TINY, 0)
    stepper:SetSize(Sizes.INPUT_HEIGHT * 2 + box:GetWidth() + Spacing.TINY * 2, Sizes.INPUT_HEIGHT)

    -- FeatureSection re-enables every child; keep a button disabled when the value is at its limit.
    local rawDecreaseSetEnabled = decrease.SetEnabled
    function decrease:SetEnabled(value)
        rawDecreaseSetEnabled(self, value == true and enabled and current > minValue)
    end
    local rawIncreaseSetEnabled = increase.SetEnabled
    function increase:SetEnabled(value)
        rawIncreaseSetEnabled(self, value == true and enabled and current < maxValue and current < increaseLimit)
    end
    local rawBoxSetEnabled = box.SetEnabled
    function box:SetEnabled(value)
        rawBoxSetEnabled(self, value == true and enabled)
    end

    local function Show(value)
        current = Util.Snap(value, minValue, maxValue, step)
        box:SetText(Format(current))
        decrease:SetEnabled(true)
        increase:SetEnabled(true)
    end

    ---@param value number
    function stepper:Commit(value)
        local nextValue = Util.Snap(value, minValue, maxValue, step)
        local changed = nextValue ~= current
        Show(nextValue)
        if changed then
            onValueChanged(current)
        end
    end

    function stepper:SetValue(value)
        Show(value)
    end

    function stepper:SetIncreaseLimit(limit)
        increaseLimit = limit
        increase:SetEnabled(true)
    end

    function stepper:SetEnabled(value)
        enabled = value == true
        box:SetEnabled(true)
        decrease:SetEnabled(true)
        increase:SetEnabled(true)
    end

    function stepper:IsEnabled()
        return enabled
    end

    box:HookScript("OnEnterPressed", function(self)
        local parsed = tonumber(self:GetText())
        if parsed == nil then
            Show(current)
            return
        end
        stepper:Commit(parsed)
    end)
    box:HookScript("OnEditFocusLost", function(self)
        local parsed = tonumber(self:GetText())
        if parsed == nil then
            Show(current)
            return
        end
        stepper:Commit(parsed)
    end)

    Show(current)
    return stepper
end
