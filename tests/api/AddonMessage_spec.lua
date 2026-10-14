local Loader = require("helpers.loader")

describe("AddonMessage", function()
    local AddonMessage

    before_each(function()
        AddonMessage = Loader.Load().Api.AddonMessage
    end)

    it("routes send and listen by prefix without cross-talk", function()
        local received = {}
        AddonMessage.Listen("TestPrefix", function(message, channel, sender)
            table.insert(received, { message = message, channel = channel, sender = sender })
        end)

        local ok, reason = AddonMessage.Send("TestPrefix", "payload", "RAID")
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.equals("TestPrefix", AddonMessage.sent[1].prefix)
        assert.equals("payload", AddonMessage.sent[1].message)
        assert.equals("RAID", AddonMessage.sent[1].chatType)

        AddonMessage.Deliver("TestPrefix", "inbound", "INSTANCE_CHAT", "Leader-Realm")
        assert.same({
            { message = "inbound", channel = "INSTANCE_CHAT", sender = "Leader-Realm" },
        }, received)
    end)

    it("maps traffic classes to NET_RT and NET_CTL", function()
        assert.equals("NET_RT", select(1, AddonMessage.PrefixForTrafficClass(AddonMessage.TrafficClass.REALTIME)))
        assert.equals("NET_CTL", select(1, AddonMessage.PrefixForTrafficClass(AddonMessage.TrafficClass.CONTROL)))
        assert.is_nil(select(1, AddonMessage.PrefixForTrafficClass("nope")))
        assert.equals("InvalidTrafficClass", select(2, AddonMessage.PrefixForTrafficClass("nope")))

        assert.is_true(AddonMessage.SendTraffic(AddonMessage.TrafficClass.REALTIME, "a", "RAID"))
        assert.is_true(AddonMessage.SendTraffic(AddonMessage.TrafficClass.CONTROL, "b", "RAID"))
        assert.equals(AddonMessage.PREFIX.REALTIME, AddonMessage.sent[1].prefix)
        assert.equals(AddonMessage.PREFIX.CONTROL, AddonMessage.sent[2].prefix)
    end)

    it("ListenProtocol registers realtime and control prefixes", function()
        local hits = 0
        assert.is_true(AddonMessage.ListenProtocol(function()
            hits = hits + 1
        end))
        AddonMessage.Deliver(AddonMessage.PREFIX.REALTIME, "1", "RAID", "A-R")
        AddonMessage.Deliver(AddonMessage.PREFIX.CONTROL, "2", "RAID", "B-R")
        assert.equals(2, hits)
    end)

    it("ListenProtocol rolls back earlier prefixes when a later one fails", function()
        AddonMessage.registerRejectPrefixes[AddonMessage.PREFIX.CONTROL] = true
        local ok, reason, failedPrefix = AddonMessage.ListenProtocol(function() end)
        assert.is_false(ok)
        assert.equals("RegisterFailed", reason)
        assert.equals(AddonMessage.PREFIX.CONTROL, failedPrefix)
        assert.is_nil(AddonMessage.listeners[AddonMessage.PREFIX.REALTIME])
        assert.is_nil(AddonMessage.listeners[AddonMessage.PREFIX.CONTROL])

        AddonMessage.registerRejectPrefixes[AddonMessage.PREFIX.CONTROL] = nil
        assert.is_true(AddonMessage.ListenProtocol(function() end))
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.REALTIME]))
        assert.equals("function", type(AddonMessage.listeners[AddonMessage.PREFIX.CONTROL]))
    end)

    it("surfaces registration failures from Listen", function()
        AddonMessage.registerAccepts = false
        local ok, reason = AddonMessage.Listen("TestPrefix", function() end)
        assert.is_false(ok)
        assert.equals("RegisterFailed", reason)
        assert.is_nil(AddonMessage.listeners.TestPrefix)
    end)

    it("rejects invalid prefixes and oversized or null-containing bodies", function()
        assert.is_false(select(1, AddonMessage.Send("", "x", "RAID")))
        assert.equals("InvalidPrefix", select(2, AddonMessage.Send("", "x", "RAID")))
        assert.is_false(select(1, AddonMessage.Send(string.rep("p", 17), "x", "RAID")))
        assert.is_false(select(1, AddonMessage.Send("ok", string.rep("x", 256), "RAID")))
        assert.equals("InvalidMessage", select(2, AddonMessage.Send("ok", "a\0b", "RAID")))
        assert.equals(0, #AddonMessage.sent)
    end)

    it("surfaces transport rejection reasons", function()
        AddonMessage.accepts = false
        AddonMessage.rejectReason = "AddOnMessageLockdown"
        local ok, reason = AddonMessage.Send("TestPrefix", "body", "RAID")
        assert.is_false(ok)
        assert.equals("AddOnMessageLockdown", reason)
        assert.equals(1, #AddonMessage.sent)
    end)

    it("allows one listener per prefix without cross-talk", function()
        local a, b = 0, 0
        AddonMessage.Listen("PrefixA", function()
            a = a + 1
        end)
        AddonMessage.Listen("PrefixB", function()
            b = b + 1
        end)
        assert.is_false(pcall(AddonMessage.Listen, "PrefixA", function() end))

        AddonMessage.Deliver("PrefixA", "1", "RAID", "A-R")
        AddonMessage.Deliver("PrefixB", "2", "RAID", "B-R")
        assert.equals(1, a)
        assert.equals(1, b)
    end)
end)
