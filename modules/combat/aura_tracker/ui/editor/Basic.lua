local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Aura = ns.Api.Aura
local Player = ns.Api.Player
local Widgets = ns.Widgets
local Activation = ns.AuraTrackerActivation
local Schema = ns.AuraTrackerSchema

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

local SPELL_ID_DIGITS = 9

local ROLE_LABELS = {
    TANK = L.AURA_TRACKER_ROLE_TANK,
    HEALER = L.AURA_TRACKER_ROLE_HEALER,
    DAMAGER = L.AURA_TRACKER_ROLE_DAMAGER,
}

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

local Controls = UI.Controls

---@param scope string
---@param savedTarget integer|string|nil
---@return string
local function FormatScopeSegmentLabel(scope, savedTarget)
    if scope == Activation.ALWAYS then
        return L.AURA_TRACKER_SCOPE_ALWAYS
    end
    if scope == Activation.SPECIALIZATION then
        return Player.GetSpecializationName(savedTarget)
            or Player.GetSpecializationName(Player.GetSpecializationId())
            or "-"
    end
    if scope == Activation.CLASS then
        return Player.GetClassName(savedTarget) or Player.GetClassName(Player.GetClassFile()) or "-"
    end
    if scope == Activation.ROLE then
        local role = savedTarget or Player.GetRole()
        return (role and ROLE_LABELS[role]) or "-"
    end
    return "-"
end

---Toggle segments in order: specialization → class → role → always.
---Selected scope uses the aura's saved target; others preview the current character.
---@param trackerId integer|nil
---@return SegmentedControlItem[]
local function BuildActivationScopeItems(trackerId)
    local scope, target
    if trackerId then
        scope, target = AuraTracker:GetActivationScope(trackerId)
    end
    return {
        {
            value = Activation.SPECIALIZATION,
            text = FormatScopeSegmentLabel(
                Activation.SPECIALIZATION,
                scope == Activation.SPECIALIZATION and target or nil
            ),
        },
        {
            value = Activation.CLASS,
            text = FormatScopeSegmentLabel(Activation.CLASS, scope == Activation.CLASS and target or nil),
        },
        {
            value = Activation.ROLE,
            text = FormatScopeSegmentLabel(Activation.ROLE, scope == Activation.ROLE and target or nil),
        },
        {
            value = Activation.ALWAYS,
            text = FormatScopeSegmentLabel(Activation.ALWAYS),
        },
    }
end

---Assigns a new scope using the current character's identifiers; same-scope reselection keeps the saved target.
---@param trackerId integer
---@param scope string
local function AssignActivationScope(trackerId, scope)
    local currentScope = AuraTracker:GetActivationScope(trackerId)
    if currentScope == scope then
        return
    end
    if scope == Activation.ALWAYS then
        AuraTracker:SetActivationScope(trackerId, scope, nil)
        return
    end
    if scope == Activation.SPECIALIZATION then
        local specializationId = Player.GetSpecializationId()
        if specializationId then
            AuraTracker:SetActivationScope(trackerId, scope, specializationId)
        end
        return
    end
    if scope == Activation.CLASS then
        local classFile = Player.GetClassFile()
        if classFile then
            AuraTracker:SetActivationScope(trackerId, scope, classFile)
        end
        return
    end
    if scope == Activation.ROLE then
        local role = Player.GetRole()
        if role then
            AuraTracker:SetActivationScope(trackerId, scope, role)
        end
    end
end

