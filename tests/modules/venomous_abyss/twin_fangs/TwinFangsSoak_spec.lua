local Loader = require("helpers.loader")

describe("TwinFangs soak reminder", function()
    local ns, Module, Schema, Encounter, EncounterTimeline, Instance, Timer
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
        Module:SetSoakReminderEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
    end

    local function HitTimes(duration)
        local hit1 = duration + Module.CAST_SECONDS
        local hit2 = hit1 + Module.HIT2_GAP
        local hit3 = hit2 + Module.HIT3_GAP
        return hit1, hit2, hit3
    end

    local function AdvanceToFirstHitReminder(duration)
        Timer.Advance(duration + Module.CAST_SECONDS - Module.HIT1_LEAD)
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Schema = ns.Modules.Internals("TwinFangs").Schema
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Instance = ns.Api.Instance
        Timer = ns.Api.Timer
        nextEventId = 1
        Module:ListenForEncounter()
    end)

    it("shows the first-hit reminder 7 seconds before the hit", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        local duration = Module.FEAST_DURATION
        EncounterTimeline.FireEventAdded(ActiveEvent(duration))

        local hit1 = HitTimes(duration)
        Timer.Advance(hit1 - Module.HIT1_LEAD - 0.01)
        assert.equals(nil, Module:GetDisplayedCallout())
        Timer.Advance(0.01)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
        assert.equals(hit1, Module:GetCalloutExpiresAt())

        Timer.Advance(Module.HIT1_LEAD)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("warns the second hit before the first, then sends them in", function()
        Module:SetSoakGroup(Schema.GROUP_LEFT)
        StartMythic()
        local duration = Module.FEAST_DURATION
        local hit1, hit2 = HitTimes(duration)
        EncounterTimeline.FireEventAdded(ActiveEvent(duration))
        assert.equals(nil, Module:GetDisplayedCallout())

        Timer.Advance(hit1 - Module.PREPARE_LEAD - 0.01)
        assert.equals(nil, Module:GetDisplayedCallout())
        Timer.Advance(0.01)
        assert.equals(ns.L.TWIN_FANGS_SOAK_PREPARE, Module:GetDisplayedCallout())
        assert.equals(hit1, Module:GetCalloutExpiresAt())

        Timer.Advance(Module.PREPARE_LEAD)
        assert.equals(ns.L.TWIN_FANGS_SOAK_NOW, Module:GetDisplayedCallout())
        assert.equals(hit2, Module:GetCalloutExpiresAt())

        Timer.Advance(hit2 - hit1)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("warns the third hit before the second, then sends them in", function()
        Module:SetSoakGroup(Schema.GROUP_MIDDLE)
        StartMythic()
        local duration = Module.FEAST_DURATION
        local _, hit2, hit3 = HitTimes(duration)
        EncounterTimeline.FireEventAdded(ActiveEvent(duration))

        Timer.Advance(hit2 - Module.PREPARE_LEAD)
        assert.equals(ns.L.TWIN_FANGS_SOAK_PREPARE, Module:GetDisplayedCallout())
        assert.equals(hit2, Module:GetCalloutExpiresAt())

        Timer.Advance(Module.PREPARE_LEAD)
        assert.equals(ns.L.TWIN_FANGS_SOAK_NOW, Module:GetDisplayedCallout())
        assert.equals(hit3, Module:GetCalloutExpiresAt())

        Timer.Advance(hit3 - hit2)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("swaps the first two groups on the 3rd and 4th casts", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        for feast = 1, 6 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
            AdvanceToFirstHitReminder(Module.FEAST_DURATION)
            local shown = Module:GetDisplayedCallout()
            if feast == 3 or feast == 4 then
                assert.equals(ns.L.TWIN_FANGS_SOAK_PREPARE, shown)
            else
                assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, shown)
            end
            Timer.Advance(80)
            assert.equals(nil, Module:GetDisplayedCallout())
        end
    end)

    it("treats every 8th ~61s bar as the next feast and ignores the ones between", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            assert.equals(nil, Module:GetDisplayedCallout())
        end
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        AdvanceToFirstHitReminder(Module.CYCLE_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
    end)

    it("does not let a ~57s feast consume the ~61s count", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        AdvanceToFirstHitReminder(Module.FEAST_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
        Timer.Advance(80)

        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            assert.equals(nil, Module:GetDisplayedCallout())
        end
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        AdvanceToFirstHitReminder(Module.CYCLE_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
    end)

    it("resets the feast and ~61s counts when the next pull starts", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        end
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)

        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            assert.equals(nil, Module:GetDisplayedCallout())
        end
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        AdvanceToFirstHitReminder(Module.CYCLE_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
    end)

    it("ignores bars that are not an active encounter event", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION, { source = 1 }))
        local inactive = ActiveEvent(Module.FEAST_DURATION)
        EncounterTimeline.SetEventStateForTests(inactive.id, 2)
        EncounterTimeline.FireEventAdded(inactive)
        EncounterTimeline.FireEventAdded(ActiveEvent(45))
        assert.equals(nil, Module:GetDisplayedCallout())

        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION, { source = 1 }))
        end
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("stays quiet while the soak reminder is off and clears when it is turned off", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        AdvanceToFirstHitReminder(Module.FEAST_DURATION)
        assert.equals(nil, Module:GetDisplayedCallout())

        Module:SetSoakReminderEnabled(true)
        for _ = 1, Module.CYCLE_LENGTH - 1 do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        end
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        AdvanceToFirstHitReminder(Module.CYCLE_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())

        Module:SetSoakReminderEnabled(false)
        assert.equals(nil, Module:GetDisplayedCallout())
        Timer.Advance(80)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("clears the reminder when the pull ends", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        AdvanceToFirstHitReminder(Module.FEAST_DURATION)
        assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)

    it("does not carry a pending reminder into the next pull", function()
        Module:SetSoakGroup(Schema.GROUP_RIGHT)
        StartMythic()
        EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
        Timer.Advance(10)
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Timer.Advance(80)
        assert.equals(nil, Module:GetDisplayedCallout())
    end)
end)
