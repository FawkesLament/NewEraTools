local _, ns = ...
local L = ns.L
local Util = ns.Util
local Encounter = ns.Api.Encounter
local Group = ns.Api.Group
local Timer = ns.Api.Timer
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm
local Timeline = ns.SszorakTimeline

-- MessageProtocol topic for edge-marker sync (payload schema versioned separately below).
local TOPIC_EDGE_MARKERS = "sszorak.edge_markers"
-- Bump when the assignment payload format changes, so older copies ignore payloads they can't read.
local MESSAGE_VERSION = "1"

local ARENA_SIDES = 8
local ENTRANCE_EDGE = 1
local EXIT_EDGE = 5
-- Mythic Sszorak in The Venomous Abyss; matches DBM/WCL encounter ID 3420.
local ENCOUNTER_ID = 3420
-- The boss is tanked on the entrance-exit centerline, near the entrance edge at x = 1.
local BOSS_X = 0.7
-- How far each group stands above or below the boss.
local GROUP_OFFSET = 0.25
-- Path tip sits on each edge's outward bisector at this fraction of the apothem (1).
local PATH_ARROW_RADIUS = 4 / 5
-- Same range as the main panel scale control.
local MAP_SCALE_MIN = 0.8
local MAP_SCALE_MAX = 1.5
local MAP_SCALE_STEP = 0.05
-- Preview plays the same timeline this many times faster than a real pull.
local ANIM_PREVIEW_RATE = 10
local STATION_HOME = Timeline.STATION_HOME
local STATION_CENTER = Timeline.STATION_CENTER
local STATION_FAR = Timeline.STATION_FAR
local STATION_X = {
    [STATION_HOME] = BOSS_X,
    [STATION_CENTER] = 0,
    [STATION_FAR] = -BOSS_X,
}
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
-- Callout mode ids; helpers register implementations against these.
local CALLOUT_MODE_NORMAL = "normal"
local CALLOUT_MODE_JAILBREAK = "jailbreak"
-- Arena side for AddonCheck snapshots (mapRotated false = left / group A, true = right / group B).
local SIDE_LEFT = "left"
local SIDE_RIGHT = "right"
-- Stable AddonCheck provider id; version is owned by AddonCheck, not this snapshot.
local ADDON_CHECK_MODULE_ID = "Sszorak"
-- Raid role: raid leader is commander (macros / sync UI); everyone else is a member.
local RAID_ROLE_MEMBER = "member"
local RAID_ROLE_COMMANDER = "commander"

---@class ArenaPoint
---@field x number
---@field y number  Up is positive.

---@alias SszorakGroup "A"|"B"

---@alias WorldMarker "STAR"|"CIRCLE"|"DIAMOND"|"TRIANGLE"|"MOON"|"SQUARE"|"CROSS"|"SKULL"

---Where the map window sits, as an anchor on the screen.
---@class MapPosition
---@field point string  e.g. "TOPLEFT".
---@field relativePoint string
---@field x number
---@field y number

---@class ArenaEdgeMarker: ArenaPoint  The midpoint of the edge the marker is attached to.
---@field edge integer
---@field marker WorldMarker

-- Placeholder assignment until the raid settles on a marker plan. The entrance and exit get none.
---@type table<integer, WorldMarker>
local DEFAULT_EDGE_MARKERS = {
    [2] = "STAR",
    [3] = "CIRCLE",
    [4] = "DIAMOND",
    [6] = "TRIANGLE",
    [7] = "MOON",
    [8] = "SQUARE",
}

-- Mythic Sszorak, the fifth boss of The Venomous Abyss.
---@class Sszorak: Module
---@field OnEdgeMarkersChanged fun(self: Sszorak)|nil  Defined by the UI file; called after the assignment changes.
---@field OnEncounterChanged fun(self: Sszorak)|nil  Defined by the UI file; called when this boss fight starts or ends.
---@field OnPositionsChanged fun(self: Sszorak)|nil  Defined by the UI file; called when the animated dots move.
---@field OnMapAnimationStarted fun(self: Sszorak)|nil  Defined by the UI file; pull/test timeline began.
---@field OnMapAnimationStopped fun(self: Sszorak)|nil  Defined by the UI file; pull/test timeline ended.
---@field OnRaidLeaderMessagesChanged fun(self: Sszorak)|nil  Defined by the UI file; saved callouts were cleared or appended.
---@field OnCalloutChanged fun(self: Sszorak)|nil  Defined by the UI file; on-screen callout text was shown or cleared.
local Sszorak = ns.Modules.New("Sszorak", {
    defaults = {
        ---@type table<integer, WorldMarker>  Edge index to marker; the entrance and exit have none.
        edgeMarkers = DEFAULT_EDGE_MARKERS,
        -- When true, the map window opens automatically for this boss fight.
        mapEnabled = true,
        -- Turns the map window half a circle, so players standing on the other side see it their way up.
        mapRotated = false,
        -- Scale of the floating arena map window.
        mapScale = 1,
        ---@type MapPosition
        mapPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        ---@type MapPosition  On-screen raid callout text.
        calloutPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 },
        -- Shows RL markers as-is, or jailbreak decrypt/retarget (see CALLOUT_MODE_*).
        calloutMode = CALLOUT_MODE_NORMAL,
    },
})

