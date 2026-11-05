local Loader = require("helpers.loader")
local Replay = require("helpers.replay")

describe("CoiledAltar nameplate interrupt indicators", function()
    local ns, Module, Internals, Tracker, L, RaidTarget, Unit
    local SECRET_MARK = {}

    local function Pending()
        return L.COILED_ALTAR_INTERRUPT_INDICATOR_PENDING
    end

    local function SetBossCount(count)
        for i = 3, 8 do
            Unit.SetForTests("boss" .. i, { exists = i < 3 + count })
        end
    end

    local function Mark(unit, marked)
        RaidTarget.indices[unit] = marked and SECRET_MARK or nil
    end

    local function Spawn(state, count)
        SetBossCount(count)
        Tracker.OnEngage(state)
        Tracker.Flush(state)
    end

    local function Cast(state, kind, unit, hasCastGUID, hasArg3)
        Tracker.OnCast(state, kind, unit, hasCastGUID ~= false, hasArg3 ~= false)
    end

    local function AddPlate(state, unit, marked)
        Unit.SetForTests(unit, { exists = true, level = 92 })
        Mark(unit, marked == true)
        Tracker.OnNameplateAdded(state, unit)
    end

    local function Shadow(wave, fields)
        local object = {
            wave = wave,
            expired = false,
            marked = false,
            kicks = 0,
            casting = false,
            plate = nil,
        }
        for key, value in pairs(fields or {}) do
            object[key] = value
        end
        return object
    end

    local function WaveState(firstFields, secondFields, live)
        local wave = { members = {} }
        local first = Shadow(wave, firstFields)
        local second = Shadow(wave, secondFields)
        wave.members = { first, second }
        local list = live
        if not list then
            list = { first, second }
        end
        local plateOwner = {}
        if first.plate then
            plateOwner[first.plate] = first
        end
        if second.plate then
            plateOwner[second.plate] = second
        end
        return {
            list = list,
            plateOwner = plateOwner,
            candidates = {},
            curWave = wave,
            disposed = false,
        }, first, second, wave
    end

    local function Resolve(state)
        return Internals.ResolveNameplateIndicators(state, Module:GetInterruptAssignments())
    end

    local function Assign(chainId, index, name)
        assert.is_true(Module:AssignInterruptPlayer(chainId, index, name))
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Internals = ns.Modules.Internals("CoiledAltar")
        Tracker = Internals.InterruptStates
        L = ns.L
        RaidTarget = ns.Api.RaidTarget
        Unit = ns.Api.Unit
        Assign("MELEE", 1, "MeleeOne")
        Assign("RANGED", 1, "RangeOne")
        Assign("MELEE", 2, "MeleeTwo")
        Assign("RANGED", 2, "RangeTwo")
    end)

    it("shows the current round and assigned player for a uniquely determined bound shadow", function()
        local state, first = WaveState({
            marked = true,
            kicks = 0,
            plate = "nameplate1",
        }, { marked = false, kicks = 0, plate = "nameplate2" })
        local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
        assert.is_true(w1)
        assert.is_false(w2)
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("colors assigned players by class and custom text gold", function()
        ns.Api.Group.members = {
            { name = "MeleeOne", fullName = "MeleeOne-TestRealm", classFile = "WARRIOR" },
            { name = "RangeOne", fullName = "RangeOne-TestRealm", classFile = "MAGE" },
        }
        assert.is_true(Module:AssignInterruptText("RANGED", 1, "点名远程"))
        local state = WaveState({
            marked = true,
            kicks = 0,
            plate = "nameplate1",
        }, { marked = false, kicks = 0, plate = "nameplate2" })
        local views = Resolve(state)
        assert.equals("WARRIOR", views.nameplate1.classFile)
        assert.is_nil(views.nameplate1.nameColor)
        assert.equals("点名远程", views.nameplate2.name)
        assert.is_nil(views.nameplate2.classFile)
        assert.equals(ns.Assets.Colors.TEXT_GOLD, views.nameplate2.nameColor)
    end)

    it("uses the reversed melee/ranged assignment when the second member is melee", function()
        local state, first = WaveState({
            marked = false,
            kicks = 1,
            plate = "nameplate1",
        }, { marked = true, kicks = 0, plate = "nameplate2" })
        local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
        assert.is_false(w1)
        assert.is_true(w2)
        local views = Resolve(state)
        assert.equals(2, views.nameplate1.number)
        assert.equals("RangeTwo", views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals("MeleeOne", views.nameplate2.name)
        assert.equals("pale_green", views.nameplate2.scheme)
    end)

    it("keeps the round and shows 待标记 when both possible worlds remain", function()
        local state, first = WaveState({
            marked = false,
            kicks = 2,
            plate = "nameplate1",
        }, { marked = false, kicks = 0, plate = "nameplate2" })
        local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
        assert.is_true(w1)
        assert.is_true(w2)
        local views = Resolve(state)
        assert.equals(3, views.nameplate1.number)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals(Pending(), views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("keeps the round and shows 待标记 when no possible world remains", function()
        local state, first = WaveState({
            marked = true,
            kicks = 0,
            plate = "nameplate1",
        }, { marked = false, kicks = 0 })
        local original = Tracker.GetPossibleWorlds
        Tracker.GetPossibleWorlds = function()
            return false, false
        end
        local w1, w2 = Tracker.GetPossibleWorlds(first.wave)
        assert.is_false(w1)
        assert.is_false(w2)
        local views = Resolve(state)
        Tracker.GetPossibleWorlds = original
        assert.equals(1, views.nameplate1.number)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.is_nil(views.nameplate2)
    end)

    it("shows a shared round and 待标记 for unmarked unbound candidates with equal counters", function()
        local state = WaveState({ kicks = 0 }, { kicks = 0 })
        state.candidates.nameplate1 = false
        state.candidates.nameplate2 = false
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals(Pending(), views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("hides unbound candidates when current-wave counters differ", function()
        local state = WaveState({ kicks = 1 }, { kicks = 0 })
        state.candidates.nameplate1 = false
        state.candidates.nameplate2 = false
        local views = Resolve(state)
        assert.is_nil(next(views))
    end)

    it("replaces 待标记 with the assigned player after a bound shadow's side is marked", function()
        local state, first = WaveState({
            marked = false,
            kicks = 0,
            plate = "nameplate1",
        }, { marked = false, kicks = 0, plate = "nameplate2" })
        assert.equals(Pending(), Resolve(state).nameplate1.name)
        assert.equals("gold", Resolve(state).nameplate1.scheme)
        first.marked = true
        local views = Resolve(state)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("shows the assigned player after pairing only when the side is unique", function()
        local state, first = WaveState({ marked = false, kicks = 0 }, { marked = false, kicks = 0 })
        state.candidates.nameplate1 = false
        assert.equals(Pending(), Resolve(state).nameplate1.name)

        first.plate = "nameplate1"
        state.plateOwner.nameplate1 = first
        state.candidates.nameplate1 = nil
        assert.equals(Pending(), Resolve(state).nameplate1.name)

        first.marked = true
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
    end)

    it("does not show an indicator for an expired-wave shadow", function()
        local oldWave = { members = {} }
        local leftover = Shadow(oldWave, { expired = true, kicks = 3, plate = "nameplate9" })
        oldWave.members = { leftover }
        local state = WaveState({ kicks = 0, plate = "nameplate1", marked = true }, { kicks = 0 })
        state.list = { leftover, state.list[1], state.list[2] }
        state.plateOwner.nameplate9 = leftover
        local views = Resolve(state)
        assert.is_nil(views.nameplate9)
        assert.equals(1, views.nameplate1.number)
        assert.equals("MeleeOne", views.nameplate1.name)
    end)

    it("suppresses unbound candidates while an expired-wave shadow is still alive", function()
        local oldWave = { members = {} }
        local leftover = Shadow(oldWave, { expired = true, kicks = 4, plate = "nameplate9" })
        oldWave.members = { leftover }
        local state, first = WaveState({
            kicks = 0,
            marked = true,
            plate = "nameplate1",
        }, { kicks = 0 })
        state.list = { leftover, first, state.list[2] }
        state.plateOwner.nameplate9 = leftover
        state.candidates.nameplate4 = false
        local views = Resolve(state)
        assert.is_nil(views.nameplate4)
        assert.is_nil(views.nameplate9)
        assert.equals("MeleeOne", views.nameplate1.name)
    end)

    it("advances a bound indicator after an interrupt", function()
        local state, first = WaveState({
            marked = true,
            kicks = 0,
            plate = "nameplate1",
        }, { marked = false, kicks = 0 })
        assert.equals(1, Resolve(state).nameplate1.number)
        assert.equals("MeleeOne", Resolve(state).nameplate1.name)
        first.kicks = 1
        local views = Resolve(state)
        assert.equals(2, views.nameplate1.number)
        assert.equals("MeleeTwo", views.nameplate1.name)
    end)

    it("does not mutate combat state while resolving", function()
        local state, first, second = WaveState({ kicks = 0 }, { kicks = 0 })
        state.candidates.nameplate1 = true
        Resolve(state)
        assert.equals(0, first.kicks)
        assert.equals(0, second.kicks)
        assert.is_true(state.candidates.nameplate1)
        assert.is_nil(next(state.plateOwner))
    end)

    it("shows the ranged first kick on an unmarked 1-add candidate", function()
        local state = Tracker.New()
        Spawn(state, 1)
        AddPlate(state, "nameplate1", false)
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals("RangeOne", views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
    end)

    it("shows the melee first kick on a 1-add candidate when the boss token is marked", function()
        local state = Tracker.New()
        Mark("boss3", true)
        Spawn(state, 1)
        AddPlate(state, "nameplate1", false)
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
    end)

    it("hides leftover 1-add candidates after the shadow is bound", function()
        local state = Tracker.New()
        Spawn(state, 1)
        AddPlate(state, "nameplate1", false)
        Cast(state, "INTERRUPTED", "boss3", true, true)
        Cast(state, "INTERRUPTED", "nameplate1", true, true)
        Tracker.Flush(state)
        AddPlate(state, "nameplate2", false)
        local views = Resolve(state)
        assert.equals(2, views.nameplate1.number)
        assert.is_nil(views.nameplate2)
    end)

    it("shows pending on both 2-add candidates before any marker", function()
        local state = Tracker.New()
        Spawn(state, 2)
        AddPlate(state, "nameplate1", false)
        AddPlate(state, "nameplate2", false)
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals(Pending(), views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("assigns melee and ranged from a marked candidate on ADDED", function()
        local state = Tracker.New()
        Spawn(state, 2)
        AddPlate(state, "nameplate1", true)
        AddPlate(state, "nameplate2", false)
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("assigns melee and ranged after RTU marks one unbound candidate", function()
        local state = Tracker.New()
        Spawn(state, 2)
        AddPlate(state, "nameplate1", false)
        AddPlate(state, "nameplate2", false)
        Mark("nameplate1", true)
        Tracker.OnRaidTargetChanged(state)
        local views = Resolve(state)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("applies candidate marks from Reconcile when RTU shares an engage batch", function()
        local state = Tracker.New()
        Spawn(state, 2)
        AddPlate(state, "nameplate1", false)
        AddPlate(state, "nameplate2", false)
        SetBossCount(2)
        Tracker.OnEngage(state)
        Mark("nameplate1", true)
        Tracker.OnRaidTargetChanged(state)
        assert.is_false(state.candidates.nameplate1)
        Tracker.Flush(state)
        assert.is_true(state.candidates.nameplate1)
        assert.is_false(state.candidates.nameplate2)
        local views = Resolve(state)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("shows pending when both 2-add candidates are marked", function()
        local state = WaveState({ kicks = 0 }, { kicks = 0 })
        state.candidates.nameplate1 = true
        state.candidates.nameplate2 = true
        local views = Resolve(state)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals(Pending(), views.nameplate2.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("hides 2-add candidates when kicks differ", function()
        local state = WaveState({ kicks = 1 }, { kicks = 0 })
        state.candidates.nameplate1 = false
        state.candidates.nameplate2 = true
        local views = Resolve(state)
        assert.is_nil(views.nameplate1)
        assert.is_nil(views.nameplate2)
    end)

    it("shows the remaining 2-add candidate by side after one shadow is bound", function()
        local state, first = WaveState({
            kicks = 0,
            marked = false,
            plate = "nameplate1",
        }, { kicks = 0, marked = false })
        state.candidates.nameplate2 = true
        local views = Resolve(state)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals("MeleeOne", views.nameplate2.name)
        assert.equals("pale_green", views.nameplate2.scheme)

        first.marked = true
        state.candidates.nameplate2 = false
        views = Resolve(state)
        assert.equals("MeleeOne", views.nameplate1.name)
        assert.equals("pale_green", views.nameplate1.scheme)
        assert.equals("RangeOne", views.nameplate2.name)
        assert.equals("gold", views.nameplate2.scheme)
    end)

    it("shows only the round and 待标记 when extra 92-level candidates appear", function()
        local state = WaveState({ kicks = 0 }, { kicks = 0 })
        state.candidates.nameplate1 = true
        state.candidates.nameplate2 = false
        state.candidates.nameplate3 = false
        local views = Resolve(state)
        assert.equals(1, views.nameplate1.number)
        assert.equals(Pending(), views.nameplate1.name)
        assert.equals("gold", views.nameplate1.scheme)
        assert.equals(1, views.nameplate2.number)
        assert.equals(Pending(), views.nameplate2.name)
        assert.equals(1, views.nameplate3.number)
        assert.equals(Pending(), views.nameplate3.name)
    end)

    describe("when marked shadows use the ranged chain", function()
        before_each(function()
            assert.is_true(Module:SetMarkedChain("RANGED"))
        end)

        it("shows ranged then melee on a uniquely determined bound pair", function()
            local state = WaveState({
                marked = true,
                kicks = 0,
                plate = "nameplate1",
            }, { marked = false, kicks = 0, plate = "nameplate2" })
            local views = Resolve(state)
            assert.equals(1, views.nameplate1.number)
            assert.equals("RangeOne", views.nameplate1.name)
            assert.equals("gold", views.nameplate1.scheme)
            assert.equals(1, views.nameplate2.number)
            assert.equals("MeleeOne", views.nameplate2.name)
            assert.equals("pale_green", views.nameplate2.scheme)
        end)

        it("assigns ranged then melee from a marked candidate", function()
            local state = WaveState({ kicks = 0 }, { kicks = 0 })
            state.candidates.nameplate1 = true
            state.candidates.nameplate2 = false
            local views = Resolve(state)
            assert.equals(1, views.nameplate1.number)
            assert.equals("RangeOne", views.nameplate1.name)
            assert.equals("gold", views.nameplate1.scheme)
            assert.equals(1, views.nameplate2.number)
            assert.equals("MeleeOne", views.nameplate2.name)
            assert.equals("pale_green", views.nameplate2.scheme)
        end)

        it("shows the melee chain on an unmarked 1-add candidate and bound plate", function()
            local state = Tracker.New()
            Spawn(state, 1)
            AddPlate(state, "nameplate1", false)
            local views = Resolve(state)
            assert.equals(1, views.nameplate1.number)
            assert.equals("MeleeOne", views.nameplate1.name)
            assert.equals("pale_green", views.nameplate1.scheme)

            Cast(state, "START", "boss3", true)
            Cast(state, "START", "nameplate1", true)
            Tracker.Flush(state)
            views = Resolve(state)
            assert.equals(1, views.nameplate1.number)
            assert.equals("MeleeOne", views.nameplate1.name)
            assert.equals("pale_green", views.nameplate1.scheme)
        end)

        it("recomputes nameplates, HUD, and Callout without resetting combat state", function()
            assert.is_true(Module:SetMarkedChain("MELEE"))
            local state, first, second = WaveState({
                marked = true,
                kicks = 0,
                casting = true,
                plate = "nameplate1",
            }, { marked = false, kicks = 0, plate = "nameplate2" })
            local list = state.list
            local meleeAssignment = { chainId = "MELEE", indices = { 1 } }
            local rangedAssignment = { chainId = "RANGED", indices = { 1 } }
            local views = Resolve(state)
            assert.equals("MeleeOne", views.nameplate1.name)
            assert.equals("pale_green", views.nameplate1.scheme)
            assert.equals("normal", Internals.ResolveRotationTrackerView(state, meleeAssignment).mode)
            assert.equals(1, Internals.ResolveInterruptCallout(state, meleeAssignment).round)
            assert.is_nil(Internals.ResolveInterruptCallout(state, rangedAssignment))

            assert.is_true(Module:SetMarkedChain("RANGED"))
            assert(list == state.list)
            assert.equals(0, first.kicks)
            assert.equals(0, second.kicks)
            assert.equals("nameplate1", first.plate)
            assert.equals("nameplate2", second.plate)
            views = Resolve(state)
            assert.equals("RangeOne", views.nameplate1.name)
            assert.equals("gold", views.nameplate1.scheme)
            assert.equals("MeleeOne", views.nameplate2.name)
            assert.equals("pale_green", views.nameplate2.scheme)
            assert.equals("normal", Internals.ResolveRotationTrackerView(state, rangedAssignment).mode)
            assert.equals(0, Internals.ResolveRotationTrackerView(state, meleeAssignment).kicks)
            assert.is_nil(Internals.ResolveInterruptCallout(state, meleeAssignment))
            assert.equals(1, Internals.ResolveInterruptCallout(state, rangedAssignment).round)
        end)
    end)
end)

describe("CoiledAltar nameplate interrupt indicators from production replay", function()
    local runners
    local lastResolve
    local lastState

    local function Fail(message)
        error(message, 0)
    end

    local function Mount(env)
        local ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        local Module = ns.Modules.Get("CoiledAltar")
        local Internals = ns.Modules.Internals("CoiledAltar")
        local Tracker = Internals.InterruptStates
        local Encounter = ns.Api.Encounter
        local Nameplate = ns.Api.Nameplate
        local RaidTarget = ns.Api.RaidTarget
        local Spell = ns.Api.Spell
        local Unit = ns.Api.Unit

        function Unit.Exists(unit)
            return env.api.UnitExists(unit)
        end
        function Unit.GetLevel(unit)
            return env.api.UnitLevel(unit)
        end
        function RaidTarget.GetIndex(unit)
            return env.api.GetRaidTargetIndex(unit)
        end

        if not Module:AssignInterruptPlayer("MELEE", 1, "PlayerA") then
            Fail("failed to configure a non-empty interrupt chain")
        end
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        local state = Tracker.Get()
        if type(state) ~= "table" then
            Fail("Coiled Altar tracker did not start for encounter 3429")
        end
        lastState = state
        state.requestFlush = function()
            if state.flushScheduled or state.disposed then
                return
            end
            state.flushScheduled = true
            env:defer(function()
                state.flushScheduled = false
                if state.disposed then
                    return
                end
                Tracker.Flush(state)
            end)
        end

        env.events:on("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
            Encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
        end)
        env.events:on("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
            Encounter.FireEngageUnit()
        end)
        env.events:on("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
            Spell.FireCastStart(unit, castGUID, spellID)
        end)
        env.events:on("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID, spellID)
            Spell.FireCastInterrupted(unit, castGUID, spellID)
        end)
        env.events:on("UNIT_SPELLCAST_STOP", function(_, unit, castGUID, spellID)
            Spell.FireCastStop(unit, castGUID, spellID)
        end)
        env.events:on("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
            Spell.FireCastSucceeded(unit, castGUID, spellID)
        end)
        env.events:on("NAME_PLATE_UNIT_ADDED", function(_, unit)
            Nameplate.FireAdded(unit, {})
        end)
        env.events:on("NAME_PLATE_UNIT_REMOVED", function(_, unit)
            Nameplate.FireRemoved(unit)
        end)
        env.events:on("RAID_TARGET_UPDATE", function()
            RaidTarget.FireChanged()
        end)

        lastResolve = function()
            return Internals.ResolveNameplateIndicators(Tracker.Get(), Module:GetInterruptAssignments())
        end

        return {
            snapshot = function()
                return lastResolve()
            end,
            stop = function()
                if Tracker.Get() == state then
                    Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
                end
            end,
        }
    end

    local function RunReplay(fixture, extraOnFrame)
        local runner = Replay.new({ mount = Mount })
        runners[#runners + 1] = runner
        runner:run(fixture, {
            onFrame = extraOnFrame,
        })
        return runner
    end

    local function SpawnSteps(firstMarked, secondMarked)
        return {
            {
                op = "unit",
                token = "boss3",
                properties = { exists = true, level = 92, markerPresent = firstMarked == true },
            },
            {
                op = "unit",
                token = "boss4",
                properties = { exists = true, level = 92, markerPresent = secondMarked == true },
            },
            {
                op = "unit",
                token = "boss5",
                properties = { exists = false },
            },
            {
                op = "event",
                name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                args = Replay.args(),
            },
        }
    end

    before_each(function()
        runners = {}
        lastResolve = nil
        lastState = nil
    end)

    after_each(function()
        for i = 1, #runners do
            pcall(function()
                runners[i]:close()
            end)
        end
    end)

    it("shows round 1 and 待标记 on the initial unbound cast", function()
        local views = {}
        local plates = {}
        RunReplay({
            schemaVersion = 1,
            name = "Initial Cast Without Nameplate START",
            frames = {
                { id = 1, time = 1, steps = SpawnSteps(false, false) },
                {
                    id = 2,
                    time = 2,
                    steps = {
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss4", Replay.PRESENT, Replay.PRESENT),
                        },
                    },
                },
                {
                    id = 3,
                    time = 3,
                    steps = {
                        {
                            op = "unit",
                            token = "nameplate2",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "unit",
                            token = "nameplate3",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_ADDED",
                            args = Replay.args("nameplate2"),
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_ADDED",
                            args = Replay.args("nameplate3"),
                        },
                    },
                },
                {
                    id = 4,
                    time = 4,
                    steps = {
                        {
                            op = "unit",
                            token = "boss3",
                            properties = { markerPresent = true },
                        },
                        {
                            op = "unit",
                            token = "nameplate2",
                            properties = { exists = true, level = 92, markerPresent = true },
                        },
                        {
                            op = "event",
                            name = "RAID_TARGET_UPDATE",
                            args = Replay.args(),
                        },
                    },
                },
                {
                    id = 5,
                    time = 5,
                    steps = {
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("nameplate2", Replay.PRESENT, Replay.PRESENT),
                        },
                    },
                },
            },
        }, function(_, frame)
            views[frame.id] = lastResolve()
            plates[frame.id] = {
                first = lastState.list[1] and lastState.list[1].plate,
                owners = lastState.plateOwner,
            }
        end)

        local pending = "待标记"
        assert.equals(1, views[3].nameplate2.number)
        assert.equals(pending, views[3].nameplate2.name)
        assert.equals(1, views[3].nameplate3.number)
        assert.equals(pending, views[3].nameplate3.name)
        assert.is_nil(plates[3].first)
        assert.equals("PlayerA", views[4].nameplate2.name)
        assert.equals("pale_green", views[4].nameplate2.scheme)
        assert.equals("", views[4].nameplate3.name)
        assert.equals("gold", views[4].nameplate3.scheme)
        assert.equals("nameplate2", plates[5].first)
        assert.is_nil(plates[5].owners.nameplate3)
        assert.equals(1, views[5].nameplate2.number)
        assert.equals("PlayerA", views[5].nameplate2.name)
        assert.equals(1, views[5].nameplate3.number)
        assert.equals("", views[5].nameplate3.name)
        assert.equals("gold", views[5].nameplate3.scheme)
    end)

    it("binds on a same-frame interrupt and advances only that indicator", function()
        local views = {}
        RunReplay({
            schemaVersion = 1,
            name = "First Interrupt Pairing",
            frames = {
                { id = 1, time = 1, steps = SpawnSteps(true, false) },
                {
                    id = 2,
                    time = 2,
                    steps = {
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss4", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "unit",
                            token = "nameplate2",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "unit",
                            token = "nameplate3",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_ADDED",
                            args = Replay.args("nameplate2"),
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_ADDED",
                            args = Replay.args("nameplate3"),
                        },
                    },
                },
                {
                    id = 3,
                    time = 3,
                    steps = {
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_INTERRUPTED",
                            args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_INTERRUPTED",
                            args = Replay.args("nameplate2", Replay.PRESENT, Replay.PRESENT),
                        },
                    },
                },
            },
        }, function(_, frame)
            views[frame.id] = lastResolve()
        end)

        assert.equals("", views[2].nameplate2.name)
        assert.equals("gold", views[2].nameplate2.scheme)
        assert.equals("nameplate2", lastState.list[1].plate)
        assert.equals(1, lastState.list[1].kicks)
        assert.equals(0, lastState.list[2].kicks)
        assert.is_nil(lastState.plateOwner.nameplate3)
        assert.equals(2, views[3].nameplate2.number)
        assert.equals("", views[3].nameplate2.name)
        assert.is_nil(views[3].nameplate3)
    end)

    it("clears a dead shadow's indicator and does not reuse a stale binding", function()
        local views = {}
        local plates = {}
        RunReplay({
            schemaVersion = 1,
            name = "Death and Nameplate Reuse",
            frames = {
                { id = 1, time = 1, steps = SpawnSteps(true, false) },
                {
                    id = 2,
                    time = 2,
                    steps = {
                        {
                            op = "unit",
                            token = "nameplate7",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_START",
                            args = Replay.args("nameplate7", Replay.PRESENT, Replay.PRESENT),
                        },
                    },
                },
                {
                    id = 3,
                    time = 3,
                    steps = {
                        {
                            op = "unit",
                            token = "boss3",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        { op = "remove", token = "boss4" },
                        {
                            op = "event",
                            name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                            args = Replay.args(),
                        },
                        {
                            op = "event",
                            name = "UNIT_SPELLCAST_INTERRUPTED",
                            args = Replay.args("nameplate7", Replay.PRESENT, nil),
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_REMOVED",
                            args = Replay.args("nameplate7"),
                        },
                        { op = "remove", token = "nameplate7" },
                    },
                },
                {
                    id = 4,
                    time = 4,
                    steps = {
                        {
                            op = "unit",
                            token = "nameplate7",
                            properties = { exists = true, level = 92, markerPresent = false },
                        },
                        {
                            op = "event",
                            name = "NAME_PLATE_UNIT_ADDED",
                            args = Replay.args("nameplate7"),
                        },
                    },
                },
            },
        }, function(_, frame)
            views[frame.id] = lastResolve()
            plates[frame.id] = {
                count = #lastState.list,
                first = lastState.list[1] and lastState.list[1].plate,
                owner = lastState.plateOwner.nameplate7,
            }
        end)

        assert.equals("PlayerA", views[2].nameplate7.name)
        assert.equals("nameplate7", plates[2].first)
        assert.equals(1, plates[3].count)
        assert.is_nil(views[3].nameplate7)
        assert.is_nil(plates[4].owner)
        assert.is_nil(views[4].nameplate7)
    end)
end)
