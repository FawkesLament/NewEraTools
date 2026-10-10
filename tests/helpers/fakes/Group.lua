return function()
    local Group = {
        members = {},
        raidChatType = nil,
        isLeaderOrAssistant = false,
        changeCallbacks = {},
    }

    function Group.GetRaidMembers()
        local copy = {}
        for index, member in ipairs(Group.members) do
            copy[index] = member
        end
        return copy
    end

    function Group.GetRaidChatType()
        return Group.raidChatType
    end

    function Group.IsPlayerRaidLeaderOrAssistant()
        return Group.isLeaderOrAssistant
    end

    function Group.OnChanged(callback)
        table.insert(Group.changeCallbacks, callback)
    end

    return Group
end
