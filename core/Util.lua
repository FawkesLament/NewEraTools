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

---@param value number
---@param min number
---@param max number
---@return number
function Util.Clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

---Removes every key from `t` in place.
---@param t table
function Util.Wipe(t)
    for key in pairs(t) do
        t[key] = nil
    end
end
