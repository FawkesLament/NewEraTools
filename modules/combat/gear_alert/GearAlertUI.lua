local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Color = ns.Color
local ActionRow = ns.ActionRow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local GearAlert = ns.Modules.Get("GearAlert")

local TYPE_MISSING_TIER_SET = "MISSING_TIER_SET"
local TYPE_LOW_LEVEL_ITEM = "LOW_LEVEL_ITEM"

---@type AlertToast|nil
local toast

---@param text string
---@return string
local function Emphasize(text)
    return Color.Wrap(Colors.WARNING, text)
end

---@param finding GearAlertPayload
---@return AlertToastRow
local function FormatFinding(finding)
    assert(type(finding) == "table", "GearAlert requires a finding")
    if finding.type == TYPE_LOW_LEVEL_ITEM then
        assert(type(finding.itemLevel) == "number", "Bad item level")
        assert(type(finding.averageItemLevel) == "number", "Bad average item level")
        if finding.itemLevel <= 0 then
            assert(type(finding.slotName) == "string" and finding.slotName ~= "", "Bad slot name")
            return {
                left = L.GEAR_ALERT_EMPTY_SLOT,
                right = Emphasize(finding.slotName),
                color = Colors.WARNING,
            }
        end
        assert(type(finding.itemLink) == "string" and finding.itemLink ~= "", "Bad item link")
        return {
            left = L.GEAR_ALERT_LOW_LEVEL_ITEM,
            right = finding.itemLink,
            color = Colors.WARNING,
        }
    end
    assert(finding.type == TYPE_MISSING_TIER_SET, "Unknown gear alert type")
    assert(type(finding.equipped) == "number", "Bad equipped count")
    assert(type(finding.required) == "number", "Bad required count")
    local equipped = math.floor(finding.equipped)
    local required = math.floor(finding.required)
    return {
        left = L.GEAR_ALERT_MISSING_TIER_SET,
        right = L.GEAR_ALERT_MISSING_TIER_SET_DETAIL:format(Emphasize(string.format("%d/%d", equipped, required))),
        color = Colors.ERROR,
    }
end

local function EnsureToast()
    if toast then
        return toast
    end
    toast = ns.AlertToast.Create({
        name = ns.ADDON_NAME .. "GearAlert",
        title = L.GEAR_ALERT_NOTIFICATION_TITLE,
        position = GearAlert:GetPosition(),
        onPositionChanged = function(position)
            GearAlert:SetPosition(position)
        end,
    })
    return toast
end

---@param findings GearAlertPayload[]|nil
local function OnFindings(findings)
    if type(findings) == "table" and #findings > 0 then
        local rows = {}
        for index = 1, #findings do
            rows[index] = FormatFinding(findings[index])
        end
        local frame = EnsureToast()
        frame:SetWindowPosition(GearAlert:GetPosition())
        frame:SetRows(rows)
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

    ActionRow.Apply(body:AddRow(ActionRow.HEIGHT), {
        title = L.GEAR_ALERT_LOW_LEVEL,
        description = L.GEAR_ALERT_LOW_LEVEL_DESC,
        enabled = GearAlert:IsLowLevelCheckEnabled(),
        onEnabledChanged = function(enabled)
            GearAlert:SetLowLevelCheckEnabled(enabled)
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
    GearAlert:SetFindingListener(OnFindings)
    self:StartMonitoring()
    ns.MainPanel:RegisterSection({
        title = L.GEAR_ALERT_TITLE,
        group = ns.PanelGroups.COMBAT,
        tooltip = L.GEAR_ALERT_HINT,
        build = Build,
    })
end
