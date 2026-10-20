local Loader = require("helpers.loader")

describe("TwinFangs encounter", function()
    local Module, Encounter, EncounterTimeline, Instance

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Instance = ns.Api.Instance
        Module:ListenForEncounter()
    end)

    it("tracks only encounter 3421", function()
        Encounter.FireStart(1, "Other", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_false(Module:IsInEncounter())

        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_true(Module:IsInEncounter())

        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        assert.is_false(Module:IsInEncounter())
    end)

    it("listens for timeline events only during a Mythic pull", function()
        assert.is_false(Module:IsListeningForTimeline())
        assert.is_false(EncounterTimeline.HasEventAddedListener())

        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_HEROIC_RAID, 20)
        assert.is_true(Module:IsInEncounter())
        assert.is_false(Module:IsListeningForTimeline())
        assert.is_false(EncounterTimeline.HasEventAddedListener())

        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_HEROIC_RAID, 20, 1)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_true(Module:IsListeningForTimeline())
        assert.is_true(EncounterTimeline.HasEventAddedListener())
    end)

    it("stops listening when the Mythic pull ends", function()
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_true(Module:IsListeningForTimeline())

        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        assert.is_false(Module:IsInEncounter())
        assert.is_false(Module:IsListeningForTimeline())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
    end)

    it("does not listen for a different encounter on Mythic", function()
        Encounter.FireStart(1, "Other", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_false(Module:IsListeningForTimeline())
        assert.is_false(EncounterTimeline.HasEventAddedListener())
    end)
end)
