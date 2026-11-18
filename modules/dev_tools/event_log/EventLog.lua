local _, ns = ...
local Client = ns.Api.Client
local Encounter = ns.Api.Encounter
local GameEvents = ns.Api.GameEvents
local Secrets = ns.Api.Secrets
local Timer = ns.Api.Timer
local Unit = ns.Api.Unit
local Util = ns.Util

local SECRET_TEXT = "<secret>"

local LOGGED_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_FLAGS",
    "UNIT_FACTION",
    "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED",
    "ENCOUNTER_WARNING",
    "ENCOUNTER_STATE_CHANGED",
    "INSTANCE_ENCOUNTER_ADD_TIMER",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "INSTANCE_ENCOUNTER_OBJECTIVE_COMPLETE",
    "INSTANCE_ENCOUNTER_OBJECTIVE_START",
    "INSTANCE_ENCOUNTER_OBJECTIVE_UPDATE",
}

local ENEMY_UNIT_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    NAME_PLATE_UNIT_ADDED = true,
    NAME_PLATE_UNIT_REMOVED = true,
    UNIT_FLAGS = true,
    UNIT_FACTION = true,
}

local MAX_LOGS_MIN = 1
local MAX_LOGS_MAX = 20
local MAX_LOGS_STEP = 1

---@class EventLog: Module
---@field OnSavedLogChanged fun(self: EventLog)|nil  Defined by the UI; called when the saved log list changes.
local EventLog = ns.Modules.New("EventLog", {
    defaults = {
        enabled = false,
        maxLogs = 1,
    },
})

EventLog.MAX_LOGS_MIN = MAX_LOGS_MIN
EventLog.MAX_LOGS_MAX = MAX_LOGS_MAX
EventLog.MAX_LOGS_STEP = MAX_LOGS_STEP

---@class EventLogSaved
---@field id integer  Unique for the session; stable while the log is kept.
---@field encounterID number
---@field encounterName string|nil  Nil when the game did not provide a readable name.
---@field startedAt string  Local wall-clock start, `YYYY-MM-DDTHH:MM:SS`.
---@field duration number|nil  Seconds; nil while the encounter is still being recorded.

---@class EventLogRecord: EventLogSaved
---@field lines string[]

---Newest first.
---@type EventLogRecord[]
local logs = {}
local nextLogID = 1
local listening = false
---@type number|nil
local encounterStart
---@type EventLogRecord|nil
local recording
---@type ResourceScope|nil
local sessionScope

local function NotifySavedLogChanged()
    if EventLog.OnSavedLogChanged then
        EventLog:OnSavedLogChanged()
    end
end

---@param value any
---@return number
local function ClockField(value)
    return tonumber(value) or 0
end

---@return string
local function FormatStartTime()
    local clock = Client.GetCalendarTime()
    if type(clock) ~= "table" then
        return "0000-00-00T00:00:00"
    end
    return string.format(
        "%04d-%02d-%02dT%02d:%02d:%02d",
        ClockField(clock.year),
        ClockField(clock.month),
        ClockField(clock.monthDay),
        ClockField(clock.hour),
        ClockField(clock.minute),
        ClockField(clock.second)
    )
end

---@param a any
---@param b any
---@return boolean
local function KeyLess(a, b)
    local typeA, typeB = type(a), type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

