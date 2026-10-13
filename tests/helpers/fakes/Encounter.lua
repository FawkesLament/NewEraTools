return function()
    local Encounter = {
        inProgress = false,
        startCallbacks = {},
        endCallbacks = {},
        warningCallbacks = {},
    }

    local function AddCallback(list, callback)
        table.insert(list, callback)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            for index, candidate in ipairs(list) do
                if candidate == callback then
                    table.remove(list, index)
                    return
                end
            end
        end
    end

    function Encounter.IsInProgress()
        return Encounter.inProgress == true
    end

    function Encounter.OnStart(callback)
        return AddCallback(Encounter.startCallbacks, callback)
    end

    function Encounter.OnEnd(callback)
        return AddCallback(Encounter.endCallbacks, callback)
    end

    function Encounter.OnWarning(callback)
        return AddCallback(Encounter.warningCallbacks, callback)
    end

    function Encounter.FireStart(encounterID, encounterName, difficultyID, groupSize)
        Encounter.inProgress = true
        local list = Encounter.startCallbacks
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(encounterID, encounterName, difficultyID, groupSize)
            end
        end
    end

    function Encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
        Encounter.inProgress = false
        local list = Encounter.endCallbacks
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(encounterID, encounterName, difficultyID, groupSize, success)
            end
        end
    end

    function Encounter.FireWarning(warningInfo)
        local list = Encounter.warningCallbacks
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(warningInfo)
            end
        end
    end

    ---Mirrors api/Encounter.lua WhileIn against this fake's OnStart/OnEnd.
    function Encounter.WhileIn(encounterID, setup)
        assert(type(encounterID) == "number", "Encounter.WhileIn requires encounterID")
        assert(type(setup) == "function", "Encounter.WhileIn requires setup")

        local enabled = true
        local inside = false
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

    return Encounter
end
