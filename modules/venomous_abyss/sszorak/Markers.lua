local _, ns = ...
local L = ns.L
local Util = ns.Util
local Group = ns.Api.Group
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm

local Sszorak = ns.Modules.Get("Sszorak")

---@alias WorldMarker "STAR"|"CIRCLE"|"DIAMOND"|"TRIANGLE"|"MOON"|"SQUARE"|"CROSS"|"SKULL"

-- MessageProtocol topic for edge-marker sync (payload schema versioned separately below).
local TOPIC_EDGE_MARKERS = "sszorak.edge_markers"
-- Bump when the assignment payload format changes, so older copies ignore payloads they can't read.
local MESSAGE_VERSION = "1"

-- Edges that carry world markers (everything except entrance and exit).
local MARKABLE_EDGES = { 2, 3, 4, 6, 7, 8 }
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

-- Same table as the module defaults, so reset and "is default" stay aligned with saved data.
local DEFAULT_EDGE_MARKERS = Sszorak.defaults.edgeMarkers

---@type integer[]
Sszorak.MARKABLE_EDGES = MARKABLE_EDGES
Sszorak.MARKER_RAID_TARGET = MARKER_RAID_TARGET

---Every marker the player can choose from, in the game's raid target order.
---@type WorldMarker[]
Sszorak.WORLD_MARKERS = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }

local function IsKnownMarker(marker)
    for _, known in ipairs(Sszorak.WORLD_MARKERS) do
        if known == marker then
            return true
        end
    end
    return false
end

-- Valid means every markable edge has a known marker, no marker is used twice, and nothing else is stored.
local function IsValidAssignment(assignment)
    local used = {}
    local count = 0
    for edge = 1, Sszorak.ARENA_SIDES do
        if Sszorak.IsMarkableEdge(edge) then
            local marker = assignment[edge]
            if not IsKnownMarker(marker) or used[marker] then
                return false
            end
            used[marker] = true
            count = count + 1
        end
    end
    for _ in pairs(assignment) do
        count = count - 1
    end
    return count == 0
end

local function IsSameAssignment(a, b)
    for edge = 1, Sszorak.ARENA_SIDES do
        if a[edge] ~= b[edge] then
            return false
        end
    end
    return true
end

local function CopyAssignment(target, source)
    Util.Wipe(target)
    for edge, marker in pairs(source) do
        target[edge] = marker
    end
end

local function NotifyChanged()
    if Sszorak.OnEdgeMarkersChanged then
        Sszorak:OnEdgeMarkersChanged()
    end
    -- Defined by Macros.lua. Marker edits only happen after every file has loaded.
    Sszorak.RequestMacroSync()
end

-- "1:2=STAR,3=CIRCLE,..." with the format version first and edges in order.
local function EncodeAssignment(assignment)
    local parts = {}
    for edge = 1, Sszorak.ARENA_SIDES do
        if assignment[edge] then
            table.insert(parts, edge .. "=" .. assignment[edge])
        end
    end
    return MESSAGE_VERSION .. ":" .. table.concat(parts, ",")
end

---@return table<integer, WorldMarker>|nil  nil if the message is from another format version or invalid.
local function DecodeAssignment(message)
    local version, body = message:match("^(%d+):(.*)$")
    if version ~= MESSAGE_VERSION then
        return nil
    end
    local assignment = {}
    for edge, marker in body:gmatch("(%d+)=(%u+)") do
        assignment[tonumber(edge)] = marker
    end
    if IsValidAssignment(assignment) then
        return assignment
    end
end

-- The sender isn't checked: only leaders and assistants get the send button, which the raid trusts.
-- Wire: MessageProtocol topic sszorak.edge_markers, payload "1:2=SKULL,3=CROSS,...".
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
    if not assignment or IsSameAssignment(assignment, Sszorak.db.edgeMarkers) then
        return
    end
    CopyAssignment(Sszorak.db.edgeMarkers, assignment)
    NotifyChanged()
    Util.Print(string.format(L.SSZORAK_MARKERS_RECEIVED, msg.sender))
