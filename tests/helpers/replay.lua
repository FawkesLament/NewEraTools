-- Deterministic WoW event replay for tests. Isolated per Replay.new(); frame boundaries are explicit.
-- Usage: local Replay = require("helpers.replay")

local Replay = {}

local HISTORY_LIMIT = 20
local UNIT_PROPERTIES = {
    exists = true,
    level = true,
    markerPresent = true,
}

---Non-nil stand-in for values the production code only tests for presence.
Replay.PRESENT = setmetatable({}, {
    __tostring = function()
        return "PRESENT"
    end,
})

---Packs event arguments, preserving count and trailing nils. Unpack with `unpack(args, 1, args.n)`.
---@return { n: integer }
function Replay.args(...)
    return { n = select("#", ...), ... }
end

---@param value any
---@return string
local function FormatValue(value)
    if value == Replay.PRESENT then
        return "PRESENT"
    elseif value == nil then
        return "nil"
    elseif type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    return tostring(value)
end

---@param packed { n: integer }
---@return string
local function FormatPackedArgs(packed)
    if not packed or packed.n == 0 then
        return ""
    end
    local parts = {}
    for i = 1, packed.n do
        parts[i] = FormatValue(packed[i])
    end
    return table.concat(parts, " ")
end

---@param eventName string
---@param packed { n: integer }
---@return string
local function FormatEvent(eventName, packed)
    local args = FormatPackedArgs(packed)
    if args == "" then
        return eventName
    end
    return eventName .. " " .. args
end

