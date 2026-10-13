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
-- Flatter down-chevron for dropdown triggers (wider tip angle than CHEVRON_DOWN).
local DROPDOWN_CARET = { { 1, 3 }, { 5, 5 }, { 9, 3 } }
local SHADOW_ALPHA = 0.6
local BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = Assets.Textures.WHITE,
    edgeSize = Sizes.BORDER,
}

---@alias ButtonVariant "primary"|"secondary"|"warning"

local BUTTON_STYLES = {
    primary = { fill = Colors.ACCENT, border = Colors.ACCENT, font = Fonts.ON_ACCENT },
    secondary = { fill = Colors.SURFACE_RAISED, border = Colors.BORDER, font = Fonts.BODY },
    warning = { fill = Colors.WARNING, border = Colors.WARNING, font = Fonts.ON_ACCENT },
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
        font:SetFont(style.path or STANDARD_TEXT_FONT, style.size, style.flags or "")
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

---Lays out a muted subsection title with a bottom divider inside an existing row.
---Use with `stack:AddRow(Sizes.CONTENT_SECTION_HEADER)`.
---@param row Frame
---@param title string
---@return FontString
function Widgets.LayoutSectionHeader(row, title)
    Widgets.EnsureFonts()
    local label = Widgets.CreateLabel(row, Fonts.HEADER, title)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT")
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))
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
---@param variant ButtonVariant|nil  "primary" for the main action; "warning" for amber danger actions. Defaults to "secondary".
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
---@param font string|nil  Normal font object name; defaults to Fonts.LINK.
---@return Button
function Widgets.CreateTextButton(parent, text, onClick, font)
    Widgets.EnsureFonts()
    local button = CreateFrame("Button", nil, parent)
    button:SetNormalFontObject(font or Fonts.LINK)
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
---@field SetItems fun(self: SegmentedControl, items: SegmentedControlItem[])  Updates labels/values; same count as create.
---@field SetEnabled fun(self: SegmentedControl, enabled: boolean)  Enables or disables every segment button.

