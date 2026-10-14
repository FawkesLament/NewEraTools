local _, ns = ...

local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm
local Group = ns.Api.Group
local Player = ns.Api.Player
local Timer = ns.Api.Timer
local Codec = ns.AddonCheckCodec

local AddonCheck = {}
ns.AddonCheck = AddonCheck

---Result state for one peer/request in a check session.
---pending: waiting for a response
---responded: a compatible reply was received
---timed_out: no reply within the session deadline (not "addon missing")
---incompatible: reply received but addon/protocol version cannot be compared
---failed: send/receive or local snapshot collection failed
---@alias AddonCheckResultState
---| "pending"
---| "responded"
---| "timed_out"
---| "incompatible"
---| "failed"

AddonCheck.State = {
    PENDING = "pending",
    RESPONDED = "responded",
    TIMED_OUT = "timed_out",
    INCOMPATIBLE = "incompatible",
    FAILED = "failed",
}

---@alias AddonCheckSessionStatus
---| "running"
---| "completed"
---| "superseded"
---| "failed"

AddonCheck.SessionStatus = {
    RUNNING = "running",
    COMPLETED = "completed",
    SUPERSEDED = "superseded",
    FAILED = "failed",
}

---Default StartCheck deadline in seconds.
AddonCheck.DEFAULT_TIMEOUT = 5

---MessageProtocol topic for configuration check Q/R (CONTROL / NET_CTL).
AddonCheck.TOPIC = "addoncheck.config"

---@class AddonCheckRequestResult
---@field state AddonCheckResultState
---@field playerName string|nil  Full "Name-Realm" when known.
---@field guid string|nil  Player GUID when known; preferred member key.
---@field version string|nil  Peer's addon version when known.
---@field configs table<string, any>|nil  moduleId -> configuration snapshot when responded.
---@field message string|nil  Detail for incompatible/failed (and optional notes otherwise).
---@field receivedAt number|nil  Timer.GetTime() when the terminal result was recorded.

---@class AddonCheckRosterMember
---@field key string  guid when available, otherwise fullName.
---@field guid string|nil
---@field fullName string
---@field name string|nil
---@field subgroup number|nil  Raid party (1–8) from the roster snapshot.
---@field classFile string|nil  e.g. "WARRIOR"; for UI class coloring.

---@class AddonCheckSession
---@field id integer
---@field version string  Local addon version captured at Start / StartCheck.
---@field localConfigs table<string, any>  moduleId -> deep-copied snapshot from Register callbacks.
---@field results table<string, AddonCheckRequestResult>  member key -> result.
---@field moduleId string|nil  Set by StartCheck for managed sessions.
---@field correlationId string|nil  Shared Q/R correlation id for StartCheck.
---@field status AddonCheckSessionStatus|nil  nil for unmanaged Start() sessions.
---@field roster AddonCheckRosterMember[]|nil  Fixed snapshot for StartCheck.
---@field timeout number|nil
---@field startedAt number|nil

---@alias AddonCheckConfigProvider fun(): any

---@type table<string, AddonCheckConfigProvider>
local providers = {}

---@type table<integer, AddonCheckSession>
local sessions = {}

local nextSessionId = 1

---@type fun(session: AddonCheckSession, requestId: string|nil)[]
local listeners = {}

---@class AddonCheckPendingRequest
---@field checkId integer
---@field moduleId string
---@field target string|nil  When set, only this sender is accepted (single Request).

---@type table<string, AddonCheckPendingRequest>
local pendingByCorrelationId = {}

local nextCorrelationSeq = 1

---Notifies OnUpdated subscribers. Used by AddonCheckSession for session-level updates.
---@param session AddonCheckSession
---@param requestId string|nil  nil for session-level updates (e.g. Start / completion).
function AddonCheck.Notify(session, requestId)
    local snapshot = {}
    for i = 1, #listeners do
        snapshot[i] = listeners[i]
    end
    for i = 1, #snapshot do
        snapshot[i](session, requestId)
    end
end

---@return string
function AddonCheck.NextCorrelationId()
    local id = "ac" .. tostring(nextCorrelationSeq)
    nextCorrelationSeq = nextCorrelationSeq + 1
    return id
