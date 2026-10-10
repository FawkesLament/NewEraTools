local _, ns = ...
local L = ns.L
local Util = ns.Util
local Chat = ns.Api.Chat
local Group = ns.Api.Group
local Timer = ns.Api.Timer

local MAX_COUNT = 40
local SEND_INTERVAL = 0.2

local ROLE_ORDER = {
    TANK = 1,
    HEALER = 2,
    DAMAGER = 3,
}
local UNASSIGNED_ROLE_ORDER = 4

---@alias RaidLotteryRole "ALL"|"DAMAGER"|"HEALER"|"TANK"

local ROLE_ALL = "ALL"

local ROLE_LABELS = {
    ALL = L.RAID_LOTTERY_ROLE_ALL,
    DAMAGER = L.RAID_LOTTERY_ROLE_DAMAGER,
    HEALER = L.RAID_LOTTERY_ROLE_HEALER,
    TANK = L.RAID_LOTTERY_ROLE_TANK,
}

---@class RaidLottery: Module
---@field OnSendingChanged fun(self: RaidLottery)|nil  Defined by the UI file; called when sending starts or stops.
local RaidLottery = ns.Modules.New("RaidLottery", {
    defaults = {
        count = 1,
        role = ROLE_ALL,
        excluded = {},
    },
})

---Role filters in display order.
---@type RaidLotteryRole[]
RaidLottery.ROLES = { ROLE_ALL, "DAMAGER", "HEALER", "TANK" }

local sending = false

local function CompareMembers(a, b)
    local aRole = ROLE_ORDER[a.role] or UNASSIGNED_ROLE_ORDER
    local bRole = ROLE_ORDER[b.role] or UNASSIGNED_ROLE_ORDER
    if aRole ~= bRole then
        return aRole < bRole
    end
    if a.subgroup ~= b.subgroup then
        return a.subgroup < b.subgroup
    end
    return a.name < b.name
end

local function IsKnownRole(role)
    for _, known in ipairs(RaidLottery.ROLES) do
        if known == role then
            return true
        end
    end
    return false
end

-- Only exclusions within the role filter count: excluding a DPS doesn't narrow a healer draw.
local function FormatResultHeader(members)
    local excludedInScope = 0
    for _, member in ipairs(members) do
        if RaidLottery:MatchesRole(member) and RaidLottery:IsExcluded(member) then
            excludedInScope = excludedInScope + 1
        end
    end
    local roleLabel = RaidLottery:GetRoleLabel(RaidLottery:GetRole())
    if excludedInScope > 0 then
        return string.format(L.RAID_LOTTERY_RESULT_HEADER_EXCLUDED, roleLabel, excludedInScope)
    end
    return string.format(L.RAID_LOTTERY_RESULT_HEADER, roleLabel)
end

local function SetSending(value)
    sending = value
    if RaidLottery.OnSendingChanged then
        RaidLottery:OnSendingChanged()
    end
end

local function SendMessages(messages, chatType)
    SetSending(true)

    local index = 0
    local function SendNext()
        index = index + 1
        if Group.GetRaidChatType() ~= chatType then
            Util.Print(L.RAID_LOTTERY_LEFT_RAID)
        else
            Chat.Send(messages[index], chatType)
            if index < #messages then
                Timer.After(SEND_INTERVAL, SendNext)
                return
            end
        end
        SetSending(false)
    end
    SendNext()
end

---@return integer
function RaidLottery:GetCount()
    return self.db.count
end

---Stores `value` rounded down and clamped to 1..MAX_COUNT.
---@param value number
function RaidLottery:SetCount(value)
    self.db.count = Util.Clamp(math.floor(value), 1, MAX_COUNT)
end

---@param eligibleCount integer
---@return integer  The largest count that can be drawn from `eligibleCount` members; at least 1.
function RaidLottery:GetMaxCount(eligibleCount)
    return Util.Clamp(eligibleCount, 1, MAX_COUNT)
end

---Lowers the count so it doesn't exceed `eligibleCount`. Leaves it alone when nobody is eligible,
---since the roster is briefly empty while it loads.
---@param eligibleCount integer
function RaidLottery:FitCount(eligibleCount)
    if eligibleCount >= 1 and self.db.count > eligibleCount then
        self.db.count = eligibleCount
    end
