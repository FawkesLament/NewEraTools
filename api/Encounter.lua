local _, ns = ...

local Encounter = {}
ns.Api.Encounter = Encounter

---Whether a boss encounter is currently in progress in the instance.
---@return boolean
function Encounter.IsInProgress()
    if C_InstanceEncounter and type(C_InstanceEncounter.IsEncounterInProgress) == "function" then
        return C_InstanceEncounter.IsEncounterInProgress() == true
    end
    return false
end

---Calls `callback` when any encounter starts.
---@param callback fun(encounterID: number, encounterName: string, difficultyID: number, groupSize: number)
function Encounter.OnStart(callback)
    ns.Api.GameEvents.Listen("ENCOUNTER_START", callback)
end

---Calls `callback` when any encounter ends.
---@param callback fun(encounterID: number, encounterName: string, difficultyID: number, groupSize: number, success: number)
function Encounter.OnEnd(callback)
    ns.Api.GameEvents.Listen("ENCOUNTER_END", callback)
end
