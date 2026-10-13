return function()
    local RaidTarget = {
        indices = {},
        changedCallbacks = {},
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

    function RaidTarget.GetIndex(unit)
        return RaidTarget.indices[unit]
    end

    function RaidTarget.OnChanged(callback)
        return AddCallback(RaidTarget.changedCallbacks, callback)
    end

    ---Test helper: set a unit's raid target and fire OnChanged.
    ---@param unit string
    ---@param index number|nil
    function RaidTarget.SetIndex(unit, index)
        RaidTarget.indices[unit] = index
        local list = RaidTarget.changedCallbacks
        for i = 1, #list do
            list[i]()
        end
    end

    function RaidTarget.FireChanged()
        local list = RaidTarget.changedCallbacks
        for i = 1, #list do
            list[i]()
        end
    end

    return RaidTarget
end
