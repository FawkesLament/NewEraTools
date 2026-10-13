return function()
    local Chat = {
        sent = {},
        raidLeaderCallbacks = {},
        raidWarningCallbacks = {},
    }

    local function AddCallback(list, callback)
        table.insert(list, callback)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            for index, candidate in ipairs(list) do
                if candidate == callback then
                    table.remove(list, index)
                    return
                end
            end
        end
    end

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
        return AddCallback(Chat.raidLeaderCallbacks, callback)
    end

    function Chat.FireRaidLeader(message, ...)
        local list = Chat.raidLeaderCallbacks
        for i = 1, #list do
            list[i](message, ...)
        end
    end

    function Chat.OnRaidWarningMessage(callback)
        return AddCallback(Chat.raidWarningCallbacks, callback)
    end

    function Chat.FireRaidWarning(message, ...)
        local list = Chat.raidWarningCallbacks
        for i = 1, #list do
            list[i](message, ...)
        end
    end

    return Chat
end
