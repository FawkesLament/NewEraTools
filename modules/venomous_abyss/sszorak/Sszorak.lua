local _, ns = ...
local L = ns.L
local Util = ns.Util
local AddonMessage = ns.Api.AddonMessage
local Encounter = ns.Api.Encounter
local Group = ns.Api.Group
local Timer = ns.Api.Timer

-- Addon message prefixes are limited to 16 characters.
local MESSAGE_PREFIX = "NewEraToolsSsz"
-- Bump when the message format changes, so older copies of the addon ignore messages they can't read.
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
-- Same range as the main panel scale control.
local MAP_SCALE_MIN = 0.8
local MAP_SCALE_MAX = 1.5
local MAP_SCALE_STEP = 0.05
-- Seconds from each animation cycle start when the dots jump to the next horizontal station.
local ANIM_T1 = 37
local ANIM_T2 = 50
local ANIM_T3 = 84
local ANIM_T4 = 127
-- Encounter pull only: timeline clock starts here so the first cycle lines up with ENCOUNTER_START.
local ANIM_ENCOUNTER_START_TIME = -3
-- Preview plays the same stations this many times faster than a real pull.
local ANIM_PREVIEW_RATE = 10
-- Horizontal stations in cycle order: home (entrance side), center, far (exit side), center again.
local STATION_HOME = 1
local STATION_CENTER = 2
local STATION_FAR = 3
local STATION_CENTER_AGAIN = 4
local STATION_X = {
    [STATION_HOME] = BOSS_X,
    [STATION_CENTER] = 0,
    [STATION_FAR] = -BOSS_X,
    [STATION_CENTER_AGAIN] = 0,
}
-- Absolute times in a cycle when the raid moves to stations 2, 3, 4, then back to 1.
local STATION_MOVE_TIMES = { ANIM_T1, ANIM_T2, ANIM_T3, ANIM_T4 }
-- Gale winds hit 3 vents; the two DoT rounds place cysts on the opposite (downwind) vents.
local WIND_VENT_COUNT = 3
local CYST_ROUND1_COUNT = 2
-- Entrance edge midpoint in arena coordinates (apothem 1 on +x).
local ENTRANCE_MID_X = 1
local ENTRANCE_MID_Y = 0

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
---@class SszorakCystPlan
---@field round1 integer[]  Downwind edges for the first DoT round (closest to the entrance).
---@field round2 integer[]  Downwind edges for the second DoT round (remaining).

---@class Sszorak: Module
---@field OnEdgeMarkersChanged fun(self: Sszorak)|nil  Defined by the UI file; called after the assignment changes.
---@field OnEncounterChanged fun(self: Sszorak)|nil  Defined by the UI file; called when this boss fight starts or ends.
---@field OnPositionsChanged fun(self: Sszorak)|nil  Defined by the UI file; called when the animated dots move.
---@field OnWindHelperChanged fun(self: Sszorak)|nil  Defined by the UI file; called when wind vents or the helper toggle change.
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
        -- When true, the raid leader can pick wind vents on the encounter map for cyst shot-calls.
        windHelperEnabled = true,
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
Sszorak.ANIM_T1 = ANIM_T1
Sszorak.ANIM_T2 = ANIM_T2
Sszorak.ANIM_T3 = ANIM_T3
Sszorak.ANIM_T4 = ANIM_T4
Sszorak.ANIM_ENCOUNTER_START_TIME = ANIM_ENCOUNTER_START_TIME
Sszorak.ANIM_PREVIEW_RATE = ANIM_PREVIEW_RATE
Sszorak.WIND_VENT_COUNT = WIND_VENT_COUNT

-- Session-only: whether the player is currently in this boss fight. Not saved across reloads.
local inEncounter = false
-- Session-only map animation: which horizontal station the dots occupy, and a token to cancel timers.
local positionStation = STATION_HOME
local animToken = 0
local animRate = 1
-- True while StartMapAnimation has not been stopped (encounter pull or preview).
local mapAnimationActive = false
-- Session-only: edges the raid leader marked as active gale vents this cycle.
---@type table<integer, boolean>
local windVents = {}

---@type SszorakGroup[]
Sszorak.GROUPS = { "A", "B" }

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

local function NotifyChanged()
    if Sszorak.OnEdgeMarkersChanged then
        Sszorak:OnEdgeMarkersChanged()
    end
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
-- To test in game while in a raid (use "INSTANCE_CHAT" in instance groups); your own client
-- receives the message and adopts it if it differs from your current assignment:
-- /run C_ChatInfo.SendAddonMessage("NewEraToolsSsz", "1:2=SKULL,3=CROSS,4=DIAMOND,6=TRIANGLE,7=MOON,8=SQUARE", "RAID")
local function OnAssignmentMessage(message, channel, sender)
    if channel ~= Group.GetRaidChatType() then
        return
    end
    local assignment = DecodeAssignment(message)
    -- Senders receive their own messages too, and need no notice about an assignment they already have.
    if not assignment or IsSameAssignment(assignment, Sszorak.db.edgeMarkers) then
        return
    end
    CopyAssignment(Sszorak.db.edgeMarkers, assignment)
    NotifyChanged()
    Util.Print(string.format(L.SSZORAK_MARKERS_RECEIVED, sender))
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

