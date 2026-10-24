local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local CollapsiblePanel = ns.CollapsiblePanel
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Util = ns.Util
local Slider = ns.Slider
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local PANEL_WIDTH = 700
local PANEL_HEIGHT = 600
local SIDEBAR_WIDTH = 160
-- Title/toggle band, plus gap above the divider so the line sits clearly below the title.
local PAGE_HEADER_HEIGHT = Sizes.CONTROL_ROW_HEIGHT + Spacing.LARGE
-- Matches FeatureSection's disabled content fade.
local PAGE_DISABLED_ALPHA = 0.4
local SCALE_MIN = 0.7
local SCALE_MAX = 1.5
local SCALE_STEP = 0.05

---@class PanelGroup
---@field order integer  Position in the sidebar; unique per group.
---@field title string

---@class PanelSectionDef
---@field title string  Shown in the sidebar. Also used as the page header unless `headerTitle` is set.
---@field headerTitle string|nil  Page header title when it should name the sub-feature instead of `title`.
---@field group PanelGroup  The sidebar lists the section under this group's title.
---@field build fun(container: Frame): number|nil  Fills the container and returns its content height. Runs once, the first time the page is on screen.
---@field enabled boolean|nil  Initial On/Off when `onEnabledChanged` is set. Defaults to true.
---@field onEnabledChanged fun(enabled: boolean)|nil  When set, the page header shows an On/Off toggle and gates the body.
---@field tooltip string|nil  Shown when hovering the page title.

local MainPanel = ns.Modules.New("MainPanel", {
    defaults = {
        scale = 1,
        ---@type FloatingWindowPosition
        layoutInspectorPosition = { point = "CENTER", relativePoint = "CENTER", x = 260, y = 40 },
    },
})
ns.MainPanel = MainPanel

local sectionDefs = {}
local panel

---@type fun(scale: number)[]
local scaleListeners = {}

---Snapped main-panel UI scale (same range as the header slider).
---@return number
function MainPanel.GetScale()
    local scale = MainPanel.db and MainPanel.db.scale or 1
    return Util.Snap(scale, SCALE_MIN, SCALE_MAX, SCALE_STEP)
end

---Subscribes to scale changes from the header slider. Returns an unsubscribe function.
---@param callback fun(scale: number)
---@return fun()
function MainPanel.OnScaleChanged(callback)
    assert(type(callback) == "function", "MainPanel.OnScaleChanged requires a callback")
    table.insert(scaleListeners, callback)
    local removed = false
    return function()
        if removed then
            return
        end
        removed = true
        for index, candidate in ipairs(scaleListeners) do
            if candidate == callback then
                table.remove(scaleListeners, index)
                return
            end
        end
    end
end

local function NotifyScaleChanged(scale)
    local snapshot = {}
    for i = 1, #scaleListeners do
        snapshot[i] = scaleListeners[i]
    end
    for i = 1, #snapshot do
        snapshot[i](scale)
    end
end

local function CreateGroupHeader(sidebar, group)
    local header = CreateFrame("Frame", nil, sidebar)

    local label = Widgets.CreateLabel(header, Fonts.NAV_GROUP, group.title)
    label:SetPoint("LEFT", Spacing.LARGE, 0)
    label:SetWordWrap(false)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(Sizes.BORDER)
    line:SetPoint("LEFT", label, "RIGHT", Spacing.MEDIUM, 0)
    line:SetPoint("RIGHT", -Spacing.LARGE, 0)
    line:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    return header
end

