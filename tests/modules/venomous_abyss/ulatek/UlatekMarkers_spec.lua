local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Ulatek corner markers", function()
    local ns, Ulatek

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Ulatek = ns.Modules.Get("Ulatek")
    end)

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

    describe("GetCornerMarkers", function()
        it("marks every corner once", function()
            local marked = {}
            for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
                assert.is_true(marked[cornerMarker.corner] == nil)
                marked[cornerMarker.corner] = true
            end
            for corner = 1, Ulatek.ARENA_SIDES do
                assert.is_true(marked[corner] == true)
            end
        end)

        it("uses a different known world marker on each corner", function()
            local used = {}
            for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
                assert.is_true(WORLD_MARKERS[cornerMarker.marker])
                assert.is_true(used[cornerMarker.marker] == nil)
                used[cornerMarker.marker] = true
            end
        end)

        it("places each marker at its vertex, not an edge midpoint", function()
            local vertices = Ulatek:GetArenaVertices()
            for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
                local vertex = vertices[cornerMarker.corner]
                AssertNear(vertex.x, cornerMarker.x)
                AssertNear(vertex.y, cornerMarker.y)
                local mid = Ulatek:GetEdgeMidpoint(cornerMarker.corner)
                assert.is_true(math.abs(mid.x - cornerMarker.x) > EPSILON or math.abs(mid.y - cornerMarker.y) > EPSILON)
            end
        end)
    end)

    describe("marker assignment", function()
        local function StartWithSaved(cornerMarkers)
            ns = Loader.Load()
            local saved = ns.Database.Load({ modules = { Ulatek = { cornerMarkers = cornerMarkers } } })
            ns.Modules.Start(saved)
            Ulatek = ns.Modules.Get("Ulatek")
        end

        local function CountChanges()
            local changes = { count = 0 }
            Ulatek.OnCornerMarkersChanged = function()
                changes.count = changes.count + 1
            end
            return changes
        end

        it("starts with the default assignment", function()
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
            assert.equals("STAR", Ulatek:GetCornerMarker(1))
            assert.equals("SKULL", Ulatek:GetCornerMarker(8))
        end)

        it("writes the assignment into saved module settings", function()
            Ulatek:SetCornerMarker(1, "MOON")
            assert.equals("MOON", Ulatek.db.cornerMarkers[1])
            assert.equals("STAR", Ulatek.db.cornerMarkers[5])
        end)

        it("reloads the assignment from saved settings", function()
            Ulatek:SetCornerMarker(1, "MOON")
            local snapshot = ns.Util.DeepCopy(Ulatek.db)
            StartWithSaved(snapshot.cornerMarkers)
            assert.equals("MOON", Ulatek:GetCornerMarker(1))
            assert.equals("STAR", Ulatek:GetCornerMarker(5))
            assert.is_false(Ulatek:IsDefaultCornerMarkers())
        end)

        it("swaps with the corner that already has the marker", function()
            local changes = CountChanges()
            Ulatek:SetCornerMarker(1, "MOON")
            assert.equals("MOON", Ulatek:GetCornerMarker(1))
            assert.equals("STAR", Ulatek:GetCornerMarker(5))
            assert.is_false(Ulatek:IsDefaultCornerMarkers())
            assert.equals(1, changes.count)
        end)

        it("shows the new assignment in GetCornerMarkers", function()
            Ulatek:SetCornerMarker(3, "CROSS")
            for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
                assert.equals(Ulatek:GetCornerMarker(cornerMarker.corner), cornerMarker.marker)
            end
        end)

        it("does nothing when the corner already has the marker", function()
            local changes = CountChanges()
            Ulatek:SetCornerMarker(1, "STAR")
            assert.equals(0, changes.count)
        end)

        it("rejects invalid corners and unknown markers", function()
            assert.is_false(pcall(Ulatek.SetCornerMarker, Ulatek, 0, "SKULL"))
            assert.is_false(pcall(Ulatek.SetCornerMarker, Ulatek, 9, "SKULL"))
            assert.is_false(pcall(Ulatek.SetCornerMarker, Ulatek, 1, "BANANA"))
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
        end)

        it("resets to the default assignment", function()
            Ulatek:SetCornerMarker(1, "SKULL")
            Ulatek:SetCornerMarker(3, "CROSS")
            local changes = CountChanges()
            Ulatek:ResetCornerMarkers()
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
            assert.equals(1, changes.count)
        end)

        it("keeps a valid saved assignment", function()
            StartWithSaved({
                [1] = "SKULL",
                [2] = "CROSS",
                [3] = "DIAMOND",
                [4] = "TRIANGLE",
                [5] = "MOON",
                [6] = "SQUARE",
                [7] = "STAR",
                [8] = "CIRCLE",
            })
            assert.equals("SKULL", Ulatek:GetCornerMarker(1))
            assert.equals("CROSS", Ulatek:GetCornerMarker(2))
            assert.is_false(Ulatek:IsDefaultCornerMarkers())
        end)

        it("falls back to the default when the saved assignment repeats a marker", function()
            StartWithSaved({
                [1] = "CIRCLE",
                [2] = "CIRCLE",
                [3] = "DIAMOND",
                [4] = "TRIANGLE",
                [5] = "MOON",
                [6] = "SQUARE",
                [7] = "CROSS",
                [8] = "SKULL",
            })
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
        end)

        it("keeps a valid assignment stored with string keys", function()
            StartWithSaved({
                ["1"] = "SKULL",
                ["2"] = "CROSS",
                ["3"] = "DIAMOND",
                ["4"] = "TRIANGLE",
                ["5"] = "MOON",
                ["6"] = "SQUARE",
                ["7"] = "STAR",
                ["8"] = "CIRCLE",
            })
            assert.equals("SKULL", Ulatek:GetCornerMarker(1))
            assert.equals("CROSS", Ulatek:GetCornerMarker(2))
            assert.equals("SKULL", Ulatek.db.cornerMarkers[1])
            assert.is_nil(Ulatek.db.cornerMarkers["1"])
        end)

        it("falls back to the default when the saved assignment has unknown markers or extra corners", function()
            StartWithSaved({ [1] = "BANANA" })
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
            StartWithSaved({
                [1] = "STAR",
                [2] = "CIRCLE",
                [3] = "DIAMOND",
                [4] = "TRIANGLE",
                [5] = "MOON",
                [6] = "SQUARE",
                [7] = "CROSS",
                [8] = "SKULL",
                [9] = "STAR",
            })
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
        end)
    end)
end)