---Creates a row of joined, equally wide buttons of which one is selected at a time.
---Clicking a segment calls `onSelect`; the caller then calls SetSelected to show the new choice.
---@param parent Frame
---@param items SegmentedControlItem[]
---@param onSelect fun(value: any)
---@return SegmentedControl
function Widgets.CreateSegmentedControl(parent, items, onSelect)
    local control = CreateFrame("Frame", nil, parent) --[[@as SegmentedControl]]
    local segments = {}
    local selectedValue
    local baseLevel = control:GetFrameLevel() + 1

    local function Relayout()
        local segmentWidth = 0
        for _, segment in ipairs(segments) do
            segmentWidth = math.max(segmentWidth, segment:GetTextWidth() + Sizes.SEGMENT_TEXT_PADDING)
        end
        -- Neighbors overlap by one border width so the dividers between segments stay 1px wide.
        local step = segmentWidth - Sizes.BORDER
        for index, segment in ipairs(segments) do
            segment:SetSize(segmentWidth, Sizes.CONTROL_HEIGHT)
            segment:ClearAllPoints()
            segment:SetPoint("LEFT", control, "LEFT", (index - 1) * step, 0)
        end
        control:SetSize(#segments * step + Sizes.BORDER, Sizes.CONTROL_HEIGHT)
    end

    local function ApplySelection()
        for _, segment in ipairs(segments) do
            local isSelected = segment.value == selectedValue
            ApplyButtonStyle(segment, isSelected and "primary" or "secondary")
            -- Keeps the selected segment's accent border above its neighbors' borders.
            segment:SetFrameLevel(isSelected and baseLevel + 1 or baseLevel)
        end
    end

    for _, item in ipairs(items) do
        -- Declare before CreateFlatButton so the click closure captures the local, not a global
        -- (Lua 5.1: a local is not in scope on the RHS of its own declaration).
        local segment
        segment = CreateFlatButton(control, "secondary", function()
            onSelect(segment.value)
        end)
        segment:SetText(item.text)
        segment.value = item.value
        segments[#segments + 1] = segment
    end
    Relayout()

    function control:SetSelected(value)
        selectedValue = value
        ApplySelection()
    end

    ---Replaces segment values/labels in order; count must match the original.
    ---@param nextItems SegmentedControlItem[]
    function control:SetItems(nextItems)
        assert(#nextItems == #segments, "SegmentedControl.SetItems count mismatch")
        for index, item in ipairs(nextItems) do
            local segment = segments[index]
            segment.value = item.value
            segment:SetText(item.text)
        end
        Relayout()
        ApplySelection()
    end

    function control:SetEnabled(enabled)
        enabled = enabled == true
        for _, segment in ipairs(segments) do
            segment:SetEnabled(enabled)
            -- Keep opaque; parent FeatureSections already dim when inactive.
            segment:SetAlpha(1)
        end
    end
    return control
end

---@class DropdownItem
---@field value any
---@field text string

---@class Dropdown: Frame
---@field SetSelected fun(self: Dropdown, value: any)  Updates the trigger label for `value`.
---@field SetItems fun(self: Dropdown, items: DropdownItem[])  Replaces the choice list; recreates the popup on next open.
---@field SetAutoWidth fun(self: Dropdown, enabled: boolean)  When false, width comes from anchors/SetWidth; popup still matches.
---@field SetJustifyH fun(self: Dropdown, justifyH: string)  Horizontal alignment of the selected-value label.
---@field SetEnabled fun(self: Dropdown, enabled: boolean)
---@field IsEnabled fun(self: Dropdown): boolean

---Creates a compact dropdown: a trigger button and a popup list of choices.
---Selecting an item calls `onSelect`; the caller then calls SetSelected to show the new choice.
---@param parent Frame
---@param items DropdownItem[]
---@param onSelect fun(value: any)
---@return Dropdown
function Widgets.CreateDropdown(parent, items, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent) --[[@as Dropdown]]
    local currentItems = items
    local textByValue = {}
    local selectedValue
    local autoWidth = true
    local menu
    local catcher
    local label
    Widgets.EnsureFonts()
    local measure = dropdown:CreateFontString(nil, "OVERLAY", Fonts.BODY)
    measure:SetFontObject(Fonts.BODY)
    measure:Hide()

    local function CloseMenu()
        if menu then
            menu:Hide()
        end
        if catcher then
            catcher:Hide()
        end
    end

    local function DiscardMenu()
        CloseMenu()
        if menu then
            menu:SetParent(nil)
            menu = nil
        end
    end

    local function ApplyItems(nextItems)
        currentItems = nextItems
        for key in pairs(textByValue) do
            textByValue[key] = nil
        end
        local maxTextWidth = 0
        for _, item in ipairs(currentItems) do
            textByValue[item.value] = item.text
            measure:SetText(item.text)
            maxTextWidth = math.max(maxTextWidth, measure:GetStringWidth())
        end
        if autoWidth then
            local width = math.max(maxTextWidth + Sizes.DROPDOWN_TEXT_PADDING, Sizes.DROPDOWN_MIN_WIDTH)
            dropdown:SetSize(width, Sizes.CONTROL_HEIGHT)
        else
            dropdown:SetHeight(Sizes.CONTROL_HEIGHT)
        end
        DiscardMenu()
        if label and selectedValue ~= nil then
            label:SetText(textByValue[selectedValue] or selectedValue or "")
        end
    end

    local function EnsureMenu()
        if menu then
            return
        end
        -- Full-screen catcher closes the menu on an outside click without eating other input while hidden.
        if not catcher then
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetAllPoints()
            catcher:EnableMouse(true)
            -- Swallow wheel so the open menu cannot scroll the panel underneath.
            catcher:EnableMouseWheel(true)
            catcher:SetScript("OnMouseWheel", function() end)
            catcher:SetScript("OnClick", CloseMenu)
            catcher:Hide()
        end

        local optionHeight = Sizes.CONTROL_HEIGHT
        local contentHeight = math.max(#currentItems, 1) * optionHeight
        local viewHeight = math.min(contentHeight, Sizes.DROPDOWN_MAX_VISIBLE * optionHeight)
        local needsScroll = contentHeight > viewHeight
        local scrollGutter = needsScroll and (Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL) or 0
        local options = {}

        -- Height only: width is locked to the trigger via TOPLEFT+TOPRIGHT in ToggleMenu.
        menu = Widgets.CreateSurface(UIParent, Colors.SURFACE_RAISED, Colors.BORDER)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(catcher:GetFrameLevel() + 1)
        menu:SetHeight(viewHeight + 2 * Sizes.BORDER)
        menu:EnableMouse(true)
        menu:Hide()

        local scrollFrame = CreateFrame("ScrollFrame", nil, menu)
        scrollFrame:SetPoint("TOPLEFT", Sizes.BORDER, -Sizes.BORDER)
        scrollFrame:SetPoint("BOTTOMRIGHT", -(Sizes.BORDER + scrollGutter), Sizes.BORDER)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetHeight(contentHeight)
        scrollFrame:SetScrollChild(content)

        ---@param _ Frame
        ---@param delta number
        local function OnMenuMouseWheel(_, delta)
            local range = scrollFrame:GetVerticalScrollRange()
            if range <= 0 then
                return
            end
            local next = scrollFrame:GetVerticalScroll() - delta * optionHeight
            scrollFrame:SetVerticalScroll(math.min(math.max(next, 0), range))
        end

        -- Wheel over options hits the button, not the ScrollFrame; bind all layers so the
        -- main panel underneath never receives the event while the menu is open.
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", OnMenuMouseWheel)
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", OnMenuMouseWheel)
        content:EnableMouse(true)
        content:EnableMouseWheel(true)
        content:SetScript("OnMouseWheel", OnMenuMouseWheel)

        if needsScroll then
            local scrollBar = CreateFrame("EventFrame", nil, menu, Assets.Templates.SCROLL_BAR)
            scrollBar:SetPoint("TOPRIGHT", -Sizes.BORDER, -Sizes.BORDER)
            scrollBar:SetPoint("BOTTOMRIGHT", -Sizes.BORDER, Sizes.BORDER)
            ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
        end

        for index, item in ipairs(currentItems) do
            local option = CreateFlatButton(content, "secondary", function()
                CloseMenu()
                onSelect(item.value)
            end)
            option:SetText(item.text)
            option:SetHeight(optionHeight)
            option:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * optionHeight))
            option:EnableMouseWheel(true)
            option:SetScript("OnMouseWheel", OnMenuMouseWheel)
            options[index] = option
        end

        -- Runs after TOPLEFT+TOPRIGHT pin the menu to the trigger's real laid-out width.
        menu:HookScript("OnSizeChanged", function(self, menuWidth)
            if menuWidth <= 0 then
                return
            end
            local innerWidth = math.max(menuWidth - 2 * Sizes.BORDER - scrollGutter, 1)
            content:SetWidth(innerWidth)
            for _, option in ipairs(options) do
                option:SetWidth(innerWidth)
            end
        end)
    end

    local function ToggleMenu()
        EnsureMenu()
        if menu:IsShown() then
            CloseMenu()
            return
        end
        menu:ClearAllPoints()
        -- Pin both corners so the popup width always matches the trigger, including anchor-stretched triggers.
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -Spacing.TINY)
        menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -Spacing.TINY)
        catcher:Show()
        menu:Show()
    end

    local trigger = CreateFlatButton(dropdown, "secondary", ToggleMenu)
    trigger:SetAllPoints(dropdown)
    -- FeatureSection walks SetEnabled on descendants after the dropdown; keep the trigger
    -- gated by this flag so a locked/disabled dropdown cannot be re-enabled underneath.
    local dropdownEnabled = true
    local rawTriggerSetEnabled = trigger.SetEnabled
    function trigger:SetEnabled(enabled)
        rawTriggerSetEnabled(self, enabled == true and dropdownEnabled)
    end

    label = Widgets.CreateLabel(trigger, Fonts.BODY)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetPoint("LEFT", Spacing.MEDIUM, 0)
    label:SetPoint("RIGHT", trigger, "RIGHT", -(Spacing.MEDIUM + Spacing.LARGE), 0)

    -- Line-drawn caret (locale fonts often lack wide-angle Unicode glyphs like ⌵).
    local caret = CreateFrame("Frame", nil, trigger)
    caret:SetSize(Sizes.DROPDOWN_CARET, Sizes.DROPDOWN_CARET)
    caret:SetPoint("RIGHT", -Spacing.MEDIUM, 0)
    local caretTip = DROPDOWN_CARET[2]
    for index = 1, 2 do
        local stroke = caret:CreateLine(nil, "ARTWORK")
        stroke:SetThickness(Sizes.DROPDOWN_CARET_THICKNESS)
        stroke:SetColorTexture(Widgets.UnpackColor(Colors.TEXT_MUTED))
        stroke:SetSnapToPixelGrid(false)
        stroke:SetTexelSnappingBias(0)
        local outer = DROPDOWN_CARET[index == 1 and 1 or 3]
        local dx, dy = caretTip[1] - outer[1], caretTip[2] - outer[2]
        local extend = Sizes.DROPDOWN_CARET_THICKNESS / 2 / math.sqrt(dx * dx + dy * dy)
        stroke:SetStartPoint("TOPLEFT", caret, outer[1], -outer[2])
        stroke:SetEndPoint("TOPLEFT", caret, caretTip[1] + dx * extend, -(caretTip[2] + dy * extend))
    end

    function dropdown:SetSelected(value)
        selectedValue = value
        label:SetText(textByValue[value] or value or "")
    end

    function dropdown:SetItems(nextItems)
        ApplyItems(nextItems)
    end

    ---When false, callers size the trigger with anchors or SetWidth; the popup still matches that width.
    ---@param enabled boolean
    function dropdown:SetAutoWidth(enabled)
        autoWidth = enabled == true
        ApplyItems(currentItems)
    end

    ---@param justifyH string  "LEFT", "CENTER", or "RIGHT".
    function dropdown:SetJustifyH(justifyH)
        label:SetJustifyH(justifyH)
    end

    function dropdown:SetEnabled(enabled)
        dropdownEnabled = enabled == true
        trigger:SetEnabled(dropdownEnabled)
        if not dropdownEnabled then
            CloseMenu()
        end
    end

    function dropdown:IsEnabled()
        return dropdownEnabled
    end

    ApplyItems(items)
    return dropdown
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

