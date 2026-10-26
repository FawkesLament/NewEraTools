-- Production api/Instance.lua. Feature specs keep tests/helpers/fakes/Instance.lua.
-- Encounter Journal and challenge-mode globals are stand-ins. Each load has its own caches.

local CURRENT_RAID = 2811
local CURRENT_DUNGEON = 2812
local SEASONAL_DUNGEON = 2400

local function Load()
    local ns = { Api = {} }
    assert(loadfile("api/Instance.lua"))("NewEraTools", ns)
    return ns.Api.Instance
end

describe("Instance production", function()
    local saved = {}
    local tier
    local queries
    local raidMap

    local function SaveGlobals()
        saved.GetInstanceInfo = GetInstanceInfo
        saved.GetSubZoneText = GetSubZoneText
        saved.EJ_GetNumTiers = EJ_GetNumTiers
        saved.EJ_GetCurrentTier = EJ_GetCurrentTier
        saved.EJ_SelectTier = EJ_SelectTier
        saved.EJ_GetInstanceByIndex = EJ_GetInstanceByIndex
        saved.C_ChallengeMode = C_ChallengeMode
    end

    local function InstallJournal()
        tier = 1
        queries = 0
        raidMap = CURRENT_RAID
        GetInstanceInfo = function()
            return nil
        end
        GetSubZoneText = function()
            return nil
        end
        EJ_GetNumTiers = function()
            return 2
        end
        EJ_GetCurrentTier = function()
            return 1
        end
        EJ_SelectTier = function(index)
            tier = index
        end
        EJ_GetInstanceByIndex = function(index, isRaid)
            queries = queries + 1
            if index ~= 1 then
                return nil
            end
            if tier == 2 and isRaid then
                return 10, "Current Raid", nil, nil, nil, nil, nil, nil, nil, nil, raidMap
            end
            if tier == 2 and not isRaid then
                return 11, "Current Dungeon", nil, nil, nil, nil, nil, nil, nil, nil, CURRENT_DUNGEON
            end
            if tier == 1 and not isRaid then
                return 12, "Seasonal Name", nil, nil, nil, nil, nil, nil, nil, nil, SEASONAL_DUNGEON
            end
            return nil
        end
        C_ChallengeMode = {
            GetMapTable = function()
                return { 501 }
            end,
            GetMapUIInfo = function()
                return "Seasonal Name", nil, nil, nil, nil, 0
            end,
            IsChallengeModeActive = function()
                return 1
            end,
        }
    end

    before_each(function()
        SaveGlobals()
        InstallJournal()
    end)

    after_each(function()
        GetInstanceInfo = saved.GetInstanceInfo
        GetSubZoneText = saved.GetSubZoneText
        EJ_GetNumTiers = saved.EJ_GetNumTiers
        EJ_GetCurrentTier = saved.EJ_GetCurrentTier
        EJ_SelectTier = saved.EJ_SelectTier
        EJ_GetInstanceByIndex = saved.EJ_GetInstanceByIndex
        C_ChallengeMode = saved.C_ChallengeMode
    end)

    it("fills missing instance info and passes a complete result through", function()
        local Instance = Load()
        local missing = Instance.GetInfo()
        assert.is_nil(missing.name)
        assert.equals("none", missing.instanceType)
        assert.equals(0, missing.difficultyID)
        assert.equals(0, missing.instanceID)

        GetInstanceInfo = function()
            return "Current Raid", "raid", 16, nil, nil, nil, nil, CURRENT_RAID
        end
        local present = Instance.GetInfo()
        assert.equals("Current Raid", present.name)
        assert.equals("raid", present.instanceType)
        assert.equals(16, present.difficultyID)
        assert.equals(CURRENT_RAID, present.instanceID)

        assert.equals("", Instance.GetSubZoneText())
        GetSubZoneText = function()
            return "Altar of the Six Winds"
        end
        assert.equals("Altar of the Six Winds", Instance.GetSubZoneText())
    end)

    it("recognizes only the last Encounter Journal tier and restores the previous tier", function()
        local Instance = Load()
        assert.is_true(Instance.IsCurrentExpansionRaid(CURRENT_RAID))
        assert.is_false(Instance.IsCurrentExpansionRaid(SEASONAL_DUNGEON))
        assert.is_true(Instance.IsCurrentExpansionDungeon(CURRENT_DUNGEON))
        assert.is_false(Instance.IsCurrentExpansionDungeon(CURRENT_RAID))
        assert.equals(1, tier)
    end)

    it("resolves a seasonal dungeon by id and by name, and ignores map id 0", function()
        local Instance = Load()
        assert.is_true(Instance.IsSeasonalMythicDungeon(SEASONAL_DUNGEON, nil))
        assert.is_true(Instance.IsSeasonalMythicDungeon(1, "Seasonal Name"))
        assert.is_false(Instance.IsSeasonalMythicDungeon(0, nil))
        assert.is_false(Instance.IsSeasonalMythicDungeon(9, "Other"))
        assert.equals(1, tier)
    end)

    it("reuses the journal cache until RefreshCaches", function()
        local Instance = Load()
        assert.is_true(Instance.IsCurrentExpansionRaid(CURRENT_RAID))
        local afterFirst = queries
        assert.is_false(Instance.IsCurrentExpansionRaid(9999))
        assert.is_true(Instance.IsCurrentExpansionDungeon(CURRENT_DUNGEON))
        assert.equals(afterFirst, queries)

        raidMap = 9999
        Instance.RefreshCaches()
        assert.is_true(queries > afterFirst)
        assert.is_false(Instance.IsCurrentExpansionRaid(CURRENT_RAID))
        assert.is_true(Instance.IsCurrentExpansionRaid(9999))
        assert.equals(1, tier)
    end)

    it("treats only boolean true as an active challenge mode", function()
        local Instance = Load()
        assert.is_false(Instance.IsChallengeModeActive())
        C_ChallengeMode.IsChallengeModeActive = function()
            return true
        end
        assert.is_true(Instance.IsChallengeModeActive())
        assert.is_true(Instance.IsMythicDungeonDifficulty(Instance.DIFFICULTY_MYTHIC_KEYSTONE))
        assert.is_true(Instance.IsMythicDungeonDifficulty(Instance.DIFFICULTY_MYTHIC_DUNGEON))
        assert.is_false(Instance.IsMythicDungeonDifficulty(Instance.DIFFICULTY_MYTHIC_RAID))
    end)

    it("fails closed when the journal and challenge-mode APIs are missing", function()
        EJ_GetNumTiers = nil
        EJ_GetCurrentTier = nil
        EJ_SelectTier = nil
        EJ_GetInstanceByIndex = nil
        C_ChallengeMode = nil
        local Instance = Load()
        assert.is_false(Instance.IsCurrentExpansionRaid(CURRENT_RAID))
        assert.is_false(Instance.IsCurrentExpansionDungeon(CURRENT_DUNGEON))
        assert.is_false(Instance.IsSeasonalMythicDungeon(SEASONAL_DUNGEON, "Seasonal Name"))
        assert.is_false(Instance.IsChallengeModeActive())
        Instance.RefreshCaches()
        assert.is_false(Instance.IsCurrentExpansionRaid(CURRENT_RAID))
    end)
end)
