-- Test stand-in for CreateFrame event registration. A communication provider may register Blizzard events directly.
local EventFrames = { frames = {} }

function EventFrames.Reset()
    EventFrames.frames = {}
end

function EventFrames.CreateFrame()
    local frame = { events = {}, scripts = {} }

    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end

    function frame:RegisterEvent(event)
        self.events[event] = true
    end

    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end

    EventFrames.frames[#EventFrames.frames + 1] = frame
    return frame
end

---Frames currently registered for `event`.
---@param event string
---@return integer
function EventFrames.ListenerCount(event)
    local count = 0
    for _, frame in ipairs(EventFrames.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            count = count + 1
        end
    end
    return count
end

---Delivers `event` to registered frames. The payload matches the game's OnEvent arguments after the event name.
function EventFrames.Fire(event, ...)
    local snapshot = {}
    for _, frame in ipairs(EventFrames.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            snapshot[#snapshot + 1] = frame
        end
    end
    for _, frame in ipairs(snapshot) do
        frame.scripts.OnEvent(frame, event, ...)
    end
end

return EventFrames
