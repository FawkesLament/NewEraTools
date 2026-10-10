local _, ns = ...

local Encounter = {}
ns.Api.Encounter = Encounter

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
