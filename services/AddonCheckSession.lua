local _, ns = ...

---Managed StartCheck lifecycle for AddonCheck (roster, timeout, one active session per module).
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm
local Group = ns.Api.Group
local Player = ns.Api.Player
local Timer = ns.Api.Timer
local Codec = ns.AddonCheckCodec
local AddonCheck = ns.AddonCheck

local Session = {}
ns.AddonCheckSession = Session

---@type table<string, integer>  moduleId -> active StartCheck session id
local activeByModuleId = {}

---@type table<integer, { Cancel: fun(self: any) }>
local timersBySessionId = {}

---@param member { guid: string|nil, fullName: string }
---@return string
local function MemberKey(member)
    if type(member.guid) == "string" and member.guid ~= "" then
        return member.guid
    end
    return member.fullName
end

---@param state string
---@return boolean
local function IsTerminalState(state)
    return state ~= AddonCheck.State.PENDING
end

---@param session AddonCheckSession
---@return boolean
local function SessionAllTerminal(session)
    for _, result in pairs(session.results) do
        if not IsTerminalState(result.state) then
            return false
        end
    end
    return true
end

---@param session AddonCheckSession
local function CancelSessionTimer(session)
    local ticker = timersBySessionId[session.id]
    if ticker then
        timersBySessionId[session.id] = nil
        ticker:Cancel()
    end
end

---@param session AddonCheckSession
---@param status AddonCheckSessionStatus
local function FinishManagedSession(session, status)
    if session.status ~= AddonCheck.SessionStatus.RUNNING then
        return
    end
    session.status = status
    CancelSessionTimer(session)
    if session.correlationId then
        AddonCheck.UnbindPending(session.correlationId, session.id)
    end
    if session.moduleId and activeByModuleId[session.moduleId] == session.id then
        activeByModuleId[session.moduleId] = nil
    end
    AddonCheck.Notify(session, nil)
end

---Applies a peer result on a running managed session; completes the session when all are terminal.
---@param session AddonCheckSession
---@param memberKey string
---@param result AddonCheckRequestResult
function Session.ApplyResult(session, memberKey, result)
    if session.status ~= AddonCheck.SessionStatus.RUNNING then
        return
    end
    local existing = session.results[memberKey]
    if not existing or IsTerminalState(existing.state) then
        return
    end
    if result.receivedAt == nil then
        result.receivedAt = Timer.GetTime()
    end
    AddonCheck.SetResult(session.id, memberKey, result)
    if SessionAllTerminal(session) then
        FinishManagedSession(session, AddonCheck.SessionStatus.COMPLETED)
    end
end

---@param session AddonCheckSession
---@param moduleId string
---@param meFullName string
---@param meGuid string|nil
local function ApplyLocalLeaderResult(session, moduleId, meFullName, meGuid)
    local memberKey = nil
    for i = 1, #session.roster do
        local member = session.roster[i]
        if member.fullName == meFullName or (meGuid and member.guid == meGuid) then
            memberKey = member.key
            break
        end
    end
    if not memberKey then
        return
    end

    local config, err = AddonCheck.GetConfig(moduleId)
    if err then
        Session.ApplyResult(session, memberKey, {
            state = AddonCheck.State.FAILED,
            playerName = meFullName,
            guid = meGuid,
            message = err,
            receivedAt = Timer.GetTime(),
        })
        return
    end

    Session.ApplyResult(session, memberKey, {
        state = AddonCheck.State.RESPONDED,
        playerName = meFullName,
        guid = meGuid,
        version = AddonCheck.GetVersion(),
        configs = { [moduleId] = ns.Util.DeepCopy(config) },
        receivedAt = Timer.GetTime(),
    })
end

---@param session AddonCheckSession
local function OnSessionTimeout(session)
    if session.status ~= AddonCheck.SessionStatus.RUNNING then
        return
    end
    timersBySessionId[session.id] = nil
    local now = Timer.GetTime()
    for memberKey, result in pairs(session.results) do
        if result.state == AddonCheck.State.PENDING then
            AddonCheck.SetResult(session.id, memberKey, {
                state = AddonCheck.State.TIMED_OUT,
                playerName = result.playerName,
                guid = result.guid,
                receivedAt = now,
            })
        end
    end
    FinishManagedSession(session, AddonCheck.SessionStatus.COMPLETED)
end

---Active StartCheck session for `moduleId`, if any.
---@param moduleId string
---@return AddonCheckSession|nil
function Session.GetActiveSession(moduleId)
    local checkId = activeByModuleId[moduleId]
    if not checkId then
        return nil
    end
    return AddonCheck.GetSession(checkId)
end

