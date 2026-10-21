local Loader = require("helpers.loader")

describe("MessageProtocol", function()
    local MessageProtocol

    before_each(function()
        MessageProtocol = Loader.Load().MessageProtocol
    end)

    local function RoundTrip(messageType, topic, correlationId, payload)
        local wire, encodeReason = MessageProtocol.Encode(messageType, topic, correlationId, payload)
        assert.is_nil(encodeReason, encodeReason)
        local decoded, decodeReason = MessageProtocol.Decode(wire)
        assert.is_nil(decodeReason, decodeReason)
        return wire, decoded
    end

    it("round-trips encoding and decoding", function()
        local wire, decoded = RoundTrip("E", "example", "-", "hello")
        assert.equals("1|E|example|-|hello", wire)
        assert.same({
            version = 1,
            type = "E",
            topic = "example",
            correlationId = "-",
            payload = "hello",
        }, decoded)
    end)

    it("round-trips empty payloads", function()
        local wire, decoded = RoundTrip("E", "example", "-", "")
        assert.equals("1|E|example|-|", wire)
        assert.equals("", decoded.payload)

        local nilPayloadWire = MessageProtocol.Encode("Q", "example", "a7", nil)
        assert.equals("1|Q|example|a7|", nilPayloadWire)
        assert.equals("", MessageProtocol.Decode(nilPayloadWire).payload)
    end)

    it("preserves payloads that contain pipe characters", function()
        local payload = "a|b||c|"
        local wire, decoded = RoundTrip("R", "topic.name", "id_1", payload)
        assert.equals("1|R|topic.name|id_1|" .. payload, wire)
        assert.equals(payload, decoded.payload)
    end)

    it("preserves arbitrary non-delimiter payload bytes", function()
        local payload = "检查\t\n\r~!@#$%^&*()[]{}<>?;:'\",./\\`"
        local _, decoded = RoundTrip("E", "bytes.demo", "-", payload)
        assert.equals(payload, decoded.payload)
    end)

    it("rejects invalid or missing envelope fields", function()
        local cases = {
            { "", "missing_fields" },
            { "1|E|example|-", "missing_fields" },
            { "1|X|example|-|x", "invalid_type" },
            { "1|E||-|x", "invalid_topic" },
            { "1|E|bad topic|-|x", "invalid_topic" },
            { "1|E|example|-|x\0y", "invalid_message" },
        }
        for _, case in ipairs(cases) do
            local decoded, reason = MessageProtocol.Decode(case[1])
            assert.is_nil(decoded, case[1])
            assert.equals(case[2], reason, case[1])
        end

        assert.is_nil(select(1, MessageProtocol.Encode("X", "example", "-", "x")))
        assert.equals("invalid_type", select(2, MessageProtocol.Encode("X", "example", "-", "x")))
        assert.equals("invalid_topic", select(2, MessageProtocol.Encode("E", "", "-", "x")))
        assert.is_nil(select(1, MessageProtocol.Encode("E", "t", "-", "a\0b")))
        assert.equals("invalid_payload", select(2, MessageProtocol.Encode("E", "t", "-", "a\0b")))
    end)

    it("rejects invalid correlation ids", function()
        assert.equals("invalid_correlation_id", select(2, MessageProtocol.Encode("E", "t", "a7", "")))
        assert.equals("invalid_correlation_id", select(2, MessageProtocol.Encode("Q", "t", "-", "")))
        assert.equals("invalid_correlation_id", select(2, MessageProtocol.Encode("Q", "t", "bad|id", "")))
        assert.equals("invalid_correlation_id", select(2, MessageProtocol.Encode("R", "t", "", "")))
        assert.equals("invalid_correlation_id", select(2, MessageProtocol.Encode("Q", "t", string.rep("a", 25), "")))

        local decoded, reason = MessageProtocol.Decode("1|Q|t|-|x")
        assert.is_nil(decoded)
        assert.equals("invalid_correlation_id", reason)

        local eventDecoded, eventReason = MessageProtocol.Decode("1|E|t|a7|x")
        assert.is_nil(eventDecoded)
        assert.equals("invalid_correlation_id", eventReason)
    end)

    it("enforces topic, correlation id, and message length limits", function()
        local topic = string.rep("a", 48)
        local _, topicDecoded = RoundTrip("E", topic, "-", "z")
        assert.equals(topic, topicDecoded.topic)

        local longTopic, longTopicReason = MessageProtocol.Decode("1|E|" .. string.rep("a", 49) .. "|-|z")
        assert.is_nil(longTopic)
        assert.equals("invalid_topic", longTopicReason)
        assert.equals("invalid_topic", select(2, MessageProtocol.Encode("E", string.rep("a", 49), "-", "z")))

        local correlationId = string.rep("b", 24)
        local _, idDecoded = RoundTrip("R", "t", correlationId, "z")
        assert.equals(correlationId, idDecoded.correlationId)

        local longId, longIdReason = MessageProtocol.Decode("1|Q|t|" .. string.rep("b", 25) .. "|z")
        assert.is_nil(longId)
        assert.equals("invalid_correlation_id", longIdReason)

        -- "1|E|t|-|" is 8 bytes, so a 247-byte payload fills the 255-byte addon-message limit.
        local prefix = "1|E|t|-|"
        assert.equals(8, #prefix)
        local exactPayload = string.rep("x", 255 - #prefix)
        local exactWire = prefix .. exactPayload
        assert.equals(255, #exactWire)
        local encoded, encodeReason = MessageProtocol.Encode("E", "t", "-", exactPayload)
        assert.is_nil(encodeReason, encodeReason)
        assert.equals(exactWire, encoded)
        local exactDecoded, exactReason = MessageProtocol.Decode(exactWire)
        assert.is_nil(exactReason, exactReason)
        assert.equals(exactPayload, exactDecoded.payload)

        local overPayload = exactPayload .. "y"
        assert.equals(256, #(prefix .. overPayload))
        local overEncoded, overEncodeReason = MessageProtocol.Encode("E", "t", "-", overPayload)
        assert.is_nil(overEncoded)
        assert.equals("too_large", overEncodeReason)
        local overDecoded, overDecodeReason = MessageProtocol.Decode(prefix .. overPayload)
        assert.is_nil(overDecoded)
        assert.equals("too_large", overDecodeReason)
    end)

    it("ignores unsupported protocol versions", function()
        local decoded, reason = MessageProtocol.Decode("2|E|example|-|hello")
        assert.is_nil(decoded)
        assert.equals("unsupported_version", reason)
        assert.is_false(MessageProtocol.Dispatch("2|E|example|-|hello", "A-R", "RAID"))
    end)

    it("rejects messages exceeding 255 bytes", function()
        local oversizedPayload = string.rep("x", 255)
        local wire, reason = MessageProtocol.Encode("E", "t", "-", oversizedPayload)
        assert.is_nil(wire)
        assert.equals("too_large", reason)

        local tooLong = "1|E|t|-|" .. string.rep("y", 250)
        assert.is_true(#tooLong > 255)
        local decoded, decodeReason = MessageProtocol.Decode(tooLong)
        assert.is_nil(decoded)
        assert.equals("too_large", decodeReason)
    end)

    it("ignores unknown topics", function()
        local called = false
        MessageProtocol.RegisterHandler("known", function()
            called = true
        end)
        assert.is_false(MessageProtocol.Dispatch("1|E|unknown|-|x", "A-R", "RAID"))
        assert.is_false(called)
    end)

    it("supports multiple handlers and cleanup", function()
        local calls = {}
        local function first(msg)
            table.insert(calls, "first:" .. msg.payload)
        end
        local function second(msg)
            table.insert(calls, "second:" .. msg.payload)
        end
        MessageProtocol.RegisterHandler("multi", first)
        MessageProtocol.RegisterHandler("multi", second)

        MessageProtocol.Dispatch("1|E|multi|-|hi", "Sender-Realm", "RAID")
        assert.same({ "first:hi", "second:hi" }, calls)

        MessageProtocol.UnregisterHandler("multi", first)
        calls = {}
        MessageProtocol.Dispatch("1|E|multi|-|yo", "Sender-Realm", "PARTY")
        assert.same({ "second:yo" }, calls)

        MessageProtocol.UnregisterHandler("multi", second)
        calls = {}
        assert.is_false(MessageProtocol.Dispatch("1|E|multi|-|no", "Sender-Realm", "RAID"))
        assert.same({}, calls)
    end)

    it("isolates handler exceptions", function()
        local calls = {}
        MessageProtocol.RegisterHandler("boom", function()
            error("handler failed")
        end)
        MessageProtocol.RegisterHandler("boom", function(msg)
            table.insert(calls, msg.sender .. ":" .. msg.channel .. ":" .. msg.payload)
        end)

        assert.is_true(MessageProtocol.Dispatch("1|Q|boom|cid1|body", "P-R", "RAID"))
        assert.same({ "P-R:RAID:body" }, calls)
    end)

    it("logs handler errors when debugHandlers is enabled", function()
        local ns = Loader.Load()
        MessageProtocol = ns.MessageProtocol
        local printed = {}
        ns.Util.Print = function(message)
            table.insert(printed, message)
        end
        MessageProtocol.debugHandlers = true
        MessageProtocol.RegisterHandler("boom", function()
            error("handler failed")
        end)
        assert.is_true(MessageProtocol.Dispatch("1|E|boom|-|x", "P-R", "RAID"))
        assert.equals(1, #printed)
        assert(printed[1]:find("boom", 1, true), "expected topic in " .. printed[1])
        assert(printed[1]:find("handler failed", 1, true), "expected error in " .. printed[1])
    end)

    it("attaches trusted sender and channel from dispatch, not the payload", function()
        local seen
        MessageProtocol.RegisterHandler("meta", function(msg)
            seen = msg
        end)
        MessageProtocol.Dispatch("1|E|meta|-|sender=fake|channel=FAKE", "Real-Realm", "INSTANCE_CHAT")
        assert.same({
            version = 1,
            type = "E",
            topic = "meta",
            correlationId = "-",
            payload = "sender=fake|channel=FAKE",
            sender = "Real-Realm",
            channel = "INSTANCE_CHAT",
        }, seen)
    end)
end)
