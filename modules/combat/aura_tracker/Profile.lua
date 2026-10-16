local _, ns = ...
local L = ns.L

---@class AuraTrackerProfileBucket
---@field count integer
---@field total number
---@field max number

---@class AuraTrackerProfile
---@field Start fun(): number
---@field Stop fun(name: string, started: number)
---@field Inc fun(name: string)
---@field EventKey fun(event: string, unit: string|nil): string
---@field IsRecording fun(): boolean
---@field Record fun()
---@field Reset fun()
---@field Report fun(): string
---@field SetNoteProvider fun(provider: fun(): string|nil)
---@field Mark fun(name: string, value: number)
local Profile = {}
ns.AuraTrackerProfile = Profile

local now = debugprofilestop or function()
    return 0
end

---@type table<string, AuraTrackerProfileBucket>
local buckets = {}

---Latest scalar for a name, such as a scroll-offset change. Not a duration.
---@type table<string, number>
local marks = {}

---Off until `/neatprof`. A UI reload clears this with the rest of the addon state.
local recording = false

---@type fun(): string|nil
local noteProvider

local EVENT_KEYS = {
    PLAYER_TARGET_CHANGED = "event.PLAYER_TARGET_CHANGED",
    PLAYER_FOCUS_CHANGED = "event.PLAYER_FOCUS_CHANGED",
    UNIT_FACTION = {
        player = "event.UNIT_FACTION.player",
        target = "event.UNIT_FACTION.target",
        focus = "event.UNIT_FACTION.focus",
    },
    UNIT_FLAGS = {
        player = "event.UNIT_FLAGS.player",
        target = "event.UNIT_FLAGS.target",
        focus = "event.UNIT_FLAGS.focus",
    },
}

---@param name string
---@return AuraTrackerProfileBucket
local function Bucket(name)
    local bucket = buckets[name]
    if bucket then
        return bucket
    end
    bucket = { count = 0, total = 0, max = 0 }
    buckets[name] = bucket
    return bucket
end

---@return boolean
function Profile.IsRecording()
    return recording
end

---Begins collecting samples. Later calls keep the current buckets.
function Profile.Record()
    recording = true
end

---Milliseconds timestamp. Zero when the client has no profiler clock, or while recording is off.
---@return number
function Profile.Start()
    if not recording then
        return 0
    end
    return now()
end

---Records one sample. `started` comes from `Start` on this same call.
---@param name string
---@param started number
function Profile.Stop(name, started)
    if not recording then
        return
    end
    local elapsed = now() - started
    local bucket = Bucket(name)
    bucket.count = bucket.count + 1
    bucket.total = bucket.total + elapsed
    if elapsed > bucket.max then
        bucket.max = elapsed
    end
end

---Counts a call without a duration. Use for events whose work is timed separately.
---@param name string
function Profile.Inc(name)
    if not recording then
        return
    end
    local bucket = Bucket(name)
    bucket.count = bucket.count + 1
end

---Stable counter name for a unit-context event. No allocation on the hot path.
---@param event string
---@param unit string|nil
---@return string
function Profile.EventKey(event, unit)
    local entry = EVENT_KEYS[event]
    if type(entry) == "table" then
        return entry[unit] or "event.other"
    end
    return entry or "event.other"
end

---Records the latest value for `name`. Overwrites the previous mark. No-op while recording is off.
---@param name string
---@param value number
function Profile.Mark(name, value)
    if not recording or type(value) ~= "number" then
        return
    end
    marks[name] = value
end

function Profile.Reset()
    buckets = {}
    marks = {}
end

---@param provider fun(): string|nil
function Profile.SetNoteProvider(provider)
    noteProvider = provider
end

---Aggregated samples as one block of text. Call from a slash command, never from a hot callback.
---@return string
function Profile.Report()
    local names = {}
    for name in pairs(buckets) do
        names[#names + 1] = name
    end
    local markNames = {}
    for name in pairs(marks) do
        markNames[#markNames + 1] = name
    end
    if #names == 0 and #markNames == 0 then
        return L.AURA_TRACKER_PROFILE_EMPTY
    end
    table.sort(names)
    table.sort(markNames)
    local lines = { L.AURA_TRACKER_PROFILE_HEADER }
    if noteProvider then
        local note = noteProvider()
        if type(note) == "string" and note ~= "" then
            lines[#lines + 1] = note
        end
    end
    for index = 1, #names do
        local name = names[index]
        local bucket = buckets[name]
        lines[#lines + 1] = string.format(L.AURA_TRACKER_PROFILE_ROW, name, bucket.count, bucket.total, bucket.max)
    end
    for index = 1, #markNames do
        local name = markNames[index]
        lines[#lines + 1] = string.format(L.AURA_TRACKER_PROFILE_MARK, name, marks[name])
    end
    return table.concat(lines, "\n")
end
