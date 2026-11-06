local Loader = require("helpers.loader")

describe("Database", function()
    local Database

    before_each(function()
        Database = Loader.Load().Database
    end)

    it("creates missing saved variables at the current schema", function()
        local saved = Database.Load(nil)
        assert.equals("number", type(saved.schemaVersion))
        assert.same({}, saved.modules)
    end)

    it("keeps existing module settings and fills in defaults", function()
        local saved = Database.Load({ modules = { Test = { count = 3 } } })
        local settings = Database.GetModuleSettings(saved, "Test", { count = 1, excluded = {} })
        assert.same({ count = 3, excluded = {} }, settings)
        assert.equals(settings, saved.modules.Test)
    end)

    describe("callout position", function()
        local function SavedAt7(modules)
            return Database.Load({
                schemaVersion = 7,
                modules = modules,
            })
        end

        it("keeps Sszorak's anchor when both launched bosses saved one", function()
            local saved = SavedAt7({
                Sszorak = {
                    mapEnabled = false,
                    calloutPosition = { point = "TOP", relativePoint = "TOP", x = 1, y = 2 },
                },
                TheLostExplorers = {
                    enabled = true,
                    calloutPosition = { point = "BOTTOM", relativePoint = "BOTTOM", x = 3, y = 4 },
                },
            })

            assert.same({ point = "TOP", relativePoint = "TOP", x = 1, y = 2 }, saved.calloutPosition)
            assert.is_nil(saved.modules.Sszorak.calloutPosition)
            assert.is_false(saved.modules.Sszorak.mapEnabled)
            assert.is_nil(saved.modules.TheLostExplorers.calloutPosition)
            assert.is_true(saved.modules.TheLostExplorers.enabled)
        end)

        it("uses The Lost Explorers when Sszorak has no callout anchor", function()
            local saved = SavedAt7({
                Sszorak = { mapEnabled = true },
                TheLostExplorers = {
                    calloutPosition = { point = "RIGHT", relativePoint = "RIGHT", x = -8, y = 9 },
                },
            })

            assert.same({ point = "RIGHT", relativePoint = "RIGHT", x = -8, y = 9 }, saved.calloutPosition)
            assert.is_true(saved.modules.Sszorak.mapEnabled)
        end)

        it("drops an invalid Sszorak anchor and keeps The Lost Explorers", function()
            local saved = SavedAt7({
                Sszorak = { calloutPosition = { point = "TOP" } },
                TheLostExplorers = {
                    calloutPosition = { point = "CENTER", relativePoint = "CENTER", x = 12, y = -40 },
                },
            })

            assert.same({ point = "CENTER", relativePoint = "CENTER", x = 12, y = -40 }, saved.calloutPosition)
            assert.is_nil(saved.modules.Sszorak.calloutPosition)
        end)

        it("leaves the shared anchor unset when neither boss saved one", function()
            local saved = SavedAt7({
                Sszorak = { mapEnabled = false },
                TheLostExplorers = { enabled = true },
            })

            assert.is_nil(saved.calloutPosition)
            assert.is_false(saved.modules.Sszorak.mapEnabled)
            assert.is_true(saved.modules.TheLostExplorers.enabled)
        end)
    end)

    describe("Interrupt Claim unlaunch", function()
        it("drops InterruptClaim settings and keeps other modules", function()
            local saved = Database.Load({
                schemaVersion = 9,
                modules = {
                    InterruptClaim = { enabled = true, modifier = "ctrl" },
                    CombatTimer = { enabled = true },
                },
            })

            assert.equals(13, saved.schemaVersion)
            assert.is_nil(saved.modules.InterruptClaim)
            assert.is_true(saved.modules.CombatTimer.enabled)
        end)

        it("leaves saved data intact when InterruptClaim was never stored", function()
            local saved = Database.Load({
                schemaVersion = 9,
                modules = { CombatTimer = { enabled = false } },
            })

            assert.is_nil(saved.modules.InterruptClaim)
            assert.is_false(saved.modules.CombatTimer.enabled)
        end)
    end)

    describe("interrupt rotation tracker position", function()
        it("promotes Twin Fangs' interrupt HUD anchor to the shared key", function()
            local saved = Database.Load({
                schemaVersion = 10,
                modules = {
                    TwinFangs = {
                        interruptStatusHudPosition = {
                            point = "BOTTOM",
                            relativePoint = "BOTTOM",
                            x = 8,
                            y = 16,
                        },
                    },
                },
            })

            assert.same({
                point = "BOTTOM",
                relativePoint = "BOTTOM",
                x = 8,
                y = 16,
            }, saved.interruptRotationTrackerPosition)
            assert.is_nil(saved.interruptStatusHudPosition)
            assert.is_nil(saved.modules.TwinFangs.interruptStatusHudPosition)
        end)

        it("promotes a leftover Twin Fangs statusHudPosition when the renamed key is missing", function()
            local saved = Database.Load({
                schemaVersion = 10,
                modules = {
                    TwinFangs = {
                        statusHudPosition = { point = "TOP", relativePoint = "TOP", x = 4, y = -8 },
                    },
                },
            })

            assert.same({ point = "TOP", relativePoint = "TOP", x = 4, y = -8 }, saved.interruptRotationTrackerPosition)
            assert.is_nil(saved.interruptStatusHudPosition)
            assert.is_nil(saved.modules.TwinFangs.statusHudPosition)
        end)

        it("drops an invalid Twin Fangs HUD anchor", function()
            local saved = Database.Load({
                schemaVersion = 10,
                modules = {
                    TwinFangs = {
                        interruptStatusHudPosition = { point = "CENTER", x = 0, y = 80 },
                    },
                },
            })

            assert.is_nil(saved.interruptRotationTrackerPosition)
            assert.is_nil(saved.interruptStatusHudPosition)
            assert.is_nil(saved.modules.TwinFangs.interruptStatusHudPosition)
        end)

        it("renames the shared interruptStatusHudPosition key", function()
            local saved = Database.Load({
                schemaVersion = 11,
                interruptStatusHudPosition = {
                    point = "LEFT",
                    relativePoint = "LEFT",
                    x = 2,
                    y = 4,
                },
            })

            assert.same({
                point = "LEFT",
                relativePoint = "LEFT",
                x = 2,
                y = 4,
            }, saved.interruptRotationTrackerPosition)
            assert.is_nil(saved.interruptStatusHudPosition)
        end)
    end)

    describe("Coiled Altar mechanic reminder", function()
        it("drops the leftover section toggle and keeps the interrupt checkbox", function()
            local saved = Database.Load({
                schemaVersion = 12,
                modules = {
                    CoiledAltar = {
                        mechanicReminder = { enabled = true, interrupt = true },
                    },
                },
            })

            assert.equals(13, saved.schemaVersion)
            assert.is_nil(saved.modules.CoiledAltar.mechanicReminder.enabled)
            assert.is_true(saved.modules.CoiledAltar.mechanicReminder.interrupt)
        end)
    end)
end)
