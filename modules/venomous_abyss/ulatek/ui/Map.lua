-- Octagon arena canvas for Ulatek's marker editor: walls, entrance, and clickable corner icons.
local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local Ulatek = ns.Modules.Get("Ulatek")

local WALL_THICKNESS = 2
local GATE_THICKNESS = 4
local CORNER_MARKER_SIZE = 20
-- Clickable frame around each marker; larger than the icon so markers are easy to hit.
local CORNER_MARKER_HIT_SIZE = 56
-- Gap between a vertex and the near side of its marker icon.
local CORNER_MARKER_GAP = Spacing.MEDIUM
-- How far the hit box reaches past the walls (icon center sits at GAP + SIZE/2 from the vertex).
local CORNER_MARKER_REACH = CORNER_MARKER_GAP + CORNER_MARKER_SIZE / 2 + CORNER_MARKER_HIT_SIZE / 2

local MARKER_NAMES = {
    STAR = L.WORLD_MARKER_STAR,
    CIRCLE = L.WORLD_MARKER_CIRCLE,
    DIAMOND = L.WORLD_MARKER_DIAMOND,
    TRIANGLE = L.WORLD_MARKER_TRIANGLE,
    MOON = L.WORLD_MARKER_MOON,
    SQUARE = L.WORLD_MARKER_SQUARE,
    CROSS = L.WORLD_MARKER_CROSS,
    SKULL = L.WORLD_MARKER_SKULL,
}

---@class ArenaCanvasOptions
---@field size number  Distance between opposite edges of the octagon.
---@field onCornerMarkerClick fun(button: Button, corner: integer)|nil  Makes the marker icons clickable.

---@class ArenaCanvas: Frame
---@field scale number
---@field placements function[]
---@field cornerIcons table<integer, Texture>
---@field cornerButtons table<integer, Button>

---@class ArenaRow
---@field row Frame
---@field canvas ArenaCanvas
---@field entranceLabel FontString  Sits outside the entrance gate.
---@field width number  Octagon plus room for corner icons on either side.
---@field inset number  Gap from the row's left side to the octagon's reserved box.

local canvases = {}

local Map = {
    MARKER_NAMES = MARKER_NAMES,
}
Internals.Map = Map

---@return number x, number y  Offset from the canvas center of the arena point (x, y).
local function ToCanvas(canvas, x, y)
    return x * canvas.scale, y * canvas.scale
end

local function AddPlacement(canvas, place)
    table.insert(canvas.placements, place)
    place()
end

local function DrawEdge(canvas, from, to, thickness, color, sublevel)
    local line = canvas:CreateLine(nil, "ARTWORK", nil, sublevel)
    line:SetThickness(thickness)
    line:SetColorTexture(Widgets.UnpackColor(color))
    AddPlacement(canvas, function()
        line:SetStartPoint("CENTER", canvas, ToCanvas(canvas, from.x, from.y))
        line:SetEndPoint("CENTER", canvas, ToCanvas(canvas, to.x, to.y))
    end)
end

---@param options ArenaCanvasOptions
local function CreateCornerMarkerButton(canvas, corner, options)
    local button = CreateFrame("Button", nil, canvas)
    button:SetSize(CORNER_MARKER_HIT_SIZE, CORNER_MARKER_HIT_SIZE)
    Widgets.AddHoverHighlight(button)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        options.onCornerMarkerClick(self, corner)
    end)
    Widgets.AttachTooltip(button, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_NAMES[Ulatek:GetCornerMarker(corner)])
    end)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CORNER_MARKER_SIZE, CORNER_MARKER_SIZE)
    icon:SetPoint("CENTER")
    return button, icon
end

