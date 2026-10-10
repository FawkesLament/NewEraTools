return function()
    local Combat = {
        inCombat = false,
        enterCallbacks = {},
        leaveCallbacks = {},
    }

    function Combat.IsInCombat()
        return Combat.inCombat
    end

    function Combat.OnEnter(callback)
        table.insert(Combat.enterCallbacks, callback)
    end

    function Combat.OnLeave(callback)
        table.insert(Combat.leaveCallbacks, callback)
    end

    function Combat.FireEnter()
        Combat.inCombat = true
        for _, callback in ipairs(Combat.enterCallbacks) do
            callback()
        end
    end

    function Combat.FireLeave()
        Combat.inCombat = false
        for _, callback in ipairs(Combat.leaveCallbacks) do
            callback()
        end
    end

    return Combat
end
