local _, ns = ...
local L = ns.L
local Util = ns.Util
local Assets = ns.Assets
local Combat = ns.Api.Combat
local FloatingWindow = ns.FloatingWindow
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local LayoutEditor = {}
ns.LayoutEditor = LayoutEditor

---@alias LayoutPosition FloatingWindowPosition

---@class LayoutElementDef
---@field id string  Stable id; use "Feature:instance" for multi-instance (e.g. "AuraTracker:1").
---@field label string  Identifying label shown while editing.
---@field frame Frame  Outer layout frame to move (not a protected child).
---@field global boolean  When true, participates in global layout edit mode.
---@field isEnabled fun(): boolean  Feature toggle; disabled elements are skipped.
---@field getPosition fun(): LayoutPosition
---@field setPosition fun(position: LayoutPosition)
---@field onEditBegin fun()  Show a preview and prepare for dragging.
---@field onEditEnd fun()  Restore normal visibility and mouse behavior.

---@type table<string, LayoutElementDef>
local registry = {}

---@type LayoutElementDef[]|nil
local activeElements = nil
---True when the session was started with BeginGlobal (Refresh rescans the registry).
local sessionGlobal = false
---Guards Refresh against re-entry from onEditEnd → module Update callbacks.
local refreshing = false
---@type table<string, Frame>
local overlays = {}
---@type table<string, string>
local savedStrata = {}
local dimmer = nil
local doneBar = nil
local combatListening = false

-- Dimmer < settings chrome < editable floating UI (front-most during edit).
local DIMMER_STRATA = "FULLSCREEN"
local CHROME_STRATA = "FULLSCREEN_DIALOG"
local EDIT_STRATA = "TOOLTIP"
local MAIN_PANEL_STRATA_KEY = "__MainPanel"

---@return Frame|nil
local function GetMainPanelFrame()
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.GetFrame then
        return nil
    end
    return mainPanel:GetFrame()
end

---Keeps the settings panel usable (and undimmed) while layout editing.
local function RaiseMainPanel()
    local frame = GetMainPanelFrame()
    if not frame or not frame:IsShown() then
        return
    end
    savedStrata[MAIN_PANEL_STRATA_KEY] = frame:GetFrameStrata()
    frame:SetFrameStrata(CHROME_STRATA)
    frame:Raise()
end

local function RestoreMainPanel()
    local strata = savedStrata[MAIN_PANEL_STRATA_KEY]
    savedStrata[MAIN_PANEL_STRATA_KEY] = nil
    if not strata then
        return
    end
    local frame = GetMainPanelFrame()
    if frame then
        frame:SetFrameStrata(strata)
    end
end

LayoutEditor.IsValidPosition = ns.Position.IsValid

LayoutEditor.ApplyPosition = FloatingWindow.ApplyPosition
LayoutEditor.ReadPosition = FloatingWindow.ReadPosition

---@return boolean
function LayoutEditor.IsEditing()
    return activeElements ~= nil
end

---@param def LayoutElementDef
function LayoutEditor.Register(def)
    assert(type(def) == "table", "LayoutEditor.Register requires a definition")
    assert(type(def.id) == "string" and def.id ~= "", "Layout element id required")
    assert(type(def.label) == "string", "Layout element label required")
    assert(def.frame ~= nil, "Layout element frame required")
    assert(type(def.isEnabled) == "function", "Layout element isEnabled required")
    assert(type(def.getPosition) == "function", "Layout element getPosition required")
    assert(type(def.setPosition) == "function", "Layout element setPosition required")
    assert(type(def.onEditBegin) == "function", "Layout element onEditBegin required")
    assert(type(def.onEditEnd) == "function", "Layout element onEditEnd required")
    registry[def.id] = def
end

---@param id string
function LayoutEditor.Unregister(id)
    registry[id] = nil
end

local function DestroyOverlay(id)
    local overlay = overlays[id]
    if not overlay then
        return
    end
    overlay:SetScript("OnDragStart", nil)
    overlay:SetScript("OnDragStop", nil)
    overlay:Hide()
    overlay:SetParent(nil)
    overlays[id] = nil
end

---One static full-screen veil; shown/hidden with edit mode (no OnUpdate).
---@return Frame
local function EnsureDimmer()
    if dimmer then
        return dimmer
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata(DIMMER_STRATA)
    frame:EnableMouse(true)
    frame:Hide()

    local veil = frame:CreateTexture(nil, "BACKGROUND")
    veil:SetAllPoints(frame)
    veil:SetColorTexture(Widgets.UnpackColor(Colors.LAYOUT_EDIT_DIMMER))

    dimmer = frame
    return frame
