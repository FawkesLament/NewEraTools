local _, ns = ...
local Assets = ns.Assets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local DISABLED_ALPHA = 0.4
-- Chevron vertices as { x, y } offsets from the top-left of a Sizes.EXPAND_ARROW square; the middle one is the tip.
-- The strokes meet at a right angle, which the tip extension in CreateExpandButton relies on.
local CHEVRON_RIGHT = { { 3, 1 }, { 7, 5 }, { 3, 9 } }
local CHEVRON_DOWN = { { 1, 3 }, { 5, 7 }, { 9, 3 } }
local SHADOW_ALPHA = 0.6
local BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = Assets.Textures.WHITE,
    edgeSize = Sizes.BORDER,
}

---@alias ButtonVariant "primary"|"secondary"

local BUTTON_STYLES = {
    primary = { fill = Colors.ACCENT, border = Colors.ACCENT, font = Fonts.ON_ACCENT },
    secondary = { fill = Colors.SURFACE_RAISED, border = Colors.BORDER, font = Fonts.BODY },
}

local Widgets = {}
ns.Widgets = Widgets

local fontsCreated = false

---@param color { r: number, g: number, b: number, a: number|nil }  e.g. a value from Assets.Colors.
---@return number r, number g, number b, number|nil a
function Widgets.UnpackColor(color)
    return color.r, color.g, color.b, color.a
end

---Creates the font objects named in Assets.Fonts. Safe to call repeatedly.
function Widgets.EnsureFonts()
    if fontsCreated then
        return
    end
    fontsCreated = true
    for name, style in pairs(Assets.FontStyles) do
        local font = CreateFont(name)
        font:SetFont(STANDARD_TEXT_FONT, style.size, style.flags or "")
        font:SetTextColor(Widgets.UnpackColor(style.color))
        if not style.flags then
            font:SetShadowOffset(1, -1)
            font:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
        end
    end
end

