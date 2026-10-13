local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Util = ns.Util
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local PANEL_WIDTH = 700
local PANEL_HEIGHT = 600
local SIDEBAR_WIDTH = 160
local SECTION_HEADER_HEIGHT = 28
local SECTION_SPACING = 24
local SCALE_MIN = 0.7
local SCALE_MAX = 1.5
local SCALE_STEP = 0.05

---@class PanelGroup
---@field order integer  Position in the sidebar; unique per group.
---@field title string

---@class PanelSectionDef
---@field title string  Shown in the sidebar and as the section header.
---@field group PanelGroup  The sidebar lists the section under this group's title.
---@field build fun(container: Frame): number|nil  Fills the container and returns its content height.

local MainPanel = ns.Modules.New("MainPanel", {
    defaults = {
        scale = 1,
    },
})
ns.MainPanel = MainPanel

local sectionDefs = {}
local panel

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

    local header = Widgets.CreateLabel(section, Fonts.HEADER, def.title)
    header:SetPoint("TOPLEFT", 0, -Spacing.SMALL)

    local dividerTop = -(SECTION_HEADER_HEIGHT - Spacing.TINY)
    local divider = section:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 0, dividerTop)
    divider:SetPoint("TOPRIGHT", 0, dividerTop)
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", 0, -SECTION_HEADER_HEIGHT)
    body:SetPoint("TOPRIGHT", 0, -SECTION_HEADER_HEIGHT)
    body:SetHeight(1)
    section.body = body

    return section
end

local function UpdateSelection(frame)
    local scroll = frame.scrollFrame:GetVerticalScroll()
    local active

    -- A clicked section near the bottom may not reach the top of the view, so honor
    -- the click until the user scrolls away from where it left the view.
    if frame.clickedSection and math.abs(scroll - frame.clickedScroll) < 1 then
        active = frame.clickedSection
    else
        frame.clickedSection = nil
        for _, section in ipairs(frame.sections) do
            if frame.sectionStack:GetOffset(section) <= scroll + 1 then
                active = section
            end
        end
    end

    for _, section in ipairs(frame.sections) do
        SetNavSelected(section.navButton, section == active)
    end
end

local function ScrollToSection(frame, section)
    local scrollFrame = frame.scrollFrame
    local offset = frame.sectionStack:GetOffset(section)
    scrollFrame:SetVerticalScroll(math.min(offset, scrollFrame:GetVerticalScrollRange()))
    frame.clickedSection = section
    frame.clickedScroll = scrollFrame:GetVerticalScroll()
    UpdateSelection(frame)
end

local function OnSectionsResized(frame)
    frame.content:SetHeight(math.max(frame.sectionStack:GetHeight(), 1))
    UpdateSelection(frame)
end

local function SetSectionBodyHeight(frame, section, height)
    section.body:SetHeight(math.max(height, 1))
    frame.sectionStack:SetEntryHeight(section, SECTION_HEADER_HEIGHT + height)
    OnSectionsResized(frame)
end

-- Both stacks are ordered by group, so a new entry goes after everything in its own and earlier groups.
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
    frame.sectionStack:Insert(sections + 1, section, SECTION_HEADER_HEIGHT)
    table.insert(frame.sections, sections + 1, section)

    local navButton = CreateNavButton(frame.sidebar, def)
    section.navButton = frame.navStack:Insert(headers + sections + 1, navButton, Sizes.NAV_ROW_HEIGHT)
    navButton:SetScript("OnClick", function()
        ScrollToSection(frame, section)
    end)

    -- The section is already in the stack, so `build` may call SetContentHeight right away.
    local body = section.body
    function body:SetContentHeight(height)
        SetSectionBodyHeight(frame, section, height)
    end

    local height = def.build and def.build(body)
    if type(height) == "number" then
        SetSectionBodyHeight(frame, section, height)
    else
        OnSectionsResized(frame)
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
    if math.abs(oldScale - scale) < 0.001 then
        return
    end
    local x, y = frame:GetCenter()
    frame:SetScale(scale)
    if x then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * oldScale / scale, y * oldScale / scale)
    end
end

local function CreateScaleControl(frame, header, closeButton)
    local value = Widgets.CreateLabel(header, Fonts.SMALL_MUTED)
    value:SetWidth(Sizes.SLIDER_VALUE_WIDTH)
    value:SetJustifyH("RIGHT")
    value:SetPoint("RIGHT", closeButton, "LEFT", -Spacing.MEDIUM, 0)

    local slider = Widgets.CreateSlider(header, SCALE_MIN, SCALE_MAX, SCALE_STEP, true)
    slider:SetPoint("RIGHT", value, "LEFT", -Spacing.MEDIUM, 0)

    local label = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, L.MAIN_PANEL_SCALE)
    label:SetPoint("RIGHT", slider, "LEFT", -Spacing.MEDIUM, 0)

    local editLayout = Widgets.CreateButton(header, L.LAYOUT_EDIT, function()
        if Combat.IsInCombat() or Combat.IsLockedDown() then
            Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
            return
        end
        LayoutEditor.BeginGlobal()
    end)
    editLayout:SetPoint("RIGHT", label, "LEFT", -Spacing.MEDIUM, 0)

    local function ShowValue(scale)
        value:SetFormattedText(L.MAIN_PANEL_SCALE_PERCENT, math.floor(scale * 100 + 0.5))
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
    CreateScaleControl(frame, header, closeButton)

    local divider = CreateDivider(header)
    divider:SetHeight(Sizes.BORDER)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    return header
end

local function CreateSidebar(frame, header)
    local sidebar = Widgets.CreateSurface(frame, Colors.SURFACE)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -Sizes.BORDER)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Sizes.BORDER, Sizes.BORDER)
    sidebar:SetWidth(SIDEBAR_WIDTH)

    local divider = CreateDivider(sidebar)
    divider:SetWidth(Sizes.BORDER)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")

    return sidebar
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

    local sidebar = CreateSidebar(frame, header)
    frame.sidebar = sidebar
    frame.navStack = Layout.Stack(sidebar, { paddingY = Spacing.MEDIUM })

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", Spacing.XLARGE, -Spacing.LARGE)
    scrollFrame:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -(Spacing.XLARGE + Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL),
        Spacing.LARGE
    )
    frame.scrollFrame = scrollFrame

    local scrollBar = CreateFrame("EventFrame", nil, frame, Assets.Templates.SCROLL_BAR)
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", Spacing.MEDIUM, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", Spacing.MEDIUM, 0)
    -- Installs its own scroll and range handlers, so ours must be hooked afterwards.
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content
    frame.sectionStack = Layout.Stack(content, { spacing = SECTION_SPACING })

    scrollFrame:HookScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)
    scrollFrame:HookScript("OnVerticalScroll", function()
        UpdateSelection(frame)
    end)

    frame.sections = {}
    frame.groupHeaders = {}

    -- Lets the Escape key close the panel.
    table.insert(UISpecialFrames, frame:GetName())

    for _, def in ipairs(sectionDefs) do
        AddSection(frame, def)
    end

    return frame
end

---Adds a section to the panel. The container passed to `def.build` also has
---`container:SetContentHeight(height)` for when its content height changes later.
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
    ns.Api.Slash.Register("NEWERATOOLS", { "/netools", "/ne2s" }, function()
        self:Toggle()
    end)
end
