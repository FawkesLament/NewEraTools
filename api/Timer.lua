local _, ns = ...

local Timer = {}
ns.Api.Timer = Timer

---Calls `callback` once after `seconds`.
---@type fun(seconds: number, callback: fun())
Timer.After = C_Timer.After
