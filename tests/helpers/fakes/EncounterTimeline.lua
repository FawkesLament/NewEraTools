return function()
    local EncounterTimeline = {
        EVENT_SOURCE_ENCOUNTER = 0,
        EVENT_STATE_ACTIVE = 0,
        eventStates = {},
        eventAddedCallbacks = {},
    }

    ---@param eventID number
    ---@return number|nil
    function EncounterTimeline.GetEventState(eventID)
        return EncounterTimeline.eventStates[eventID]
    end

    ---@param callback fun(eventInfo: table)
    ---@return fun()
    function EncounterTimeline.OnEventAdded(callback)
        table.insert(EncounterTimeline.eventAddedCallbacks, callback)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            for index, candidate in ipairs(EncounterTimeline.eventAddedCallbacks) do
                if candidate == callback then
                    table.remove(EncounterTimeline.eventAddedCallbacks, index)
                    return
                end
            end
        end
    end

    ---Test helper: whether any OnEventAdded listeners remain.
    ---@return boolean
    function EncounterTimeline.HasEventAddedListener()
        return #EncounterTimeline.eventAddedCallbacks > 0
    end

    ---Test helper: set the state returned by GetEventState.
    ---@param eventID number
    ---@param state number|nil
    function EncounterTimeline.SetEventStateForTests(eventID, state)
        EncounterTimeline.eventStates[eventID] = state
    end

    ---Test helper: fire ENCOUNTER_TIMELINE_EVENT_ADDED.
    ---@param eventInfo table
    function EncounterTimeline.FireEventAdded(eventInfo)
        local list = EncounterTimeline.eventAddedCallbacks
        for i = 1, #list do
            local callback = list[i]
            if callback then
                callback(eventInfo)
            end
        end
    end

    return EncounterTimeline
end
