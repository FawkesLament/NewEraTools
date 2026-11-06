local Loader = require("helpers.loader")

describe("CoiledAltar interrupt assignment sync", function()
    local ns, Assignments, Sync, Group, AddonMessage, MessageProtocol, MessageProtocolComm, Timer, Module, printed
    local LEADER = "Leader-TestRealm"
    local MAX_TEXT = "一二三四五六七八九十甲乙"

    local function Member(name, index)
        return {
            name = name,
            fullName = name .. "-TestRealm",
            guid = name,
            index = index,
            subgroup = 1,
            classFile = "MAGE",
            role = "DAMAGER",
        }
    end

    local function ExampleRoster()
        local roster = { Member("Leader", 1) }
        for index = 2, 12 do
            roster[index] = Member("P" .. index, index)
        end
        return roster
    end

    local function Slot(slotType, value)
        return { type = slotType, value = value }
    end

    local function EmptyAssignments()
        return Assignments.SanitizeSaved({})
    end

    local function SnapshotOf(module)
        return {
            markedChain = module:GetMarkedChain(),
            assignments = ns.Util.DeepCopy(module:GetInterruptAssignments()),
        }
    end

    local function AllowRaid()
        Group.raidChatType = "RAID"
        Group.inRaid = true
        Group.raidLeaderFullName = LEADER
        Group.members = ExampleRoster()
    end

    local function StartModule()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        return Module
    end

    local function DeliverPayload(payload, opts)
        opts = opts or {}
        local wire = assert(
            MessageProtocol.Encode(
                opts.type or MessageProtocol.TYPE_EVENT,
                Sync.TOPIC,
                opts.correlationId or "-",
                payload
            )
        )
        AddonMessage.Deliver(
            MessageProtocolComm.PREFIX.CONTROL,
            wire,
            opts.channel or "RAID",
            opts.sender or LEADER
        )
    end

    local function DeliverBody(body, opts)
        local payloads = assert(Sync.WrapSnapshot(body, opts and opts.sid or "aa"))
        for _, payload in ipairs(payloads) do
            DeliverPayload(payload, opts)
        end
    end

    before_each(function()
        ns = Loader.Load()
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
        Sync = ns.Modules.Internals("CoiledAltar").InterruptSync
        Group = ns.Api.Group
        AddonMessage = ns.Api.AddonMessage
        MessageProtocol = ns.MessageProtocol
        MessageProtocolComm = ns.Api.MessageProtocolComm
        Timer = ns.Api.Timer
        printed = {}
        ns.Util.Print = function(message)
            printed[#printed + 1] = message
        end
        AllowRaid()
        MessageProtocolComm.Enable()
    end)

    describe("validation", function()
        it("accepts twelve empty slots and a marked-enemy side", function()
            local issues = Sync.Validate(EmptyAssignments(), Assignments.MELEE, ExampleRoster())
            assert.same({}, issues)
        end)

        it("accepts mixed members, custom text, empties, and delimiter text", function()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assignments.MELEE[2] = Slot(Assignments.TYPE_TEXT, "点名|近战")
            assignments.MELEE[3] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
            assignments.RANGED[1] = Slot(Assignments.TYPE_PLAYER, "P3-TestRealm")
            assignments.RANGED[6] = Slot(Assignments.TYPE_TEXT, "P2-TestRealm")
            local issues = Sync.Validate(assignments, Assignments.RANGED, ExampleRoster())
            assert.same({}, issues)
        end)

        it("does not treat custom text as a player assignment even when it matches a name", function()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_TEXT, "P2-TestRealm")
            assignments.RANGED[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assert.same({}, Sync.Validate(assignments, Assignments.MELEE, ExampleRoster()))
        end)

        it("rejects a player who is missing from the raid roster and names the slot", function()
            local assignments = EmptyAssignments()
            assignments.RANGED[4] = Slot(Assignments.TYPE_PLAYER, "Gone-TestRealm")
            local issues = Sync.Validate(assignments, Assignments.MELEE, ExampleRoster())
            assert.equals(1, #issues)
            assert.equals("player_missing", issues[1].code)
            assert.equals(Assignments.RANGED, issues[1].chainId)
            assert.equals(4, issues[1].index)
        end)

        it("rejects the same player on both chains and names the second slot", function()
            local assignments = EmptyAssignments()
            assignments.MELEE[2] = Slot(Assignments.TYPE_PLAYER, "P4-TestRealm")
            assignments.RANGED[5] = Slot(Assignments.TYPE_PLAYER, "P4-TestRealm")
            local issues = Sync.Validate(assignments, Assignments.MELEE, ExampleRoster())
            assert.equals("CROSS_CHAIN", issues[1].code)
            assert.equals(Assignments.RANGED, issues[1].chainId)
            assert.equals(5, issues[1].index)
        end)

        it("rejects custom text longer than the existing limit", function()
            local assignments = EmptyAssignments()
            assignments.MELEE[6] = Slot(Assignments.TYPE_TEXT, MAX_TEXT .. "丙")
            local issues = Sync.Validate(assignments, Assignments.MELEE, ExampleRoster())
            assert.equals("text_too_long", issues[1].code)
            assert.equals(Assignments.MELEE, issues[1].chainId)
            assert.equals(6, issues[1].index)
        end)
    end)

    describe("serialization", function()
        it("round-trips twelve empty slots", function()
            local roster = ExampleRoster()
            local body = assert(Sync.EncodeSnapshot(EmptyAssignments(), Assignments.MELEE, roster))
            assert.equals("M............", body)
            local snapshot = assert(Sync.DecodeSnapshot(body, roster))
            assert.equals(Assignments.MELEE, snapshot.markedChain)
            for index = 1, 6 do
                assert.equals(Assignments.TYPE_EMPTY, snapshot.assignments.MELEE[index].type)
                assert.equals(Assignments.TYPE_EMPTY, snapshot.assignments.RANGED[index].type)
            end
        end)

        it("encodes raid roster indices rather than names for player slots", function()
            local roster = ExampleRoster()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assignments.RANGED[6] = Slot(Assignments.TYPE_PLAYER, "P12-TestRealm")
            local body = assert(Sync.EncodeSnapshot(assignments, Assignments.RANGED, roster))
            assert.equals("Rp02..........p12", body)
            assert.is_nil(body:find("P2", 1, true))
            assert.is_nil(body:find("P12", 1, true))
            local snapshot = assert(Sync.DecodeSnapshot(body, roster))
            assert.equals(Assignments.RANGED, snapshot.markedChain)
            assert.same(Slot(Assignments.TYPE_PLAYER, "P2-TestRealm"), snapshot.assignments.MELEE[1])
            assert.same(Slot(Assignments.TYPE_PLAYER, "P12-TestRealm"), snapshot.assignments.RANGED[6])
        end)

        it("round-trips mixed members, custom text, empties, delimiters, and name-like text", function()
            local roster = ExampleRoster()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assignments.MELEE[2] = Slot(Assignments.TYPE_TEXT, "a|b|c")
            assignments.MELEE[3] = Slot(Assignments.TYPE_TEXT, "P2-TestRealm")
            assignments.MELEE[4] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
            assignments.RANGED[1] = Slot(Assignments.TYPE_PLAYER, "P3-TestRealm")
            local body = assert(Sync.EncodeSnapshot(assignments, Assignments.MELEE, roster))
            local snapshot = assert(Sync.ResolveSnapshot(body, roster))
            assert.same(assignments.MELEE[1], snapshot.assignments.MELEE[1])
            assert.same(assignments.MELEE[2], snapshot.assignments.MELEE[2])
            assert.equals(Assignments.TYPE_TEXT, snapshot.assignments.MELEE[3].type)
            assert.equals("P2-TestRealm", snapshot.assignments.MELEE[3].value)
            assert.equals(MAX_TEXT, snapshot.assignments.MELEE[4].value)
            assert.same(assignments.RANGED[1], snapshot.assignments.RANGED[1])
        end)

        it("encodes all twelve slots as raid members", function()
            local roster = ExampleRoster()
            local assignments = EmptyAssignments()
            for index = 1, 6 do
                assignments.MELEE[index] = Slot(Assignments.TYPE_PLAYER, "P" .. (index + 1) .. "-TestRealm")
            end
            for index = 1, 5 do
                assignments.RANGED[index] = Slot(Assignments.TYPE_PLAYER, "P" .. (index + 7) .. "-TestRealm")
            end
            assignments.RANGED[6] = Slot(Assignments.TYPE_PLAYER, "Leader-TestRealm")
            local body = assert(Sync.EncodeSnapshot(assignments, Assignments.MELEE, roster))
            assert.equals("Mp02p03p04p05p06p07p08p09p10p11p12p01", body)
            local snapshot = assert(Sync.ResolveSnapshot(body, roster))
            assert.same(assignments, snapshot.assignments)
        end)

        it("rejects malformed bodies and out-of-range roster indices", function()
            local roster = ExampleRoster()
            assert.is_nil(Sync.DecodeSnapshot("X............", roster))
            assert.is_nil(Sync.DecodeSnapshot("M...........", roster))
            assert.is_nil(Sync.DecodeSnapshot("Mp00...........", roster))
            assert.is_nil(Sync.DecodeSnapshot("Mp99...........", roster))
            assert.is_nil(Sync.DecodeSnapshot("Mpab...........", roster))
            local _, reason, detail = Sync.DecodeSnapshot("Mp40...........", roster)
            assert.equals("player_missing", reason)
            assert.equals(Assignments.MELEE, detail.chainId)
            assert.equals(1, detail.index)
        end)
    end)

    describe("multipart", function()
        local function MaxTextAssignments()
            local assignments = EmptyAssignments()
            for index = 1, 6 do
                assignments.MELEE[index] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
                assignments.RANGED[index] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
            end
            return assignments
        end

        it("keeps a small snapshot in one envelope at or under 255 bytes", function()
            local body = assert(Sync.EncodeSnapshot(EmptyAssignments(), Assignments.MELEE, ExampleRoster()))
            local payloads = assert(Sync.WrapSnapshot(body, "a0"))
            assert.equals(1, #payloads)
            local wire = assert(MessageProtocol.Encode(MessageProtocol.TYPE_EVENT, Sync.TOPIC, "-", payloads[1]))
            assert.is_true(#wire <= 255)
            assert.equals(body, select(1, Sync.Collect("Leader-TestRealm", payloads[1])))
        end)

        it("splits a snapshot that cannot fit in one 255-byte envelope", function()
            local body = assert(Sync.EncodeSnapshot(MaxTextAssignments(), Assignments.RANGED, ExampleRoster()))
            local payloads = assert(Sync.WrapSnapshot(body, "b1"))
            assert.is_true(#payloads > 1)
            for _, payload in ipairs(payloads) do
                local wire = assert(MessageProtocol.Encode(MessageProtocol.TYPE_EVENT, Sync.TOPIC, "-", payload))
                assert.is_true(#wire <= 255)
                local part = assert(Sync.ParsePart(payload))
                assert.equals("b1", part.sid)
                assert.equals(#payloads, part.total)
            end
            local collected
            for _, payload in ipairs(payloads) do
                collected = Sync.Collect("Leader-TestRealm", payload)
            end
            assert.equals(body, collected)
        end)

        it("reassembles out-of-order parts and ignores duplicate identical parts", function()
            local body = assert(Sync.EncodeSnapshot(MaxTextAssignments(), Assignments.MELEE, ExampleRoster()))
            local payloads = assert(Sync.WrapSnapshot(body, "c2"))
            assert.is_true(#payloads >= 2)
            assert.is_nil(Sync.Collect("Leader-TestRealm", payloads[2]))
            assert.is_nil(Sync.Collect("Leader-TestRealm", payloads[2]))
            local collected
            for index = #payloads, 1, -1 do
                collected = Sync.Collect("Leader-TestRealm", payloads[index]) or collected
            end
            assert.equals(body, collected)
        end)

        it("does not assemble when a part is missing and discards the rest after timeout", function()
            local body = assert(Sync.EncodeSnapshot(MaxTextAssignments(), Assignments.MELEE, ExampleRoster()))
            local payloads = assert(Sync.WrapSnapshot(body, "d3"))
            assert.is_nil(Sync.Collect("Leader-TestRealm", payloads[1]))
            Timer.Advance(Sync.REASSEMBLY_TIMEOUT)
            local collected
            for index = 2, #payloads do
                collected = Sync.Collect("Leader-TestRealm", payloads[index]) or collected
            end
            assert.is_nil(collected)
        end)

        it("replaces an incomplete snapshot when the same sender starts another", function()
            local first = assert(Sync.EncodeSnapshot(MaxTextAssignments(), Assignments.MELEE, ExampleRoster()))
            local secondAssignments = MaxTextAssignments()
            secondAssignments.MELEE[1] = Slot(Assignments.TYPE_TEXT, "第二份")
            local second = assert(Sync.EncodeSnapshot(secondAssignments, Assignments.RANGED, ExampleRoster()))
            local firstParts = assert(Sync.WrapSnapshot(first, "e4"))
            local secondParts = assert(Sync.WrapSnapshot(second, "e5"))
            assert.is_nil(Sync.Collect("Leader-TestRealm", firstParts[1]))
            local collected
            for _, payload in ipairs(secondParts) do
                collected = Sync.Collect("Leader-TestRealm", payload) or collected
            end
            assert.equals(second, collected)
            assert.is_nil(Sync.Collect("Leader-TestRealm", firstParts[2]))
        end)
    end)

    describe("publish", function()
        before_each(function()
            StartModule()
        end)

        it("sends CONTROL events and does not send when validation or raid context fails", function()
            assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 1, "P2-TestRealm"))
            assert.is_true(Sync.Publish())
            assert.is_true(#AddonMessage.sent >= 1)
            local sent = AddonMessage.sent[1]
            assert.equals(MessageProtocolComm.PREFIX.CONTROL, sent.prefix)
            assert.equals("RAID", sent.chatType)
            local decoded = assert(MessageProtocol.Decode(sent.message))
            assert.equals(Sync.TOPIC, decoded.topic)
            assert.equals(MessageProtocol.TYPE_EVENT, decoded.type)
            AddonMessage.sent = {}

            Module:AssignInterruptPlayer(Assignments.RANGED, 1, "P2-TestRealm")
            Module.db.assignments.RANGED[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assert.is_false(Sync.Publish())
            assert.equals(0, #AddonMessage.sent)

            Module.db.assignments.RANGED[1] = Slot(Assignments.TYPE_EMPTY)
            Group.raidChatType = nil
            assert.is_false(select(1, Sync.Publish()))
            assert.equals("not_in_raid", select(2, Sync.Publish()))
            assert.equals(0, #AddonMessage.sent)
        end)

        it("surfaces transport failures without claiming delivery", function()
            AddonMessage.accepts = false
            AddonMessage.rejectReason = "AddonMessageThrottle"
            local ok, reason = Sync.Publish()
            assert.is_false(ok)
            assert.equals("AddonMessageThrottle", reason)
            local text, kind = Sync.StatusText(ok, reason)
            assert.equals("error", kind)
            assert.equals(string.format(ns.L.COILED_ALTAR_INTERRUPT_SYNC_FAILED, "AddonMessageThrottle"), text)
        end)
    end)

    describe("reception", function()
        before_each(function()
            StartModule()
            Sync.Listen()
        end)

        local function ExampleBody()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            assignments.MELEE[2] = Slot(Assignments.TYPE_TEXT, "点名近战")
            assignments.RANGED[3] = Slot(Assignments.TYPE_PLAYER, "P5-TestRealm")
            return assert(Sync.EncodeSnapshot(assignments, Assignments.RANGED, ExampleRoster())), assignments
        end

        it("applies an authorized snapshot atomically, including marked-enemy side", function()
            Module:AssignInterruptPlayer(Assignments.MELEE, 6, "P3-TestRealm")
            Module:SetMarkedChain(Assignments.MELEE)
            local refreshed = 0
            Module.OnInterruptAssignmentsChanged = function()
                refreshed = refreshed + 1
            end
            local body, assignments = ExampleBody()
            DeliverBody(body)
            assert.equals(1, refreshed)
            assert.equals(Assignments.RANGED, Module:GetMarkedChain())
            assert.same(assignments.MELEE[1], Module:GetInterruptSlot(Assignments.MELEE, 1))
            assert.same(assignments.MELEE[2], Module:GetInterruptSlot(Assignments.MELEE, 2))
            assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, 6))
            assert.same(assignments.RANGED[3], Module:GetInterruptSlot(Assignments.RANGED, 3))
            assert.equals(ns.L.COILED_ALTAR_INTERRUPT_SYNC_RECEIVED, printed[1])
        end)

        it("applies delimiter custom text without treating it as a player name", function()
            local assignments = EmptyAssignments()
            assignments.MELEE[1] = Slot(Assignments.TYPE_TEXT, "a|b|c")
            assignments.MELEE[2] = Slot(Assignments.TYPE_TEXT, "P2-TestRealm")
            DeliverBody(assert(Sync.EncodeSnapshot(assignments, Assignments.MELEE, ExampleRoster())))
            assert.same(Slot(Assignments.TYPE_TEXT, "a|b|c"), Module:GetInterruptSlot(Assignments.MELEE, 1))
            assert.equals(Assignments.TYPE_TEXT, Module:GetInterruptSlot(Assignments.MELEE, 2).type)
        end)

        it("ignores unauthorized senders, own echoes, other types, and other channels", function()
            local before = SnapshotOf(Module)
            local body = ExampleBody()
            DeliverBody(body, { sender = "Stranger-TestRealm" })
            DeliverBody(body, { sender = ns.Api.Player.GetFullName() })
            Group.raidLeaderFullName = ns.Api.Player.GetFullName()
            DeliverBody(body, { sender = ns.Api.Player.GetFullName() })
            Group.raidLeaderFullName = LEADER
            DeliverBody(body, { type = MessageProtocol.TYPE_REQUEST, correlationId = "c1" })
            DeliverBody(body, { channel = "PARTY" })
            assert.same(before, SnapshotOf(Module))
            assert.equals(0, #printed)
        end)

        it("rejects a malformed or cross-chain snapshot without partial updates", function()
            local body = ExampleBody()
            DeliverBody(body)
            local before = SnapshotOf(Module)
            printed = {}
            DeliverPayload("garbage")
            local bad = EmptyAssignments()
            bad.MELEE[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            bad.RANGED[1] = Slot(Assignments.TYPE_PLAYER, "P2-TestRealm")
            local badBody = assert(Sync.EncodeSnapshot(bad, Assignments.MELEE, ExampleRoster()))
            -- EncodeSnapshot does not enforce cross-chain; wrap and deliver the invalid body.
            DeliverBody(badBody)
            assert.same(before, SnapshotOf(Module))
            assert.is_true(#printed >= 1)
        end)

        it("never applies an incomplete multipart snapshot", function()
            local assignments = EmptyAssignments()
            for index = 1, 6 do
                assignments.MELEE[index] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
                assignments.RANGED[index] = Slot(Assignments.TYPE_TEXT, MAX_TEXT)
            end
            local body = assert(Sync.EncodeSnapshot(assignments, Assignments.MELEE, ExampleRoster()))
            local payloads = assert(Sync.WrapSnapshot(body, "z9"))
            local before = SnapshotOf(Module)
            DeliverPayload(payloads[1])
            assert.same(before, SnapshotOf(Module))
            assert.equals(0, #printed)
        end)

        it("keeps synchronized assignments after a simulated reload", function()
            local body, assignments = ExampleBody()
            DeliverBody(body)
            local saved = {
                schemaVersion = 13,
                modules = {
                    CoiledAltar = {
                        assignments = Module.db.assignments,
                        markedChain = Module.db.markedChain,
                    },
                },
            }
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load(saved))
            Module = ns.Modules.Get("CoiledAltar")
            assert.equals(Assignments.RANGED, Module:GetMarkedChain())
            assert.same(assignments.MELEE[1], Module:GetInterruptSlot(Assignments.MELEE, 1))
            assert.same(assignments.MELEE[2], Module:GetInterruptSlot(Assignments.MELEE, 2))
            assert.same(assignments.RANGED[3], Module:GetInterruptSlot(Assignments.RANGED, 3))
        end)
    end)
end)
