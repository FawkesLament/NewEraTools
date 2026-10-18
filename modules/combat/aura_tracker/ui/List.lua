local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CollapsibleSection = ns.CollapsibleSection
local Layout = ns.Layout
local Player = ns.Api.Player
local Spell = ns.Api.Spell
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")
local ListPlan = ns.AuraTrackerListPlan
local Profile = ns.AuraTrackerProfile
local Schema = ns.AuraTrackerSchema

local TRACKER_ROW_HEIGHT = Sizes.NAV_ROW_HEIGHT
local LIST_SPELL_ICON_SIZE = 24
local SPEC_ICON_SIZE = 16

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

local UNIT_LABELS = {
    [Schema.UNIT_PLAYER] = L.AURA_TRACKER_UNIT_PLAYER,
    [Schema.UNIT_TARGET] = L.AURA_TRACKER_UNIT_TARGET,
    [Schema.UNIT_FOCUS] = L.AURA_TRACKER_UNIT_FOCUS,
}

---@param unit string
---@return string
local function UnitLabel(unit)
    return UNIT_LABELS[unit] or UNIT_LABELS[Schema.UNIT_PLAYER]
end

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

---Applies a cached spell icon (or the question-mark placeholder) to an existing texture.
---@param icon Texture
---@param spellId integer
function UI.ApplySpellIcon(icon, spellId)
    icon:SetTexture(Spell.GetTexture(spellId) or Assets.Icons.QUESTION_MARK)
end

---@return integer|nil
function UI.ResolveSelectedTrackerId()
    if UI.selectedTrackerId and AuraTracker:HasTracker(UI.selectedTrackerId) then
        return UI.selectedTrackerId
    end
    local ids = AuraTracker:GetTrackerIds()
    UI.selectedTrackerId = AuraTracker:GetFirstTrackerEnabledForCurrentPlayer() or ids[1]
    return UI.selectedTrackerId
end

---Selects the first tracker enabled for the current player when the settings page is shown.
function UI.SelectFirstTrackerEnabledForCurrentPlayer()
    local trackerId = AuraTracker:GetFirstTrackerEnabledForCurrentPlayer()
    if not trackerId or trackerId == UI.selectedTrackerId then
        return
    end
    UI.SelectTracker(trackerId)
end

---The settings page is the scroll child, so the ScrollFrame is a few parents up.
---@param frame Frame|nil
---@return ScrollFrame|nil
function UI.PageScrollFrame(frame)
    local current = frame
    for _ = 1, 6 do
        if not current then
            return nil
        end
        if current.GetObjectType and current:GetObjectType() == "ScrollFrame" then
            return current
        end
        current = current:GetParent()
    end
    return nil
end

function UI.RelayoutSettings()
    if UI.suspendLayout then
        return
    end
    local started = Profile.Start()
    if
        not UI.settingsContainer
        or not UI.contentBody
        or not UI.listHost
        or not UI.emptyEditorHost
        or not UI.editorHost
    then
        Profile.Stop("ui.relayout", started)
        return
    end

    local listHeight = UI.listStack and UI.listStack:GetHeight() or 0
    UI.listHost:SetHeight(listHeight)
    UI.contentBody:SetEntryHeight(UI.listHost, listHeight)

    local trackerId = UI.ResolveSelectedTrackerId()
    if trackerId then
        UI.emptyEditorHost:Hide()
        UI.contentBody:SetEntryHeight(UI.emptyEditorHost, 0)
        local editorHeight = UI.editorStack and UI.editorStack:GetHeight() or 0
        UI.editorHost:Show()
        UI.editorHost:SetHeight(editorHeight)
        UI.contentBody:SetEntryHeight(UI.editorHost, editorHeight)
    else
        UI.editorHost:Hide()
        UI.contentBody:SetEntryHeight(UI.editorHost, 0)
        UI.emptyEditorHost:Show()
        UI.contentBody:SetEntryHeight(UI.emptyEditorHost, Sizes.CONTROL_ROW_HEIGHT)
    end

    UI.settingsContainer:SetContentHeight(UI.contentBody:GetHeight())
    if UI.SyncEditorHeaderPosition then
        UI.SyncEditorHeaderPosition()
    end
    Profile.Stop("ui.relayout", started)
end