end

---Binds a pending Q/R for `correlationId`. Used by Request and AddonCheckSession.
---@param correlationId string
---@param pending AddonCheckPendingRequest
function AddonCheck.BindPending(correlationId, pending)
    pendingByCorrelationId[correlationId] = pending
end

---Clears a pending Q/R when it still belongs to `checkId`.
---@param correlationId string
---@param checkId integer
function AddonCheck.UnbindPending(correlationId, checkId)
    local pending = pendingByCorrelationId[correlationId]
    if pending and pending.checkId == checkId then
        pendingByCorrelationId[correlationId] = nil
    end
end

---@param target string
---@param correlationId string
---@param payload string
---@return boolean ok
---@return string|nil reason
local function SendResponse(target, correlationId, payload)
    return MessageProtocolComm.Send(
        MessageProtocol.TYPE_RESPONSE,
        AddonCheck.TOPIC,
        correlationId,
        payload,
        "WHISPER",
        {
            target = target,
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        }
    )
end

---@param msg MessageProtocolMessage
local function HandleRequest(msg)
    local me = Player.GetFullName()
    if not me or msg.sender == me then
        return
    end

    local leader = Group.GetRaidLeaderFullName()
    if not leader or msg.sender ~= leader then
        return
    end

    local moduleId = Codec.DecodeRequestPayload(msg.payload)
    if not moduleId then
        return
    end

    local version = AddonCheck.GetVersion()
    local status
    local body = ""

    if not providers[moduleId] then
        status = "unsupported"
    else
        local config, err = AddonCheck.GetConfig(moduleId)
        if err then
            status = "failed"
            body = err
        else
            local encoded, encodeReason = Codec.EncodeValue(config)
            if not encoded then
                status = "failed"
                body = encodeReason or "serialize_failed"
            else
                status = "ok"
                body = encoded
            end
        end
    end

    local payload = Codec.EncodeResponsePayload(status, moduleId, version, body)
    if not payload then
        return
    end

    local ok, reason = SendResponse(msg.sender, msg.correlationId, payload)
    if ok or status ~= "ok" then
        return
    end

    -- ok payloads can exceed the wire limit; fall back to a compact failure response.
    local failPayload = Codec.EncodeResponsePayload("failed", moduleId, version, reason or "too_large")
    if failPayload then
        SendResponse(msg.sender, msg.correlationId, failPayload)
    end
end

---@param pending AddonCheckPendingRequest
---@param session AddonCheckSession
---@param sender string
---@return string|nil memberKey
---@return string|nil playerName
---@return string|nil guid
local function ResolveResponseMember(pending, session, sender)
    if type(sender) ~= "string" or sender == "" or not sender:find("-", 1, true) then
        return nil
    end

    if session.roster then
        for i = 1, #session.roster do
            local member = session.roster[i]
            if member.fullName == sender then
                return member.key, member.fullName, member.guid
            end
        end
        return nil
    end

    if pending.target and sender == pending.target then
        return pending.target, pending.target, nil
    end
    return nil
end

---@param pending AddonCheckPendingRequest
---@param moduleId string
---@param decoded AddonCheckResponsePayload
---@param playerName string
---@param guid string|nil
---@return AddonCheckRequestResult
local function ResultFromDecodedResponse(pending, moduleId, decoded, playerName, guid)
    local base = {
        playerName = playerName,
        guid = guid,
        version = decoded.version,
        receivedAt = Timer.GetTime(),
    }

    if decoded.status == "ok" then
        local config, nextIndex, decodeReason = Codec.DecodeValue(decoded.body, 1)
        if decodeReason or nextIndex ~= #decoded.body + 1 then
            base.state = AddonCheck.State.FAILED
            base.message = "malformed"
            return base
        end
        base.state = AddonCheck.State.RESPONDED
        base.configs = { [moduleId] = config }
        return base
    end

    if decoded.status == "unsupported" then
        base.state = AddonCheck.State.RESPONDED
        base.message = "unknown_module"
        return base
    end

    base.state = AddonCheck.State.FAILED
    base.message = decoded.body ~= "" and decoded.body or "failed"
    return base
end