---@param out string[]
---@param value any
---@param seen table
local function AppendSanitized(out, value, seen)
    if Secrets.IsSecret(value) then
        out[#out + 1] = SECRET_TEXT
        return
    end
    if type(value) ~= "table" then
        out[#out + 1] = tostring(value)
        return
    end
    if seen[value] then
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, KeyLess)
    for i = 1, #keys do
        AppendSanitized(out, value[keys[i]], seen)
    end
end

---@return string[]
local function SanitizePayload(...)
    local out = {}
    local seen = {}
    local count = select("#", ...)
    for i = 1, count do
        AppendSanitized(out, (select(i, ...)), seen)
    end
    return out
end

---@param unitToken any
---@return boolean
local function ShouldLogEnemyUnit(unitToken)
    if Secrets.IsSecret(unitToken) then
        return false
    end
    return Unit.IsEnemy(unitToken) == true
end

---@param callback fun(event: string, ...)
---@return fun()
local function SubscribeLoggedEvents(callback)
    local unsubs = {}
    for i = 1, #LOGGED_EVENTS do
        local event = LOGGED_EVENTS[i]
        unsubs[i] = GameEvents.Listen(event, function(...)
            if ENEMY_UNIT_EVENTS[event] and not ShouldLogEnemyUnit(...) then
                return
            end
            callback(event, ...)
        end)
    end
    return function()
        for i = 1, #unsubs do
            unsubs[i]()
        end
    end
end

---Stops recording and stamps the duration on the log being recorded.
---@return boolean  True when a recording was finished.
local function StopSession()
    local scope = sessionScope
    local record = recording
    local startTime = encounterStart
    sessionScope = nil
    encounterStart = nil
    recording = nil
    if scope then
        scope:Dispose()
    end
    if not record or not startTime then
        return false
    end
    record.duration = math.max(Timer.GetTime() - startTime, 0)
    return true
end

local function EndEncounter()
    if StopSession() then
        NotifySavedLogChanged()
    end
end

---Drops the oldest logs beyond `limit`.
---@param limit integer
---@return boolean  True when any log was removed.
local function TrimLogs(limit)
    local trimmed = false
    while #logs > limit do
        logs[#logs] = nil
        trimmed = true
    end
    return trimmed
end

---@param name any
---@return string|nil
local function ReadableName(name)
    if Secrets.IsSecret(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

local function OnLoggedEvent(event, ...)
    local startTime = encounterStart
    local record = recording
    if not startTime or not record then
        return
    end
    local fields = { event, string.format("%.3f", Timer.GetTime() - startTime) }
    local payload = SanitizePayload(...)
    for i = 1, #payload do
        fields[#fields + 1] = payload[i]
    end
    record.lines[#record.lines + 1] = table.concat(fields, " ")
end

---@param encounterID number|nil
---@param encounterName any
local function BeginEncounter(encounterID, encounterName)
    local stopped = StopSession()
    if not EventLog:IsEnabled() then
        if stopped then
            NotifySavedLogChanged()
        end
        return
    end
    ---@type EventLogRecord
    local record = {
        id = nextLogID,
        encounterID = tonumber(encounterID) or 0,
        encounterName = ReadableName(encounterName),
        startedAt = FormatStartTime(),
        lines = {},
    }
    nextLogID = nextLogID + 1
    table.insert(logs, 1, record)
    TrimLogs(EventLog:GetMaxLogs())
    recording = record
    encounterStart = Timer.GetTime()
    local scope = ns.ResourceScope.New()
    sessionScope = scope
    scope:Subscribe(SubscribeLoggedEvents, OnLoggedEvent)
    if sessionScope ~= scope then
        scope:Dispose()
    end
    NotifySavedLogChanged()
end

---@param id integer|nil
---@return EventLogRecord|nil
local function FindLog(id)
    if id == nil then
        return logs[1]
    end
    for i = 1, #logs do
        if logs[i].id == id then
            return logs[i]
        end
    end
    return nil
end

---@return boolean
function EventLog:IsEnabled()
    return self.db.enabled == true
end

---@param enabled boolean
function EventLog:SetEnabled(enabled)
    enabled = enabled == true
    if self.db.enabled == enabled then
        return
    end
    self.db.enabled = enabled
    if not enabled then
        EndEncounter()
    end
end

---How many logs are kept; the oldest is dropped when a new encounter starts with the list full.
---@return integer
function EventLog:GetMaxLogs()
    return Util.Snap(tonumber(self.db.maxLogs) or MAX_LOGS_MIN, MAX_LOGS_MIN, MAX_LOGS_MAX, MAX_LOGS_STEP)
end

---Lowering the limit drops the oldest logs right away.
---@param value number
function EventLog:SetMaxLogs(value)
    local limit = Util.Snap(tonumber(value) or MAX_LOGS_MIN, MAX_LOGS_MIN, MAX_LOGS_MAX, MAX_LOGS_STEP)
    self.db.maxLogs = limit
    if TrimLogs(limit) then
        NotifySavedLogChanged()
    end
end

---Saved logs, newest first. The returned entries are copies.
---@return EventLogSaved[]
function EventLog:GetSavedLogs()
    local out = {}
    for i = 1, #logs do
        local record = logs[i]
        out[i] = {
            id = record.id,
            encounterID = record.encounterID,
            encounterName = record.encounterName,
            startedAt = record.startedAt,
            duration = record.duration,
        }
    end
    return out
end

---Lines of a saved log. Empty when the log does not exist.
---@param id integer|nil  Defaults to the newest log.
---@return string[]
function EventLog:GetLines(id)
    local record = FindLog(id)
    return record and record.lines or {}
end

---Log lines joined for the viewer, or nil when the log does not exist.
---@param id integer|nil  Defaults to the newest log.
---@return string|nil
function EventLog:GetLogText(id)
    local record = FindLog(id)
    if not record then
        return nil
    end
    return table.concat(record.lines, "\n")
end

---Registers encounter start/end listeners once. Called from OnEnable.
function EventLog:StartListening()
    if listening then
        return
    end
    listening = true
    Encounter.OnStart(BeginEncounter)
    Encounter.OnEnd(EndEncounter)
end
