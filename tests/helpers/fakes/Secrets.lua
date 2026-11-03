return function()
    local Secrets = {}

    function Secrets.IsSecret(value)
        return issecretvalue and issecretvalue(value)
    end

    return Secrets
end
