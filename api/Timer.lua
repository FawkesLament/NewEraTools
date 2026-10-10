local _, ns = ...

local Timer = {}
ns.Api.Timer = Timer

---Calls `callback` once after `seconds`.
---@type fun(seconds: number, callback: fun())
Timer.After = C_Timer.After

---Repeating timer; first fire after `seconds`. Cancel with `ticker:Cancel()`.
---@type fun(seconds: number, callback: fun(), iterations: number|nil): table
Timer.NewTicker = C_Timer.NewTicker

---Seconds since an arbitrary epoch; differences are elapsed time. Looked up at call time for tests.
---@type fun(): number
Timer.GetTime = GetTime
