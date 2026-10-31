return function()
    local Unit = {
        realm = "TestRealm",
        ---@type table<string, string|nil>
        guids = {
            player = "Player-1-00000001",
        },
        ---@type table<string, boolean>
        exists = {
            player = true,
        },
        ---@type table<string, string|nil>
        names = {
            player = "You",
        },
        ---@type table<string, boolean|nil>  nil = secret / unknown.
        assist = {
            player = true,
        },
        ---@type table<string, boolean|nil>  nil = secret / unknown.
        attack = {},
        ---@type table<string, boolean|nil>  nil = secret / unknown.
        bossMob = {},
    }

    function Unit.GetFullName(name)
        if name:find("-", 1, true) then
            return name
        end
        return name .. "-" .. Unit.realm
    end

    function Unit.Exists(unit)
        if type(unit) ~= "string" or unit == "" then
            return false
        end
        return Unit.exists[unit] == true
    end

    ---@return boolean|nil
    function Unit.CanPlayerAssist(unit)
        if not Unit.Exists(unit) then
            return nil
        end
        local canAssist = Unit.assist[unit]
        if canAssist == nil then
            return nil
        end
        return canAssist == true
    end

    ---@return boolean|nil
    function Unit.CanPlayerAttack(unit)
        if not Unit.Exists(unit) then
            return nil
        end
        local canAttack = Unit.attack[unit]
        if canAttack == nil then
            return nil
        end
        return canAttack == true
    end

    ---@return boolean|nil
    function Unit.IsBossMob(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil
        end
        local isBoss = Unit.bossMob[unit]
        if isBoss == nil then
            return nil
        end
        return isBoss == true
    end

    ---@param unit string
    ---@param state { exists: boolean|nil, guid: string|nil, name: string|nil, canAssist: boolean|nil, canAttack: boolean|nil, isBossMob: boolean|nil }
    function Unit.SetForTests(unit, state)
        if state.exists == nil then
            Unit.exists[unit] = false
        else
            Unit.exists[unit] = state.exists == true
        end
        Unit.guids[unit] = state.guid
        if state.name ~= nil then
            Unit.names[unit] = state.name
        end
        if state.canAssist == nil then
            Unit.assist[unit] = nil
        else
            Unit.assist[unit] = state.canAssist == true
        end
        if state.canAttack == nil then
            Unit.attack[unit] = nil
        else
            Unit.attack[unit] = state.canAttack == true
        end
        if state.isBossMob == nil then
            Unit.bossMob[unit] = nil
        else
            Unit.bossMob[unit] = state.isBossMob == true
        end
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

    function Unit.GetName(unit)
        if not Unit.Exists(unit) then
            return nil
        end
        local name = Unit.names[unit]
        if type(name) ~= "string" or name == "" then
            return nil
        end
        return name
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
