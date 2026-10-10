return function()
    local Unit = { realm = "TestRealm" }

    function Unit.GetFullName(name)
        if name:find("-", 1, true) then
            return name
        end
        return name .. "-" .. Unit.realm
    end

    function Unit.GetClassFile()
        return nil
    end

    function Unit.GetClassColor()
        return nil
    end

    return Unit
end
