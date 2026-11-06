local Loader = require("helpers.loader")

describe("CoiledAltar phase detector", function()
    local ns, Module, Detector, Encounter, EncounterTimeline, Spell, Timer

    local function StartEncounter(id)
        Encounter.FireStart(id or Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
    end

    local function EndEncounter()
        Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
    end

    local function EncounterEvent(id, overrides)
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
        return eventInfo
    end

    local function FireEncounterAdded(id, overrides)
        EncounterTimeline.FireEventAdded(EncounterEvent(id, overrides))
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

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Detector = ns.Modules.Internals("CoiledAltar").PhaseDetector
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        Module:ListenForEncounter()
    end)

    it("returns nil before an encounter starts", function()
        assert.is_nil(Detector.GetPhase())
        assert.is_nil(Detector.GetPhaseStartTime())
        assert.is_nil(Detector.GetPhaseElapsed())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
        assert.is_false(Spell.HasChannelStartListener("boss2"))
    end)

    it("initializes P1 and its start timestamp on encounter start", function()
        Timer.Advance(12)
        local startedAt = Timer.GetTime()
        StartEncounter()
        assert.equals("P1", Detector.GetPhase())
        assert.equals(startedAt, Detector.GetPhaseStartTime())
        Timer.Advance(3)
        assert.equals(3, Detector.GetPhaseElapsed())
        assert.is_true(EncounterTimeline.HasEventAddedListener())
        assert.is_true(Spell.HasChannelStartListener("boss2"))
    end)

    it("does not enter P2 from a 70-second timeline event in the first 5 seconds", function()
        StartEncounter()
        local p1Start = Detector.GetPhaseStartTime()
        Timer.Advance(4.9)
        FireEncounterAdded(1, { duration = 70 })
        assert.equals("P1", Detector.GetPhase())
        assert.equals(p1Start, Detector.GetPhaseStartTime())
    end)

    it("enters P2 from a qualifying 70-second event after 5 seconds", function()
        StartEncounter()
        Timer.Advance(5)
        local p2Start = Timer.GetTime()
        FireEncounterAdded(2, { duration = 70 })
        assert.equals("P2", Detector.GetPhase())
        assert.equals(p2Start, Detector.GetPhaseStartTime())
        Timer.Advance(2)
        assert.equals(2, Detector.GetPhaseElapsed())
    end)

    it("ignores timeline events from non-Encounter sources", function()
        StartEncounter()
        Timer.Advance(5)
        local p1Start = Detector.GetPhaseStartTime()
        FireEncounterAdded(3, {
            duration = 70,
            source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER + 1,
        })
        assert.equals("P1", Detector.GetPhase())
        assert.equals(p1Start, Detector.GetPhaseStartTime())

        EnterI2()
        for id = 4, 7 do
            FireEncounterAdded(id, { source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER + 1 })
        end
        assert.equals("I2", Detector.GetPhase())
    end)

    it("enters I2 on boss2 channel start only when no Encounter timeline is Active", function()
        StartEncounter()
        EnterP2()
        local p2Start = Detector.GetPhaseStartTime()
        local active = EncounterEvent(8)
        EncounterTimeline.SetEventsForTests({ active })
        EncounterTimeline.SetEventStateForTests(active.id, EncounterTimeline.EVENT_STATE_ACTIVE)
        Spell.FireChannelStart("boss1")
        Spell.FireChannelStart("boss2")
        assert.equals("P2", Detector.GetPhase())
        assert.equals(p2Start, Detector.GetPhaseStartTime())

        EncounterTimeline.SetEventsForTests(nil)
        Spell.FireChannelStart("boss2")
        assert.equals("I2", Detector.GetPhase())
    end)

    it("does not let inactive timeline states block P2 to I2", function()
        StartEncounter()
        EnterP2()
        local inactiveEncounter = EncounterEvent(9)
        local activeOther = EncounterEvent(10, { source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER + 1 })
        EncounterTimeline.SetEventsForTests({ inactiveEncounter, activeOther })
        EncounterTimeline.SetEventStateForTests(inactiveEncounter.id, EncounterTimeline.EVENT_STATE_ACTIVE + 1)
        EncounterTimeline.SetEventStateForTests(activeOther.id, EncounterTimeline.EVENT_STATE_ACTIVE)
        local i2Start = Timer.GetTime()
        Spell.FireChannelStart("boss2")
        assert.equals("I2", Detector.GetPhase())
        assert.equals(i2Start, Detector.GetPhaseStartTime())
    end)

    it("notifies OnChanged with the P3 start timestamp used by GetPhaseStartTime", function()
        StartEncounter()
        EnterI2()
        local seen = {}
        local stop = Detector.OnChanged(function(phase, at)
            seen[#seen + 1] = { phase = phase, at = at }
        end)
        FireEncounterAdded(11)
        Timer.Advance(0.003)
        FireEncounterAdded(12)
        Timer.Advance(0.003)
        FireEncounterAdded(13)
        Timer.Advance(0.003)
        FireEncounterAdded(14)
        stop()
        assert.equals(1, #seen)
        assert.equals("P3", seen[1].phase)
        assert.equals(Detector.GetPhaseStartTime(), seen[1].at)
    end)

    it("enters P3 when four Encounter-sourced events arrive within 10ms", function()
        StartEncounter()
        EnterI2()
        FireEncounterAdded(11)
        Timer.Advance(0.003)
        FireEncounterAdded(12, { spellID = 12345 })
        Timer.Advance(0.003)
        FireEncounterAdded(13, { spellID = 12345 })
        Timer.Advance(0.003)
        local p3Start = Timer.GetTime()
        FireEncounterAdded(14, { spellID = 12345 })
        assert.equals("P3", Detector.GetPhase())
        assert.equals(p3Start, Detector.GetPhaseStartTime())
        Timer.Advance(1)
        assert.equals(1, Detector.GetPhaseElapsed())
    end)

    it("does not enter P3 from three eligible events", function()
        StartEncounter()
        EnterI2()
        local i2Start = Detector.GetPhaseStartTime()
        FireEncounterAdded(15)
        FireEncounterAdded(16)
        FireEncounterAdded(17)
        assert.equals("I2", Detector.GetPhase())
        assert.equals(i2Start, Detector.GetPhaseStartTime())
    end)

    it("does not accumulate events more than 10ms after the batch start", function()
        StartEncounter()
        EnterI2()
        FireEncounterAdded(18)
        Timer.Advance(0.005)
        FireEncounterAdded(19)
        Timer.Advance(0.006)
        FireEncounterAdded(20)
        FireEncounterAdded(21)
        FireEncounterAdded(22)
        assert.equals("I2", Detector.GetPhase())
    end)

    it("starts a new batch after the 10ms window expires", function()
        StartEncounter()
        EnterI2()
        FireEncounterAdded(23)
        FireEncounterAdded(24)
        FireEncounterAdded(25)
        Timer.Advance(0.011)
        FireEncounterAdded(26)
        Timer.Advance(0.002)
        FireEncounterAdded(27)
        FireEncounterAdded(28)
        local p3Start = Timer.GetTime()
        FireEncounterAdded(29)
        assert.equals("P3", Detector.GetPhase())
        assert.equals(p3Start, Detector.GetPhaseStartTime())
    end)

    it("clears all phase state when the encounter ends", function()
        StartEncounter()
        EnterI2()
        EndEncounter()
        assert.is_nil(Detector.GetPhase())
        assert.is_nil(Detector.GetPhaseStartTime())
        assert.is_nil(Detector.GetPhaseElapsed())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
        assert.is_false(Spell.HasChannelStartListener("boss2"))

        FireEncounterAdded(30, { duration = 70 })
        Spell.FireChannelStart("boss2")
        assert.is_nil(Detector.GetPhase())

        local startedAt = Timer.GetTime()
        StartEncounter()
        assert.equals("P1", Detector.GetPhase())
        assert.equals(startedAt, Detector.GetPhaseStartTime())
        EndEncounter()
        assert.is_nil(Detector.GetPhase())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
    end)

    it("ignores duplicate and out-of-order transitions", function()
        StartEncounter()
        local p1Start = Detector.GetPhaseStartTime()
        Spell.FireChannelStart("boss2")
        FireEncounterAdded(31)
        FireEncounterAdded(32)
        FireEncounterAdded(33)
        FireEncounterAdded(34)
        assert.equals("P1", Detector.GetPhase())
        assert.equals(p1Start, Detector.GetPhaseStartTime())

        EnterP2()
        local p2Start = Detector.GetPhaseStartTime()
        Timer.Advance(5)
        FireEncounterAdded(35, { duration = 70 })
        assert.equals("P2", Detector.GetPhase())
        assert.equals(p2Start, Detector.GetPhaseStartTime())

        Spell.FireChannelStart("boss2")
        local i2Start = Detector.GetPhaseStartTime()
        Spell.FireChannelStart("boss2")
        FireEncounterAdded(36, { duration = 70 })
        assert.equals("I2", Detector.GetPhase())
        assert.equals(i2Start, Detector.GetPhaseStartTime())

        FireEncounterAdded(37)
        FireEncounterAdded(38)
        FireEncounterAdded(39)
        FireEncounterAdded(40)
        local p3Start = Detector.GetPhaseStartTime()
        FireEncounterAdded(41, { duration = 70 })
        Spell.FireChannelStart("boss2")
        FireEncounterAdded(42)
        FireEncounterAdded(43)
        FireEncounterAdded(44)
        FireEncounterAdded(45)
        assert.equals("P3", Detector.GetPhase())
        assert.equals(p3Start, Detector.GetPhaseStartTime())
    end)

    it("does not start for a different encounter", function()
        StartEncounter(1)
        assert.is_nil(Detector.GetPhase())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
    end)
end)
