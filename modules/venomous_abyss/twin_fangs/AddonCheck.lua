local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L

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
---@field channel TwinFangsInterruptChannel|nil
---@field backupChannel TwinFangsInterruptChannel|nil

---@class TwinFangsAddonCheckConfig
---@field assignment TwinFangsAddonCheckAssignment
---@field channels string
---@field soak false|"left"|"middle"|"right"

---@param chain TwinFangsInterruptChainSettings|nil
---@param regionId string|nil
---@return TwinFangsInterruptChannel|nil
local function RegionChannel(chain, regionId)
    if not regionId or type(chain) ~= "table" then
        return nil
    end
    local region = chain[regionId]
    if type(region) ~= "table" then
        return nil
    end
    return Schema.CoerceChannel(region.channel)
end

---Four-region wire snapshot, in InterruptChain.REGION_IDS order. Missing regions are party.
---@param chain TwinFangsInterruptChainSettings|nil
---@return string
local function SnapshotChannels(chain)
    local codes = {}
    for _, regionId in ipairs(Chain.REGION_IDS) do
        codes[#codes + 1] = Schema.EncodeChannelWire(RegionChannel(chain, regionId))
    end
    return table.concat(codes)
end

---Legacy clients omit channels; treat that as all-party. Invalid values stay distinguishable.
---@param value any
---@return string|false
local function NormalizeChannels(value)
    if value == nil or value == "" then
        return "pppp"
    end
    if type(value) ~= "string" or #value ~= 4 then
        return false
    end
    for index = 1, 4 do
        if not Schema.DecodeChannelWire(value:sub(index, index)) then
            return false
        end
    end
    return value
end

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
    assignment.channel = RegionChannel(chain, assignment.region)
    assignment.backupChannel = RegionChannel(chain, assignment.backup)
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
    local chain = TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
    return {
        assignment = SnapshotAssignment(),
        channels = SnapshotChannels(chain),
        soak = SnapshotSoak(),
    }
end

---AddonCheck panel validator: column keys to highlight, or nil when ok.
---Does not compare a peer's primary/backup slots or soak group against the commander.
---Flags assignment when the four-zone channel snapshot differs from the commander.
---@param config any
---@param localConfig any
---@return string[]|nil
function TwinFangs.ValidateAddonCheckConfig(config, localConfig)
    if type(config) ~= "table" then
        return { "assignment", "soak" }
    end
    local flagged = {}
    if type(config.assignment) ~= "table" then
        flagged[#flagged + 1] = "assignment"
    elseif type(localConfig) == "table" then
        local localChannels = NormalizeChannels(localConfig.channels)
        local peerChannels = NormalizeChannels(config.channels)
        if localChannels == false or peerChannels == false or peerChannels ~= localChannels then
            flagged[#flagged + 1] = "assignment"
        end
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
    local function WithChannel(line, channel)
        local slash = Schema.ChannelSlash(channel)
        if not slash then
            return line
        end
        return line .. " · " .. slash
    end
    if region then
        local label = RegionLabel(region)
        local line
        if type(value.index) == "number" then
            line = string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, label, value.index)
        else
            line = label
        end
        lines[#lines + 1] = WithChannel(line, value.channel)
    end
    if backup then
        lines[#lines + 1] =
            WithChannel(string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, RegionLabel(backup)), value.backupChannel)
    end
    return table.concat(lines, "\n")
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
            flex = 2,
        },
        {
            key = "soak",
            title = L.TWIN_FANGS_ADDONCHECK_COL_SOAK,
            format = TwinFangs.FormatAddonCheckSoak,
        },
    }
end
