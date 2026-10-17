local Harness = require("helpers.sszorak")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Sszorak", function()
    local Sszorak

    before_each(function()
        local _
        _, Sszorak = Harness.Start()
    end)

    local function EdgeEnds(vertices, edge)
        return vertices[edge], vertices[edge % #vertices + 1]
    end

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

    describe("GetEdgeMidpoint", function()
        it("matches GetEdgeMarkers for markable edges", function()
            for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
                local mid = Sszorak:GetEdgeMidpoint(edgeMarker.edge)
                AssertNear(edgeMarker.x, mid.x)
                AssertNear(edgeMarker.y, mid.y)
            end
        end)

        it("returns the exit wall midpoint", function()
            local mid = Sszorak:GetEdgeMidpoint(Sszorak.EXIT_EDGE)
            AssertNear(-1, mid.x)
            AssertNear(0, mid.y)
        end)

        it("rejects out-of-range edges", function()
            assert.is_false(pcall(Sszorak.GetEdgeMidpoint, Sszorak, 0))
            assert.is_false(pcall(Sszorak.GetEdgeMidpoint, Sszorak, Sszorak.ARENA_SIDES + 1))
        end)
    end)

    describe("GetEdgePathPoint", function()
        it("lies on the edge bisector at PATH_ARROW_RADIUS from the center", function()
            for edge = 1, Sszorak.ARENA_SIDES do
                local mid = Sszorak:GetEdgeMidpoint(edge)
                local tip = Sszorak:GetEdgePathPoint(edge)
                AssertNear(mid.x * Sszorak.PATH_ARROW_RADIUS, tip.x)
                AssertNear(mid.y * Sszorak.PATH_ARROW_RADIUS, tip.y)
                AssertNear(Sszorak.PATH_ARROW_RADIUS, math.sqrt(tip.x * tip.x + tip.y * tip.y))
            end
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

    describe("edge relationships", function()
        it("places group B on the entrance side and group A on the exit side", function()
            assert.equals("B", Sszorak:GetEdgeGroup(2))
            assert.equals("B", Sszorak:GetEdgeGroup(4))
            assert.equals("A", Sszorak:GetEdgeGroup(6))
            assert.equals("A", Sszorak:GetEdgeGroup(8))
            assert.equals(nil, Sszorak:GetEdgeGroup(Sszorak.ENTRANCE_EDGE))
            assert.equals(nil, Sszorak:GetEdgeGroup(Sszorak.EXIT_EDGE))
        end)

        it("measures depth from the entrance gate", function()
            assert.equals("near", Sszorak:GetEdgeEntranceDepth(2))
            assert.equals("mid", Sszorak:GetEdgeEntranceDepth(3))
            assert.equals("far", Sszorak:GetEdgeEntranceDepth(4))
            assert.equals("far", Sszorak:GetEdgeEntranceDepth(6))
            assert.equals("mid", Sszorak:GetEdgeEntranceDepth(7))
            assert.equals("near", Sszorak:GetEdgeEntranceDepth(8))
            assert.equals(nil, Sszorak:GetEdgeEntranceDepth(Sszorak.ENTRANCE_EDGE))
        end)
    end)
end)
