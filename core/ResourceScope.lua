local _, ns = ...

---@class ResourceScope
---@field private cleanups function[]
---@field private disposed boolean
local ResourceScope = {}
ResourceScope.__index = ResourceScope
ns.ResourceScope = ResourceScope

local function ReportCleanupError(err)
    ns.Util.Print("ResourceScope cleanup error: " .. tostring(err))
end

local function RunCleanup(cleanup)
    local ok, err = pcall(cleanup)
    if not ok then
        ReportCleanupError(err)
    end
end

---Creates an empty scope. `Dispose` runs registered cleanups in reverse order.
---@return ResourceScope
function ResourceScope.New()
    return setmetatable({
        cleanups = {},
        disposed = false,
    }, ResourceScope)
end

---@param cleanup fun()
function ResourceScope:Add(cleanup)
    assert(type(cleanup) == "function", "ResourceScope:Add requires a function")
    if self.disposed then
        RunCleanup(cleanup)
        return
    end
    self.cleanups[#self.cleanups + 1] = cleanup
end

---@param subscribe fun(callback: function): (fun()|nil)
---@param callback function
function ResourceScope:Subscribe(subscribe, callback)
    assert(type(subscribe) == "function", "ResourceScope:Subscribe requires a subscribe function")
    assert(type(callback) == "function", "ResourceScope:Subscribe requires a callback")
    if self.disposed then
        return
    end
    local unsubscribe = subscribe(callback)
    if unsubscribe ~= nil then
        self:Add(unsubscribe)
    end
end

---@param interval number
---@param callback function
function ResourceScope:Ticker(interval, callback)
    assert(type(interval) == "number", "ResourceScope:Ticker requires an interval")
    assert(type(callback) == "function", "ResourceScope:Ticker requires a callback")
    if self.disposed then
        return
    end
    local ticker = ns.Api.Timer.NewTicker(interval, function(...)
        if self.disposed then
            return
        end
        callback(...)
    end)
    self:Add(function()
        ticker:Cancel()
    end)
end

---@param delay number
---@param callback function
function ResourceScope:After(delay, callback)
    assert(type(delay) == "number", "ResourceScope:After requires a delay")
    assert(type(callback) == "function", "ResourceScope:After requires a callback")
    if self.disposed then
        return
    end
    local timer = ns.Api.Timer.NewTimer(delay, function(...)
        if self.disposed then
            return
        end
        callback(...)
    end)
    self:Add(function()
        timer:Cancel()
    end)
end

function ResourceScope:Dispose()
    if self.disposed then
        return
    end
    self.disposed = true
    local cleanups = self.cleanups
    for index = #cleanups, 1, -1 do
        local cleanup = cleanups[index]
        cleanups[index] = nil
        RunCleanup(cleanup)
    end
end