---Gives a frame created with Assets.Templates.BACKDROP a flat fill and a 1px border.
---@param frame Frame
---@param fill table  A color from Assets.Colors.
---@param border table|nil  A color from Assets.Colors; no border if nil.
function Widgets.ApplyBackdrop(frame, fill, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(Widgets.UnpackColor(fill))
    if border then
        frame:SetBackdropBorderColor(Widgets.UnpackColor(border))
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

---Creates a flat frame with a fill and an optional border.
---@param parent Frame
---@param fill table  A color from Assets.Colors.
---@param border table|nil  A color from Assets.Colors.
---@param name string|nil  Global frame name; must start with the addon name.
---@return Frame
function Widgets.CreateSurface(parent, fill, border, name)
    local frame = CreateFrame("Frame", name, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(frame, fill, border)
    return frame
end

---Adds a translucent overlay that shows while the mouse is over `frame`, and not while it is disabled.
---@param frame Button
---@return Texture
function Widgets.AddHoverHighlight(frame)
    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(Widgets.UnpackColor(Colors.HOVER))
    return highlight
end

---@param parent Frame
---@param font string  A font object name from Assets.Fonts.
---@param text string|nil
---@return FontString
function Widgets.CreateLabel(parent, font, text)
    Widgets.EnsureFonts()
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    if text then
        label:SetText(text)
    end
    return label
end

local function ApplyButtonStyle(button, variant)
    local style = BUTTON_STYLES[variant]
    Widgets.ApplyBackdrop(button, style.fill, style.border)
    button:SetNormalFontObject(style.font)
    button:SetDisabledFontObject(style.font)
end

local function CreateFlatButton(parent, variant, onClick)
    Widgets.EnsureFonts()
    local button = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP)
    ApplyButtonStyle(button, variant)
    Widgets.AddHoverHighlight(button)
    button:SetScript("OnEnable", function(self)
        self:SetAlpha(1)
    end)
    button:SetScript("OnDisable", function(self)
        self:SetAlpha(DISABLED_ALPHA)
    end)
    button:SetScript("OnClick", onClick)
    return button
end

---Creates a flat button sized to fit its text, so translations can't overflow it.
---@param parent Frame
---@param text string
---@param onClick fun(button: Button)
---@param variant ButtonVariant|nil  "primary" for the main action of a section. Defaults to "secondary".
---@return Button
function Widgets.CreateButton(parent, text, onClick, variant)
    local button = CreateFlatButton(parent, variant or "secondary", onClick)
    button:SetText(text)
    local width = math.max(button:GetTextWidth() + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH)
    button:SetSize(width, Sizes.CONTROL_HEIGHT)
    return button
end

---Creates a borderless, link-style button: accent-colored text that turns white on hover, sized to fit.
---@param parent Frame
---@param text string
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateTextButton(parent, text, onClick)
    Widgets.EnsureFonts()
    local button = CreateFrame("Button", nil, parent)
    button:SetNormalFontObject(Fonts.LINK)
    button:SetHighlightFontObject(Fonts.BODY)
    button:SetText(text)
    button:SetSize(button:GetTextWidth() + 2 * Spacing.SMALL, Sizes.CONTROL_HEIGHT)
    button:SetScript("OnClick", onClick)
    return button
end

---@class SegmentedControlItem
---@field value any
---@field text string

---@class SegmentedControl: Frame
---@field SetSelected fun(self: SegmentedControl, value: any)  Highlights the segment holding `value`.

---Creates a row of joined, equally wide buttons of which one is selected at a time.
---Clicking a segment calls `onSelect`; the caller then calls SetSelected to show the new choice.
---@param parent Frame
---@param items SegmentedControlItem[]
---@param onSelect fun(value: any)
---@return SegmentedControl
function Widgets.CreateSegmentedControl(parent, items, onSelect)
    local control = CreateFrame("Frame", nil, parent) --[[@as SegmentedControl]]
    local segments = {}
    local segmentWidth = 0
    for index, item in ipairs(items) do
        local segment = CreateFlatButton(control, "secondary", function()
            onSelect(item.value)
        end)
        segment:SetText(item.text)
        segment.value = item.value
        segmentWidth = math.max(segmentWidth, segment:GetTextWidth() + Sizes.SEGMENT_TEXT_PADDING)
        segments[index] = segment
    end

    -- Neighbors overlap by one border width so the dividers between segments stay 1px wide.
    local step = segmentWidth - Sizes.BORDER
    for index, segment in ipairs(segments) do
        segment:SetSize(segmentWidth, Sizes.CONTROL_HEIGHT)
        segment:SetPoint("LEFT", control, "LEFT", (index - 1) * step, 0)
    end
    control:SetSize(#segments * step + Sizes.BORDER, Sizes.CONTROL_HEIGHT)

    local baseLevel = control:GetFrameLevel() + 1
    function control:SetSelected(value)
        for _, segment in ipairs(segments) do
            local isSelected = segment.value == value
            ApplyButtonStyle(segment, isSelected and "primary" or "secondary")
            -- Keeps the selected segment's accent border above its neighbors' borders.
            segment:SetFrameLevel(isSelected and baseLevel + 1 or baseLevel)
        end
    end
    return control
end

---@class Stepper: Frame
---@field SetValue fun(self: Stepper, value: integer, min: integer, max: integer)  Shows `value`; the
---buttons are disabled at the limits.

---Creates a compact "[-] value [+]" control. The buttons call `onStep` with -1 or 1; the caller
---then calls SetValue with the new value.
---@param parent Frame
---@param onStep fun(delta: integer)
---@return Stepper
function Widgets.CreateStepper(parent, onStep)
    local stepper = CreateFrame("Frame", nil, parent) --[[@as Stepper]]
    stepper:SetSize(2 * Sizes.CONTROL_HEIGHT + Sizes.STEPPER_VALUE_WIDTH, Sizes.CONTROL_HEIGHT)

    local function CreateStepButton(glyph, delta, point)
        local button = CreateFlatButton(stepper, "secondary", function()
            onStep(delta)
        end)
        button:SetText(glyph)
        button:SetSize(Sizes.CONTROL_HEIGHT, Sizes.CONTROL_HEIGHT)
        button:SetPoint(point)
        return button
    end
    local decrease = CreateStepButton(Assets.Glyphs.DECREASE, -1, "LEFT")
    local increase = CreateStepButton(Assets.Glyphs.INCREASE, 1, "RIGHT")

    local label = Widgets.CreateLabel(stepper, Fonts.BODY)
    label:SetPoint("LEFT", decrease, "RIGHT")
    label:SetPoint("RIGHT", increase, "LEFT")
    label:SetJustifyH("CENTER")

    function stepper:SetValue(value, min, max)
        label:SetText(tostring(value))
        decrease:SetEnabled(value > min)
        increase:SetEnabled(value < max)
    end
    return stepper
end

---@class ExpandButton: Button
---@field SetExpanded fun(self: ExpandButton, expanded: boolean)  Points the arrow down when expanded.
---@field SetLabel fun(self: ExpandButton, text: string)  Changes the text and resizes to fit it.

---Creates a borderless header with a disclosure arrow, for showing and hiding a section below it.
---@param parent Frame
---@param onClick fun(button: Button)
---@return ExpandButton
function Widgets.CreateExpandButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent) --[[@as ExpandButton]]
    Widgets.AddHoverHighlight(button)

    local arrow = CreateFrame("Frame", nil, button)
    arrow:SetSize(Sizes.EXPAND_ARROW, Sizes.EXPAND_ARROW)
    arrow:SetPoint("LEFT")

    -- Drawn with lines rather than a texture so it stays sharp at any panel scale.
    local strokes = {}
    for index = 1, 2 do
        local stroke = arrow:CreateLine(nil, "ARTWORK")
        stroke:SetThickness(Sizes.EXPAND_ARROW_THICKNESS)
        stroke:SetColorTexture(Widgets.UnpackColor(Colors.TEXT))
        -- Snapping moves each line's ends independently, which pulls the two strokes apart at the tip.
        stroke:SetSnapToPixelGrid(false)
        stroke:SetTexelSnappingBias(0)
        strokes[index] = stroke
    end

    local label = Widgets.CreateLabel(button, Fonts.BODY)
    label:SetPoint("LEFT", arrow, "RIGHT", Spacing.SMALL, 0)

    function button:SetExpanded(expanded)
        local points = expanded and CHEVRON_DOWN or CHEVRON_RIGHT
        local tip = points[2]
        for index, stroke in ipairs(strokes) do
            local outer = points[index == 1 and 1 or 3]
            -- Lines have square caps, so each stroke runs half its thickness past the tip
            -- to fill the outer corner where the two meet.
            local dx, dy = tip[1] - outer[1], tip[2] - outer[2]
            local extend = Sizes.EXPAND_ARROW_THICKNESS / 2 / math.sqrt(dx * dx + dy * dy)
            stroke:SetStartPoint("TOPLEFT", arrow, outer[1], -outer[2])
            stroke:SetEndPoint("TOPLEFT", arrow, tip[1] + dx * extend, -(tip[2] + dy * extend))
        end
    end
    button:SetExpanded(false)

    function button:SetLabel(text)
        label:SetText(text)
        local width = Sizes.EXPAND_ARROW + label:GetStringWidth() + 2 * Spacing.SMALL
        self:SetSize(width, Sizes.CONTROL_HEIGHT)
    end

    button:SetScript("OnClick", onClick)
    return button
end

---Creates a borderless square button showing a close glyph.
---@param parent Frame
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateCloseButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(Sizes.CLOSE_BUTTON, Sizes.CLOSE_BUTTON)
    Widgets.AddHoverHighlight(button)

    local glyph = Widgets.CreateLabel(button, Fonts.GLYPH, Assets.Glyphs.CLOSE)
    glyph:SetPoint("CENTER")

    button:SetScript("OnClick", onClick)
    return button
end

---Creates a flat square checkbox that fills with the accent color when checked.
---@param parent Frame
---@return CheckButton
function Widgets.CreateCheckbox(parent)
    local box = CreateFrame("CheckButton", nil, parent, Assets.Templates.BACKDROP)
    box:SetSize(Sizes.CHECKBOX, Sizes.CHECKBOX)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    Widgets.AddHoverHighlight(box)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", Sizes.CHECKBOX_FILL_INSET, -Sizes.CHECKBOX_FILL_INSET)
    fill:SetPoint("BOTTOMRIGHT", -Sizes.CHECKBOX_FILL_INSET, Sizes.CHECKBOX_FILL_INSET)
    fill:SetColorTexture(Widgets.UnpackColor(Colors.ACCENT))
    box:SetCheckedTexture(fill)
    return box
end

---Creates a flat horizontal slider. The mouse wheel moves it by one step.
---@param parent Frame
---@param minValue number
---@param maxValue number
---@param step number
---@return Slider
---Creates a horizontal slider. Drag the thumb to change the value.
---@param parent Frame
---@param minValue number
---@param maxValue number
---@param step number
---@param allowMouseWheel boolean|nil  When true, the mouse wheel steps the value. Defaults to false.
---@return Slider
function Widgets.CreateSlider(parent, minValue, maxValue, step, allowMouseWheel)
    local slider = CreateFrame("Slider", nil, parent)
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
    end
    return slider
end

---Creates a centered, digits-only input box sized to fit `maxDigits`. Enter clears focus.
---The border turns to the accent color while focused; add focus handlers with HookScript to keep that.
---@param parent Frame
---@param maxDigits integer
---@return EditBox
function Widgets.CreateNumberBox(parent, maxDigits)
    Widgets.EnsureFonts()
    local box = CreateFrame("EditBox", nil, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    box:SetFontObject(Fonts.BODY)
    local width = maxDigits * Sizes.INPUT_DIGIT_WIDTH + Sizes.INPUT_TEXT_PADDING
    box:SetSize(width, Sizes.INPUT_HEIGHT)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(maxDigits)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.ACCENT))
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER))
    end)
    return box
end

---Shows GameTooltip on hover. Nothing is shown if `populate` adds no lines.
---@param frame Frame
---@param anchor string  e.g. "ANCHOR_TOP".
---@param populate fun(tooltip: GameTooltip)
function Widgets.AttachTooltip(frame, anchor, populate)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor)
        populate(GameTooltip)
        if GameTooltip:NumLines() > 0 then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
