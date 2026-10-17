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

    describe("map window position", function()
        it("starts at the screen center", function()
            assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, Sszorak:GetMapPosition())
        end)

        it("is saved", function()
            Sszorak:SetMapPosition({ point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 })
            assert.same({ point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 }, Sszorak.db.mapPosition)
        end)

        it("rejects incomplete positions", function()
            assert.is_false(pcall(Sszorak.SetMapPosition, Sszorak, { point = "TOPLEFT", x = 1, y = 2 }))
            assert.is_false(pcall(Sszorak.SetMapPosition, Sszorak, { point = "TOP", relativePoint = "TOP" }))
            assert.equals("CENTER", Sszorak:GetMapPosition().point)
        end)
    end)

    describe("callout position", function()
        it("saves and restores callout position", function()
            Sszorak:SetCalloutPosition({ point = "TOP", relativePoint = "CENTER", x = 12, y = -40 })
            assert.same({ point = "TOP", relativePoint = "CENTER", x = 12, y = -40 }, Sszorak:GetCalloutPosition())
        end)
    end)

    describe("positions", function()
        it("puts the player in group A, or in group B when the map is rotated", function()
            assert.equals("A", Sszorak:GetPlayerGroup())
            Sszorak:SetMapRotated(true)
            assert.equals("B", Sszorak:GetPlayerGroup())
        end)
    end)
end)