local function CreateNavButton(sidebar, def)
    local button = CreateFrame("Button", nil, sidebar)
    Widgets.AddHoverHighlight(button)

    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetColorTexture(Widgets.UnpackColor(Colors.SURFACE_RAISED))
    button.selected = selected

    local accent = button:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(Sizes.NAV_ACCENT_WIDTH)
    accent:SetColorTexture(Widgets.UnpackColor(Colors.ACCENT))
    button.accent = accent

    local label = Widgets.CreateLabel(button, Fonts.BODY, def.title)
    label:SetPoint("LEFT", Spacing.LARGE, 0)
    label:SetPoint("RIGHT", -Spacing.LARGE, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button.label = label

    return button
end

local function SetNavSelected(button, isSelected)
    button.selected:SetShown(isSelected)
    button.accent:SetShown(isSelected)
    button.label:SetTextColor(Widgets.UnpackColor(isSelected and Colors.TEXT or Colors.TEXT_MUTED))
end

local function CreateSection(frame, def)
    local section = CreateFrame("Frame", nil, frame.content)
    section:SetPoint("TOPLEFT")
    section:SetPoint("TOPRIGHT")
    -- Header-only pages never run `build`; a 0-tall parent inside the scroll frame culls the header.
    section:SetHeight(PAGE_HEADER_HEIGHT)
    section:Hide()

    local header = CreateFrame("Frame", nil, section)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(PAGE_HEADER_HEIGHT)

    -- Keep title and toggle in the top control band; Spacing.LARGE below is the gap to the line.
    local titleBandCenterY = -Sizes.CONTROL_ROW_HEIGHT / 2

    local title = Widgets.CreateLabel(header, Fonts.HEADER, def.headerTitle or def.title)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", header, "TOPLEFT", 0, titleBandCenterY)
    title:SetWordWrap(false)

    if def.tooltip then
        -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
        local hit = CreateFrame("Frame", nil, header)
        hit:SetPoint("TOPLEFT", title, "TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT")
        hit:EnableMouse(true)
        Widgets.AttachTooltip(hit, "ANCHOR_TOP", function(tooltip)
            tooltip:SetText(def.tooltip)
        end)
    end

    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    body:SetHeight(1)
    section.body = body
    section.bodyHeight = 0
    section.headerHeight = PAGE_HEADER_HEIGHT
    -- Callers may add a compact readout on this row. The title stays left; a toggle, if any, stays right.
    body.header = header
    body.titleLabel = title

    if def.onEnabledChanged then
        local enabled = def.enabled ~= false

        local function ApplyContentInteractive()
            body:SetAlpha(enabled and 1 or PAGE_DISABLED_ALPHA)
            FeatureSection.SetSubtreeInteractive(body, enabled)
        end

        -- Declare before CreateSegmentedControl so the click closure captures the local
        -- (Lua 5.1: a local is not in scope on the RHS of its own declaration).
        local toggle
        toggle = Widgets.CreateSegmentedControl(header, {
            { value = true, text = L.FEATURE_ON },
            { value = false, text = L.FEATURE_OFF },
        }, function(value)
            value = value == true
            if enabled == value then
                ApplyContentInteractive()
                return
            end
            enabled = value
            toggle:SetSelected(enabled)
            ApplyContentInteractive()
            def.onEnabledChanged(enabled)
        end)
        toggle:SetPoint("RIGHT", header, "TOPRIGHT", 0, titleBandCenterY)
        toggle:SetSelected(enabled)

        function body:RefreshContentInteractive()
            ApplyContentInteractive()
        end

        ApplyContentInteractive()
    end

    return section
end

local function UpdateNavSelection(frame)
    for _, section in ipairs(frame.sections) do
        SetNavSelected(section.navButton, section == frame.activeSection)
    end
end

local function SyncActivePageHeight(frame)
    local section = frame.activeSection
    local height = 1
    if section then
        height = math.max(section.headerHeight + section.bodyHeight, 1)
    end
    frame.content:SetHeight(height)
    local scrollFrame = frame.scrollFrame
    if scrollFrame then
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        local range = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0
        local current = scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll() or 0
        if current > range then
            scrollFrame:SetVerticalScroll(range)
        end
    end
end

local function SetSectionBodyHeight(frame, section, height)
    section.bodyHeight = math.max(height, 0)
    section.body:SetHeight(math.max(height, 1))
    section:SetHeight(math.max(section.headerHeight + section.bodyHeight, 1))
    if section == frame.activeSection then
        SyncActivePageHeight(frame)
    end
end

-- Frames created under a hidden page can keep an unresolved rect until they are hidden and shown
-- again, so `build` waits until its page is on screen for the first time.
local function EnsureSectionBuilt(frame, section)
    if not section or section.built or not section:IsVisible() then
        return
    end
    section.built = true
    local body = section.body
    local height = section.def.build and section.def.build(body)
    if type(height) ~= "number" then
        height = 0
    end
    SetSectionBodyHeight(frame, section, height)
    if body.RefreshContentInteractive then
        body:RefreshContentInteractive()
    end
end

---Shows one feature page and hides the others. Resets scroll so each page starts at the top.
local function SelectSection(frame, section)
    if frame.activeSection == section then
        UpdateNavSelection(frame)
        return
    end

    if frame.activeSection then
        frame.activeSection:Hide()
    end
    frame.activeSection = section
    if section then
        section:Show()
        frame.scrollFrame:SetVerticalScroll(0)
    end
    SyncActivePageHeight(frame)
    UpdateNavSelection(frame)
end

-- The nav stack is ordered by group, so a new entry goes after everything in its own and earlier groups.
local function CountEntriesThrough(frame, group)
    local headers, sections = 0, 0
    for other in pairs(frame.groupHeaders) do
        if other.order <= group.order then
            headers = headers + 1
        end
    end
    for _, section in ipairs(frame.sections) do
        if section.group.order <= group.order then
            sections = sections + 1
        end
    end
    return headers, sections
end

local function AddSection(frame, def)
    local group = def.group
    if not frame.groupHeaders[group] then
        local headers, sections = CountEntriesThrough(frame, group)
        local header = CreateGroupHeader(frame.sidebar, group)
        frame.navStack:Insert(headers + sections + 1, header, Sizes.NAV_GROUP_HEIGHT, Spacing.LARGE)
        frame.groupHeaders[group] = header
    end

    local headers, sections = CountEntriesThrough(frame, group)
    local section = CreateSection(frame, def)
    section.group = group
    section.def = def
    section.built = false
    -- Fires on selection, on opening the panel, and on expanding it from collapsed.
    section:HookScript("OnShow", function()
        EnsureSectionBuilt(frame, section)
    end)
    table.insert(frame.sections, sections + 1, section)

    local navButton = CreateNavButton(frame.sidebar, def)
    section.navButton = frame.navStack:Insert(headers + sections + 1, navButton, Sizes.NAV_ROW_HEIGHT)
    navButton:SetScript("OnClick", function()
        SelectSection(frame, section)
    end)

    -- The page exists before `build`, so it may call SetContentHeight right away.
    local body = section.body
    function body:SetContentHeight(height)
        SetSectionBodyHeight(frame, section, height)
    end

    -- Keep the topmost sidebar entry selected when sections register out of group order.
    if not frame.activeSection or frame.sections[1] == section then
        SelectSection(frame, section)
    else
        UpdateNavSelection(frame)
    end
end

local function CreateDivider(parent)
    local divider = parent:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))
    return divider
