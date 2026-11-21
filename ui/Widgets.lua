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
    primary = { fill = Colors.MENU_ACCENT, border = Colors.MENU_ACCENT, font = Fonts.ON_ACCENT },
    secondary = { fill = Colors.SURFACE_RAISED, border = Colors.BORDER, font = Fonts.SUBTITLE },
    warning = { fill = Colors.WARNING, border = Colors.WARNING, font = Fonts.ON_ACCENT },
    -- Dark fill with a teal edge. Quieter than a solid accent bar.
    accent = { fill = Colors.SURFACE_RAISED, border = Colors.MENU_ACCENT, font = Fonts.SUBTITLE },
    -- SegmentedControl selected: tinted well + accent edge. Not used by CreateButton.
    segmentSelected = {
        fill = Colors.SEGMENT_SELECTED_FILL,
        border = Colors.MENU_ACCENT,
        font = Fonts.SUBTITLE,
        textColor = Colors.TEXT_PRIMARY,
    },
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

---Lays out a subsection title with a bottom divider inside an existing row.
---Use with `stack:AddRow(Sizes.CONTENT_SECTION_HEADER)`.
---@param row Frame
---@param title string
---@return FontString
function Widgets.LayoutSectionHeader(row, title)
    Widgets.EnsureFonts()
    local label = Widgets.CreateLabel(row, Fonts.SUBTITLE, title)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT")
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))
    return label
end

---@param texture Texture
local function SnapHairline(texture)
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(true)
        texture:SetTexelSnappingBias(0)
    end
end

---@param parent Frame
---@param color table
---@return Texture[]
local function CreatePixelBorder(parent, color)
    local r, g, b, a = Widgets.UnpackColor(color)
    local thickness = Sizes.BORDER
    local edges = {
        { height = thickness, p1 = "TOPLEFT", p2 = "TOPRIGHT" },
        { height = thickness, p1 = "BOTTOMLEFT", p2 = "BOTTOMRIGHT" },
        { width = thickness, p1 = "TOPLEFT", p2 = "BOTTOMLEFT" },
        { width = thickness, p1 = "TOPRIGHT", p2 = "BOTTOMRIGHT" },
    }
    ---@type Texture[]
    local textures = {}
    for index, spec in ipairs(edges) do
        local texture = parent:CreateTexture(nil, "BORDER")
        if spec.width then
            texture:SetWidth(spec.width)
        else
            texture:SetHeight(spec.height)
        end
        texture:SetPoint(spec.p1)
        texture:SetPoint(spec.p2)
        texture:SetColorTexture(r, g, b, a)
        SnapHairline(texture)
        textures[index] = texture
    end
    return textures
end

---@param textures Texture[]
---@param color table
local function SetTexturesColor(textures, color)
    local r, g, b, a = Widgets.UnpackColor(color)
    for _, texture in ipairs(textures) do
        texture:SetColorTexture(r, g, b, a)
    end
end

local function ApplyButtonStyle(button, variant)
    local style = BUTTON_STYLES[variant]
    Widgets.ApplyBackdrop(button, style.fill, style.border)
    button:SetNormalFontObject(style.font)
    button:SetDisabledFontObject(style.font)
    local label = button.GetFontString and button:GetFontString()
    if label then
        local color = style.textColor
        if not color then
            local fontStyle = Assets.FontStyles[style.font]
            color = fontStyle and fontStyle.color
        end
        if color then
            label:SetTextColor(Widgets.UnpackColor(color))
        end
    end
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
    glyphLabel:SetTextColor(Widgets.UnpackColor(Colors.MENU_ACCENT))
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
    local mark = enabled and Colors.MENU_ACCENT or Colors.TEXT_MUTED
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
---@param variant ButtonVariant|nil  "primary" fills with menu accent. "accent" keeps the dark fill and a teal edge. "warning" is amber. Defaults to "secondary".
---@param glyph string|nil  Small mark drawn before the label. Used with "accent".
---@return Button
function Widgets.CreateButton(parent, text, onClick, variant, glyph)
    variant = variant or "secondary"
    local button = Widgets.CreateFlatButton(parent, variant, onClick)
    button:SetText(text)

    if variant == "accent" then
        local wash = button:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        local r, g, b = Widgets.UnpackColor(Colors.MENU_ACCENT)
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
    local caption = Widgets.CreateLabel(button, Fonts.SUBTITLE, text)
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
    button:SetHighlightFontObject(Fonts.SUBTITLE)
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
---@field IsEnabled fun(self: SegmentedControl): boolean
---@field SetSegmentEnabled fun(self: SegmentedControl, value: any, enabled: boolean)  Locks one segment by its value.

