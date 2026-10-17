-- Read-only capability context for sszorak.communication providers (version 1).
-- This file only forwards calls. Marker assignment, the player's group, arena depth,
-- and localized phrases stay in the modules that already own them. Edge numbers are
-- part of the callout contract. The provider calls GetTime and registers chat and
-- raid-target events itself.

local _, ns = ...
local L = ns.L
local Chat = ns.Api.Chat

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

local SIDE_TEXT = {
    same = L.SSZORAK_SIDE_SAME,
    opposite = L.SSZORAK_SIDE_OPPOSITE,
}

local DEPTH_TEXT = {
    near = L.SSZORAK_DEPTH_NEAR,
    mid = L.SSZORAK_DEPTH_MID,
    far = L.SSZORAK_DEPTH_FAR,
}

---Same-side or opposite-side phrase for `edge`, flipped when the player is on the exit side of the room.
---@param edge integer
---@param fromEntranceSide boolean
---@return string|nil
local function RelativePosition(edge, fromEntranceSide)
    local absoluteDepth = Sszorak:GetEdgeEntranceDepth(edge)
    local edgeGroup = Sszorak:GetEdgeGroup(edge)
    if not absoluteDepth or not edgeGroup then
        return nil
    end
    local depth = absoluteDepth
    if absoluteDepth ~= "mid" and not fromEntranceSide then
        depth = absoluteDepth == "near" and "far" or "near"
    end
    local sideText = edgeGroup == Sszorak:GetPlayerGroup() and SIDE_TEXT.same or SIDE_TEXT.opposite
    local depthText = DEPTH_TEXT[depth]
    if not sideText or not depthText then
        return nil
    end
    return string.format(L.SSZORAK_RELATIVE_POSITION, sideText, depthText)
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
    presentation = ReadOnly({
        ---Jailbreak HUD resolve for `edge`: exit text, or the edge's raid-target icon plus relative position.
        ---`fromEntranceSide` is ignored for the exit edge. Other edges return nil when they have no marker.
        ---@param edge integer
        ---@param fromEntranceSide boolean|nil
        ---@return SszorakCalloutResolve|nil
        Resolve = function(edge, fromEntranceSide)
            if type(edge) ~= "number" then
                return nil
            end
            if edge == Sszorak.EXIT_EDGE then
                return {
                    hudMessage = L.SSZORAK_EXIT,
                    targetEdge = edge,
                }
            end
            local marker = Sszorak:GetEdgeMarker(edge)
            local raidTarget = marker and Sszorak.MARKER_RAID_TARGET[marker]
            if not raidTarget then
                return nil
            end
            local relative = RelativePosition(edge, fromEntranceSide == true)
            if not relative then
                return nil
            end
            return {
                hudMessage = Chat.ReplaceIconAndGroupExpressions("{rt" .. raidTarget .. "}") .. " " .. relative,
                targetEdge = edge,
            }
        end,
    }),
}

ns.Extensions.SetCapabilities(EXTENSION_TYPE, ReadOnly(context))
