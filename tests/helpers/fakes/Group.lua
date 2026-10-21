return function()
    local Group = {
        members = {},
        rosterComplete = nil,
        raidChatType = nil,
        isRaidLeader = false,
        isLeaderOrAssistant = false,
        raidLeaderFullName = nil,
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

    function Group.HasCompleteRaidRoster()
        if Group.rosterComplete ~= nil then
            return Group.rosterComplete
        end
        return Group.raidChatType ~= nil and #Group.members > 0
    end

    function Group.IsPlayerRaidLeader()
        return Group.isRaidLeader
    end

    function Group.IsPlayerRaidLeaderOrAssistant()
        return Group.isLeaderOrAssistant
    end

    function Group.GetRaidLeaderFullName()
        return Group.raidLeaderFullName
    end

    function Group.OnChanged(callback)
        table.insert(Group.changeCallbacks, callback)
    end

    return Group
end