---@param options ArenaCanvasOptions
local function CreateCornerMarkers(canvas, options)
    local circumradius = 1 / math.cos(math.pi / Ulatek.ARENA_SIDES)
    local distance = circumradius + (CORNER_MARKER_GAP + CORNER_MARKER_SIZE / 2) / canvas.scale
    canvas.cornerIcons = {}
    canvas.cornerButtons = {}
    local clickable = options.onCornerMarkerClick ~= nil
    for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
        local region, icon
        if clickable then
            region, icon = CreateCornerMarkerButton(canvas, cornerMarker.corner, options)
            canvas.cornerButtons[cornerMarker.corner] = region
        else
            icon = canvas:CreateTexture(nil, "OVERLAY")
            icon:SetSize(CORNER_MARKER_SIZE, CORNER_MARKER_SIZE)
            region = icon
        end
        icon:SetTexture(Assets.WORLD_MARKER_ICONS[cornerMarker.marker])
        canvas.cornerIcons[cornerMarker.corner] = icon
        local unit = circumradius
        local x, y = cornerMarker.x / unit * distance, cornerMarker.y / unit * distance
        AddPlacement(canvas, function()
            region:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, x, y))
        end)
    end
end

local function RefreshCornerMarkers(canvas)
    for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
        canvas.cornerIcons[cornerMarker.corner]:SetTexture(Assets.WORLD_MARKER_ICONS[cornerMarker.marker])
    end
end

---@param options ArenaCanvasOptions
---@return ArenaCanvas
local function CreateArenaCanvas(parent, options)
    local canvas = CreateFrame("Frame", nil, parent) --[[@as ArenaCanvas]]
    canvas:SetSize(options.size, options.size)
    canvas.scale = options.size / 2
    canvas.placements = {}

    CreateCornerMarkers(canvas, options)
    local vertices = Ulatek:GetArenaVertices()
    for index, from in ipairs(vertices) do
        local to = vertices[index % #vertices + 1]
        if index == Ulatek.ENTRANCE_EDGE then
            DrawEdge(canvas, from, to, GATE_THICKNESS, Colors.ACCENT, 1)
        else
            DrawEdge(canvas, from, to, WALL_THICKNESS, Colors.TEXT_MUTED, 0)
        end
    end

    table.insert(canvases, canvas)
    return canvas
end

local function CreateEntranceLabel(parent)
    local label = Widgets.CreateLabel(parent, Fonts.BODY, L.ULATEK_ENTRANCE)
    label:SetTextColor(Widgets.UnpackColor(Colors.ACCENT))
    label:SetWordWrap(false)
    label:SetJustifyH("CENTER")
    return label
end

---Puts the entrance label just outside its edge. The text stays upright.
---@param canvas ArenaCanvas
---@param label FontString
local function PlaceEntranceLabel(canvas, label)
    local mid = Ulatek:GetEdgeMidpoint(Ulatek.ENTRANCE_EDGE)
    local halfW = label:GetStringWidth() / 2
    local halfH = Assets.FontStyles[Fonts.BODY].size / 2
    local reach = math.abs(mid.x) * halfW + math.abs(mid.y) * halfH
    local dist = canvas.scale + Spacing.MEDIUM + reach
    label:ClearAllPoints()
    label:SetPoint("CENTER", canvas, "CENTER", mid.x * dist, mid.y * dist)
end

---Centers the octagon in the row. The entrance label is anchored to the canvas.
---@param arena ArenaRow
function Map.LayoutArenaRow(arena)
    local canvas = arena.canvas
    canvas:ClearAllPoints()
    local left = arena.inset + (arena.width - canvas:GetWidth()) / 2
    canvas:SetPoint("LEFT", arena.row, "LEFT", left, 0)
end

---Fills `row` with the octagon. Call LayoutArenaRow once `inset` is final.
---@param row Frame
---@param options ArenaCanvasOptions
---@return ArenaRow
function Map.CreateArenaRow(row, options)
    local canvas = CreateArenaCanvas(row, options)
    local entranceLabel = CreateEntranceLabel(canvas)
    AddPlacement(canvas, function()
        PlaceEntranceLabel(canvas, entranceLabel)
    end)

    return {
        row = row,
        canvas = canvas,
        entranceLabel = entranceLabel,
        width = options.size + 2 * CORNER_MARKER_REACH,
        inset = 0,
    }
end

---Height of a row holding an arena, with room for the marker icons outside the top and bottom walls.
---@param size number
---@return number
function Map.GetArenaRowHeight(size)
    return size + 2 * CORNER_MARKER_REACH
end

function Map.RefreshCornerMarkers()
    for _, canvas in ipairs(canvases) do
        RefreshCornerMarkers(canvas)
    end
end
