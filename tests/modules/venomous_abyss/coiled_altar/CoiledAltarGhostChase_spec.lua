local Loader = require("helpers.loader")

describe("CoiledAltar ghost chase", function()
    local ns, Module, Internals, Detector, Encounter, EncounterTimeline, Spell, Timer, CalloutManager, Instance

    local function StartEncounter(difficultyID)
        Encounter.FireStart(
            Module.ENCOUNTER_ID,
            "The Coiled Altar",
            difficultyID or Instance.DIFFICULTY_MYTHIC_RAID,
            20
        )
    end

    local function EndEncounter()
        Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
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

    local function EnterP3()
        EnterP2()
        EncounterTimeline.SetEventsForTests(nil)
        Spell.FireChannelStart("boss2")
        FireEncounterAdded(11)
        Timer.Advance(0.003)
        FireEncounterAdded(12)
        Timer.Advance(0.003)
        FireEncounterAdded(13)
        Timer.Advance(0.003)
        FireEncounterAdded(14)
    end

    local function ValidWarning(overrides)
        local warningInfo = {
            severity = Module.GHOST_CHASE_WARNING_SEVERITY,
            duration = Module.GHOST_CHASE_WARNING_DURATION,
        }
        if overrides then
            for key, value in pairs(overrides) do
                warningInfo[key] = value
            end
        end
        return warningInfo
    end

    local function FireValidWarning(overrides)
        Encounter.FireWarning(ValidWarning(overrides))
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
        Instance = ns.Api.Instance
        Module:ListenForEncounter()
    end)

    describe("dreadmarch window", function()
        it("treats P2 offsets in [1.5, 7.5] and [35.5, 44.5] as dreadmarch each 85s round", function()
            assert.is_false(Internals.IsDreadmarchWindow("P2", 1.49))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 1.5))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 7.5))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 7.51))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 12.5))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 35.49))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 35.5))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 44.5))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 44.51))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 85 + 4))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 85 + 40))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 85 + 12.5))
        end)

        it("opens P2 window 1 early from a late-round start through the next 7.5", function()
            assert.equals(85 + 7.5, Internals.GhostChaseP2Window1EarlyEnd(70))
            assert.equals(85 + 7.5, Internals.GhostChaseP2Window1EarlyEnd(80))
            assert.equals(7.5, Internals.GhostChaseP2Window1EarlyEnd(0.5))
            assert.equals(85 + 7.5, Internals.GhostChaseP2Window1EarlyEnd(85 + 1))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 80, 70))
            assert.is_true(Internals.IsDreadmarchWindow("P2", 86, 70))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 85 + 7.51, 70))
            assert.is_false(Internals.IsDreadmarchWindow("P2", 1, nil))
        end)

        it("treats P3 [55, 60] as dreadmarch and allows an early open from 38", function()
            assert.is_false(Internals.IsDreadmarchWindow("P3", 54.99))
            assert.is_true(Internals.IsDreadmarchWindow("P3", 55))
            assert.is_true(Internals.IsDreadmarchWindow("P3", 60))
            assert.is_false(Internals.IsDreadmarchWindow("P3", 60.01))
            assert.is_true(Internals.IsDreadmarchWindow("P3", 40, nil, 38))
            assert.is_false(Internals.IsDreadmarchWindow("P3", 37.99, nil, 38))
            assert.is_false(Internals.IsDreadmarchWindow("P3", 45))
            assert.is_false(Internals.IsDreadmarchWindow("P1", 12.5))
            assert.is_false(Internals.IsDreadmarchWindow("I2", 4))
        end)
    end)

    describe("encounter warning", function()
        before_each(function()
            Module:SetGhostChaseReminderEnabled(true)
        end)

        it("ignores warnings outside the boss fight", function()
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("ignores warnings in P1 even at a P2 elapsed", function()
            StartEncounter()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.equals("P1", Detector.GetPhase())
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("ignores warnings that fail severity or duration checks", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            Encounter.FireWarning({
                severity = 2,
                duration = Module.GHOST_CHASE_WARNING_DURATION,
            })
            assert.is_nil(CalloutManager.GetDisplayed())
            Encounter.FireWarning({
                severity = Module.GHOST_CHASE_WARNING_SEVERITY,
                duration = Module.GHOST_CHASE_WARNING_DURATION + Module.GHOST_CHASE_WARNING_DURATION_TOLERANCE + 0.01,
            })
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("accepts duration at both ends of the ±0.5 window", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            Encounter.FireWarning({
                severity = Module.GHOST_CHASE_WARNING_SEVERITY,
                duration = Module.GHOST_CHASE_WARNING_DURATION - Module.GHOST_CHASE_WARNING_DURATION_TOLERANCE,
            })
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            EndEncounter()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            Encounter.FireWarning({
                severity = Module.GHOST_CHASE_WARNING_SEVERITY,
                duration = Module.GHOST_CHASE_WARNING_DURATION + Module.GHOST_CHASE_WARNING_DURATION_TOLERANCE,
            })
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("shows a 22-second Callout on a Mythic P2 warning outside dreadmarch windows", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals("CoiledAltarGhostChase", CalloutManager.GetCurrent().source)
            assert.is_true(CalloutManager.GetAppendTimer())
            assert.equals(Timer.GetTime() + Module.GHOST_CHASE_CALLOUT_DURATION, CalloutManager.GetExpiresAt())
            Timer.Advance(Module.GHOST_CHASE_CALLOUT_DURATION - 1)
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            Timer.Advance(1)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("does not show for Mythic P2 warnings inside either dreadmarch window", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(4)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(36)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("opens P2 window 1 early on boss2 UNIT_SPELLCAST_STOP in the late-round eligibility span", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(80)
            Spell.FireCastStop("boss2", "Cast-1", 1)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(6)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(85 + 7.5 - 86 + 0.02)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("does not open P2 window 1 early on UNIT_SPELLCAST_STOP from another unit", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(80)
            Spell.FireCastStop("boss1", "Cast-1", 1)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("closes an early P2 window on I2 so a later P3 warning is classified from P3 elapsed", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(80)
            Spell.FireCastStop("boss2", "Cast-1", 1)
            EncounterTimeline.SetEventsForTests(nil)
            Spell.FireChannelStart("boss2")
            assert.equals("I2", Detector.GetPhase())
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("matches Mythic P3 ghost chase from phase elapsed, not pull elapsed", function()
            StartEncounter()
            EnterP3()
            assert.equals("P3", Detector.GetPhase())
            Timer.Advance(62.4)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("does not show for Mythic P3 warnings inside the dreadmarch window", function()
            StartEncounter()
            EnterP3()
            Timer.Advance(57)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("opens the P3 window early on boss2 UNIT_SPELLCAST_STOP between 38s and 55s", function()
            StartEncounter()
            EnterP3()
            Timer.Advance(40)
            Spell.FireCastStop("boss2", "Cast-1", 1)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(21)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("does not open the P3 window early when boss2 stops before 38s", function()
            StartEncounter()
            EnterP3()
            Timer.Advance(30)
            Spell.FireCastStop("boss2", "Cast-1", 1)
            Timer.Advance(15)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("does not show when the reminder is disabled", function()
            Module:SetGhostChaseReminderEnabled(false)
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("hides a showing Callout when the reminder is turned off", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            Module:SetGhostChaseReminderEnabled(false)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("clears the Callout when the fight ends", function()
            StartEncounter()
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            EndEncounter()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("does not monitor ghost chase on Heroic", function()
            StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("ignores warnings on difficulties without Mythic monitoring", function()
            StartEncounter(14)
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)
end)
