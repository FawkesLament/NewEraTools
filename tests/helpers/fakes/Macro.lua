return function()
    local Macro = {
        ---@type table<number, { name: string, icon: string|number, body: string }>
        slots = {},
        nextIndex = 1,
        createBlocked = false,
    }

    local function FindByName(name)
        for index, entry in pairs(Macro.slots) do
            if entry.name == name then
                return index, entry
            end
        end
    end

    function Macro.GetIndexByName(name)
        local index = FindByName(name)
        return index or 0
    end

    ---Stable fake FileIDs so tests can assert icons without the client CASC table.
    function Macro.GetFileIDFromPath(filePath)
        local raidTarget = filePath:match("UI%-RaidTargetingIcon_(%d+)$")
        if raidTarget then
            return 9000 + tonumber(raidTarget)
        end
        return 1
    end

    function Macro.Create(name, icon, body)
        if Macro.createBlocked then
            error("CreateMacro is protected during combat", 2)
        end
        assert(type(name) == "string" and #name <= 16, "Bad macro name")
        local index = Macro.nextIndex
        Macro.nextIndex = Macro.nextIndex + 1
        Macro.slots[index] = { name = name, icon = icon, body = body or "" }
        return index
    end

    function Macro.Edit(macroInfo, name, icon, body)
        if Macro.createBlocked then
            error("EditMacro is protected during combat", 2)
        end
        local index, entry
        if type(macroInfo) == "number" then
            index, entry = macroInfo, Macro.slots[macroInfo]
        else
            index, entry = FindByName(macroInfo)
        end
        assert(entry, "Unknown macro: " .. tostring(macroInfo))
        if name ~= nil then
            entry.name = name
        end
        if icon ~= nil then
            entry.icon = icon
        end
        if body ~= nil then
            entry.body = body
        end
        return index
    end

    ---Test helper: returns the stored macro, or nil.
    function Macro.Get(name)
        local _, entry = FindByName(name)
        return entry
    end

    return Macro
end
