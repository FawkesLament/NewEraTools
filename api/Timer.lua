local _, ns = ...

local Timer = {}
ns.Api.Timer = Timer

---Calls `callback` once after `seconds`.
---@type fun(seconds: number, callback: fun())
Timer.After = C_Timer.After

---Repeating timer; first fire after `seconds`. Cancel with `ticker:Cancel()`.
---@type fun(seconds: number, callback: fun(), iterations: number|nil): table
Timer.NewTicker = C_Timer.NewTicker

---One-shot timer; fires after `seconds`. Cancel with `timer:Cancel()`.
---@type fun(seconds: number, callback: fun()): table
Timer.NewTimer = C_Timer.NewTimer or function(seconds, callback)
    return C_Timer.NewTicker(seconds, callback, 1)
end

---Seconds since an arbitrary epoch; differences are elapsed time. Looked up at call time for tests.
---@type fun(): number
Timer.GetTime = GetTime
