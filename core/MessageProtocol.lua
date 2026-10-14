local _, ns = ...

local MessageProtocol = {}
ns.MessageProtocol = MessageProtocol

---When true, Dispatch prints handler errors via Util.Print (default off).
MessageProtocol.debugHandlers = false

---Wire protocol version (independent of ns.ADDON_VERSION).
MessageProtocol.VERSION = 1

MessageProtocol.TYPE_EVENT = "E"
MessageProtocol.TYPE_REQUEST = "Q"
MessageProtocol.TYPE_RESPONSE = "R"

---Blizzard addon-message body limit (bytes / characters).
MessageProtocol.MAX_MESSAGE_LENGTH = 255

MessageProtocol.MAX_TOPIC_LENGTH = 48
MessageProtocol.MAX_CORRELATION_ID_LENGTH = 24

---Reserved correlation id for Event messages; must not be used for Q/R.
MessageProtocol.EVENT_CORRELATION_ID = "-"

local TOPIC_PATTERN = "^[A-Za-z0-9_.-]+$"
local CORRELATION_ID_PATTERN = "^[A-Za-z0-9_-]+$"

---@alias MessageProtocolType "E"|"Q"|"R"

---@class MessageProtocolEnvelope
---@field version integer
---@field type MessageProtocolType
---@field topic string
---@field correlationId string
---@field payload string

---@class MessageProtocolMessage : MessageProtocolEnvelope
---@field sender string  Trusted transport identity ("Name-Realm").
---@field channel string  Trusted transport channel (e.g. "RAID").

---@alias MessageProtocolHandler fun(message: MessageProtocolMessage)

---@type table<string, MessageProtocolHandler[]>
local handlersByTopic = {}

---@param value string
---@param pattern string
---@param minLength integer
---@param maxLength integer
---@return boolean
local function IsToken(value, pattern, minLength, maxLength)
    return type(value) == "string"
        and #value >= minLength
        and #value <= maxLength
        and value:find(pattern) ~= nil
end

---@param topic string
---@return boolean
function MessageProtocol.IsValidTopic(topic)
    return IsToken(topic, TOPIC_PATTERN, 1, MessageProtocol.MAX_TOPIC_LENGTH)
end

---Validates a Q/R correlation id. The Event sentinel `-` is never valid here.
---@param correlationId string
---@return boolean
function MessageProtocol.IsValidCorrelationId(correlationId)
    if correlationId == MessageProtocol.EVENT_CORRELATION_ID then
        return false
    end
    return IsToken(correlationId, CORRELATION_ID_PATTERN, 1, MessageProtocol.MAX_CORRELATION_ID_LENGTH)
end

---@param messageType string
---@return boolean
local function IsKnownType(messageType)
    return messageType == MessageProtocol.TYPE_EVENT
        or messageType == MessageProtocol.TYPE_REQUEST
        or messageType == MessageProtocol.TYPE_RESPONSE
end

---Encodes a v1 envelope. Payload is opaque and may contain `|`; it is never escaped.
---@param messageType MessageProtocolType
---@param topic string
---@param correlationId string  `-` for events; 1–24 `[A-Za-z0-9_-]` for Q/R.
---@param payload string|nil  Defaults to "".
---@return string|nil wire
---@return string|nil reason
function MessageProtocol.Encode(messageType, topic, correlationId, payload)
    if not IsKnownType(messageType) then
        return nil, "invalid_type"
    end
    if not MessageProtocol.IsValidTopic(topic) then
        return nil, "invalid_topic"
    end
    if messageType == MessageProtocol.TYPE_EVENT then
        if correlationId ~= MessageProtocol.EVENT_CORRELATION_ID then
            return nil, "invalid_correlation_id"
        end
    elseif not MessageProtocol.IsValidCorrelationId(correlationId) then
        return nil, "invalid_correlation_id"
    end
    if payload == nil then
        payload = ""
    end
    if type(payload) ~= "string" or payload:find("\0", 1, true) then
        return nil, "invalid_payload"
    end

    local wire = table.concat({
        tostring(MessageProtocol.VERSION),
        messageType,
        topic,
        correlationId,
        payload,
    }, "|")
    if #wire > MessageProtocol.MAX_MESSAGE_LENGTH then
        return nil, "too_large"
    end
    return wire
end