---@class ColorRGB
---@field r number
---@field g number
---@field b number

---@class ColorSwatch: Button
---@field SetColor fun(self: ColorSwatch, color: ColorRGB)  Updates the swatch fill.
---@field GetColor fun(self: ColorSwatch): ColorRGB  Copy of the current RGB.

---Creates a square swatch that opens ColorPickerFrame on click (RGB only, no opacity).
---@param parent Frame
---@param color ColorRGB  Initial fill color.
---@param onColorChanged fun(color: ColorRGB)  Called for live edits and cancel restore.
---@return ColorSwatch
function Widgets.CreateColorSwatch(parent, color, onColorChanged)
    local swatch = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP) --[[@as ColorSwatch]]
    swatch:SetSize(Sizes.COLOR_SWATCH, Sizes.COLOR_SWATCH)
    Widgets.ApplyBackdrop(swatch, color, Colors.BORDER)
    Widgets.AddHoverHighlight(swatch)

    ---@type ColorRGB
    swatch.color = { r = color.r, g = color.g, b = color.b }

    function swatch:SetColor(next)
        self.color.r, self.color.g, self.color.b = next.r, next.g, next.b
        self:SetBackdropColor(next.r, next.g, next.b, 1)
    end

    function swatch:GetColor()
        local current = self.color
        return { r = current.r, g = current.g, b = current.b }
    end

    -- FeatureSection (and callers) use SetEnabled; Button Enable/Disable is native but unnamed.
    function swatch:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end

    swatch:SetScript("OnClick", function(self)
        local current = self:GetColor()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = current.r,
            g = current.g,
            b = current.b,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local next = { r = r, g = g, b = b }
                self:SetColor(next)
                onColorChanged(next)
            end,
            cancelFunc = function()
                local r, g, b = ColorPickerFrame:GetPreviousValues()
                local next = { r = r, g = g, b = b }
                self:SetColor(next)
                onColorChanged(next)
            end,
        })
    end)
    return swatch
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
    -- FeatureSection (and callers) use SetEnabled; EditBox only has Enable/Disable natively.
    function box:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end
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
