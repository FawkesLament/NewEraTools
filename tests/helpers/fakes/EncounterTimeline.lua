-- Test-only event simulation for the real api/EncounterTimeline.lua table.
-- helpers/loader.lua executes the production file, then calls this.
-- OnEventAdded stays in production, including its source and active-state filter.
return function(timeline, gameEvents)
    assert(type(timeline.OnEventAdded) == "function", "EncounterTimeline fake expects the real OnEventAdded")
    assert(type(gameEvents.Fire) == "function", "EncounterTimeline fake expects GameEvents.Fire")

    local states = {}

    ---@param eventID number
    ---@return number|nil
    function timeline.GetEventState(eventID)
        return states[eventID]
    end

    ---Test helper: set the state returned by GetEventState.
    ---@param eventID number
    ---@param state number|nil
    function timeline.SetEventStateForTests(eventID, state)
        states[eventID] = state
    end

    ---Test helper: whether any OnEventAdded listeners remain.
    ---@return boolean
    function timeline.HasEventAddedListener()
        local list = gameEvents.handlers and gameEvents.handlers["ENCOUNTER_TIMELINE_EVENT_ADDED"]
        return list ~= nil and #list > 0
    end

    ---Test helper: fire ENCOUNTER_TIMELINE_EVENT_ADDED.
    ---@param eventInfo table|nil
    function timeline.FireEventAdded(eventInfo)
        gameEvents.Fire("ENCOUNTER_TIMELINE_EVENT_ADDED", eventInfo)
    end
end
