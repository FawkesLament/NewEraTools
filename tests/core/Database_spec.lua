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
end)
