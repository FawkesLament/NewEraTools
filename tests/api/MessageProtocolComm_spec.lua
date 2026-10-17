local Loader = require("helpers.loader")

describe("MessageProtocolComm", function()
    local ns
    local MessageProtocol
    local MessageProtocolComm
    local AddonMessage

    before_each(function()
        ns = Loader.Load()
        MessageProtocol = ns.MessageProtocol
        MessageProtocolComm = ns.Api.MessageProtocolComm
        AddonMessage = ns.Api.AddonMessage
        MessageProtocolComm.Enable()
    end)

    it("does not attach transport methods onto MessageProtocol", function()
        assert.is_nil(MessageProtocol.Enable)
        assert.is_nil(MessageProtocol.Send)
        assert.is_nil(MessageProtocol.PREFIX)
        assert.is_nil(MessageProtocol.TrafficClass)
        assert.equals(AddonMessage.PREFIX, MessageProtocolComm.PREFIX)
        assert.equals(AddonMessage.TrafficClass, MessageProtocolComm.TrafficClass)
    end)

    it("defaults Send to the CONTROL prefix", function()
        local ok, reason = MessageProtocolComm.Send("E", "example", "-", "hello", "RAID")
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.equals(1, #AddonMessage.sent)
        assert.equals(AddonMessage.PREFIX.CONTROL, AddonMessage.sent[1].prefix)
        assert.equals("RAID", AddonMessage.sent[1].chatType)
        assert.equals("1|E|example|-|hello", AddonMessage.sent[1].message)
        assert.is_nil(AddonMessage.sent[1].target)
    end)

    it("sends REALTIME traffic on NET_RT", function()
        local ok = MessageProtocolComm.Send("E", "example", "-", "hello", "RAID", {
            trafficClass = MessageProtocolComm.TrafficClass.REALTIME,
        })
        assert.is_true(ok)
        assert.equals(1, #AddonMessage.sent)
        assert.equals(AddonMessage.PREFIX.REALTIME, AddonMessage.sent[1].prefix)
    end)

    it("forwards an optional whisper target to AddonMessage", function()
        local ok = MessageProtocolComm.Send("Q", "whisper.demo", "c1", "ping", "WHISPER", "Target-Realm")
        assert.is_true(ok)
        assert.equals("WHISPER", AddonMessage.sent[1].chatType)
        assert.equals("Target-Realm", AddonMessage.sent[1].target)
    end)

    it("accepts target inside the options table", function()
        local ok = MessageProtocolComm.Send("Q", "whisper.demo", "c1", "ping", "WHISPER", {
            target = "Target-Realm",
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        })
        assert.is_true(ok)
        assert.equals("Target-Realm", AddonMessage.sent[1].target)
        assert.equals(AddonMessage.PREFIX.CONTROL, AddonMessage.sent[1].prefix)
    end)

    it("merges a seventh options table over a sixth options table", function()
        local ok = MessageProtocolComm.Send("E", "example", "-", "hello", "RAID", {
            target = "Ignored-Realm",
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        }, {
            trafficClass = MessageProtocolComm.TrafficClass.REALTIME,
        })
        assert.is_true(ok)
        assert.equals(AddonMessage.PREFIX.REALTIME, AddonMessage.sent[1].prefix)
        assert.equals("Ignored-Realm", AddonMessage.sent[1].target)
    end)

    it("rejects WHISPER without a target", function()
        local ok, reason = MessageProtocolComm.Send("Q", "whisper.demo", "c1", "ping", "WHISPER")
        assert.is_false(ok)
        assert.equals("InvalidTarget", reason)
        assert.equals(0, #AddonMessage.sent)

        ok, reason = MessageProtocolComm.Send("Q", "whisper.demo", "c1", "ping", "WHISPER", {
            trafficClass = MessageProtocolComm.TrafficClass.CONTROL,
        })
        assert.is_false(ok)
        assert.equals("InvalidTarget", reason)
        assert.equals(0, #AddonMessage.sent)

        ok, reason = MessageProtocolComm.Send("Q", "whisper.demo", "c1", "ping", "WHISPER", "")
        assert.is_false(ok)
        assert.equals("InvalidTarget", reason)
        assert.equals(0, #AddonMessage.sent)
    end)

    it("rejects an empty or non-string channel before sending", function()
        local ok, reason = MessageProtocolComm.Send("E", "example", "-", "x", "")
        assert.is_false(ok)
        assert.equals("InvalidChannel", reason)
        assert.equals(0, #AddonMessage.sent)

        ok, reason = MessageProtocolComm.Send("E", "example", "-", "x", nil)
        assert.is_false(ok)
        assert.equals("InvalidChannel", reason)
        assert.equals(0, #AddonMessage.sent)
    end)

    it("surfaces encode and transport failures without claiming delivery", function()
        local ok, reason = MessageProtocolComm.Send("E", "bad topic", "-", "x", "RAID")
        assert.is_false(ok)
        assert.equals("invalid_topic", reason)
        assert.equals(0, #AddonMessage.sent)

        AddonMessage.accepts = false
        AddonMessage.rejectReason = "AddonMessageThrottle"
        ok, reason = MessageProtocolComm.Send("E", "example", "-", "x", "RAID")
        assert.is_false(ok)
        assert.equals("AddonMessageThrottle", reason)
    end)

    it("rejects unknown traffic classes", function()
        local ok, reason = MessageProtocolComm.Send("E", "example", "-", "x", "RAID", {
            trafficClass = "BULK",
        })
        assert.is_false(ok)
        assert.equals("InvalidTrafficClass", reason)
        assert.equals(0, #AddonMessage.sent)
    end)

    it("routes inbound traffic from every protocol prefix to registered handlers", function()
        local seen = {}
        MessageProtocol.RegisterHandler("example", function(msg)
            table.insert(seen, {
                sender = msg.sender,
                channel = msg.channel,
                payload = msg.payload,
            })
        end)

        AddonMessage.Deliver(AddonMessage.PREFIX.CONTROL, "1|E|example|-|hello", "RAID", "Ctl-Realm")
        AddonMessage.Deliver(AddonMessage.PREFIX.REALTIME, "1|E|example|-|hello", "INSTANCE_CHAT", "Rt-Realm")

        assert.same({
            { sender = "Ctl-Realm", channel = "RAID", payload = "hello" },
            { sender = "Rt-Realm", channel = "INSTANCE_CHAT", payload = "hello" },
        }, seen)
    end)

    it("does not consume other AddonMessage prefixes", function()
        local otherCalls = 0
        local protocolCalls = 0
        AddonMessage.Listen("OtherPrefix", function()
            otherCalls = otherCalls + 1
        end)
        MessageProtocol.RegisterHandler("example", function()
            protocolCalls = protocolCalls + 1
        end)

        AddonMessage.Deliver("OtherPrefix", "raw-body", "RAID", "Leader-Realm")
        AddonMessage.Deliver(AddonMessage.PREFIX.CONTROL, "1|E|example|-|x", "RAID", "Leader-Realm")

        assert.equals(1, otherCalls)
        assert.equals(1, protocolCalls)
    end)

    it("Enable is idempotent and keeps protocol prefix listeners", function()
        MessageProtocolComm.Enable()
        MessageProtocolComm.Enable()
        local ok = pcall(function()
            -- A second Listen on a managed prefix would assert inside the fake.
            AddonMessage.Listen(AddonMessage.PREFIX.CONTROL, function() end)
        end)
        assert.is_false(ok)
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.REALTIME]))
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.CONTROL]))
    end)

    it("Enable can retry after a rolled-back partial registration failure", function()
        ns = Loader.Load()
        MessageProtocolComm = ns.Api.MessageProtocolComm
        AddonMessage = ns.Api.AddonMessage

        AddonMessage.registerRejectPrefixes[AddonMessage.PREFIX.CONTROL] = true
        local ok, reason, failedPrefix = MessageProtocolComm.Enable()
        assert.is_false(ok)
        assert.equals("RegisterFailed", reason)
        assert.equals(AddonMessage.PREFIX.CONTROL, failedPrefix)
        assert.is_nil(AddonMessage.listeners[AddonMessage.PREFIX.REALTIME])
        assert.is_nil(AddonMessage.listeners[AddonMessage.PREFIX.CONTROL])

        AddonMessage.registerRejectPrefixes[AddonMessage.PREFIX.CONTROL] = nil
        assert.is_true(MessageProtocolComm.Enable())
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.REALTIME]))
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.CONTROL]))
        assert.is_true(MessageProtocolComm.Enable())
    end)
end)
