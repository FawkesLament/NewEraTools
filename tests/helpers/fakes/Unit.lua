return function()
    local Unit = {
        realm = "TestRealm",
        ---@type table<string, string|nil>
        guids = {
            player = "Player-1-00000001",
        },
    }

    function Unit.GetFullName(name)
        if name:find("-", 1, true) then
            return name
        end
        return name .. "-" .. Unit.realm
    end

    function Unit.GetGUID(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil
        end
        local guid = Unit.guids[unit]
        if type(guid) ~= "string" or guid == "" then
            return nil
        end
        return guid
    end

    function Unit.GetClassFile()
        return nil
    end

    ---@param classFile string|nil
    function Unit.GetClassColor(classFile)
        if type(classFile) ~= "string" or classFile == "" then
            return nil
        end
        return { r = 0.78, g = 0.61, b = 0.43 }
    end

    return Unit
end
