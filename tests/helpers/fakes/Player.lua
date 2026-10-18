return function()
    local Player = {
        fullName = "Player-TestRealm",
        guid = "Player-1-00000001",
        classFile = "DRUID",
        specializationId = 105,
        role = "HEALER",
        classNames = {
            DRUID = "Druid",
            MAGE = "Mage",
            WARRIOR = "Warrior",
        },
        specializationNames = {
            [64] = "Frost",
            [71] = "Arms",
        },
        specializations = {
            { id = 102, name = "Balance", role = "DAMAGER" },
            { id = 103, name = "Feral", role = "DAMAGER" },
            { id = 104, name = "Guardian", role = "TANK" },
            { id = 105, name = "Restoration", role = "HEALER" },
        },
        changeCallbacks = {},
    }

    local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

    function Player.GetFullName()
        return Player.fullName
    end

    function Player.GetGUID()
        return Player.guid
    end

    function Player.GetClassFile()
        return Player.classFile
    end

    function Player.GetClassName(classFile)
        if type(classFile) ~= "string" or classFile == "" then
            return nil
        end
        return Player.classNames[classFile]
    end

    function Player.GetSpecializationName(specializationId)
        if type(specializationId) ~= "number" then
            return nil
        end
        for _, spec in ipairs(Player.specializations) do
            if spec.id == specializationId then
                return spec.name
            end
        end
        return Player.specializationNames[specializationId]
    end

    function Player.GetSpecializationId()
        return Player.specializationId
    end

    function Player.GetSpecializationIcon(specializationId)
        if type(specializationId) ~= "number" then
            return nil
        end
        for _, spec in ipairs(Player.specializations) do
            if spec.id == specializationId then
                return spec.icon
            end
        end
        return nil
    end

    function Player.GetRole()
        return Player.role
    end

    function Player.ListSpecializations()
        local list = {}
        for index, spec in ipairs(Player.specializations) do
            list[index] = {
                id = spec.id,
                name = spec.name,
                role = spec.role,
            }
        end
        return list
    end

    function Player.ListRoles()
        local seen = {}
        local roles = {}
        for _, spec in ipairs(Player.specializations) do
            if not seen[spec.role] then
                seen[spec.role] = true
                roles[#roles + 1] = spec.role
            end
        end
        table.sort(roles, function(a, b)
            return (ROLE_ORDER[a] or 99) < (ROLE_ORDER[b] or 99)
        end)
        return roles
    end

    function Player.GetActivationContext()
        return {
            classFile = Player.classFile,
            specializationId = Player.specializationId,
            role = Player.role,
        }
    end

    function Player.OnChanged(callback)
        table.insert(Player.changeCallbacks, callback)
    end

    ---Test helper: replace the fake player's class / spec / role context.
    ---Nil fields are left alone. Use ClearContextForTests to represent a missing specialization.
    ---@param context { classFile: string|nil, specializationId: integer|nil, role: string|nil, specializations: table|nil }
    function Player.SetContextForTests(context)
        if context.classFile ~= nil then
            Player.classFile = context.classFile
        end
        if context.specializationId ~= nil then
            Player.specializationId = context.specializationId
        end
        if context.role ~= nil then
            Player.role = context.role
        end
        if context.specializations ~= nil then
            Player.specializations = context.specializations
        end
    end

    local CLEARABLE = {
        classFile = true,
        specializationId = true,
        role = true,
    }

    ---Test helper: set context fields to nil. Production getters return nil when that context is unavailable.
    ---@param fields string[]
    function Player.ClearContextForTests(fields)
        assert(type(fields) == "table", "Bad context fields")
        for _, field in ipairs(fields) do
            assert(CLEARABLE[field] == true, "Cannot clear " .. tostring(field))
            Player[field] = nil
        end
    end

    function Player.FireChanged()
        for _, callback in ipairs(Player.changeCallbacks) do
            callback()
        end
    end

    return Player
end