---@param token string
---@param properties table
---@return string
local function FormatUnitUpdate(token, properties)
    local parts = { "unit update", token }
    if properties.exists ~= nil then
        parts[#parts + 1] = "exists=" .. tostring(properties.exists)
    end
    if properties.level ~= nil then
        parts[#parts + 1] = "level=" .. tostring(properties.level)
    end
    if properties.markerPresent ~= nil then
        parts[#parts + 1] = "markerPresent=" .. tostring(properties.markerPresent)
    end
    return table.concat(parts, " ")
end

---@param err any
---@return any
local function AttachTraceback(err)
    if type(err) ~= "string" then
        return err
    end
    if debugstack then
        return err .. "\n" .. debugstack(2)
    end
    return debug.traceback(err, 2)
end

---@param options { mount: fun(env: table): { snapshot: fun(): any, stop: fun()? } }
---@return table
function Replay.new(options)
    assert(type(options) == "table", "Replay.new requires an options table")
    assert(type(options.mount) == "function", "Replay.new requires options.mount")

    local closed = false
    local frameOpen = false
    local flushing = false
    local currentFrameId = nil
    local currentTime = nil
    local lastFrameId = nil
    local lastTime = nil
    local currentStepIndex = nil
    local currentOp = nil
    local pending = {}
    local history = {}
    ---@type table<string, { exists: boolean|nil, level: number|nil, markerPresent: boolean|nil }>
    local units = {}
    ---@type table<string, { callback: fun(eventName: string, ...), }[]>
    local handlers = {}

    local function Record(text)
        local frame = currentFrameId ~= nil and tostring(currentFrameId) or "-"
        history[#history + 1] = "frame " .. frame .. ": " .. text
        while #history > HISTORY_LIMIT do
            table.remove(history, 1)
        end
    end

    local function Raise(cause)
        local causeText = tostring(cause)
        if causeText:find("Replay failed at frame", 1, true) then
            error(causeText, 0)
        end
        local frameLabel = currentFrameId ~= nil and tostring(currentFrameId) or "?"
        local timeLabel = currentTime ~= nil and string.format("%.3f", currentTime) or "?"
        local lines = {
            string.format("Replay failed at frame %s (t=%s)", frameLabel, timeLabel),
        }
        if currentStepIndex then
            lines[#lines + 1] = string.format("Step %d: %s", currentStepIndex, currentOp or "")
        elseif currentOp then
            lines[#lines + 1] = "Current: " .. currentOp
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Recent operations:"
        if #history == 0 then
            lines[#lines + 1] = "  (none)"
        else
            for i = 1, #history do
                lines[#lines + 1] = "  " .. history[i]
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Cause:"
        lines[#lines + 1] = causeText
        error(table.concat(lines, "\n"), 0)
    end

    local function Protect(fn)
        local ok, result = xpcall(fn, AttachTraceback)
        if not ok then
            Raise(result)
        end
        return result
    end

    local function EnsureNotClosed()
        if closed then
            error("Replay: runner is closed")
        end
    end

    local function EnsureFrameOpen()
        EnsureNotClosed()
        if not frameOpen then
            error("Replay: no frame is open")
        end
    end

    local function RequireUnit(token, apiName)
        if type(token) ~= "string" or token == "" then
            error(string.format("Replay: %s requires a unit token", apiName))
        end
        local unit = units[token]
        if not unit then
            error(string.format("Replay: %s queried unconfigured unit %q", apiName, token))
        end
        return unit
    end

    local api = {}

    function api.UnitExists(unitToken)
        local unit = RequireUnit(unitToken, "UnitExists")
        if unit.exists == nil then
            error(string.format("Replay: UnitExists queried unit %q with no configured existence", unitToken))
        end
        return unit.exists == true
    end

    function api.UnitLevel(unitToken)
        local unit = RequireUnit(unitToken, "UnitLevel")
        if unit.exists == false then
            return nil
        end
        if unit.exists ~= true then
            error(string.format("Replay: UnitLevel queried unit %q with no configured existence", unitToken))
        end
        if unit.level == nil then
            error(string.format("Replay: UnitLevel queried unit %q with no configured level", unitToken))
        end
        return unit.level
    end

    function api.GetRaidTargetIndex(unitToken)
        local unit = RequireUnit(unitToken, "GetRaidTargetIndex")
        if unit.exists == false then
            return nil
        end
        if unit.markerPresent == nil then
            error(
                string.format("Replay: GetRaidTargetIndex queried unit %q with no configured markerPresent", unitToken)
            )
        end
        if unit.markerPresent then
            return Replay.PRESENT
        end
        return nil
    end

    function api.GetTime()
        if currentTime ~= nil then
            return currentTime
        end
        return 0
    end

    local events = {}

    function events:on(eventName, callback)
        assert(type(eventName) == "string" and eventName ~= "", "Replay: event name must be a string")
        assert(type(callback) == "function", "Replay: event callback must be a function")
        EnsureNotClosed()
        local list = handlers[eventName]
        if not list then
            list = {}
            handlers[eventName] = list
        end
        local entry = { callback = callback }
        list[#list + 1] = entry
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            local current = handlers[eventName]
            if not current then
                return
            end
            for i = 1, #current do
                if current[i] == entry then
                    table.remove(current, i)
                    break
                end
            end
            if #current == 0 then
                handlers[eventName] = nil
            end
        end
    end

    local function Dispatch(eventName, ...)
        local list = handlers[eventName]
        if not list then
            return
        end
        local snapshot = {}
        for i = 1, #list do
            snapshot[i] = list[i]
        end
        for i = 1, #snapshot do
            snapshot[i].callback(eventName, ...)
        end
    end

    local env = {
        events = events,
        api = api,
    }

    function env:defer(callback)
        EnsureNotClosed()
        if not frameOpen and not flushing then
            error("Replay: cannot defer outside an open frame")
        end
        assert(type(callback) == "function", "Replay: defer callback must be a function")
        pending[#pending + 1] = callback
    end

    local function ValidateProperties(properties)
        if type(properties) ~= "table" then
            error("Replay: unit properties must be a table")
        end
        for key, value in pairs(properties) do
            if not UNIT_PROPERTIES[key] then
                error(string.format("Replay: unsupported unit property %q", tostring(key)))
            end
            if key == "exists" or key == "markerPresent" then
                if type(value) ~= "boolean" then
                    error(string.format("Replay: %s must be a boolean", key))
                end
            elseif key == "level" then
                if type(value) ~= "number" then
                    error("Replay: level must be a number")
                end
            end
        end
    end

    local function SetUnit(token, properties)
        if type(token) ~= "string" or token == "" then
            error("Replay: setUnit requires a unit token")
        end
        properties = properties or {}
        ValidateProperties(properties)
        local unit = units[token]
        if not unit then
            unit = {}
            units[token] = unit
        end
        if properties.exists ~= nil then
            unit.exists = properties.exists
        end
        if properties.level ~= nil then
            unit.level = properties.level
        end
        if properties.markerPresent ~= nil then
            unit.markerPresent = properties.markerPresent
        end
    end

    local function RemoveUnit(token)
        if type(token) ~= "string" or token == "" then
            error("Replay: removeUnit requires a unit token")
        end
        units[token] = { exists = false }
    end

    local function BeginFrame(frameId, timeSeconds)
        EnsureNotClosed()
        if frameOpen then
            error("Replay: a frame is already open")
        end
        if type(frameId) ~= "number" then
            error("Replay: frameId must be a number")
        end
        if type(timeSeconds) ~= "number" then
            error("Replay: timeSeconds must be a number")
        end
        if lastFrameId ~= nil and not (frameId > lastFrameId) then
            error("Replay: frames must be processed in increasing order")
        end
        if lastTime ~= nil and timeSeconds < lastTime then
            error("Replay: simulated time must not move backwards")
        end
        frameOpen = true
        currentFrameId = frameId
        currentTime = timeSeconds
        lastFrameId = frameId
        lastTime = timeSeconds
        currentStepIndex = 0
        currentOp = nil
    end

    local function Emit(eventName, ...)
        if type(eventName) ~= "string" or eventName == "" then
            error("Replay: emit requires an event name")
        end
        Dispatch(eventName, ...)
    end

    local function EndFrame()
        EnsureFrameOpen()
        currentOp = "end-of-frame flush"
        flushing = true
        local toRun = pending
        pending = {}
        for i = 1, #toRun do
            toRun[i]()
        end
        flushing = false
        frameOpen = false
        currentOp = nil
        currentStepIndex = nil
    end

    local function ApplyStep(step)
        if type(step) ~= "table" or type(step.op) ~= "string" then
            error("Replay: fixture step must be a table with an op")
        end
        if step.op == "unit" then
            currentOp = FormatUnitUpdate(step.token, step.properties or {})
            Record(currentOp)
            SetUnit(step.token, step.properties)
        elseif step.op == "remove" then
            currentOp = "remove unit " .. tostring(step.token)
            Record(currentOp)
            RemoveUnit(step.token)
        elseif step.op == "event" then
            if type(step.name) ~= "string" or step.name == "" then
                error("Replay: event step requires a name")
            end
            local args = step.args
            if args == nil then
                args = { n = 0 }
            elseif type(args) ~= "table" or type(args.n) ~= "number" then
                error("Replay: event args must be created with Replay.args()")
            end
            currentOp = FormatEvent(step.name, args)
            Record(currentOp)
            Emit(step.name, unpack(args, 1, args.n))
        else
            error(string.format("Replay: unknown operation %q", step.op))
        end
    end

    local adapter = options.mount(env)
    assert(type(adapter) == "table", "Replay.mount must return an adapter table")
    assert(type(adapter.snapshot) == "function", "Replay adapter must provide snapshot()")

    local runner = {}

    function runner:beginFrame(frameId, timeSeconds)
        Protect(function()
            BeginFrame(frameId, timeSeconds)
        end)
    end

    function runner:setUnit(unitToken, properties)
        Protect(function()
            EnsureFrameOpen()
            currentStepIndex = (currentStepIndex or 0) + 1
            currentOp = FormatUnitUpdate(unitToken, properties or {})
            Record(currentOp)
            SetUnit(unitToken, properties)
        end)
    end

    function runner:removeUnit(unitToken)
        Protect(function()
            EnsureFrameOpen()
            currentStepIndex = (currentStepIndex or 0) + 1
            currentOp = "remove unit " .. tostring(unitToken)
            Record(currentOp)
            RemoveUnit(unitToken)
        end)
    end

    function runner:emit(eventName, ...)
        local packed = { n = select("#", ...), ... }
        Protect(function()
            EnsureFrameOpen()
            currentStepIndex = (currentStepIndex or 0) + 1
            currentOp = FormatEvent(eventName, packed)
            Record(currentOp)
            Emit(eventName, unpack(packed, 1, packed.n))
        end)
    end

    function runner:endFrame()
        Protect(function()
            EndFrame()
        end)
    end

    function runner:snapshot()
        return Protect(function()
            EnsureNotClosed()
            return adapter.snapshot()
        end)
    end

    function runner:stepFrame(frame)
        Protect(function()
            EnsureNotClosed()
            if type(frame) ~= "table" then
                error("Replay: frame must be a table")
            end
            BeginFrame(frame.id, frame.time)
            local steps = frame.steps
            if steps == nil then
                steps = {}
            elseif type(steps) ~= "table" then
                error("Replay: frame.steps must be a table")
            end
            for i = 1, #steps do
                currentStepIndex = i
                ApplyStep(steps[i])
            end
            EndFrame()
        end)
    end

    function runner:run(fixture, runOptions)
        return Protect(function()
            EnsureNotClosed()
            if type(fixture) ~= "table" or type(fixture.frames) ~= "table" then
                error("Replay: fixture must have a frames table")
            end
            runOptions = runOptions or {}
            local onFrame = runOptions.onFrame
            if onFrame ~= nil and type(onFrame) ~= "function" then
                error("Replay: options.onFrame must be a function")
            end
            for i = 1, #fixture.frames do
                local frame = fixture.frames[i]
                runner:stepFrame(frame)
                if onFrame then
                    onFrame(runner, frame, runner:snapshot())
                end
            end
            return runner
        end)
    end

    function runner:close()
        if closed then
            return
        end
        closed = true
        frameOpen = false
        flushing = false
        local stop = adapter.stop
        local ok, err = true, nil
        if type(stop) == "function" then
            ok, err = xpcall(stop, AttachTraceback)
        end
        adapter = {
            snapshot = function() end,
        }
        pending = {}
        handlers = {}
        units = {}
        currentOp = nil
        currentStepIndex = nil
        if not ok then
            Raise(err)
        end
    end

    return runner
end

return Replay
