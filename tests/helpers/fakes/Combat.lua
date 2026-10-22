return function()
    local Combat = {
        inCombat = false,
        enterCallbacks = {},
        leaveCallbacks = {},
    }

    function Combat.IsInCombat()
        return Combat.inCombat
    end

    function Combat.IsLockedDown()
        return Combat.inCombat
    end

    function Combat.OnEnter(callback)
        table.insert(Combat.enterCallbacks, callback)
        return function()
            for index, candidate in ipairs(Combat.enterCallbacks) do
                if candidate == callback then
                    table.remove(Combat.enterCallbacks, index)
                    return
                end
            end
        end
    end

    function Combat.OnLeave(callback)
        table.insert(Combat.leaveCallbacks, callback)
        return function()
            for index, candidate in ipairs(Combat.leaveCallbacks) do
                if candidate == callback then
                    table.remove(Combat.leaveCallbacks, index)
                    return
                end
            end
        end
    end

    function Combat.FireEnter()
        Combat.inCombat = true
        for _, callback in ipairs(Combat.enterCallbacks) do
            callback()
        end
    end

    function Combat.FireLeave()
        Combat.inCombat = false
        local snapshot = {}
        for index, callback in ipairs(Combat.leaveCallbacks) do
            snapshot[index] = callback
        end
        for _, callback in ipairs(snapshot) do
            callback()
        end
    end

    return Combat
end
