local _, ns = ...
local Assets = ns.Assets
local L = ns.L
local Util = ns.Util

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
    local button = CreateFlatButton(parent, variant, onClick)
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
    local button = CreateFlatButton(parent, "secondary", onClick)
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
        segment = CreateFlatButton(control, "secondary", function()
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
---@field Close fun(self: Dropdown)  Hides the popup and its outside-click catcher.

-- Above MainPanel (DIALOG) and layout-edit chrome (FULLSCREEN_DIALOG) so popups are never covered.
local DROPDOWN_MENU_STRATA = "TOOLTIP"

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

    ---Keeps the popup above the settings panel and any later sibling sections.
    local function RaiseMenu()
        if catcher then
            catcher:SetFrameStrata(DROPDOWN_MENU_STRATA)
            catcher:Raise()
        end
        if menu then
            menu:SetFrameStrata(DROPDOWN_MENU_STRATA)
            -- Raise after the catcher so the list stays clickable above the outside-click shield.
            menu:Raise()
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
            catcher:SetFrameStrata(DROPDOWN_MENU_STRATA)
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
        menu:SetFrameStrata(DROPDOWN_MENU_STRATA)
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
        -- Match the trigger when it lives on a scaled panel (the edit toolbar, or the main panel).
        local uiScale = UIParent:GetEffectiveScale()
        if uiScale and uiScale > 0 then
            menu:SetScale(dropdown:GetEffectiveScale() / uiScale)
        end
        -- Pin both corners so the popup width always matches the trigger, including anchor-stretched triggers.
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -Spacing.TINY)
        menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -Spacing.TINY)
        catcher:Show()
        menu:Show()
        RaiseMenu()
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
        -- Fade the outer frame; keep the trigger opaque so FeatureSection (or this call) does
        -- not stack DISABLED_ALPHA on both. Callers that unlock without RefreshContentInteractive
        -- still restore opacity here.
        trigger:SetAlpha(1)
        self:SetAlpha(dropdownEnabled and 1 or DISABLED_ALPHA)
        if not dropdownEnabled then
            CloseMenu()
        end
    end

    function dropdown:IsEnabled()
        return dropdownEnabled
    end

    ---Hides the popup. Safe when the menu has never been opened.
    function dropdown:Close()
        CloseMenu()
    end

    ApplyItems(items)
    return dropdown
end

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
function Widgets.CreateNumberStepper(parent, minValue, maxValue, step, onValueChanged)
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

    local decrease = CreateFlatButton(stepper, "secondary", function()
        stepper:Commit(current - step)
    end)
    decrease:SetText(Assets.Glyphs.DECREASE)
    decrease:SetNormalFontObject(Fonts.STEPPER)
    decrease:SetDisabledFontObject(Fonts.STEPPER)
    decrease:SetSize(Sizes.INPUT_HEIGHT, Sizes.INPUT_HEIGHT)
    decrease:SetPoint("LEFT")

    local increase = CreateFlatButton(stepper, "secondary", function()
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
    return box
end

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
function Widgets.CreateSlider(parent, minValue, maxValue, step, allowMouseWheelOrOptions)
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
