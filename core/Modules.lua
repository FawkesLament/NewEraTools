local _, ns = ...

local Modules = {}
ns.Modules = Modules

---@class Module
---@field name string
---@field defaults table|nil
---@field db table  This module's saved settings; available from OnInit on.
---@field OnInit fun(self: Module)|nil  Prepare internal state. Runs for every module before any OnEnable.
---@field OnEnable fun(self: Module)|nil  Create frames, register events, sections and slash commands.

local ordered = {}
local byName = {}
local beforeInit = {}

---Runs on Start, before any module OnInit, with the loaded saved-variable table.
---Use it for saved data that more than one module reads.
---@param callback fun(saved: table)
function Modules.BeforeInit(callback)
    assert(type(callback) == "function", "Modules.BeforeInit requires a function")
    table.insert(beforeInit, callback)
end

---@param name string
---@param options { defaults: table|nil }|nil
---@return Module
function Modules.New(name, options)
    assert(type(name) == "string" and not byName[name], "Modules.New requires a unique name")
    local module = {
        name = name,
        defaults = options and options.defaults,
    }
    byName[name] = module
    table.insert(ordered, module)
    return module
end

---Returns a module defined earlier in the TOC. Only use it to reach a module from its own UI file.
---@param name string
---@return Module
function Modules.Get(name)
    return assert(byName[name], "Unknown module: " .. tostring(name))
end

---@param saved table  Result of Database.Load.
function Modules.Start(saved)
    for _, callback in ipairs(beforeInit) do
        callback(saved)
    end
    for _, module in ipairs(ordered) do
        module.db = ns.Database.GetModuleSettings(saved, module.name, module.defaults)
    end
    for _, module in ipairs(ordered) do
        if module.OnInit then
            module:OnInit()
        end
    end
    for _, module in ipairs(ordered) do
        if module.OnEnable then
            module:OnEnable()
        end
    end
end