end

local function EnsureDoneBar()
    if doneBar then
        return doneBar
    end
    local bar = Widgets.CreateSurface(UIParent, Colors.BG, Colors.ACCENT)
    -- Same front strata as the previews so Raise() can keep Done clickable on top.
    bar:SetFrameStrata(EDIT_STRATA)
    bar:SetToplevel(true)
    bar:EnableMouse(true)
    bar:Hide()

    local button = Widgets.CreateButton(bar, L.LAYOUT_EDIT_DONE, function()
        LayoutEditor.End()
    end, "primary")
    button:SetNormalFontObject(Fonts.LAYOUT_EDIT_DONE)
    button:SetDisabledFontObject(Fonts.LAYOUT_EDIT_DONE)
    local width = math.max(
        button:GetTextWidth() + Sizes.LAYOUT_EDIT_DONE_TEXT_PADDING,
        Sizes.LAYOUT_EDIT_DONE_MIN_WIDTH
    )
    button:SetSize(width, Sizes.LAYOUT_EDIT_DONE_HEIGHT)
    local pad = Spacing.LARGE
    bar:SetSize(button:GetWidth() + 2 * pad, button:GetHeight() + 2 * pad)
    button:SetPoint("CENTER")
    bar:SetPoint("TOP", UIParent, "TOP", 0, -Spacing.XLARGE)

    doneBar = bar
    return bar
end

---Labels sit on the element overlay, so cancel the element's scale and match the main panel instead.
---@param overlay Frame
---@param frame Frame
local function ApplyLabelScale(overlay, frame)
    local label = overlay.label
    if not label then
        return
    end
    local parentScale = frame:GetEffectiveScale()
    if not parentScale or parentScale <= 0 then
        return
    end
    local menuScale = (ns.MainPanel and ns.MainPanel.db and ns.MainPanel.db.scale) or 1
    local desired = UIParent:GetEffectiveScale() * menuScale
    label:SetScale(desired / parentScale)
end

