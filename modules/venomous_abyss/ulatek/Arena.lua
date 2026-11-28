-- Regular octagon arena for Ulatek: vertical sides, entrance on the bottom edge, markers on corners.
local _, ns = ...

local Ulatek = ns.Modules.Get("Ulatek")

---@class ArenaPoint
---@field x number
---@field y number  Up is positive.

local ARENA_SIDES = 8
-- Bottom horizontal edge of the octagon (vertices 7–8).
local ENTRANCE_EDGE = 7

Ulatek.ARENA_SIDES = ARENA_SIDES
Ulatek.ENTRANCE_EDGE = ENTRANCE_EDGE

---@param corner integer
---@return boolean
function Ulatek.IsArenaCorner(corner)
    return type(corner) == "number" and corner >= 1 and corner <= ARENA_SIDES and corner % 1 == 0
end

---Corners of the arena, a regular octagon with vertical edges on the left and right. Centered on the
---origin with an apothem of 1, so every edge lies 1 from the center. Listed counterclockwise from the
---bottom corner of the right edge, which makes edge 7 the bottom (entrance).
---@return ArenaPoint[]
function Ulatek:GetArenaVertices()
    local halfAngle = math.pi / ARENA_SIDES
    local radius = 1 / math.cos(halfAngle)
    local vertices = {}
    for index = 1, ARENA_SIDES do
        local angle = (2 * index - 3) * halfAngle
        vertices[index] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
    end
    return vertices
end

---Vertex `corner` (1–ARENA_SIDES) of the octagon.
---@param corner integer
---@return ArenaPoint
function Ulatek:GetCornerPoint(corner)
    assert(Ulatek.IsArenaCorner(corner), "Invalid corner: " .. tostring(corner))
    return self:GetArenaVertices()[corner]
end

---Midpoint of arena edge `edge` (1–ARENA_SIDES). For an apothem of 1 this lies on the outward bisector.
---@param edge integer
---@return ArenaPoint
function Ulatek:GetEdgeMidpoint(edge)
    assert(Ulatek.IsArenaCorner(edge), "Invalid edge: " .. tostring(edge))
    local vertices = self:GetArenaVertices()
    local from, to = vertices[edge], vertices[edge % ARENA_SIDES + 1]
    return { x = (from.x + to.x) / 2, y = (from.y + to.y) / 2 }
end
