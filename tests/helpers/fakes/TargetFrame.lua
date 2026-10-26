return function()
    local TargetFrame = {
        ---@type Frame|nil
        frame = nil,
        ---@type Frame|nil
        ellesmereFrame = nil,
        ellesmereLoaded = false,
        readyCallbacks = {},
    }

    local function IsEllesmereTarget(frame)
        if type(frame) ~= "table" or frame.forbidden == true then
            return false
        end
        if type(frame.GetName) == "function" then
            local name = frame:GetName()
            if name ~= "EllesmereUIUnitFrames_Target" then
                return false
            end
        end
        if type(frame.GetAttribute) == "function" then
            local unit = frame:GetAttribute("unit")
            if unit ~= nil and unit ~= "target" then
                return false
            end
        end
        return true
    end

    function TargetFrame.GetFrame()
        if TargetFrame.ellesmereLoaded and IsEllesmereTarget(TargetFrame.ellesmereFrame) then
            return TargetFrame.ellesmereFrame
        end
        local frame = TargetFrame.frame
        if type(frame) ~= "table" then
            return nil
        end
        if frame.forbidden == true then
            return nil
        end
        if type(frame.GetName) == "function" then
            local name = frame:GetName()
            if type(name) == "string" and name ~= "TargetFrame" then
                return nil
            end
        end
        return frame
    end

    function TargetFrame.OnReady(callback)
        table.insert(TargetFrame.readyCallbacks, callback)
    end

    function TargetFrame.FireReady()
        local snapshot = {}
        for i = 1, #TargetFrame.readyCallbacks do
            snapshot[i] = TargetFrame.readyCallbacks[i]
        end
        for i = 1, #snapshot do
            snapshot[i]()
        end
    end

    return TargetFrame
end
