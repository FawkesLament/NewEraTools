local _, ns = ...
local Unit = ns.Api.Unit

local AddonMessage = {}
ns.Api.AddonMessage = AddonMessage

-- Older clients return a boolean; newer ones return an Enum.SendAddonMessageResult code.
local SEND_SUCCESS = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success

---Traffic classes map to separate Blizzard prefixes so per-prefix throttles do not starve each other.
AddonMessage.TrafficClass = {
    REALTIME = "REALTIME",
    CONTROL = "CONTROL",
}

---Canonical prefixes for MessageProtocol traffic.
AddonMessage.PREFIX = {
    REALTIME = "NET_RT",
    CONTROL = "NET_CTL",
}

local PREFIX_BY_TRAFFIC = {
    [AddonMessage.TrafficClass.REALTIME] = AddonMessage.PREFIX.REALTIME,
    [AddonMessage.TrafficClass.CONTROL] = AddonMessage.PREFIX.CONTROL,
}

---Ordered list used when registering listeners for every protocol-managed prefix.
local PROTOCOL_PREFIXES = {
    AddonMessage.PREFIX.REALTIME,
    AddonMessage.PREFIX.CONTROL,
}

local callbacks = {}
local listening = false

local function OnAddonMessage(prefix, message, channel, sender)
    local callback = callbacks[prefix]
    if callback then
        callback(message, channel, Unit.GetFullName(sender))
    end
end

---@param result any
---@return boolean ok
---@return string|nil reason  `Enum.SendAddonMessageResult` field name when known.
local function ClassifySendResult(result)
    if result == true then
        return true
    end
    if SEND_SUCCESS ~= nil and result == SEND_SUCCESS then
        return true
    end
    if type(result) == "number" and Enum and Enum.SendAddonMessageResult then
        for name, code in pairs(Enum.SendAddonMessageResult) do
            if code == result and type(name) == "string" then
                return false, name
            end
        end
    end
    if result == false then
        return false, "rejected"
    end
    return false, "GeneralError"
end

---@param prefix string
---@return boolean
function AddonMessage.IsProtocolPrefix(prefix)
    return prefix == AddonMessage.PREFIX.REALTIME or prefix == AddonMessage.PREFIX.CONTROL
end

---Resolves a traffic class to its Blizzard addon-message prefix.
---@param trafficClass string
---@return string|nil prefix
---@return string|nil reason
function AddonMessage.PrefixForTrafficClass(trafficClass)
    local prefix = PREFIX_BY_TRAFFIC[trafficClass]
    if not prefix then
        return nil, "InvalidTrafficClass"
    end
    return prefix
end

---Sends a hidden message that only addons listening for `prefix` receive.
---Uses `select(-1, ...)` so both legacy boolean and enum result layouts work.
---@param prefix string  At most 16 characters.
---@param message string  At most 255 characters.
---@param chatType ChatType  e.g. "RAID".
---@param target string|nil  Whisper/channel target when required by `chatType`.
---@return boolean ok  Whether the game accepted it for transmission (not delivery).
---@return string|nil reason  Failure name, e.g. "AddOnMessageLockdown" or "AddonMessageThrottle".
function AddonMessage.Send(prefix, message, chatType, target)
    if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
        return false, "InvalidPrefix"
    end
    if type(message) ~= "string" or #message > 255 or message:find("\0", 1, true) then
        return false, "InvalidMessage"
    end
    local result = select(-1, C_ChatInfo.SendAddonMessage(prefix, message, chatType, target))
    return ClassifySendResult(result)
end

---Sends on the prefix mapped from `trafficClass` (`REALTIME` → `NET_RT`, `CONTROL` → `NET_CTL`).
---@param trafficClass string
---@param message string
---@param chatType ChatType
---@param target string|nil
---@return boolean ok
---@return string|nil reason
function AddonMessage.SendTraffic(trafficClass, message, chatType, target)
    local prefix, mapReason = AddonMessage.PrefixForTrafficClass(trafficClass)
    if not prefix then
        return false, mapReason
    end
    return AddonMessage.Send(prefix, message, chatType, target)
end

---Calls `callback` for every addon message sent with `prefix`, including the player's own.
---@param prefix string  At most 16 characters; one listener per prefix.
---@param callback fun(message: string, channel: ChatType, sender: string)  `sender` is "Name-Realm".
---@return boolean ok
---@return string|nil reason  `InvalidPrefix` or `RegisterFailed`.
function AddonMessage.Listen(prefix, callback)
    assert(type(callback) == "function", "AddonMessage.Listen requires a callback")
    assert(not callbacks[prefix], "Already listening for addon prefix: " .. tostring(prefix))
    if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
        return false, "InvalidPrefix"
    end
    -- `RegisterAddonMessagePrefix` returns false when the client refuses (e.g. prefix table full).
    -- Older clients may return nil on success; only an explicit false is treated as failure.
    local registered = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if registered == false then
        return false, "RegisterFailed"
    end
    callbacks[prefix] = callback
    if not listening then
        listening = true
        ns.Api.GameEvents.Listen("CHAT_MSG_ADDON", OnAddonMessage)
    end
    return true
end

---Stops delivering messages for `prefix`. The Blizzard prefix registration cannot be undone;
---a later Listen may call RegisterAddonMessagePrefix again and reattach a callback.
---@param prefix string
function AddonMessage.Unlisten(prefix)
    callbacks[prefix] = nil
end

---Registers one callback for every MessageProtocol-managed prefix (realtime and control).
---On failure, unbinds any prefixes successfully registered in this call so a retry is safe.
---@param callback fun(message: string, channel: ChatType, sender: string)
---@return boolean ok
---@return string|nil reason
---@return string|nil failedPrefix
function AddonMessage.ListenProtocol(callback)
    local bound = {}
    for i = 1, #PROTOCOL_PREFIXES do
        local prefix = PROTOCOL_PREFIXES[i]
        local ok, reason = AddonMessage.Listen(prefix, callback)
        if not ok then
            for j = 1, #bound do
                AddonMessage.Unlisten(bound[j])
            end
            return false, reason, prefix
        end
        bound[#bound + 1] = prefix
    end
    return true
end
