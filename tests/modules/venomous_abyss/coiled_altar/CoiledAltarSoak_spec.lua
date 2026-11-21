local Loader = require("helpers.loader")

describe("CoiledAltar soak", function()
    local ns, Module, Internals, Detector, Encounter, EncounterTimeline, Spell, Timer, CalloutManager

    local CAST_DEADLINE = 3.5
    local REMINDER_LEAD = 10
    local P1_FIRST_CAST = 43.0
    local P1_SECOND_CAST = 128.0
    local P3_FIRST_CAST = 16.64
    local P3_SECOND_CAST = 81.1
    local P3_THIRD_CAST = 181.1

    local function StartEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
    end

    local function EndEncounter()
        Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
    end

    local function FireEncounterAdded(id, overrides)
        local eventInfo = {
            id = id,
            source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER,
            duration = 10,
            spellID = 12345,
        }
        if overrides then
            for key, value in pairs(overrides) do
                eventInfo[key] = value
            end
        end
        EncounterTimeline.FireEventAdded(eventInfo)
    end

    local function EnterP2()
        Timer.Advance(5)
        FireEncounterAdded(70, { duration = 70 })
    end

    local function EnterI2()
        EnterP2()
        EncounterTimeline.SetEventsForTests(nil)
        Spell.FireChannelStart("boss2")
    end

    local function FireP3Batch()
        FireEncounterAdded(11)
        Timer.Advance(0.003)
        FireEncounterAdded(12)
        Timer.Advance(0.003)
        FireEncounterAdded(13)
        Timer.Advance(0.003)
        FireEncounterAdded(14)
    end

    local function EnterP3()
        EnterI2()
        FireP3Batch()
    end

    local function AdvanceTo(absoluteTime)
        Timer.Advance(absoluteTime - Timer.GetTime())
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Internals = ns.Modules.Internals("CoiledAltar")
        Detector = Internals.PhaseDetector
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        CalloutManager = ns.CalloutManager
        Module:ListenForEncounter()
    end)

    describe("P1 reminders", function()
        it("shows the first-wave callout 10s before the soak deadline", function()
            Module:SetSoakP1FirstReminderEnabled(true)
            StartEncounter()
            local pullStart = Timer.GetTime()
            local deadline = pullStart + P1_FIRST_CAST + CAST_DEADLINE
            AdvanceTo(deadline - REMINDER_LEAD - 0.01)
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(0.01)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals("CoiledAltarSoak", CalloutManager.GetCurrent().source)
            assert.equals(deadline, CalloutManager.GetExpiresAt())
            assert.is_true(CalloutManager.GetAppendTimer())
            AdvanceTo(deadline)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("shows the second-wave callout from combat start", function()
            Module:SetSoakP1SecondReminderEnabled(true)
            StartEncounter()
            local pullStart = Timer.GetTime()
            local deadline = pullStart + P1_SECOND_CAST + CAST_DEADLINE
            AdvanceTo(deadline - REMINDER_LEAD - 0.01)
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(0.01)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(deadline, CalloutManager.GetExpiresAt())
        end)

        it("does not show a disabled P1 wave", function()
            Module:SetSoakP1SecondReminderEnabled(true)
            StartEncounter()
            AdvanceTo(Timer.GetTime() + P1_FIRST_CAST + CAST_DEADLINE)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("cancels pending P1 reminders when entering P2", function()
            Module:SetSoakP1FirstReminderEnabled(true)
            StartEncounter()
            EnterP2()
            assert.equals("P2", Detector.GetPhase())
            Timer.Advance(P1_FIRST_CAST)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("hides an active P1 callout when entering P2", function()
            Module:SetSoakP1FirstReminderEnabled(true)
            StartEncounter()
            local pullStart = Timer.GetTime()
            AdvanceTo(pullStart + P1_FIRST_CAST + CAST_DEADLINE - REMINDER_LEAD)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            FireEncounterAdded(70, { duration = 70 })
            assert.equals("P2", Detector.GetPhase())
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("hides the presented wave when that checkbox is turned off", function()
            Module:SetSoakP1FirstReminderEnabled(true)
            StartEncounter()
            AdvanceTo(Timer.GetTime() + P1_FIRST_CAST + CAST_DEADLINE - REMINDER_LEAD)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            Module:SetSoakP1FirstReminderEnabled(false)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)

    describe("P3 reminders", function()
        it("schedules the first P3 soak from phase enter", function()
            Module:SetSoakP3FirstReminderEnabled(true)
            StartEncounter()
            EnterP3()
            assert.equals("P3", Detector.GetPhase())
            local p3Start = Detector.GetPhaseStartTime()
            local deadline = p3Start + P3_FIRST_CAST + CAST_DEADLINE
            AdvanceTo(deadline - REMINDER_LEAD - 0.01)
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(0.01)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(deadline, CalloutManager.GetExpiresAt())
            assert.is_true(CalloutManager.GetAppendTimer())
        end)

        it("schedules later P3 soaks independently of P1 settings", function()
            Module:SetSoakP3SecondReminderEnabled(true)
            StartEncounter()
            EnterP3()
            local p3Start = Detector.GetPhaseStartTime()
            AdvanceTo(p3Start + P3_FIRST_CAST + CAST_DEADLINE)
            assert.is_nil(CalloutManager.GetDisplayed())
            local deadline = p3Start + P3_SECOND_CAST + CAST_DEADLINE
            AdvanceTo(deadline - REMINDER_LEAD)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(deadline, CalloutManager.GetExpiresAt())
        end)

        it("schedules the third P3 soak", function()
            Module:SetSoakP3ThirdReminderEnabled(true)
            StartEncounter()
            EnterP3()
            local p3Start = Detector.GetPhaseStartTime()
            local deadline = p3Start + P3_THIRD_CAST + CAST_DEADLINE
            AdvanceTo(deadline - REMINDER_LEAD)
            assert.equals(ns.L.COILED_ALTAR_SOAK_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(deadline, CalloutManager.GetExpiresAt())
        end)

        it("does not show a disabled P3 wave", function()
            Module:SetSoakP3SecondReminderEnabled(true)
            StartEncounter()
            EnterP3()
            AdvanceTo(Detector.GetPhaseStartTime() + P3_FIRST_CAST + CAST_DEADLINE)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)

    describe("lifecycle", function()
        it("does not fire delayed callbacks after the encounter ends", function()
            Module:SetSoakP1FirstReminderEnabled(true)
            StartEncounter()
            EndEncounter()
            Timer.Advance(P1_FIRST_CAST)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("does not leak P3 reminders after the encounter ends", function()
            Module:SetSoakP3FirstReminderEnabled(true)
            StartEncounter()
            EnterP3()
            EndEncounter()
            Timer.Advance(P3_FIRST_CAST)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)
end)