---@param msg MessageProtocolMessage
local function HandleResponse(msg)
    local pending = pendingByCorrelationId[msg.correlationId]
    if not pending then
        return
    end

    local session = sessions[pending.checkId]
    if not session then
        pendingByCorrelationId[msg.correlationId] = nil
        return
    end

    if session.status and session.status ~= AddonCheck.SessionStatus.RUNNING then
        return
    end

    if pending.target and msg.sender ~= pending.target then
        return
    end

    local memberKey, playerName, guid = ResolveResponseMember(pending, session, msg.sender)
    if not memberKey then
        return
    end

    local decoded = Codec.DecodeResponsePayload(msg.payload)
    if not decoded or decoded.moduleId ~= pending.moduleId then
        local failed = {
            state = AddonCheck.State.FAILED,
            playerName = playerName,
            guid = guid,
            message = "malformed",
            receivedAt = Timer.GetTime(),
        }
        if session.status then
            ns.AddonCheckSession.ApplyResult(session, memberKey, failed)
        else
            pendingByCorrelationId[msg.correlationId] = nil
            AddonCheck.SetResult(session.id, memberKey, failed)
        end
        return
    end

    local result = ResultFromDecodedResponse(pending, pending.moduleId, decoded, playerName, guid)
    if session.status then
        ns.AddonCheckSession.ApplyResult(session, memberKey, result)
    else
        pendingByCorrelationId[msg.correlationId] = nil
        AddonCheck.SetResult(session.id, memberKey, result)
    end
end

---@param msg MessageProtocolMessage
local function OnProtocolMessage(msg)
    if msg.type == MessageProtocol.TYPE_REQUEST then
        HandleRequest(msg)
    elseif msg.type == MessageProtocol.TYPE_RESPONSE then
        HandleResponse(msg)
    end
end

MessageProtocol.RegisterHandler(AddonCheck.TOPIC, OnProtocolMessage)

---Addon version from the centralized project source (`ns.ADDON_VERSION` / TOC).
---@return string
function AddonCheck.GetVersion()
    return ns.ADDON_VERSION
end

---Registers a feature's configuration provider. `moduleId` must be unique for this load.
---Safe across init and `/reload`: each load starts with an empty registry; modules register again.
---@param moduleId string
---@param getConfig AddonCheckConfigProvider  Returns this module's current configuration snapshot.
function AddonCheck.Register(moduleId, getConfig)
    assert(type(moduleId) == "string" and moduleId ~= "", "AddonCheck.Register requires a non-empty moduleId")
    assert(type(getConfig) == "function", "AddonCheck.Register requires a getConfig function")
    assert(not providers[moduleId], "AddonCheck.Register requires a unique moduleId: " .. moduleId)
    providers[moduleId] = getConfig
end

---Removes a previously registered provider. No-op if `moduleId` is unknown.
---@param moduleId string
function AddonCheck.Unregister(moduleId)
    providers[moduleId] = nil
end

---@param moduleId string
---@return boolean
function AddonCheck.IsRegistered(moduleId)
    return providers[moduleId] ~= nil
end

---Returns a live configuration snapshot for one registered module.
---@param moduleId string
---@return any|nil config
---@return string|nil error  `unknown_module` or `provider_failed`.
function AddonCheck.GetConfig(moduleId)
    local getConfig = providers[moduleId]
    if not getConfig then
        return nil, "unknown_module"
    end
    local ok, config = pcall(getConfig)
    if not ok then
        return nil, "provider_failed"
    end
    return config
end

---@return string[]
function AddonCheck.GetRegisteredModuleIds()
    local ids = {}
    for moduleId in pairs(providers) do
        table.insert(ids, moduleId)
    end
    table.sort(ids)
    return ids
end

---@param moduleIds string[]|nil  nil = every registered module.
---@return table<string, any>
local function CollectLocalConfigs(moduleIds)
    local configs = {}
    if moduleIds then
        for _, moduleId in ipairs(moduleIds) do
            local getConfig = providers[moduleId]
            assert(getConfig, "AddonCheck.Start: unknown moduleId " .. tostring(moduleId))
            configs[moduleId] = ns.Util.DeepCopy(getConfig())
        end
        return configs
    end
    for moduleId, getConfig in pairs(providers) do
        configs[moduleId] = ns.Util.DeepCopy(getConfig())
    end
    return configs
