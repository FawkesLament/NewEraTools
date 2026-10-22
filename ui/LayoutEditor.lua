local _, ns = ...
local L = ns.L
local Util = ns.Util
local Assets = ns.Assets
local Combat = ns.Api.Combat
local FloatingWindow = ns.FloatingWindow
local LayoutCoordinateInspector = ns.LayoutCoordinateInspector
local Dropdown = ns.Dropdown
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
---@field global boolean  When true, participates in the common UI editing scope.
---@field isEnabled fun(): boolean  Feature toggle; disabled elements are skipped.
---@field getPosition fun(): LayoutPosition
---@field setPosition fun(position: LayoutPosition)
---@field getDefaultPosition fun(): LayoutPosition  Factory default anchor; used by Reset Position.
---@field onEditBegin fun()  Show a preview and prepare for dragging.
---@field onEditEnd fun()  Restore normal visibility and mouse behavior.

---Built-in scope: every registered element with `global = true`.
local COMMON_SCOPE_ID = "common"

---@class LayoutScopeDef
---@field id string  Stable id, unique among scopes. "common" is reserved.
---@field label string  Name shown in the editing-scope selector.
---@field order number|nil  Sort key after the common scope. Defaults to 0.
---@field elementIds string[]  Layout element ids edited while this scope is active.
---@field prepare fun()|nil  Create frames so those elements are registered before the scope is shown.

---@class LayoutScope
---@field id string
---@field label string
---@field order number
---@field elementIds string[]
---@field prepare fun()|nil

LayoutEditor.COMMON_SCOPE_ID = COMMON_SCOPE_ID

---@type table<string, LayoutElementDef>
local registry = {}

---@type table<string, LayoutScope>
local scopes = {}

---@type LayoutElementDef[]|nil
local activeElements = nil
---@type string|nil
local activeScopeId = nil
---Guards Refresh against re-entry from onEditEnd → module Update callbacks.
local refreshing = false
---@type table<string, Frame>
local overlays = {}
---@type table<string, string>
local savedStrata = {}
---@type string|nil
local selectedId = nil
local dimmer = nil
local toolbar = nil
---@type Dropdown|nil
local scopeDropdown = nil
local combatListening = false
local scaleListening = false
local UpdateToolbar

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
    return activeScopeId ~= nil
end

---@return string|nil
function LayoutEditor.GetActiveScopeId()
    return activeScopeId
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
    assert(type(def.getDefaultPosition) == "function", "Layout element getDefaultPosition required")
    assert(type(def.onEditBegin) == "function", "Layout element onEditBegin required")
    assert(type(def.onEditEnd) == "function", "Layout element onEditEnd required")
    registry[def.id] = def
end

---@param id string
function LayoutEditor.Unregister(id)
    registry[id] = nil
end

---@param def LayoutScopeDef
function LayoutEditor.RegisterScope(def)
    assert(type(def) == "table", "LayoutEditor.RegisterScope requires a definition")
    assert(type(def.id) == "string" and def.id ~= "", "Layout scope id required")
    assert(def.id ~= COMMON_SCOPE_ID, "Layout scope id 'common' is reserved")
    assert(type(def.label) == "string" and def.label ~= "", "Layout scope label required")
    assert(type(def.elementIds) == "table", "Layout scope elementIds required")
    assert(def.prepare == nil or type(def.prepare) == "function", "Layout scope prepare must be a function")
    local elementIds = {}
    for index, id in ipairs(def.elementIds) do
        assert(type(id) == "string" and id ~= "", "Layout scope element id required")
        elementIds[index] = id
    end
    scopes[def.id] = {
        id = def.id,
        label = def.label,
        order = def.order or 0,
        elementIds = elementIds,
        prepare = def.prepare,
    }
    if LayoutEditor.IsEditing() then
        UpdateToolbar()
    end
end

