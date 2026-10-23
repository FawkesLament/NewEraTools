local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Colors = ns.Assets.Colors

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local Chain = Internals.InterruptChain

local REGION_IDS = {
    [Chain.FRONT_LEFT] = true,
    [Chain.FRONT_RIGHT] = true,
    [Chain.BACK_LEFT] = true,
    [Chain.BACK_RIGHT] = true,
}

---@param regionId string|nil
---@return string|nil
local function KnownRegion(regionId)
    if REGION_IDS[regionId] then
        return regionId
    end
end

---@param regionId string|nil
---@return string
local function RegionLabel(regionId)
    if regionId == Chain.FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    end
    if regionId == Chain.FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    end
    if regionId == Chain.BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    end
    if regionId == Chain.BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

---@class TwinFangsAddonCheckAssignment
---@field region string|nil
---@field index number|nil
---@field backup string|nil

---@class TwinFangsAddonCheckConfig
---@field assignment TwinFangsAddonCheckAssignment
---@field macro "ready"|"not_ready"|"na"|"unknown"
---@field soak false|"left"|"middle"|"right"

---@return TwinFangsAddonCheckAssignment
local function SnapshotAssignment()
    local chain = TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
    local found = Chain.GetPlayerResponsibilities(chain, Chain.ResolveLocalPlayerName())
    local assignment = {}
    assignment.region = KnownRegion(found.region)
    if
        assignment.region
        and type(found.index) == "number"
        and found.index >= 1
        and found.index == math.floor(found.index)
    then
        assignment.index = found.index
    end
    assignment.backup = KnownRegion(found.backup)
    return assignment
end

---@return false|"left"|"middle"|"right"
local function SnapshotSoak()
    local soak = TwinFangs.db and TwinFangs.db.soakReminder
    if type(soak) ~= "table" then
        error("TwinFangs AddonCheck: invalid soakReminder")
    end
    if type(soak.enabled) ~= "boolean" then
        error("TwinFangs AddonCheck: invalid soakReminder.enabled")
    end
    if not soak.enabled then
        return false
    end
    if not Schema.GROUPS[soak.group] then
        error("TwinFangs AddonCheck: invalid soakReminder.group")
    end
    return soak.group
end

---Live AddonCheck snapshot. Reads current settings; does not mutate them.
---@return TwinFangsAddonCheckConfig
function TwinFangs:GetAddonCheckConfig()
    return {
        assignment = SnapshotAssignment(),
        macro = self:InspectInterruptMacroReadiness(),
        soak = SnapshotSoak(),
    }
end

---AddonCheck panel validator: column keys to highlight, or nil when ok.
---Does not compare a peer's assignments or soak group against the commander.
---@param config any
---@return string[]|nil
function TwinFangs.ValidateAddonCheckConfig(config)
    if type(config) ~= "table" then
        return { "assignment", "macro", "soak" }
    end
    local flagged = {}
    if type(config.assignment) ~= "table" then
        flagged[#flagged + 1] = "assignment"
    end
    local macro = config.macro
    if macro ~= TwinFangs.ADDON_CHECK_MACRO_READY and macro ~= TwinFangs.ADDON_CHECK_MACRO_NA then
        flagged[#flagged + 1] = "macro"
    end
    if config.soak ~= false and not Schema.GROUPS[config.soak] then
        flagged[#flagged + 1] = "soak"
    end
    if #flagged == 0 then
        return nil
    end
    return flagged
end

---@param value any
---@return string|nil
function TwinFangs.FormatAddonCheckAssignment(value)
    if type(value) ~= "table" then
        return nil
    end
    local region = KnownRegion(value.region)
    local backup = KnownRegion(value.backup)
    if not region and not backup then
        return L.TWIN_FANGS_ADDONCHECK_UNASSIGNED
    end
    local lines = {}
    if region then
        local label = RegionLabel(region)
        if type(value.index) == "number" then
            lines[#lines + 1] = string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, label, value.index)
        else
            lines[#lines + 1] = label
        end
    end
    if backup then
        lines[#lines + 1] = string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, RegionLabel(backup))
    end
    return table.concat(lines, "\n")
end

---@param value any
---@return string|nil
---@return table|nil
function TwinFangs.FormatAddonCheckMacro(value)
    if value == TwinFangs.ADDON_CHECK_MACRO_READY then
        return L.TWIN_FANGS_ADDONCHECK_MACRO_READY, Colors.SUCCESS
    end
    if value == TwinFangs.ADDON_CHECK_MACRO_NOT_READY then
        return L.TWIN_FANGS_ADDONCHECK_MACRO_NOT_READY, Colors.ERROR
    end
    if value == TwinFangs.ADDON_CHECK_MACRO_NA then
        return L.TWIN_FANGS_ADDONCHECK_MACRO_NA, Colors.TEXT_MUTED
    end
    if value == TwinFangs.ADDON_CHECK_MACRO_UNKNOWN then
        return L.TWIN_FANGS_ADDONCHECK_MACRO_UNKNOWN, Colors.WARNING
    end
end

---@param value any
---@return string|nil
function TwinFangs.FormatAddonCheckSoak(value)
    if value == false then
        return L.TWIN_FANGS_ADDONCHECK_SOAK_DISABLED
    end
    if value == Schema.GROUP_LEFT then
        return L.TWIN_FANGS_SOAK_GROUP_LEFT
    end
    if value == Schema.GROUP_MIDDLE then
        return L.TWIN_FANGS_SOAK_GROUP_MIDDLE
    end
    if value == Schema.GROUP_RIGHT then
        return L.TWIN_FANGS_SOAK_GROUP_RIGHT
    end
end

---@return AddonCheckPanelColumn[]
function TwinFangs.AddonCheckColumns()
    return {
        {
            key = "assignment",
            title = L.TWIN_FANGS_ADDONCHECK_COL_ASSIGNMENT,
            format = TwinFangs.FormatAddonCheckAssignment,
        },
        {
            key = "macro",
            title = L.TWIN_FANGS_ADDONCHECK_COL_MACRO,
            format = TwinFangs.FormatAddonCheckMacro,
        },
        {
            key = "soak",
            title = L.TWIN_FANGS_ADDONCHECK_COL_SOAK,
            format = TwinFangs.FormatAddonCheckSoak,
        },
    }
end
