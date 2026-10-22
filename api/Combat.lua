local _, ns = ...

local Combat = {}
ns.Api.Combat = Combat

---Whether the player is currently in combat.
---@return boolean
function Combat.IsInCombat()
    return UnitAffectingCombat("player")
end

---Whether protected frame configuration is locked (combat lockdown).
---@return boolean
function Combat.IsLockedDown()
    return InCombatLockdown() == true
end

---Calls `callback` when the player enters combat.
---@param callback fun()
function Combat.OnEnter(callback)
    ns.Api.GameEvents.Listen("PLAYER_REGEN_DISABLED", callback)
end

---Calls `callback` when the player leaves combat.
---@param callback fun()
---@return fun()  Unsubscribe; safe to call more than once.
function Combat.OnLeave(callback)
    return ns.Api.GameEvents.Listen("PLAYER_REGEN_ENABLED", callback)
end
