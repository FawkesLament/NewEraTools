-- Saved world-marker assignment for Ulatek's eight arena corners.
local _, ns = ...
local L = ns.L
local Util = ns.Util
local Group = ns.Api.Group
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm

local Ulatek = ns.Modules.Get("Ulatek")

---@alias WorldMarker "STAR"|"CIRCLE"|"DIAMOND"|"TRIANGLE"|"MOON"|"SQUARE"|"CROSS"|"SKULL"

---@class ArenaCornerMarker: ArenaPoint  The vertex the marker is attached to.
---@field corner integer
---@field marker WorldMarker

-- MessageProtocol topic for corner-marker sync.
local TOPIC_CORNER_MARKERS = "ulatek.corner_markers"

-- Raid-target icon index for `/raid {rtN}` and the matching targeting-frame texture.
local MARKER_RAID_TARGET = {
    STAR = 1,
    CIRCLE = 2,
    DIAMOND = 3,
    TRIANGLE = 4,
    MOON = 5,
    SQUARE = 6,
    CROSS = 7,
    SKULL = 8,
}

local RAID_TARGET_MARKER = {}
for marker, index in pairs(MARKER_RAID_TARGET) do
    RAID_TARGET_MARKER[index] = marker
end

local DEFAULT_CORNER_MARKERS = Ulatek.defaults.cornerMarkers

Ulatek.MARKER_RAID_TARGET = MARKER_RAID_TARGET

---Every marker the player can choose from, in the game's raid target order.
---@type WorldMarker[]
Ulatek.WORLD_MARKERS = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }

local function IsKnownMarker(marker)
    for _, known in ipairs(Ulatek.WORLD_MARKERS) do
        if known == marker then
            return true
        end
    end
    return false
end

-- SavedVariables may stringify integer keys. ApplyDefaults then fills the missing
-- numeric keys from factory defaults, so a string key is the player's saved choice.
local function MarkerAt(assignment, corner)
    local fromString = assignment[tostring(corner)]
    if fromString ~= nil then
        return fromString
    end
    return assignment[corner]
end

-- Integer keys 1–ARENA_SIDES only. Drops string keys and anything else.
local function CoerceAssignment(assignment)
    local coerced = {}
    if type(assignment) ~= "table" then
        return coerced
    end
    for corner = 1, Ulatek.ARENA_SIDES do
        coerced[corner] = MarkerAt(assignment, corner)
    end
    return coerced
end

-- Valid means every corner has a known marker, no marker is used twice, and nothing else is stored.
local function IsValidAssignment(assignment)
    local used = {}
    local count = 0
    for corner = 1, Ulatek.ARENA_SIDES do
        local marker = assignment[corner]
        if not IsKnownMarker(marker) or used[marker] then
            return false
        end
        used[marker] = true
        count = count + 1
    end
    for _ in pairs(assignment) do
        count = count - 1
    end
    return count == 0
end

local function IsSameAssignment(a, b)
    for corner = 1, Ulatek.ARENA_SIDES do
        if a[corner] ~= b[corner] then
            return false
        end
    end
    return true
end

local function CopyAssignment(target, source)
    Util.Wipe(target)
    for corner, marker in pairs(source) do
        target[corner] = marker
    end
end

local function NotifyChanged()
    if Ulatek.OnCornerMarkersChanged then
        Ulatek:OnCornerMarkersChanged()
    end
end

-- Eight digits, one raid-target index per corner in order: "12345678".
local function EncodeAssignment(assignment)
    local digits = {}
    for corner = 1, Ulatek.ARENA_SIDES do
        digits[corner] = tostring(MARKER_RAID_TARGET[assignment[corner]])
    end
    return table.concat(digits)
end

---@return table<integer, WorldMarker>|nil  nil if the payload is the wrong length or not a permutation of 1–8.
local function DecodeAssignment(message)
    if type(message) ~= "string" or #message ~= Ulatek.ARENA_SIDES then
        return nil
    end
    local assignment = {}
    local used = {}
    for corner = 1, Ulatek.ARENA_SIDES do
        local index = tonumber(message:sub(corner, corner))
        local marker = RAID_TARGET_MARKER[index]
        if not marker or used[marker] then
            return nil
        end
        used[marker] = true
        assignment[corner] = marker
    end
    return assignment
end

