return function()
    local Slash = { registered = {} }

    function Slash.Register(id, commands, handler)
        Slash.registered[id] = { commands = commands, handler = handler }
    end

    return Slash
end