---Common UI first, then module scopes by order and id.
---@return { id: string, label: string }[]
function LayoutEditor.GetScopes()
    local list = {
        { id = COMMON_SCOPE_ID, label = L.LAYOUT_EDIT_SCOPE_COMMON },
    }
    local modules = {}
    for _, scope in pairs(scopes) do
        modules[#modules + 1] = scope
    end
    table.sort(modules, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.id < b.id
    end)
    for _, scope in ipairs(modules) do
        list[#list + 1] = { id = scope.id, label = scope.label }
    end
    return list
end

---@param overlay Frame
local function ApplyOverlayBorder(overlay)
    local selected = overlay.elementId ~= nil and overlay.elementId == selectedId
    local color = selected and Colors.LAYOUT_EDIT_OUTLINE_SELECTED or Colors.LAYOUT_EDIT_OUTLINE
    local edgeSize = selected and Sizes.LAYOUT_EDIT_OUTLINE_EDGE_SELECTED or Sizes.LAYOUT_EDIT_OUTLINE_EDGE
    overlay:SetBackdrop({
        edgeFile = Assets.Textures.WHITE,
        edgeSize = edgeSize,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    overlay:SetBackdropColor(0, 0, 0, 0)
    overlay:SetBackdropBorderColor(Widgets.UnpackColor(color))
end

local function ClearSelection()
    local previousId = selectedId
    selectedId = nil
    if previousId and overlays[previousId] then
        ApplyOverlayBorder(overlays[previousId])
    end
    LayoutCoordinateInspector.Hide()
end

---Clears the selected element and hides the coordinate inspector without leaving edit mode.
function LayoutEditor.Deselect()
    ClearSelection()
end

---@param def LayoutElementDef
local function SelectElement(def)
    local previousId = selectedId
    selectedId = def.id
    if previousId and previousId ~= selectedId and overlays[previousId] then
        ApplyOverlayBorder(overlays[previousId])
    end
    if overlays[def.id] then
        ApplyOverlayBorder(overlays[def.id])
    end
    LayoutCoordinateInspector.Show(def)
end

local function DestroyOverlay(id)
    local overlay = overlays[id]
    if not overlay then
        return
    end
    overlay:SetScript("OnDragStart", nil)
    overlay:SetScript("OnDragStop", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
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

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

local function ApplyToolbarScale(scale)
    if toolbar then
        toolbar:SetScale(scale)
    end
end

---Follows the header slider. Safe to call before MainPanel finishes loading.
local function ListenForToolbarScale()
    if scaleListening then
        return
    end
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    scaleListening = true
    mainPanel.OnScaleChanged(function(scale)
        ApplyToolbarScale(scale)
    end)
end

local function EnsureToolbar()
    if toolbar then
        return toolbar
    end
    local bar = Widgets.CreateSurface(UIParent, Colors.BG, Colors.ACCENT)
    -- Same front strata as the previews so Raise() can keep the toolbar clickable on top.
    -- Not toplevel: the scope menu is also TOOLTIP and must be able to Raise() above this bar.
    bar:SetFrameStrata(EDIT_STRATA)
    bar:EnableMouse(true)
    bar:Hide()

    local dropdown = Dropdown.Create(bar, {}, function(scopeId)
        LayoutEditor.BeginScope(scopeId)
    end)

    local button = Widgets.CreateButton(bar, L.LAYOUT_EDIT_DONE, function()
        LayoutEditor.End()
    end, "primary")
    button:SetNormalFontObject(Fonts.LAYOUT_EDIT_DONE)
    button:SetDisabledFontObject(Fonts.LAYOUT_EDIT_DONE)
    local width =
        math.max(button:GetTextWidth() + Sizes.LAYOUT_EDIT_DONE_TEXT_PADDING, Sizes.LAYOUT_EDIT_DONE_MIN_WIDTH)
    button:SetSize(width, Sizes.LAYOUT_EDIT_DONE_HEIGHT)

    bar.doneButton = button
    toolbar = bar
    scopeDropdown = dropdown
    ListenForToolbarScale()
    ApplyToolbarScale(MainPanelScale())
    return bar
end

---Sizes the bar to its contents: scope selector, then the Done button.
local function LayoutToolbar()
    local pad = Spacing.LARGE
    local clusterGap = Spacing.XLARGE
    local dropdown = scopeDropdown
    local button = toolbar.doneButton

    dropdown:ClearAllPoints()
    dropdown:SetPoint("LEFT", toolbar, "LEFT", pad, 0)
    button:ClearAllPoints()
    button:SetPoint("LEFT", dropdown, "RIGHT", clusterGap * 2, 0)

    local width = pad + dropdown:GetWidth() + clusterGap * 2 + button:GetWidth() + pad
    toolbar:ClearAllPoints()
    toolbar:SetSize(width, button:GetHeight() + 2 * pad)
    toolbar:SetPoint("TOP", UIParent, "TOP", 0, -Spacing.XLARGE)
end

local function ScopeItems()
    local items = {}
    for _, scope in ipairs(LayoutEditor.GetScopes()) do
        items[#items + 1] = { value = scope.id, text = scope.label }
    end
    return items
end

function UpdateToolbar()
    if not scopeDropdown then
        return
    end
    scopeDropdown:SetItems(ScopeItems())
    if activeScopeId then
        scopeDropdown:SetSelected(activeScopeId)
    end
    LayoutToolbar()
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
    overlay:RegisterForDrag("RightButton")
    overlay.elementId = def.id
    ApplyOverlayBorder(overlay)

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
        -- StartMoving leaves arbitrary anchors; normalize so inspector X/Y share CENTER/CENTER space.
        local position = FloatingWindow.NormalizePosition(def.frame)
        def.setPosition(position)
        if selectedId == def.id then
            LayoutCoordinateInspector.RefreshCoordinates()
        end
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        if Combat.IsLockedDown() then
            LayoutEditor.End()
            return
        end
        SelectElement(def)
    end)
    -- Below the widget so it does not cover the name label above the outline.
    Widgets.AttachTooltip(overlay, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:AddLine(L.LAYOUT_EDIT_TOOLTIP_LEFT)
        tooltip:AddLine(L.LAYOUT_EDIT_TOOLTIP_RIGHT)
        -- First AddLine uses the header font; match body size without changing face/color.
        local line1 = _G[tooltip:GetName() .. "TextLeft1"]
        if line1 then
            line1:SetFontObject(GameTooltipText)
        end
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
    ApplyOverlayBorder(overlay)
    overlay:Show()
end

---@param def LayoutElementDef
local function DetachElement(def)
    if def.frame.StopMovingOrSizing then
        def.frame:StopMovingOrSizing()
    end
    if selectedId == def.id then
        ClearSelection()
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
    if not activeScopeId then
        return
    end
    for _, def in ipairs(activeElements or {}) do
        def.frame:Raise()
    end
    LayoutCoordinateInspector.Raise()
    if toolbar and toolbar:IsShown() then
        toolbar:Raise()
    end
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

---Enabled elements for a scope. `prepare` runs module frame setup before the lookup.
---@param scopeId string
---@param prepare boolean
---@return LayoutElementDef[]
local function CollectScope(scopeId, prepare)
    if scopeId == COMMON_SCOPE_ID then
        return CollectGlobalElements()
    end
    local scope = scopes[scopeId]
    if prepare and scope.prepare then
        scope.prepare()
    end
    local elements = {}
    for _, id in ipairs(scope.elementIds) do
        local def = registry[id]
        if def and def.isEnabled() then
            elements[#elements + 1] = def
        end
    end
    return elements
end

---@param scopeId string
---@return boolean
local function IsKnownScope(scopeId)
    return scopeId == COMMON_SCOPE_ID or scopes[scopeId] ~= nil
end

---Destroys overlays first, then restores module visibility.
---@param elements LayoutElementDef[]
local function ReleaseElements(elements)
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
    ClearSelection()
    -- onEditEnd may call Refresh; ignore that until the caller finishes the transition.
    refreshing = true
    for _, def in ipairs(elements) do
        def.onEditEnd()
    end
    refreshing = false
end

---@param scopeId string
---@param elements LayoutElementDef[]
local function PresentScope(scopeId, elements)
    activeScopeId = scopeId
    activeElements = elements
    for _, def in ipairs(elements) do
        AttachElement(def)
    end
    local bar = EnsureToolbar()
    bar:Show()
    UpdateToolbar()
    RaiseEditChrome()
end

---Enters the shared editor, or switches scope when a session is already active.
---A scope with nothing enabled refuses the initial enter. Switching to one keeps the session.
---@param scopeId string
---@return boolean
function LayoutEditor.BeginScope(scopeId)
    if not IsKnownScope(scopeId) then
        return false
    end
    if Combat.IsInCombat() or Combat.IsLockedDown() then
        Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
        return false
    end
    if activeScopeId == scopeId then
        return true
    end
    if activeScopeId then
        if scopeDropdown then
            scopeDropdown:Close()
        end
        local previous = activeElements or {}
        activeElements = {}
        ReleaseElements(previous)
        PresentScope(scopeId, CollectScope(scopeId, true))
        return true
    end

    local elements = CollectScope(scopeId, true)
    if #elements == 0 then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return false
    end

    ListenForCombat()
    EnsureDimmer():Show()
    -- Panel above the dimmer first; editable frames are raised last so they sit in front.
    RaiseMainPanel()
    PresentScope(scopeId, elements)
    return true
end

---Enters the editor in the common UI scope.
---@return boolean
function LayoutEditor.BeginGlobal()
    return LayoutEditor.BeginScope(COMMON_SCOPE_ID)
end

---Re-syncs the current scope with each element's isEnabled().
---Shows newly enabled elements and hides ones that became disabled (e.g. aura toggle in preview).
---An empty scope keeps the session so the toolbar can switch scopes.
function LayoutEditor.Refresh()
    if not activeScopeId or refreshing then
        return
    end
    refreshing = true

    local desired = CollectScope(activeScopeId, false)
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
    RaiseEditChrome()
    refreshing = false
end

---Leaves the editing session, restores module visibility, and tears down overlays.
function LayoutEditor.End()
    if not activeScopeId then
        return
    end
    local elements = activeElements or {}
    activeElements = nil
    activeScopeId = nil
    if scopeDropdown then
        scopeDropdown:Close()
    end
    ReleaseElements(elements)
    RestoreMainPanel()
    if dimmer then
        dimmer:Hide()
    end
    if toolbar then
        toolbar:Hide()
    end
end
