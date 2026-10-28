local Loader = require("helpers.loader")

describe("TwinFangs encounter", function()
    local ns, Module, Encounter, EncounterTimeline, Instance

    before_each(function()
        ns = Loader.Load()
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

    it("does not accumulate timeline listeners across Mythic pulls", function()
        local function TimelineListenerCount()
            local list = ns.Api.GameEvents.handlers["ENCOUNTER_TIMELINE_EVENT_ADDED"]
            return list and #list or 0
        end

        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.equals(1, TimelineListenerCount())
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        assert.equals(0, TimelineListenerCount())
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.equals(1, TimelineListenerCount())
        assert.is_true(Module:IsListeningForTimeline())
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        assert.equals(0, TimelineListenerCount())
        assert.is_false(Module:IsListeningForTimeline())
    end)

    it("releases every pull listener across repeated Mythic pulls", function()
        local function GameEventListenerCount()
            local total = 0
            for _, list in pairs(ns.Api.GameEvents.handlers) do
                total = total + #list
            end
            return total
        end

        local idle = GameEventListenerCount()
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        local active = GameEventListenerCount()
        assert.is_true(active > idle)
        assert.is_true(ns.Api.Spell.HasCastStopListener())

        for _ = 1, 2 do
            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            assert.equals(idle, GameEventListenerCount())
            assert.is_false(ns.Api.Spell.HasCastStopListener())
            assert.is_false(Module:IsListeningForNameplateHint())
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            assert.equals(active, GameEventListenerCount())
            assert.is_true(Module:IsListeningForNameplateHint())
        end

        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_HEROIC_RAID, 20)
        assert.equals(idle, GameEventListenerCount())
        assert.is_false(Module:IsListeningForTimeline())
    end)
end)
