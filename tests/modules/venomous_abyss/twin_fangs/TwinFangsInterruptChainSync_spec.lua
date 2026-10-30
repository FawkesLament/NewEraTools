local Loader = require("helpers.loader")

describe("TwinFangs interrupt chain sync", function()
    local ns, Chain, Group, AddonMessage, MessageProtocol, MessageProtocolComm, printed

    local function Member(guid, subgroup, index)
        return {
            name = guid,
            fullName = guid .. "-TestRealm",
            guid = guid,
            index = index,
            subgroup = subgroup,
            classFile = "MAGE",
            role = "DAMAGER",
        }
    end

    local function Player(guid)
        return { name = guid .. "-TestRealm" }
    end

    local function Snapshot(state)
        local copy = {}
        for _, regionId in ipairs(Chain.REGION_IDS) do
            copy[regionId] = Chain.GetRegion(state, regionId)
        end
        return copy
    end

    local function AllowPublish()
        Group.raidChatType = "RAID"
    end

    local function FillExample(state)
        local roster = {
            Member("LF1", 1, 1),
            Member("LF2", 1, 2),
            Member("LF3", 1, 3),
            Member("LF4", 1, 4),
            Member("LF5", 1, 5),
            Member("RF1", 2, 6),
            Member("RF2", 2, 7),
            Member("RF3", 2, 8),
            Member("RF4", 2, 9),
            Member("RF5", 2, 10),
            Member("LB1", 3, 11),
            Member("LB2", 3, 12),
            Member("LB3", 3, 13),
            Member("LB4", 3, 14),
            Member("LB5", 3, 15),
            Member("RB1", 4, 16),
            Member("RB2", 4, 17),
            Member("RB3", 4, 18),
            Member("RB4", 4, 19),
            Member("RB5", 4, 20),
            Member("B61", 6, 21),
            Member("B51", 5, 22),
            Member("B52", 5, 23),
        }
        Chain.SetRoster(state, roster)
        state.regions[Chain.FRONT_LEFT] = {
            group = 1,
            players = { Player("LF1"), Player("LF5"), Player("LF3"), Player("LF2"), Player("LF4") },
            backup = Player("B52"),
            channel = "say",
        }
        state.regions[Chain.FRONT_RIGHT] = {
            group = 2,
            players = { Player("RF3"), Player("RF1"), Player("RF4"), Player("RF2"), Player("RF5") },
            backup = nil,
        }
        state.regions[Chain.BACK_LEFT] = {
            group = 3,
            players = { Player("LB1"), Player("LB2"), Player("LB3"), Player("LB4"), Player("LB5") },
            backup = Player("B61"),
            channel = "yell",
        }
        state.regions[Chain.BACK_RIGHT] = {
            group = 4,
            players = { Player("RB2"), Player("RB5"), Player("RB1"), Player("RB3"), Player("RB4") },
            backup = nil,
        }
        return roster
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Group = ns.Api.Group
        AddonMessage = ns.Api.AddonMessage
        MessageProtocol = ns.MessageProtocol
        MessageProtocolComm = ns.Api.MessageProtocolComm
        printed = {}
        ns.Util.Print = function(message)
            printed[#printed + 1] = message
        end
        AllowPublish()
        MessageProtocolComm.Enable()
    end)

    it("maps display names to subgroup slots in Auto Assign roster-index order", function()
        local roster = {
            Member("late", 1, 30),
            Member("first", 1, 2),
            Member("mid", 1, 10),
            Member("other", 2, 3),
        }
        local positions = Chain.SubgroupPositions(roster)
        assert.same({ group = 1, position = 1 }, positions["first-TestRealm"])
        assert.same({ group = 1, position = 2 }, positions["mid-TestRealm"])
        assert.same({ group = 1, position = 3 }, positions["late-TestRealm"])
        assert.same({ group = 2, position = 1 }, positions["other-TestRealm"])
    end)

    it("encodes Player and Vehicle roster names the same way", function()
        local vehicle = "Vehicle-0-1-2-3-4-99"
        local player = "Player-0-AAA"
        local positions = Chain.SubgroupPositions({
            Member(vehicle, 8, 1),
            Member(player, 8, 2),
        })
        assert.same({ group = 8, position = 1 }, positions[vehicle .. "-TestRealm"])
        assert.same({ group = 8, position = 2 }, positions[player .. "-TestRealm"])
        local state = Chain.NewState()
        Chain.SetRoster(state, {
            Member(vehicle, 8, 1),
            Member(player, 7, 2),
        })
        state.regions[Chain.FRONT_LEFT].group = 8
        state.regions[Chain.FRONT_LEFT].players = { Player(vehicle) }
        state.regions[Chain.FRONT_LEFT].backup = Player(player)
        state.regions[Chain.FRONT_LEFT].channel = "say"
        assert.equals("1|8:1:71:s|:::p|:::p|:::p", Chain.EncodePublication(state))
        assert.is_true(Chain.Publish(state))
        assert.equals("1|8:1:71:s|:::p|:::p|:::p", MessageProtocol.Decode(AddonMessage.sent[1].message).payload)
    end)

    it("encodes LF/RF/LB/RB, interrupt order, backups, and empty fields", function()
        local state = Chain.NewState()
        FillExample(state)
        assert.equals("1|1:15324:52:s|2:31425::p|3:12345:61:y|4:25134::p", Chain.EncodePublication(state))
    end)

    it("encodes consecutive repeats as repeated subgroup-position digits", function()
        local state = Chain.NewState()
        FillExample(state)
        state.regions[Chain.FRONT_LEFT].players = {
            Player("LF1"),
            Player("LF2"),
            Player("LF2"),
            Player("LF2"),
            Player("LF3"),
        }
        assert.equals("1|1:12223:52:s|2:31425::p|3:12345:61:y|4:25134::p", Chain.EncodePublication(state))
        assert.is_true(Chain.Publish(state))
        assert.equals("1|1:12223:52:s|2:31425::p|3:12345:61:y|4:25134::p", MessageProtocol.Decode(AddonMessage.sent[1].message).payload)
    end)

    it("encodes a maximum-length 15-turn region", function()
        local state = Chain.NewState()
        local roster = {}
        local players = {}
        for index = 1, 5 do
            local guid = "G1P" .. index
            roster[index] = Member(guid, 1, index)
            for _ = 1, 3 do
                players[#players + 1] = Player(guid)
            end
        end
        Chain.SetRoster(state, roster)
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = players
        assert.equals("1|1:111222333444555::p|:::p|:::p|:::p", Chain.EncodePublication(state))
    end)

    it("rejects four consecutive repeats and nonconsecutive duplicates before sending", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, {
            Member("A", 1, 1),
            Member("B", 1, 2),
        })
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = { Player("A"), Player("A"), Player("A"), Player("A") }
        assert.is_nil(Chain.EncodePublication(state))
        state.regions[Chain.FRONT_LEFT].players = { Player("A"), Player("B"), Player("A") }
        assert.is_nil(Chain.EncodePublication(state))
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
    end)

    it("encodes empty chains, missing backups, and unassigned regions", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, { Member("solo", 4, 1) })
        state.regions[Chain.BACK_LEFT].group = 4
        assert.equals("1|:::p|:::p|4:::p|:::p", Chain.EncodePublication(state))
    end)

    it("sends one CONTROL event with the encoded payload", function()
        local state = Chain.NewState()
        FillExample(state)
        assert.is_true(Chain.Publish(state))
        assert.equals(1, #AddonMessage.sent)
        local sent = AddonMessage.sent[1]
        assert.equals(MessageProtocolComm.PREFIX.CONTROL, sent.prefix)
        assert.equals("RAID", sent.chatType)
        local decoded = assert(MessageProtocol.Decode(sent.message))
        assert.equals(MessageProtocol.TYPE_EVENT, decoded.type)
        assert.equals(Chain.SYNC_TOPIC, decoded.topic)
        assert.equals(MessageProtocol.EVENT_CORRELATION_ID, decoded.correlationId)
        assert.equals("1|1:15324:52:s|2:31425::p|3:12345:61:y|4:25134::p", decoded.payload)
        assert.equals(string.format(ns.L.TWIN_FANGS_INTERRUPT_SYNC_SENT, ns.L.TWIN_FANGS_TITLE), printed[1])
        assert.equals(1, #printed)
        assert.is_false(state.dirty)
    end)

    it("does not send when the player is not in a raid", function()
        local state = Chain.NewState()
        FillExample(state)
        Group.raidChatType = nil
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_NOT_IN_RAID, printed[1])
        assert.is_true(state.dirty)
    end)

    it("does not send an invalid configuration and leaves assignments unchanged", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, { Member("A", 1, 1), Member("B", 2, 2) })
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = { Player("A") }
        state.regions[Chain.FRONT_RIGHT].group = 2
        state.regions[Chain.FRONT_RIGHT].players = { Player("A") }
        local before = Snapshot(state)
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
        assert.is_true(#printed == 1)
        assert.same(before, Snapshot(state))
        assert.is_true(state.dirty)
    end)

    it("does not send when a configured player is missing from the roster", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, { Member("A", 1, 1) })
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = { Player("gone") }
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
    end)

    it("does not send a party-channel backup", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, {
            Member("A", 1, 1),
            Member("B", 2, 2),
        })
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = { Player("A") }
        state.regions[Chain.FRONT_LEFT].backup = Player("B")
        local before = Snapshot(state)
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
        assert.same(before, Snapshot(state))
        assert.is_true(state.dirty)
    end)

    it("does not send a same-group or shared backup", function()
        local state = Chain.NewState()
        Chain.SetRoster(state, {
            Member("A", 1, 1),
            Member("B", 1, 2),
            Member("C", 2, 3),
        })
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = { Player("A") }
        state.regions[Chain.FRONT_LEFT].backup = Player("B")
        state.regions[Chain.FRONT_RIGHT].group = 2
        state.regions[Chain.FRONT_RIGHT].players = { Player("C") }
        state.regions[Chain.FRONT_RIGHT].backup = Player("B")
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
    end)

    it("rejects a sixth subgroup slot before sending", function()
        local state = Chain.NewState()
        local roster = {}
        local players = {}
        for index = 1, 6 do
            local guid = "G1P" .. index
            roster[index] = Member(guid, 1, index)
            players[index] = Player(guid)
        end
        Chain.SetRoster(state, roster)
        state.regions[Chain.FRONT_LEFT].group = 1
        state.regions[Chain.FRONT_LEFT].players = players
        assert.is_nil(Chain.EncodePublication(state))
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
    end)

    it("validates envelope size before any send", function()
        local state = Chain.NewState()
        FillExample(state)
        local encode = MessageProtocol.Encode
        MessageProtocol.Encode = function()
            return nil, "too_large"
        end
        assert.is_nil(select(1, Chain.EncodePublication(state)))
        assert.is_false(Chain.Publish(state))
        MessageProtocol.Encode = encode
        assert.equals(0, #AddonMessage.sent)
        assert.equals(ns.L.TWIN_FANGS_INTERRUPT_SYNC_TOO_LARGE, printed[1])
    end)

    it("does not claim success when the transport rejects the message", function()
        local state = Chain.NewState()
        FillExample(state)
        AddonMessage.accepts = false
        AddonMessage.rejectReason = "AddonMessageThrottle"
        local before = Snapshot(state)
        assert.is_false(Chain.Publish(state))
        assert.equals(1, #AddonMessage.sent)
        assert.equals(string.format(ns.L.TWIN_FANGS_INTERRUPT_SYNC_FAILED, "AddonMessageThrottle"), printed[1])
        assert.is_true(state.dirty)
        assert.same(before, Snapshot(state))
    end)

    it("does not overlap a publication already in progress", function()
        local state = Chain.NewState()
        FillExample(state)
        local send = MessageProtocolComm.Send
        local nested
        MessageProtocolComm.Send = function(...)
            nested = { Chain.Publish(state) }
            return send(...)
        end
        assert.is_true(Chain.Publish(state))
        MessageProtocolComm.Send = send
        assert.same({ false, "in_progress" }, nested)
        assert.equals(1, #AddonMessage.sent)
        assert.equals(1, #printed)
        assert.equals(string.format(ns.L.TWIN_FANGS_INTERRUPT_SYNC_SENT, ns.L.TWIN_FANGS_TITLE), printed[1])
    end)

    it("does not mutate persisted assignments on a successful send", function()
        ns.Modules.Start(ns.Database.Load(nil))
        local module = ns.Modules.Get("TwinFangs")
        local state = Chain.NewState(module.db.interruptReminder.chain)
        FillExample(state)
        local before = Snapshot(state)
        assert.is_true(Chain.Publish(state))
        assert.same(before, Snapshot(state))
        assert.same(before[Chain.FRONT_LEFT].players, module.db.interruptReminder.chain.front_left.players)
    end)

    it("encodes all six communication channels on the four regions", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        local state = Chain.NewState()
        FillExample(state)
        local channels = {
            [Chain.FRONT_LEFT] = Schema.CHANNEL_SAY,
            [Chain.FRONT_RIGHT] = Schema.CHANNEL_YELL,
            [Chain.BACK_LEFT] = Schema.CHANNEL_EMOTE,
            [Chain.BACK_RIGHT] = Schema.CHANNEL_NOD,
        }
        for regionId, channel in pairs(channels) do
            state.regions[regionId].channel = channel
        end
        assert.equals("1|1:15324:52:s|2:31425::y|3:12345:61:e|4:25134::n", Chain.EncodePublication(state))
        state.regions[Chain.FRONT_LEFT].channel = Schema.CHANNEL_PARTY
        state.regions[Chain.FRONT_RIGHT].channel = Schema.CHANNEL_MARKER
        state.regions[Chain.BACK_LEFT].channel = Schema.CHANNEL_PARTY
        state.regions[Chain.BACK_RIGHT].channel = Schema.CHANNEL_PARTY
        assert.equals("1|1:15324:52:p|2:31425::m|3:12345:61:p|4:25134::p", Chain.EncodePublication(state))
    end)

    it("does not send conflicting exclusive channels", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        local state = Chain.NewState()
        FillExample(state)
        state.regions[Chain.FRONT_LEFT].channel = Schema.CHANNEL_NOD
        state.regions[Chain.FRONT_RIGHT].channel = Schema.CHANNEL_NOD
        local before = Snapshot(state)
        assert.is_false(Chain.Publish(state))
        assert.equals(0, #AddonMessage.sent)
        assert.same(before, Snapshot(state))
        assert.is_true(state.dirty)
    end)

    it("registers no inbound handler for the topic", function()
        local registered = 0
        local register = MessageProtocol.RegisterHandler
        MessageProtocol.RegisterHandler = function(...)
            registered = registered + 1
            return register(...)
        end
        local state = Chain.NewState()
        FillExample(state)
        Chain.Publish(state)
        MessageProtocol.RegisterHandler = register
        assert.equals(0, registered)
        local sent = AddonMessage.sent[1]
        local chain = Snapshot(state)
        AddonMessage.Deliver(sent.prefix, sent.message, "RAID", "Leader-TestRealm")
        assert.same(chain, Snapshot(state))
    end)
end)
