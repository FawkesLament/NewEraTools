local _, ns = ...
local L = ns.L
local Chat = ns.Api.Chat
local Util = ns.Util

local Sszorak = ns.Modules.Get("Sszorak")

-- Raid leader callouts saved per home phase; text may be secret values and is stored opaque.
local RAID_LEADER_MESSAGE_LIMIT = 3
-- Anchors are processed in groups of this size; the index within the group selects a saved message.
local WARNING_ANCHOR_GROUP_SIZE = 4

Sszorak.RAID_LEADER_MESSAGE_LIMIT = RAID_LEADER_MESSAGE_LIMIT
Sszorak.WARNING_ANCHOR_GROUP_SIZE = WARNING_ANCHOR_GROUP_SIZE

-- Session-only: first raid leader messages since the last time dots returned home (opaque values).
local raidLeaderMessages = {}
-- Session-only: whether CHAT_MSG_RAID_LEADER is stored (boss fight or map test only).
local raidLeaderCapture = false

local function NotifyRaidLeaderMessagesChanged()
    if Sszorak.OnRaidLeaderMessagesChanged then
        Sszorak:OnRaidLeaderMessagesChanged()
    end
end

local function ClearRaidLeaderMessages()
    Sszorak.ClearDisplayedCallout()
    if #raidLeaderMessages == 0 then
        return
    end
    Util.Wipe(raidLeaderMessages)
    NotifyRaidLeaderMessagesChanged()
end

local function TrySaveRaidLeaderMessage(message)
    if not raidLeaderCapture or #raidLeaderMessages >= RAID_LEADER_MESSAGE_LIMIT then
        return
    end
    table.insert(raidLeaderMessages, message)
    NotifyRaidLeaderMessagesChanged()
end

---Expands raid-target icon tags in a saved raid-leader message for HUD display.
---@param savedMessage any
---@return SszorakCalloutResolve
local function FormatRaidLeaderCallout(savedMessage)
    return {
        hudMessage = Chat.ReplaceIconAndGroupExpressions(savedMessage),
    }
end

---Normal callout mode: show the raid-leader marker text as-is (icon tags expanded); opposite-edge macros.
---@type SszorakCalloutMode
local Normal = {
    id = Sszorak.CALLOUT_MODE_NORMAL,
}

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

---@param anchorIndex integer
---@return SszorakCalloutResolve|nil
function Normal:OnMatchedWarning(anchorIndex)
    local messageIndex = ((anchorIndex - 1) % WARNING_ANCHOR_GROUP_SIZE) + 1
    -- Last slot in each anchor group is always the exit drop (no raid-leader message).
    if messageIndex == WARNING_ANCHOR_GROUP_SIZE then
        return {
            hudMessage = L.SSZORAK_EXIT,
            targetEdge = Sszorak.EXIT_EDGE,
        }
    end
    local message = raidLeaderMessages[messageIndex]
    if message == nil then
        return nil
    end
    return FormatRaidLeaderCallout(message)
end

function Normal:BeginCapture()
    raidLeaderCapture = true
    ClearRaidLeaderMessages()
end

function Normal:EndCapture()
    if not raidLeaderCapture then
        return
    end
    raidLeaderCapture = false
    ClearRaidLeaderMessages()
end

function Normal:ClearMessages()
    ClearRaidLeaderMessages()
end

---@return boolean
function Normal:IsCapturing()
    return raidLeaderCapture
end

---Shared ENCOUNTER_WARNING matching plus raid-leader capture (jailbreak handles chat differently).
---@return fun()
function Normal:Listen()
    local stopWarning = Sszorak.SubscribeSharedCalloutListeners()
    local stopRaidLeader = Chat.OnRaidLeaderMessage(TrySaveRaidLeaderMessage)
    return function()
        stopWarning()
        stopRaidLeader()
    end
end

---@return boolean  Whether raid leader messages are being captured.
function Sszorak:IsCapturingRaidLeaderMessages()
    return raidLeaderCapture
end

---The saved raid leader messages for this home phase (opaque; may be secret values).
---@return table
function Sszorak:GetRaidLeaderMessages()
    return raidLeaderMessages
end

function Sszorak:ClearRaidLeaderMessages()
    ClearRaidLeaderMessages()
end

Sszorak.RegisterCalloutMode(Normal)
