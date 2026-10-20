local Loader = require("helpers.loader")

describe("TwinFangs interrupt reminder", function()
    local ns, Module, Encounter, EncounterTimeline, Instance, Timer, Speech
    local nextEventId

    local function ActiveEvent(duration, overrides)
        local eventInfo = {
            id = nextEventId,
            source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER,
            duration = duration,
        }
        nextEventId = nextEventId + 1
        if overrides then
            for key, value in pairs(overrides) do
                eventInfo[key] = value
            end
        end
        EncounterTimeline.SetEventStateForTests(eventInfo.id, EncounterTimeline.EVENT_STATE_ACTIVE)
        return eventInfo
    end

    local function StartMythic()
        Module:SetInterruptReminderEnabled(true)
        Module:SetInterruptVoiceEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
    end

    local function FireCycleBars(count)
        for _ = 1, count do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        end
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Instance = ns.Api.Instance
        Timer = ns.Api.Timer
        Speech = ns.Api.Speech
        nextEventId = 1
        Module:ListenForEncounter()
    end)

    it("saves the voice option off", function()
        assert.is_false(Module:IsInterruptVoiceEnabled())
        Module:SetInterruptVoiceEnabled(true)
        assert.is_true(Module:IsInterruptVoiceEnabled())
        assert.is_true(Module.db.interruptReminder.voice)
        Module:SetInterruptVoiceEnabled(false)
        assert.is_false(Module.db.interruptReminder.voice)
    end)

    it("speaks after the 5th ~61s bar's duration", function()
        StartMythic()
        FireCycleBars(Module.BROOD_SLOT - 1)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({}, Speech.spoken)

        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        Timer.Advance(Module.CYCLE_DURATION - 0.01)
        assert.same({}, Speech.spoken)
        Timer.Advance(0.01)
        assert.same({ ns.L.TWIN_FANGS_INTERRUPT_PREPARE }, Speech.spoken)
    end)

    it("speaks again on the 5th bar of the next cycle", function()
        StartMythic()
        FireCycleBars(Module.CYCLE_LENGTH + Module.BROOD_SLOT)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({
            ns.L.TWIN_FANGS_INTERRUPT_PREPARE,
            ns.L.TWIN_FANGS_INTERRUPT_PREPARE,
        }, Speech.spoken)
    end)

    it("does not speak for the feast bar or a ~57s bar", function()
        StartMythic()
        FireCycleBars(Module.CYCLE_LENGTH)
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({ ns.L.TWIN_FANGS_INTERRUPT_PREPARE }, Speech.spoken)
    end)

    it("does not let a ~57s bar consume a slot in the cycle", function()
        StartMythic()
        FireCycleBars(Module.BROOD_SLOT - 1)
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        Timer.Advance(Module.FEAST_DURATION)
        assert.same({}, Speech.spoken)

        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({ ns.L.TWIN_FANGS_INTERRUPT_PREPARE }, Speech.spoken)
    end)

    it("resets the cycle when the next pull starts", function()
        StartMythic()
        FireCycleBars(Module.BROOD_SLOT - 1)
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({}, Speech.spoken)

        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        FireCycleBars(Module.BROOD_SLOT)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({ ns.L.TWIN_FANGS_INTERRUPT_PREPARE }, Speech.spoken)
    end)

    it("stays quiet unless the reminder and the voice option are both on", function()
        Module:SetInterruptVoiceEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        FireCycleBars(Module.BROOD_SLOT)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({}, Speech.spoken)

        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        Module:SetInterruptReminderEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        FireCycleBars(Module.BROOD_SLOT)
        Module:SetInterruptVoiceEnabled(false)
        Timer.Advance(Module.CYCLE_DURATION)
        assert.same({}, Speech.spoken)
    end)
end)
