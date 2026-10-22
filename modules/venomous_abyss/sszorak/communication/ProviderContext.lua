-- Read-only capability context for sszorak.communication providers (version 1).
-- This file only forwards calls. The host builds GUI warnings from `targetEdge`
-- in Host.lua.

local _, ns = ...

local Sszorak = ns.Modules.Get("Sszorak")

local EXTENSION_TYPE = "sszorak.communication"
local CONTEXT_VERSION = 1

---@param methods table
---@return table
local function ReadOnly(methods)
    return setmetatable({}, {
        __index = methods,
        __newindex = function()
            error("Sszorak communication capabilities are read-only", 2)
        end,
    })
end

local context = {
    version = CONTEXT_VERSION,
    events = ReadOnly({
        ---Shared encounter-warning filter. The host calls the active mode's OnViscousCystWarning.
        ---@return fun()
        SubscribeViscousCystWarning = function()
            return Sszorak.SubscribeSharedCalloutListeners()
        end,
    }),
}

ns.Extensions.SetCapabilities(EXTENSION_TYPE, ReadOnly(context))
