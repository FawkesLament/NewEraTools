local Loader = require("helpers.loader")

describe("TwinFangs interrupt status", function()
    local ns, Module, Encounter, EncounterTimeline, Instance, Timer, GameEvents, Player
    local nextEventId

    local function ActiveEvent(duration)
        local eventInfo = {
            id = nextEventId,
            source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER,
            duration = duration,
        }
        nextEventId = nextEventId + 1
        EncounterTimeline.SetEventStateForTests(eventInfo.id, EncounterTimeline.EVENT_STATE_ACTIVE)
        return eventInfo
    end

    local function FireCycleBars(count)
        for _ = 1, count do
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
        end
    end

    local function AssignPrimary(index)
        index = index or 3
        local players = {}
        for i = 1, index do
            players[i] = { name = i == index and Player.GetFullName() or ("Other" .. i .. "-TestRealm") }
        end
        local chain = Module.db.interruptReminder.chain
        chain.front_left.group = 1
        chain.front_left.players = players
    end

    local function AssignBackupOnly()
        local chain = Module.db.interruptReminder.chain
        chain.front_right.group = 2
        chain.front_right.players = { { name = "Other-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
    end

    local function StartMythic()
        Module:SetInterruptReminderEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
    end

    local function TriggerBrood()
        FireCycleBars(Module.BROOD_SLOT)
        Timer.Advance(Module.CYCLE_DURATION)
    end

    local function ExpectedStatus(interruptCount, index)
        index = index or 3
        return {
            region = "front_left",
            index = index,
            interruptCount = interruptCount,
            chainLength = index,
        }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Instance = ns.Api.Instance
        Timer = ns.Api.Timer
        GameEvents = ns.Api.GameEvents
        Player = ns.Api.Player
        nextEventId = 1
        Module:ListenForEncounter()
    end)

    describe("activation", function()
        it("opens an 11-second window when Brood elapses for a primary assignment", function()
            AssignPrimary(3)
            assert.is_true(Module:HasPrimaryInterruptAssignment())
            StartMythic()
            FireCycleBars(Module.BROOD_SLOT - 1)
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            Timer.Advance(Module.CYCLE_DURATION - 0.01)
            assert.is_false(Module:IsInterruptStatusActive())
            Timer.Advance(0.01)
            assert.is_true(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
            assert.same(ExpectedStatus(0, 3), Module:GetInterruptStatus())

            Timer.Advance(Module.INTERRUPT_STATUS_DURATION - 0.01)
            assert.is_true(Module:IsInterruptStatusActive())
            Timer.Advance(0.01)
            assert.is_false(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
            assert.is_nil(Module:GetInterruptStatus())
        end)

        it("uses the same region, index, and count as Edit Mode preview", function()
            AssignPrimary(3)
            StartMythic()
            Module:BeginInterruptStatusWindow()
            local preview = Module:GetInterruptStatusPreview()
            local live = Module:GetInterruptStatus()
            assert.equals(preview.region, live.region)
            assert.equals(preview.index, live.index)
            assert.equals(preview.interruptCount, live.interruptCount)
            assert.equals(5, preview.chainLength)
            assert.equals(3, live.chainLength)
        end)

        it("does not activate for backup-only or unassigned players", function()
            assert.is_false(Module:HasPrimaryInterruptAssignment())
            StartMythic()
            TriggerBrood()
            assert.is_false(Module:IsInterruptStatusActive())
            assert.is_nil(Module:GetInterruptStatus())

            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            AssignBackupOnly()
            assert.is_false(Module:HasPrimaryInterruptAssignment())
            StartMythic()
            TriggerBrood()
            assert.is_false(Module:IsInterruptStatusActive())
            assert.is_nil(Module:GetInterruptStatus())
        end)

        it("does not activate when the interrupt reminder is off", function()
            AssignPrimary()
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            TriggerBrood()
            assert.is_false(Module:IsInterruptStatusActive())
        end)

        it("hides immediately when the encounter ends", function()
            AssignPrimary()
            StartMythic()
            TriggerBrood()
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(1, Module:GetInterruptCount())
            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            assert.is_false(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
            Timer.Advance(Module.INTERRUPT_STATUS_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())
        end)

        it("starts each Brood window at round 1", function()
            AssignPrimary()
            StartMythic()
            TriggerBrood()
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.same(ExpectedStatus(2), Module:GetInterruptStatus())

            FireCycleBars(Module.CYCLE_LENGTH)
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_true(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
            assert.same(ExpectedStatus(0), Module:GetInterruptStatus())
        end)

        it("ignores a stale hide after a newer window has begun", function()
            AssignPrimary()
            StartMythic()
            Module:BeginInterruptStatusWindow()
            GameEvents.Fire("CHAT_MSG_PARTY")
            Timer.Advance(1)
            Module:BeginInterruptStatusWindow()
            assert.equals(0, Module:GetInterruptCount())
            Timer.Advance(Module.INTERRUPT_STATUS_DURATION - 1)
            assert.is_true(Module:IsInterruptStatusActive())
            assert.same(ExpectedStatus(0), Module:GetInterruptStatus())
            Timer.Advance(1)
            assert.is_false(Module:IsInterruptStatusActive())
        end)
    end)

    describe("counting", function()
        local function OpenWindow()
            AssignPrimary()
            StartMythic()
            TriggerBrood()
        end

        it("increments once per party or party-leader chat without reading the payload", function()
            OpenWindow()
            local secret = setmetatable({}, {
                __index = function()
                    error("secret payload was read")
                end,
                __tostring = function()
                    error("secret payload was read")
                end,
            })
            GameEvents.Fire("CHAT_MSG_PARTY", secret, secret)
            GameEvents.Fire("CHAT_MSG_PARTY_LEADER", secret)
            assert.equals(2, Module:GetInterruptCount())
            assert.same(ExpectedStatus(2), Module:GetInterruptStatus())
        end)

        it("ignores party events outside the window and non-party chat", function()
            AssignPrimary()
            StartMythic()
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(0, Module:GetInterruptCount())

            TriggerBrood()
            GameEvents.Fire("CHAT_MSG_WHISPER")
            GameEvents.Fire("CHAT_MSG_RAID")
            GameEvents.Fire("CHAT_MSG_RAID_WARNING")
            assert.equals(0, Module:GetInterruptCount())
            assert.same(ExpectedStatus(0), Module:GetInterruptStatus())

            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(1, Module:GetInterruptCount())

            Timer.Advance(Module.INTERRUPT_STATUS_DURATION)
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(0, Module:GetInterruptCount())
            assert.is_nil(Module:GetInterruptStatus())
        end)

        it("does not extend the window when reports arrive", function()
            OpenWindow()
            Timer.Advance(Module.INTERRUPT_STATUS_DURATION - 1)
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.is_true(Module:IsInterruptStatusActive())
            Timer.Advance(1)
            assert.is_false(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
        end)

        it("keeps the assigned position while the round advances", function()
            AssignPrimary(2)
            StartMythic()
            TriggerBrood()
            assert.same(ExpectedStatus(0, 2), Module:GetInterruptStatus())
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.same(ExpectedStatus(5, 2), Module:GetInterruptStatus())
        end)
    end)

    describe("test mode", function()
        it("does not start when the interrupt reminder is off", function()
            AssignPrimary()
            Module:SetInterruptStatusTestMode(true)
            assert.is_false(Module:IsInterruptStatusTestMode())

            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.is_true(Module:IsInterruptStatusTestMode())
            Module:SetInterruptReminderEnabled(false)
            assert.is_false(Module:IsInterruptStatusTestMode())
        end)

        it("shows the live assignment without an encounter and counts party chat from 0", function()
            AssignPrimary(2)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.is_true(Module:IsInterruptStatusTestMode())
            assert.is_false(Module:IsInterruptStatusActive())
            assert.same(ExpectedStatus(0, 2), Module:GetInterruptStatus())

            local secret = setmetatable({}, {
                __index = function()
                    error("secret payload was read")
                end,
                __tostring = function()
                    error("secret payload was read")
                end,
            })
            GameEvents.Fire("CHAT_MSG_PARTY", secret)
            GameEvents.Fire("CHAT_MSG_WHISPER")
            GameEvents.Fire("CHAT_MSG_PARTY_LEADER", secret)
            assert.same(ExpectedStatus(2, 2), Module:GetInterruptStatus())

            Module:SetInterruptStatusTestMode(false)
            assert.is_false(Module:IsInterruptStatusTestMode())
            assert.is_nil(Module:GetInterruptStatus())
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.is_nil(Module:GetInterruptStatus())
        end)

        it("does not reset the test count when a Brood window starts or ends", function()
            AssignPrimary()
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_PARTY")
            StartMythic()
            TriggerBrood()
            assert.is_true(Module:IsInterruptStatusActive())
            assert.equals(0, Module:GetInterruptCount())
            assert.same(ExpectedStatus(2), Module:GetInterruptStatus())

            Timer.Advance(Module.INTERRUPT_STATUS_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())
            assert.same(ExpectedStatus(2), Module:GetInterruptStatus())
        end)

        it("hides the HUD when the player has no primary assignment", function()
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.is_true(Module:IsInterruptStatusTestMode())
            assert.is_nil(Module:GetInterruptStatus())
            GameEvents.Fire("CHAT_MSG_PARTY")
            AssignPrimary(2)
            assert.same(ExpectedStatus(1, 2), Module:GetInterruptStatus())
        end)
    end)
end)
