local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Ulatek", function()
    local Module

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("Ulatek")
    end)

    it("registers with mechanic reminders off", function()
        assert.is_false(Module == nil)
        assert.equals("table", type(Module.db))
        assert.is_false(Module:IsEggDeadlineReminderEnabled())
        assert.is_false(Module.db.mechanicReminder.eggDeadline)
        assert.is_false(Module:IsCausticWavesReminderEnabled())
        assert.is_false(Module.db.mechanicReminder.causticWaves)
        assert.is_false(Module:IsWretchAoeReminderEnabled())
        assert.is_false(Module.db.mechanicReminder.wretchAoe)
        assert.is_true(Module:IsDefaultCornerMarkers())
        assert.equals("STAR", Module:GetCornerMarker(1))
    end)

    it("toggles and persists each reminder independently", function()
        Module:SetEggDeadlineReminderEnabled(true)
        assert.is_true(Module:IsEggDeadlineReminderEnabled())
        assert.is_false(Module:IsCausticWavesReminderEnabled())
        assert.is_false(Module:IsWretchAoeReminderEnabled())

        Module:SetCausticWavesReminderEnabled(true)
        Module:SetWretchAoeReminderEnabled(true)
        Module:SetEggDeadlineReminderEnabled(false)
        assert.is_false(Module:IsEggDeadlineReminderEnabled())
        assert.is_true(Module:IsCausticWavesReminderEnabled())
        assert.is_true(Module:IsWretchAoeReminderEnabled())
        assert.is_true(Module.db.mechanicReminder.causticWaves)
        assert.is_true(Module.db.mechanicReminder.wretchAoe)
    end)

    it("coerces invalid reminder flags to false", function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            schemaVersion = 17,
            modules = {
                Ulatek = {
                    mechanicReminder = { eggDeadline = 1, causticWaves = "yes" },
                },
            },
        }))
        local ulatek = ns.Modules.Get("Ulatek")
        assert.is_false(ulatek:IsEggDeadlineReminderEnabled())
        assert.is_false(ulatek:IsCausticWavesReminderEnabled())
        assert.is_false(ulatek:IsWretchAoeReminderEnabled())
    end)

    describe("tactical pad position", function()
        it("starts at the unset factory default", function()
            assert.same(
                { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
                Module:GetTacticalPadPosition()
            )
        end)

        it("is saved", function()
            Module:SetTacticalPadPosition({ point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 })
            assert.same(
                { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 },
                Module.db.tacticalPadPosition
            )
        end)

        it("rejects incomplete positions", function()
            assert.is_false(pcall(Module.SetTacticalPadPosition, Module, { point = "TOPLEFT", x = 1, y = 2 }))
            assert.equals("CENTER", Module:GetTacticalPadPosition().point)
        end)

        it("repairs a corrupt saved position", function()
            local ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load({
                schemaVersion = 18,
                modules = {
                    Ulatek = {
                        tacticalPadPosition = { point = "CENTER" },
                    },
                },
            }))
            local ulatek = ns.Modules.Get("Ulatek")
            assert.same(
                { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
                ulatek:GetTacticalPadPosition()
            )
        end)
    end)

    describe("tactical pad scale", function()
        it("is 100% by default", function()
            AssertNear(1, Module:GetTacticalPadScale())
        end)

        it("is saved and snapped to the step", function()
            Module:SetTacticalPadScale(1.22)
            AssertNear(1.2, Module:GetTacticalPadScale())
            AssertNear(1.2, Module.db.tacticalPadScale)
        end)

        it("clamps to the allowed range", function()
            Module:SetTacticalPadScale(0.1)
            AssertNear(Module.PAD_SCALE_MIN, Module:GetTacticalPadScale())
            Module:SetTacticalPadScale(3)
            AssertNear(Module.PAD_SCALE_MAX, Module:GetTacticalPadScale())
        end)

        it("rejects non-numbers", function()
            assert.is_false(pcall(Module.SetTacticalPadScale, Module, "big"))
            AssertNear(1, Module:GetTacticalPadScale())
        end)
    end)
end)
