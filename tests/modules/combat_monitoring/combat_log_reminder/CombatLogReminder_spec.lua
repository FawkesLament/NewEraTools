local Loader = require("helpers.loader")

local EPSILON = 1e-9
local RAID_ID = 1001
local DUNGEON_ID = 2001
local SEASONAL_ID = 3001

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("CombatLogReminder", function()
    local ns, Reminder, CombatLog, Encounter, Instance, Timer

    local function EnterRaid(instanceID)
        Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = 16,
            instanceID = instanceID or RAID_ID,
        }
    end

    local function EnterMythicDungeon(instanceID, difficultyID)
        Instance.info = {
            name = "Dungeon",
            instanceType = "party",
            difficultyID = difficultyID or Instance.DIFFICULTY_MYTHIC_DUNGEON,
            instanceID = instanceID or DUNGEON_ID,
        }
    end

    local function LeaveInstance()
        Instance.info = {
            name = "",
            instanceType = "none",
            difficultyID = 0,
            instanceID = 0,
        }
        Instance.challengeModeActive = false
        Encounter.inProgress = false
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Reminder = ns.Modules.Get("CombatLogReminder")
        CombatLog = ns.Api.CombatLog
        Encounter = ns.Api.Encounter
        Instance = ns.Api.Instance
        Timer = ns.Api.Timer

        Instance.currentRaidIds[RAID_ID] = true
        Instance.currentDungeonIds[DUNGEON_ID] = true
        Instance.seasonalMythicIds[SEASONAL_ID] = true
        CombatLog.logging = false
        Reminder:StartMonitoring()
    end)

    local function EnableInRaid()
        Reminder:SetEnabled(true)
        EnterRaid(RAID_ID)
        Reminder:UpdateMonitoring()
    end

    it("is registered with saved settings", function()
        assert.is_false(Reminder == nil)
        assert.equals("table", type(Reminder.db))
        assert.is_false(Reminder:IsEnabled())
        assert.is_true(Reminder:GetRemindRaids())
        assert.is_true(Reminder:GetRemindMythicDungeons())
    end)

    describe("enabled", function()
        it("toggles and notifies the UI hook", function()
            local seen = {}
            function Reminder:OnDisplayChanged()
                table.insert(seen, self:IsEnabled())
            end
            Reminder:SetEnabled(true)
            Reminder:SetEnabled(true)
            Reminder:SetEnabled(false)
            assert.same({ true, false }, seen)
        end)
    end)

    describe("scale", function()
        it("is 100% by default", function()
            AssertNear(1, Reminder:GetScale())
        end)

        it("clamps to 50%–200% and snaps to the step", function()
            Reminder:SetScale(0.1)
            AssertNear(Reminder.SCALE_MIN, Reminder:GetScale())
            Reminder:SetScale(3)
            AssertNear(Reminder.SCALE_MAX, Reminder:GetScale())
            Reminder:SetScale(1.22)
            AssertNear(1.2, Reminder:GetScale())
        end)
    end)

    describe("position", function()
        it("stores a valid anchor", function()
            Reminder:SetPosition({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -20 })
            local position = Reminder:GetPosition()
            assert.equals("TOPLEFT", position.point)
            assert.equals(10, position.x)
            assert.equals(-20, position.y)
        end)

        it("rejects a bad anchor", function()
            assert.is_false(pcall(Reminder.SetPosition, Reminder, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
            }))
        end)
    end)

    describe("EnableLogging", function()
        local printed

        before_each(function()
            printed = {}
            ns.Util.Print = function(message)
                table.insert(printed, message)
            end
        end)

        it("enables logging, clears the reminder, and prints success feedback", function()
            EnableInRaid()
            assert.is_true(Reminder:ShouldRemind())
            assert.is_true(Reminder:EnableLogging())
            assert.is_true(Reminder:GetKnownLogging())
            assert.is_false(Reminder:ShouldRemind())
            assert.equals(1, #printed)
            assert(printed[1]:find(ns.L.COMBAT_LOG_REMINDER_LOGGING_ENABLED, 1, true))
        end)

        it("keeps the reminder and prints an error when the API is rate-limited", function()
            EnableInRaid()
            assert.is_true(Reminder:ShouldRemind())
            CombatLog.setRateLimited = true
            assert.is_false(Reminder:EnableLogging())
            assert.is_false(Reminder:GetKnownLogging())
            assert.is_true(Reminder:ShouldRemind())
            assert.equals(1, #printed)
            assert(printed[1]:find(ns.L.COMBAT_LOG_REMINDER_LOGGING_ENABLE_FAILED, 1, true))
        end)

        it("does not print when polling refreshes logging state", function()
            EnableInRaid()
            CombatLog.logging = true
            Timer.Advance(5)
            assert.is_false(Reminder:ShouldRemind())
            assert.same({}, printed)
        end)
    end)

    describe("polling lifecycle", function()
        it("does not poll outside eligible instances", function()
            Reminder:SetEnabled(true)
            assert.is_false(Reminder:IsPolling())
            Timer.Advance(5)
            assert.is_false(Reminder:IsPolling())
            assert.equals(nil, Reminder:GetKnownLogging())
        end)

        it("starts polling with an immediate LoggingCombat check when entering an eligible raid", function()
            EnableInRaid()
            assert.is_true(Reminder:IsPolling())
            assert.is_false(Reminder:GetKnownLogging())
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("stops polling when leaving the instance", function()
            EnableInRaid()
            assert.is_true(Reminder:IsPolling())
            LeaveInstance()
            Reminder:UpdateMonitoring()
            assert.is_false(Reminder:IsPolling())
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("stops polling when the feature is disabled", function()
            EnableInRaid()
            Reminder:SetEnabled(false)
            assert.is_false(Reminder:IsPolling())
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("does not restart an already-running ticker", function()
            EnableInRaid()
            local firstPending = #Timer.pending
            Reminder:UpdateMonitoring()
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:IsPolling())
            assert.equals(firstPending, #Timer.pending)
        end)

        it("polls logging state every 5 seconds only while eligible", function()
            EnableInRaid()
            assert.is_true(Reminder:ShouldRemind())
            CombatLog.logging = true
            assert.is_true(Reminder:ShouldRemind())
            Timer.Advance(5)
            assert.is_false(Reminder:ShouldRemind())
            assert.is_true(Reminder:IsPolling())
        end)

        it("stops during a raid encounter and restarts after", function()
            EnableInRaid()
            assert.is_true(Reminder:IsPolling())
            Encounter.FireStart(1, "Boss", 16, 20)
            assert.is_false(Reminder:IsPolling())
            assert.is_false(Reminder:ShouldRemind())
            Encounter.FireEnd(1, "Boss", 16, 20, 1)
            assert.is_true(Reminder:IsPolling())
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("stops when Mythic+ starts and can restart after completion", function()
            Reminder:SetEnabled(true)
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_KEYSTONE)
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:IsPolling())
            Instance.FireChallengeModeStart()
            assert.is_false(Reminder:IsPolling())
            assert.is_false(Reminder:ShouldRemind())
            Instance.FireChallengeModeCompleted()
            assert.is_true(Reminder:IsPolling())
            assert.is_true(Reminder:ShouldRemind())
        end)
    end)

    describe("ShouldRemind", function()
        before_each(function()
            Reminder:SetEnabled(true)
        end)

        it("shows in a current-expansion raid when logging is disabled", function()
            EnterRaid(RAID_ID)
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("hides when combat logging is enabled", function()
            EnterRaid(RAID_ID)
            Reminder:UpdateMonitoring()
            CombatLog.logging = true
            Timer.Advance(5)
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("does not treat unknown logging state as disabled", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load(nil))
            Reminder = ns.Modules.Get("CombatLogReminder")
            CombatLog = ns.Api.CombatLog
            Instance = ns.Api.Instance
            CombatLog.logging = nil
            Instance.currentRaidIds[RAID_ID] = true
            Reminder:SetEnabled(true)
            Reminder:StartMonitoring()
            EnterRaid(RAID_ID)
            Reminder:UpdateMonitoring()
            assert.equals(nil, Reminder:GetKnownLogging())
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("hides during a raid boss encounter and returns after", function()
            EnterRaid(RAID_ID)
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:ShouldRemind())
            Encounter.FireStart(1, "Boss", 16, 20)
            assert.is_false(Reminder:ShouldRemind())
            Encounter.FireEnd(1, "Boss", 16, 20, 1)
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("ignores legacy raids", function()
            EnterRaid(9999)
            Reminder:UpdateMonitoring()
            assert.is_false(Reminder:ShouldRemind())
            assert.is_false(Reminder:IsPolling())
        end)

        it("shows in current-expansion Mythic 0 before the key starts", function()
            EnterMythicDungeon(DUNGEON_ID, Instance.DIFFICULTY_MYTHIC_DUNGEON)
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("shows for Mythic 0 on a seasonal older-expansion dungeon", function()
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_DUNGEON)
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("shows in a seasonal Mythic+ dungeon before the timer starts", function()
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_KEYSTONE)
            Instance.challengeModeActive = false
            Reminder:UpdateMonitoring()
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("hides once Mythic+ challenge mode is active", function()
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_KEYSTONE)
            Reminder:UpdateMonitoring()
            Instance.FireChallengeModeStart()
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("does not show in Normal or Heroic dungeons", function()
            Instance.info = {
                name = "Dungeon",
                instanceType = "party",
                difficultyID = 2,
                instanceID = DUNGEON_ID,
            }
            Reminder:UpdateMonitoring()
            assert.is_false(Reminder:ShouldRemind())
            assert.is_false(Reminder:IsPolling())
        end)

        it("respects reminder location toggles", function()
            EnterRaid(RAID_ID)
            Reminder:UpdateMonitoring()
            Reminder:SetRemindRaids(false)
            assert.is_false(Reminder:ShouldRemind())
            assert.is_false(Reminder:IsPolling())
            EnterMythicDungeon(DUNGEON_ID)
            Reminder:SetRemindMythicDungeons(false)
            Reminder:UpdateMonitoring()
            assert.is_false(Reminder:ShouldRemind())
        end)

        it("restores correctly after zoning via PLAYER_ENTERING_WORLD", function()
            CombatLog.logging = false
            EnterRaid(RAID_ID)
            Instance.FireEnteringWorld()
            assert.is_true(Reminder:IsPolling())
            assert.is_true(Reminder:ShouldRemind())
        end)

        it("retries monitoring shortly after PLAYER_ENTERING_WORLD for late game state", function()
            Reminder:SetEnabled(true)
            Instance.FireEnteringWorld()
            assert.is_false(Reminder:IsPolling())
            EnterRaid(RAID_ID)
            Timer.Advance(1)
            assert.is_true(Reminder:IsPolling())
            assert.is_true(Reminder:ShouldRemind())
        end)
    end)
end)