---@param def LayoutElementDef
---@return Frame
local function EnsureOverlay(def)
    local overlay = overlays[def.id]
    if overlay then
        return overlay
    end

    overlay = CreateFrame("Frame", nil, def.frame, Assets.Templates.BACKDROP)
    overlay:SetAllPoints(def.frame)
    overlay:SetFrameStrata(EDIT_STRATA)
    overlay:SetFrameLevel(def.frame:GetFrameLevel() + 50)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetBackdrop({
        edgeFile = Assets.Textures.WHITE,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    overlay:SetBackdropColor(0, 0, 0, 0)
    overlay:SetBackdropBorderColor(Widgets.UnpackColor(Colors.LAYOUT_EDIT_OUTLINE))

    local label = Widgets.CreateLabel(overlay, Fonts.SMALL_MUTED, def.label)
    label:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", 0, Spacing.TINY)
    label:SetTextColor(Widgets.UnpackColor(Colors.LAYOUT_EDIT_LABEL))
    overlay.label = label

    overlay:SetScript("OnDragStart", function()
        if Combat.IsLockedDown() then
            LayoutEditor.End()
            return
        end
        def.frame:SetMovable(true)
        def.frame:SetClampedToScreen(true)
        def.frame:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function()
        def.frame:StopMovingOrSizing()
        if Combat.IsLockedDown() then
            LayoutEditor.End()
            return
        end
        local position = LayoutEditor.ReadPosition(def.frame)
        def.setPosition(position)
        -- Re-apply as a clean UIParent anchor; StartMoving can leave mixed relative anchors.
        LayoutEditor.ApplyPosition(def.frame, def.getPosition())
    end)

    overlays[def.id] = overlay
    return overlay
end

local function ListenForCombat()
    if combatListening then
        return
    end
    combatListening = true
    Combat.OnEnter(function()
        if LayoutEditor.IsEditing() then
            LayoutEditor.End()
        end
    end)
end

---@param def LayoutElementDef
local function AttachElement(def)
    def.onEditBegin()
    LayoutEditor.ApplyPosition(def.frame, def.getPosition())
    savedStrata[def.id] = def.frame:GetFrameStrata()
    def.frame:SetFrameStrata(EDIT_STRATA)
    local overlay = EnsureOverlay(def)
    overlay:SetParent(def.frame)
    overlay:SetAllPoints(def.frame)
    ApplyLabelScale(overlay, def.frame)
    overlay:Show()
end

---@param def LayoutElementDef
local function DetachElement(def)
    if def.frame.StopMovingOrSizing then
        def.frame:StopMovingOrSizing()
    end
    DestroyOverlay(def.id)
    local strata = savedStrata[def.id]
    if strata then
        def.frame:SetFrameStrata(strata)
        savedStrata[def.id] = nil
    end
    def.onEditEnd()
end

local function RaiseEditChrome()
    if not activeElements then
        return
    end
    for _, def in ipairs(activeElements) do
        def.frame:Raise()
    end
    if doneBar and doneBar:IsShown() then
        doneBar:Raise()
    end
end

---@param elements LayoutElementDef[]
---@param isGlobal boolean
---@return boolean
local function BeginSession(elements, isGlobal)
    if LayoutEditor.IsEditing() then
        LayoutEditor.End()
    end
    if Combat.IsInCombat() or Combat.IsLockedDown() then
        Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
        return false
    end
    if #elements == 0 then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return false
    end

    ListenForCombat()
    sessionGlobal = isGlobal == true
    activeElements = elements
    EnsureDimmer():Show()
    -- Panel above the dimmer first; editable frames are raised last so they sit in front.
    RaiseMainPanel()
    for _, def in ipairs(elements) do
        AttachElement(def)
    end
    RaiseEditChrome()
    local bar = EnsureDoneBar()
    bar:Show()
    bar:Raise()
    return true
end

---@return LayoutElementDef[]
local function CollectGlobalElements()
    local elements = {}
    for _, def in pairs(registry) do
        if def.global and def.isEnabled() then
            elements[#elements + 1] = def
        end
    end
    table.sort(elements, function(a, b)
        return a.id < b.id
    end)
    return elements
end

---Enters global edit mode for every registered, enabled, global element.
---@return boolean
function LayoutEditor.BeginGlobal()
    return BeginSession(CollectGlobalElements(), true)
end

---Enters edit mode for one or more registered elements (e.g. boss-specific UI).
---@param idOrIds string|string[]
---@return boolean
function LayoutEditor.BeginLocal(idOrIds)
    local ids = type(idOrIds) == "table" and idOrIds or { idOrIds }
    local elements = {}
    for _, id in ipairs(ids) do
        local def = registry[id]
        if def and def.isEnabled() then
            elements[#elements + 1] = def
        end
    end
    if #elements == 0 then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return false
    end
    return BeginSession(elements, false)
end

---Re-syncs the current edit session with each element's isEnabled().
---Shows newly enabled elements and hides ones that became disabled (e.g. aura toggle in preview).
function LayoutEditor.Refresh()
    if not activeElements or refreshing then
        return
    end
    refreshing = true

    local desired
    if sessionGlobal then
        desired = CollectGlobalElements()
    else
        desired = {}
        for _, def in ipairs(activeElements) do
            if def.isEnabled() then
                desired[#desired + 1] = def
            end
        end
    end

    local desiredById = {}
    for _, def in ipairs(desired) do
        desiredById[def.id] = true
    end
    local previousById = {}
    for _, def in ipairs(activeElements) do
        previousById[def.id] = def
    end

    for _, def in ipairs(activeElements) do
        if not desiredById[def.id] then
            DetachElement(def)
        end
    end
    for _, def in ipairs(desired) do
        if not previousById[def.id] then
            AttachElement(def)
        end
    end

    activeElements = desired

    if #desired == 0 then
        sessionGlobal = false
        activeElements = nil
        RestoreMainPanel()
        if dimmer then
            dimmer:Hide()
        end
        if doneBar then
            doneBar:Hide()
        end
        refreshing = false
        return
    end

    RaiseEditChrome()
    refreshing = false
end

---Leaves edit mode, restores module visibility, and tears down overlays.
function LayoutEditor.End()
    if not activeElements then
        return
    end
    local elements = activeElements
    activeElements = nil
    sessionGlobal = false

    for _, def in ipairs(elements) do
        if def.frame.StopMovingOrSizing then
            def.frame:StopMovingOrSizing()
        end
        DestroyOverlay(def.id)
        local strata = savedStrata[def.id]
        if strata then
            def.frame:SetFrameStrata(strata)
            savedStrata[def.id] = nil
        end
    end
    RestoreMainPanel()
    if dimmer then
        dimmer:Hide()
    end
    if doneBar then
        doneBar:Hide()
    end

    -- Restore after overlays are gone so modules can re-apply mouse/visibility safely.
    for _, def in ipairs(elements) do
        def.onEditEnd()
    end
end