---@param trackerId integer
function UI.SelectTracker(trackerId)
    if not AuraTracker:HasTracker(trackerId) then
        return
    end
    local previous = UI.selectedTrackerId
    if previous == trackerId and UI.editorBuilt then
        return
    end
    UI.selectedTrackerId = trackerId
    if previous and previous ~= trackerId then
        UI.SyncTrackerRow(previous)
    end
    UI.SyncTrackerRow(trackerId)
    UI.RefreshSelectedEditor()
end

---@return string
local function FormatCharacterSummary()
    local specName = Player.GetSpecializationName(Player.GetSpecializationId()) or "-"
    local className = Player.GetClassName(Player.GetClassFile()) or "-"
    local role = Player.GetRole()
    local roleName = (role and ROLE_LABELS[role]) or "-"
    return string.format(L.AURA_TRACKER_CHARACTER_SUMMARY, specName, className, roleName)
end

---Splits trackers into active/inactive lists without changing saved order.
---@return integer[] activeIds
---@return integer[] inactiveIds
local function PartitionTrackerIds()
    local activeIds = {}
    local inactiveIds = {}
    for _, trackerId in ipairs(AuraTracker:GetTrackerIds()) do
        if AuraTracker:IsActivationActive(trackerId) then
            activeIds[#activeIds + 1] = trackerId
        else
            inactiveIds[#inactiveIds + 1] = trackerId
        end
    end
    return activeIds, inactiveIds
end

---@class AuraTrackerRow
---@field frame Button
---@field trackerId integer
---@field enableBox CheckButton
---@field spellIcon Texture
---@field unitLabel FontString
---@field nameLabel FontString
---@field scopeLabel FontString
---@field isActive boolean
---@field selected boolean
---@field enabled boolean
---@field spellId integer
---@field unit string
---@field name string
---@field scope string

---Keeps the unit label immediately after the spell name, shortening the name before it meets the scope.
---@param row AuraTrackerRow
local function FitTrackerRowText(row)
    local frameWidth = row.frame:GetWidth()
    if frameWidth <= 0 then
        return
    end
    local nameWidth = row.nameLabel:GetUnboundedStringWidth()
    local unitWidth = row.unitLabel:GetUnboundedStringWidth()
    local scopeWidth = row.scopeLabel:GetUnboundedStringWidth()
    local left = Spacing.SMALL + Sizes.CHECKBOX + Spacing.SMALL + LIST_SPELL_ICON_SIZE + Spacing.SMALL
    local right = Spacing.MEDIUM + scopeWidth + Spacing.SMALL
    local available = frameWidth - left - Spacing.SMALL - unitWidth - right
    row.nameLabel:SetWidth(math.max(math.min(nameWidth, available), 1))
end

---@param parent Frame
---@param trackerId integer
---@return AuraTrackerRow
local function CreateTrackerRow(parent, trackerId)
    Profile.Inc("ui.trackerRow")
    local frame = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP)
    frame:SetHeight(TRACKER_ROW_HEIGHT)
    Widgets.ApplyBackdrop(frame, Colors.SURFACE, Colors.BORDER)
    Widgets.AddHoverHighlight(frame)

    local enableBox = Widgets.CreateCheckbox(frame)
    enableBox:SetPoint("LEFT", frame, "LEFT", Spacing.SMALL, 0)
    enableBox:SetScript("OnClick", function(self)
        if not AuraTracker:HasTracker(trackerId) or not AuraTracker:IsEnabled() then
            if AuraTracker:HasTracker(trackerId) then
                self:SetChecked(AuraTracker:IsTrackerEnabled(trackerId))
            end
            return
        end
        AuraTracker:SetTrackerEnabled(trackerId, self:GetChecked())
        self:SetChecked(AuraTracker:IsTrackerEnabled(trackerId))
    end)

    -- Texture on the row button: clicks select the aura; only the checkbox toggles enable.
    local spellIcon = frame:CreateTexture(nil, "ARTWORK")
    spellIcon:SetSize(LIST_SPELL_ICON_SIZE, LIST_SPELL_ICON_SIZE)
    spellIcon:SetPoint("LEFT", enableBox, "RIGHT", Spacing.SMALL, 0)

    local nameLabel = Widgets.CreateLabel(frame, Fonts.BODY, "")
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    nameLabel:SetPoint("LEFT", spellIcon, "RIGHT", Spacing.SMALL, 0)

    local unitLabel = Widgets.CreateLabel(frame, Fonts.SMALL_MUTED, "")
    unitLabel:SetJustifyH("LEFT")
    unitLabel:SetWordWrap(false)
    unitLabel:SetPoint("LEFT", nameLabel, "RIGHT", Spacing.SMALL, 0)

    local scopeLabel = Widgets.CreateLabel(frame, Fonts.SMALL_MUTED, "")
    scopeLabel:SetJustifyH("RIGHT")
    scopeLabel:SetWordWrap(false)
    scopeLabel:SetPoint("RIGHT", frame, "RIGHT", -Spacing.SMALL, 0)

    ---@type AuraTrackerRow
    local row = {
        frame = frame,
        trackerId = trackerId,
        enableBox = enableBox,
        spellIcon = spellIcon,
        unitLabel = unitLabel,
        nameLabel = nameLabel,
        scopeLabel = scopeLabel,
        isActive = false,
        selected = false,
        enabled = false,
        spellId = -1,
        unit = "",
        name = "",
        scope = "",
    }
    frame:SetScript("OnClick", function()
        UI.SelectTracker(trackerId)
    end)
    frame:HookScript("OnSizeChanged", function()
        FitTrackerRowText(row)
    end)
    return row
end

---@param trackerId integer
---@param isActive boolean
---@return boolean
local function RowDisplayMatches(row, trackerId, isActive)
    return row.isActive == isActive
        and row.selected == (UI.selectedTrackerId == trackerId)
        and row.enabled == AuraTracker:IsTrackerEnabled(trackerId)
        and row.spellId == AuraTracker:GetSpellId(trackerId)
        and row.unit == AuraTracker:GetUnit(trackerId)
        and row.name == AuraTracker:GetDisplayName(trackerId)
        and row.scope == AuraTracker:GetActivationScopeLabel(trackerId)
end

---@param row AuraTrackerRow
---@param isActive boolean
local function PaintRow(row, isActive)
    local trackerId = row.trackerId
    local selected = UI.selectedTrackerId == trackerId
    local enabled = AuraTracker:IsTrackerEnabled(trackerId)
    local spellId = AuraTracker:GetSpellId(trackerId)
    local unit = AuraTracker:GetUnit(trackerId)
    local name = AuraTracker:GetDisplayName(trackerId)
    local scope = AuraTracker:GetActivationScopeLabel(trackerId)
    Widgets.ApplyBackdrop(
        row.frame,
        selected and Colors.SURFACE_RAISED or Colors.SURFACE,
        selected and Colors.ACCENT or Colors.BORDER
    )
    row.enableBox:SetChecked(enabled)
    UI.ApplySpellIcon(row.spellIcon, spellId)
    row.unitLabel:SetText(UnitLabel(unit))
    row.unitLabel:SetAlpha(isActive and 1 or 0.7)
    row.nameLabel:SetFontObject(isActive and Fonts.BODY or Fonts.MUTED)
    row.nameLabel:SetText(name)
    row.scopeLabel:SetText(scope)
    row.scopeLabel:SetAlpha(isActive and 1 or 0.7)
    FitTrackerRowText(row)
    row.isActive = isActive
    row.selected = selected
    row.enabled = enabled
    row.spellId = spellId
    row.unit = unit
    row.name = name
    row.scope = scope
end

---@param trackerId integer
local function ReleaseRow(trackerId)
    local row = UI.trackerRows and UI.trackerRows[trackerId]
    if not row then
        return
    end
    row.frame:SetScript("OnClick", nil)
    row.enableBox:SetScript("OnClick", nil)
    row.frame:Hide()
    row.frame:SetParent(nil)
    UI.trackerRows[trackerId] = nil
end

---@param parent Frame
---@param trackerId integer
---@return AuraTrackerRow
local function EnsureRow(parent, trackerId)
    UI.trackerRows = UI.trackerRows or {}
    local row = UI.trackerRows[trackerId]
    if row then
        row.frame:SetParent(parent)
        return row
    end
    row = CreateTrackerRow(parent, trackerId)
    UI.trackerRows[trackerId] = row
    return row
end

---@param section CollapsibleSection
---@param stack LayoutStack
---@param trackerIds integer[]
---@param isActive boolean
local function RefillGroup(section, stack, trackerIds, isActive)
    stack:BeginUpdate()
    stack:Clear()
    for _, trackerId in ipairs(trackerIds) do
        local row = EnsureRow(section.content, trackerId)
        PaintRow(row, isActive)
        stack:Add(row.frame, TRACKER_ROW_HEIGHT)
    end
    stack:EndUpdate()
    section:SetBadge(tostring(#trackerIds))
    section:SetContentHeight(#trackerIds == 0 and 0 or stack:GetHeight())
end

---Builds the list chrome once. Later syncs reuse these frames.
local function EnsureTrackerList()
    if UI.listReady or not UI.listHost then
        return
    end
    UI.suspendLayout = true
    UI.trackerRows = {}
    UI.activeIds = {}
    UI.inactiveIds = {}
    UI.listStack = Layout.Stack(UI.listHost, { spacing = Spacing.TINY })

    local header = UI.listStack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local addButton = Widgets.CreateButton(header, L.AURA_TRACKER_ADD, function()
        if not AuraTracker:IsEnabled() then
            return
        end
        local id = AuraTracker:AddTracker()
        UI.SelectTracker(id)
    end, "accent", Assets.Glyphs.INCREASE)
    addButton:SetPoint("RIGHT", header, "RIGHT")

    local specIcon = header:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(SPEC_ICON_SIZE, SPEC_ICON_SIZE)
    specIcon:SetPoint("LEFT", header, "LEFT")
    specIcon:Hide()
    UI.summaryIcon = specIcon
    UI.summaryHeader = header
    UI.summaryAddButton = addButton

    UI.summaryLabel = Widgets.CreateLabel(header, Fonts.BODY, "")
    UI.summaryLabel:SetJustifyH("LEFT")
    UI.summaryLabel:SetWordWrap(false)
    UI.summaryLabel:SetPoint("LEFT", header, "LEFT")
    UI.summaryLabel:SetPoint("RIGHT", addButton, "LEFT", -Spacing.MEDIUM, 0)

    UI.activeGroup = CollapsibleSection.Create(UI.listStack, {
        title = L.AURA_TRACKER_GROUP_ACTIVE,
        expanded = UI.listActiveExpanded ~= false,
        spacingBefore = Spacing.SMALL,
        onStackHeightChanged = function()
            UI.RelayoutSettings()
        end,
        onExpandedChanged = function(expanded)
            UI.listActiveExpanded = expanded
        end,
    })
    UI.activeRowStack = Layout.Stack(UI.activeGroup.content, { spacing = Spacing.TINY })

    UI.inactiveGroup = CollapsibleSection.Create(UI.listStack, {
        title = L.AURA_TRACKER_GROUP_INACTIVE,
        expanded = UI.listInactiveExpanded == true,
        onStackHeightChanged = function()
            UI.RelayoutSettings()
        end,
        onExpandedChanged = function(expanded)
            UI.listInactiveExpanded = expanded
        end,
    })
    UI.inactiveRowStack = Layout.Stack(UI.inactiveGroup.content, { spacing = Spacing.TINY })
    UI.suspendLayout = false
    UI.listReady = true
end

local function RefreshCharacterSummary()
    if not UI.summaryLabel or not UI.summaryIcon then
        return
    end
    local text = FormatCharacterSummary()
    local icon = Player.GetSpecializationIcon(Player.GetSpecializationId())
    if UI.summaryText == text and UI.summaryIconPath == icon then
        return
    end
    UI.summaryText = text
    UI.summaryIconPath = icon
    UI.summaryLabel:SetText(text)
    UI.summaryLabel:ClearAllPoints()
    UI.summaryLabel:SetPoint("RIGHT", UI.summaryAddButton, "LEFT", -Spacing.MEDIUM, 0)
    if icon then
        UI.summaryIcon:SetTexture(icon)
        UI.summaryIcon:Show()
        UI.summaryLabel:SetPoint("LEFT", UI.summaryIcon, "RIGHT", Spacing.SMALL, 0)
    else
        UI.summaryIcon:Hide()
        UI.summaryLabel:SetPoint("LEFT", UI.summaryHeader, "LEFT")
    end
end

---One page-height update, then keep the viewport on the content that was below the list.
---@param anchor number
---@param oldHeight number
local function FinishStructureLayout(anchor, oldHeight)
    UI.RelayoutSettings()
    local scroll = UI.PageScrollFrame(UI.settingsContainer)
    if not scroll or not scroll.GetVerticalScroll or not scroll.SetVerticalScroll then
        return
    end
    local before = scroll:GetVerticalScroll()
    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or nil
    local nextScroll = ListPlan.AdjustScroll(before, anchor, oldHeight, UI.listHost:GetHeight(), range)
    if nextScroll ~= before then
        scroll:SetVerticalScroll(nextScroll)
    end
end

---Replaces group membership and order. One content-height change for the whole edit.
local function SyncTrackerStructure(activeIds, inactiveIds)
    local anchor = UI.contentBody:GetOffset(UI.listHost)
    local oldHeight = UI.listHost:GetHeight()
    UI.suspendLayout = true
    RefillGroup(UI.activeGroup, UI.activeRowStack, activeIds, true)
    RefillGroup(UI.inactiveGroup, UI.inactiveRowStack, inactiveIds, false)
    local live = {}
    for _, trackerId in ipairs(activeIds) do
        live[trackerId] = true
    end
    for _, trackerId in ipairs(inactiveIds) do
        live[trackerId] = true
    end
    for trackerId in pairs(UI.trackerRows) do
        if not live[trackerId] then
            ReleaseRow(trackerId)
        end
    end
    UI.activeIds = activeIds
    UI.inactiveIds = inactiveIds
    UI.suspendLayout = false
    FinishStructureLayout(anchor, oldHeight)
end

---Paints one row. Moves it between groups only when membership changed, as one list edit.
---@param trackerId integer
function UI.SyncTrackerRow(trackerId)
    if not UI.listHost or not AuraTracker:HasTracker(trackerId) then
        return
    end
    EnsureTrackerList()
    local isActive = AuraTracker:IsActivationActive(trackerId)
    local inActive = false
    for _, id in ipairs(UI.activeIds or {}) do
        if id == trackerId then
            inActive = true
            break
        end
    end
    local inInactive = false
    if not inActive then
        for _, id in ipairs(UI.inactiveIds or {}) do
            if id == trackerId then
                inInactive = true
                break
            end
        end
    end
    local placed = (isActive and inActive) or (not isActive and inInactive)
    if not placed then
        UI.SyncTrackerList()
        return
    end
    local row = UI.trackerRows[trackerId]
    if row and RowDisplayMatches(row, trackerId, isActive) then
        return
    end
    if not row then
        UI.SyncTrackerList()
        return
    end
    PaintRow(row, isActive)
end

---Updates visible rows. Rebuilds group contents only when ids are added, removed, or reordered.
function UI.SyncTrackerList()
    if not UI.listHost then
        return
    end
    local started = Profile.Start()
    if UI.selectedTrackerId and not AuraTracker:HasTracker(UI.selectedTrackerId) then
        UI.selectedTrackerId = nil
    end
    UI.ResolveSelectedTrackerId()
    EnsureTrackerList()
    RefreshCharacterSummary()

    local activeIds, inactiveIds = PartitionTrackerIds()
    local function RowsPresent(ids)
        for _, trackerId in ipairs(ids) do
            if not UI.trackerRows[trackerId] then
                return false
            end
        end
        return true
    end
    if
        ListPlan.SameIds(UI.activeIds, activeIds)
        and ListPlan.SameIds(UI.inactiveIds, inactiveIds)
        and RowsPresent(activeIds)
        and RowsPresent(inactiveIds)
    then
        for _, trackerId in ipairs(activeIds) do
            UI.SyncTrackerRow(trackerId)
        end
        for _, trackerId in ipairs(inactiveIds) do
            UI.SyncTrackerRow(trackerId)
        end
        Profile.Stop("ui.syncList", started)
        return
    end

    SyncTrackerStructure(activeIds, inactiveIds)
    Profile.Stop("ui.refreshList", started)
end

---Full list sync. Structure is skipped when the saved order and groups are unchanged.
function UI.RefreshTrackerList()
    UI.SyncTrackerList()
end
