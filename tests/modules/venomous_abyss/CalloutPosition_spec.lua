local Loader = require("helpers.loader")

describe("Callout position", function()
    local ns, Sszorak, TheLostExplorers, TwinFangs

    local function Start(saved)
        ns = Loader.Load()
        local loaded = ns.Database.Load(saved)
        ns.Modules.Start(loaded)
        Sszorak = ns.Modules.Get("Sszorak")
        TheLostExplorers = ns.Modules.Get("TheLostExplorers")
        TwinFangs = ns.Modules.Get("TwinFangs")
        return loaded
    end

    before_each(function()
        Start(nil)
    end)

    it("starts the three bosses on one factory anchor", function()
        local position = Sszorak:GetCalloutPosition()
        assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 160 }, position)
        assert.equals(position, TheLostExplorers:GetCalloutPosition())
        assert.equals(position, TwinFangs:GetCalloutPosition())
        assert.equals(position, ns.CalloutPosition.GetPosition())
        assert.is_nil(Sszorak.db.calloutPosition)
        assert.is_nil(TheLostExplorers.db.calloutPosition)
        assert.is_nil(TwinFangs.db.soakReminder.calloutPosition)
    end)

    it("writes one saved anchor from any of the three bosses", function()
        local saved = Start(nil)
        local moved = { point = "TOP", relativePoint = "CENTER", x = 12, y = -40 }
        TwinFangs:SetCalloutPosition(moved)

        assert.same(moved, Sszorak:GetCalloutPosition())
        assert.same(moved, TheLostExplorers:GetCalloutPosition())
        assert.equals(Sszorak:GetCalloutPosition(), TwinFangs:GetCalloutPosition())
        assert.equals(saved.calloutPosition, Sszorak:GetCalloutPosition())

        Start(saved)
        assert.same(moved, TheLostExplorers:GetCalloutPosition())
        assert.equals(saved.calloutPosition, TwinFangs:GetCalloutPosition())
    end)

    it("rejects an incomplete anchor and leaves the shared one in place", function()
        Sszorak:SetCalloutPosition({ point = "LEFT", relativePoint = "LEFT", x = 4, y = 5 })
        assert.is_false(pcall(TheLostExplorers.SetCalloutPosition, TheLostExplorers, { point = "TOP", x = 1, y = 2 }))
        assert.is_false(pcall(TwinFangs.SetCalloutPosition, TwinFangs, { point = "TOP", relativePoint = "TOP" }))
        assert.same({ point = "LEFT", relativePoint = "LEFT", x = 4, y = 5 }, Sszorak:GetCalloutPosition())
    end)

    it("reads the anchor inherited from Sszorak", function()
        Start({
            schemaVersion = 7,
            modules = {
                Sszorak = { calloutPosition = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 20, y = -30 } },
                TheLostExplorers = { calloutPosition = { point = "BOTTOM", relativePoint = "BOTTOM", x = 1, y = 2 } },
            },
        })

        assert.same({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 20, y = -30 }, TwinFangs:GetCalloutPosition())
        assert.equals(TwinFangs:GetCalloutPosition(), TheLostExplorers:GetCalloutPosition())
    end)

    it("reads the anchor inherited from The Lost Explorers when Sszorak has none", function()
        Start({
            schemaVersion = 7,
            modules = {
                TheLostExplorers = {
                    calloutPosition = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = -4, y = 8 },
                },
            },
        })

        assert.same({ point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = -4, y = 8 }, Sszorak:GetCalloutPosition())
    end)
end)
