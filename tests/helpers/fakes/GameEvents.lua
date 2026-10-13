return function()
    local GameEvents = { handlers = {} }

    local function AddHandler(event, handler)
        GameEvents.handlers[event] = GameEvents.handlers[event] or {}
        table.insert(GameEvents.handlers[event], handler)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            local list = GameEvents.handlers[event]
            if not list then
                return
            end
            for index, candidate in ipairs(list) do
                if candidate == handler then
                    table.remove(list, index)
                    break
                end
            end
            if #list == 0 then
                GameEvents.handlers[event] = nil
            end
        end
    end

    function GameEvents.Listen(event, handler)
        return AddHandler(event, handler)
    end

    function GameEvents.ListenUnit(event, unit, handler)
        return AddHandler(event, function(unitTarget, ...)
            if unitTarget == unit then
                handler(unitTarget, ...)
            end
        end)
    end

    function GameEvents.Fire(event, ...)
        local list = GameEvents.handlers[event]
        if not list then
            return
        end
        for i = 1, #list do
            local handler = list[i]
            if handler then
                handler(...)
            end
        end
    end

    return GameEvents
end
