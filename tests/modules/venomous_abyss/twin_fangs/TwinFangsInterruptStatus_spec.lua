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

    local function AssignBackupOnly(chainLength)
        chainLength = chainLength or 1
        local players = {}
        for i = 1, chainLength do
            players[i] = { name = "Other" .. i .. "-TestRealm" }
        end
        local chain = Module.db.interruptReminder.chain
        chain.front_right.group = 2
        chain.front_right.players = players
        chain.front_right.backup = { name = Player.GetFullName() }
    end

    local function AssignBoth(primaryIndex, backupLength)
        AssignPrimary(primaryIndex)
        AssignBackupOnly(backupLength)
    end

    local function FireBackupWhisper()
        GameEvents.Fire("CHAT_MSG_WHISPER", ns.L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
    end

    local function ExpectedBackupStatus(interruptCount, chainLength)
        chainLength = chainLength or 1
        return {
            region = "front_right",
            index = chainLength + 1,
            interruptCount = interruptCount,
            chainLength = chainLength,
        }
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

        it("does not activate for unassigned players", function()
            assert.is_false(Module:HasPrimaryInterruptAssignment())
            assert.is_false(Module:HasBackupInterruptAssignment())
            StartMythic()
            TriggerBrood()
            assert.is_false(Module:IsInterruptStatusActive())
            assert.is_nil(Module:GetInterruptStatus())
            assert.is_nil(Module:GetBackupInterruptStatus())
        end)

        it("opens the window for a backup-only assignment", function()
            AssignBackupOnly(2)
            assert.is_false(Module:HasPrimaryInterruptAssignment())
            assert.is_true(Module:HasBackupInterruptAssignment())
            StartMythic()
            TriggerBrood()
            assert.is_true(Module:IsInterruptStatusActive())
            assert.is_nil(Module:GetInterruptStatus())
            assert.same(ExpectedBackupStatus(0, 2), Module:GetBackupInterruptStatus())
        end)

        it("does not activate when the interrupt reminder is off", function()
            AssignPrimary()
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            TriggerBrood()
            assert.is_false(Module:IsInterruptStatusActive())
        end)

        it("does not open the window for a ~57s feast bar", function()
            AssignPrimary()
            StartMythic()
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
            Timer.Advance(Module.FEAST_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())
        end)

        it("does not let a ~57s bar consume a slot in the cycle", function()
            AssignPrimary()
            StartMythic()
            FireCycleBars(Module.BROOD_SLOT - 1)
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
            Timer.Advance(Module.FEAST_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_true(Module:IsInterruptStatusActive())
        end)

        it("opens the window when the 2nd ~33s bar elapses", function()
            AssignPrimary()
            StartMythic()
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            Timer.Advance(Module.BROOD_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            Timer.Advance(Module.BROOD_DURATION - 0.01)
            assert.is_false(Module:IsInterruptStatusActive())
            Timer.Advance(0.01)
            assert.is_true(Module:IsInterruptStatusActive())
        end)

        it("does not wrap the ~33s brood count", function()
            AssignPrimary()
            StartMythic()
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            Timer.Advance(Module.BROOD_DURATION)
            assert.is_true(Module:IsInterruptStatusActive())
            Timer.Advance(Module.INTERRUPT_STATUS_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            Timer.Advance(Module.BROOD_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())
        end)

        it("does not let a ~33s bar consume a slot in the cycle", function()
            AssignPrimary()
            StartMythic()
            FireCycleBars(Module.BROOD_SLOT - 1)
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.BROOD_DURATION))
            Timer.Advance(Module.BROOD_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            EncounterTimeline.FireEventAdded(ActiveEvent(Module.CYCLE_DURATION))
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_true(Module:IsInterruptStatusActive())
        end)

        it("resets the cycle when the next pull starts", function()
            AssignPrimary()
            StartMythic()
            FireCycleBars(Module.BROOD_SLOT - 1)
            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_false(Module:IsInterruptStatusActive())

            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            FireCycleBars(Module.BROOD_SLOT)
            Timer.Advance(Module.CYCLE_DURATION)
            assert.is_true(Module:IsInterruptStatusActive())
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

        it("shows the interrupt callout when Brood reaches the player's assignment", function()
            AssignPrimary(1)
            StartMythic()
            TriggerBrood()
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT),
                Module:GetDisplayedCallout()
            )
            assert.is_false(Module:GetCalloutAppendTimer())
            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            assert.is_nil(Module:GetDisplayedCallout())
        end)

        it("shows the backup-region callout after the backup rotation is exhausted", function()
            AssignBackupOnly(2)
            StartMythic()
            TriggerBrood()
            assert.is_nil(Module:GetDisplayedCallout())
            FireBackupWhisper()
            assert.is_nil(Module:GetDisplayedCallout())
            FireBackupWhisper()
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT),
                Module:GetDisplayedCallout()
            )
            assert.is_false(Module:GetCalloutAppendTimer())
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

        it("advances the backup region on each incoming whisper without reading the payload", function()
            AssignBoth(2, 2)
            StartMythic()
            TriggerBrood()
            assert.same(ExpectedStatus(0, 2), Module:GetInterruptStatus())
            assert.same(ExpectedBackupStatus(0, 2), Module:GetBackupInterruptStatus())

            local secret = setmetatable({}, {
                __index = function()
                    error("secret payload was read")
                end,
                __tostring = function()
                    error("secret payload was read")
                end,
            })
            GameEvents.Fire("CHAT_MSG_WHISPER_INFORM", ns.L.TWIN_FANGS_INTERRUPT_MACRO_BACKUP_REPORT)
            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(1, Module:GetInterruptCount())
            assert.equals(0, Module:GetBackupInterruptCount())

            GameEvents.Fire("CHAT_MSG_WHISPER", secret)
            GameEvents.Fire("CHAT_MSG_WHISPER")
            assert.same(ExpectedStatus(1, 2), Module:GetInterruptStatus())
            assert.same(ExpectedBackupStatus(2, 2), Module:GetBackupInterruptStatus())
        end)
    end)

    describe("test mode", function()
        local Group

        before_each(function()
            Group = ns.Api.Group
            Group.inRaid = true
        end)

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

        it("does not start when the player is not in a raid", function()
            AssignPrimary()
            Module:SetInterruptReminderEnabled(true)
            Group.inRaid = false
            Module:SetInterruptStatusTestMode(true)
            assert.is_false(Module:IsInterruptStatusTestMode())

            Group.inRaid = true
            Module:SetInterruptStatusTestMode(true)
            assert.is_true(Module:IsInterruptStatusTestMode())
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

        it("shows a 10-second interrupt callout on the player's turn and hides it after", function()
            AssignPrimary(2)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.is_nil(Module:GetDisplayedCallout())

            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT),
                Module:GetDisplayedCallout()
            )
            assert.equals(Timer.GetTime() + Module.INTERRUPT_CALLOUT_DURATION, Module:GetCalloutExpiresAt())
            assert.is_false(Module:GetCalloutAppendTimer())

            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.is_nil(Module:GetDisplayedCallout())
        end)

        it("shows the interrupt callout when the first assignment is the player's", function()
            AssignPrimary(1)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT),
                Module:GetDisplayedCallout()
            )

            Module:SetInterruptStatusTestMode(false)
            assert.is_nil(Module:GetDisplayedCallout())
        end)

        it("hides the interrupt callout when its duration elapses", function()
            AssignPrimary(1)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            Timer.Advance(Module.INTERRUPT_CALLOUT_DURATION - 0.01)
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT),
                Module:GetDisplayedCallout()
            )
            Timer.Advance(0.01)
            assert.is_nil(Module:GetDisplayedCallout())
            assert.is_true(Module:IsInterruptStatusTestMode())
        end)

        it("lets a later soak callout replace the interrupt callout", function()
            AssignPrimary(1)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            Module:ShowCallout(ns.L.TWIN_FANGS_SOAK_ENTER, Timer.GetTime() + 20, {
                kind = "soak",
                appendTimer = true,
            })
            assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
            assert.is_true(Module:GetCalloutAppendTimer())

            GameEvents.Fire("CHAT_MSG_PARTY")
            assert.equals(ns.L.TWIN_FANGS_SOAK_ENTER, Module:GetDisplayedCallout())
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

        it("shows backup status without an encounter and counts whispers from 0", function()
            AssignBackupOnly(2)
            Module:SetInterruptReminderEnabled(true)
            Module:SetInterruptStatusTestMode(true)
            assert.is_true(Module:IsInterruptStatusTestMode())
            assert.is_false(Module:IsInterruptStatusActive())
            assert.is_nil(Module:GetInterruptStatus())
            assert.same(ExpectedBackupStatus(0, 2), Module:GetBackupInterruptStatus())

            local secret = setmetatable({}, {
                __index = function()
                    error("secret payload was read")
                end,
                __tostring = function()
                    error("secret payload was read")
                end,
            })
            GameEvents.Fire("CHAT_MSG_PARTY")
            GameEvents.Fire("CHAT_MSG_WHISPER", secret)
            assert.same(ExpectedBackupStatus(1, 2), Module:GetBackupInterruptStatus())
            assert.is_nil(Module:GetDisplayedCallout())

            GameEvents.Fire("CHAT_MSG_WHISPER_INFORM")
            assert.equals(
                ns.L.TWIN_FANGS_INTERRUPT_CALLOUT:format(ns.L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT),
                Module:GetDisplayedCallout()
            )

            Module:SetInterruptStatusTestMode(false)
            assert.is_nil(Module:GetBackupInterruptStatus())
            GameEvents.Fire("CHAT_MSG_WHISPER")
            GameEvents.Fire("CHAT_MSG_WHISPER_INFORM")
            assert.is_nil(Module:GetBackupInterruptStatus())
        end)
    end)
end)
