return function()
    local Encounter = {
        startCallbacks = {},
        endCallbacks = {},
    }

    function Encounter.OnStart(callback)
        table.insert(Encounter.startCallbacks, callback)
    end

    function Encounter.OnEnd(callback)
        table.insert(Encounter.endCallbacks, callback)
    end

    function Encounter.FireStart(encounterID, encounterName, difficultyID, groupSize)
        for _, callback in ipairs(Encounter.startCallbacks) do
            callback(encounterID, encounterName, difficultyID, groupSize)
        end
    end

    function Encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
        for _, callback in ipairs(Encounter.endCallbacks) do
            callback(encounterID, encounterName, difficultyID, groupSize, success)
        end
    end

    return Encounter
end
