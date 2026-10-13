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

local LIST_HEADER_HEIGHT = 14
local TRACKER_ROW_HEIGHT = Sizes.NAV_ROW_HEIGHT
local LIST_SPELL_ICON_SIZE = 24

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

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
    UI.selectedTrackerId = ids[1]
    return UI.selectedTrackerId
end

function UI.RelayoutSettings()
    if not UI.moduleSection or not UI.contentBody or not UI.listHost or not UI.emptyEditorHost or not UI.editorHost then
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

    UI.moduleSection:SetContentHeight(UI.contentBody:GetHeight())
end

---@param trackerId integer
function UI.SelectTracker(trackerId)
    if not AuraTracker:HasTracker(trackerId) then
        return
    end
    UI.selectedTrackerId = trackerId
    UI.RefreshTrackerList()
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

---@param parent Frame
---@param trackerId integer
---@param isActive boolean
---@return Frame
local function CreateTrackerRow(parent, trackerId, isActive)
    local selected = UI.selectedTrackerId == trackerId
    local row = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP)
    row:SetHeight(TRACKER_ROW_HEIGHT)
    -- Teal border marks selection; avoid extra accent strips that compete with list content.
    Widgets.ApplyBackdrop(
        row,
        selected and Colors.SURFACE_RAISED or Colors.SURFACE,
        selected and Colors.ACCENT or Colors.BORDER
    )
    Widgets.AddHoverHighlight(row)

    local enableBox = Widgets.CreateCheckbox(row)
    enableBox:SetChecked(AuraTracker:IsTrackerEnabled(trackerId))
    enableBox:SetPoint("LEFT", row, "LEFT", Spacing.SMALL, 0)
    enableBox:SetScript("OnClick", function(self)
        if not AuraTracker:IsEnabled() then
            self:SetChecked(AuraTracker:IsTrackerEnabled(trackerId))
            return
        end
        AuraTracker:SetTrackerEnabled(trackerId, self:GetChecked())
        self:SetChecked(AuraTracker:IsTrackerEnabled(trackerId))
    end)

    -- Texture on the row button: clicks select the aura; only the checkbox toggles enable.
    local spellIcon = row:CreateTexture(nil, "ARTWORK")
    spellIcon:SetSize(LIST_SPELL_ICON_SIZE, LIST_SPELL_ICON_SIZE)
    spellIcon:SetPoint("LEFT", enableBox, "RIGHT", Spacing.SMALL, 0)
    UI.ApplySpellIcon(spellIcon, AuraTracker:GetSpellId(trackerId))

    local nameFont = isActive and Fonts.BODY or Fonts.MUTED
    local nameLabel = Widgets.CreateLabel(row, nameFont, AuraTracker:GetDisplayName(trackerId))
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(false)
    nameLabel:SetPoint("LEFT", spellIcon, "RIGHT", Spacing.SMALL, 0)

    local scopeLabel = Widgets.CreateLabel(row, Fonts.SMALL_MUTED, AuraTracker:GetActivationScopeLabel(trackerId))
    scopeLabel:SetJustifyH("RIGHT")
    scopeLabel:SetWordWrap(false)
    scopeLabel:SetPoint("RIGHT", row, "RIGHT", -Spacing.SMALL, 0)
    if not isActive then
        scopeLabel:SetAlpha(0.7)
    end
    nameLabel:SetPoint("RIGHT", scopeLabel, "LEFT", -Spacing.MEDIUM, 0)

    row:SetScript("OnClick", function()
        UI.SelectTracker(trackerId)
    end)

    return row
end

---@param section CollapsibleSection
---@param trackerIds integer[]
---@param isActive boolean
local function FillGroupSection(section, trackerIds, isActive)
    section:SetBadge(tostring(#trackerIds))
    if #trackerIds == 0 then
        section:SetContentHeight(0)
        return
    end

    local body = Layout.Stack(section.content, { spacing = Spacing.TINY })
    for _, trackerId in ipairs(trackerIds) do
        local row = CreateTrackerRow(section.content, trackerId, isActive)
        body:Add(row, TRACKER_ROW_HEIGHT)
    end
    section:SetContentHeight(body:GetHeight())
end

function UI.RefreshTrackerList()
    if not UI.listHost then
        return
    end

    -- Selection is independent of activation; only replace it when the id is gone.
    if UI.selectedTrackerId and not AuraTracker:HasTracker(UI.selectedTrackerId) then
        UI.selectedTrackerId = nil
    end
    UI.ResolveSelectedTrackerId()

    local activeExpanded = UI.listActiveExpanded ~= false
    local inactiveExpanded = UI.listInactiveExpanded == true

    local children = { UI.listHost:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    UI.listStack = Layout.Stack(UI.listHost, { spacing = Spacing.TINY })

    local header = UI.listStack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local headerLabel = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, L.AURA_TRACKER_LIST)
    headerLabel:SetJustifyH("LEFT")
    headerLabel:SetPoint("LEFT", header, "LEFT")
    headerLabel:SetPoint("RIGHT", header, "RIGHT", -Sizes.BUTTON_MIN_WIDTH - Spacing.SMALL, 0)

    local addButton = Widgets.CreateButton(header, L.AURA_TRACKER_ADD, function()
        if not AuraTracker:IsEnabled() then
            return
        end
        local id = AuraTracker:AddTracker()
        UI.selectedTrackerId = id
        UI.RefreshTrackerList()
        UI.RefreshSelectedEditor()
    end)
    addButton:SetPoint("RIGHT", header, "RIGHT")

    local summary = UI.listStack:AddRow(LIST_HEADER_HEIGHT)
    local summaryLabel = Widgets.CreateLabel(summary, Fonts.TINY_MUTED, FormatCharacterSummary())
    summaryLabel:SetJustifyH("LEFT")
    summaryLabel:SetWordWrap(false)
    summaryLabel:SetPoint("LEFT", summary, "LEFT")
    summaryLabel:SetPoint("RIGHT", summary, "RIGHT")

    local activeIds, inactiveIds = PartitionTrackerIds()

    local activeSection = CollapsibleSection.Create(UI.listStack, {
        title = L.AURA_TRACKER_GROUP_ACTIVE,
        expanded = activeExpanded,
        spacingBefore = Spacing.SMALL,
        onStackHeightChanged = function()
            UI.RelayoutSettings()
        end,
        onExpandedChanged = function(expanded)
            UI.listActiveExpanded = expanded
        end,
    })
    FillGroupSection(activeSection, activeIds, true)

    local inactiveSection = CollapsibleSection.Create(UI.listStack, {
        title = L.AURA_TRACKER_GROUP_INACTIVE,
        expanded = inactiveExpanded,
        onStackHeightChanged = function()
            UI.RelayoutSettings()
        end,
        onExpandedChanged = function(expanded)
            UI.listInactiveExpanded = expanded
        end,
    })
    FillGroupSection(inactiveSection, inactiveIds, false)

    UI.RelayoutSettings()
end