end

-- Keeps the panel's center where it is on screen; anchor offsets are in the frame's own scale.
local function ApplyScale(frame, scale)
    local oldScale = frame:GetScale()
    if math.abs(oldScale - scale) >= 0.001 then
        local x, y = frame:GetCenter()
        frame:SetScale(scale)
        if x then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * oldScale / scale, y * oldScale / scale)
        end
    end
    NotifyScaleChanged(scale)
end

---Scale slider + label; parented to a chrome frame so the whole group can hide when collapsed.
---Typed entry is off: rescaling moves the control under the cursor, so a textbox is a poor fit.
local function CreateScaleControl(frame, chrome, anchorRight)
    local value = Widgets.CreateLabel(chrome, Fonts.SMALL_MUTED)
    value:SetWidth(Sizes.SLIDER_VALUE_WIDTH)
    value:SetJustifyH("RIGHT")
    value:SetPoint("RIGHT", anchorRight, "LEFT", -Spacing.MEDIUM, 0)

    local slider = Slider.Create(chrome, SCALE_MIN, SCALE_MAX, SCALE_STEP, {
        allowMouseWheel = true,
        allowTypedValue = false,
    })
    slider:SetPoint("RIGHT", value, "LEFT", -Spacing.MEDIUM, 0)

    local label = Widgets.CreateLabel(chrome, Fonts.SMALL_MUTED, L.MAIN_PANEL_SCALE)
    label:SetPoint("RIGHT", slider, "LEFT", -Spacing.MEDIUM, 0)

    local function ShowValue(scale)
        value:SetText(string.format("%d%s", math.floor(scale * 100 + 0.5), L.PERCENT_SUFFIX))
    end

    -- Rescaling moves the slider under the cursor, so a drag only applies the scale on release.
    local pressed = false
    slider:SetScript("OnMouseDown", function()
        pressed = true
    end)
    slider:SetScript("OnMouseUp", function()
        pressed = false
        ApplyScale(frame, MainPanel.db.scale)
    end)

    slider:SetValue(MainPanel.db.scale)
    ShowValue(MainPanel.db.scale)
    slider:SetScript("OnValueChanged", function(_, rawValue)
        local scale = Util.Snap(rawValue, SCALE_MIN, SCALE_MAX, SCALE_STEP)
        MainPanel.db.scale = scale
        ShowValue(scale)
        if not pressed then
            ApplyScale(frame, scale)
        end
    end)
