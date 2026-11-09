local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ActionRow = ns.ActionRow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local GearAlert = ns.Modules.Get("GearAlert")

local TYPE_MISSING_TIER_SET = "MISSING_TIER_SET"

---@type CountToast|nil
local toast

---@param finding GearAlertPayload
---@return string, string, string
local function FormatFinding(finding)
    assert(type(finding) == "table", "GearAlert requires a finding")
    assert(finding.type == TYPE_MISSING_TIER_SET, "Unknown gear alert type")
    assert(type(finding.equipped) == "number", "Bad equipped count")
    assert(type(finding.required) == "number", "Bad required count")
    local equipped = math.floor(finding.equipped)
    local required = math.floor(finding.required)
    return L.GEAR_ALERT_NOTIFICATION_TITLE, L.GEAR_ALERT_MISSING_TIER_SET, L.GEAR_ALERT_COUNT:format(equipped, required)
end

local function EnsureToast()
    if toast then
        return toast
    end
    toast = ns.CountToast.Create({
        name = ns.ADDON_NAME .. "GearAlert",
        title = L.GEAR_ALERT_NOTIFICATION_TITLE,
        message = "",
        count = "",
        position = GearAlert:GetPosition(),
        onPositionChanged = function(position)
            GearAlert:SetPosition(position)
        end,
    })
    return toast
end

local function OnFinding(finding)
    if not GearAlert:IsFourPieceCheckEnabled() then
        return
    end
    if finding then
        local frame = EnsureToast()
        frame:SetWindowPosition(GearAlert:GetPosition())
        frame:SetToastText(FormatFinding(finding))
        frame:Show()
        frame:Raise()
    elseif toast then
        toast:Hide()
    end
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    local _, description = ActionRow.Apply(body:AddRow(ActionRow.HEIGHT), {
        title = L.GEAR_ALERT_MISSING_SET,
        description = GearAlert:GetMenuStatusText(),
        enabled = GearAlert:IsFourPieceCheckEnabled(),
        onEnabledChanged = function(enabled)
            GearAlert:SetFourPieceCheckEnabled(enabled)
        end,
    })

    local function ApplyStatus()
        if not description then
            return
        end
        description:SetText(GearAlert:GetMenuStatusText())
        if GearAlert:HasFourPieceHistory() then
            description:SetTextColor(Widgets.UnpackColor(Colors.SUCCESS))
        else
            description:SetTextColor(Widgets.UnpackColor(Assets.FontStyles[Fonts.SMALL_MUTED].color))
        end
    end

    ApplyStatus()
    if description then
        GearAlert:SetStatusListener(ApplyStatus)
    end

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    return BuildContent(container)
end

function GearAlert:OnEnable()
    EnsureToast()
    GearAlert:SetFindingListener(OnFinding)
    self:StartMonitoring()
    ns.MainPanel:RegisterSection({
        title = L.GEAR_ALERT_TITLE,
        group = ns.PanelGroups.COMBAT,
        tooltip = L.GEAR_ALERT_HINT,
        build = Build,
    })
end
