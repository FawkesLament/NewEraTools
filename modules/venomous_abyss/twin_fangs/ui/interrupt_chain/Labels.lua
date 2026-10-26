local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Schema = Internals.Schema
local Chain = Internals.InterruptChain

local Labels = {}
Internals.InterruptChainLabels = Labels

---@param name string
---@return string
local function ShortName(name)
    return name:match("^([^-]+)") or name
end

---@return string
function Labels.RegionLabel(regionId)
    if regionId == Chain.FRONT_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT
    elseif regionId == Chain.FRONT_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT
    elseif regionId == Chain.BACK_LEFT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT
    elseif regionId == Chain.BACK_RIGHT then
        return L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT
    end
    return regionId
end

---@param channel any
---@return string
function Labels.ChannelLabel(channel)
    local key = Schema.CHANNEL_LABELS[Schema.CoerceChannel(channel)]
    return L[key]
end

---@return DropdownItem[]
function Labels.ChannelItems()
    local items = {}
    for _, channel in ipairs(Schema.CHANNEL_IDS) do
        items[#items + 1] = { value = channel, text = Labels.ChannelLabel(channel) }
    end
    return items
end

---@param regionId string
---@param group number|nil
---@param channel any
---@return string
function Labels.AssignmentTitle(regionId, group, channel)
    return string.format(
        "%s  ·  %s  ·  %s",
        Labels.RegionLabel(regionId),
        Labels.GroupLabel(group),
        Labels.ChannelLabel(channel)
    )
end

---@param group number|nil
---@return string
function Labels.GroupLabel(group)
    if Chain.IsRaidGroup(group) then
        return string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP, group)
    end
    return L.TWIN_FANGS_INTERRUPT_RAID_GROUP_NONE
end

---@param roster RaidMember[]
---@param player TwinFangsInterruptPlayer|string|nil
---@return string
function Labels.DisplayName(roster, player)
    if player == nil then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    local name = Chain.PlayerName(player)
    if not name then
        return L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    end
    for _, member in ipairs(roster) do
        if Chain.PlayerName(member.fullName or member.name) == name then
            return ShortName(member.name)
        end
    end
    return ShortName(name)
end

---Empty-state copy for Member View. Does not read or write saved assignments.
---@param chain TwinFangsInterruptChainSettings|nil
---@param inRaid boolean
---@return string
function Labels.MemberViewEmptyText(chain, inRaid)
    if not inRaid then
        return L.TWIN_FANGS_INTERRUPT_NOT_IN_RAID
    end
    if Chain.HasAssignments(chain) then
        return L.TWIN_FANGS_INTERRUPT_NO_ASSIGNMENT
    end
    return L.TWIN_FANGS_INTERRUPT_SYNC_NONE
end

---@param state TwinFangsInterruptChainState
---@param regionId string
---@param group number
---@return string
function Labels.GroupChoiceLabel(state, regionId, group)
    local label = Labels.GroupLabel(group)
    if Chain.IsGroupAssignedElsewhere(state, regionId, group) then
        return string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP_ASSIGNED, group)
    end
    return label
end
