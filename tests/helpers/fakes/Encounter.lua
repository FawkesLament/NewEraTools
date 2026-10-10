return function()
    local Encounter = {
        inProgress = false,
        startCallbacks = {},
        endCallbacks = {},
    }

    function Encounter.IsInProgress()
        return Encounter.inProgress == true
    end

    function Encounter.OnStart(callback)
        table.insert(Encounter.startCallbacks, callback)
    end

    function Encounter.OnEnd(callback)
        table.insert(Encounter.endCallbacks, callback)
    end

    function Encounter.FireStart(encounterID, encounterName, difficultyID, groupSize)
        Encounter.inProgress = true
        for _, callback in ipairs(Encounter.startCallbacks) do
            callback(encounterID, encounterName, difficultyID, groupSize)
        end
    end

    function Encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
        Encounter.inProgress = false
        for _, callback in ipairs(Encounter.endCallbacks) do
            callback(encounterID, encounterName, difficultyID, groupSize, success)
        end
    end

    return Encounter
end
