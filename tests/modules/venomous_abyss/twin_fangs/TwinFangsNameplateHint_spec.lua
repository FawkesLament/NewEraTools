local Loader = require("helpers.loader")

describe("TwinFangs nameplate hint casts", function()
    local Module, Encounter, Instance, Nameplate, Spell, Timer, Unit
    local shown
    local hidden
    local cleared

    local function StartEncounter(difficultyID)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", difficultyID or Instance.DIFFICULTY_MYTHIC_RAID, 20)
    end

    local function EndEncounter(difficultyID)
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", difficultyID or Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
    end

    local function AdvanceTo(time)
        Timer.Advance(time - Timer.GetTime())
    end

    local function SetAdd(unit)
        Unit.SetForTests(unit, {
            exists = true,
            guid = "Creature-" .. unit,
            canAssist = false,
            canAttack = true,
            isBossMob = false,
        })
    end

    local function FireStart(unit)
        Spell.FireCastStart(unit, "Cast-1", 1)
    end

    local function FireStop(unit)
        Spell.FireCastStop(unit, "Cast-1", 1)
    end

    before_each(function()
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Encounter = ns.Api.Encounter
        Instance = ns.Api.Instance
        Nameplate = ns.Api.Nameplate
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        Unit = ns.Api.Unit
        shown = {}
        hidden = {}
        cleared = 0
        Module.OnNameplateHintShow = function(_, unit, number)
            shown[#shown + 1] = { unit = unit, number = number }
        end
        Module.OnNameplateHintHide = function(_, unit)
            hidden[#hidden + 1] = unit
        end
        Module.OnNameplateHintCleared = function()
            cleared = cleared + 1
        end
        Module:ListenForEncounter()
        Module:SetNameplateHintEnabled(true)
    end)

    it("listens for add casts for the whole Mythic pull", function()
        assert.is_false(Module:IsListeningForNameplateHint())
        assert.is_false(Spell.HasCastStartListener())

        StartEncounter()
        assert.is_true(Module:IsListeningForNameplateHint())
        assert.is_true(Spell.HasCastStartListener())
        assert.is_true(Spell.HasCastStopListener())

        Module:SetNameplateHintEnabled(false)
        assert.is_true(Module:IsListeningForNameplateHint())
        assert.is_true(Spell.HasCastStartListener())

        EndEncounter()
        assert.is_false(Module:IsListeningForNameplateHint())
        assert.is_false(Spell.HasCastStartListener())
        assert.is_false(Spell.HasCastStopListener())
    end)

    it("does not listen on a non-Mythic pull of this encounter", function()
        SetAdd("nameplate1")
        StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
        assert.is_true(Module:IsInEncounter())
        assert.is_false(Module:IsListeningForNameplateHint())
        assert.is_false(Module:IsListeningForTimeline())
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")
        assert.same({}, shown)
    end)

    it("does not listen for a different encounter", function()
        Encounter.FireStart(1, "Other", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.is_false(Module:IsListeningForNameplateHint())
    end)

    it("assigns the wave index when an add starts casting on an anchor", function()
        SetAdd("nameplate1")
        SetAdd("nameplate2")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1] + 1)
        FireStart("nameplate2")
        assert.same({
            { unit = "nameplate1", number = 1 },
            { unit = "nameplate2", number = 2 },
        }, shown)
    end)

    it("accepts casts at the edges of the 150ms window and rejects the rest", function()
        local window = Module.NAMEPLATE_ANCHOR_WINDOW
        local first = Module.NAMEPLATE_WAVE_STARTS[1]
        local last = first + (Module.NAMEPLATE_ANCHORS_PER_WAVE - 1)
        SetAdd("nameplate1")
        SetAdd("nameplate2")
        SetAdd("nameplate3")
        SetAdd("nameplate4")
        SetAdd("nameplate5")
        StartEncounter()

        AdvanceTo(first - window)
        FireStart("nameplate1")
        AdvanceTo(first + window)
        FireStart("nameplate2")
        AdvanceTo(first + window + 0.001)
        FireStart("nameplate3")
        AdvanceTo(last)
        FireStart("nameplate4")
        AdvanceTo(last + window + 0.001)
        FireStart("nameplate5")

        assert.same({
            { unit = "nameplate1", number = 1 },
            { unit = "nameplate2", number = 1 },
            { unit = "nameplate4", number = 10 },
        }, shown)
    end)

    it("restarts numbering on each wave", function()
        SetAdd("nameplate1")
        SetAdd("nameplate3")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[2])
        FireStart("nameplate1")
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[2] + 3)
        FireStart("nameplate3")
        assert.same({
            { unit = "nameplate1", number = 1 },
            { unit = "nameplate3", number = 4 },
        }, shown)
    end)

    it("ignores casts that are not an add nameplate", function()
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])

        SetAdd("player")
        FireStart("player")

        Unit.SetForTests("nameplate1", {
            exists = true,
            guid = "Creature-boss",
            canAssist = false,
            canAttack = true,
            isBossMob = true,
        })
        FireStart("nameplate1")

        Unit.SetForTests("nameplate2", {
            exists = true,
            guid = "Creature-secret",
            canAssist = false,
            canAttack = true,
        })
        FireStart("nameplate2")

        FireStart({ secret = true })
        assert.same({}, shown)
    end)

    it("removes the badge when that add stops casting", function()
        SetAdd("nameplate1")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")
        FireStop("nameplate1")
        assert.same({ "nameplate1" }, hidden)
    end)

    it("does not remove a badge for a boss or a non-nameplate stop", function()
        SetAdd("nameplate1")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")

        Unit.SetForTests("nameplate1", {
            exists = true,
            guid = "Creature-boss",
            canAssist = false,
            canAttack = true,
            isBossMob = true,
        })
        FireStop("nameplate1")
        FireStop("player")
        assert.same({}, hidden)
    end)

    it("drops a live assignment when that nameplate is recycled", function()
        SetAdd("nameplate1")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")
        Nameplate.FireRemoved("nameplate1")
        Module:ReplayNameplateHints()
        assert.equals(1, #shown)
    end)

    it("clears live badges when the hint turns off or the pull ends", function()
        SetAdd("nameplate1")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")

        Module:SetNameplateHintEnabled(false)
        assert.equals(1, cleared)
        Module:ReplayNameplateHints()
        assert.equals(1, #shown)

        Module:SetNameplateHintEnabled(true)
        FireStart("nameplate1")
        assert.equals(2, #shown)
        EndEncounter()
        assert.equals(2, cleared)
        Module:ReplayNameplateHints()
        assert.equals(2, #shown)
    end)

    it("does not assign a number while the hint is off", function()
        Module:SetNameplateHintEnabled(false)
        SetAdd("nameplate1")
        StartEncounter()
        AdvanceTo(Module.NAMEPLATE_WAVE_STARTS[1])
        FireStart("nameplate1")
        assert.same({}, shown)
    end)
end)
