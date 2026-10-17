local Harness = require("helpers.sszorak")

describe("Sszorak", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    describe("broadcasting", function()
        local Group, AddonMessage, MessageProtocol, MessageProtocolComm, printed

        local LEADER = "Leader-TestRealm"
        local TOPIC = "sszorak.edge_markers"

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
            Sszorak:ListenForBroadcasts()
        end)

        -- What the raid leader's copy sends for the current assignment.
        local function CaptureBroadcast()
            Sszorak:BroadcastEdgeMarkers()
            local sent = AddonMessage.sent[#AddonMessage.sent]
            return sent.prefix, sent.message
        end

        local function CaptureCustomBroadcast()
            Sszorak:SetEdgeMarker(2, "SKULL")
            Sszorak:SetEdgeMarker(3, "CROSS")
            local prefix, message = CaptureBroadcast()
            Sszorak:ResetEdgeMarkers()
            printed = {}
            return prefix, message
        end

        local function DeliverPayload(payload, channel, sender)
            local wire = assert(MessageProtocol.Encode(MessageProtocol.TYPE_EVENT, TOPIC, "-", payload))
            AddonMessage.Deliver(MessageProtocolComm.PREFIX.REALTIME, wire, channel, sender)
        end

        it("sends the assignment on the REALTIME prefix", function()
            Group.raidChatType = "INSTANCE_CHAT"
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(1, #AddonMessage.sent)
            assert.equals(MessageProtocolComm.PREFIX.REALTIME, AddonMessage.sent[1].prefix)
            assert.equals("INSTANCE_CHAT", AddonMessage.sent[1].chatType)
            local decoded = assert(MessageProtocol.Decode(AddonMessage.sent[1].message))
            assert.equals(MessageProtocol.TYPE_EVENT, decoded.type)
            assert.equals(TOPIC, decoded.topic)
            assert.equals("-", decoded.correlationId)
            assert.is_true(decoded.payload:find("^1:") ~= nil)
            assert.equals(ns.L.SSZORAK_BROADCAST_SENT, printed[1])
        end)

        it("is blocked outside a raid", function()
            Group.raidChatType = nil
            assert.is_false(Sszorak:CanBroadcastEdgeMarkers())
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(0, #AddonMessage.sent)
            assert.equals(0, #printed)
        end)

        it("is blocked when the player is not the raid leader", function()
            Group.isRaidLeader = false
            Group.isLeaderOrAssistant = false
            assert.is_false(Sszorak:CanBroadcastEdgeMarkers())
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(0, #AddonMessage.sent)
            assert.equals(0, #printed)
        end)

        it("says so when the game refuses the message", function()
            AddonMessage.accepts = false
            Sszorak:BroadcastEdgeMarkers()
            assert.equals(ns.L.SSZORAK_BROADCAST_FAILED, printed[1])
        end)

        it("adopts an assignment from the raid leader", function()
            local prefix, message = CaptureCustomBroadcast()
            local changes = 0
            Sszorak.OnEdgeMarkersChanged = function()
                changes = changes + 1
            end
            AddonMessage.Deliver(prefix, message, "RAID", LEADER)
            assert.equals("SKULL", Sszorak:GetEdgeMarker(2))
            assert.equals("CROSS", Sszorak:GetEdgeMarker(3))
            assert.equals(1, changes)
            assert.equals(string.format(ns.L.SSZORAK_MARKERS_RECEIVED, LEADER), printed[1])
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
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)

        it("ignores other payload format versions and invalid assignments", function()
            local _, message = CaptureCustomBroadcast()
            local payload = assert(MessageProtocol.Decode(message)).payload
            DeliverPayload((payload:gsub("^%d+:", "99:")), "RAID", LEADER)
            DeliverPayload("1:2=STAR,3=STAR", "RAID", LEADER)
            DeliverPayload("garbage", "RAID", LEADER)
            assert.is_true(Sszorak:IsDefaultEdgeMarkers())
        end)
    end)
end)
