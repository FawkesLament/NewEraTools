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

---xpcall handler: runs before the stack unwinds, so the trace still shows where `setup` failed.
---@param err any
---@return any
local function AttachTraceback(err)
    if type(err) ~= "string" then
        return err
    end
    if debugstack then
        return err .. "\n" .. debugstack(2)
    end
    return debug.traceback(err, 2)
end

---@class EncounterWhileIn
---@field SetEnabled fun(self: EncounterWhileIn, enabled: boolean)  Feature gate; inactive when false.
---@field IsEnabled fun(self: EncounterWhileIn): boolean
---@field IsInside fun(self: EncounterWhileIn): boolean  True between matching ENCOUNTER_START and END.
---@field IsActive fun(self: EncounterWhileIn): boolean  True from the moment this activation's scope is installed until that scope is disposed.

---Runs `setup` while inside `encounterID` (and while enabled). `setup` receives a `ResourceScope`
---and may also return a cleanup function; both are disposed when the fight ends or when disabled.
---`setup` receives the `difficultyID` from the matching ENCOUNTER_START (and again if re-enabled mid-fight).
---`IsActive` is true as soon as the activation scope is installed, including while `setup` is running,
---and false after that scope is disposed. A failed or superseded `setup` is not left active.
---@param encounterID number
---@param setup fun(difficultyID: number, scope: ResourceScope): (fun()|nil)
---@return EncounterWhileIn
function Encounter.WhileIn(encounterID, setup)
    assert(type(encounterID) == "number", "Encounter.WhileIn requires encounterID")
    assert(type(setup) == "function", "Encounter.WhileIn requires setup")

    local enabled = true
    local inside = false
    local difficultyID = 0
    ---@type ResourceScope|nil
    local activeScope = nil

    local function DisposeActive()
        local scope = activeScope
        if not scope then
            return
        end
        activeScope = nil
        scope:Dispose()
    end

    local function Activate()
        local scope = ns.ResourceScope.New()
        activeScope = scope

        local ok, result = xpcall(function()
            return setup(difficultyID, scope)
        end, AttachTraceback)
        if not ok then
            if activeScope == scope then
                activeScope = nil
            end
            scope:Dispose()
            -- Level 0: the message already carries the original location and trace.
            error(result, 0)
        end

        if type(result) == "function" then
            scope:Add(result)
        end

        if activeScope ~= scope then
            scope:Dispose()
        end
    end

    local function Sync()
        local want = enabled and inside
        if want then
            if activeScope then
                return
            end
            Activate()
            return
        end
        DisposeActive()
    end

    Encounter.OnStart(function(id, _, startDifficultyID)
        if id ~= encounterID then
            return
        end
        difficultyID = startDifficultyID or 0
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
        return activeScope ~= nil
    end

    return handle
end
