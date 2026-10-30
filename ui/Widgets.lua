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
-- Corner brackets in a 12px box (y grows downward). Reads as a layout frame being moved.
local LAYOUT_MOVE_STROKES = {
    { 1, 1, 4, 1 },
    { 1, 1, 1, 4 },
    { 8, 1, 11, 1 },
    { 11, 1, 11, 4 },
    { 1, 8, 1, 11 },
    { 1, 11, 4, 11 },
    { 11, 8, 11, 11 },
    { 8, 11, 11, 11 },
}
local SHADOW_ALPHA = 0.6
local BACKDROP = {
    bgFile = Assets.Textures.WHITE,
    edgeFile = Assets.Textures.WHITE,
    edgeSize = Sizes.BORDER,
}

---@alias ButtonVariant "primary"|"secondary"|"warning"|"accent"

local BUTTON_STYLES = {
    primary = { fill = Colors.ACCENT, border = Colors.ACCENT, font = Fonts.ON_ACCENT },
    secondary = { fill = Colors.SURFACE_RAISED, border = Colors.BORDER, font = Fonts.BODY },
    warning = { fill = Colors.WARNING, border = Colors.WARNING, font = Fonts.ON_ACCENT },
    -- Dark fill with a turquoise edge. Quieter than a solid accent bar.
    accent = { fill = Colors.SURFACE_RAISED, border = Colors.ACCENT, font = Fonts.BODY },
}

-- Pressed wash over an accent button. Light enough that the label stays readable.
local ACCENT_PRESS_ALPHA = 0.16

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
        local path = style.path
        if name == Fonts.OVERLAY_DIGIT then
            path = DAMAGE_TEXT_FONT or path
        end
        font:SetFont(path or STANDARD_TEXT_FONT, style.size, style.flags or "")
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

---Backdrop button with hover highlight and fade-on-disable. Callers that size the button themselves use this.
---@param parent Frame
---@param variant ButtonVariant
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateFlatButton(parent, variant, onClick)
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
    -- SetEnabled must sync fade even when already disabled: Disable() does not re-fire
    -- OnDisable, and FeatureSection forces alpha to 1 while a parent feature is off.
    local rawSetEnabled = button.SetEnabled
    function button:SetEnabled(enabled)
        enabled = enabled == true
        rawSetEnabled(self, enabled)
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    end
    button:SetScript("OnClick", onClick)
    return button
end

---Hides the built-in label and draws `glyph` plus `text`, centered as one cluster.
---@param button Button
---@param text string
---@param glyph string
---@return FontString glyphLabel, FontString caption
local function AddButtonGlyph(button, text, glyph)
    button:SetText(text)
    local builtin = button:GetFontString()
    if builtin then
        builtin:Hide()
    end

    local glyphLabel = Widgets.CreateLabel(button, Fonts.BODY, glyph)
    glyphLabel:SetTextColor(Widgets.UnpackColor(Colors.ACCENT))
    local caption = Widgets.CreateLabel(button, Fonts.BODY, text)
    caption:SetTextColor(Widgets.UnpackColor(Colors.TEXT))

    local gap = Spacing.SMALL
    local clusterWidth = glyphLabel:GetStringWidth() + gap + caption:GetStringWidth()
    glyphLabel:SetPoint("LEFT", button, "CENTER", -clusterWidth / 2, 0)
    caption:SetPoint("LEFT", glyphLabel, "RIGHT", gap, 0)

    local width = math.max(clusterWidth + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH)
    button:SetSize(width, Sizes.CONTROL_HEIGHT)
    return glyphLabel, caption
end

---Accent stays opaque when disabled and shifts to a neutral fill instead of fading the turquoise edge.
---@param button Button
---@param enabled boolean
local function ApplyAccentEnabled(button, enabled)
    button:SetAlpha(1)
    if enabled then
        ApplyButtonStyle(button, "accent")
    else
        Widgets.ApplyBackdrop(button, Colors.SURFACE, Colors.BORDER)
        button:SetNormalFontObject(Fonts.MUTED)
        button:SetDisabledFontObject(Fonts.MUTED)
        button.accentWash:Hide()
    end
    local mark = enabled and Colors.ACCENT or Colors.TEXT_MUTED
    local caption = enabled and Colors.TEXT or Colors.TEXT_MUTED
    if button.accentGlyph then
        button.accentGlyph:SetTextColor(Widgets.UnpackColor(mark))
    end
    if button.accentCaption then
        button.accentCaption:SetTextColor(Widgets.UnpackColor(caption))
    end
end

