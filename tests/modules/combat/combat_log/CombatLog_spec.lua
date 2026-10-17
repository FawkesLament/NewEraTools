local Loader = require("helpers.loader")

local RAID_ID = 1001
local DUNGEON_ID = 2001
local SEASONAL_ID = 3001

describe("CombatLog", function()
    local ns, Module, CombatLogApi, Instance, Timer

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
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CombatLog")
        CombatLogApi = ns.Api.CombatLog
        Instance = ns.Api.Instance
        Timer = ns.Api.Timer

        Instance.currentRaidIds[RAID_ID] = true
        Instance.currentDungeonIds[DUNGEON_ID] = true
        Instance.seasonalMythicIds[SEASONAL_ID] = true
        CombatLogApi.logging = false
        Module:StartMonitoring()
    end)

    local function EnableInRaid()
        Module:SetEnabled(true)
        EnterRaid(RAID_ID)
        Module:UpdateMonitoring()
    end

    it("is registered with saved settings", function()
        assert.is_false(Module == nil)
        assert.equals("table", type(Module.db))
        assert.is_false(Module:IsEnabled())
        assert.equals(Module.LOCATION_ALL, Module:GetLocations())
    end)

    describe("enabled", function()
        it("toggles and auto-enables logging in an eligible instance", function()
            ns.Util.Print = function() end
            EnterRaid(RAID_ID)
            Module:SetEnabled(true)
            assert.is_true(CombatLogApi.logging)
            Module:SetEnabled(false)
            assert.is_false(Module:IsEnabled())
        end)
    end)

    describe("EnsureLogging", function()
        local printed

        before_each(function()
            printed = {}
            ns.Util.Print = function(message)
                table.insert(printed, message)
            end
        end)

        it("enables logging and prints when it was off", function()
            EnableInRaid()
            assert.is_true(CombatLogApi.logging)
            assert.equals(1, #printed)
            assert(printed[1]:find(ns.L.COMBAT_LOG_LOGGING_ENABLED, 1, true))
        end)

        it("does not print when logging is already on", function()
            CombatLogApi.logging = true
            EnableInRaid()
            assert.is_true(CombatLogApi.logging)
            assert.same({}, printed)
        end)

        it("does not treat unknown logging state as disabled", function()
            CombatLogApi.logging = nil
            Module:SetEnabled(true)
            EnterRaid(RAID_ID)
            Module:UpdateMonitoring()
            assert.same({}, printed)
            assert.equals(nil, CombatLogApi.logging)
        end)

        it("does nothing outside eligible instances", function()
            Module:SetEnabled(true)
            assert.is_false(CombatLogApi.logging)
            assert.same({}, printed)
        end)

        it("does not enable when the feature is disabled", function()
            EnterRaid(RAID_ID)
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)
            assert.same({}, printed)
        end)
    end)

    describe("eligibility", function()
        before_each(function()
            Module:SetEnabled(true)
            CombatLogApi.logging = false
            ns.Util.Print = function() end
        end)

        it("enables in a current-expansion raid", function()
            EnterRaid(RAID_ID)
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("enables during a raid boss encounter", function()
            EnterRaid(RAID_ID)
            Instance.info.difficultyID = 16
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("ignores legacy raids", function()
            EnterRaid(9999)
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)
        end)

        it("enables in current-expansion Mythic 0", function()
            EnterMythicDungeon(DUNGEON_ID, Instance.DIFFICULTY_MYTHIC_DUNGEON)
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("enables for Mythic 0 on a seasonal older-expansion dungeon", function()
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_DUNGEON)
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("enables in a seasonal Mythic+ dungeon including during the key", function()
            EnterMythicDungeon(SEASONAL_ID, Instance.DIFFICULTY_MYTHIC_KEYSTONE)
            Instance.challengeModeActive = true
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("does not enable in Normal or Heroic dungeons", function()
            Instance.info = {
                name = "Dungeon",
                instanceType = "party",
                difficultyID = 2,
                instanceID = DUNGEON_ID,
            }
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)
        end)

        it("respects the locations setting", function()
            Module:SetLocations(Module.LOCATION_DUNGEONS)
            EnterRaid(RAID_ID)
            CombatLogApi.logging = false
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)

            Module:SetLocations(Module.LOCATION_RAIDS)
            EnterMythicDungeon(DUNGEON_ID)
            CombatLogApi.logging = false
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)

            Module:SetLocations(Module.LOCATION_ALL)
            CombatLogApi.logging = false
            Module:UpdateMonitoring()
            assert.is_true(CombatLogApi.logging)
        end)

        it("enables after zoning via PLAYER_ENTERING_WORLD", function()
            CombatLogApi.logging = false
            EnterRaid(RAID_ID)
            Instance.FireEnteringWorld()
            assert.is_true(CombatLogApi.logging)
        end)

        it("retries shortly after PLAYER_ENTERING_WORLD for late game state", function()
            Module:SetEnabled(true)
            CombatLogApi.logging = false
            Instance.FireEnteringWorld()
            assert.is_false(CombatLogApi.logging)
            EnterRaid(RAID_ID)
            Timer.Advance(1)
            assert.is_true(CombatLogApi.logging)
        end)

        it("does not enable after leaving the instance", function()
            EnableInRaid()
            assert.is_true(CombatLogApi.logging)
            LeaveInstance()
            CombatLogApi.logging = false
            Module:UpdateMonitoring()
            assert.is_false(CombatLogApi.logging)
        end)
    end)
end)
