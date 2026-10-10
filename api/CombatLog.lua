local _, ns = ...

local CombatLog = {}
ns.Api.CombatLog = CombatLog

---Whether combat logging is enabled.
---Returns nil when the call is rate-limited (unknown); never treat nil as false.
---Heavily rate-limited by the client (~5 calls / 10s across all addons); do not call often.
---@return boolean|nil
function CombatLog.IsLogging()
    return LoggingCombat()
end

---Enables or disables combat logging.
---Returns the new state, or nil when rate-limited.
---@param enabled boolean
---@return boolean|nil
function CombatLog.SetLogging(enabled)
    return LoggingCombat(enabled == true)
end
