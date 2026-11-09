local Loader = require("helpers.loader")

describe("GearAlert", function()
    local ns, GearAlert

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        GearAlert = ns.Modules.Get("GearAlert")
    end)

    it("is registered with saved settings", function()
        assert.is_false(GearAlert == nil)
        assert.equals("table", type(GearAlert.db))
        assert.is_true(GearAlert:IsFourPieceCheckEnabled())
    end)

    describe("four-piece check", function()
        it("can be turned off", function()
            GearAlert:SetFourPieceCheckEnabled(false)
            assert.is_false(GearAlert:IsFourPieceCheckEnabled())
        end)
    end)

    describe("position", function()
        it("defaults above the screen center", function()
            local position = GearAlert:GetPosition()
            assert.equals("CENTER", position.point)
            assert.equals("CENTER", position.relativePoint)
            assert.equals(0, position.x)
            assert.equals(200, position.y)
        end)

        it("stores a valid anchor", function()
            GearAlert:SetPosition({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -20 })
            local position = GearAlert:GetPosition()
            assert.equals("TOPLEFT", position.point)
            assert.equals("TOPLEFT", position.relativePoint)
            assert.equals(10, position.x)
            assert.equals(-20, position.y)
        end)

        it("rejects a bad anchor", function()
            assert.is_false(pcall(GearAlert.SetPosition, GearAlert, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
            }))
        end)

        it("does not let Reset Position mutate saved data", function()
            local defaults = GearAlert.DefaultPosition()
            defaults.x = 99
            assert.equals(0, GearAlert:GetPosition().x)
            assert.equals(0, GearAlert.DefaultPosition().x)
        end)
    end)
end)
