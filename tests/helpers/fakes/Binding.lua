return function()
    local Binding = {
        ---@type table<any, { isPriority: boolean, key: string, buttonName: string }[]>
        overrides = {},
    }

    ---@param owner any
    ---@param isPriority boolean
    ---@param key string
    ---@param buttonName string
    function Binding.SetOverrideClick(owner, isPriority, key, buttonName)
        Binding.overrides[owner] = Binding.overrides[owner] or {}
        table.insert(Binding.overrides[owner], {
            isPriority = isPriority == true,
            key = key,
            buttonName = buttonName,
        })
    end

    ---@param owner any
    function Binding.ClearOverrides(owner)
        Binding.overrides[owner] = nil
    end

    return Binding
end
