return function()
    local ACCOUNT_SLOTS = 120
    local CHARACTER_SLOTS = 18
    local MAX_BODY_LENGTH = 255

    local Macro = {
        ACCOUNT_SLOTS = ACCOUNT_SLOTS,
        CHARACTER_SLOTS = CHARACTER_SLOTS,
        MAX_BODY_LENGTH = MAX_BODY_LENGTH,
        ---@type table<number, { name: string, icon: string|number, body: string }>
        slots = {},
        createBlocked = false,
        createCount = 0,
        editCount = 0,
        failNextCreate = false,
        changeCallbacks = {},
    }

    local function CountRange(first, last)
        local count = 0
        for index = first, last do
            if Macro.slots[index] then
                count = count + 1
            end
        end
        return count
    end

    local function FirstFree(first, last)
        for index = first, last do
            if not Macro.slots[index] then
                return index
            end
        end
    end

    local function FindByName(name)
        for index = 1, ACCOUNT_SLOTS + CHARACTER_SLOTS do
            local entry = Macro.slots[index]
            if entry and entry.name == name then
                return index, entry
            end
        end
    end

    function Macro.GetIndexByName(name)
        local index = FindByName(name)
        return index or 0
    end

    function Macro.GetNum()
        return CountRange(1, ACCOUNT_SLOTS), CountRange(ACCOUNT_SLOTS + 1, ACCOUNT_SLOTS + CHARACTER_SLOTS)
    end

    function Macro.GetInfo(index)
        local entry = Macro.slots[index]
        if not entry then
            return nil
        end
        return entry.name, entry.icon, entry.body, false
    end

    function Macro.IsCharacterSlot(index)
        return type(index) == "number"
            and index > ACCOUNT_SLOTS
            and index <= ACCOUNT_SLOTS + CHARACTER_SLOTS
    end

    function Macro.Matches(index, name, icon, body)
        local currentName, currentIcon, currentBody = Macro.GetInfo(index)
        return currentName == name and currentIcon == icon and currentBody == body
    end

    ---Stable fake FileIDs so tests can assert icons without the client CASC table.
    function Macro.GetFileIDFromPath(filePath)
        local raidTarget = filePath:match("UI%-RaidTargetingIcon_(%d+)$")
        if raidTarget then
            return 9000 + tonumber(raidTarget)
        end
        return 1
    end

    function Macro.Create(name, icon, body, perCharacter)
        if Macro.createBlocked then
            error("CreateMacro is protected during combat", 2)
        end
        assert(type(name) == "string" and #name <= 16, "Bad macro name")
        if type(body) == "string" then
            assert(#body <= MAX_BODY_LENGTH, "Macro body too long")
        end
        if Macro.failNextCreate then
            Macro.failNextCreate = false
            return nil
        end
        local index
        if perCharacter then
            index = FirstFree(ACCOUNT_SLOTS + 1, ACCOUNT_SLOTS + CHARACTER_SLOTS)
        else
            index = FirstFree(1, ACCOUNT_SLOTS)
        end
        if not index then
            return nil
        end
        Macro.createCount = Macro.createCount + 1
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
        if type(body) == "string" then
            assert(#body <= MAX_BODY_LENGTH, "Macro body too long")
        end
        Macro.editCount = Macro.editCount + 1
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

    function Macro.OnChanged(callback)
        table.insert(Macro.changeCallbacks, callback)
        return function()
            for index, candidate in ipairs(Macro.changeCallbacks) do
                if candidate == callback then
                    table.remove(Macro.changeCallbacks, index)
                    return
                end
            end
        end
    end

    ---Test helper: fire UPDATE_MACROS.
    function Macro.FireChanged()
        for _, callback in ipairs(Macro.changeCallbacks) do
            callback()
        end
    end

    ---Test helper: returns the stored macro, or nil.
    function Macro.Get(name)
        local _, entry = FindByName(name)
        return entry
    end

    ---Test helper: fill every character-specific slot with placeholders.
    function Macro.FillCharacterSlotsForTests()
        for index = ACCOUNT_SLOTS + 1, ACCOUNT_SLOTS + CHARACTER_SLOTS do
            if not Macro.slots[index] then
                Macro.slots[index] = {
                    name = "Fill" .. index,
                    icon = 1,
                    body = "/say fill",
                }
            end
        end
    end

    return Macro
end