-- Edge `i` runs from vertex `i` to the next one; see GetArenaVertices.
Sszorak.ARENA_SIDES = ARENA_SIDES
Sszorak.ENTRANCE_EDGE = ENTRANCE_EDGE
Sszorak.EXIT_EDGE = EXIT_EDGE
Sszorak.ENCOUNTER_ID = ENCOUNTER_ID
Sszorak.MAP_SCALE_MIN = MAP_SCALE_MIN
Sszorak.MAP_SCALE_MAX = MAP_SCALE_MAX
Sszorak.MAP_SCALE_STEP = MAP_SCALE_STEP
Sszorak.ANIM_PREVIEW_RATE = ANIM_PREVIEW_RATE
Sszorak.STATION_HOME = STATION_HOME
Sszorak.STATION_CENTER = STATION_CENTER
Sszorak.STATION_FAR = STATION_FAR
Sszorak.MARKER_RAID_TARGET = MARKER_RAID_TARGET
Sszorak.CALLOUT_MODE_NORMAL = CALLOUT_MODE_NORMAL
Sszorak.CALLOUT_MODE_JAILBREAK = CALLOUT_MODE_JAILBREAK
Sszorak.SIDE_LEFT = SIDE_LEFT
Sszorak.SIDE_RIGHT = SIDE_RIGHT
Sszorak.ADDON_CHECK_MODULE_ID = ADDON_CHECK_MODULE_ID
Sszorak.RAID_ROLE_MEMBER = RAID_ROLE_MEMBER
Sszorak.RAID_ROLE_COMMANDER = RAID_ROLE_COMMANDER
Sszorak.PATH_ARROW_RADIUS = PATH_ARROW_RADIUS

-- Session-only: schedule for the current pull / map test (heroic when difficulty is unknown).
---@type SszorakTimelineSchedule
Sszorak.ACTIVE_SCHEDULE = Timeline.GetSchedule()

local function SetActiveSchedule(difficultyID)
    Sszorak.ACTIVE_SCHEDULE = Timeline.GetSchedule(difficultyID)
end

-- Session-only: GetTime() when the current pull/test timeline started.
local pullStartTime = nil
-- Session-only map animation: which horizontal station the dots occupy, and a token to cancel timers.
local positionStation = STATION_HOME
local animToken = 0
local animRate = 1
---@type EncounterWhileIn|nil
local fight = nil

-- Filled by SszorakCallout.lua / SszorakMacros.lua after load (shell must not call methods those files define).
local calloutHooks = {
    beginCapture = function() end,
    endCapture = function() end,
    clearMessages = function() end,
    onStationChanged = function(_from, _to) end,
}
local requestMacroSync = function() end

---Called from SszorakCallout.lua once the callout engine is loaded.
---@param hooks table
function Sszorak.BindCalloutHooks(hooks)
    calloutHooks.beginCapture = hooks.beginCapture
    calloutHooks.endCapture = hooks.endCapture
    calloutHooks.clearMessages = hooks.clearMessages
    calloutHooks.onStationChanged = hooks.onStationChanged
end

---Called from SszorakMacros.lua once macro sync exists.
---@param sync fun()
function Sszorak.BindMacroSync(sync)
    requestMacroSync = sync
end

---Asks the macros layer to rewrite edge macros (no-op until BindMacroSync runs).
---Only the raid leader (commander) keeps macros in sync with marker / callout-mode changes.
function Sszorak.RequestMacroSync()
    if not Sszorak:IsRaidCommander() then
        return
    end
    requestMacroSync()
end

---@type SszorakGroup[]
Sszorak.GROUPS = { "A", "B" }

