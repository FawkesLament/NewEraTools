local _, ns = ...

-- Missing keys render as "[KEY]" so they are visible in-game instead of blank.
ns.L = setmetatable({}, {
    __index = function(_, key)
        return "[" .. tostring(key) .. "]"
    end,
})
