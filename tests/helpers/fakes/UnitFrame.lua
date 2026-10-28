return function()
    local UnitFrame = {
        ---@type any[]
        frames = {},
        ---@type fun(frame: any)[]
        created = {},
    }

    function UnitFrame.IsConfigurable(frame)
        if type(frame) ~= "table" then
            return false
        end
        if type(frame.GetAttribute) ~= "function" or type(frame.SetAttribute) ~= "function" then
            return false
        end
        if frame.forbidden then
            return false
        end
        if frame.nameplate or frame.namePlateUnitToken then
            return false
        end
        if frame.protected == false then
            return false
        end
        return true
    end

    function UnitFrame.ForEach(handler)
        for i = 1, #UnitFrame.frames do
            local frame = UnitFrame.frames[i]
            if UnitFrame.IsConfigurable(frame) then
                handler(frame)
            end
        end
    end

    function UnitFrame.OnCreated(handler)
        table.insert(UnitFrame.created, handler)
    end

    local attributeListeners = {}
    local watched = {}

    ---Post-hooks `frame.SetAttribute` once, like `hooksecurefunc(frame, "SetAttribute", ...)`.
    function UnitFrame.WatchAttributes(frame)
        if watched[frame] then
            return
        end
        watched[frame] = true
        local original = frame.SetAttribute
        frame.SetAttribute = function(self, key, value)
            original(self, key, value)
            for i = 1, #attributeListeners do
                attributeListeners[i](self, key, value)
            end
        end
    end

    function UnitFrame.OnAttributeSet(handler)
        table.insert(attributeListeners, handler)
    end

    ---Test helper: a compact or ClickCastFrames unit button became available. Like production,
    ---later ForEach walks include it until a test removes it from `frames`.
    ---@param frame any
    function UnitFrame.FireCreated(frame)
        table.insert(UnitFrame.frames, frame)
        local list = UnitFrame.created
        for i = 1, #list do
            list[i](frame)
        end
    end

    return UnitFrame
end
