return function()
    local Chat = { sent = {}, raidLeaderCallbacks = {} }

    function Chat.Send(message, chatType)
        table.insert(Chat.sent, { message = message, chatType = chatType })
    end

    ---Mirrors C_ChatInfo.ReplaceIconAndGroupExpressions for `{rtN}` tags used in callout tests.
    function Chat.ReplaceIconAndGroupExpressions(input)
        if type(input) ~= "string" then
            return input
        end
        return (
            input:gsub("{rt(%d)}", function(index)
                return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
            end)
        )
    end

    function Chat.OnRaidLeaderMessage(callback)
        table.insert(Chat.raidLeaderCallbacks, callback)
    end

    function Chat.FireRaidLeader(message, ...)
        for _, callback in ipairs(Chat.raidLeaderCallbacks) do
            callback(message, ...)
        end
    end

    return Chat
end
