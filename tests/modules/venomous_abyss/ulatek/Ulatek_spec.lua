local Loader = require("helpers.loader")

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
end)
