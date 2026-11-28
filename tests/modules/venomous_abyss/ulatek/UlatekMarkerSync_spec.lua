local Loader = require("helpers.loader")

describe("Ulatek corner-marker sync", function()
    local ns, Ulatek

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Ulatek = ns.Modules.Get("Ulatek")
    end)

    describe("broadcasting", function()
        local Group, AddonMessage, MessageProtocol, MessageProtocolComm, printed

        local LEADER = "Leader-TestRealm"
        local TOPIC = "ulatek.corner_markers"

        before_each(function()
            Group = ns.Api.Group
            AddonMessage = ns.Api.AddonMessage
            MessageProtocol = ns.MessageProtocol
            MessageProtocolComm = ns.Api.MessageProtocolComm
            printed = {}
            ns.Util.Print = function(message)
                table.insert(printed, message)
            end
            Group.raidChatType = "RAID"
            Group.isRaidLeader = true
            Group.isLeaderOrAssistant = true
            MessageProtocolComm.Enable()
            Ulatek:ListenForBroadcasts()
        end)

        local function CaptureBroadcast()
            Ulatek:BroadcastCornerMarkers()
            local sent = AddonMessage.sent[#AddonMessage.sent]
            return sent.prefix, sent.message
        end

        local function CaptureCustomBroadcast()
            Ulatek:SetCornerMarker(1, "MOON")
            local prefix, message = CaptureBroadcast()
            Ulatek:ResetCornerMarkers()
            printed = {}
            return prefix, message
        end

        local function DeliverPayload(payload, channel, sender)
            local wire = assert(MessageProtocol.Encode(MessageProtocol.TYPE_EVENT, TOPIC, "-", payload))
            AddonMessage.Deliver(MessageProtocolComm.PREFIX.REALTIME, wire, channel, sender)
        end

        it("sends raid-target indexes in corner order on the REALTIME prefix", function()
            Group.raidChatType = "INSTANCE_CHAT"
            Ulatek:BroadcastCornerMarkers()
            assert.equals(1, #AddonMessage.sent)
            assert.equals(MessageProtocolComm.PREFIX.REALTIME, AddonMessage.sent[1].prefix)
            assert.equals("INSTANCE_CHAT", AddonMessage.sent[1].chatType)
            local decoded = assert(MessageProtocol.Decode(AddonMessage.sent[1].message))
            assert.equals(MessageProtocol.TYPE_EVENT, decoded.type)
            assert.equals(TOPIC, decoded.topic)
            assert.equals("-", decoded.correlationId)
            assert.equals("12345678", decoded.payload)
            assert.equals(ns.L.ULATEK_BROADCAST_SENT, printed[1])
        end)

        it("is blocked outside a raid", function()
            Group.raidChatType = nil
            assert.is_false(Ulatek:CanBroadcastCornerMarkers())
            Ulatek:BroadcastCornerMarkers()
            assert.equals(0, #AddonMessage.sent)
            assert.equals(0, #printed)
        end)

        it("is blocked when the player is not the raid leader", function()
            Group.isRaidLeader = false
            Group.isLeaderOrAssistant = false
            assert.is_false(Ulatek:CanBroadcastCornerMarkers())
            Ulatek:BroadcastCornerMarkers()
            assert.equals(0, #AddonMessage.sent)
            assert.equals(0, #printed)
        end)

        it("says so when the game refuses the message", function()
            AddonMessage.accepts = false
            Ulatek:BroadcastCornerMarkers()
            assert.equals(ns.L.ULATEK_BROADCAST_FAILED, printed[1])
        end)

        it("adopts an assignment from the raid leader", function()
            local prefix, message = CaptureCustomBroadcast()
            local changes = 0
            Ulatek.OnCornerMarkersChanged = function()
                changes = changes + 1
            end
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.equals("MOON", Ulatek:GetCornerMarker(1))
            assert.equals("STAR", Ulatek:GetCornerMarker(5))
            assert.equals(1, changes)
            assert.equals(string.format(ns.L.ULATEK_MARKERS_RECEIVED, LEADER), printed[1])
        end)

        it("stays quiet when the assignment is already in place", function()
            local prefix, message = CaptureBroadcast()
            printed = {}
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.equals(0, #printed)
        end)

        it("ignores messages from outside the current raid's channel", function()
            local _, message = CaptureCustomBroadcast()
            local payload = assert(MessageProtocol.Decode(message)).payload
            DeliverPayload(payload, "PARTY", LEADER)
            Group.raidChatType = nil
            DeliverPayload(payload, "RAID", LEADER)
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
        end)

        it("ignores payloads that are not a permutation of 1–8", function()
            DeliverPayload("52341678", "RAID", LEADER)
            assert.equals("MOON", Ulatek:GetCornerMarker(1))
            Ulatek:ResetCornerMarkers()
            DeliverPayload("1234567", "RAID", LEADER)
            DeliverPayload("12345679", "RAID", LEADER)
            DeliverPayload("11345678", "RAID", LEADER)
            DeliverPayload("garbage", "RAID", LEADER)
            assert.is_true(Ulatek:IsDefaultCornerMarkers())
        end)
    end)
end)
