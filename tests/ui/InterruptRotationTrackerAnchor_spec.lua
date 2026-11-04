local Loader = require("helpers.loader")

describe("InterruptRotationTrackerAnchor", function()
    local ns, TwinFangs, CoiledAltar

    local function Start(saved)
        ns = Loader.Load()
        local loaded = ns.Database.Load(saved)
        ns.Modules.Start(loaded)
        TwinFangs = ns.Modules.Get("TwinFangs")
        CoiledAltar = ns.Modules.Get("CoiledAltar")
        return loaded
    end

    before_each(function()
        Start(nil)
    end)

    it("starts Twin Fangs and The Coiled Altar on one factory anchor", function()
        local position = TwinFangs:GetInterruptRotationTrackerPosition()
        assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 80 }, position)
        assert.equals(position, CoiledAltar:GetInterruptRotationTrackerPosition())
        assert.equals(position, ns.InterruptRotationTrackerAnchor.GetPosition())
        assert.is_nil(TwinFangs.db.interruptStatusHudPosition)
        assert.is_nil(CoiledAltar.db.interruptStatusHudPosition)
    end)

    it("writes one saved anchor from either boss", function()
        local saved = Start(nil)
        local moved = { point = "TOP", relativePoint = "CENTER", x = 12, y = -40 }
        CoiledAltar:SetInterruptRotationTrackerPosition(moved)

        assert.same(moved, TwinFangs:GetInterruptRotationTrackerPosition())
        assert.equals(TwinFangs:GetInterruptRotationTrackerPosition(), CoiledAltar:GetInterruptRotationTrackerPosition())
        assert.equals(saved.interruptRotationTrackerPosition, TwinFangs:GetInterruptRotationTrackerPosition())

        Start(saved)
        assert.same(moved, CoiledAltar:GetInterruptRotationTrackerPosition())
        assert.equals(saved.interruptRotationTrackerPosition, TwinFangs:GetInterruptRotationTrackerPosition())
    end)

    it("rejects an incomplete anchor and leaves the shared one in place", function()
        TwinFangs:SetInterruptRotationTrackerPosition({ point = "LEFT", relativePoint = "LEFT", x = 4, y = 5 })
        assert.is_false(
            pcall(CoiledAltar.SetInterruptRotationTrackerPosition, CoiledAltar, { point = "TOP", x = 1, y = 2 })
        )
        assert.is_false(
            pcall(TwinFangs.SetInterruptRotationTrackerPosition, TwinFangs, { point = "TOP", relativePoint = "TOP" })
        )
        assert.same(
            { point = "LEFT", relativePoint = "LEFT", x = 4, y = 5 },
            TwinFangs:GetInterruptRotationTrackerPosition()
        )
    end)

    it("reads the anchor inherited from Twin Fangs", function()
        Start({
            schemaVersion = 10,
            modules = {
                TwinFangs = {
                    interruptStatusHudPosition = {
                        point = "TOPLEFT",
                        relativePoint = "TOPLEFT",
                        x = 20,
                        y = -30,
                    },
                },
            },
        })

        assert.same(
            { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 20, y = -30 },
            CoiledAltar:GetInterruptRotationTrackerPosition()
        )
        assert.equals(TwinFangs:GetInterruptRotationTrackerPosition(), CoiledAltar:GetInterruptRotationTrackerPosition())
    end)
end)