function UI.RefreshActivationScopeControl()
    if not UI.activationScopeControl then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local items = BuildActivationScopeItems(trackerId)
    local selected = AuraTracker:GetActivationScope(trackerId)
    local parts = { selected }
    for _, item in ipairs(items) do
        parts[#parts + 1] = tostring(item.value)
        parts[#parts + 1] = item.text
    end
    local signature = table.concat(parts, "\0")
    if signature == UI.activationScopeSignature then
        return
    end
    UI.activationScopeSignature = signature
    UI.activationScopeControl:SetItems(items)
    UI.activationScopeControl:SetSelected(selected)
end

---Keeps the current type when the new unit still supports it; otherwise the one type that unit allows.
---@param unit string
---@param current string
---@return string
local function PreferredAuraType(unit, current)
    if Aura.IsSupportedSource(unit, current) then
        return current
    end
    if Aura.IsSupportedSource(unit, Schema.AURA_HELPFUL) then
        return Schema.AURA_HELPFUL
    end
    return Schema.AURA_HARMFUL
end

---@param unit string
---@return string
local function SourceLimitationHint(unit)
    if unit == Schema.UNIT_PLAYER then
        return L.AURA_TRACKER_SOURCE_HINT_PLAYER
    end
    return L.AURA_TRACKER_SOURCE_HINT_EXTERNAL
end

---Shows this bar's unit and aura type, and locks aura types the tracker does not implement yet.
function UI.RefreshSourceControls()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId or not UI.unitControl then
        return
    end
    local unit = AuraTracker:GetUnit(trackerId)
    local auraType = AuraTracker:GetAuraType(trackerId)
    UI.unitControl:SetSelected(unit)
    if UI.auraTypeControl then
        UI.auraTypeControl:SetSegmentEnabled(Schema.AURA_HELPFUL, Aura.IsSupportedSource(unit, Schema.AURA_HELPFUL))
        UI.auraTypeControl:SetSegmentEnabled(Schema.AURA_HARMFUL, Aura.IsSupportedSource(unit, Schema.AURA_HARMFUL))
        UI.auraTypeControl:SetSelected(auraType)
    end
    if UI.sourceHintLabel then
        UI.sourceHintLabel:SetText(SourceLimitationHint(unit))
    end
end

local function CommitSpellIdFromBox()
    if UI.refreshingControls or not UI.spellIdBox then
        return
    end
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        return
    end
    local raw = UI.spellIdBox:GetNumber()
    local spellId = (type(raw) == "number" and raw > 0) and math.floor(raw) or 0
    AuraTracker:SetSpellId(trackerId, spellId)
    UI.spellIdBox:SetText(spellId > 0 and tostring(spellId) or "")
    UI.RefreshEditorHeader(trackerId)
    UI.SyncTrackerRow(trackerId)
end

---@param content Frame
---@return number
function UI.BuildBasicSection(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    local spellRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local spellLabel = Widgets.CreateLabel(spellRow, Fonts.BODY, L.AURA_TRACKER_SPELL_ID)
    spellLabel:SetJustifyH("LEFT")
    UI.spellIdBox = Widgets.CreateNumberBox(spellRow, SPELL_ID_DIGITS)
    UI.spellIdBox:SetScript("OnEnterPressed", function(self)
        CommitSpellIdFromBox()
        self:ClearFocus()
    end)
    UI.spellIdBox:HookScript("OnEditFocusLost", function()
        CommitSpellIdFromBox()
    end)
    Layout.Row(spellRow, { spellLabel, UI.spellIdBox }, Spacing.LARGE)

    local unitRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    UI.unitControl = Controls.AddSegmentedRow(unitRow, L.AURA_TRACKER_UNIT, {
        { value = Schema.UNIT_PLAYER, text = L.AURA_TRACKER_UNIT_PLAYER },
        { value = Schema.UNIT_TARGET, text = L.AURA_TRACKER_UNIT_TARGET },
        { value = Schema.UNIT_FOCUS, text = L.AURA_TRACKER_UNIT_FOCUS },
    }, function(unit)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        local auraType = PreferredAuraType(unit, AuraTracker:GetAuraType(trackerId))
        AuraTracker:SetSource(trackerId, unit, auraType)
        UI.RefreshSourceControls()
    end)

    -- Both types stay visible so the model can grow; unsupported ones cannot be clicked.
    local auraTypeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    UI.auraTypeControl = Controls.AddSegmentedRow(auraTypeRow, L.AURA_TRACKER_AURA_TYPE, {
        { value = Schema.AURA_HELPFUL, text = L.AURA_TRACKER_AURA_HELPFUL },
        { value = Schema.AURA_HARMFUL, text = L.AURA_TRACKER_AURA_HARMFUL },
    }, function(auraType)
        if UI.refreshingControls or not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId or not Aura.IsSupportedSource(AuraTracker:GetUnit(trackerId), auraType) then
            return
        end
        AuraTracker:SetAuraType(trackerId, auraType)
    end)
    UI.sourceHintLabel = Widgets.CreateLabel(auraTypeRow, Fonts.SMALL_MUTED, "")
    UI.sourceHintLabel:SetJustifyH("LEFT")
    UI.sourceHintLabel:SetWordWrap(false)
    UI.sourceHintLabel:SetPoint("LEFT", UI.auraTypeControl, "RIGHT", Spacing.LARGE, 0)
    UI.sourceHintLabel:SetPoint("RIGHT", auraTypeRow, "RIGHT")

    local scopeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    UI.activationScopeControl = Controls.AddSegmentedRow(
        scopeRow,
        L.AURA_TRACKER_ACTIVATION_SCOPE,
        BuildActivationScopeItems(UI.ResolveSelectedTrackerId()),
        function(scope)
            if UI.refreshingControls or not UI.CanEditSelected() then
                return
            end
            local trackerId = UI.ResolveSelectedTrackerId()
            if not trackerId then
                return
            end
            AssignActivationScope(trackerId, scope)
            UI.RefreshActivationScopeControl()
        end
    )

    UI.RefreshSourceControls()
    UI.RefreshActivationScopeControl()

    return body:GetHeight()
end
