local _, ns = ...

local Util = {}
ns.Util = Util

local PRINT_PREFIX_COLOR = "ff33ff99"

---@param message string
function Util.Print(message)
    print("|c" .. PRINT_PREFIX_COLOR .. ns.ADDON_NAME .. "|r: " .. message)
end

---Fills missing keys in `target` from `defaults`, recursing into nested tables. Existing values win.
---@param target table
---@param defaults table
function Util.ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            Util.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

---Returns a deep copy of `value`. Nested tables are independent; non-tables are returned as-is.
---@param value any
---@return any
function Util.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = Util.DeepCopy(nested)
    end
    return copy
end

---@param value number
---@param min number
---@param max number
---@return number
function Util.Clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

---Rounds `value` to the nearest `step`, then clamps to `[min, max]`.
---@param value number
---@param min number
---@param max number
---@param step number
---@return number
function Util.Snap(value, min, max, step)
    local rounded = math.floor(value / step + 0.5) * step
    return math.min(math.max(rounded, min), max)
end

---Removes every key from `t` in place.
---@param t table
function Util.Wipe(t)
    for key in pairs(t) do
        t[key] = nil
    end
end
