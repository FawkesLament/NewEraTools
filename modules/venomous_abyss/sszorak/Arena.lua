local _, ns = ...

local Sszorak = ns.Modules.Get("Sszorak")

---@class ArenaPoint
---@field x number
---@field y number  Up is positive.

---@alias SszorakGroup "A"|"B"

---@class ArenaEdgeMarker: ArenaPoint  The midpoint of the edge the marker is attached to.
---@field edge integer
---@field marker WorldMarker

local ARENA_SIDES = 8
local ENTRANCE_EDGE = 1
local EXIT_EDGE = 5
-- Path tip sits on each edge's outward bisector at this fraction of the apothem (1).
local PATH_ARROW_RADIUS = 4 / 5

-- Absolute depth from the entrance gate (flipped to player-relative when on the exit side).
local EDGE_ENTRANCE_DEPTH = {
    [2] = "near",
    [3] = "mid",
    [4] = "far",
    [6] = "far",
    [7] = "mid",
    [8] = "near",
}

-- Group A (below, −Y) owns edges 6–8; group B (above, +Y) owns edges 2–4.
local EDGE_GROUP = {
    [2] = "B",
    [3] = "B",
    [4] = "B",
    [6] = "A",
    [7] = "A",
    [8] = "A",
}

Sszorak.ARENA_SIDES = ARENA_SIDES
Sszorak.ENTRANCE_EDGE = ENTRANCE_EDGE
Sszorak.EXIT_EDGE = EXIT_EDGE
Sszorak.PATH_ARROW_RADIUS = PATH_ARROW_RADIUS

---@param edge integer
---@return boolean
function Sszorak.IsMarkableEdge(edge)
    return type(edge) == "number"
        and edge >= 1
        and edge <= ARENA_SIDES
        and edge % 1 == 0
        and edge ~= ENTRANCE_EDGE
        and edge ~= EXIT_EDGE
end

local function OppositeEdge(edge)
    return (edge - 1 + ARENA_SIDES / 2) % ARENA_SIDES + 1
end

---The edge opposite `edge` across the arena center.
---@param edge integer
---@return integer
function Sszorak:GetOppositeEdge(edge)
    assert(Sszorak.IsMarkableEdge(edge), "Edge has no opposite marker edge: " .. tostring(edge))
    return OppositeEdge(edge)
end

---Corners of the arena, a regular octagon with vertical edges on the left and right. Centered on the
---origin with an apothem of 1, so every edge lies 1 from the center. Listed counterclockwise from the
---bottom corner of the right edge, which makes edge 1 the right edge (entrance) and edge 5 the left (exit).
---@return ArenaPoint[]
function Sszorak:GetArenaVertices()
    local halfAngle = math.pi / ARENA_SIDES
    local radius = 1 / math.cos(halfAngle)
    local vertices = {}
    for index = 1, ARENA_SIDES do
        local angle = (2 * index - 3) * halfAngle
        vertices[index] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
    end
    return vertices
end

---Midpoint of arena edge `edge` (1–ARENA_SIDES), including entrance and exit.
---For a regular octagon with apothem 1 this point lies on the edge and on its outward bisector.
---@param edge integer
---@return ArenaPoint
function Sszorak:GetEdgeMidpoint(edge)
    assert(
        type(edge) == "number" and edge >= 1 and edge <= ARENA_SIDES and edge % 1 == 0,
        "Invalid edge: " .. tostring(edge)
    )
    local vertices = self:GetArenaVertices()
    local from, to = vertices[edge], vertices[edge % ARENA_SIDES + 1]
    return { x = (from.x + to.x) / 2, y = (from.y + to.y) / 2 }
end

---Path-arrow tip for `edge`: on the outward perpendicular bisector at PATH_ARROW_RADIUS from center.
---@param edge integer
---@return ArenaPoint
function Sszorak:GetEdgePathPoint(edge)
    local mid = self:GetEdgeMidpoint(edge)
    return { x = mid.x * PATH_ARROW_RADIUS, y = mid.y * PATH_ARROW_RADIUS }
end

---Which raid group stands on `edge`, or nil for the gates.
---@param edge integer
---@return SszorakGroup|nil
function Sszorak:GetEdgeGroup(edge)
    return EDGE_GROUP[edge]
end

---Depth of `edge` measured from the entrance gate, or nil for the gates.
---@param edge integer
---@return "near"|"mid"|"far"|nil
function Sszorak:GetEdgeEntranceDepth(edge)
    return EDGE_ENTRANCE_DEPTH[edge]
end
