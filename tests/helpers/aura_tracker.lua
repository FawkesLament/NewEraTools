local Loader = require("helpers.loader")

local Harness = {}

---Fresh addon, modules started, empty Aura Tracker db.
---@return table ns, table AuraTracker, table Activation, table Schema
function Harness.Start()
    local ns = Loader.Load()
    ns.Modules.Start(ns.Database.Load(nil))
    return ns, ns.Modules.Get("AuraTracker"), ns.AuraTrackerActivation, ns.AuraTrackerSchema
end

return Harness
