local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("CoiledAltar", function()
    local Module

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
    end)

    it("registers with the interrupt reminder on and nameplate hint off", function()
        assert.is_false(Module == nil)
        assert.equals("table", type(Module.db))
        assert.is_true(Module:IsInterruptReminderEnabled())
        assert.is_true(Module.db.mechanicReminder.interrupt)
        assert.is_nil(Module.db.mechanicReminder.enabled)
        assert.is_false(Module:IsNameplateHintEnabled())
        assert.is_false(Module.db.nameplateHint.enabled)
    end)

    it("toggles and persists the interrupt checkbox", function()
        Module:SetInterruptReminderEnabled(false)
        assert.is_false(Module:IsInterruptReminderEnabled())
        assert.is_false(Module.db.mechanicReminder.interrupt)

        Module:SetInterruptReminderEnabled(true)
        assert.is_true(Module:IsInterruptReminderEnabled())
        assert.is_true(Module.db.mechanicReminder.interrupt)
    end)

    it("toggles and persists the nameplate hint", function()
        Module:SetNameplateHintEnabled(true)
        assert.is_true(Module:IsNameplateHintEnabled())
        assert.is_true(Module.db.nameplateHint.enabled)

        Module:SetNameplateHintEnabled(false)
        assert.is_false(Module:IsNameplateHintEnabled())
        assert.is_false(Module.db.nameplateHint.enabled)
    end)

    describe("nameplate preview", function()
        it("stays off until the hint is enabled", function()
            local calls = 0
            Module.OnNameplateHintPreviewChanged = function()
                calls = calls + 1
            end
            Module:SetNameplateHintPreviewing(true)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(0, calls)

            Module:SetNameplateHintEnabled(true)
            Module:SetNameplateHintPreviewing(true)
            assert.is_true(Module:IsNameplateHintPreviewing())
            Module:SetNameplateHintPreviewing(true)
            assert.equals(1, calls)

            Module:SetNameplateHintPreviewing(false)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(2, calls)

            Module:SetNameplateHintEnabled(false)
            assert.is_false(Module:IsNameplateHintPreviewing())
            assert.equals(2, calls)
        end)
    end)

    describe("appearance", function()
        it("defaults to the bottom of the nameplate at 100% scale with no offset", function()
            assert.equals(Module.SIDE_BOTTOM, Module:GetNameplateHintSide())
            AssertNear(1, Module:GetNameplateHintScale())
            assert.equals(14, Module:GetNameplateHintNumberFontSize())
            assert.equals(11, Module:GetNameplateHintNameFontSize())
            assert.equals(0, Module:GetNameplateHintOffsetX())
            assert.equals(0, Module:GetNameplateHintOffsetY())
        end)

        it("saves side, scale, font sizes, and offsets", function()
            local calls = 0
            Module.OnNameplateHintAppearanceChanged = function()
                calls = calls + 1
            end
            Module:SetNameplateHintSide(Module.SIDE_TOP)
            Module:SetNameplateHintScale(1.22)
            AssertNear(1.2, Module:GetNameplateHintScale())
            Module:SetNameplateHintNumberFontSize(18)
            Module:SetNameplateHintNameFontSize(9)
            Module:SetNameplateHintOffsetX(-12)
            Module:SetNameplateHintOffsetY(8)
            assert.equals(Module.SIDE_TOP, Module.db.nameplateHint.side)
            assert.equals(18, Module.db.nameplateHint.numberFontSize)
            assert.equals(9, Module.db.nameplateHint.nameFontSize)
            assert.equals(-12, Module.db.nameplateHint.offsetX)
            assert.equals(8, Module.db.nameplateHint.offsetY)
            assert.equals(6, calls)

            Module:SetNameplateHintSide(Module.SIDE_TOP)
            Module:SetNameplateHintScale(1.2)
            Module:SetNameplateHintNumberFontSize(18)
            Module:SetNameplateHintOffsetX(-12)
            assert.equals(6, calls)
        end)

        it("clamps scale, font sizes, and offsets to their ranges", function()
            Module:SetNameplateHintScale(0.1)
            AssertNear(Module.SCALE_MIN, Module:GetNameplateHintScale())
            Module:SetNameplateHintScale(3)
            AssertNear(Module.SCALE_MAX, Module:GetNameplateHintScale())
            Module:SetNameplateHintNumberFontSize(1)
            assert.equals(Module.NUMBER_FONT_SIZE_MIN, Module:GetNameplateHintNumberFontSize())
            Module:SetNameplateHintNumberFontSize(99)
            assert.equals(Module.NUMBER_FONT_SIZE_MAX, Module:GetNameplateHintNumberFontSize())
            Module:SetNameplateHintNameFontSize(1)
            assert.equals(Module.NAME_FONT_SIZE_MIN, Module:GetNameplateHintNameFontSize())
            Module:SetNameplateHintNameFontSize(99)
            assert.equals(Module.NAME_FONT_SIZE_MAX, Module:GetNameplateHintNameFontSize())
            Module:SetNameplateHintOffsetX(-200)
            assert.equals(Module.OFFSET_MIN, Module:GetNameplateHintOffsetX())
            Module:SetNameplateHintOffsetY(250)
            assert.equals(Module.OFFSET_MAX, Module:GetNameplateHintOffsetY())
        end)

        it("rejects a bad scale or side", function()
            assert.is_false(pcall(Module.SetNameplateHintScale, Module, "big"))
            AssertNear(1, Module:GetNameplateHintScale())
            assert.is_false(pcall(Module.SetNameplateHintSide, Module, "left"))
            assert.equals(Module.SIDE_BOTTOM, Module:GetNameplateHintSide())
        end)

        it("fills and clamps leftover saved appearance values", function()
            local ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                schemaVersion = 10,
                modules = {
                    CoiledAltar = {
                        nameplateHint = {
                            enabled = true,
                            side = "left",
                            scale = 9,
                            numberFontSize = 99,
                            offsetX = -400,
                        },
                    },
                },
            }))
            local coiled = ns.Modules.Get("CoiledAltar")
            assert.is_true(coiled:IsNameplateHintEnabled())
            assert.equals(coiled.SIDE_BOTTOM, coiled:GetNameplateHintSide())
            AssertNear(coiled.SCALE_MAX, coiled:GetNameplateHintScale())
            assert.equals(coiled.NUMBER_FONT_SIZE_MAX, coiled:GetNameplateHintNumberFontSize())
            assert.equals(11, coiled:GetNameplateHintNameFontSize())
            assert.equals(coiled.OFFSET_MIN, coiled:GetNameplateHintOffsetX())
            assert.equals(0, coiled:GetNameplateHintOffsetY())
        end)
    end)

    describe("marked chain", function()
        it("treats a missing or illegal saved value as melee", function()
            assert.equals("MELEE", Module:GetMarkedChain())
            Module.db.markedChain = nil
            assert.equals("MELEE", Module:GetMarkedChain())
            Module.db.markedChain = "BOTH"
            assert.equals("MELEE", Module:GetMarkedChain())

            local ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                schemaVersion = 12,
                modules = {
                    CoiledAltar = {
                        markedChain = "BOTH",
                    },
                },
            }))
            local coiled = ns.Modules.Get("CoiledAltar")
            assert.equals("MELEE", coiled:GetMarkedChain())
            assert.equals("MELEE", coiled.db.markedChain)
        end)

        it("rejects an illegal chain and notifies encounter state only when the value changes", function()
            local notifies = 0
            Module.OnInterruptStateChanged = function()
                notifies = notifies + 1
            end
            assert.is_false(pcall(Module.SetMarkedChain, Module, "BOTH"))
            assert.equals("MELEE", Module:GetMarkedChain())
            assert.equals(0, notifies)

            assert.is_false(Module:SetMarkedChain("MELEE"))
            assert.equals("MELEE", Module.db.markedChain)
            assert.equals(0, notifies)

            assert.is_true(Module:SetMarkedChain("RANGED"))
            assert.equals("RANGED", Module:GetMarkedChain())
            assert.equals(1, notifies)

            assert.is_false(Module:SetMarkedChain("RANGED"))
            assert.equals(1, notifies)
        end)
    end)
end)
