local _, ns = ...

local Color = {}
ns.Color = Color

---@class RgbColor
---@field r number
---@field g number
---@field b number

---Clamps r/g/b to 0–1. Returns nil when the value is not a usable color table.
---@param color any
---@return RgbColor|nil
function Color.Normalize(color)
    if type(color) ~= "table" then
        return nil
    end
    local r, g, b = color.r, color.g, color.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return {
        r = math.min(math.max(r, 0), 1),
        g = math.min(math.max(g, 0), 1),
        b = math.min(math.max(b, 0), 1),
    }
end

---@param a RgbColor
---@param b RgbColor
---@return boolean
function Color.Equal(a, b)
    return a.r == b.r and a.g == b.g and a.b == b.b
end

---Copies r/g/b from `color` into `saved` in place.
---@param saved RgbColor
---@param color RgbColor
function Color.Copy(saved, color)
    saved.r, saved.g, saved.b = color.r, color.g, color.b
end