---Creates a flat button sized to fit its text, so translations can't overflow it.
---@param parent Frame
---@param text string
---@param onClick fun(button: Button)
---@param variant ButtonVariant|nil  "primary" fills with accent. "accent" keeps the dark fill and a turquoise edge. "warning" is amber. Defaults to "secondary".
---@param glyph string|nil  Small mark drawn before the label. Used with "accent".
---@return Button
function Widgets.CreateButton(parent, text, onClick, variant, glyph)
    variant = variant or "secondary"
    local button = Widgets.CreateFlatButton(parent, variant, onClick)
    button:SetText(text)

    if variant == "accent" then
        local wash = button:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        local r, g, b = Widgets.UnpackColor(Colors.ACCENT)
        wash:SetColorTexture(r, g, b, ACCENT_PRESS_ALPHA)
        wash:Hide()
        button.accentWash = wash
        button:HookScript("OnMouseDown", function(self)
            if self:IsEnabled() then
                wash:Show()
            end
        end)
        button:HookScript("OnMouseUp", function()
            wash:Hide()
        end)

        local rawSetEnabled = button.SetEnabled
        function button:SetEnabled(enabled)
            rawSetEnabled(self, enabled)
            ApplyAccentEnabled(self, enabled == true)
        end
    end

    if variant == "accent" and type(glyph) == "string" and glyph ~= "" then
        button.accentGlyph, button.accentCaption = AddButtonGlyph(button, text, glyph)
    else
        local width = math.max(button:GetTextWidth() + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH)
        button:SetSize(width, Sizes.CONTROL_HEIGHT)
    end
    return button
end

---Line-drawn layout frame. Stays sharp when the main panel is scaled.
---@param parent Frame
---@return Frame
local function CreateLayoutMoveIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(Sizes.LAYOUT_EDIT_ICON, Sizes.LAYOUT_EDIT_ICON)
    for _, stroke in ipairs(LAYOUT_MOVE_STROKES) do
        local line = icon:CreateLine(nil, "ARTWORK")
        line:SetThickness(Sizes.LAYOUT_EDIT_ICON_THICKNESS)
        line:SetColorTexture(Widgets.UnpackColor(Colors.TEXT_MUTED))
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetStartPoint("TOPLEFT", icon, stroke[1], -stroke[2])
        line:SetEndPoint("TOPLEFT", icon, stroke[3], -stroke[4])
    end
    return icon
end

---Secondary button that enters layout editing: muted move icon, then the label, centered as a pair.
---@param parent Frame
---@param text string
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateLayoutEditButton(parent, text, onClick)
    local button = Widgets.CreateFlatButton(parent, "secondary", onClick)
    -- Keep the label available to GetText, but draw our own so the icon and text center together.
    button:SetText(text)
    local builtin = button:GetFontString()
    if builtin then
        builtin:Hide()
    end

    local icon = CreateLayoutMoveIcon(button)
    local caption = Widgets.CreateLabel(button, Fonts.BODY, text)
    caption:SetJustifyH("LEFT")
    local gap = Spacing.SMALL
    local clusterWidth = Sizes.LAYOUT_EDIT_ICON + gap + caption:GetStringWidth()
    icon:SetPoint("LEFT", button, "CENTER", -clusterWidth / 2, 0)
    caption:SetPoint("LEFT", icon, "RIGHT", gap, 0)

    local width = math.max(clusterWidth + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH)
    button:SetSize(width, Sizes.CONTROL_HEIGHT)
    return button
end

---Creates a borderless, link-style button: accent-colored text that turns white on hover, sized to fit.
---Disabled text uses the muted face.
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
    button:SetDisabledFontObject(Fonts.MUTED)
    button:SetText(text)
    button:SetSize(button:GetTextWidth() + 2 * Spacing.SMALL, Sizes.CONTROL_HEIGHT)
    button:SetScript("OnClick", onClick)
    return button
end

---@class SegmentedControlItem
---@field value any
---@field text string
---@field disabled boolean|nil  When true, the segment is visible but cannot be selected.

---@class SegmentedControl: Frame
---@field SetSelected fun(self: SegmentedControl, value: any)  Highlights the segment holding `value`.
---@field SetItems fun(self: SegmentedControl, items: SegmentedControlItem[])  Updates labels/values; same count as create.
---@field SetEnabled fun(self: SegmentedControl, enabled: boolean)  Enables or disables every segment button.
---@field SetSegmentEnabled fun(self: SegmentedControl, value: any, enabled: boolean)  Locks one segment by its value.

