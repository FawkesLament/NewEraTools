return function()
    local Instance = {
        DIFFICULTY_MYTHIC_KEYSTONE = 8,
        DIFFICULTY_MYTHIC_DUNGEON = 23,
        info = {
            name = "",
            instanceType = "none",
            difficultyID = 0,
            instanceID = 0,
        },
        challengeModeActive = false,
        currentRaidIds = {},
        currentDungeonIds = {},
        seasonalMythicIds = {},
        seasonalMythicNames = {},
        enteringWorldCallbacks = {},
        challengeModeStartCallbacks = {},
        challengeModeCompletedCallbacks = {},
        challengeModeResetCallbacks = {},
    }

    function Instance.GetInfo()
        return {
            name = Instance.info.name,
            instanceType = Instance.info.instanceType,
            difficultyID = Instance.info.difficultyID,
            instanceID = Instance.info.instanceID,
        }
    end

    function Instance.IsChallengeModeActive()
        return Instance.challengeModeActive == true
    end

    function Instance.IsCurrentExpansionRaid(instanceID)
        return Instance.currentRaidIds[instanceID] == true
    end

    function Instance.IsCurrentExpansionDungeon(instanceID)
        return Instance.currentDungeonIds[instanceID] == true
    end

    function Instance.IsSeasonalMythicDungeon(instanceID, instanceName)
        if Instance.seasonalMythicIds[instanceID] then
            return true
        end
        return type(instanceName) == "string" and Instance.seasonalMythicNames[instanceName] == true
    end

    function Instance.IsMythicDungeonDifficulty(difficultyID)
        return difficultyID == Instance.DIFFICULTY_MYTHIC_DUNGEON
            or difficultyID == Instance.DIFFICULTY_MYTHIC_KEYSTONE
    end

    function Instance.RefreshCaches() end

    function Instance.OnEnteringWorld(callback)
        table.insert(Instance.enteringWorldCallbacks, callback)
    end

    function Instance.OnChallengeModeStart(callback)
        table.insert(Instance.challengeModeStartCallbacks, callback)
    end

    function Instance.OnChallengeModeCompleted(callback)
        table.insert(Instance.challengeModeCompletedCallbacks, callback)
    end

    function Instance.OnChallengeModeReset(callback)
        table.insert(Instance.challengeModeResetCallbacks, callback)
    end

    function Instance.FireEnteringWorld()
        for _, callback in ipairs(Instance.enteringWorldCallbacks) do
            callback()
        end
    end

    function Instance.FireChallengeModeStart()
        Instance.challengeModeActive = true
        for _, callback in ipairs(Instance.challengeModeStartCallbacks) do
            callback()
        end
    end

    function Instance.FireChallengeModeCompleted()
        Instance.challengeModeActive = false
        for _, callback in ipairs(Instance.challengeModeCompletedCallbacks) do
            callback()
        end
    end

    function Instance.FireChallengeModeReset()
        Instance.challengeModeActive = false
        for _, callback in ipairs(Instance.challengeModeResetCallbacks) do
            callback()
        end
    end

    return Instance
end
