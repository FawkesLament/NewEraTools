return function()
    local GameEvents = { handlers = {} }

    function GameEvents.Listen(event, handler)
        GameEvents.handlers[event] = GameEvents.handlers[event] or {}
        table.insert(GameEvents.handlers[event], handler)
    end

    function GameEvents.Fire(event, ...)
        for _, handler in ipairs(GameEvents.handlers[event] or {}) do
            handler(...)
        end
    end

    return GameEvents
end