---@return ArenaEdgeMarker[]  One per marked edge, in edge order.
function Sszorak:GetEdgeMarkers()
    local vertices = self:GetArenaVertices()
    local markers = {}
    for edge = 1, ARENA_SIDES do
        local marker = self.db.edgeMarkers[edge]
        if marker then
            local from, to = vertices[edge], vertices[edge % ARENA_SIDES + 1]
            table.insert(markers, {
                edge = edge,
                marker = marker,
                x = (from.x + to.x) / 2,
                y = (from.y + to.y) / 2,
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

---@return boolean  Whether the wind-vent helper is on.
function Sszorak:IsWindHelperEnabled()
    return self.db.windHelperEnabled == true
end

---Whether the helper can accept vent clicks and show its status (encounter or map preview).
---Requires the parent encounter-map feature to be on.
---@return boolean
function Sszorak:IsWindHelperInteractive()
    return self:IsMapEnabled() and self:IsWindHelperEnabled() and mapAnimationActive
end

local function NotifyWindHelperChanged()
    if Sszorak.OnWindHelperChanged then
        Sszorak:OnWindHelperChanged()
    end
end

---Clears the selected wind vents for this cycle.
---@param silent boolean|nil  When true, skip the UI notify (used when the caller notifies next).
function Sszorak:ClearWindVents(silent)
    if not next(windVents) then
        return
    end
    Util.Wipe(windVents)
    if not silent then
        NotifyWindHelperChanged()
    end
end

---@param enabled boolean
function Sszorak:SetWindHelperEnabled(enabled)
    enabled = enabled == true
    if self.db.windHelperEnabled == enabled then
        return
    end
    self.db.windHelperEnabled = enabled
    if not enabled then
        self:ClearWindVents(true)
    end
    NotifyWindHelperChanged()
end

---The edge opposite `edge` across the arena center (same side index + half the polygon).
---@param edge integer
---@return integer
local function OppositeEdge(edge)
    return (edge - 1 + ARENA_SIDES / 2) % ARENA_SIDES + 1
end

local function CountWindVents()
    local count = 0
    for _ in pairs(windVents) do
        count = count + 1
    end
    return count
end

---Squared distance from an edge midpoint to the entrance midpoint; lower edge index breaks ties.
---@param edge integer
---@return number distanceSq
---@return integer edge
local function EntranceSortKey(edge)
    local vertices = Sszorak:GetArenaVertices()
    local from, to = vertices[edge], vertices[edge % ARENA_SIDES + 1]
    local mx, my = (from.x + to.x) / 2, (from.y + to.y) / 2
    local dx, dy = mx - ENTRANCE_MID_X, my - ENTRANCE_MID_Y
    return dx * dx + dy * dy, edge
end

---@param edge integer
---@return boolean
function Sszorak:IsWindVent(edge)
    return windVents[edge] == true
end

---Selected wind-vent edges in ascending edge order.
---@return integer[]
function Sszorak:GetWindVents()
    local edges = {}
    for edge = 1, ARENA_SIDES do
        if windVents[edge] then
            table.insert(edges, edge)
        end
    end
    return edges
end

---Downwind cyst edges split into the two DoT rounds, or nil until all wind vents are picked.
---@return SszorakCystPlan|nil
function Sszorak:GetCystPlan()
    if CountWindVents() ~= WIND_VENT_COUNT then
        return nil
    end
    local downwinds = {}
    for edge in pairs(windVents) do
        table.insert(downwinds, OppositeEdge(edge))
    end
    table.sort(downwinds, function(a, b)
        local da, ea = EntranceSortKey(a)
        local db, eb = EntranceSortKey(b)
        if da ~= db then
            return da < db
        end
        return ea < eb
    end)
    local round1 = {}
    for index = 1, CYST_ROUND1_COUNT do
        round1[index] = downwinds[index]
    end
    local round2 = {}
    for index = CYST_ROUND1_COUNT + 1, #downwinds do
        table.insert(round2, downwinds[index])
    end
    return { round1 = round1, round2 = round2 }
end

---Toggles `edge` as an active gale vent. No-op when the helper isn't interactive or at the cap of 3.
---@param edge integer  Any markable edge.
---@return boolean  Whether the selection changed.
function Sszorak:ToggleWindVent(edge)
    if not self:IsWindHelperInteractive() then
        return false
    end
    assert(IsMarkableEdge(edge), "Edge can't be a wind vent: " .. tostring(edge))
    if windVents[edge] then
        windVents[edge] = nil
        NotifyWindHelperChanged()
        return true
    end
    if CountWindVents() >= WIND_VENT_COUNT then
        return false
    end
    windVents[edge] = true
    NotifyWindHelperChanged()
    return true
end

---@return boolean  Whether the map window is turned 180 degrees.
function Sszorak:IsMapRotated()
    return self.db.mapRotated == true
end

---@param rotated boolean
function Sszorak:SetMapRotated(rotated)
    self.db.mapRotated = rotated == true
end

local function ClampMapScale(scale)
    local rounded = math.floor(scale / MAP_SCALE_STEP + 0.5) * MAP_SCALE_STEP
    return math.min(math.max(rounded, MAP_SCALE_MIN), MAP_SCALE_MAX)
end

---@return number
function Sszorak:GetMapScale()
    return ClampMapScale(self.db.mapScale)
end

---@param scale number
function Sszorak:SetMapScale(scale)
    assert(type(scale) == "number", "Bad scale")
    self.db.mapScale = ClampMapScale(scale)
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

---@return boolean
function Sszorak:IsInEncounter()
    return inEncounter
end

local function NotifyPositionsChanged()
    if Sszorak.OnPositionsChanged then
        Sszorak:OnPositionsChanged()
    end
end

local function SetPositionStation(station)
    if positionStation == station then
        return
    end
    positionStation = station
    NotifyPositionsChanged()
end

local function CurrentPositionX()
    return STATION_X[positionStation]
end

---@class MapAnimationOptions
---@field startTime number|nil  Timeline clock at the beginning of the first cycle. Defaults to 0.
---@field rate number|nil  How fast timeline seconds elapse. Defaults to 1.

-- Schedules the four jumps of one cycle. `token` must still match `animToken` when each fires.
-- `cycleStartTime` is where the timeline clock begins for this cycle (0 after the first pull cycle).
local function ScheduleAnimationCycle(token, cycleStartTime)
    for index, at in ipairs(STATION_MOVE_TIMES) do
        local delay = (at - cycleStartTime) / animRate
        Timer.After(delay, function()
            if token ~= animToken then
                return
            end
            if index < #STATION_MOVE_TIMES then
                SetPositionStation(index + 1)
            else
                -- t4: back home, then the same timeline runs again from zero (no pull offset).
                -- Wind vents are per cycle; the next gale set is picked fresh.
                Sszorak:ClearWindVents()
                SetPositionStation(STATION_HOME)
                ScheduleAnimationCycle(token, 0)
            end
        end)
    end
end

---Starts (or restarts) the looping map animation from the home positions.
---@param options MapAnimationOptions|nil
function Sszorak:StartMapAnimation(options)
    options = options or {}
    animToken = animToken + 1
    local token = animToken
    animRate = options.rate or 1
    local startTime = options.startTime or 0
    mapAnimationActive = true
    -- A new pull or preview run starts a fresh vent cycle.
    self:ClearWindVents(true)
    positionStation = STATION_HOME
    NotifyPositionsChanged()
    -- Preview and pull both open wind-helper interaction on the floating map.
    NotifyWindHelperChanged()
    ScheduleAnimationCycle(token, startTime)
end

---Stops the map animation and snaps the dots back home.
function Sszorak:StopMapAnimation()
    animToken = animToken + 1
    animRate = 1
    mapAnimationActive = false
    self:ClearWindVents(true)
    NotifyWindHelperChanged()
    SetPositionStation(STATION_HOME)
end

local function SetInEncounter(value)
    if inEncounter == value then
        return
    end
    inEncounter = value
    if value then
        -- Always restart from pull, even if preview was already animating.
        Sszorak:StartMapAnimation({ startTime = ANIM_ENCOUNTER_START_TIME })
    else
        Sszorak:StopMapAnimation()
    end
    if Sszorak.OnEncounterChanged then
        Sszorak:OnEncounterChanged()
    end
end

---Starts watching for this boss fight. Called from OnEnable.
function Sszorak:ListenForEncounter()
    Encounter.OnStart(function(encounterID)
        if encounterID == ENCOUNTER_ID then
            SetInEncounter(true)
        end
    end)
    Encounter.OnEnd(function(encounterID)
        if encounterID == ENCOUNTER_ID then
            SetInEncounter(false)
        end
    end)
end

---@return string|nil  Why the player can't send the assignment to the raid right now, or nil if they can.
function Sszorak:GetBroadcastBlockedReason()
    if not Group.GetRaidChatType() then
        return L.SSZORAK_BROADCAST_NOT_IN_RAID
    end
    if not Group.IsPlayerRaidLeaderOrAssistant() then
        return L.SSZORAK_BROADCAST_NOT_LEADER
    end
end

---Sends the player's marker assignment to everyone in the raid running this addon, who adopt it.
---Only works for the raid leader and assistants; receivers ignore anyone else.
function Sszorak:BroadcastEdgeMarkers()
    local reason = self:GetBroadcastBlockedReason()
    if reason then
        Util.Print(reason)
        return
    end
    local sent = AddonMessage.Send(MESSAGE_PREFIX, EncodeAssignment(self.db.edgeMarkers), Group.GetRaidChatType())
    Util.Print(sent and L.SSZORAK_BROADCAST_SENT or L.SSZORAK_BROADCAST_FAILED)
end

---Starts adopting assignments that raid leaders and assistants send. Called from OnEnable.
function Sszorak:ListenForBroadcasts()
    AddonMessage.Listen(MESSAGE_PREFIX, OnAssignmentMessage)
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
    self.db.mapScale = ClampMapScale(self.db.mapScale)
end
