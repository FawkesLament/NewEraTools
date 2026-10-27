return function()
    local WorldFrame = {
        ---@type Frame|nil
        frame = nil,
    }

    function WorldFrame.GetFrame()
        local frame = WorldFrame.frame
        if type(frame) ~= "table" then
            return nil
        end
        if frame.forbidden == true then
            return nil
        end
        return frame
    end

    return WorldFrame
end
