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

---Encounter-sourced bars that are already active. Script and edit-mode bars are ignored.
---@param eventInfo table|nil
---@return boolean
local function IsValidTimelineEvent(eventInfo)
    if type(eventInfo) ~= "table" then
        return false
    end
    if eventInfo.source ~= EncounterTimeline.EVENT_SOURCE_ENCOUNTER then
        return false
    end
    return EncounterTimeline.GetEventState(eventInfo.id) == EncounterTimeline.EVENT_STATE_ACTIVE
end

---Calls `callback` when an encounter-timeline event is queued.
---By default the callback only runs for an active encounter-sourced bar (`source` and `id` state).
---@param callback fun(eventInfo: table)
---@return fun()  Unsubscribe.
function EncounterTimeline.OnEventAdded(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_TIMELINE_EVENT_ADDED", function(eventInfo)
        if not IsValidTimelineEvent(eventInfo) then
            return
        end
        callback(eventInfo)
    end)
end