---Creates a grooved, equally wide segmented control. One inset thumb marks the selection.
---Clicking a segment calls `onSelect`; the caller then calls SetSelected to show the new choice.
---A segment with `disabled` stays greyed out when the control is enabled, and ignores clicks.
---@param parent Frame
---@param items SegmentedControlItem[]
---@param onSelect fun(value: any)
---@return SegmentedControl
function Widgets.CreateSegmentedControl(parent, items, onSelect)
    Widgets.EnsureFonts()
    local INSET = Sizes.TOGGLE_THUMB_INSET
    local control = CreateFrame("Frame", nil, parent) --[[@as SegmentedControl]]
    local segments = {}
    local selectedValue
    local controlEnabled = true
    local baseLevel = control:GetFrameLevel() + 1

    local track = control:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(Widgets.UnpackColor(Colors.TOGGLE_TRACK_OFF))
    SnapHairline(track)
    CreatePixelBorder(control, Colors.TOGGLE_TRACK_OFF_BORDER)

    local thumb = CreateFrame("Frame", nil, control)
    thumb:SetFrameLevel(baseLevel)
    local thumbFill = thumb:CreateTexture(nil, "BACKGROUND")
    thumbFill:SetAllPoints()
    thumbFill:SetColorTexture(Widgets.UnpackColor(Colors.SEGMENT_THUMB_BG))
    SnapHairline(thumbFill)
    CreatePixelBorder(thumb, Colors.SEGMENT_THUMB_BORDER)
    thumb:Hide()

    local function CanHover(segment)
        return controlEnabled and segment.segmentEnabled ~= false and segment.value ~= selectedValue
    end

    local function ApplySegmentAppearance(segment)
        local hover = segment.hover
        if CanHover(segment) and segment.hovered then
            hover:Show()
            segment.label:SetTextColor(Widgets.UnpackColor(Colors.TEXT_HEADING))
        else
            hover:Hide()
            if segment.segmentEnabled == false then
                segment.label:SetTextColor(Widgets.UnpackColor(Colors.TEXT_HINT))
            elseif segment.value == selectedValue then
                segment.label:SetTextColor(Widgets.UnpackColor(Colors.TEXT_PRIMARY))
            else
                segment.label:SetTextColor(Widgets.UnpackColor(Colors.TEXT_BODY))
            end
        end
    end

    local function ApplyThumb()
        local selected
        for _, segment in ipairs(segments) do
            if segment.value == selectedValue then
                selected = segment
                break
            end
        end
        if not selected then
            thumb:Hide()
            return
        end
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", selected, "TOPLEFT")
        thumb:SetPoint("BOTTOMRIGHT", selected, "BOTTOMRIGHT")
        thumb:Show()
    end

    local function ApplySelection()
        ApplyThumb()
        for _, segment in ipairs(segments) do
            ApplySegmentAppearance(segment)
        end
    end

    local function Relayout()
        local segmentWidth = 0
        for _, segment in ipairs(segments) do
            segmentWidth = math.max(segmentWidth, segment:GetTextWidth() + Sizes.SEGMENT_TEXT_PADDING)
        end
        local segmentHeight = Sizes.CONTROL_HEIGHT - INSET * 2
        for index, segment in ipairs(segments) do
            segment:SetSize(segmentWidth, segmentHeight)
            segment:ClearAllPoints()
            segment:SetPoint("LEFT", control, "LEFT", INSET + (index - 1) * segmentWidth, 0)
        end
        control:SetSize(#segments * segmentWidth + INSET * 2, Sizes.CONTROL_HEIGHT)
        ApplyThumb()
    end

    ---FeatureSection already dims inactive content; keep this control opaque.
    ---@param segment Button
    local function ApplySegmentState(segment)
        segment:SetAlpha(1)
        ApplySegmentAppearance(segment)
    end

    for _, item in ipairs(items) do
        -- Declare before CreateFrame so the click closure captures the local, not a global
        -- (Lua 5.1: a local is not in scope on the RHS of its own declaration).
        local segment
        segment = CreateFrame("Button", nil, control)
        segment:SetFrameLevel(baseLevel + 1)
        local hover = segment:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(Widgets.UnpackColor(Colors.HOVER))
        hover:Hide()
        local label = Widgets.CreateLabel(segment, Fonts.BODY, item.text)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetAllPoints()
        segment.hover = hover
        segment.label = label
        segment.value = item.value
        segment.segmentEnabled = item.disabled ~= true
        segment.hovered = false
        function segment:SetText(text)
            self.label:SetText(text)
        end
        function segment:GetTextWidth()
            return self.label:GetStringWidth()
        end
        -- FeatureSection walks descendants with SetEnabled. Never fade here: locked
        -- segments use TEXT_HINT, and a disabled parent already owns the dim.
        function segment:SetEnabled()
            self:SetAlpha(1)
            ApplySegmentAppearance(self)
        end
        function segment:IsEnabled()
            return true
        end
        segment:SetScript("OnEnter", function()
            segment.hovered = true
            ApplySegmentAppearance(segment)
        end)
        segment:SetScript("OnLeave", function()
            segment.hovered = false
            ApplySegmentAppearance(segment)
        end)
        segment:SetScript("OnClick", function()
            if not controlEnabled or segment.segmentEnabled == false then
                return
            end
            onSelect(segment.value)
        end)
        segments[#segments + 1] = segment
    end
    Relayout()
    ApplySelection()

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

    function control:IsEnabled()
        return controlEnabled
    end

    function control:SetEnabled(enabled)
        controlEnabled = enabled == true
        self:SetAlpha(1)
        for _, segment in ipairs(segments) do
            ApplySegmentState(segment)
        end
    end
    return control
end

---@class ToggleSwitch: Button
---@field SetChecked fun(self: ToggleSwitch, checked: boolean)
---@field IsChecked fun(self: ToggleSwitch): boolean
---@field SetEnabled fun(self: ToggleSwitch, enabled: boolean)
---@field IsEnabled fun(self: ToggleSwitch): boolean

---Creates a compact On/Off switch. Clicking calls `onToggle(not checked)`; the caller then
---calls SetChecked to show the new state (same controlled pattern as CreateSegmentedControl).
---@param parent Frame
---@param onToggle fun(checked: boolean)
---@return ToggleSwitch
function Widgets.CreateToggleSwitch(parent, onToggle)
    local checked = false
    local enabled = true
    local button = CreateFrame("Button", nil, parent) --[[@as ToggleSwitch]]
    button:SetSize(Sizes.TOGGLE_WIDTH, Sizes.TOGGLE_HEIGHT)

    local track = button:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    SnapHairline(track)
    local borders = CreatePixelBorder(button, Colors.TOGGLE_TRACK_OFF_BORDER)

    local inset = Sizes.TOGGLE_THUMB_INSET
    local thumbSize = Sizes.TOGGLE_HEIGHT - 2 * inset
    local thumb = button:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(thumbSize, thumbSize)
    SnapHairline(thumb)
    Widgets.AddHoverHighlight(button)

    local function ApplyVisual()
        if checked then
            track:SetColorTexture(Widgets.UnpackColor(Colors.MENU_ACCENT))
            SetTexturesColor(borders, Colors.MENU_ACCENT)
            thumb:SetColorTexture(Widgets.UnpackColor(Colors.TOGGLE_THUMB_ON))
            thumb:ClearAllPoints()
            thumb:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        else
            track:SetColorTexture(Widgets.UnpackColor(Colors.TOGGLE_TRACK_OFF))
            SetTexturesColor(borders, Colors.TOGGLE_TRACK_OFF_BORDER)
            thumb:SetColorTexture(Widgets.UnpackColor(Colors.TOGGLE_THUMB_OFF))
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", button, "LEFT", inset, 0)
        end
    end

    function button:IsChecked()
        return checked
    end

    function button:SetChecked(value)
        checked = value == true
        ApplyVisual()
    end

    function button:IsEnabled()
        return enabled
    end

    function button:SetEnabled(isEnabled)
        enabled = isEnabled == true
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    end

    button:SetScript("OnClick", function()
        if not enabled then
            return
        end
        onToggle(not checked)
    end)

    ApplyVisual()
    return button
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

    local label = Widgets.CreateLabel(button, Fonts.SUBTITLE)
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
    box:SetFontObject(Fonts.SUBTITLE)
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
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.MENU_ACCENT))
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