end

local function CreateHeader(frame)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", Sizes.BORDER, -Sizes.BORDER)
    header:SetPoint("TOPRIGHT", -Sizes.BORDER, -Sizes.BORDER)
    header:SetHeight(Sizes.HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(Sizes.HEADER_LOGO, Sizes.HEADER_LOGO)
    logo:SetTexture(Assets.LOGO)

    local title = Widgets.CreateLabel(header, Fonts.TITLE, ns.ADDON_NAME)
    local welcome = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, L.MAIN_PANEL_WELCOME)
    Layout.Row(header, { logo, title, welcome }, Spacing.MEDIUM, Spacing.LARGE)

    local closeButton = Widgets.CreateCloseButton(header, function()
        frame:Hide()
    end)
    closeButton:SetPoint("RIGHT", -Spacing.MEDIUM, 0)

    local collapseButton = Widgets.CreateCollapseButton(header, function()
        frame.collapse:Toggle()
    end)
    collapseButton:SetPoint("RIGHT", closeButton, "LEFT", -Spacing.MEDIUM, 0)

    -- Stays visible while collapsed so layout editing stays reachable from the title bar.
    local editLayout = Widgets.CreateLayoutEditButton(header, L.LAYOUT_EDIT, function()
        if Combat.IsInCombat() or Combat.IsLockedDown() then
            Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
            return
        end
        LayoutEditor.BeginGlobal()
    end)
    editLayout:SetPoint("RIGHT", collapseButton, "LEFT", -Spacing.MEDIUM, 0)

    local scaleChrome = CreateFrame("Frame", nil, header)
    scaleChrome:SetPoint("TOPLEFT")
    scaleChrome:SetPoint("BOTTOMRIGHT", editLayout, "BOTTOMLEFT", -Spacing.MEDIUM, 0)
    CreateScaleControl(frame, scaleChrome, editLayout)

    local divider = CreateDivider(header)
    divider:SetHeight(Sizes.BORDER)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    header.welcome = welcome
    header.scaleChrome = scaleChrome
    header.collapseButton = collapseButton
    header.divider = divider
    return header
end

