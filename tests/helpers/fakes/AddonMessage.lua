return function()
    local AddonMessage = { sent = {}, listeners = {}, accepts = true }

    function AddonMessage.Send(prefix, message, chatType)
        table.insert(AddonMessage.sent, { prefix = prefix, message = message, chatType = chatType })
        return AddonMessage.accepts
    end

    function AddonMessage.Listen(prefix, callback)
        AddonMessage.listeners[prefix] = callback
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
