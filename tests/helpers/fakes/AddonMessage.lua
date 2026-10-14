return function()
    local AddonMessage = {
        sent = {},
        listeners = {},
        accepts = true,
        rejectReason = "rejected",
        registerAccepts = true,
        ---Set `registerRejectPrefixes[prefix] = true` to fail Listen for that prefix only.
        registerRejectPrefixes = {},
    }

    AddonMessage.TrafficClass = {
        REALTIME = "REALTIME",
        CONTROL = "CONTROL",
    }

    AddonMessage.PREFIX = {
        REALTIME = "NET_RT",
        CONTROL = "NET_CTL",
    }

    local PREFIX_BY_TRAFFIC = {
        [AddonMessage.TrafficClass.REALTIME] = AddonMessage.PREFIX.REALTIME,
        [AddonMessage.TrafficClass.CONTROL] = AddonMessage.PREFIX.CONTROL,
    }

    local PROTOCOL_PREFIXES = {
        AddonMessage.PREFIX.REALTIME,
        AddonMessage.PREFIX.CONTROL,
    }

    function AddonMessage.IsProtocolPrefix(prefix)
        return prefix == AddonMessage.PREFIX.REALTIME or prefix == AddonMessage.PREFIX.CONTROL
    end

    function AddonMessage.PrefixForTrafficClass(trafficClass)
        local prefix = PREFIX_BY_TRAFFIC[trafficClass]
        if not prefix then
            return nil, "InvalidTrafficClass"
        end
        return prefix
    end

    function AddonMessage.Send(prefix, message, chatType, target)
        if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
            return false, "InvalidPrefix"
        end
        if type(message) ~= "string" or #message > 255 or message:find("\0", 1, true) then
            return false, "InvalidMessage"
        end
        table.insert(AddonMessage.sent, {
            prefix = prefix,
            message = message,
            chatType = chatType,
            target = target,
        })
        if not AddonMessage.accepts then
            return false, AddonMessage.rejectReason
        end
        return true
    end

    function AddonMessage.SendTraffic(trafficClass, message, chatType, target)
        local prefix, mapReason = AddonMessage.PrefixForTrafficClass(trafficClass)
        if not prefix then
            return false, mapReason
        end
        return AddonMessage.Send(prefix, message, chatType, target)
    end

    function AddonMessage.Listen(prefix, callback)
        assert(type(callback) == "function", "AddonMessage.Listen requires a callback")
        assert(not AddonMessage.listeners[prefix], "Already listening for addon prefix: " .. tostring(prefix))
        if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
            return false, "InvalidPrefix"
        end
        if AddonMessage.registerAccepts == false or AddonMessage.registerRejectPrefixes[prefix] then
            return false, "RegisterFailed"
        end
        AddonMessage.listeners[prefix] = callback
        return true
    end

    function AddonMessage.Unlisten(prefix)
        AddonMessage.listeners[prefix] = nil
    end

    function AddonMessage.ListenProtocol(callback)
        local bound = {}
        for i = 1, #PROTOCOL_PREFIXES do
            local prefix = PROTOCOL_PREFIXES[i]
            local ok, reason = AddonMessage.Listen(prefix, callback)
            if not ok then
                for j = 1, #bound do
                    AddonMessage.Unlisten(bound[j])
                end
                return false, reason, prefix
            end
            bound[#bound + 1] = prefix
        end
        return true
    end

    ---Simulates a message arriving from `sender`.
    function AddonMessage.Deliver(prefix, message, channel, sender)
        local callback = AddonMessage.listeners[prefix]
        if callback then
            callback(message, channel, sender)
        end
    end

    return AddonMessage
end
