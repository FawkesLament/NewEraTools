-- Test-only event simulation for the real api/Encounter.lua table.
-- helpers/loader.lua executes the production file, then calls this.
-- WhileIn, OnStart, OnEnd, OnWarning, and IsInProgress stay in production.
return function(encounter, gameEvents)
    assert(type(encounter.WhileIn) == "function", "Encounter fake expects the real WhileIn")
    assert(type(gameEvents.Fire) == "function", "Encounter fake expects GameEvents.Fire")

    function encounter.FireStart(encounterID, encounterName, difficultyID, groupSize)
        gameEvents.Fire("ENCOUNTER_START", encounterID, encounterName, difficultyID, groupSize)
    end

    function encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
        gameEvents.Fire("ENCOUNTER_END", encounterID, encounterName, difficultyID, groupSize, success)
    end

    function encounter.FireWarning(warningInfo)
        gameEvents.Fire("ENCOUNTER_WARNING", warningInfo)
    end
end
