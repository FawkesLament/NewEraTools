local _, ns = ...

local EncounterTimeline = {}
ns.Api.EncounterTimeline = EncounterTimeline

-- Enum.EncounterTimelineEventSource.Encounter
EncounterTimeline.EVENT_SOURCE_ENCOUNTER = 0
-- Enum.EncounterTimelineEventState.Active
EncounterTimeline.EVENT_STATE_ACTIVE = 0

---Current timeline event IDs, or an empty list when the API is unavailable.
---@return number[]
function EncounterTimeline.GetEventList()
    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventList) == "function" then
        local list = C_EncounterTimeline.GetEventList()
        if type(list) == "table" then
            return list
        end
    end
    return {}
end

---Timeline event payload for `eventID`, or nil when missing / unavailable.
---@param eventID number
---@return table|nil
function EncounterTimeline.GetEventInfo(eventID)
    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventInfo) == "function" then
        return C_EncounterTimeline.GetEventInfo(eventID)
    end
    return nil
end

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

---Calls `callback` for every ENCOUNTER_TIMELINE_EVENT_ADDED payload.
---Does not filter on source or state; callers decide what to ignore.
---@param callback fun(eventInfo: table|nil)
---@return fun()  Unsubscribe.
function EncounterTimeline.OnAnyEventAdded(callback)
    return ns.Api.GameEvents.Listen("ENCOUNTER_TIMELINE_EVENT_ADDED", callback)
end

---Calls `callback` when an encounter-timeline event is queued.
---By default the callback only runs for an active encounter-sourced bar (`source` and `id` state).
---@param callback fun(eventInfo: table)
---@return fun()  Unsubscribe.
function EncounterTimeline.OnEventAdded(callback)
    return EncounterTimeline.OnAnyEventAdded(function(eventInfo)
        if not IsValidTimelineEvent(eventInfo) then
            return
        end
        callback(eventInfo)
    end)
end
