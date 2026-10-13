return function()
    local Activity = {
        skyriding = false,
        inPetBattle = false,
        inCinematic = false,
        contextCallbacks = {},
    }

    function Activity.IsSkyriding()
        return Activity.skyriding == true
    end

    function Activity.IsInPetBattle()
        return Activity.inPetBattle == true
    end

    function Activity.IsInCinematic()
        return Activity.inCinematic == true
    end

    function Activity.OnContextChanged(callback)
        table.insert(Activity.contextCallbacks, callback)
    end

    ---Test helper: replace situational activity flags.
    ---@param state { skyriding: boolean|nil, inPetBattle: boolean|nil, inCinematic: boolean|nil }
    function Activity.SetStateForTests(state)
        if state.skyriding ~= nil then
            Activity.skyriding = state.skyriding == true
        end
        if state.inPetBattle ~= nil then
            Activity.inPetBattle = state.inPetBattle == true
        end
        if state.inCinematic ~= nil then
            Activity.inCinematic = state.inCinematic == true
        end
    end

    function Activity.FireContextChanged()
        for _, callback in ipairs(Activity.contextCallbacks) do
            callback()
        end
    end

    return Activity
end
