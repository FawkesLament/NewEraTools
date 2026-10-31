local _, ns = ...
local Unit = ns.Api.Unit

local Group = {}
ns.Api.Group = Group

---@alias GroupRole "TANK"|"HEALER"|"DAMAGER"|"NONE"

---@class RaidMember
---@field name string  As shown in the roster; no realm for same-realm players.
---@field fullName string  "Name-Realm"; stable across realms.
---@field guid string|nil  Unit GUID when available; preferred local identity key.
---@field index number  GetRaidRosterInfo index; use this for subgroup slot order.
---@field subgroup number
---@field classFile string|nil  e.g. "WARRIOR".
---@field role GroupRole
---@field unit string  `raidN` matching `index`.

local CHANGE_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "PARTY_LEADER_CHANGED",
}

---@type fun(): boolean
Group.IsInRaid = IsInRaid

---@type fun(): boolean
Group.IsInGroup = IsInGroup

---Group size including the player, or 0 when not in a group.
---@return number
function Group.GetNumMembers()
    return GetNumGroupMembers() or 0
end

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
                index = index,
                subgroup = subgroup,
                classFile = classFile,
                role = UnitGroupRolesAssigned(unit),
                unit = unit,
            })
        end
    end
    return members
end

---Whether every current raid roster slot resolved a name. False when not in a raid.
---@return boolean
function Group.HasCompleteRaidRoster()
    if not IsInRaid() then
        return false
    end
    local expected = GetNumGroupMembers()
    if type(expected) ~= "number" or expected < 1 then
        return false
    end
    for index = 1, expected do
        if not GetRaidRosterInfo(index) then
            return false
        end
    end
    return true
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

---Calls `callback` when group membership or composition changes; not for role or leader changes.
---@param callback fun()
function Group.OnRosterChanged(callback)
    ns.Api.GameEvents.Listen("GROUP_ROSTER_UPDATE", function()
        callback()
    end)
end

---Starts a ready check. Only the group leader can succeed; otherwise this is a no-op.
---@type fun()
Group.DoReadyCheck = C_PartyInfo.DoReadyCheck

---Starts a pull countdown for `seconds`. Only the group leader can succeed.
---@type fun(seconds: number): boolean|nil
Group.DoCountdown = C_PartyInfo.DoCountdown

---Stops an active pull countdown. Falls back to a zero-second countdown on older clients.
if C_PartyInfo.CancelCountdown then
    Group.CancelCountdown = C_PartyInfo.CancelCountdown
else
    function Group.CancelCountdown()
        return C_PartyInfo.DoCountdown(0)
    end
end
