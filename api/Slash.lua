local _, ns = ...

local Slash = {}
ns.Api.Slash = Slash

---@param id string  Unique uppercase key, e.g. "NEWERATOOLS".
---@param commands string[]  e.g. { "/netools" }.
---@param handler fun(input: string)
function Slash.Register(id, commands, handler)
    for index, command in ipairs(commands) do
        _G["SLASH_" .. id .. index] = command
    end
    SlashCmdList[id] = handler
end
