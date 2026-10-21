return function()
    local Nameplate = {
        ---@type table<string, Frame>
        frames = {},
        ---@type { unit: string, frame: Frame }[]
        visible = {},
        added = {},
        removed = {},
    }

    local function AddHandler(list, handler)
        table.insert(list, handler)
        local removed = false
        return function()
            if removed then
                return
            end
            removed = true
            for index, candidate in ipairs(list) do
                if candidate == handler then
                    table.remove(list, index)
                    return
                end
            end
        end
    end

    local function VisibleIndex(unit)
        for index, entry in ipairs(Nameplate.visible) do
            if entry.unit == unit then
                return index
            end
        end
        return nil
    end

    function Nameplate.GetFrame(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil
        end
        return Nameplate.frames[unit]
    end

    function Nameplate.IsUnitToken(unit)
        return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
    end

    function Nameplate.OnAdded(handler)
        return AddHandler(Nameplate.added, handler)
    end

    function Nameplate.OnRemoved(handler)
        return AddHandler(Nameplate.removed, handler)
    end

    function Nameplate.ForEachVisible(handler)
        for i = 1, #Nameplate.visible do
            local entry = Nameplate.visible[i]
            handler(entry.unit, entry.frame)
        end
    end

    ---Shows `frame` for `unit` and notifies OnAdded listeners.
    ---@param unit string
    ---@param frame Frame
    function Nameplate.FireAdded(unit, frame)
        Nameplate.frames[unit] = frame
        local index = VisibleIndex(unit)
        if index then
            Nameplate.visible[index].frame = frame
        else
            Nameplate.visible[#Nameplate.visible + 1] = { unit = unit, frame = frame }
        end
        local list = Nameplate.added
        for i = 1, #list do
            list[i](unit, frame)
        end
    end

    ---Hides `unit`'s nameplate and notifies OnRemoved listeners.
    ---@param unit string
    function Nameplate.FireRemoved(unit)
        Nameplate.frames[unit] = nil
        local index = VisibleIndex(unit)
        if index then
            table.remove(Nameplate.visible, index)
        end
        local list = Nameplate.removed
        for i = 1, #list do
            list[i](unit)
        end
    end

    return Nameplate
end
