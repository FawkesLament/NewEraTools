return function()
    local Chat = { sent = {} }

    function Chat.Send(message, chatType)
        table.insert(Chat.sent, { message = message, chatType = chatType })
    end

    return Chat
end
