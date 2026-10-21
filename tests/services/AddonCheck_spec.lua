local Loader = require("helpers.loader")

describe("AddonCheck", function()
    local ns
    local AddonCheck

    before_each(function()
        ns = Loader.Load()
        AddonCheck = ns.AddonCheck
    end)

    it("exposes the TOC addon version", function()
        local tocVersion
        for line in io.lines("NewEraTools.toc") do
            tocVersion = line:gsub("\r$", ""):match("^## Version:%s*(%S+)")
            if tocVersion then
                break
            end
        end
        assert.equals(tocVersion, ns.Api.Client.GetAddonVersion())
        assert.equals(tocVersion, AddonCheck.GetVersion())
    end)

    it("rejects duplicate module ids", function()
        AddonCheck.Register("Feature", function()
            return {}
        end)
        assert.is_false(pcall(AddonCheck.Register, "Feature", function()
            return {}
        end))
    end)

    it("lists registered module ids sorted", function()
        AddonCheck.Register("zeta", function()
            return 1
        end)
        AddonCheck.Register("alpha", function()
            return 2
        end)
        assert.same({ "alpha", "zeta" }, AddonCheck.GetRegisteredModuleIds())
    end)

    it("Unregister frees a module id for registration again", function()
        AddonCheck.Register("Feature", function()
            return { a = 1 }
        end)
        AddonCheck.Unregister("Feature")
        AddonCheck.Register("Feature", function()
            return { a = 2 }
        end)
        local session = AddonCheck.Start()
        assert.same({ a = 2 }, session.localConfigs.Feature)
    end)

    it("Start captures deep-copied snapshots from all registered modules", function()
        local shared = { nested = { value = 1 } }
        AddonCheck.Register("A", function()
            return shared
        end)
        AddonCheck.Register("B", function()
            return "plain"
        end)

        local session = AddonCheck.Start()
        assert.equals(1, session.id)
        assert.equals(AddonCheck.GetVersion(), session.version)
        assert.same({ A = { nested = { value = 1 } }, B = "plain" }, session.localConfigs)
        assert.same({}, session.results)

        shared.nested.value = 99
        assert.equals(1, session.localConfigs.A.nested.value)
    end)

    it("Start can limit which modules are snapshotted", function()
        AddonCheck.Register("Keep", function()
            return true
        end)
        AddonCheck.Register("Skip", function()
            return false
        end)
        local session = AddonCheck.Start({ moduleIds = { "Keep" } })
        assert.same({ Keep = true }, session.localConfigs)
    end)

    it("SetResult stores peer state and notifies subscribers", function()
        local events = {}
        local unsubscribe = AddonCheck.OnUpdated(function(session, requestId)
            local state = requestId and session.results[requestId].state or nil
            table.insert(events, { id = session.id, requestId = requestId, state = state })
        end)

        local session = AddonCheck.Start()
        AddonCheck.SetResult(session.id, "Player-Realm", {
            state = AddonCheck.State.PENDING,
            playerName = "Player-Realm",
        })
        AddonCheck.SetResult(session.id, "Player-Realm", {
            state = AddonCheck.State.RESPONDED,
            playerName = "Player-Realm",
            version = "0.2.0",
            configs = { Feature = { ok = true } },
        })
        unsubscribe()
        AddonCheck.SetResult(session.id, "Other-Realm", {
            state = AddonCheck.State.TIMED_OUT,
            playerName = "Other-Realm",
        })

        assert.same({
            { id = 1, requestId = nil, state = nil },
            { id = 1, requestId = "Player-Realm", state = "pending" },
            { id = 1, requestId = "Player-Realm", state = "responded" },
        }, events)
        assert.equals(AddonCheck.State.RESPONDED, session.results["Player-Realm"].state)
        assert.equals(AddonCheck.State.TIMED_OUT, AddonCheck.GetSession(1).results["Other-Realm"].state)
    end)

    it("documents all result states", function()
        assert.same({
            PENDING = "pending",
            RESPONDED = "responded",
            TIMED_OUT = "timed_out",
            INCOMPATIBLE = "incompatible",
            FAILED = "failed",
        }, AddonCheck.State)
    end)

    describe("request/response", function()
        local Group
        local Player
        local AddonMessage
        local MessageProtocol
        local MessageProtocolComm

        local LEADER = "Leader-TestRealm"
        local MEMBER = "Member-TestRealm"
        local MODULE_ID = "Feature"

        before_each(function()
            Group = ns.Api.Group
            Player = ns.Api.Player
            AddonMessage = ns.Api.AddonMessage
            MessageProtocol = ns.MessageProtocol
            MessageProtocolComm = ns.Api.MessageProtocolComm
            MessageProtocolComm.Enable()

            Group.isRaidLeader = true
            Group.raidLeaderFullName = LEADER
            Player.fullName = LEADER
        end)

        local function Deliver(wire, channel, sender)
            AddonMessage.Deliver(MessageProtocolComm.PREFIX.CONTROL, wire, channel, sender)
        end

        local function LastSent()
            return AddonMessage.sent[#AddonMessage.sent]
        end

        it("encodes and dispatches a CONTROL whisper request", function()
            AddonCheck.Register(MODULE_ID, function()
                return { enabled = true }
            end)
            local session = AddonCheck.Start()
            local ok, correlationId = AddonCheck.Request(session.id, MEMBER, MODULE_ID, "c1")
            assert.is_true(ok)
            assert.equals("c1", correlationId)

            local sent = LastSent()
            assert.equals(MessageProtocolComm.PREFIX.CONTROL, sent.prefix)
            assert.equals("WHISPER", sent.chatType)
            assert.equals(MEMBER, sent.target)

            local decoded = assert(MessageProtocol.Decode(sent.message))
            assert.equals(MessageProtocol.TYPE_REQUEST, decoded.type)
            assert.equals(AddonCheck.TOPIC, decoded.topic)
            assert.equals("c1", decoded.correlationId)
            assert.equals("1|" .. MODULE_ID, decoded.payload)
            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER].state)
        end)

        it("answers a valid leader request with configuration", function()
            Player.fullName = MEMBER
            Group.raidLeaderFullName = LEADER
            Group.isRaidLeader = false
            AddonCheck.Register(MODULE_ID, function()
                return { mode = "normal", count = 2 }
            end)

            local requestWire = assert(
                MessageProtocol.Encode(MessageProtocol.TYPE_REQUEST, AddonCheck.TOPIC, "req1", "1|" .. MODULE_ID)
            )
            Deliver(requestWire, "WHISPER", LEADER)

            local sent = LastSent()
            assert.equals(MessageProtocolComm.PREFIX.CONTROL, sent.prefix)
            assert.equals("WHISPER", sent.chatType)
            assert.equals(LEADER, sent.target)

            local decoded = assert(MessageProtocol.Decode(sent.message))
            assert.equals(MessageProtocol.TYPE_RESPONSE, decoded.type)
            assert.equals("req1", decoded.correlationId)
            local version = AddonCheck.GetVersion():gsub("%.", "%%.")
            assert.is_true(decoded.payload:find("^1|ok|" .. MODULE_ID .. "|" .. version .. "|T2:", 1) == 1)

            -- Leader applies the member response through the normal pending-match path.
            Player.fullName = LEADER
            Group.isRaidLeader = true
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, MODULE_ID, "req1"))
            Deliver(sent.message, "WHISPER", MEMBER)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER].state)
            assert.same({ mode = "normal", count = 2 }, session.results[MEMBER].configs[MODULE_ID])
        end)

        it("ignores unauthorized requests", function()
            Player.fullName = MEMBER
            Group.raidLeaderFullName = LEADER
            AddonCheck.Register(MODULE_ID, function()
                return {}
            end)

            local requestWire = assert(
                MessageProtocol.Encode(MessageProtocol.TYPE_REQUEST, AddonCheck.TOPIC, "req2", "1|" .. MODULE_ID)
            )
            Deliver(requestWire, "WHISPER", "Intruder-TestRealm")
            assert.equals(0, #AddonMessage.sent)
        end)

        it("responds unsupported when the module is not registered", function()
            Player.fullName = MEMBER
            Group.raidLeaderFullName = LEADER

            local requestWire =
                assert(MessageProtocol.Encode(MessageProtocol.TYPE_REQUEST, AddonCheck.TOPIC, "req3", "1|Missing"))
            Deliver(requestWire, "WHISPER", LEADER)

            local decoded = assert(MessageProtocol.Decode(LastSent().message))
            assert.equals("1|unsupported|Missing|" .. AddonCheck.GetVersion() .. "|", decoded.payload)
        end)

        it("responds failed when the provider callback errors", function()
            Player.fullName = MEMBER
            Group.raidLeaderFullName = LEADER
            AddonCheck.Register(MODULE_ID, function()
                error("boom")
            end)

            local requestWire = assert(
                MessageProtocol.Encode(MessageProtocol.TYPE_REQUEST, AddonCheck.TOPIC, "req4", "1|" .. MODULE_ID)
            )
            Deliver(requestWire, "WHISPER", LEADER)

            local decoded = assert(MessageProtocol.Decode(LastSent().message))
            local payload = "1|failed|" .. MODULE_ID .. "|" .. AddonCheck.GetVersion() .. "|provider_failed"
            assert.equals(payload, decoded.payload)
        end)

        it("stores a successful configuration response on the session", function()
            AddonCheck.Register(MODULE_ID, function()
                return { enabled = true }
            end)
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, MODULE_ID, "match1"))

            -- Pair order is not stable; build a response the member would send.
            local configBody = "T1:S7:enabledB1"
            local responseWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "match1",
                    "1|ok|" .. MODULE_ID .. "|0.2.0|" .. configBody
                )
            )
            Deliver(responseWire, "WHISPER", MEMBER)

            local result = session.results[MEMBER]
            assert.equals(AddonCheck.State.RESPONDED, result.state)
            assert.equals("0.2.0", result.version)
            assert.same({ [MODULE_ID] = { enabled = true } }, result.configs)
        end)

        it("stores unsupported module responses", function()
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, "Missing", "u1"))

            local responseWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "u1",
                    "1|unsupported|Missing|0.2.0|"
                )
            )
            Deliver(responseWire, "WHISPER", MEMBER)

            local result = session.results[MEMBER]
            assert.equals(AddonCheck.State.RESPONDED, result.state)
            assert.equals("unknown_module", result.message)
            assert.is_nil(result.configs)
        end)

        it("rejects malformed responses for a pending correlation id", function()
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, MODULE_ID, "bad1"))

            local responseWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "bad1",
                    "1|ok|" .. MODULE_ID .. "|0.2.0|NOT_VALID"
                )
            )
            Deliver(responseWire, "WHISPER", MEMBER)

            local result = session.results[MEMBER]
            assert.equals(AddonCheck.State.FAILED, result.state)
            assert.equals("malformed", result.message)
        end)

        it("ignores responses that do not match the pending correlation id", function()
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, MODULE_ID, "keep1"))

            local responseWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "other",
                    "1|ok|" .. MODULE_ID .. "|0.2.0|B1"
                )
            )
            Deliver(responseWire, "WHISPER", MEMBER)

            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER].state)

            local matched = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "keep1",
                    "1|ok|" .. MODULE_ID .. "|0.2.0|B1"
                )
            )
            Deliver(matched, "WHISPER", MEMBER)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER].state)
            assert.same({ [MODULE_ID] = true }, session.results[MEMBER].configs)
        end)

        it("ignores responses from a sender other than the requested target", function()
            local session = AddonCheck.Start()
            assert.is_true(AddonCheck.Request(session.id, MEMBER, MODULE_ID, "tgt1"))

            local responseWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "tgt1",
                    "1|ok|" .. MODULE_ID .. "|0.2.0|B1"
                )
            )
            Deliver(responseWire, "WHISPER", "Other-TestRealm")
            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER].state)
        end)
    end)

    describe("StartCheck session management", function()
        local Group
        local Player
        local AddonMessage
        local MessageProtocol
        local MessageProtocolComm
        local Timer

        local LEADER = "Leader-TestRealm"
        local LEADER_GUID = "Player-1-AAAA0001"
        local MEMBER_A = "Alpha-TestRealm"
        local MEMBER_A_GUID = "Player-1-AAAA0002"
        local MEMBER_B = "Bravo-TestRealm"
        local MEMBER_B_GUID = "Player-1-AAAA0003"
        local MODULE_ID = "Feature"

        before_each(function()
            Group = ns.Api.Group
            Player = ns.Api.Player
            AddonMessage = ns.Api.AddonMessage
            MessageProtocol = ns.MessageProtocol
            MessageProtocolComm = ns.Api.MessageProtocolComm
            Timer = ns.Api.Timer
            MessageProtocolComm.Enable()

            Group.isRaidLeader = true
            Group.raidLeaderFullName = LEADER
            Group.raidChatType = "RAID"
            Player.fullName = LEADER
            Player.guid = LEADER_GUID
            Group.members = {
                {
                    name = "Leader",
                    fullName = LEADER,
                    guid = LEADER_GUID,
                    subgroup = 1,
                    classFile = "WARRIOR",
                    role = "TANK",
                },
                {
                    name = "Alpha",
                    fullName = MEMBER_A,
                    guid = MEMBER_A_GUID,
                    subgroup = 1,
                    classFile = "MAGE",
                    role = "DAMAGER",
                },
                {
                    name = "Bravo",
                    fullName = MEMBER_B,
                    guid = MEMBER_B_GUID,
                    subgroup = 2,
                    classFile = "PRIEST",
                    role = "HEALER",
                },
            }
        end)

        local function Deliver(wire, channel, sender)
            AddonMessage.Deliver(MessageProtocolComm.PREFIX.CONTROL, wire, channel, sender)
        end

        local function OkResponse(correlationId, moduleId, body)
            body = body or "B1"
            return assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    correlationId,
                    "1|ok|" .. moduleId .. "|0.2.0|" .. body
                )
            )
        end

        it("refuses to start when the player is not raid leader", function()
            Group.isRaidLeader = false
            AddonCheck.Register(MODULE_ID, function()
                return { ok = true }
            end)
            local session, reason = AddonCheck.StartCheck(MODULE_ID)
            assert.is_nil(session)
            assert.equals("not_raid_leader", reason)
            assert.equals(0, #AddonMessage.sent)
        end)

        it("refuses unknown modules without creating a session", function()
            local session, reason = AddonCheck.StartCheck("Missing")
            assert.is_nil(session)
            assert.equals("unknown_module", reason)
        end)

        it("snapshots the roster, resolves the leader locally, and broadcasts one raid request", function()
            AddonCheck.Register(MODULE_ID, function()
                return { mode = "jailbreak" }
            end)

            local session, reason = AddonCheck.StartCheck(MODULE_ID)
            assert.is_nil(reason)
            assert.equals(AddonCheck.SessionStatus.RUNNING, session.status)
            assert.equals(MODULE_ID, session.moduleId)
            assert.equals(session, AddonCheck.GetActiveSession(MODULE_ID))
            assert.equals(3, #session.roster)
            assert.equals(1, session.roster[1].subgroup)
            assert.equals(1, session.roster[2].subgroup)
            assert.equals(2, session.roster[3].subgroup)
            assert.equals(AddonCheck.State.RESPONDED, session.results[LEADER_GUID].state)
            assert.same({ mode = "jailbreak" }, session.results[LEADER_GUID].configs[MODULE_ID])
            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER_A_GUID].state)
            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER_B_GUID].state)

            assert.equals(1, #AddonMessage.sent)
            local sent = AddonMessage.sent[1]
            assert.equals(MessageProtocolComm.PREFIX.CONTROL, sent.prefix)
            assert.equals("RAID", sent.chatType)
            assert.is_nil(sent.target)
            local decoded = assert(MessageProtocol.Decode(sent.message))
            assert.equals(MessageProtocol.TYPE_REQUEST, decoded.type)
            assert.equals(session.correlationId, decoded.correlationId)
            assert.equals("1|" .. MODULE_ID, decoded.payload)
        end)

        it("aggregates responses by GUID key and completes when all members finish", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local events = {}
            AddonCheck.OnUpdated(function(session, requestId)
                table.insert(events, {
                    id = session.id,
                    requestId = requestId,
                    status = session.status,
                })
            end)

            local session = assert(AddonCheck.StartCheck(MODULE_ID))
            Deliver(OkResponse(session.correlationId, MODULE_ID, "B1"), "WHISPER", MEMBER_A)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER_A_GUID].state)
            assert.equals(true, session.results[MEMBER_A_GUID].configs[MODULE_ID])
            assert.equals(AddonCheck.SessionStatus.RUNNING, session.status)

            Deliver(OkResponse(session.correlationId, MODULE_ID, "B0"), "WHISPER", MEMBER_B)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER_B_GUID].state)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, session.status)
            assert.is_nil(AddonCheck.GetActiveSession(MODULE_ID))

            local sawCompletion = false
            for _, event in ipairs(events) do
                if event.id == session.id and event.requestId == nil and event.status == "completed" then
                    sawCompletion = true
                end
            end
            assert.is_true(sawCompletion)
        end)

        it("ignores unknown senders and duplicate responses", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local session = assert(AddonCheck.StartCheck(MODULE_ID))

            Deliver(OkResponse(session.correlationId, MODULE_ID), "WHISPER", "Stranger-TestRealm")
            assert.equals(AddonCheck.State.PENDING, session.results[MEMBER_A_GUID].state)

            Deliver(OkResponse(session.correlationId, MODULE_ID, "B1"), "WHISPER", MEMBER_A)
            assert.equals(true, session.results[MEMBER_A_GUID].configs[MODULE_ID])
            Deliver(OkResponse(session.correlationId, MODULE_ID, "B0"), "WHISPER", MEMBER_A)
            assert.equals(true, session.results[MEMBER_A_GUID].configs[MODULE_ID])
        end)

        it("times out remaining pending members without implying missing addons", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local session = assert(AddonCheck.StartCheck(MODULE_ID, { timeout = 5 }))
            Deliver(OkResponse(session.correlationId, MODULE_ID), "WHISPER", MEMBER_A)

            Timer.Advance(5)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER_A_GUID].state)
            assert.equals(AddonCheck.State.TIMED_OUT, session.results[MEMBER_B_GUID].state)
            assert.is_nil(session.results[MEMBER_B_GUID].message)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, session.status)
        end)

        it("keeps the roster snapshot fixed when membership changes mid-check", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local session = assert(AddonCheck.StartCheck(MODULE_ID))
            Group.members[#Group.members + 1] = {
                name = "Charlie",
                fullName = "Charlie-TestRealm",
                guid = "Player-1-AAAA0004",
                subgroup = 2,
                classFile = "ROGUE",
                role = "DAMAGER",
            }
            table.remove(Group.members, 2) -- Alpha leaves the live roster

            assert.equals(3, #session.roster)
            Deliver(OkResponse(session.correlationId, MODULE_ID), "WHISPER", MEMBER_A)
            assert.equals(AddonCheck.State.RESPONDED, session.results[MEMBER_A_GUID].state)
            Deliver(OkResponse(session.correlationId, MODULE_ID), "WHISPER", "Charlie-TestRealm")
            assert.is_nil(session.results["Player-1-AAAA0004"])
        end)

        it("supersedes a running session for the same module", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local first = assert(AddonCheck.StartCheck(MODULE_ID))
            local firstCorrelation = first.correlationId
            local second = assert(AddonCheck.StartCheck(MODULE_ID))

            assert.equals(AddonCheck.SessionStatus.SUPERSEDED, first.status)
            assert.equals(AddonCheck.SessionStatus.RUNNING, second.status)
            assert.equals(second, AddonCheck.GetActiveSession(MODULE_ID))

            Deliver(OkResponse(firstCorrelation, MODULE_ID), "WHISPER", MEMBER_A)
            assert.equals(AddonCheck.State.PENDING, first.results[MEMBER_A_GUID].state)

            Deliver(OkResponse(second.correlationId, MODULE_ID), "WHISPER", MEMBER_A)
            assert.equals(AddonCheck.State.RESPONDED, second.results[MEMBER_A_GUID].state)
        end)

        it("allows independent checks for different modules", function()
            AddonCheck.Register("A", function()
                return 1
            end)
            AddonCheck.Register("B", function()
                return 2
            end)
            local sessionA = assert(AddonCheck.StartCheck("A"))
            local sessionB = assert(AddonCheck.StartCheck("B"))
            assert.equals(AddonCheck.SessionStatus.RUNNING, sessionA.status)
            assert.equals(AddonCheck.SessionStatus.RUNNING, sessionB.status)
            assert.equals(sessionA, AddonCheck.GetActiveSession("A"))
            assert.equals(sessionB, AddonCheck.GetActiveSession("B"))
            assert.is_true(sessionA.correlationId ~= sessionB.correlationId)
        end)

        it("records local provider failure without aborting the session", function()
            AddonCheck.Register(MODULE_ID, function()
                error("local boom")
            end)
            local session = assert(AddonCheck.StartCheck(MODULE_ID))
            assert.equals(AddonCheck.State.FAILED, session.results[LEADER_GUID].state)
            assert.equals("provider_failed", session.results[LEADER_GUID].message)
            assert.equals(AddonCheck.SessionStatus.RUNNING, session.status)
            assert.equals(1, #AddonMessage.sent)
            assert.equals("RAID", AddonMessage.sent[1].chatType)
        end)

        it("marks remotes failed when the raid broadcast send fails", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            Group.members = {
                Group.members[1],
                Group.members[2],
            }
            AddonMessage.accepts = false
            AddonMessage.rejectReason = "AddonMessageThrottle"

            local session, reason = AddonCheck.StartCheck(MODULE_ID)
            assert.equals("AddonMessageThrottle", reason)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, session.status)
            assert.equals(AddonCheck.State.RESPONDED, session.results[LEADER_GUID].state)
            assert.equals(AddonCheck.State.FAILED, session.results[MEMBER_A_GUID].state)
            assert.equals("AddonMessageThrottle", session.results[MEMBER_A_GUID].message)
        end)

        it("ignores late responses after completion", function()
            AddonCheck.Register(MODULE_ID, function()
                return true
            end)
            local session = assert(AddonCheck.StartCheck(MODULE_ID, { timeout = 1 }))
            Timer.Advance(1)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, session.status)
            Deliver(OkResponse(session.correlationId, MODULE_ID), "WHISPER", MEMBER_A)
            assert.equals(AddonCheck.State.TIMED_OUT, session.results[MEMBER_A_GUID].state)
        end)
    end)
end)
