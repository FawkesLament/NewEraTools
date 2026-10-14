local _, ns = ...
local Unit = ns.Api.Unit

local Group = {}
ns.Api.Group = Group

---@alias GroupRole "TANK"|"HEALER"|"DAMAGER"|"NONE"

---@class RaidMember
---@field name string  As shown in the roster; no realm for same-realm players.
---@field fullName string  "Name-Realm"; stable across realms.
---@field guid string|nil  Unit GUID when available; preferred local identity key.
---@field subgroup number
---@field classFile string|nil  e.g. "WARRIOR".
---@field role GroupRole

local CHANGE_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "PARTY_LEADER_CHANGED",
}

---@return RaidMember[]  Roster order; empty when not in a raid.
function Group.GetRaidMembers()
    local members = {}
    if not IsInRaid() then
        return members
    end
    for index = 1, GetNumGroupMembers() do
        local unit = "raid" .. index
        local name, _, subgroup, _, _, classFile = GetRaidRosterInfo(index)
        if name then
            -- NPC raid members may not report a class through the roster API.
            if not classFile or classFile == "" then
                classFile = Unit.GetClassFile(unit)
            end
            table.insert(members, {
                name = name,
                fullName = Unit.GetFullName(name),
                guid = Unit.GetGUID(unit),
                subgroup = subgroup,
                classFile = classFile,
                role = UnitGroupRolesAssigned(unit),
            })
        end
    end
    return members
end

---@alias PartyCategoryType number

-- A player can be in a home raid and an instance (e.g. LFR) raid at once; the home raid takes precedence.
---@return PartyCategoryType|nil
local function GetRaidCategory()
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        return LE_PARTY_CATEGORY_HOME
    elseif IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then
        return LE_PARTY_CATEGORY_INSTANCE
    end
end

---@return ChatType|nil  "RAID", "INSTANCE_CHAT" for instance (e.g. LFR) raids, or nil when not in a raid.
function Group.GetRaidChatType()
    local category = GetRaidCategory()
    if category == LE_PARTY_CATEGORY_HOME then
        return "RAID"
    elseif category == LE_PARTY_CATEGORY_INSTANCE then
        return "INSTANCE_CHAT"
    end
end

---@return boolean  Whether the player leads the current raid; false when not in a raid.
function Group.IsPlayerRaidLeader()
    local category = GetRaidCategory()
    if not category then
        return false
    end
    return UnitIsGroupLeader("player", category)
end

---Raid leader as "Name-Realm", or nil when not in a raid / leader cannot be resolved.
---@return string|nil
function Group.GetRaidLeaderFullName()
    if not IsInRaid() then
        return nil
    end
    for index = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(index)
        -- GetRaidRosterInfo rank: 2 = leader, 1 = assistant, 0 = member.
        if name and rank == 2 then
            return Unit.GetFullName(name)
        end
    end
end

---@return boolean  Whether the player leads or assists the current raid; false when not in a raid.
function Group.IsPlayerRaidLeaderOrAssistant()
    local category = GetRaidCategory()
    if not category then
        return false
    end
    return UnitIsGroupLeader("player", category) or UnitIsGroupAssistant("player")
end

---Calls `callback` whenever the roster, roles, or leadership change.
---@param callback fun()
function Group.OnChanged(callback)
    for _, event in ipairs(CHANGE_EVENTS) do
        ns.Api.GameEvents.Listen(event, function()
            callback()
        end)
    end
end