local function CreateBody(frame, header)
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -Sizes.BORDER)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Sizes.BORDER, Sizes.BORDER)

    local sidebar = Widgets.CreateSurface(body, Colors.SURFACE)
    sidebar:SetPoint("TOPLEFT")
    sidebar:SetPoint("BOTTOMLEFT")
    sidebar:SetWidth(SIDEBAR_WIDTH)

    local sidebarDivider = CreateDivider(sidebar)
    sidebarDivider:SetWidth(Sizes.BORDER)
    sidebarDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
    sidebarDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")

    local scrollFrame = CreateFrame("ScrollFrame", nil, body)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", Spacing.XLARGE, -Spacing.LARGE)
    scrollFrame:SetPoint(
        "BOTTOMRIGHT",
        body,
        "BOTTOMRIGHT",
        -(Spacing.XLARGE + Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL),
        Spacing.LARGE
    )

    local scrollBar = CreateFrame("EventFrame", nil, body, Assets.Templates.SCROLL_BAR)
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", Spacing.MEDIUM, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", Spacing.MEDIUM, 0)
    -- Installs its own scroll and range handlers, so ours must be hooked afterwards.
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    return body, sidebar, scrollFrame, content
end

local function CreatePanel()
    local frame = Widgets.CreateSurface(UIParent, Colors.BG, Colors.BORDER, ns.ADDON_NAME .. "Panel")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetScale(Util.Snap(MainPanel.db.scale, SCALE_MIN, SCALE_MAX, SCALE_STEP))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    local header = CreateHeader(frame)
    local body, sidebar, scrollFrame, content = CreateBody(frame, header)
    frame.sidebar = sidebar
    frame.navStack = Layout.Stack(sidebar, { paddingY = Spacing.MEDIUM })
    frame.scrollFrame = scrollFrame
    frame.content = content

    scrollFrame:HookScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)

    frame.collapse = CollapsiblePanel.Attach({
        frame = frame,
        body = body,
        header = header,
        expandedChrome = { header.welcome, header.scaleChrome, header.divider },
        collapsedWidth = Sizes.COLLAPSED_PANEL_WIDTH,
        collapsedHeight = Sizes.COLLAPSED_PANEL_HEIGHT,
        onExpandedChanged = function(expanded)
            header.collapseButton:SetCollapsed(not expanded)
        end,
    })
    header.collapseButton:SetCollapsed(false)

    frame.sections = {}
    frame.groupHeaders = {}
    frame.activeSection = nil

    -- Lets the Escape key close the panel.
    table.insert(UISpecialFrames, frame:GetName())

    for _, def in ipairs(sectionDefs) do
        AddSection(frame, def)
    end

    return frame
end

---Adds a feature settings page to the panel. `def.build` runs the first time the page is visible,
---so modules must not depend on its widgets existing before then. The container passed to it also has
---`container:SetContentHeight(height)` for when its content height changes later.
---`container.header` is the title row and `container.titleLabel` is the title on its left.
---An On/Off toggle, when present, occupies the header's right side.
---When `onEnabledChanged` is set, the page header shows an On/Off toggle and the container also has
---`container:RefreshContentInteractive()` to re-apply enable/disable after rebuilding controls.
---@param def PanelSectionDef
function MainPanel:RegisterSection(def)
    assert(type(def) == "table" and type(def.title) == "string", "RegisterSection requires a title")
    local group = def.group
    assert(
        type(group) == "table" and type(group.order) == "number" and type(group.title) == "string",
        "RegisterSection requires a group with an order and a title"
    )
    table.insert(sectionDefs, def)
    if panel then
        AddSection(panel, def)
    end
end

function MainPanel:Toggle()
    if not panel then
        panel = CreatePanel()
    end
    panel:SetShown(not panel:IsShown())
end

---Returns the settings panel frame once it has been created; nil before the first open.
---@return Frame|nil
function MainPanel:GetFrame()
    return panel
end

function MainPanel:OnEnable()
    ns.Api.Slash.Register("NEWERATOOLS", { "/netools", "/nets" }, function()
        self:Toggle()
    end)
end
