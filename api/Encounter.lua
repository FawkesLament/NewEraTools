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
---@return fun()  Unsubscribe.
function Encounter.OnStart(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_START", callback)
end

---Calls `callback` when any encounter ends.
---@param callback fun(encounterID: number, encounterName: string, difficultyID: number, groupSize: number, success: number)
---@return fun()  Unsubscribe.
function Encounter.OnEnd(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_END", callback)
end

---Calls `callback` with the encounter warning info table (severity/duration are plain; text may be secret).
---@param callback fun(warningInfo: table)
---@return fun()  Unsubscribe.
function Encounter.OnWarning(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_WARNING", callback)
end

---@class EncounterWhileIn
---@field SetEnabled fun(self: EncounterWhileIn, enabled: boolean)  Feature gate; inactive when false.
---@field IsEnabled fun(self: EncounterWhileIn): boolean
---@field IsInside fun(self: EncounterWhileIn): boolean  True between matching ENCOUNTER_START and END.
---@field IsActive fun(self: EncounterWhileIn): boolean  True while `setup`'s cleanup has not run yet.

---Runs `setup` while inside `encounterID` (and while enabled). `setup` must return a cleanup function;
---that cleanup always runs when the fight ends or when disabled — so subscriptions cannot outlive the pull.
---@param encounterID number
---@param setup fun(): (fun()|nil)
---@return EncounterWhileIn
function Encounter.WhileIn(encounterID, setup)
    assert(type(encounterID) == "number", "Encounter.WhileIn requires encounterID")
    assert(type(setup) == "function", "Encounter.WhileIn requires setup")

    local enabled = true
    local inside = false
    ---@type fun()|nil
    local cleanup = nil

    local function Sync()
        local want = enabled and inside
        if want then
            if cleanup then
                return
            end
            cleanup = setup() or function() end
            return
        end
        if not cleanup then
            return
        end
        local leave = cleanup
        cleanup = nil
        leave()
    end

    Encounter.OnStart(function(id)
        if id ~= encounterID then
            return
        end
        inside = true
        Sync()
    end)
    Encounter.OnEnd(function(id)
        if id ~= encounterID then
            return
        end
        inside = false
        Sync()
    end)

    ---@type EncounterWhileIn
    local handle = {}

    function handle:SetEnabled(value)
        enabled = value == true
        Sync()
    end

    function handle:IsEnabled()
        return enabled
    end

    function handle:IsInside()
        return inside
    end

    function handle:IsActive()
        return cleanup ~= nil
    end

    return handle
end
