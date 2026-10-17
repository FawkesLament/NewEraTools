local Harness = require("helpers.sszorak")
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
        ns, Sszorak = Harness.Start()
    end)

    local function EdgeEnds(vertices, edge)
        return vertices[edge], vertices[edge % #vertices + 1]
    end

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
end)