end

---Drops a saved assignment that repeats a marker or marks a gate. Called from OnInit.
function Sszorak:RepairEdgeMarkers()
    -- Defaults are merged edge by edge, so a partly saved assignment can come back with a marker repeated.
    if not IsValidAssignment(self.db.edgeMarkers) then
        CopyAssignment(self.db.edgeMarkers, DEFAULT_EDGE_MARKERS)
    end
end

---@return ArenaEdgeMarker[]  One per marked edge, in edge order.
function Sszorak:GetEdgeMarkers()
    local markers = {}
    for edge = 1, Sszorak.ARENA_SIDES do
        local marker = self.db.edgeMarkers[edge]
        if marker then
            local mid = self:GetEdgeMidpoint(edge)
            table.insert(markers, {
                edge = edge,
                marker = marker,
                x = mid.x,
                y = mid.y,
            })
        end
    end
    return markers
end

---@param edge integer
---@return WorldMarker|nil  nil for the entrance and exit.
function Sszorak:GetEdgeMarker(edge)
    return self.db.edgeMarkers[edge]
end

---@param marker WorldMarker
---@return integer|nil  The edge carrying `marker`, or nil if it is unused.
function Sszorak:FindEdgeWithMarker(marker)
    for edge, assigned in pairs(self.db.edgeMarkers) do
        if assigned == marker then
            return edge
        end
    end
end

---Puts `marker` on `edge`. If another edge already carries it, that edge takes `edge`'s old marker,
---so every edge keeps a marker and none repeats.
---@param edge integer  Any edge but the entrance and exit.
---@param marker WorldMarker
function Sszorak:SetEdgeMarker(edge, marker)
    assert(Sszorak.IsMarkableEdge(edge), "Edge can't carry a marker: " .. tostring(edge))
    assert(IsKnownMarker(marker), "Unknown marker: " .. tostring(marker))
    local assignment = self.db.edgeMarkers
    local previous = assignment[edge]
    if previous == marker then
        return
    end
    local other = self:FindEdgeWithMarker(marker)
    if other then
        assignment[other] = previous
    end
    assignment[edge] = marker
    NotifyChanged()
end

---@return boolean
function Sszorak:IsDefaultEdgeMarkers()
    return IsSameAssignment(self.db.edgeMarkers, DEFAULT_EDGE_MARKERS)
end

function Sszorak:ResetEdgeMarkers()
    CopyAssignment(self.db.edgeMarkers, DEFAULT_EDGE_MARKERS)
    NotifyChanged()
end

---Whether the player can sync the marker assignment (raid leader / commander only).
---@return boolean
function Sszorak:CanBroadcastEdgeMarkers()
    return self:IsRaidCommander() and Group.GetRaidChatType() ~= nil
end

---Sends the player's marker assignment to everyone in the raid running this addon, who adopt it.
---Only the raid leader (commander) can send; no-ops silently otherwise.
function Sszorak:BroadcastEdgeMarkers()
    if not self:CanBroadcastEdgeMarkers() then
        return
    end
    -- REALTIME uses NET_RT so marker sync is not starved by control-plane traffic.
    local ok = MessageProtocolComm.Send(
        MessageProtocol.TYPE_EVENT,
        TOPIC_EDGE_MARKERS,
        MessageProtocol.EVENT_CORRELATION_ID,
        EncodeAssignment(self.db.edgeMarkers),
        Group.GetRaidChatType(),
        { trafficClass = MessageProtocolComm.TrafficClass.REALTIME }
    )
    Util.Print(ok and L.SSZORAK_BROADCAST_SENT or L.SSZORAK_BROADCAST_FAILED)
end

---Starts adopting assignments that other clients send. Called from OnEnable.
function Sszorak:ListenForBroadcasts()
    MessageProtocol.RegisterHandler(TOPIC_EDGE_MARKERS, OnAssignmentMessage)
end