---@type integer[]
Sszorak.MARKABLE_EDGES = MARKABLE_EDGES

---Every marker the player can choose from, in the game's raid target order.
---@type WorldMarker[]
Sszorak.WORLD_MARKERS = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }

-- Group A stands below the boss, group B above.
local GROUP_DIRECTIONS = {
    A = -1,
    B = 1,
}

local function IsMarkableEdge(edge)
    return type(edge) == "number"
        and edge >= 1
        and edge <= ARENA_SIDES
        and edge % 1 == 0
        and edge ~= ENTRANCE_EDGE
        and edge ~= EXIT_EDGE
end

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
    for edge = 1, ARENA_SIDES do
        if IsMarkableEdge(edge) then
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
    for edge = 1, ARENA_SIDES do
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

local function OppositeEdge(edge)
    return (edge - 1 + ARENA_SIDES / 2) % ARENA_SIDES + 1
end

---The edge opposite `edge` across the arena center.
---@param edge integer
---@return integer
function Sszorak:GetOppositeEdge(edge)
    assert(IsMarkableEdge(edge), "Edge has no opposite marker edge: " .. tostring(edge))
    return OppositeEdge(edge)
end

local function NotifyChanged()
    if Sszorak.OnEdgeMarkersChanged then
        Sszorak:OnEdgeMarkersChanged()
    end
    Sszorak.RequestMacroSync()
end

-- "1:2=STAR,3=CIRCLE,..." with the format version first and edges in order.
local function EncodeAssignment(assignment)
    local parts = {}
    for edge = 1, ARENA_SIDES do
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

---Corners of the arena, a regular octagon with vertical edges on the left and right. Centered on the
---origin with an apothem of 1, so every edge lies 1 from the center. Listed counterclockwise from the
---bottom corner of the right edge, which makes edge 1 the right edge (entrance) and edge 5 the left (exit).
---@return ArenaPoint[]
function Sszorak:GetArenaVertices()
    local halfAngle = math.pi / ARENA_SIDES
    local radius = 1 / math.cos(halfAngle)
    local vertices = {}
    for index = 1, ARENA_SIDES do
        local angle = (2 * index - 3) * halfAngle
        vertices[index] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
    end
    return vertices
end

---Midpoint of arena edge `edge` (1–ARENA_SIDES), including entrance and exit.
---For a regular octagon with apothem 1 this point lies on the edge and on its outward bisector.
---@param edge integer
---@return ArenaPoint
function Sszorak:GetEdgeMidpoint(edge)
    assert(
        type(edge) == "number" and edge >= 1 and edge <= ARENA_SIDES and edge % 1 == 0,
        "Invalid edge: " .. tostring(edge)
    )
    local vertices = self:GetArenaVertices()
    local from, to = vertices[edge], vertices[edge % ARENA_SIDES + 1]
    return { x = (from.x + to.x) / 2, y = (from.y + to.y) / 2 }
end

---Path-arrow tip for `edge`: on the outward perpendicular bisector at PATH_ARROW_RADIUS from center.
---@param edge integer
---@return ArenaPoint
function Sszorak:GetEdgePathPoint(edge)
    local mid = self:GetEdgeMidpoint(edge)
    return { x = mid.x * PATH_ARROW_RADIUS, y = mid.y * PATH_ARROW_RADIUS }
end

---@return ArenaEdgeMarker[]  One per marked edge, in edge order.
function Sszorak:GetEdgeMarkers()
    local markers = {}
    for edge = 1, ARENA_SIDES do
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
    assert(IsMarkableEdge(edge), "Edge can't carry a marker: " .. tostring(edge))
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

---@return boolean  Whether the map opens automatically during this boss fight.
function Sszorak:IsMapEnabled()
    return self.db.mapEnabled == true
end

---@param enabled boolean
function Sszorak:SetMapEnabled(enabled)
    self.db.mapEnabled = enabled == true
end

---@return boolean  Whether the map window is turned 180 degrees.
function Sszorak:IsMapRotated()
    return self.db.mapRotated == true
end

---@param rotated boolean
function Sszorak:SetMapRotated(rotated)
    self.db.mapRotated = rotated == true
end