---Starts a managed raid check for one registered module. Requires raid lead.
---Broadcasts one CONTROL request on the raid channel; peers reply with a WHISPER response.
---Roster membership is fixed at start; leavers may time out, joiners wait for the next check.
---Only one running session per module; a new StartCheck supersedes the previous one.
---@param moduleId string
---@param options { timeout: number|nil }|nil  `timeout` seconds (default DEFAULT_TIMEOUT).
---@return AddonCheckSession|nil session
---@return string|nil reason  Start failure (`not_raid_leader`, `unknown_module`, …). No session created.
function Session.StartCheck(moduleId, options)
    if not Codec.IsValidModuleId(moduleId) then
        return nil, "invalid_module_id"
    end
    if not AddonCheck.IsRegistered(moduleId) then
        return nil, "unknown_module"
    end
    if not Group.IsPlayerRaidLeader() then
        return nil, "not_raid_leader"
    end

    local meFullName = Player.GetFullName()
    if not meFullName then
        return nil, "no_player"
    end
    local meGuid = Player.GetGUID()

    local chatType = Group.GetRaidChatType()
    local raidMembers = Group.GetRaidMembers()
    if not chatType or #raidMembers == 0 then
        return nil, "not_in_raid"
    end

    local timeout = AddonCheck.DEFAULT_TIMEOUT
    if options and options.timeout ~= nil then
        assert(type(options.timeout) == "number" and options.timeout >= 0, "AddonCheck.StartCheck timeout must be >= 0")
        timeout = options.timeout
    end

    local roster = {}
    local seenKeys = {}
    for i = 1, #raidMembers do
        local raidMember = raidMembers[i]
        if type(raidMember.fullName) == "string" and raidMember.fullName ~= "" then
            local entry = {
                key = MemberKey(raidMember),
                guid = raidMember.guid,
                fullName = raidMember.fullName,
                name = raidMember.name,
                subgroup = raidMember.subgroup,
                classFile = raidMember.classFile,
            }
            if not seenKeys[entry.key] then
                seenKeys[entry.key] = true
                roster[#roster + 1] = entry
            end
        end
    end
    if #roster == 0 then
        return nil, "empty_roster"
    end

    local previousId = activeByModuleId[moduleId]
    if previousId then
        local previous = AddonCheck.GetSession(previousId)
        if previous and previous.status == AddonCheck.SessionStatus.RUNNING then
            FinishManagedSession(previous, AddonCheck.SessionStatus.SUPERSEDED)
        end
    end

    local correlationId = AddonCheck.NextCorrelationId()
    -- Empty moduleIds avoids a throwing provider aborting Start; local result uses GetConfig.
    local session = AddonCheck.Start({ moduleIds = {} })
    session.moduleId = moduleId
    session.correlationId = correlationId
    session.status = AddonCheck.SessionStatus.RUNNING
    session.timeout = timeout
    session.startedAt = Timer.GetTime()
    session.roster = roster

    local localConfig, localConfigErr = AddonCheck.GetConfig(moduleId)
    if not localConfigErr then
        session.localConfigs[moduleId] = ns.Util.DeepCopy(localConfig)
    end

    for i = 1, #roster do
        local entry = roster[i]
        session.results[entry.key] = {
            state = AddonCheck.State.PENDING,
            playerName = entry.fullName,
            guid = entry.guid,
        }
    end

    -- Start() already notified with empty results; publish the pending roster snapshot.
    AddonCheck.Notify(session, nil)

    activeByModuleId[moduleId] = session.id
    AddonCheck.BindPending(correlationId, {
        checkId = session.id,
        moduleId = moduleId,
    })

    ApplyLocalLeaderResult(session, moduleId, meFullName, meGuid)

    if session.status ~= AddonCheck.SessionStatus.RUNNING then
        return session
    end

    local payload = Codec.EncodeRequestPayload(moduleId)
    if not payload then
        FinishManagedSession(session, AddonCheck.SessionStatus.FAILED)
        return session, "invalid_module_id"
    end

    local ok, reason =
        MessageProtocolComm.Send(MessageProtocol.TYPE_REQUEST, AddonCheck.TOPIC, correlationId, payload, chatType, {
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        })
    if not ok then
        local now = Timer.GetTime()
        for i = 1, #session.roster do
            local member = session.roster[i]
            local isSelf = member.fullName == meFullName or (meGuid and member.guid == meGuid)
            if not isSelf then
                Session.ApplyResult(session, member.key, {
                    state = AddonCheck.State.FAILED,
                    playerName = member.fullName,
                    guid = member.guid,
                    message = reason,
                    receivedAt = now,
                })
                if session.status ~= AddonCheck.SessionStatus.RUNNING then
                    return session, reason
                end
            end
        end
        if session.status ~= AddonCheck.SessionStatus.RUNNING then
            return session, reason
        end
    end

    if session.status ~= AddonCheck.SessionStatus.RUNNING then
        return session
    end

    local checkId = session.id
    local ticker = Timer.NewTicker(timeout, function()
        local current = AddonCheck.GetSession(checkId)
        if current then
            OnSessionTimeout(current)
        end
    end, 1)
    timersBySessionId[checkId] = ticker

    return session
end

AddonCheck.StartCheck = Session.StartCheck
AddonCheck.GetActiveSession = Session.GetActiveSession
