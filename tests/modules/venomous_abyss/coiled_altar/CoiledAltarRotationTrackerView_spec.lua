local Loader = require("helpers.loader")

describe("CoiledAltar RotationTracker view", function()
    local ns, Internals, Tracker, RaidTarget, Unit

    local function SetBossCount(count)
        for i = 3, 8 do
            Unit.SetForTests("boss" .. i, { exists = i < 3 + count })
        end
    end

    local function Mark(unit, marked)
        RaidTarget.indices[unit] = marked and 1 or nil
    end

    local function Spawn(state, count)
        SetBossCount(count)
        Tracker.OnEngage(state)
        Tracker.Flush(state)
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
        return {
            list = list,
            plateOwner = {},
            curWave = wave,
            disposed = false,
        }, first, second, wave
    end

    local function Assignment(chainId, indices)
        return {
            chainId = chainId or "MELEE",
            indices = indices or { 3 },
        }
    end

    local function View(state, chainId, indices)
        return Internals.ResolveRotationTrackerView(state, Assignment(chainId, indices))
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Internals = ns.Modules.Internals("CoiledAltar")
        Tracker = Internals.InterruptStates
        RaidTarget = ns.Api.RaidTarget
        Unit = ns.Api.Unit
    end)

    it("hides when there is no current wave", function()
        local view = View(Tracker.New())
        assert.equals("hidden", view.mode)
        assert.is_nil(view.chainId)
    end)

    it("hides when the player has no assignment", function()
        local state = Tracker.New()
        Spawn(state, 2)
        assert.equals("hidden", Internals.ResolveRotationTrackerView(state, nil).mode)
        assert.equals("hidden", Internals.ResolveRotationTrackerView(state, Assignment("MELEE", {})).mode)
    end)

    it("shows round 1 for a new assigned wave with no marker", function()
        local state = Tracker.New()
        Spawn(state, 2)
        local view = View(state, "MELEE", { 3 })
        assert.equals("normal", view.mode)
        assert.equals("MELEE", view.chainId)
        assert.same({ 3 }, view.indices)
        assert.equals(0, view.kicks)
    end)

    it("assigns a 1-add unmarked spawn to the ranged chain", function()
        local state = Tracker.New()
        Spawn(state, 1)
        assert.equals("hidden", View(state, "MELEE", { 3 }).mode)
        local ranged = View(state, "RANGED", { 2 })
        assert.equals("normal", ranged.mode)
        assert.equals("RANGED", ranged.chainId)
        assert.equals(0, ranged.kicks)
        assert.equals(false, ranged.casting)

        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.Flush(state)
        local after = View(state, "RANGED", { 2 })
        assert.equals("normal", after.mode)
        assert.equals(1, after.kicks)
        assert.equals("hidden", View(state, "MELEE", { 3 }).mode)
    end)

    it("assigns an unmarked 1-add to melee when marked shadows use the ranged chain", function()
        ns.Modules.Get("CoiledAltar"):SetMarkedChain("RANGED")
        local state = Tracker.New()
        Spawn(state, 1)
        local melee = View(state, "MELEE", { 3 })
        assert.equals("normal", melee.mode)
        assert.equals("MELEE", melee.chainId)
        assert.equals(0, melee.kicks)
        assert.equals("hidden", View(state, "RANGED", { 2 }).mode)
    end)

    it("assigns a 1-add marked spawn to the melee chain", function()
        local state = Tracker.New()
        Mark("boss3", true)
        Spawn(state, 1)
        local melee = View(state, "MELEE", { 3 })
        assert.equals("normal", melee.mode)
        assert.equals("MELEE", melee.chainId)
        assert.equals(0, melee.kicks)
        assert.equals("hidden", View(state, "RANGED", { 2 }).mode)

        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.Flush(state)
        assert.equals(1, View(state, "MELEE", { 3 }).kicks)
        assert.equals("hidden", View(state, "RANGED", { 2 }).mode)
    end)

    it("shows a shared round when unmarked shadows have equal kicks", function()
        local state = WaveState({ kicks = 2 }, { kicks = 2 })
        local view = View(state, "RANGED", { 2 })
        assert.equals("normal", view.mode)
        assert.equals("RANGED", view.chainId)
        assert.equals(2, view.kicks)
    end)

    it("enters pending when unmarked shadows have different kicks", function()
        local state = Tracker.New()
        Spawn(state, 2)
        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.Flush(state)
        local view = View(state, "MELEE", { 1 })
        assert.equals("pending", view.mode)
        assert.equals("MELEE", view.chainId)
        assert.same({ 1 }, view.indices)
        assert.is_nil(view.kicks)
    end)

    it("resolves pending to the marked side's round", function()
        local state = Tracker.New()
        Spawn(state, 2)
        Tracker.OnCast(state, "INTERRUPTED", "boss4", true, true)
        Tracker.Flush(state)
        assert.equals("pending", View(state, "MELEE", { 3 }).mode)

        Mark("boss3", true)
        Tracker.OnRaidTargetChanged(state)
        local melee = View(state, "MELEE", { 3 })
        assert.equals("normal", melee.mode)
        assert.equals(0, melee.kicks)
        local ranged = View(state, "RANGED", { 2 })
        assert.equals("normal", ranged.mode)
        assert.equals(1, ranged.kicks)
    end)

    it("advances the assigned chain after that shadow is interrupted", function()
        local state = Tracker.New()
        Mark("boss3", true)
        Spawn(state, 2)
        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.Flush(state)
        local view = View(state, "MELEE", { 4 })
        assert.equals("normal", view.mode)
        assert.equals(1, view.kicks)
    end)

    it("does not advance the assigned chain when the opposite shadow is interrupted", function()
        local state = Tracker.New()
        Mark("boss3", true)
        Spawn(state, 2)
        Tracker.OnCast(state, "INTERRUPTED", "boss4", true, true)
        Tracker.Flush(state)
        local view = View(state, "MELEE", { 4 })
        assert.equals("normal", view.mode)
        assert.equals(0, view.kicks)
        assert.equals(1, state.list[2].kicks)
    end)

    it("hides when the assigned current-wave shadow dies", function()
        local state, melee, ranged = WaveState({ marked = true, kicks = 2 }, { kicks = 1 }, nil)
        state.list = { ranged }
        assert.equals("hidden", View(state, "MELEE", { 3 }).mode)
        local other = View(state, "RANGED", { 1 })
        assert.equals("normal", other.mode)
        assert.equals(1, other.kicks)
        assert.equals(melee.kicks, 2)
    end)

    it("keeps the current-wave view when an expired shadow dies", function()
        local previous = { members = {} }
        local expired = Shadow(previous, { expired = true, kicks = 4 })
        previous.members = { expired, Shadow(previous, { expired = true, kicks = 1 }) }
        local state, melee, ranged = WaveState({ marked = true, kicks = 1 }, { kicks = 0 })
        state.list = { expired, melee, ranged }
        local before = View(state, "MELEE", { 2 })
        assert.equals("normal", before.mode)
        assert.equals(1, before.kicks)

        state.list = { melee, ranged }
        local after = View(state, "MELEE", { 2 })
        assert.equals("normal", after.mode)
        assert.equals("MELEE", after.chainId)
        assert.equals(1, after.kicks)
        assert.same(before.indices, after.indices)
    end)

    it("resets to the new wave instead of keeping the previous round", function()
        local state = Tracker.New()
        Mark("boss3", true)
        Spawn(state, 2)
        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.OnCast(state, "INTERRUPTED", "boss3", true, true)
        Tracker.Flush(state)
        assert.equals(2, View(state, "MELEE", { 1 }).kicks)

        SetBossCount(4)
        Tracker.OnEngage(state)
        Tracker.Flush(state)
        local view = View(state, "MELEE", { 1 })
        assert.equals("normal", view.mode)
        assert.equals(0, view.kicks)
        assert.is_true(state.list[1].expired)
        assert.equals(state.curWave.members[1].kicks, 0)
    end)

    it("keeps every matching assignment in the same chain", function()
        local state = WaveState()
        local view = View(state, "MELEE", { 1, 3, 4 })
        assert.equals("normal", view.mode)
        assert.same({ 1, 3, 4 }, view.indices)
    end)
end)
