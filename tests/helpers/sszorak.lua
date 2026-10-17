-- Starts a fresh addon so Sszorak specs share one module setup.
local Loader = require("helpers.loader")

local Harness = {}

---Fresh addon, modules started, Sszorak saved defaults.
---@return table ns
---@return table Sszorak
function Harness.Start()
    local ns = Loader.Load()
    ns.Modules.Start(ns.Database.Load(nil))
    return ns, ns.Modules.Get("Sszorak")
end

return Harness
