local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ActionRow = ns.ActionRow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local Equipment = ns.Api.Equipment
local GearAlert = ns.Modules.Get("GearAlert")

local TYPE_MISSING_TIER_SET = "MISSING_TIER_SET"
local TYPE_LOW_LEVEL_ITEM = "LOW_LEVEL_ITEM"

---@type AlertToast|nil
local toast
---@type GearAlertPayload[]|nil
local lastFindings

---@param link string
---@return string
local function ColoredItemName(link)
    local info = Equipment.GetItemInfo(link)
    if type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then
        return link
    end
    local name = "[" .. info.name .. "]"
    local hex = Equipment.GetItemQualityHex(info.quality)
    if type(hex) == "string" and hex ~= "" then
        return hex .. name .. "|r"
    end
    return name
end

---@param finding GearAlertPayload
---@return AlertToastRow
local function FormatFinding(finding)
    assert(type(finding) == "table", "GearAlert requires a finding")
    if finding.type == TYPE_LOW_LEVEL_ITEM then
        assert(type(finding.itemLevel) == "number", "Bad item level")
        assert(type(finding.slotName) == "string" and finding.slotName ~= "", "Bad slot name")
        if finding.itemLevel <= 0 then
            return {
                label = finding.slotName,
                status = L.GEAR_ALERT_EMPTY_SLOT,
                severity = "danger",
            }
        end
        assert(type(finding.itemLink) == "string" and finding.itemLink ~= "", "Bad item link")
        return {
            label = finding.slotName,
            detail = ColoredItemName(finding.itemLink),
            status = L.GEAR_ALERT_ITEM_LEVEL .. " " .. math.floor(finding.itemLevel),
            severity = "danger",
        }
    end
    assert(finding.type == TYPE_MISSING_TIER_SET, "Unknown gear alert type")
    assert(type(finding.equipped) == "number", "Bad equipped count")
    assert(type(finding.required) == "number", "Bad required count")
    local equipped = math.floor(finding.equipped)
    local required = math.floor(finding.required)
    local detail
    local names = finding.missingSlotNames
    if type(names) == "table" and #names > 0 then
        detail = L.GEAR_ALERT_MISSING_SLOTS:format(table.concat(names, L.GEAR_ALERT_SLOT_JOIN))
    end
    return {
        label = L.GEAR_ALERT_TAG_SET,
        detail = detail,
        status = equipped .. "/" .. required,
        severity = "warning",
    }
end

---@param findings GearAlertPayload[]
---@return AlertToastRow[]
local function FormatFindings(findings)
    local slotRows = {}
    local setRows = {}
    for index = 1, #findings do
        local finding = findings[index]
        local row = FormatFinding(finding)
        if finding.type == TYPE_MISSING_TIER_SET then
            setRows[#setRows + 1] = row
        else
            slotRows[#slotRows + 1] = row
        end
    end
    local rows = slotRows
    for index = 1, #setRows do
        rows[#rows + 1] = setRows[index]
    end
    return rows
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
        lastFindings = findings
        local frame = EnsureToast()
        frame:SetWindowPosition(GearAlert:GetPosition())
        frame:SetRows(FormatFindings(findings))
        frame:PlayIn()
        frame:Raise()
    else
        lastFindings = nil
        if toast then
            toast:Hide()
        end
    end
end

local function OnItemInfoReceived()
    if type(lastFindings) ~= "table" or not toast then
        return
    end
    toast:SetRows(FormatFindings(lastFindings))
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
    Equipment.OnItemInfoReceived(OnItemInfoReceived)
    self:StartMonitoring()
    ns.MainPanel:RegisterSection({
        title = L.GEAR_ALERT_TITLE,
        group = ns.PanelGroups.COMBAT,
        subtitle = L.GEAR_ALERT_SUBTITLE,
        build = Build,
    })
end
