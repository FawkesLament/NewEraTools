local Loader = require("helpers.loader")

describe("CoiledAltar interrupt tracker", function()
    local ns, Module, Tracker, Encounter, Nameplate, RaidTarget, Spell, Timer, Unit

    local function AssignChain()
        assert.is_true(Module:AssignInterruptPlayer("MELEE", 1, "PlayerA"))
    end

    local function SetBossCount(count)
        for i = 3, 8 do
            Unit.SetForTests("boss" .. i, { exists = i < 3 + count })
        end
    end

    local function SetPlate(unit, level)
        Unit.SetForTests(unit, { exists = true, level = level or 92 })
    end

    local function Mark(unit, marked)
        RaidTarget.indices[unit] = marked and 1 or nil
    end

    ---@return CoiledAltarInterruptState
    local function NewState()
        return Tracker.New()
    end

    local function Spawn(state, count)
        SetBossCount(count)
        Tracker.OnEngage(state)
        Tracker.Flush(state)
    end

    local function Cast(state, kind, unit, hasCastGUID, hasArg3)
        local guidPresent = hasCastGUID ~= false
        local arg3Present = hasArg3 ~= false
        Tracker.OnCast(state, kind, unit, guidPresent, arg3Present)
    end

    -- Shadows are cyclic (wave.members), so assert.equals would overflow Format.
    local function Same(expected, actual, message)
        assert(expected == actual, message or "expected the same object")
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Tracker = ns.Modules.Internals("CoiledAltar").InterruptTracker
        Encounter = ns.Api.Encounter
        Nameplate = ns.Api.Nameplate
        RaidTarget = ns.Api.RaidTarget
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        Unit = ns.Api.Unit
    end)

    describe("encounter activation", function()
        local function StartEncounter(id)
            Encounter.FireStart(id or Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        end

        local function EndEncounter()
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
        end

        local function Listening()
            return Spell.HasCastStartListener()
                and Spell.HasCastStopListener()
                and Spell.HasCastInterruptedListener()
                and Spell.HasCastSucceededListener()
        end

        it("starts tracking encounter 3429 when interrupt chains are configured", function()
            AssignChain()
            Module:ListenForEncounter()
            assert.is_nil(Tracker.Get())
            assert.is_false(Listening())

            StartEncounter()
            assert.equals("table", type(Tracker.Get()))
            assert.is_true(Listening())
            assert.equals(0, #Tracker.Get().list)
        end)

        it("does not start tracking encounter 3429 when interrupt chains are empty", function()
            Module:ListenForEncounter()
            StartEncounter()
            assert.is_nil(Tracker.Get())
            assert.is_false(Spell.HasCastStartListener())
            assert.is_false(Spell.HasCastInterruptedListener())
        end)

        it("does not start tracking a different encounter", function()
            AssignChain()
            Module:ListenForEncounter()
            StartEncounter(1)
            assert.is_nil(Tracker.Get())
            assert.is_false(Spell.HasCastStartListener())
        end)

        it("unregisters listeners and discards state when the encounter ends", function()
            AssignChain()
            Module:ListenForEncounter()
            StartEncounter()
            SetBossCount(2)
            Encounter.FireEngageUnit()
            Timer.Advance(0)
            assert.equals(2, #Tracker.Get().list)

            EndEncounter()
            assert.is_nil(Tracker.Get())
            assert.is_false(Listening())
            assert.equals(0, #RaidTarget.changedCallbacks)
            assert.equals(0, #Nameplate.removed)
        end)

        it("invalidates a pending flush when the encounter ends", function()
            AssignChain()
            Module:ListenForEncounter()
            StartEncounter()
            SetBossCount(2)
            Encounter.FireEngageUnit()
            EndEncounter()
            Timer.Advance(0)
            assert.is_nil(Tracker.Get())
            assert.is_false(Spell.HasCastStartListener())
        end)
    end)

    describe("combat state", function()
        it("creates one wave of two shadows on the initial spawn", function()
            local state = NewState()
            assert.equals(0, #state.list)
            Mark("boss3", true)
            Mark("boss4", false)
            Spawn(state, 2)

            assert.equals(2, #state.list)
            Same(state.list[1].wave, state.list[2].wave, "both shadows belong to the same wave")
            Same(state.curWave, state.list[1].wave, "curWave is the spawned wave")
            assert.equals(2, #state.curWave.members)
            Same(state.list[1], state.curWave.members[1], "first member is list[1]")
            Same(state.list[2], state.curWave.members[2], "second member is list[2]")
            assert.equals(0, state.list[1].kicks)
            assert.equals(0, state.list[2].kicks)
            assert.is_false(state.list[1].casting)
            assert.is_false(state.list[2].casting)
            assert.is_false(state.list[1].expired)
            assert.is_false(state.list[2].expired)
            assert.is_true(state.list[1].marked)
            assert.is_false(state.list[2].marked)
            assert.is_nil(state.list[1].plate)
            assert.is_nil(state.list[2].plate)
        end)

        it("applies START to casting without inventing a nameplate bind", function()
            local state = NewState()
            Spawn(state, 2)
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "boss4", true)
            Cast(state, "START", "boss3", false)
            Cast(state, "START", "boss4", false)
            Tracker.Flush(state)

            assert.is_true(state.list[1].casting)
            assert.is_true(state.list[2].casting)
            assert.equals(0, state.list[1].kicks)
            assert.equals(0, state.list[2].kicks)
            assert.is_nil(state.list[1].plate)
            assert.is_nil(state.list[2].plate)
            assert.is_nil(next(state.plateOwner))
        end)

        it("increments kicks only from a boss-token INTERRUPTED", function()
            local state = NewState()
            Spawn(state, 2)
            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)
            assert.equals("nameplate1", state.list[1].plate)

            Cast(state, "INTERRUPTED", "boss3", true, true)
            Cast(state, "INTERRUPTED", "nameplate1", true, true)
            Cast(state, "STOP", "boss3", true, true)
            Tracker.Flush(state)

            assert.equals(1, state.list[1].kicks)
            assert.equals(0, state.list[2].kicks)
            assert.is_false(state.list[1].casting)
            assert.equals("nameplate1", state.list[1].plate)
        end)

        it("identifies a death from a nil nameplate INTERRUPTED captured before unbind", function()
            local state = NewState()
            Spawn(state, 2)
            local first = state.list[1]
            local second = state.list[2]
            first.kicks = 2
            second.kicks = 3
            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)
            Same(first, state.plateOwner.nameplate1)

            SetBossCount(1)
            Tracker.OnEngage(state)
            Cast(state, "INTERRUPTED", "nameplate1", false, false)
            Cast(state, "STOP", "boss3", true, true)
            Tracker.OnNameplateRemoved(state, "nameplate1")
            assert.is_nil(first.plate)
            assert.is_nil(state.plateOwner.nameplate1)
            Tracker.Flush(state)

            assert.equals(1, #state.list)
            Same(second, state.list[1])
            assert.equals(3, second.kicks)
            assert.equals(2, first.kicks)
            Same(first, first.wave.members[1])
            Same(second, first.wave.members[2])
            assert.is_nil(state.plateOwner.nameplate1)
        end)

        it("identifies a death from a same-frame nameplate REMOVED", function()
            local state = NewState()
            Spawn(state, 2)
            local first = state.list[1]
            local second = state.list[2]
            first.kicks = 1
            second.kicks = 4
            Mark("boss3", true)
            Mark("boss4", false)
            Tracker.OnRaidTargetChanged(state)
            SetPlate("nameplate2")
            Cast(state, "START", "boss4", true)
            Cast(state, "START", "nameplate2", true)
            Tracker.Flush(state)
            Same(second, state.plateOwner.nameplate2)

            SetBossCount(1)
            Mark("boss3", true)
            Tracker.OnEngage(state)
            Tracker.OnNameplateRemoved(state, "nameplate2")
            Tracker.Flush(state)

            assert.equals(1, #state.list)
            Same(first, state.list[1])
            assert.equals(1, first.kicks)
            assert.equals(4, second.kicks)
            assert.is_true(first.marked)
            assert.is_false(second.marked)
            Same(second, first.wave.members[2])
            local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
            assert.is_true(w1)
            assert.is_false(w2)
        end)

        it("keeps identity and kicks when a death shifts boss tokens", function()
            local state = NewState()
            Spawn(state, 2)
            local first = state.list[1]
            local second = state.list[2]
            Cast(state, "INTERRUPTED", "boss3", true, true)
            Cast(state, "INTERRUPTED", "boss3", true, true)
            Cast(state, "INTERRUPTED", "boss4", true, true)
            Cast(state, "INTERRUPTED", "boss4", true, true)
            Cast(state, "INTERRUPTED", "boss4", true, true)
            Tracker.Flush(state)
            assert.equals(2, first.kicks)
            assert.equals(3, second.kicks)

            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)

            SetBossCount(1)
            Tracker.OnEngage(state)
            Cast(state, "INTERRUPTED", "nameplate1", false, false)
            Tracker.OnNameplateRemoved(state, "nameplate1")
            Tracker.Flush(state)

            assert.equals(1, #state.list)
            Same(second, state.list[1])
            assert.equals(3, state.list[1].kicks)
        end)

        it("freezes a dead member's marker so melee identity stays knowable", function()
            local state = NewState()
            Mark("boss3", true)
            Mark("boss4", false)
            Spawn(state, 2)
            local first = state.list[1]
            local second = state.list[2]
            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)

            SetBossCount(1)
            Mark("boss3", false)
            Tracker.OnEngage(state)
            Tracker.OnNameplateRemoved(state, "nameplate1")
            Tracker.Flush(state)

            Same(second, state.list[1])
            assert.is_true(first.marked)
            assert.is_false(second.marked)
            local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
            assert.is_true(w1)
            assert.is_false(w2)
            Mark("boss3", true)
            Tracker.OnRaidTargetChanged(state)
            assert.is_true(first.marked)
            assert.is_true(second.marked)

            Mark("boss3", true)
            Mark("boss4", true)
            local both = NewState()
            Spawn(both, 2)
            w1, w2 = Tracker.GetPossibleWorlds(both.curWave)
            assert.is_true(w1)
            assert.is_true(w2)

            Mark("boss3", false)
            Mark("boss4", false)
            local unmarked = NewState()
            Spawn(unmarked, 2)
            w1, w2 = Tracker.GetPossibleWorlds(unmarked.curWave)
            assert.is_true(w1)
            assert.is_true(w2)

            Mark("boss3", false)
            Mark("boss4", true)
            local rangedFirst = NewState()
            Spawn(rangedFirst, 2)
            w1, w2 = Tracker.GetPossibleWorlds(rangedFirst.curWave)
            assert.is_false(w1)
            assert.is_true(w2)
        end)

        it("starts a new wave on top of a surviving expired shadow", function()
            local state = NewState()
            Spawn(state, 2)
            local oldA = state.list[1]
            local oldB = state.list[2]
            oldA.kicks = 5
            oldB.kicks = 2
            SetPlate("nameplate1")
            Cast(state, "START", "boss4", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)

            SetBossCount(1)
            Tracker.OnEngage(state)
            Tracker.OnNameplateRemoved(state, "nameplate1")
            Tracker.Flush(state)
            Same(oldA, state.list[1])

            SetBossCount(3)
            Tracker.OnEngage(state)
            Tracker.Flush(state)

            assert.equals(3, #state.list)
            Same(oldA, state.list[1])
            assert.is_true(oldA.expired)
            assert.equals(5, oldA.kicks)
            assert.equals(2, oldB.kicks)
            local newA = state.list[2]
            local newB = state.list[3]
            assert(oldA.wave ~= newA.wave, "expected a new wave")
            Same(state.curWave, newA.wave)
            Same(newA, state.curWave.members[1])
            Same(newB, state.curWave.members[2])
            assert.equals(0, newA.kicks)
            assert.equals(0, newB.kicks)
            assert.is_false(newA.expired)
            assert.is_false(newB.casting)
            Same(oldA, oldA.wave.members[1])

            Cast(state, "INTERRUPTED", "boss3", true, true)
            Tracker.Flush(state)
            assert.equals(6, oldA.kicks)
            assert.equals(0, newA.kicks)
        end)

        it("does not inherit a stale nameplate binding after REMOVED", function()
            local state = NewState()
            Spawn(state, 2)
            local first = state.list[1]
            local second = state.list[2]
            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)
            Same(first, state.plateOwner.nameplate1)

            Tracker.OnNameplateRemoved(state, "nameplate1")
            Tracker.Flush(state)
            assert.is_nil(first.plate)
            assert.is_nil(state.plateOwner.nameplate1)

            Cast(state, "START", "boss4", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)
            Same(second, state.plateOwner.nameplate1)
            assert.equals("nameplate1", second.plate)
            assert.is_nil(first.plate)
        end)

        it("ignores a nameplate disappearance that is not an ENGAGE death", function()
            local state = NewState()
            Spawn(state, 2)
            local first = state.list[1]
            SetPlate("nameplate1")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)

            Tracker.OnNameplateRemoved(state, "nameplate1")
            Tracker.Flush(state)
            assert.equals(2, #state.list)
            Same(first, state.list[1])
            assert.is_nil(first.plate)
        end)

        it("does not pair ambiguous same-frame START events", function()
            local state = NewState()
            Spawn(state, 2)
            SetPlate("nameplate1")
            SetPlate("nameplate2")
            Cast(state, "START", "boss3", true)
            Cast(state, "START", "boss4", true)
            Cast(state, "START", "nameplate1", true)
            Cast(state, "START", "nameplate2", true)
            Tracker.Flush(state)
            assert.is_nil(state.list[1].plate)
            assert.is_nil(state.list[2].plate)
        end)

        it("does not count SUCCEEDED as an interrupt", function()
            local state = NewState()
            Spawn(state, 2)
            Cast(state, "START", "boss3", true)
            Cast(state, "SUCCEEDED", "boss3", true, true)
            Tracker.Flush(state)
            assert.is_false(state.list[1].casting)
            assert.equals(0, state.list[1].kicks)
        end)
    end)
end)
