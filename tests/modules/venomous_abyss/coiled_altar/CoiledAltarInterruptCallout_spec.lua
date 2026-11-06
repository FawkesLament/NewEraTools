local Loader = require("helpers.loader")

describe("CoiledAltar interrupt Callout", function()
    local ns, Module, Internals, Tracker, Encounter, RaidTarget, Spell, Timer, Unit, CalloutManager, Speech, BossAlert
    local originalShow
    local shows
    local hides

    local function Assignment(chainId, indices)
        return {
            chainId = chainId or "MELEE",
            indices = indices or { 1 },
        }
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

    local function Resolve(state, chainId, indices)
        return Internals.ResolveInterruptCallout(state, Assignment(chainId, indices))
    end

    local function AssignLocal(chainId, ...)
        local name = ns.Api.Player.GetFullName()
        for index = 1, select("#", ...) do
            assert.is_true(Module:AssignInterruptPlayer(chainId, select(index, ...), name))
        end
    end

    local function EnableReminders()
        Module:SetInterruptReminderEnabled(true)
        BossAlert:ListenForCalloutTts()
        BossAlert:SetCalloutTtsEnabled(true)
    end

    local function StartEncounter()
        Module:ListenForEncounter()
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
    end

    local function SpawnLive(count)
        SetBossCount(count)
        Encounter.FireEngageUnit()
        Timer.Advance(0)
    end

    local function StartBoth()
        Spell.FireCastStart("boss3", true, true)
        Spell.FireCastStart("boss4", true, true)
        Timer.Advance(0)
    end

    local function LastShow()
        return shows[#shows]
    end

    local function AssertShownOnce()
        assert.equals(1, #shows)
        assert.equals(ns.L.COILED_ALTAR_INTERRUPT_CALLOUT, LastShow().text)
        assert.equals(Module.INTERRUPT_CALLOUT_DURATION, LastShow().duration)
        assert.is_true(LastShow().appendTimer)
        assert.equals("CoiledAltar", LastShow().source)
        assert.equals(Timer.GetTime() + Module.INTERRUPT_CALLOUT_DURATION, CalloutManager.GetExpiresAt())
        assert.same({ ns.L.COILED_ALTAR_INTERRUPT_CALLOUT }, Speech.spoken)
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Internals = ns.Modules.Internals("CoiledAltar")
        Tracker = Internals.InterruptStates
        Encounter = ns.Api.Encounter
        RaidTarget = ns.Api.RaidTarget
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        Unit = ns.Api.Unit
        CalloutManager = ns.CalloutManager
        Speech = ns.Api.Speech
        BossAlert = ns.Modules.Get("BossAlert")
        shows = {}
        hides = 0
        originalShow = CalloutManager.Show
        function CalloutManager.Show(options)
            shows[#shows + 1] = options
            local handle = originalShow(options)
            local dismiss = handle.Dismiss
            function handle:Dismiss()
                hides = hides + 1
                return dismiss(self)
            end
            return handle
        end
    end)

    after_each(function()
        if originalShow then
            CalloutManager.Show = originalShow
        end
    end)

    describe("resolver", function()
        it("returns nil when there is no current wave", function()
            assert.is_nil(Resolve(Tracker.New(), "MELEE", { 1 }))
        end)

        it("returns nil when the player has no interrupt assignment", function()
            local state = Tracker.New()
            Spawn(state, 2)
            state.list[1].casting = true
            state.list[2].casting = true
            assert.is_nil(Internals.ResolveInterruptCallout(state, nil))
            assert.is_nil(Resolve(state, "MELEE", {}))
        end)

        it("returns the first-round melee task when both unmarked shadows start together", function()
            local state = Tracker.New()
            Spawn(state, 2)
            state.list[1].casting = true
            state.list[2].casting = true
            local task = Resolve(state, "MELEE", { 1 })
            assert(task.wave == state.curWave)
            assert.equals("MELEE", task.chainId)
            assert.equals(1, task.round)
            local ranged = Resolve(state, "RANGED", { 1 })
            assert.equals("RANGED", ranged.chainId)
            assert.equals(1, ranged.round)
        end)

        it("keeps the same first-round identity after a marker arrives", function()
            local state = Tracker.New()
            Spawn(state, 2)
            state.list[1].casting = true
            state.list[2].casting = true
            local before = Resolve(state, "MELEE", { 1 })
            Mark("boss3", true)
            Tracker.OnRaidTargetChanged(state)
            local after = Resolve(state, "MELEE", { 1 })
            assert(before.wave == after.wave)
            assert.equals(before.chainId, after.chainId)
            assert.equals(before.round, after.round)
        end)

        it("returns nil when neither world guarantees a local interrupt", function()
            local state = WaveState({ kicks = 1, casting = true }, { kicks = 0, casting = true })
            assert.is_nil(Resolve(state, "MELEE", { 2 }))
            assert.is_nil(Resolve(state, "RANGED", { 2 }))
        end)

        it("returns a later-round task once the assigned shadow is casting", function()
            local state = WaveState({ marked = true, kicks = 2, casting = true }, { kicks = 1, casting = false })
            local task = Resolve(state, "MELEE", { 3 })
            assert.equals("MELEE", task.chainId)
            assert.equals(3, task.round)
        end)

        it("returns the matching round when the player occupies multiple slots", function()
            local state = WaveState({ marked = true, kicks = 2, casting = true }, { kicks = 0, casting = false })
            local task = Resolve(state, "MELEE", { 1, 3 })
            assert.equals(3, task.round)
            state.list[1].kicks = 0
            local first = Resolve(state, "MELEE", { 1, 3 })
            assert.equals(1, first.round)
        end)

        it("returns nil when the assigned shadow is not casting", function()
            local state = WaveState({ marked = true, kicks = 0, casting = false }, { kicks = 0, casting = true })
            assert.is_nil(Resolve(state, "MELEE", { 1 }))
        end)

        it("alerts the ranged first kick when a marked first member uses the ranged chain", function()
            Module:SetMarkedChain("RANGED")
            local state = WaveState({ marked = true, kicks = 0, casting = true }, { kicks = 0, casting = false })
            local ranged = Resolve(state, "RANGED", { 1 })
            assert.equals("RANGED", ranged.chainId)
            assert.equals(1, ranged.round)
            assert.is_nil(Resolve(state, "MELEE", { 1 }))
        end)

        it("returns nil when the assigned current-wave shadow is dead", function()
            local state, melee, ranged = WaveState({ marked = true, kicks = 0, casting = true }, { kicks = 0, casting = true })
            state.list = { ranged }
            assert.is_nil(Resolve(state, "MELEE", { 1 }))
            local other = Resolve(state, "RANGED", { 1 })
            assert.equals(1, other.round)
            assert.equals(melee.kicks, 0)
        end)
    end)

    describe("lifecycle", function()
        it("does not show a Callout without a current wave", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            Internals.NotifyEncounterState()
            assert.equals(0, #shows)
            assert.equals(0, #Speech.spoken)
        end)

        it("does not show a Callout when the player has no interrupt assignment", function()
            assert.is_true(Module:AssignInterruptPlayer("MELEE", 1, "OtherPlayer"))
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            assert.equals(0, #shows)
        end)

        it("shows one Callout for each first-round assignee during an unmarked simultaneous start", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            AssertShownOnce()
        end)

        it("shows the ranged first-round Callout on that client's simultaneous start", function()
            AssignLocal("RANGED", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            AssertShownOnce()
        end)

        it("does not restart the same first-cast task on duplicate notifications", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            local expiresAt = CalloutManager.GetExpiresAt()
            Tracker.OnRaidTargetChanged(Tracker.Get())
            Internals.NotifyEncounterState()
            assert.equals(1, #shows)
            assert.equals(1, #Speech.spoken)
            assert.equals(expiresAt, CalloutManager.GetExpiresAt())
            assert.equals(0, hides)
        end)

        it("does not restart the countdown when a marker arrives during the first cast", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            local expiresAt = CalloutManager.GetExpiresAt()
            Mark("boss3", true)
            RaidTarget.FireChanged()
            assert.equals(1, #shows)
            assert.equals(1, #Speech.spoken)
            assert.equals(expiresAt, CalloutManager.GetExpiresAt())
            assert.equals(ns.L.COILED_ALTAR_INTERRUPT_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("does not show a Callout when neither world guarantees a local interrupt", function()
            AssignLocal("MELEE", 2)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            Spell.FireCastInterrupted("boss3", true, true)
            Timer.Advance(0)
            StartBoth()
            assert.equals(0, #shows)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("shows a new Callout when the assigned shadow begins a later-round cast", function()
            AssignLocal("MELEE", 1, 2)
            EnableReminders()
            StartEncounter()
            Mark("boss3", true)
            SpawnLive(2)
            StartBoth()
            AssertShownOnce()
            Spell.FireCastInterrupted("boss3", true, true)
            Timer.Advance(0)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())
            Spell.FireCastStart("boss3", true, true)
            Timer.Advance(0)
            assert.equals(2, #shows)
            assert.equals(2, #Speech.spoken)
            assert.equals(ns.L.COILED_ALTAR_INTERRUPT_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("hides the Callout when the assigned shadow is interrupted", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            Mark("boss3", true)
            SpawnLive(2)
            StartBoth()
            Spell.FireCastInterrupted("boss3", true, true)
            Timer.Advance(0)
            assert.equals(1, #shows)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("keeps the Callout when the other shadow is interrupted and the task remains certain", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            Mark("boss3", true)
            SpawnLive(2)
            StartBoth()
            local expiresAt = CalloutManager.GetExpiresAt()
            Spell.FireCastInterrupted("boss4", true, true)
            Timer.Advance(0)
            assert.equals(1, #shows)
            assert.equals(0, hides)
            assert.equals(expiresAt, CalloutManager.GetExpiresAt())
            assert.equals(ns.L.COILED_ALTAR_INTERRUPT_CALLOUT, CalloutManager.GetDisplayed())
        end)

        it("hides the Callout when the assigned shadow dies", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            Mark("boss3", true)
            Mark("boss4", false)
            SpawnLive(2)
            Unit.SetForTests("nameplate1", { exists = true, level = 92 })
            Spell.FireCastStart("boss3", true, true)
            Spell.FireCastStart("nameplate1", true, true)
            Timer.Advance(0)
            AssertShownOnce()
            SetBossCount(1)
            Mark("boss3", false)
            Encounter.FireEngageUnit()
            Spell.FireCastInterrupted("nameplate1", true, nil)
            ns.Api.Nameplate.FireRemoved("nameplate1")
            Timer.Advance(0)
            assert.equals(1, #shows)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("does not hide a current-wave Callout when an expired previous-wave shadow dies", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            SetBossCount(4)
            Encounter.FireEngageUnit()
            Timer.Advance(0)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())

            Mark("boss5", true)
            RaidTarget.FireChanged()
            Spell.FireCastStart("boss5", true, true)
            Spell.FireCastStart("boss6", true, true)
            Timer.Advance(0)
            assert.equals(2, #shows)
            local expiresAt = CalloutManager.GetExpiresAt()
            local state = Tracker.Get()
            local expired = state.list[1]
            assert.is_true(expired.expired)
            table.remove(state.list, 1)
            Internals.NotifyEncounterState()
            assert.equals(2, #shows)
            assert.equals(1, hides)
            assert.equals(expiresAt, CalloutManager.GetExpiresAt())
        end)

        it("ends the previous Callout when a new wave appears and evaluates the new task", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            assert.equals(1, #shows)
            SetBossCount(4)
            Encounter.FireEngageUnit()
            Timer.Advance(0)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())
            Spell.FireCastStart("boss5", true, true)
            Spell.FireCastStart("boss6", true, true)
            Timer.Advance(0)
            assert.equals(2, #shows)
            assert.equals(2, #Speech.spoken)
        end)

        it("shows Callouts for each assigned round when the player appears multiple times", function()
            AssignLocal("MELEE", 1, 3)
            EnableReminders()
            StartEncounter()
            Mark("boss3", true)
            SpawnLive(2)
            StartBoth()
            assert.equals(1, #shows)
            Spell.FireCastInterrupted("boss3", true, true)
            Timer.Advance(0)
            Spell.FireCastStart("boss3", true, true)
            Timer.Advance(0)
            assert.equals(1, #shows)
            Spell.FireCastInterrupted("boss3", true, true)
            Timer.Advance(0)
            Spell.FireCastStart("boss3", true, true)
            Timer.Advance(0)
            assert.equals(2, #shows)
            assert.equals(2, #Speech.spoken)
        end)

        it("does not restart the same task after the Callout expires naturally", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            Timer.Advance(Module.INTERRUPT_CALLOUT_DURATION)
            assert.is_nil(CalloutManager.GetDisplayed())
            Tracker.OnRaidTargetChanged(Tracker.Get())
            Internals.NotifyEncounterState()
            assert.equals(1, #shows)
            assert.equals(1, #Speech.spoken)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("hides on encounter cleanup and ignores delayed callbacks", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            StartBoth()
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
            assert.equals(1, hides)
            assert.is_nil(CalloutManager.GetDisplayed())
            Spell.FireCastStart("boss3", true, true)
            Spell.FireCastStart("boss4", true, true)
            Timer.Advance(0)
            assert.equals(1, #shows)
            assert.equals(1, #Speech.spoken)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("leaves another source's Callout in place when this task is not showing", function()
            AssignLocal("MELEE", 1)
            EnableReminders()
            StartEncounter()
            SpawnLive(2)
            CalloutManager.Show = originalShow
            originalShow({ source = "OtherFeature", text = "other", duration = 60 })
            function CalloutManager.Show(options)
                shows[#shows + 1] = options
                local handle = originalShow(options)
                local dismiss = handle.Dismiss
                function handle:Dismiss()
                    hides = hides + 1
                    return dismiss(self)
                end
                return handle
            end
            Internals.NotifyEncounterState()
            assert.equals("other", CalloutManager.GetCurrent().text)
            StartBoth()
            assert.equals(ns.L.COILED_ALTAR_INTERRUPT_CALLOUT, CalloutManager.GetDisplayed())
        end)
    end)
end)