end

---@return RaidLotteryRole
function RaidLottery:GetRole()
    local role = self.db.role
    return IsKnownRole(role) and role or ROLE_ALL
end

---@param role RaidLotteryRole
function RaidLottery:SetRole(role)
    assert(IsKnownRole(role), "Unknown role: " .. tostring(role))
    self.db.role = role
end

---@param role RaidLotteryRole
---@return string
function RaidLottery:GetRoleLabel(role)
    return ROLE_LABELS[role]
end

---@param member RaidMember
---@return boolean  Whether the member's assigned role passes the role filter.
function RaidLottery:MatchesRole(member)
    local role = self:GetRole()
    return role == ROLE_ALL or member.role == role
end

---@return RaidMember[]  Sorted by role, then subgroup, then name.
function RaidLottery:GetMembers()
    local members = Group.GetRaidMembers()
    table.sort(members, CompareMembers)
    return members
end

---@param member RaidMember
---@return boolean
function RaidLottery:IsExcluded(member)
    return self.db.excluded[member.fullName] == true
end

---@param member RaidMember
---@param excluded boolean
function RaidLottery:SetExcluded(member, excluded)
    self.db.excluded[member.fullName] = excluded or nil
end

function RaidLottery:ClearExcluded()
    Util.Wipe(self.db.excluded)
end

---@param members RaidMember[]
---@return integer  How many of `members` are excluded; exclusions of absent players don't count.
function RaidLottery:GetExcludedCount(members)
    local count = 0
    for _, member in ipairs(members) do
        if self:IsExcluded(member) then
            count = count + 1
        end
    end
    return count
end

---Forgets exclusions of players who are no longer in the raid. An empty roster changes nothing,
---since it is also what the game reports while the roster loads.
---@param members RaidMember[]
function RaidLottery:PruneExcluded(members)
    if #members == 0 then
        return
    end
    local present = {}
    for _, member in ipairs(members) do
        present[member.fullName] = true
    end
    for fullName in pairs(self.db.excluded) do
        if not present[fullName] then
            self.db.excluded[fullName] = nil
        end
    end
end

---@param members RaidMember[]
---@return RaidMember[]  Members that pass the role filter and aren't excluded.
function RaidLottery:GetEligible(members)
    local eligible = {}
    for _, member in ipairs(members) do
        if self:MatchesRole(member) and not self:IsExcluded(member) then
            table.insert(eligible, member)
        end
    end
    return eligible
end

---@return boolean
function RaidLottery:IsSending()
    return sending
end

---@return string|nil  Why the player can't use this feature, or nil if they can.
function RaidLottery:GetAccessBlockedReason()
    if not Group.GetRaidChatType() then
        return L.RAID_LOTTERY_BLOCKED_NOT_IN_RAID
    end
    if not Group.IsPlayerRaidLeaderOrAssistant() then
        return L.RAID_LOTTERY_BLOCKED_NOT_LEADER
    end
end

---@param eligibleCount integer|nil  Size of the eligible pool; computed from the roster if nil.
---@return string|nil  Why the player can't start a draw right now, or nil if they can.
function RaidLottery:GetBlockedReason(eligibleCount)
    local accessBlocked = self:GetAccessBlockedReason()
    if accessBlocked then
        return accessBlocked
    end
    eligibleCount = eligibleCount or #self:GetEligible(self:GetMembers())
    if eligibleCount < self.db.count then
        return string.format(L.RAID_LOTTERY_NOT_ENOUGH, self.db.count, eligibleCount)
    end
end

---Picks random eligible members and announces them in raid chat, one message per line.
function RaidLottery:Draw()
    if sending then
        return
    end
    local members = self:GetMembers()
    local pool = self:GetEligible(members)
    local blockedReason = self:GetBlockedReason(#pool)
    if blockedReason then
        Util.Print(blockedReason)
        return
    end

    local count = self.db.count
    for i = 1, count do
        local j = math.random(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
    end

    local messages = { FormatResultHeader(members) }
    for i = 1, count do
        table.insert(messages, pool[i].name)
    end
    SendMessages(messages, Group.GetRaidChatType())
end
