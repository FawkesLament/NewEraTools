local _, ns = ...
local Chat = ns.Api.Chat

local Sszorak = ns.Modules.Get("Sszorak")

---Normal callout mode: show the raid-leader marker text as-is (icon tags expanded); opposite-edge macros.
---@type SszorakCalloutMode
local Normal = {
    id = Sszorak.CALLOUT_MODE_NORMAL,
}

---@param savedMessage any
---@param _context table|nil
---@return SszorakCalloutResolve
function Normal:Resolve(savedMessage, _context)
    return {
        hudMessage = Chat.ReplaceIconAndGroupExpressions(savedMessage),
    }
end

---@param edge integer
---@param assignment table<integer, WorldMarker>
---@return string
function Normal:GetEdgeMacroBody(edge, assignment)
    local opposite = Sszorak:GetOppositeEdge(edge)
    local oppositeMarker = assert(assignment[opposite], "Missing opposite marker")
    local raidTarget =
        assert(Sszorak.MARKER_RAID_TARGET[oppositeMarker], "Unknown marker: " .. tostring(oppositeMarker))
    return "/raid {rt" .. raidTarget .. "}"
end

---Raid-leader capture + encounter-warning matching (shared with jailbreak).
---@return fun()
function Normal:Listen()
    return Sszorak.SubscribeSharedCalloutListeners()
end

Sszorak.RegisterCalloutMode(Normal)
