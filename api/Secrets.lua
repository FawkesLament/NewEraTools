local _, ns = ...

local Secrets = {}
ns.Api.Secrets = Secrets

---Whether `value` is a secret. Check this before any comparison or other use.
---@param value any
---@return boolean
function Secrets.IsSecret(value)
    return issecretvalue and issecretvalue(value)
end
