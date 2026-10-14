local _, ns = ...

-- Transport adapter for ns.MessageProtocol. Wire format: docs/message_protocol.md
-- One-way deps only: Comm → MessageProtocol + AddonMessage. Does not mutate MessageProtocol.
local MessageProtocol = ns.MessageProtocol
local AddonMessage = ns.Api.AddonMessage

local Comm = {}
ns.Api.MessageProtocolComm = Comm

-- Convenience aliases; canonical tables live on AddonMessage.
Comm.PREFIX = AddonMessage.PREFIX
Comm.TrafficClass = AddonMessage.TrafficClass

local enabled = false

---@param message string
---@param channel string
---@param sender string
local function OnMessage(message, channel, sender)
    MessageProtocol.Dispatch(message, sender, channel)
end

---@param base table
---@param overlay table|nil
---@return table
local function MergeOptions(base, overlay)
    if type(overlay) ~= "table" then
        return base
    end
    local merged = {}
    for key, value in pairs(base) do
        merged[key] = value
    end
    for key, value in pairs(overlay) do
        merged[key] = value
    end
    return merged
end

---@param targetOrOptions string|table|nil
---@param options table|nil
---@return string|nil target
---@return table options
local function ResolveSendOptions(targetOrOptions, options)
    if type(targetOrOptions) == "table" then
        local opts = MergeOptions(targetOrOptions, options)
        return opts.target, opts
    end
    return targetOrOptions, options or {}
end

---Registers listeners for NET_RT and NET_CTL.
---Safe to call more than once. Partial registration failures are rolled back so retries work.
---@return boolean ok
---@return string|nil reason
---@return string|nil failedPrefix
function Comm.Enable()
    if enabled then
        return true
    end
    local ok, reason, failedPrefix = AddonMessage.ListenProtocol(OnMessage)
    if not ok then
        return false, reason, failedPrefix
    end
    enabled = true
    return true
end

---Encodes and sends a v1 message via AddonMessage. Does not imply delivery.
---@param messageType MessageProtocolType
---@param topic string
---@param correlationId string
---@param payload string|nil
---@param channel string  Chat type accepted by AddonMessage (e.g. "RAID", "WHISPER").
---@param targetOrOptions string|table|nil  Options table, or whisper target string.
---@param options { trafficClass: string|nil, target: string|nil }|nil
---  Merged over `targetOrOptions` when that arg is a table. `trafficClass` defaults to CONTROL.
---@return boolean ok
---@return string|nil reason  Encode reason or AddonMessage failure name.
function Comm.Send(messageType, topic, correlationId, payload, channel, targetOrOptions, options)
    if type(channel) ~= "string" or channel == "" then
        return false, "InvalidChannel"
    end
    local target, opts = ResolveSendOptions(targetOrOptions, options)
    if channel == "WHISPER" and (type(target) ~= "string" or target == "") then
        return false, "InvalidTarget"
    end
    local trafficClass = opts.trafficClass or AddonMessage.TrafficClass.CONTROL
    local prefix, mapReason = AddonMessage.PrefixForTrafficClass(trafficClass)
    if not prefix then
        return false, mapReason
    end

    local wire, encodeReason = MessageProtocol.Encode(messageType, topic, correlationId, payload)
    if not wire then
        return false, encodeReason
    end

    return AddonMessage.Send(prefix, wire, channel, target)
end
