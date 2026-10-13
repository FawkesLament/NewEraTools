local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Sszorak", function()
    local ns, Sszorak

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Sszorak = ns.Modules.Get("Sszorak")
    end)

    local function EdgeEnds(vertices, edge)
        return vertices[edge], vertices[edge % #vertices + 1]
    end

    it("is registered with saved settings", function()
        assert.is_false(Sszorak == nil)
        assert.equals("table", type(Sszorak.db))
    end)

    describe("GetArenaVertices", function()
        it("returns one corner per side", function()
            assert.equals(Sszorak.ARENA_SIDES, #Sszorak:GetArenaVertices())
        end)

        it("forms a regular polygon with every edge 1 from the center", function()
            local vertices = Sszorak:GetArenaVertices()
            local radius = 1 / math.cos(math.pi / Sszorak.ARENA_SIDES)
            local firstFrom, firstTo = EdgeEnds(vertices, 1)
            local sideLength = math.sqrt((firstTo.x - firstFrom.x) ^ 2 + (firstTo.y - firstFrom.y) ^ 2)
            for edge = 1, #vertices do
                local from, to = EdgeEnds(vertices, edge)
                AssertNear(radius, math.sqrt(from.x ^ 2 + from.y ^ 2))
                AssertNear(sideLength, math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2))
                AssertNear(1, math.sqrt(((from.x + to.x) / 2) ^ 2 + ((from.y + to.y) / 2) ^ 2))
            end
        end)

        it("lists corners counterclockwise", function()
            local vertices = Sszorak:GetArenaVertices()
            for edge = 1, #vertices do
                local from, to = EdgeEnds(vertices, edge)
                assert.is_true(from.x * to.y - from.y * to.x > 0)
            end
        end)

        it("puts the entrance on the vertical right edge", function()
            local from, to = EdgeEnds(Sszorak:GetArenaVertices(), Sszorak.ENTRANCE_EDGE)
            AssertNear(1, from.x)
            AssertNear(1, to.x)
            assert.is_true(from.y < 0 and to.y > 0)
        end)

        it("puts the exit on the vertical left edge", function()
            local from, to = EdgeEnds(Sszorak:GetArenaVertices(), Sszorak.EXIT_EDGE)
            AssertNear(-1, from.x)
            AssertNear(-1, to.x)
            assert.is_true(from.y > 0 and to.y < 0)
        end)
    end)

    describe("GetEdgeMarkers", function()
        local WORLD_MARKERS = {
            STAR = true,
            CIRCLE = true,
            DIAMOND = true,
            TRIANGLE = true,
            MOON = true,
            SQUARE = true,
            CROSS = true,
            SKULL = true,
        }

        it("marks every edge except the entrance and exit, once each", function()
            local marked = {}
            for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
                assert.is_true(marked[edgeMarker.edge] == nil)
                marked[edgeMarker.edge] = true
            end
            for edge = 1, Sszorak.ARENA_SIDES do
                local isGate = edge == Sszorak.ENTRANCE_EDGE or edge == Sszorak.EXIT_EDGE
                assert.equals(not isGate, marked[edge] == true)
            end
        end)

        it("uses a different known world marker on each edge", function()
            local used = {}
            for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
                assert.is_true(WORLD_MARKERS[edgeMarker.marker])
                assert.is_true(used[edgeMarker.marker] == nil)
                used[edgeMarker.marker] = true
            end
        end)

        it("places each marker at the midpoint of its edge", function()
            local vertices = Sszorak:GetArenaVertices()
            for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
                local from, to = EdgeEnds(vertices, edgeMarker.edge)
                AssertNear((from.x + to.x) / 2, edgeMarker.x)
                AssertNear((from.y + to.y) / 2, edgeMarker.y)
            end
        end)
    end)

    describe("marker assignment", function()
        local function StartWithSaved(edgeMarkers)
            ns = Loader.Load()
            local saved = ns.Database.Load({ modules = { Sszorak = { edgeMarkers = edgeMarkers } } })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
        end

        local function CountChanges()
            local changes = { count = 0 }
            Sszorak.OnEdgeMarkersChanged = function()
                changes.count = changes.count + 1
            end
            return changes
        end

        it("starts with the default assignment", function()
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
            assert.equals("STAR", Sszorak:GetEdgeMarker(2))
            assert.is_true(Sszorak:GetEdgeMarker(Sszorak.ENTRANCE_EDGE) == nil)
        end)

        it("puts an unused marker on an edge", function()
            local changes = CountChanges()
            Sszorak:SetEdgeMarker(2, "SKULL")
            assert.equals("SKULL", Sszorak:GetEdgeMarker(2))
            assert.is_true(Sszorak:FindEdgeWithMarker("STAR") == nil)
            assert.is_false(Sszorak:IsDefaultEdgeMarkers())
            assert.equals(1, changes.count)
        end)

        it("swaps with the edge that already has the marker", function()
            Sszorak:SetEdgeMarker(2, "MOON")
            assert.equals("MOON", Sszorak:GetEdgeMarker(2))
            assert.equals("STAR", Sszorak:GetEdgeMarker(7))
        end)

        it("shows the new assignment in GetEdgeMarkers", function()
            Sszorak:SetEdgeMarker(3, "CROSS")
            for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
                assert.equals(Sszorak:GetEdgeMarker(edgeMarker.edge), edgeMarker.marker)
            end
        end)

        it("does nothing when the edge already has the marker", function()
            local changes = CountChanges()
            Sszorak:SetEdgeMarker(2, "STAR")
            assert.equals(0, changes.count)
        end)

        it("rejects the entrance, the exit and unknown markers", function()
            assert.is_false(pcall(Sszorak.SetEdgeMarker, Sszorak, Sszorak.ENTRANCE_EDGE, "SKULL"))
            assert.is_false(pcall(Sszorak.SetEdgeMarker, Sszorak, Sszorak.EXIT_EDGE, "SKULL"))
            assert.is_false(pcall(Sszorak.SetEdgeMarker, Sszorak, 2, "BANANA"))
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)

        it("resets to the default assignment", function()
            Sszorak:SetEdgeMarker(2, "SKULL")
            Sszorak:SetEdgeMarker(3, "CROSS")
            local changes = CountChanges()
            Sszorak:ResetEdgeMarkers()
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
            assert.equals(1, changes.count)
        end)

        it("keeps a valid saved assignment", function()
            StartWithSaved({
                [2] = "SKULL",
                [3] = "CROSS",
                [4] = "DIAMOND",
                [6] = "TRIANGLE",
                [7] = "MOON",
                [8] = "SQUARE",
            })
            assert.equals("SKULL", Sszorak:GetEdgeMarker(2))
            assert.equals("CROSS", Sszorak:GetEdgeMarker(3))
        end)

        it("falls back to the default when the saved assignment repeats a marker", function()
            -- Edge 3 is missing, so merging defaults gives it CIRCLE, which edge 2 already has.
            StartWithSaved({ [2] = "CIRCLE", [4] = "DIAMOND", [6] = "TRIANGLE", [7] = "MOON", [8] = "SQUARE" })
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)

        it("falls back to the default when the saved assignment has unknown markers or edges", function()
            StartWithSaved({ [2] = "BANANA" })
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
            StartWithSaved({ [Sszorak.ENTRANCE_EDGE] = "SKULL" })
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)
    end)

    describe("broadcasting", function()
        local Group, AddonMessage, printed

        local LEADER = "Leader-TestRealm"

        before_each(function()
            Group = ns.Api.Group
            AddonMessage = ns.Api.AddonMessage
            printed = {}
            ns.Util.Print = function(message)
                table.insert(printed, message)
            end
            Group.raidChatType = "RAID"
            Group.isLeaderOrAssistant = true
            Sszorak:ListenForBroadcasts()
        end)

        -- What the raid leader's copy sends for the current assignment.
        local function CaptureBroadcast()
            Sszorak:BroadcastEdgeMarkers()
            local sent = AddonMessage.sent[#AddonMessage.sent]
            return sent.prefix, sent.message
        end

        local function CaptureCustomBroadcast()
            Sszorak:SetEdgeMarker(2, "SKULL")
            Sszorak:SetEdgeMarker(3, "CROSS")
            local prefix, message = CaptureBroadcast()
            Sszorak:ResetEdgeMarkers()
            printed = {}
            return prefix, message
        end

        it("sends the assignment to the raid", function()
            Group.raidChatType = "INSTANCE_CHAT"
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(1, #AddonMessage.sent)
            assert.equals("INSTANCE_CHAT", AddonMessage.sent[1].chatType)
            assert.equals(ns.L.SSZORAK_BROADCAST_SENT, printed[1])
        end)

        it("is blocked outside a raid", function()
            Group.raidChatType = nil
            assert.equals(ns.L.SSZORAK_BROADCAST_NOT_IN_RAID, Sszorak:GetBroadcastBlockedReason())
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(0, #AddonMessage.sent)
        end)

        it("is blocked for players who aren't leader or assistant", function()
            Group.isLeaderOrAssistant = false
            assert.equals(ns.L.SSZORAK_BROADCAST_NOT_LEADER, Sszorak:GetBroadcastBlockedReason())
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(0, #AddonMessage.sent)
        end)

        it("says so when the game refuses the message", function()
            AddonMessage.accepts = false
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(ns.L.SSZORAK_BROADCAST_FAILED, printed[1])
        end)

        it("adopts an assignment from the raid leader", function()
            local prefix, message = CaptureCustomBroadcast()
            local changes = 0
            Sszorak.OnEdgeMarkersChanged = function()
                changes = changes + 1
            end
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.equals("SKULL", Sszorak:GetEdgeMarker(2))
            assert.equals("CROSS", Sszorak:GetEdgeMarker(3))
            assert.equals(1, changes)
            assert.equals(string.format(ns.L.SSZORAK_MARKERS_RECEIVED, LEADER), printed[1])
        end)

        it("stays quiet when the assignment is already in place", function()
            local prefix, message = CaptureBroadcast()
            printed = {}
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.equals(0, #printed)
        end)

        it("ignores messages from outside the current raid's channel", function()
            local prefix, message = CaptureCustomBroadcast()
            AddonMessage.Deliver(prefix, message, "PARTY", LEADER)
            Group.raidChatType = nil
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)

        it("ignores other format versions and invalid assignments", function()
            local prefix, message = CaptureCustomBroadcast()
            AddonMessage.Deliver(prefix, (message:gsub("^%d+:", "99:")), "RAID", LEADER)
            AddonMessage.Deliver(prefix, "1:2=STAR,3=STAR", "RAID", LEADER)
            AddonMessage.Deliver(prefix, "garbage", "RAID", LEADER)
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)
    end)

    describe("map enabled", function()
        it("is on by default", function()
            assert.is_true(Sszorak:IsMapEnabled())
        end)

        it("is saved", function()
            Sszorak:SetMapEnabled(false)
            assert.is_false(Sszorak:IsMapEnabled())
            assert.is_false(Sszorak.db.mapEnabled)
            Sszorak:SetMapEnabled(true)
            assert.is_true(Sszorak:IsMapEnabled())
        end)

        it("keeps a saved preference", function()
            ns = Loader.Load()
            local saved = ns.Database.Load({ modules = { Sszorak = { mapEnabled = false } } })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
            assert.is_false(Sszorak:IsMapEnabled())
        end)
    end)

    describe("map rotation", function()
        it("is off by default", function()
            assert.is_false(Sszorak:IsMapRotated())
        end)

        it("is saved", function()
            Sszorak:SetMapRotated(true)
            assert.is_true(Sszorak:IsMapRotated())
            assert.is_true(Sszorak.db.mapRotated)
            Sszorak:SetMapRotated(false)
            assert.is_false(Sszorak:IsMapRotated())
        end)
    end)

    describe("map scale", function()
        it("is 100% by default", function()
            AssertNear(1, Sszorak:GetMapScale())
        end)

        it("is saved and snapped to the step", function()
            Sszorak:SetMapScale(1.22)
            AssertNear(1.2, Sszorak:GetMapScale())
            AssertNear(1.2, Sszorak.db.mapScale)
        end)

        it("clamps to the allowed range", function()
            Sszorak:SetMapScale(0.1)
            AssertNear(Sszorak.MAP_SCALE_MIN, Sszorak:GetMapScale())
            Sszorak:SetMapScale(3)
            AssertNear(Sszorak.MAP_SCALE_MAX, Sszorak:GetMapScale())
        end)

        it("rejects non-numbers", function()
            assert.is_false(pcall(Sszorak.SetMapScale, Sszorak, "big"))
            AssertNear(1, Sszorak:GetMapScale())
        end)
    end)

    describe("encounter detection", function()
        local Encounter
        local changes

        before_each(function()
            Encounter = ns.Api.Encounter
            changes = 0
            Sszorak.OnEncounterChanged = function()
                changes = changes + 1
            end
            Sszorak:ListenForEncounter()
        end)

        it("starts outside the encounter", function()
            assert.is_false(Sszorak:IsInEncounter())
        end)

        it("enters and leaves this boss fight", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(Sszorak:IsInEncounter())
            assert.equals(1, changes)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(2, changes)
        end)

        it("ignores other encounters", function()
            Encounter.FireStart(1, "Other", 16, 20)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(0, changes)
            Encounter.FireEnd(1, "Other", 16, 20, 0)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(0, changes)
        end)

        it("does not notify twice for the same state", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.equals(1, changes)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 0)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 0)
            assert.equals(2, changes)
        end)

        it("does not change the map enabled preference", function()
            Sszorak:SetMapEnabled(false)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_false(Sszorak:IsMapEnabled())
        end)
    end)

    describe("map animation", function()
        local Timer
        local moves

        local function BossX()
            return Sszorak:GetBossPosition().x
        end

        local function AdvanceTimeline(fromTime, toTime)
            Timer.Advance(toTime - fromTime)
        end

        local function ExpectedX(station, homeX)
            if station == 1 then
                return homeX
            end
            if station == 2 then
                return 0
            end
            return -homeX
        end

        before_each(function()
            Timer = ns.Api.Timer
            moves = 0
            Sszorak.OnPositionsChanged = function()
                moves = moves + 1
            end
        end)

        it("starts on the entrance side", function()
            assert.is_true(BossX() > 0.5)
            AssertNear(BossX(), Sszorak:GetGroupPosition("A").x)
            AssertNear(BossX(), Sszorak:GetGroupPosition("B").x)
        end)

        it("follows the fixed position timeline and freezes on the last station", function()
            local homeX = BossX()
            Sszorak:StartMapAnimation()
            assert.equals(1, moves)
            AssertNear(homeX, BossX())

            local elapsed = 0
            for _, entry in ipairs(Sszorak.POSITION_TIMELINE) do
                AdvanceTimeline(elapsed, entry.time)
                elapsed = entry.time
                AssertNear(ExpectedX(entry.station, homeX), BossX())
            end

            local frozenX = BossX()
            AdvanceTimeline(elapsed, elapsed + 600)
            AssertNear(frozenX, BossX())
            assert.is_true(frozenX > 0.5)
        end)

        it("keeps group Y offsets while sharing the animated X", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.POSITION_TIMELINE[1].time)
            local a = Sszorak:GetGroupPosition("A")
            local b = Sszorak:GetGroupPosition("B")
            AssertNear(0, a.x)
            AssertNear(0, b.x)
            assert.is_true(a.y < 0 and b.y > 0)
        end)

        it("resets when started again, ignoring the previous timer", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.POSITION_TIMELINE[1].time)
            AssertNear(0, BossX())
            Sszorak:StartMapAnimation()
            local homeX = BossX()
            assert.is_true(homeX > 0.5)
            -- The old second jump from the first run must not fire.
            local firstJump = Sszorak.POSITION_TIMELINE[1].time
            local secondJump = Sszorak.POSITION_TIMELINE[2].time
            Timer.Advance(secondJump - firstJump)
            AssertNear(homeX, BossX())
            Timer.Advance(firstJump - (secondJump - firstJump))
            AssertNear(0, BossX())
        end)

        it("stops and snaps home", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.POSITION_TIMELINE[2].time)
            Sszorak:StopMapAnimation()
            assert.is_true(BossX() > 0.5)
            local x = BossX()
            Timer.Advance(Sszorak.POSITION_TIMELINE[#Sszorak.POSITION_TIMELINE].time)
            AssertNear(x, BossX())
        end)

        it("starts on encounter pull and stops when the fight ends", function()
            local Encounter = ns.Api.Encounter
            Sszorak:ListenForEncounter()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.POSITION_TIMELINE[1].time)
            AssertNear(0, BossX())

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(Sszorak.POSITION_TIMELINE[1].time - 0.001)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(0.001)
            AssertNear(0, BossX())

            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_true(BossX() > 0.5)
            local x = BossX()
            Timer.Advance(Sszorak.POSITION_TIMELINE[1].time)
            AssertNear(x, BossX())
        end)

        it("runs preview on a faster timeline", function()
            local firstJump = Sszorak.POSITION_TIMELINE[1].time
            Sszorak:StartMapAnimation({ rate = Sszorak.ANIM_PREVIEW_RATE })
            Timer.Advance(firstJump / Sszorak.ANIM_PREVIEW_RATE - 0.001)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(0.001)
            AssertNear(0, BossX())
        end)
    end)

    describe("opposite edges", function()
        it("maps each edge to its opposite across the arena", function()
            assert.equals(6, Sszorak:GetOppositeEdge(2))
            assert.equals(2, Sszorak:GetOppositeEdge(6))
            assert.equals(7, Sszorak:GetOppositeEdge(3))
            assert.equals(8, Sszorak:GetOppositeEdge(4))
        end)
    end)

    describe("map window position", function()
        it("starts at the screen center", function()
            assert.same(
                { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
                Sszorak:GetMapPosition()
            )
        end)

        it("is saved", function()
            Sszorak:SetMapPosition({ point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 })
            assert.same(
                { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 },
                Sszorak.db.mapPosition
            )
        end)

        it("rejects incomplete positions", function()
            assert.is_false(pcall(Sszorak.SetMapPosition, Sszorak, { point = "TOPLEFT", x = 1, y = 2 }))
            assert.is_false(pcall(Sszorak.SetMapPosition, Sszorak, { point = "TOP", relativePoint = "TOP" }))
            assert.equals("CENTER", Sszorak:GetMapPosition().point)
        end)
    end)

    describe("positions", function()
        it("puts the boss on the entrance-exit centerline, nearer the entrance", function()
            local boss = Sszorak:GetBossPosition()
            AssertNear(0, boss.y)
            assert.is_true(boss.x > 0.5 and boss.x < 1)
        end)

        it("puts group A directly below the boss and group B directly above", function()
            local boss = Sszorak:GetBossPosition()
            local a = Sszorak:GetGroupPosition("A")
            local b = Sszorak:GetGroupPosition("B")
            AssertNear(boss.x, a.x)
            AssertNear(boss.x, b.x)
            assert.is_true(a.y < boss.y and b.y > boss.y)
            AssertNear(boss.y - a.y, b.y - boss.y)
        end)

        it("keeps every group inside the arena", function()
            for _, group in ipairs(Sszorak.GROUPS) do
                local point = Sszorak:GetGroupPosition(group)
                assert.is_true(math.sqrt(point.x ^ 2 + point.y ^ 2) < 1)
            end
        end)

        it("rejects unknown groups", function()
            local ok = pcall(Sszorak.GetGroupPosition, Sszorak, "C")
            assert.is_false(ok)
        end)

        it("puts the player in group A, or in group B when the map is rotated", function()
            assert.equals("A", Sszorak:GetPlayerGroup())
            Sszorak:SetMapRotated(true)
            assert.equals("B", Sszorak:GetPlayerGroup())
        end)
    end)
end)
