local _, ns = ...

local RaidTarget = {}
ns.Api.RaidTarget = RaidTarget

---Raid target icon index on `unit` (1–8), or nil when unmarked.
---@type fun(unit: string): number|nil
RaidTarget.GetIndex = GetRaidTargetIndex

---Calls `callback` when any raid target icon assignment changes. Re-query with `GetIndex`.
---@param callback fun()
---@return fun()  Unsubscribe.
function RaidTarget.OnChanged(callback)
    return ns.Api.GameEvents.Listen("RAID_TARGET_UPDATE", callback)
end
