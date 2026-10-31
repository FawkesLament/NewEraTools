local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local Group = ns.Api.Group
local Unit = ns.Api.Unit

local MAX_GROUPS = 6
local MAX_GROUP_SIZE = 5

local PREVIEW_CLASSES = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
}

---@class TwinFangsVenomRosterMember
---@field name string
---@field subgroup number
---@field index number  GetRaidRosterInfo index; within-group order.
---@field classFile string|nil
---@field unit string|nil
---@field guid string|nil
---@field fullName string|nil

---@class TwinFangsVenomRosterColumn
---@field group number
---@field members TwinFangsVenomRosterMember[]

local VenomRoster = {
    MAX_GROUPS = MAX_GROUPS,
    MAX_GROUP_SIZE = MAX_GROUP_SIZE,
}
Internals.VenomRoster = VenomRoster

---@param roster TwinFangsVenomRosterMember[]|nil
---@return TwinFangsVenomRosterMember[]
local function MembersInRosterIndexOrder(roster)
    local ordered = {}
    if type(roster) ~= "table" then
        return ordered
    end
    local allIndexed = true
    for index, member in ipairs(roster) do
        ordered[index] = member
        if type(member.index) ~= "number" then
            allIndexed = false
        end
    end
    if allIndexed then
        table.sort(ordered, function(a, b)
            return a.index < b.index
        end)
    end
    return ordered
end

---@param group number
---@return boolean
local function IsTrackedGroup(group)
    return type(group) == "number" and group >= 1 and group <= MAX_GROUPS
end

---Groups populated raid members into subgroup columns. Empty subgroups are omitted.
---Order within a group follows roster index, never stacks or unit-token sequence.
---@param roster TwinFangsVenomRosterMember[]|nil
---@return TwinFangsVenomRosterColumn[]
function VenomRoster.Organize(roster)
    local buckets = {}
    for group = 1, MAX_GROUPS do
        buckets[group] = {}
    end
    for _, member in ipairs(MembersInRosterIndexOrder(roster)) do
        local group = member.subgroup
        if IsTrackedGroup(group) then
            local list = buckets[group]
            if #list < MAX_GROUP_SIZE then
                list[#list + 1] = member
            end
        end
    end
    local columns = {}
    for group = 1, MAX_GROUPS do
        local members = buckets[group]
        if #members > 0 then
            columns[#columns + 1] = {
                group = group,
                members = members,
            }
        end
    end
    return columns
end

---@param index number
---@return number
function VenomRoster.PreviewStackCount(index)
    return (index - 1) % 10
end

---@param members TwinFangsVenomRosterMember[]
---@return table<number, number>
function VenomRoster.PreviewStacksByIndex(members)
    local stacks = {}
    for _, member in ipairs(members) do
        stacks[member.index] = VenomRoster.PreviewStackCount(member.index)
    end
    return stacks
end

---@param index number
---@param subgroup number
---@return TwinFangsVenomRosterMember
local function PreviewMember(index, subgroup)
    return {
        name = "Player" .. index,
        fullName = "Player" .. index .. "-Venom",
        guid = "Player-VENOM-" .. index,
        index = index,
        subgroup = subgroup,
        classFile = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1],
        unit = "raid" .. index,
        role = "DAMAGER",
    }
end

---@param counts table<number, number>
---@return TwinFangsVenomRosterMember[]
local function MembersFromGroupCounts(counts)
    local members = {}
    local index = 0
    for group = 1, MAX_GROUPS do
        local count = counts[group]
        if type(count) == "number" and count > 0 then
            for _ = 1, math.min(count, MAX_GROUP_SIZE) do
                index = index + 1
                members[index] = PreviewMember(index, group)
            end
        end
    end
    return members
end

---@param size number
---@return TwinFangsVenomRosterMember[]
local function SequentialMembers(size)
    local counts = {}
    local remaining = math.max(0, math.min(size, MAX_GROUPS * MAX_GROUP_SIZE))
    for group = 1, MAX_GROUPS do
        local count = math.min(MAX_GROUP_SIZE, remaining)
        counts[group] = count
        remaining = remaining - count
        if remaining <= 0 then
            break
        end
    end
    return MembersFromGroupCounts(counts)
end

local NAMED_PRESETS = {
    gaps = { [1] = 2, [3] = 4, [5] = 3 },
    uneven = { [1] = 5, [2] = 1, [4] = 3 },
}

VenomRoster.DEFAULT_PREVIEW_SPEC = "20"
VenomRoster.PREVIEW_SPECS = { "1", "5", "10", "20", "30", "uneven", "gaps" }

---@param spec any
---@return string
function VenomRoster.CoercePreviewSpec(spec)
    if spec == nil then
        return VenomRoster.DEFAULT_PREVIEW_SPEC
    end
    local id = tostring(spec)
    for _, known in ipairs(VenomRoster.PREVIEW_SPECS) do
        if known == id then
            return known
        end
    end
    return VenomRoster.DEFAULT_PREVIEW_SPEC
end

---Development-only mock raid. Live combat must not call this.
---@param spec number|string|table|nil
---@return TwinFangsVenomRosterMember[]
function VenomRoster.BuildPreviewMembers(spec)
    if spec == nil then
        return SequentialMembers(20)
    end
    if type(spec) == "number" then
        return SequentialMembers(spec)
    end
    if type(spec) == "string" then
        local size = tonumber(spec)
        if size then
            return SequentialMembers(size)
        end
        local preset = NAMED_PRESETS[spec]
        if preset then
            return MembersFromGroupCounts(preset)
        end
        return {}
    end
    if type(spec) ~= "table" then
        return {}
    end
    if type(spec.groups) == "table" then
        local members = {}
        for _, group in ipairs(spec.groups) do
            if IsTrackedGroup(group) then
                members[#members + 1] = PreviewMember(#members + 1, group)
            end
        end
        return members
    end
    local counts = spec.counts or spec
    return MembersFromGroupCounts(counts)
end

---@param unit string
---@param index number
---@param subgroup number
---@return TwinFangsVenomRosterMember|nil
local function MemberFromUnit(unit, index, subgroup)
    local name = Unit.GetName(unit)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return {
        name = name,
        fullName = Unit.GetFullName(name),
        guid = Unit.GetGUID(unit),
        index = index,
        subgroup = subgroup,
        classFile = Unit.GetClassFile(unit),
        unit = unit,
    }
end

---Live raid, party, or solo roster with unit tokens. Raid members keep subgroup and index
---from GetRaidRosterInfo; party/solo testing is a single group-1 column.
---@return TwinFangsVenomRosterMember[]
function VenomRoster.CollectLiveMembers()
    if Group.IsInRaid() then
        local members = Group.GetRaidMembers()
        for _, member in ipairs(members) do
            if type(member.unit) ~= "string" or member.unit == "" then
                member.unit = "raid" .. member.index
            end
        end
        return members
    end
    local members = {}
    local player = MemberFromUnit("player", 1, 1)
    if player then
        members[1] = player
    end
    if not Group.IsInGroup() then
        return members
    end
    local grouped = Group.GetNumMembers()
    if type(grouped) ~= "number" or grouped < 2 then
        return members
    end
    for partyIndex = 1, grouped - 1 do
        local member = MemberFromUnit("party" .. partyIndex, #members + 1, 1)
        if member then
            members[#members + 1] = member
        end
    end
    return members
end
