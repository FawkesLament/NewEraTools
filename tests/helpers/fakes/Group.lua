return function()
    local Group = {
        members = {},
        rosterComplete = nil,
        inRaid = false,
        raidChatType = nil,
        isRaidLeader = false,
        isLeaderOrAssistant = false,
        raidLeaderFullName = nil,
        changeCallbacks = {},
        readyChecks = 0,
        countdowns = {},
        cancels = 0,
    }

    function Group.IsInRaid()
        return Group.inRaid == true
    end

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
        return Group.isRaidLeader or Group.isLeaderOrAssistant
    end

    function Group.GetRaidLeaderFullName()
        return Group.raidLeaderFullName
    end

    function Group.OnChanged(callback)
        table.insert(Group.changeCallbacks, callback)
    end

    function Group.FireChanged()
        for _, callback in ipairs(Group.changeCallbacks) do
            callback()
        end
    end

    function Group.DoReadyCheck()
        Group.readyChecks = Group.readyChecks + 1
    end

    function Group.DoCountdown(seconds)
        table.insert(Group.countdowns, seconds)
        return true
    end

    function Group.CancelCountdown()
        Group.cancels = Group.cancels + 1
    end

    return Group
end