---@return number
function Sszorak:GetMapScale()
    return Util.Snap(self.db.mapScale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
end

---@param scale number
function Sszorak:SetMapScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.mapScale = Util.Snap(scale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
end

---@return MapPosition
function Sszorak:GetMapPosition()
    return self.db.mapPosition
end

---@param position MapPosition
function Sszorak:SetMapPosition(position)
    assert(type(position.point) == "string" and type(position.relativePoint) == "string", "Bad anchor points")
    assert(type(position.x) == "number" and type(position.y) == "number", "Bad offsets")
    local saved = self.db.mapPosition
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@return MapPosition
function Sszorak:GetCalloutPosition()
    return self.db.calloutPosition
end

---@param position MapPosition
function Sszorak:SetCalloutPosition(position)
    assert(type(position.point) == "string" and type(position.relativePoint) == "string", "Bad anchor points")
    assert(type(position.x) == "number" and type(position.y) == "number", "Bad offsets")
    local saved = self.db.calloutPosition
    saved.point, saved.relativePoint = position.point, position.relativePoint
    saved.x, saved.y = position.x, position.y
end

---@class SszorakAddonCheckConfig
---@field enabled boolean  Feature On/Off (`mapEnabled`).
---@field side "left"|"right"  From mapRotated: false → left, true → right.
---@field mode string  CALLOUT_MODE_NORMAL or CALLOUT_MODE_JAILBREAK.

---Live AddonCheck snapshot. Reads current settings; does not mutate them.
---Invalid or unavailable values error so AddonCheck reports `provider_failed` instead of a fake default.
---@return SszorakAddonCheckConfig
function Sszorak:GetAddonCheckConfig()
    local mapEnabled = self.db.mapEnabled
    if type(mapEnabled) ~= "boolean" then
        error("Sszorak AddonCheck: invalid mapEnabled")
    end
    local mapRotated = self.db.mapRotated
    if type(mapRotated) ~= "boolean" then
        error("Sszorak AddonCheck: invalid mapRotated")
    end
    local mode = self.db.calloutMode
    if mode ~= CALLOUT_MODE_NORMAL and mode ~= CALLOUT_MODE_JAILBREAK then
        error("Sszorak AddonCheck: invalid calloutMode")
    end
    if not Sszorak.IsCalloutModeAvailable(mode) then
        error("Sszorak AddonCheck: unavailable calloutMode")
    end
    return {
        enabled = mapEnabled,
        side = mapRotated and SIDE_RIGHT or SIDE_LEFT,
        mode = mode,
    }
end

---AddonCheck panel validator: column keys to highlight, or nil when ok.
---Flags disabled feature and marker-assignment mode that differs from the commander's snapshot.
---@param config any  Peer's AddonCheck config.
---@param localConfig any  Commander's snapshot from the check session.
---@return string[]|nil
function Sszorak.ValidateAddonCheckConfig(config, localConfig)
    local flagged = {}
    if type(config) ~= "table" or config.enabled ~= true then
        flagged[#flagged + 1] = "enabled"
    end
    if type(config) == "table"
        and type(localConfig) == "table"
        and config.mode ~= nil
        and localConfig.mode ~= nil
        and config.mode ~= localConfig.mode
    then
        flagged[#flagged + 1] = "mode"
    end
    if #flagged == 0 then
        return nil
    end
    return flagged
end

---Raid leader is commander (edge-click macros / sync UI); everyone else is a member.
---@return string
function Sszorak:GetRaidRole()
    if Group.IsPlayerRaidLeader() then
        return RAID_ROLE_COMMANDER
    end
    return RAID_ROLE_MEMBER
end

---@return boolean
function Sszorak:IsRaidCommander()
    return self:GetRaidRole() == RAID_ROLE_COMMANDER
end

---@return boolean
function Sszorak:IsInEncounter()
    return fight ~= nil and fight:IsInside()
end

---Whether a pull or map-test timeline is running.
---@return boolean
function Sszorak:IsMapAnimating()
    return pullStartTime ~= nil
end

---Whether the boss/group dots are at the entrance-side home station.
---@return boolean
function Sszorak:IsAtHomeStation()
    return positionStation == STATION_HOME
end

---Elapsed timeline seconds since the current pull/test started (scaled by animation rate).
---@return number
function Sszorak:GetTimelineElapsed()
    if not pullStartTime then
        return 0
    end
    return (Timer.GetTime() - pullStartTime) * animRate
end

local function NotifyPositionsChanged()
    if Sszorak.OnPositionsChanged then
        Sszorak:OnPositionsChanged()
    end
end

local function NotifyMapAnimationStarted()
    if Sszorak.OnMapAnimationStarted then
        Sszorak:OnMapAnimationStarted()
    end
end

local function NotifyMapAnimationStopped()
    if Sszorak.OnMapAnimationStopped then
        Sszorak:OnMapAnimationStopped()
    end
end

local function SetPositionStation(station)
    if positionStation == station then
        return
    end
    local fromStation = positionStation
    positionStation = station
    if station == STATION_HOME and fromStation ~= STATION_HOME then
        calloutHooks.clearMessages()
    end
    calloutHooks.onStationChanged(fromStation, station)
    NotifyPositionsChanged()
end

local function CurrentPositionX()
    return STATION_X[positionStation]
end

---@class MapAnimationOptions
---@field rate number|nil  How fast timeline seconds elapse. Defaults to 1.

-- Schedules every timeline jump. `token` must still match `animToken` when each fires.
local function SchedulePositionTimeline(token)
    for _, entry in ipairs(Sszorak.ACTIVE_SCHEDULE.positionTimeline) do
        Timer.After(entry.time / animRate, function()
            if token ~= animToken then
                return
            end
            SetPositionStation(entry.station)
        end)
    end
end

---Starts map test mode: fast timeline plus raid leader capture until `EndMapTest`.
function Sszorak:StartMapTest()
    SetActiveSchedule(nil)
    calloutHooks.beginCapture()
    self:StartMapAnimation({ rate = ANIM_PREVIEW_RATE })
end

---Ends map test mode and stops raid leader capture.
function Sszorak:EndMapTest()
    calloutHooks.endCapture()
    self:StopMapAnimation()
end

---Starts (or restarts) the map animation from home and follows `ACTIVE_SCHEDULE`.
---@param options MapAnimationOptions|nil
function Sszorak:StartMapAnimation(options)
    options = options or {}
    animToken = animToken + 1
    local token = animToken
    animRate = options.rate or 1
    pullStartTime = Timer.GetTime()
    positionStation = STATION_HOME
    NotifyPositionsChanged()
    NotifyMapAnimationStarted()
    SchedulePositionTimeline(token)
end

---Stops the map animation and snaps the dots back home.
function Sszorak:StopMapAnimation()
    animToken = animToken + 1
    animRate = 1
    pullStartTime = nil
    SetPositionStation(STATION_HOME)
    NotifyMapAnimationStopped()
end

local function NotifyEncounterChanged()
    if Sszorak.OnEncounterChanged then
        Sszorak:OnEncounterChanged()
    end
end

---Starts watching for this boss fight. Called from OnEnable.
---Map test mode (`StartMapTest`) is separate and does not use this scope.
function Sszorak:ListenForEncounter()
    fight = Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID)
        -- Always restart from pull, even if preview was already animating.
        SetActiveSchedule(difficultyID)
        calloutHooks.beginCapture()
        Sszorak:StartMapAnimation()
        NotifyEncounterChanged()
        return function()
            Sszorak:StopMapAnimation()
            calloutHooks.endCapture()
            NotifyEncounterChanged()
        end
    end)
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

---@return ArenaPoint  In the same coordinates as GetArenaVertices.
function Sszorak:GetBossPosition()
    return { x = CurrentPositionX(), y = 0 }
end

---@param group SszorakGroup
---@return ArenaPoint  In the same coordinates as GetArenaVertices.
function Sszorak:GetGroupPosition(group)
    local direction = assert(GROUP_DIRECTIONS[group], "Unknown group: " .. tostring(group))
    return { x = CurrentPositionX(), y = direction * GROUP_OFFSET }
end

---@return SszorakGroup
function Sszorak:GetPlayerGroup()
    -- Group assignment isn't implemented yet; players rotate the map when they're in group B.
    return self:IsMapRotated() and "B" or "A"
end

function Sszorak:OnInit()
    -- Defaults are merged edge by edge, so a partly saved assignment can come back with a marker repeated.
    if not IsValidAssignment(self.db.edgeMarkers) then
        CopyAssignment(self.db.edgeMarkers, DEFAULT_EDGE_MARKERS)
    end
    self.db.mapScale = Util.Snap(self.db.mapScale, MAP_SCALE_MIN, MAP_SCALE_MAX, MAP_SCALE_STEP)
    if not Sszorak.IsCalloutModeAvailable(self.db.calloutMode) then
        self.db.calloutMode = Sszorak.CALLOUT_MODE_NORMAL
    end
    -- Raid members must answer config checks; register regardless of UI, role, or encounter.
    ns.AddonCheck.Register(ADDON_CHECK_MODULE_ID, function()
        return Sszorak:GetAddonCheckConfig()
    end)
end
