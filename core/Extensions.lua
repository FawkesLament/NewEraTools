local _, ns = ...

local Extensions = {}
ns.Extensions = Extensions

local MAX_TOKEN_LENGTH = 64

---@type table<string, table<string, table>>
local providers = {}
---@type table<string, table>
local capabilitySets = {}
---@type table<string, fun(extensionType: string, providerId: string, provider: table)[]>
local listeners = {}

---@param value any
---@return boolean
local function IsToken(value)
    return type(value) == "string"
        and #value >= 1
        and #value <= MAX_TOKEN_LENGTH
        and value:match("^[A-Za-z][A-Za-z0-9_.%-]*$") ~= nil
end

---@param extensionType string
---@param providerId string
---@param provider table
local function Notify(extensionType, providerId, provider)
    local list = listeners[extensionType]
    if not list then
        return
    end
    -- Copy first so a listener can subscribe or unsubscribe without skipping a call.
    local snapshot = {}
    for index = 1, #list do
        snapshot[index] = list[index]
    end
    for index = 1, #snapshot do
        snapshot[index](extensionType, providerId, provider)
    end
end

---Stores a provider and notifies listeners. Does not call into the provider.
---Both wrappers pass error level 3 so the message points at their caller: level 1 is this
---function, level 2 is the wrapper, level 3 is the addon or module that registered.
---@param extensionType string
---@param providerId string
---@param provider table
---@param level integer
local function Register(extensionType, providerId, provider, level)
    if not IsToken(extensionType) then
        error("Extensions.Register requires a valid extension type", level)
    end
    if not IsToken(providerId) then
        error("Extensions.Register requires a valid provider id", level)
    end
    if type(provider) ~= "table" then
        error("Extensions.Register requires a provider table", level)
    end
    local byType = providers[extensionType]
    if not byType then
        byType = {}
        providers[extensionType] = byType
    end
    if byType[providerId] ~= nil then
        error("Extensions.Register duplicate provider '" .. providerId .. "' for '" .. extensionType .. "'", level)
    end
    byType[providerId] = provider
    local ok, err = pcall(Notify, extensionType, providerId, provider)
    if not ok then
        byType[providerId] = nil
        if next(byType) == nil then
            providers[extensionType] = nil
        end
        error(err, 0)
    end
end

---Registers a provider for one feature-defined extension type. Errors on a duplicate id.
---@param extensionType string
---@param providerId string
---@param provider table
function Extensions.Register(extensionType, providerId, provider)
    Register(extensionType, providerId, provider, 3)
end

---The registered provider, or nil when this type has no provider with that id.
---@param extensionType string
---@param providerId string
---@return table|nil
function Extensions.Get(extensionType, providerId)
    if not IsToken(extensionType) or not IsToken(providerId) then
        error("Extensions.Get requires a valid extension type and provider id", 2)
    end
    local byType = providers[extensionType]
    if not byType then
        return nil
    end
    return byType[providerId]
end

---Shallow copy of the providers registered for `extensionType`. Empty when none are registered.
---@param extensionType string
---@return table<string, table>
function Extensions.GetAll(extensionType)
    if not IsToken(extensionType) then
        error("Extensions.GetAll requires a valid extension type", 2)
    end
    local copy = {}
    local byType = providers[extensionType]
    if byType then
        for providerId, provider in pairs(byType) do
            copy[providerId] = provider
        end
    end
    return copy
end

---Calls `callback` after a later registration for `extensionType` is stored.
---Does not replay providers that were already registered. Returns an unsubscribe function.
---@param extensionType string
---@param callback fun(extensionType: string, providerId: string, provider: table)
---@return fun()
function Extensions.OnRegistered(extensionType, callback)
    if not IsToken(extensionType) then
        error("Extensions.OnRegistered requires a valid extension type", 2)
    end
    if type(callback) ~= "function" then
        error("Extensions.OnRegistered requires a callback", 2)
    end
    local list = listeners[extensionType]
    if not list then
        list = {}
        listeners[extensionType] = list
    end
    table.insert(list, callback)
    return function()
        for index, existing in ipairs(list) do
            if existing == callback then
                table.remove(list, index)
                return
            end
        end
    end
end

---Publishes the capability object for an extension type. The host feature owns that object.
---@param extensionType string
---@param capabilities table
function Extensions.SetCapabilities(extensionType, capabilities)
    if not IsToken(extensionType) then
        error("Extensions.SetCapabilities requires a valid extension type", 2)
    end
    if type(capabilities) ~= "table" then
        error("Extensions.SetCapabilities requires a capabilities table", 2)
    end
    if capabilitySets[extensionType] ~= nil then
        error("Extensions.SetCapabilities duplicate capabilities for '" .. extensionType .. "'", 2)
    end
    capabilitySets[extensionType] = capabilities
end

---@param extensionType string
---@param level integer
---@return table
local function ReadCapabilities(extensionType, level)
    if not IsToken(extensionType) then
        error("Extensions.GetCapabilities requires a valid extension type", level)
    end
    local capabilities = capabilitySets[extensionType]
    if capabilities == nil then
        error("Extensions.GetCapabilities unknown extension type: " .. extensionType, level)
    end
    return capabilities
end

---The capability object a host feature published for `extensionType`.
---@param extensionType string
---@return table
function Extensions.GetCapabilities(extensionType)
    return ReadCapabilities(extensionType, 3)
end

---Public entry for other addons. This table is not `ns`.
---@class NewEraToolsPublicAPI
---@field RegisterExtension fun(extensionType: string, providerId: string, provider: table)
---@field GetCapabilities fun(extensionType: string): table
NewEraToolsAPI = {
    RegisterExtension = function(extensionType, providerId, provider)
        Register(extensionType, providerId, provider, 3)
    end,
    GetCapabilities = function(extensionType)
        return ReadCapabilities(extensionType, 3)
    end,
}