---Creates a row of joined, equally wide buttons of which one is selected at a time.
---Clicking a segment calls `onSelect`; the caller then calls SetSelected to show the new choice.
---A segment with `disabled` stays greyed out when the control is enabled, and ignores clicks.
---@param parent Frame
---@param items SegmentedControlItem[]
---@param onSelect fun(value: any)
---@return SegmentedControl
function Widgets.CreateSegmentedControl(parent, items, onSelect)
    local control = CreateFrame("Frame", nil, parent) --[[@as SegmentedControl]]
    local segments = {}
    local selectedValue
    local controlEnabled = true
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

    ---FeatureSection re-enables descendants. The wrapper keeps a locked segment disabled.
    ---@param segment Button
    local function ApplySegmentState(segment)
        segment:SetEnabled(controlEnabled)
        if not controlEnabled then
            -- Parent FeatureSections already dim inactive content; don't stack another fade.
            segment:SetAlpha(1)
        end
    end

    for _, item in ipairs(items) do
        -- Declare before CreateFlatButton so the click closure captures the local, not a global
        -- (Lua 5.1: a local is not in scope on the RHS of its own declaration).
        local segment
        segment = Widgets.CreateFlatButton(control, "secondary", function()
            if segment.segmentEnabled == false then
                return
            end
            onSelect(segment.value)
        end)
        segment:SetText(item.text)
        segment.value = item.value
        segment.segmentEnabled = item.disabled ~= true
        local rawSetEnabled = segment.SetEnabled
        function segment:SetEnabled(enabled)
            rawSetEnabled(self, enabled == true and self.segmentEnabled ~= false)
        end
        if item.disabled then
            segment:SetEnabled(true)
        end
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
            segment.segmentEnabled = item.disabled ~= true
            ApplySegmentState(segment)
        end
        Relayout()
        ApplySelection()
    end

    ---Locks or unlocks the segment whose value is `value`. Unknown values are ignored.
    ---@param value any
    ---@param enabled boolean
    function control:SetSegmentEnabled(value, enabled)
        for _, segment in ipairs(segments) do
            if segment.value == value then
                segment.segmentEnabled = enabled == true
                ApplySegmentState(segment)
                return
            end
        end
    end

    function control:SetEnabled(enabled)
        controlEnabled = enabled == true
        for _, segment in ipairs(segments) do
            ApplySegmentState(segment)
        end
    end
    return control
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

---Creates a borderless square button showing a single glyph character.
---@param parent Frame
---@param glyph string
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateGlyphButton(parent, glyph, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(Sizes.CLOSE_BUTTON, Sizes.CLOSE_BUTTON)
    Widgets.AddHoverHighlight(button)

    local label = Widgets.CreateLabel(button, Fonts.GLYPH, glyph)
    label:SetPoint("CENTER")

    function button:SetGlyph(text)
        label:SetText(text)
    end

    button:SetScript("OnClick", onClick)
    return button
end

---Creates a borderless square button showing a close glyph.
---@param parent Frame
---@param onClick fun(button: Button)
---@return Button
function Widgets.CreateCloseButton(parent, onClick)
    return Widgets.CreateGlyphButton(parent, Assets.Glyphs.CLOSE, onClick)
end

---@class CollapseButton: Button
---@field SetCollapsed fun(self: CollapseButton, collapsed: boolean)  Shows − when expanded, + when collapsed.

---Creates a borderless square button that toggles between collapse (−) and expand (+) glyphs.
---@param parent Frame
---@param onClick fun(button: Button)
---@return CollapseButton
function Widgets.CreateCollapseButton(parent, onClick)
    local button = Widgets.CreateGlyphButton(parent, Assets.Glyphs.COLLAPSE, onClick) --[[@as CollapseButton]]

    function button:SetCollapsed(collapsed)
        self:SetGlyph(collapsed and Assets.Glyphs.EXPAND or Assets.Glyphs.COLLAPSE)
    end

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
    -- FeatureSection uses SetEnabled; CheckButton only has Enable/Disable natively.
    function box:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end
    return box
end

---Creates a centered numeric input box sized to fit `maxDigits`. Enter clears focus.
---The border turns to the accent color while focused; add focus handlers with HookScript to keep that.
---@param parent Frame
---@param maxDigits integer
---@param options { signed: boolean|nil, decimal: boolean|nil }|nil
---  `signed` allows a leading minus; `decimal` allows one `.`. Callers validate on commit.
---@return EditBox
function Widgets.CreateNumberBox(parent, maxDigits, options)
    options = options or {}
    local signed = options.signed == true
    local decimal = options.decimal == true
    Widgets.EnsureFonts()
    local box = CreateFrame("EditBox", nil, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    box:SetFontObject(Fonts.BODY)
    local letterCount = maxDigits
    if signed then
        letterCount = letterCount + 1
    end
    if decimal then
        letterCount = letterCount + 1
    end
    local width = letterCount * Sizes.INPUT_DIGIT_WIDTH + Sizes.INPUT_TEXT_PADDING
    box:SetSize(width, Sizes.INPUT_HEIGHT)
    box:SetAutoFocus(false)
    -- SetNumeric only allows 0-9; signed/decimal need a free-form box with commit-time parsing.
    box:SetNumeric(not signed and not decimal)
    box:SetMaxLetters(letterCount)
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