-- The sender isn't checked: only the raid leader sees the send button, which the raid trusts.
-- Wire: MessageProtocol topic ulatek.corner_markers, payload "12345678".
---@param msg MessageProtocolMessage
local function OnAssignmentMessage(msg)
    if msg.type ~= MessageProtocol.TYPE_EVENT then
        return
    end
    if msg.channel ~= Group.GetRaidChatType() then
        return
    end
    local assignment = DecodeAssignment(msg.payload)
    -- Senders receive their own messages too, and need no notice about an assignment they already have.
    if not assignment or IsSameAssignment(assignment, Ulatek.db.cornerMarkers) then
        return
    end
    CopyAssignment(Ulatek.db.cornerMarkers, assignment)
    NotifyChanged()
    Util.Print(string.format(L.ULATEK_MARKERS_RECEIVED, msg.sender))
end

---Rewrites the saved assignment to integer keys. Drops a table that repeats a marker or skips a corner.
---Called from OnInit so SavedVariables keep the player's choices.
function Ulatek:RepairCornerMarkers()
    local coerced = CoerceAssignment(self.db.cornerMarkers)
    if IsValidAssignment(coerced) then
        CopyAssignment(self.db.cornerMarkers, coerced)
    else
        CopyAssignment(self.db.cornerMarkers, DEFAULT_CORNER_MARKERS)
    end
end

---@return ArenaCornerMarker[]  One per corner, in corner order.
function Ulatek:GetCornerMarkers()
    local markers = {}
    for corner = 1, Ulatek.ARENA_SIDES do
        local marker = self.db.cornerMarkers[corner]
        local point = self:GetCornerPoint(corner)
        table.insert(markers, {
            corner = corner,
            marker = marker,
            x = point.x,
            y = point.y,
        })
    end
    return markers
end

---@param corner integer
---@return WorldMarker
function Ulatek:GetCornerMarker(corner)
    return self.db.cornerMarkers[corner]
end

---@param marker WorldMarker
---@return integer|nil  The corner carrying `marker`, or nil if it is unused.
function Ulatek:FindCornerWithMarker(marker)
    for corner, assigned in pairs(self.db.cornerMarkers) do
        if assigned == marker then
            return corner
        end
    end
end

---Puts `marker` on `corner`. If another corner already carries it, that corner takes `corner`'s old
---marker, so every corner keeps a marker and none repeats.
---@param corner integer
---@param marker WorldMarker
function Ulatek:SetCornerMarker(corner, marker)
    assert(Ulatek.IsArenaCorner(corner), "Invalid corner: " .. tostring(corner))
    assert(IsKnownMarker(marker), "Unknown marker: " .. tostring(marker))
    local assignment = self.db.cornerMarkers
    local previous = assignment[corner]
    if previous == marker then
        return
    end
    local other = self:FindCornerWithMarker(marker)
    if other then
        assignment[other] = previous
    end
    assignment[corner] = marker
    NotifyChanged()
end

---@return boolean
function Ulatek:IsDefaultCornerMarkers()
    return IsSameAssignment(self.db.cornerMarkers, DEFAULT_CORNER_MARKERS)
end

function Ulatek:ResetCornerMarkers()
    CopyAssignment(self.db.cornerMarkers, DEFAULT_CORNER_MARKERS)
    NotifyChanged()
end

---Whether the player can sync the marker assignment (raid leader / commander only).
---@return boolean
function Ulatek:CanBroadcastCornerMarkers()
    return self:IsRaidCommander() and Group.GetRaidChatType() ~= nil
end

---Sends the player's marker assignment to everyone in the raid running this addon, who adopt it.
---Only the raid leader (commander) can send; no-ops silently otherwise.
function Ulatek:BroadcastCornerMarkers()
    if not self:CanBroadcastCornerMarkers() then
        return
    end
    -- REALTIME uses NET_RT so marker sync is not starved by control-plane traffic.
    local ok = MessageProtocolComm.Send(
        MessageProtocol.TYPE_EVENT,
        TOPIC_CORNER_MARKERS,
        MessageProtocol.EVENT_CORRELATION_ID,
        EncodeAssignment(self.db.cornerMarkers),
        Group.GetRaidChatType(),
        { trafficClass = MessageProtocolComm.TrafficClass.REALTIME }
    )
    Util.Print(ok and L.ULATEK_BROADCAST_SENT or L.ULATEK_BROADCAST_FAILED)
end

---Starts adopting assignments that other clients send. Called from OnEnable.
function Ulatek:ListenForBroadcasts()
    MessageProtocol.RegisterHandler(TOPIC_CORNER_MARKERS, OnAssignmentMessage)
end
