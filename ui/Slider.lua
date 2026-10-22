local _, ns = ...
local Assets = ns.Assets
local L = ns.L
local Util = ns.Util
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Slider = {}
ns.Slider = Slider

---@class CreateSliderOptions
---@field allowMouseWheel boolean|nil  When true, the mouse wheel steps the value. Defaults to false.
---@field allowTypedValue boolean|nil  When true, shows an editable number box. Defaults to true.
---@field percentage boolean|nil  When true, the box shows `value * 100` with a "%" suffix. Defaults to false.
---@field suffix string|nil  Text after the value box. `percentage` uses the percent suffix instead.

---@class SliderControl: Slider
---@field valueBox EditBox|nil  Present when typed values are enabled; anchored to the right of the slider by default.
---@field valueSuffix FontString|nil  Suffix after the value box, such as "%" or "°".

---Digits needed to show the larger of `|a|` and `|b|` as integers.
---@param a number
---@param b number
---@return integer
local function MaxIntegerDigits(a, b)
    local maxAbs = math.max(math.abs(a), math.abs(b))
    if maxAbs < 1 then
        return 1
    end
    return math.floor(math.log10(maxAbs)) + 1
end

---Creates a horizontal slider. Drag the thumb to change the value.
---By default a number box to the right accepts typed values and clamps them to `[minValue, maxValue]`.
---@param parent Frame
---@param minValue number
---@param maxValue number
---@param step number
---@param allowMouseWheelOrOptions boolean|CreateSliderOptions|nil  Legacy: `true` enables mouse wheel. Or an options table.
---@return SliderControl
function Slider.Create(parent, minValue, maxValue, step, allowMouseWheelOrOptions)
    ---@type CreateSliderOptions
    local options
    if type(allowMouseWheelOrOptions) == "table" then
        options = allowMouseWheelOrOptions
    else
        options = { allowMouseWheel = allowMouseWheelOrOptions == true }
    end
    local allowMouseWheel = options.allowMouseWheel == true
    local allowTypedValue = options.allowTypedValue ~= false
    local percentage = options.percentage == true
    local displayScale = percentage and 100 or 1
    local suffixText = percentage and L.PERCENT_SUFFIX or options.suffix

    local slider = CreateFrame("Slider", nil, parent) --[[@as SliderControl]]
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(Sizes.SLIDER_WIDTH, Sizes.SLIDER_HEIGHT)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(Sizes.SLIDER_TRACK)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(Widgets.UnpackColor(Colors.BORDER))

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(Sizes.SLIDER_THUMB_WIDTH, Sizes.SLIDER_THUMB_HEIGHT)
    thumb:SetColorTexture(Widgets.UnpackColor(Colors.ACCENT))
    slider:SetThumbTexture(thumb)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(Sizes.SLIDER_TRACK)
    fill:SetPoint("LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(Widgets.UnpackColor(Colors.ACCENT))

    if allowMouseWheel then
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not self:IsEnabled() then
                return
            end
            self:SetValue(self:GetValue() + delta * step)
        end)
    end

    if allowTypedValue then
        local displayStep = step * displayScale
        local integerDisplay = math.abs(displayStep - math.floor(displayStep + 0.5)) < 1e-9
        local maxDigits = MaxIntegerDigits(minValue * displayScale, maxValue * displayScale)
        if not integerDisplay then
            -- Room for a decimal point and one step digit (e.g. "1.05").
            maxDigits = maxDigits + 2
        end
        local valueBox = Widgets.CreateNumberBox(parent, maxDigits, {
            signed = minValue * displayScale < 0,
            decimal = not integerDisplay,
        })
        valueBox:SetPoint("LEFT", slider, "RIGHT", Spacing.MEDIUM, 0)
        slider.valueBox = valueBox
        if type(suffixText) == "string" and suffixText ~= "" then
            local suffix = Widgets.CreateLabel(parent, Fonts.BODY, suffixText)
            suffix:SetPoint("LEFT", valueBox, "RIGHT", Spacing.TINY, 0)
            slider.valueSuffix = suffix
        end

        local suppressBoxSync = false
        ---@type fun(self: Slider, value: number)|nil
        local userOnValueChanged

        local function FormatDisplay(value)
            local display = value * displayScale
            if integerDisplay then
                return tostring(math.floor(display + 0.5))
            end
            return string.format("%g", display)
        end

        local function SyncValueBox()
            if suppressBoxSync or valueBox:HasFocus() then
                return
            end
            suppressBoxSync = true
            valueBox:SetText(FormatDisplay(slider:GetValue()))
            suppressBoxSync = false
        end

        local function CommitValueBox()
            if suppressBoxSync then
                return
            end
            local parsed = tonumber(valueBox:GetText())
            if parsed == nil then
                SyncValueBox()
                return
            end
            local nextValue = Util.Snap(parsed / displayScale, minValue, maxValue, step)
            if math.abs(nextValue - slider:GetValue()) > 1e-9 then
                slider:SetValue(nextValue)
            end
            suppressBoxSync = true
            valueBox:SetText(FormatDisplay(slider:GetValue()))
            suppressBoxSync = false
        end

        -- Callers use SetScript("OnValueChanged"), which replaces HookScript handlers, so keep
        -- sync on our own handler and forward the caller's script from a SetScript wrapper.
        local rawSetScript = slider.SetScript
        rawSetScript(slider, "OnValueChanged", function(self, value)
            SyncValueBox()
            if userOnValueChanged then
                userOnValueChanged(self, value)
            end
        end)
        function slider:SetScript(scriptType, handler)
            if scriptType == "OnValueChanged" then
                userOnValueChanged = handler
                return
            end
            return rawSetScript(self, scriptType, handler)
        end

        valueBox:HookScript("OnEnterPressed", CommitValueBox)
        valueBox:HookScript("OnEditFocusLost", CommitValueBox)
    end

    -- FeatureSection (and callers) use SetEnabled; Slider only has Enable/Disable natively.
    function slider:SetEnabled(enabled)
        if enabled then
            self:Enable()
            if allowMouseWheel then
                self:EnableMouseWheel(true)
            end
        else
            self:Disable()
            self:EnableMouseWheel(false)
        end
        if self.valueBox then
            self.valueBox:SetEnabled(enabled)
        end
    end
    return slider
end