end

---Creates a check session with local snapshots. Does not network or resolve peer results yet.
---@param options { moduleIds: string[]|nil }|nil  `moduleIds` limits which registered modules are included.
---@return AddonCheckSession
function AddonCheck.Start(options)
    local moduleIds = options and options.moduleIds
    local session = {
        id = nextSessionId,
        version = ns.ADDON_VERSION,
        localConfigs = CollectLocalConfigs(moduleIds),
        results = {},
    }
    nextSessionId = nextSessionId + 1
    sessions[session.id] = session
    AddonCheck.Notify(session, nil)
    return session
end

---@param checkId integer
---@return AddonCheckSession|nil
function AddonCheck.GetSession(checkId)
    return sessions[checkId]
end

---Records or replaces one peer/request result and notifies subscribers.
---@param checkId integer
---@param requestId string  Member key (GUID when available, else full name).
---@param result AddonCheckRequestResult
---@return AddonCheckSession
function AddonCheck.SetResult(checkId, requestId, result)
    assert(type(requestId) == "string" and requestId ~= "", "AddonCheck.SetResult requires a non-empty requestId")
    assert(
        type(result) == "table" and type(result.state) == "string",
        "AddonCheck.SetResult requires a result with state"
    )
    local session = assert(sessions[checkId], "AddonCheck.SetResult: unknown checkId " .. tostring(checkId))
    session.results[requestId] = result
    AddonCheck.Notify(session, requestId)
    return session
end

---Subscribes to session creation and result updates. Returns an unsubscribe function.
---@param callback fun(session: AddonCheckSession, requestId: string|nil)
---@return fun()
function AddonCheck.OnUpdated(callback)
    assert(type(callback) == "function", "AddonCheck.OnUpdated requires a callback")
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

---Sends one CONTROL whisper request for `moduleId` to `target` and records a pending result on `checkId`.
---Requires raid lead. Exercise via unit tests or a caller of `Start` + `Request` (no slash command).
---@param checkId integer  Session from `Start`.
---@param target string  Peer "Name-Realm".
---@param moduleId string
---@param correlationId string|nil  Generated when nil; must be a valid Q/R correlation id.
---@return boolean ok
---@return string|nil correlationIdOrReason  Correlation id on success; failure reason otherwise.
function AddonCheck.Request(checkId, target, moduleId, correlationId)
    assert(type(checkId) == "number", "AddonCheck.Request requires a checkId")
    assert(type(target) == "string" and target ~= "", "AddonCheck.Request requires a target")
    assert(Codec.IsValidModuleId(moduleId), "AddonCheck.Request requires a valid moduleId")

    local session = sessions[checkId]
    if not session then
        return false, "unknown_check"
    end
    if not Group.IsPlayerRaidLeader() then
        return false, "not_raid_leader"
    end

    if correlationId == nil then
        correlationId = AddonCheck.NextCorrelationId()
    end
    if not MessageProtocol.IsValidCorrelationId(correlationId) then
        return false, "invalid_correlation_id"
    end
    if pendingByCorrelationId[correlationId] then
        return false, "duplicate_correlation_id"
    end

    local payload = Codec.EncodeRequestPayload(moduleId)
    if not payload then
        return false, "invalid_module_id"
    end

    local ok, reason = MessageProtocolComm.Send(
        MessageProtocol.TYPE_REQUEST,
        AddonCheck.TOPIC,
        correlationId,
        payload,
        "WHISPER",
        {
            target = target,
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        }
    )
    if not ok then
        AddonCheck.SetResult(checkId, target, {
            state = AddonCheck.State.FAILED,
            playerName = target,
            message = reason,
            receivedAt = Timer.GetTime(),
        })
        return false, reason
    end

    AddonCheck.BindPending(correlationId, {
        checkId = checkId,
        target = target,
        moduleId = moduleId,
    })
    AddonCheck.SetResult(checkId, target, {
        state = AddonCheck.State.PENDING,
        playerName = target,
    })
    return true, correlationId
end
