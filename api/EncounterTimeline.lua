local _, ns = ...

local EncounterTimeline = {}
ns.Api.EncounterTimeline = EncounterTimeline

-- Enum.EncounterTimelineEventSource.Encounter
EncounterTimeline.EVENT_SOURCE_ENCOUNTER = 0
-- Enum.EncounterTimelineEventState.Active
EncounterTimeline.EVENT_STATE_ACTIVE = 0

---Current state of a timeline event, or nil when the API is unavailable.
---@param eventID number
---@return number|nil
function EncounterTimeline.GetEventState(eventID)
    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventState) == "function" then
        return C_EncounterTimeline.GetEventState(eventID)
    end
    return nil
end

---Calls `callback` when an encounter-timeline event is queued.
---@param callback fun(eventInfo: table)
---@return fun()  Unsubscribe.
function EncounterTimeline.OnEventAdded(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_TIMELINE_EVENT_ADDED", callback)
end