---Finds the first four `|` delimiters; everything after the fourth is the payload.
---@param message string
---@return string|nil version
---@return string|nil messageType
---@return string|nil topic
---@return string|nil correlationId
---@return string|nil payload
local function SplitEnvelope(message)
    local start = 1
    local fields = {}
    for _ = 1, 4 do
        local index = message:find("|", start, true)
        if not index then
            return nil
        end
        table.insert(fields, message:sub(start, index - 1))
        start = index + 1
    end
    return fields[1], fields[2], fields[3], fields[4], message:sub(start)
end

---Decodes a v1 wire message. Returns nil for malformed or unsupported versions (never errors).
---@param message string
---@return MessageProtocolEnvelope|nil
---@return string|nil reason
function MessageProtocol.Decode(message)
    if type(message) ~= "string" then
        return nil, "invalid_message"
    end
    if message:find("\0", 1, true) then
        return nil, "invalid_message"
    end
    if #message > MessageProtocol.MAX_MESSAGE_LENGTH then
        return nil, "too_large"
    end

    local versionText, messageType, topic, correlationId, payload = SplitEnvelope(message)
    if not versionText then
        return nil, "missing_fields"
    end

    if not versionText:find("^%d+$") then
        return nil, "invalid_version"
    end
    local version = tonumber(versionText)
    if version ~= MessageProtocol.VERSION then
        return nil, "unsupported_version"
    end

    if not IsKnownType(messageType) then
        return nil, "invalid_type"
    end
    if not MessageProtocol.IsValidTopic(topic) then
        return nil, "invalid_topic"
    end
    if messageType == MessageProtocol.TYPE_EVENT then
        if correlationId ~= MessageProtocol.EVENT_CORRELATION_ID then
            return nil, "invalid_correlation_id"
        end
    elseif not MessageProtocol.IsValidCorrelationId(correlationId) then
        return nil, "invalid_correlation_id"
    end

    return {
        version = version,
        type = messageType,
        topic = topic,
        correlationId = correlationId,
        payload = payload,
    }
end

---Registers a handler for `topic`. Multiple handlers per topic are invoked in registration order.
---@param topic string
---@param callback MessageProtocolHandler
function MessageProtocol.RegisterHandler(topic, callback)
    assert(MessageProtocol.IsValidTopic(topic), "MessageProtocol.RegisterHandler requires a valid topic")
    assert(type(callback) == "function", "MessageProtocol.RegisterHandler requires a callback")
    local list = handlersByTopic[topic]
    if not list then
        list = {}
        handlersByTopic[topic] = list
    end
    for _, existing in ipairs(list) do
        assert(existing ~= callback, "MessageProtocol.RegisterHandler: callback already registered for " .. topic)
    end
    table.insert(list, callback)
end

---Removes one previously registered handler. No-op if the pair is unknown.
---@param topic string
---@param callback MessageProtocolHandler
function MessageProtocol.UnregisterHandler(topic, callback)
    local list = handlersByTopic[topic]
    if not list then
        return
    end
    for index, existing in ipairs(list) do
        if existing == callback then
            table.remove(list, index)
            break
        end
    end
    if #list == 0 then
        handlersByTopic[topic] = nil
    end
end

---Decodes `message` and dispatches to topic handlers. Invalid envelopes and unknown topics are ignored.
---Handler errors are isolated with `pcall` so one consumer cannot break others.
---@param message string
---@param sender string  From transport; never from the payload.
---@param channel string  From transport; never from the payload.
---@return boolean dispatched  True when at least one handler ran (successfully or not).
function MessageProtocol.Dispatch(message, sender, channel)
    if type(sender) ~= "string" or sender == "" or type(channel) ~= "string" or channel == "" then
        return false
    end

    local envelope = MessageProtocol.Decode(message)
    if not envelope then
        return false
    end

    local list = handlersByTopic[envelope.topic]
    if not list or #list == 0 then
        return false
    end

    ---@type MessageProtocolMessage
    local inbound = {
        version = envelope.version,
        type = envelope.type,
        topic = envelope.topic,
        correlationId = envelope.correlationId,
        payload = envelope.payload,
        sender = sender,
        channel = channel,
    }

    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        local ok, err = pcall(snapshot[i], inbound)
        if not ok and MessageProtocol.debugHandlers then
            ns.Util.Print(
                "MessageProtocol handler error (" .. envelope.topic .. "): " .. tostring(err)
            )
        end
    end
    return true
end
