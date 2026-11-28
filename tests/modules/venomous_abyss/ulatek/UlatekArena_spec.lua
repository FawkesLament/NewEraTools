local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Ulatek arena", function()
    local Ulatek

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Ulatek = ns.Modules.Get("Ulatek")
    end)

    local function EdgeEnds(vertices, edge)
        return vertices[edge], vertices[edge % #vertices + 1]
    end

    describe("GetArenaVertices", function()
        it("returns one corner per side", function()
            assert.equals(Ulatek.ARENA_SIDES, #Ulatek:GetArenaVertices())
        end)

        it("forms a regular polygon with every edge 1 from the center", function()
            local vertices = Ulatek:GetArenaVertices()
            local radius = 1 / math.cos(math.pi / Ulatek.ARENA_SIDES)
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
            local vertices = Ulatek:GetArenaVertices()
            for edge = 1, #vertices do
                local from, to = EdgeEnds(vertices, edge)
                assert.is_true(from.x * to.y - from.y * to.x > 0)
            end
        end)

        it("puts the entrance on the horizontal bottom edge", function()
            local from, to = EdgeEnds(Ulatek:GetArenaVertices(), Ulatek.ENTRANCE_EDGE)
            AssertNear(-1, from.y)
            AssertNear(-1, to.y)
            assert.is_true(from.x < 0 and to.x > 0)
        end)

        it("has no exit edge", function()
            assert.is_nil(Ulatek.EXIT_EDGE)
        end)
    end)

    describe("GetCornerPoint", function()
        it("matches GetArenaVertices", function()
            local vertices = Ulatek:GetArenaVertices()
            for corner = 1, Ulatek.ARENA_SIDES do
                local point = Ulatek:GetCornerPoint(corner)
                AssertNear(vertices[corner].x, point.x)
                AssertNear(vertices[corner].y, point.y)
            end
        end)

        it("rejects out-of-range corners", function()
            assert.is_false(pcall(Ulatek.GetCornerPoint, Ulatek, 0))
            assert.is_false(pcall(Ulatek.GetCornerPoint, Ulatek, 9))
        end)
    end)

    describe("GetEdgeMidpoint", function()
        it("returns the entrance wall midpoint at the bottom", function()
            local mid = Ulatek:GetEdgeMidpoint(Ulatek.ENTRANCE_EDGE)
            AssertNear(0, mid.x)
            AssertNear(-1, mid.y)
        end)
    end)
end)
