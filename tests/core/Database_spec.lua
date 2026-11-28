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

    describe("retired schemas through 12", function()
        it("loads schema 12 and older without running removed 7–12 transforms", function()
            local saved = Database.Load({
                schemaVersion = 6,
                modules = {
                    Sszorak = { mapRotated = true, mapEnabled = false },
                    CombatTimer = { enabled = true },
                },
            })

            assert.equals(18, saved.schemaVersion)
            assert.is_true(saved.modules.Sszorak.mapRotated)
            assert.is_false(saved.modules.Sszorak.mapEnabled)
            assert.is_true(saved.modules.CombatTimer.enabled)
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

            assert.equals(18, saved.schemaVersion)
            assert.is_nil(saved.modules.CoiledAltar.mechanicReminder.enabled)
            assert.is_true(saved.modules.CoiledAltar.mechanicReminder.interrupt)
        end)
    end)

    describe("Boss Alert callout font size", function()
        it("converts the old alert-body size into the countdown size", function()
            local saved = Database.Load({
                schemaVersion = 13,
                modules = {
                    BossAlert = {
                        callout = { fontSize = 40, scale = 1.1 },
                    },
                },
            })

            assert.equals(18, saved.schemaVersion)
            assert.equals(48, saved.modules.BossAlert.callout.countdownFontSize)
            assert.is_nil(saved.modules.BossAlert.callout.fontSize)
            assert.equals(1.1, saved.modules.BossAlert.callout.scale)
        end)

        it("leaves callout settings alone when fontSize is unset", function()
            local saved = Database.Load({
                schemaVersion = 13,
                modules = {
                    BossAlert = {
                        callout = { scale = 1 },
                    },
                },
            })

            assert.is_nil(saved.modules.BossAlert.callout.fontSize)
            assert.is_nil(saved.modules.BossAlert.callout.countdownFontSize)
            assert.equals(1, saved.modules.BossAlert.callout.scale)
        end)

        it("renames callout appearance keys", function()
            local saved = Database.Load({
                schemaVersion = 14,
                modules = {
                    BossAlert = {
                        callout = {
                            font = "Custom Font",
                            fontSize = 48,
                            fontColor = { r = 0, g = 1, b = 0 },
                        },
                    },
                },
            })

            local callout = saved.modules.BossAlert.callout
            assert.equals("Custom Font", callout.alertFont)
            assert.equals(48, callout.countdownFontSize)
            assert.equals(0, callout.alertFontColor.r)
            assert.equals(1, callout.alertFontColor.g)
            assert.is_nil(callout.font)
            assert.is_nil(callout.fontSize)
            assert.is_nil(callout.fontColor)
        end)
    end)

    describe("Coiled Altar single-shadow migration", function()
        it("moves MELEE assignments into RANGED when RANGED is empty and resets markedChain to MELEE", function()
            local saved = Database.Load({
                schemaVersion = 15,
                modules = {
                    CoiledAltar = {
                        markedChain = "RANGED",
                        assignments = {
                            MELEE = {
                                { type = "player", value = "Alice-TestRealm" },
                            },
                            RANGED = {},
                        },
                    },
                },
            })

            local coiled = saved.modules.CoiledAltar
            assert.equals(18, saved.schemaVersion)
            assert.equals("MELEE", coiled.markedChain)
            assert.same({}, coiled.assignments.MELEE)
            assert.same({ { type = "player", value = "Alice-TestRealm" } }, coiled.assignments.RANGED)
        end)

        it("keeps RANGED when both chains are populated and markedChain was MELEE", function()
            local saved = Database.Load({
                schemaVersion = 15,
                modules = {
                    CoiledAltar = {
                        markedChain = "MELEE",
                        assignments = {
                            MELEE = { { type = "player", value = "Melee-TestRealm" } },
                            RANGED = { { type = "player", value = "Ranged-TestRealm" } },
                        },
                    },
                },
            })

            local coiled = saved.modules.CoiledAltar
            assert.equals("MELEE", coiled.markedChain)
            assert.same({}, coiled.assignments.MELEE)
            assert.same({ { type = "player", value = "Ranged-TestRealm" } }, coiled.assignments.RANGED)
        end)

        it("prefers MELEE when both chains are populated and markedChain was RANGED", function()
            local saved = Database.Load({
                schemaVersion = 15,
                modules = {
                    CoiledAltar = {
                        markedChain = "RANGED",
                        assignments = {
                            MELEE = { { type = "player", value = "Melee-TestRealm" } },
                            RANGED = { { type = "player", value = "Ranged-TestRealm" } },
                        },
                    },
                },
            })

            local coiled = saved.modules.CoiledAltar
            assert.equals("MELEE", coiled.markedChain)
            assert.same({}, coiled.assignments.MELEE)
            assert.same({ { type = "player", value = "Melee-TestRealm" } }, coiled.assignments.RANGED)
        end)
    end)

    describe("Twin Fangs venom roster appearance keys", function()
        it("renames rowSpacing and columnSpacing without overwriting newer keys", function()
            local saved = Database.Load({
                schemaVersion = 16,
                modules = {
                    TwinFangs = {
                        venomRoster = {
                            enabled = true,
                            rowSpacing = 24,
                            rowGap = 2,
                            columnSpacing = 8,
                            nameColumnWidth = 90,
                        },
                    },
                },
            })

            local roster = saved.modules.TwinFangs.venomRoster
            assert.equals(18, saved.schemaVersion)
            assert.equals(24, roster.rowHeight)
            assert.equals(8, roster.columnGap)
            assert.equals(2, roster.rowGap)
            assert.equals(90, roster.nameColumnWidth)
            assert.is_nil(roster.rowSpacing)
            assert.is_nil(roster.columnSpacing)
        end)

        it("keeps already-renamed keys when both old and new names are present", function()
            local saved = Database.Load({
                schemaVersion = 16,
                modules = {
                    TwinFangs = {
                        venomRoster = {
                            rowSpacing = 18,
                            rowHeight = 26,
                            columnSpacing = 4,
                            columnGap = 10,
                        },
                    },
                },
            })

            local roster = saved.modules.TwinFangs.venomRoster
            assert.equals(26, roster.rowHeight)
            assert.equals(10, roster.columnGap)
            assert.is_nil(roster.rowSpacing)
            assert.is_nil(roster.columnSpacing)
        end)
    end)

    describe("Ulatek Wretch AoE reminder key", function()
        it("renames addSoak without overwriting a newer key", function()
            local saved = Database.Load({
                schemaVersion = 17,
                modules = {
                    Ulatek = {
                        mechanicReminder = {
                            eggDeadline = true,
                            addSoak = true,
                        },
                    },
                },
            })

            local reminder = saved.modules.Ulatek.mechanicReminder
            assert.equals(18, saved.schemaVersion)
            assert.is_true(reminder.wretchAoe)
            assert.is_true(reminder.eggDeadline)
            assert.is_nil(reminder.addSoak)
        end)

        it("keeps already-renamed keys when both old and new names are present", function()
            local saved = Database.Load({
                schemaVersion = 17,
                modules = {
                    Ulatek = {
                        mechanicReminder = {
                            addSoak = true,
                            wretchAoe = false,
                        },
                    },
                },
            })

            local reminder = saved.modules.Ulatek.mechanicReminder
            assert.is_false(reminder.wretchAoe)
            assert.is_nil(reminder.addSoak)
        end)
    end)
end)
