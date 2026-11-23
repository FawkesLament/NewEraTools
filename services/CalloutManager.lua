local _, ns = ...
local Timer = ns.Api.Timer

local DEFAULT_DURATION = 10

local CalloutManager = {}
ns.CalloutManager = CalloutManager

---@class CalloutManagerShowOptions
---@field source string  Caller id; ClearSource only affects this source.
---@field key string|nil  Stack identity. Defaults to source. Same key upserts; different keys stack.
---@field text any  Opaque message body.
---@field expiresAt number|nil  Absolute Timer.GetTime() when the message hides. Preferred over duration.
---@field duration number|nil  Seconds from now; used when expiresAt is omitted.
---@field appendTimer boolean|nil  When true, the HUD appends a countdown.
---@field wrap string|nil  Optional SetFormattedText pattern with one `%s` for the message body.

---@class CalloutManagerMessage
---@field source string
---@field key string
---@field text any
---@field expiresAt number
---@field appendTimer boolean
---@field wrap string|nil

---@class CalloutManagerHandle
---@field Dismiss fun(self: CalloutManagerHandle)

local nextId = 0
local nextOrder = 0
---@type { id: integer, order: integer, source: string, key: string, text: any, expiresAt: number, appendTimer: boolean, wrap: string|nil }[]
local entries = {}
local listeners = {}

local function Notify()
    for index = 1, #listeners do
        listeners[index]()
    end
end

---@param options CalloutManagerShowOptions
---@return string
local function EntryKey(options)
    local key = options.key
    if key == nil then
        return options.source
    end
    assert(type(key) == "string" and key ~= "", "CalloutManager.Show key must be a non-empty string")
    return key
end

---@param entry { source: string, key: string, text: any, expiresAt: number, appendTimer: boolean, wrap: string|nil }
---@return CalloutManagerMessage
local function PublicCopy(entry)
    return {
        source = entry.source,
        key = entry.key,
        text = entry.text,
        expiresAt = entry.expiresAt,
        appendTimer = entry.appendTimer,
        wrap = entry.wrap,
    }
end

local function SortEntries()
    table.sort(entries, function(a, b)
        if a.expiresAt ~= b.expiresAt then
            return a.expiresAt < b.expiresAt
        end
        return a.order < b.order
    end)
end

---@param key string
---@return integer|nil
---@return table|nil
local function FindByKey(key)
    for index = 1, #entries do
        local entry = entries[index]
        if entry.key == key then
            return index, entry
        end
    end
end

---@param id integer
---@return integer|nil
local function FindIndexById(id)
    for index = 1, #entries do
        if entries[index].id == id then
            return index
        end
    end
end

---@return table|nil
local function Primary()
    if #entries == 0 then
        return nil
    end
    SortEntries()
    return entries[1]
end

local function HideId(id)
    local index = FindIndexById(id)
    if not index then
        return
    end
    table.remove(entries, index)
    Notify()
end

---@param id integer
---@return CalloutManagerHandle
local function NewHandle(id)
    local handle = {}
    function handle:Dismiss()
        HideId(id)
    end
    return handle
end

---Shows `options.text` until it expires or is dismissed. Same `key` (or `source`) upserts; other keys stack.
---@param options CalloutManagerShowOptions
---@return CalloutManagerHandle
function CalloutManager.Show(options)
    assert(type(options) == "table", "CalloutManager.Show requires options")
    assert(type(options.source) == "string" and options.source ~= "", "CalloutManager.Show requires source")
    assert(options.text ~= nil, "CalloutManager.Show requires text")
    if options.wrap ~= nil then
        assert(type(options.wrap) == "string", "CalloutManager.Show wrap must be a string")
    end

    local now = Timer.GetTime()
    local expiresAt = options.expiresAt
    if expiresAt == nil then
        local duration = options.duration or DEFAULT_DURATION
        assert(type(duration) == "number", "CalloutManager duration must be a number")
        expiresAt = now + duration
    else
        assert(type(expiresAt) == "number", "CalloutManager expiresAt must be a number")
    end

    local key = EntryKey(options)
    nextId = nextId + 1
    local id = nextId
    if expiresAt <= now then
        local index = FindByKey(key)
        if index then
            table.remove(entries, index)
            Notify()
        end
        return NewHandle(id)
    end

    local _, existing = FindByKey(key)
    if existing then
        existing.id = id
        existing.source = options.source
        existing.text = options.text
        existing.expiresAt = expiresAt
        existing.appendTimer = options.appendTimer == true
        existing.wrap = options.wrap
    else
        nextOrder = nextOrder + 1
        entries[#entries + 1] = {
            id = id,
            order = nextOrder,
            source = options.source,
            key = key,
            text = options.text,
            expiresAt = expiresAt,
            appendTimer = options.appendTimer == true,
            wrap = options.wrap,
        }
    end
    Notify()
    Timer.After(expiresAt - now, function()
        HideId(id)
    end)
    return NewHandle(id)
end

---Hides messages that belong to `source`. Other sources are left alone.
---@param source string
function CalloutManager.ClearSource(source)
    assert(type(source) == "string" and source ~= "", "CalloutManager.ClearSource requires source")
    local write = 1
    local removed = false
    for index = 1, #entries do
        local entry = entries[index]
        if entry.source == source then
            removed = true
        else
            entries[write] = entry
            write = write + 1
        end
    end
    for index = write, #entries do
        entries[index] = nil
    end
    if removed then
        Notify()
    end
end

---The soonest-expiring message, or nil when nothing is shown.
---@return CalloutManagerMessage|nil
function CalloutManager.GetCurrent()
    local entry = Primary()
    if not entry then
        return nil
    end
    return PublicCopy(entry)
end

---Active messages, soonest expiry first.
---@return CalloutManagerMessage[]
function CalloutManager.GetActive()
    SortEntries()
    local active = {}
    for index = 1, #entries do
        active[index] = PublicCopy(entries[index])
    end
    return active
end

---The current message body, or nil when nothing is shown.
---@return any|nil
function CalloutManager.GetDisplayed()
    local entry = Primary()
    return entry and entry.text or nil
end

---Absolute Timer.GetTime() when the current message hides, or nil when nothing is shown.
---@return number|nil
function CalloutManager.GetExpiresAt()
    local entry = Primary()
    return entry and entry.expiresAt or nil
end

---Whether the HUD should append a countdown to the current message.
---@return boolean
function CalloutManager.GetAppendTimer()
    local entry = Primary()
    return entry ~= nil and entry.appendTimer == true
end

---Subscribes to show, replace, dismiss, and expire. Returns an unsubscribe function.
---@param callback fun()
---@return fun()
function CalloutManager.OnChanged(callback)
    assert(type(callback) == "function", "CalloutManager.OnChanged requires a callback")
    table.insert(listeners, callback)
    local removed = false
    return function()
        if removed then
            return
        end
        removed = true
        for index, candidate in ipairs(listeners) do
            if candidate == callback then
                table.remove(listeners, index)
                return
            end
        end
    end
end
