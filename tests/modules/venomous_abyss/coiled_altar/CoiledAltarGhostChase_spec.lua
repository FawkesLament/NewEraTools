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

    describe("anchor matcher", function()
        it("accepts a hit from 3 seconds before to 5 seconds after an unused anchor", function()
            local anchors = { 12.5 }
            local used = {}
            assert.equals(1, Internals.MatchGhostChaseAnchor(9.5, anchors, used))
            assert.is_nil(Internals.MatchGhostChaseAnchor(9.5 - 0.01, anchors, used))
            assert.equals(1, Internals.MatchGhostChaseAnchor(17.5, anchors, used))
            assert.is_nil(Internals.MatchGhostChaseAnchor(17.5 + 0.01, anchors, used))
        end)

        it("picks the closest unused overlapping anchor and refuses a second hit on it", function()
            local anchors = { 50, 55 }
            local used = {}
            assert.equals(1, Internals.MatchGhostChaseAnchor(52.4, anchors, used))
            used[1] = true
            assert.equals(2, Internals.MatchGhostChaseAnchor(52.4, anchors, used))
            used[2] = true
            assert.is_nil(Internals.MatchGhostChaseAnchor(52.4, anchors, used))
        end)

        it("breaks an equal-distance overlap toward the earlier unused anchor", function()
            local used = {}
            assert.equals(1, Internals.MatchGhostChaseAnchor(52.5, { 50, 55 }, used))
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

        it("shows a 22-second Callout on a Mythic P2 anchor", function()
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

        it("uses Heroic P2 anchors and consumes each at most once per fight", function()
            StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
            EnterP2()
            Timer.Advance(13)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
            Timer.Advance(37)
            FireValidWarning()
            assert.equals(Timer.GetTime() + Module.GHOST_CHASE_CALLOUT_DURATION, CalloutManager.GetExpiresAt())
            Timer.Advance(45)
            FireValidWarning()
            assert.equals(Timer.GetTime() + Module.GHOST_CHASE_CALLOUT_DURATION, CalloutManager.GetExpiresAt())
        end)

        it("does not treat a Mythic-only elapsed as a Heroic anchor", function()
            StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
            EnterP2()
            Timer.Advance(136)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("matches Mythic P3 from phase elapsed, not pull elapsed", function()
            StartEncounter()
            EnterP3()
            assert.equals("P3", Detector.GetPhase())
            Timer.Advance(62.4)
            FireValidWarning()
            assert.equals(ns.L.COILED_ALTAR_GHOST_CHASE_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("matches Heroic P3 anchors", function()
            StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
            EnterP3()
            Timer.Advance(72.3)
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

        it("ignores warnings on difficulties without a schedule", function()
            StartEncounter(14)
            EnterP2()
            Timer.Advance(12.5)
            FireValidWarning()
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)
end)
