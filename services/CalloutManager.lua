local _, ns = ...
local Timer = ns.Api.Timer

local DEFAULT_DURATION = 10

local CalloutManager = {}
ns.CalloutManager = CalloutManager

---@class CalloutManagerShowOptions
---@field source string  Caller id; ClearSource only affects this source.
---@field text any  Opaque message body.
---@field expiresAt number|nil  Absolute Timer.GetTime() when the message hides. Preferred over duration.
---@field duration number|nil  Seconds from now; used when expiresAt is omitted.
---@field appendTimer boolean|nil  When true, the HUD appends a countdown.
---@field wrap string|nil  Optional SetFormattedText pattern with one `%s` for the message body.

---@class CalloutManagerMessage
---@field source string
---@field text any
---@field expiresAt number
---@field appendTimer boolean
---@field wrap string|nil

---@class CalloutManagerHandle
---@field Dismiss fun(self: CalloutManagerHandle)

local nextId = 0
---@type { id: integer, source: string, text: any, expiresAt: number, appendTimer: boolean, wrap: string|nil }|nil
local current = nil
local listeners = {}

local function Notify()
    for index = 1, #listeners do
        listeners[index]()
    end
end

local function HideId(id)
    if current == nil or current.id ~= id then
        return
    end
    current = nil
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

---Shows `options.text` until it expires or is dismissed. Replaces any current message immediately.
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

    nextId = nextId + 1
    local id = nextId
    if expiresAt <= now then
        if current ~= nil then
            current = nil
            Notify()
        end
        return NewHandle(id)
    end

    current = {
        id = id,
        source = options.source,
        text = options.text,
        expiresAt = expiresAt,
        appendTimer = options.appendTimer == true,
        wrap = options.wrap,
    }
    Notify()
    Timer.After(expiresAt - now, function()
        HideId(id)
    end)
    return NewHandle(id)
end

---Hides the current message when it belongs to `source`. Other sources are left alone.
---@param source string
function CalloutManager.ClearSource(source)
    assert(type(source) == "string" and source ~= "", "CalloutManager.ClearSource requires source")
    if current == nil or current.source ~= source then
        return
    end
    current = nil
    Notify()
end

---The current message, or nil when nothing is shown.
---@return CalloutManagerMessage|nil
function CalloutManager.GetCurrent()
    if current == nil then
        return nil
    end
    return {
        source = current.source,
        text = current.text,
        expiresAt = current.expiresAt,
        appendTimer = current.appendTimer,
        wrap = current.wrap,
    }
end

---The current message body, or nil when nothing is shown.
---@return any|nil
function CalloutManager.GetDisplayed()
    if current == nil then
        return nil
    end
    return current.text
end

---Absolute Timer.GetTime() when the current message hides, or nil when nothing is shown.
---@return number|nil
function CalloutManager.GetExpiresAt()
    if current == nil then
        return nil
    end
    return current.expiresAt
end

---Whether the HUD should append a countdown to the current message.
---@return boolean
function CalloutManager.GetAppendTimer()
    return current ~= nil and current.appendTimer == true
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
