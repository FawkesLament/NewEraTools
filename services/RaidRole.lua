local _, ns = ...
local Group = ns.Api.Group

---Raid-leader commander vs everyone else. Shared by encounter helpers that switch UI/behavior.
local RaidRole = {}
ns.RaidRole = RaidRole

RaidRole.MEMBER = "member"
RaidRole.COMMANDER = "commander"

---Raid leader is commander; anyone else (including not in a raid) is a member.
---@return string
function RaidRole.Get()
    if Group.IsPlayerRaidLeader() then
        return RaidRole.COMMANDER
    end
    return RaidRole.MEMBER
end

---@return boolean
function RaidRole.IsCommander()
    return RaidRole.Get() == RaidRole.COMMANDER
end

---Adds GetRaidRole / IsRaidCommander and the role id constants on `module`.
---@param module table
function RaidRole.Attach(module)
    module.RAID_ROLE_MEMBER = RaidRole.MEMBER
    module.RAID_ROLE_COMMANDER = RaidRole.COMMANDER

    function module:GetRaidRole()
        return RaidRole.Get()
    end

    function module:IsRaidCommander()
        return RaidRole.IsCommander()
    end
end
