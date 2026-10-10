local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")

local WALL_THICKNESS = 2
local GATE_THICKNESS = 4
local EDGE_MARKER_SIZE = 20
-- Clickable frame around each marker; larger than the icon so vents are easy to hit in combat.
local EDGE_MARKER_HIT_SIZE = 56
-- Gap between a wall and the near side of its marker icon.
local EDGE_MARKER_GAP = Spacing.MEDIUM
-- How far the hit box reaches past the walls (icon center sits at GAP + SIZE/2 from the wall).
local EDGE_MARKER_REACH = EDGE_MARKER_GAP + EDGE_MARKER_SIZE / 2 + EDGE_MARKER_HIT_SIZE / 2
-- Selected wind-vent markers grow so they stand out from the rest.
local EDGE_MARKER_SELECTED_SIZE = 32

local HALO_ALPHA = 0.3

local GATES = {
    [Sszorak.ENTRANCE_EDGE] = { color = Colors.ACCENT, text = L.SSZORAK_ENTRANCE },
    [Sszorak.EXIT_EDGE] = { color = Colors.WARNING, text = L.SSZORAK_EXIT },
}

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

---@class ArenaMarkerStyle
---@field size number  Dot diameter.
---@field halo number|nil  Diameter of a translucent ring behind the dot, to make it stand out.
---@field color table  A color from Assets.Colors.

local BOSS_STYLE = { size = 14, color = Colors.ERROR }
local PLAYER_GROUP_STYLE = { size = 12, halo = 24, color = Colors.TEXT }
local OTHER_GROUP_STYLE = { size = 8, color = Colors.TEXT_MUTED }

---@class ArenaCanvasOptions
---@field size number  Distance between opposite edges of the octagon.
---@field showPositions boolean|nil  Draws the boss and group positions.
---@field onEdgeMarkerClick fun(button: Button, edge: integer)|nil  Makes the marker icons clickable.
---@field windHighlights boolean|nil  Selected wind-vent icons scale up on this canvas.
---@field followsRotation boolean|nil  Turns with the map rotation setting.

---@class ArenaCanvas: Frame
---@field scale number
---@field rotated boolean
---@field placements function[]
---@field bossMarker ArenaPositionMarker|nil
---@field groupMarkers table<string, ArenaPositionMarker>|nil
---@field edgeIcons table<integer, Texture>
---@field edgeButtons table<integer, Button>
---@field windHighlights boolean

---@class ArenaRow
---@field row Frame
---@field canvas ArenaCanvas
---@field exitLabel FontString
---@field entranceLabel FontString
---@field width number  Of the labels and octagon side by side.
---@field inset number  Gap from the row's left side to the first label.

-- Every drawn arena, so a new marker assignment reaches all of them.
local canvases = {}

local SszorakMapUI = {
    MARKER_NAMES = MARKER_NAMES,
}
ns.SszorakMapUI = SszorakMapUI

---@return number x, number y  Offset from the canvas center of the arena point (x, y).
local function ToCanvas(canvas, x, y)
    local scale = canvas.scale
    if canvas.rotated then
        return -x * scale, -y * scale
    end
    return x * scale, y * scale
end

-- Anchors depend on the rotation, so every drawn piece keeps a function that places it, rerun on rotation.
local function AddPlacement(canvas, place)
    table.insert(canvas.placements, place)
    place()
end

local function PlaceAll(canvas)
    for _, place in ipairs(canvas.placements) do
        place()
    end
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

local function CreateDot(canvas, point, sublevel)
    local dot = canvas:CreateTexture(nil, "OVERLAY", nil, sublevel)
    AddPlacement(canvas, function()
        dot:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, point.x, point.y))
    end)

    local mask = canvas:CreateMaskTexture()
    mask:SetTexture(Assets.Textures.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(dot)
    dot:AddMaskTexture(mask)
    return dot
end

local function PaintDot(dot, size, color, alpha)
    dot:SetSize(size, size)
    local r, g, b = Widgets.UnpackColor(color)
    dot:SetColorTexture(r, g, b, alpha)
end

---@class ArenaPositionMarker
---@field point ArenaPoint  Mutable; updated as the map animation moves the dots.
---@field halo Texture
---@field dot Texture
---@field label FontString
---@field offset number  Gap between the dot's center and the near side of the label.

local function PlaceMarkerLabel(canvas, marker)
    -- Keep labels toward the arena center so they don't sit on the nearer gate.
    marker.label:ClearAllPoints()
    local labelOnLeft = (marker.point.x >= 0) ~= canvas.rotated
    if labelOnLeft then
        marker.label:SetPoint("RIGHT", marker.dot, "CENTER", -marker.offset, 0)
    else
        marker.label:SetPoint("LEFT", marker.dot, "CENTER", marker.offset, 0)
    end
end

---Draws an unstyled marker at `point`; StyleMarker gives it a look.
---@return ArenaPositionMarker
local function CreateMarker(canvas, point)
    local marker = {
        point = { x = point.x, y = point.y },
        label = Widgets.CreateLabel(canvas, Fonts.BODY),
        offset = 0,
    }
    marker.halo = CreateDot(canvas, marker.point, 0)
    marker.dot = CreateDot(canvas, marker.point, 1)
    AddPlacement(canvas, function()
        PlaceMarkerLabel(canvas, marker)
    end)
    return marker
end

local function MoveMarker(marker, point)
    marker.point.x = point.x
    marker.point.y = point.y
end

---@param marker ArenaPositionMarker
---@param style ArenaMarkerStyle
---@param text string|nil  Label beside the dot; none if nil.
local function StyleMarker(canvas, marker, style, text)
    marker.halo:SetShown(style.halo ~= nil)
    if style.halo then
        PaintDot(marker.halo, style.halo, style.color, HALO_ALPHA)
    end
    PaintDot(marker.dot, style.size, style.color, 1)
    marker.label:SetText(text or "")
    marker.label:SetTextColor(Widgets.UnpackColor(style.color))
    marker.offset = (style.halo or style.size) / 2 + Spacing.SMALL
    PlaceMarkerLabel(canvas, marker)
end

-- The player's group can change with the map rotation, so the group markers are restyled rather than redrawn.
local function StyleGroupMarkers(canvas)
    local playerGroup = Sszorak:GetPlayerGroup()
    for group, marker in pairs(canvas.groupMarkers) do
        if group == playerGroup then
            StyleMarker(canvas, marker, PLAYER_GROUP_STYLE, L.SSZORAK_YOU)
        else
            StyleMarker(canvas, marker, OTHER_GROUP_STYLE)
        end
    end
end

local function CreatePositionMarkers(canvas)
    canvas.bossMarker = CreateMarker(canvas, Sszorak:GetBossPosition())
    StyleMarker(canvas, canvas.bossMarker, BOSS_STYLE, L.SSZORAK_BOSS)

    canvas.groupMarkers = {}
    for _, group in ipairs(Sszorak.GROUPS) do
        canvas.groupMarkers[group] = CreateMarker(canvas, Sszorak:GetGroupPosition(group))
    end
    StyleGroupMarkers(canvas)
end

local function RefreshPositionMarkers(canvas)
    MoveMarker(canvas.bossMarker, Sszorak:GetBossPosition())
    for group, marker in pairs(canvas.groupMarkers) do
        MoveMarker(marker, Sszorak:GetGroupPosition(group))
    end
    PlaceAll(canvas)
end

local function CreateEdgeMarkerButton(canvas, edge, onClick)
    local button = CreateFrame("Button", nil, canvas)
    button:SetSize(EDGE_MARKER_HIT_SIZE, EDGE_MARKER_HIT_SIZE)
    button:RegisterForClicks("LeftButtonUp")
    Widgets.AddHoverHighlight(button)
    button:SetScript("OnClick", function(self)
        onClick(self, edge)
    end)
    Widgets.AttachTooltip(button, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_NAMES[Sszorak:GetEdgeMarker(edge)])
    end)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
    icon:SetPoint("CENTER")
    return button, icon
end

---@param options ArenaCanvasOptions
local function CreateEdgeMarkers(canvas, options)
    -- Edge midpoints lie 1 from the center, so each one is also its edge's outward unit normal.
    -- `distance` is in arena units, like the midpoints.
    local distance = 1 + (EDGE_MARKER_GAP + EDGE_MARKER_SIZE / 2) / canvas.scale
    canvas.edgeIcons = {}
    canvas.edgeButtons = {}
    canvas.windHighlights = options.windHighlights == true
    local baseLevel = canvas:GetFrameLevel()
    for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
        local region, icon
        if options.onEdgeMarkerClick then
            region, icon = CreateEdgeMarkerButton(canvas, edgeMarker.edge, options.onEdgeMarkerClick)
            canvas.edgeButtons[edgeMarker.edge] = region
            region:SetFrameLevel(baseLevel + 1)
        else
            icon = canvas:CreateTexture(nil, "OVERLAY")
            icon:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
            region = icon
        end
        local x, y = edgeMarker.x * distance, edgeMarker.y * distance
        AddPlacement(canvas, function()
            region:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, x, y))
        end)
        icon:SetTexture(Assets.WORLD_MARKER_ICONS[edgeMarker.marker])
        canvas.edgeIcons[edgeMarker.edge] = icon
    end
end

local function RefreshEdgeMarkers(canvas)
    for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
        canvas.edgeIcons[edgeMarker.edge]:SetTexture(Assets.WORLD_MARKER_ICONS[edgeMarker.marker])
    end
end

---@param options ArenaCanvasOptions
---@return ArenaCanvas
local function CreateArenaCanvas(parent, options)
    local canvas = CreateFrame("Frame", nil, parent) --[[@as ArenaCanvas]]
    canvas:SetSize(options.size, options.size)
    canvas.scale = options.size / 2
    canvas.rotated = options.followsRotation and Sszorak:IsMapRotated() or false
    canvas.placements = {}

    if options.showPositions then
        CreatePositionMarkers(canvas)
    end
    CreateEdgeMarkers(canvas, options)
    local vertices = Sszorak:GetArenaVertices()
    for index, from in ipairs(vertices) do
        local to = vertices[index % #vertices + 1]
        local gate = GATES[index]
        if gate then
            -- Drawn above the walls so the overlapping corners show the gate color.
            DrawEdge(canvas, from, to, GATE_THICKNESS, gate.color, 1)
        else
            DrawEdge(canvas, from, to, WALL_THICKNESS, Colors.TEXT_MUTED, 0)
        end
    end

    table.insert(canvases, canvas)
    return canvas
end

local function CreateGateLabel(parent, edge)
    local gate = GATES[edge]
    local label = Widgets.CreateLabel(parent, Fonts.BODY, gate.text)
    label:SetTextColor(Widgets.UnpackColor(gate.color))
    label:SetWordWrap(false)
    return label
end

---Lines up the gate labels on either side of the octagon, next to their edges: the exit is on the left
---unless the arena is rotated.
---@param arena ArenaRow
function SszorakMapUI.LayoutArenaRow(arena)
    local left, right = arena.exitLabel, arena.entranceLabel
    if arena.canvas.rotated then
        left, right = right, left
    end
    left:SetJustifyH("RIGHT")
    right:SetJustifyH("LEFT")
    Layout.Row(arena.row, { left, arena.canvas, right }, Spacing.MEDIUM, arena.inset)
end

---Fills `row` with the octagon between its gate labels. Call LayoutArenaRow once `inset` is final.
---@param row Frame
---@param options ArenaCanvasOptions
---@return ArenaRow
function SszorakMapUI.CreateArenaRow(row, options)
    local exitLabel = CreateGateLabel(row, Sszorak.EXIT_EDGE)
    local entranceLabel = CreateGateLabel(row, Sszorak.ENTRANCE_EDGE)
    -- Equal label widths keep the octagon centered between them.
    local labelWidth = math.max(exitLabel:GetStringWidth(), entranceLabel:GetStringWidth())
    exitLabel:SetWidth(labelWidth)
    entranceLabel:SetWidth(labelWidth)

    return {
        row = row,
        canvas = CreateArenaCanvas(row, options),
        exitLabel = exitLabel,
        entranceLabel = entranceLabel,
        width = options.size + 2 * (labelWidth + Spacing.MEDIUM),
        inset = 0,
    }
end

---Height of a row holding an arena, with room for the marker icons outside the top and bottom walls.
---@param size number
---@return number
function SszorakMapUI.GetArenaRowHeight(size)
    return size + 2 * EDGE_MARKER_REACH
end

---Turns an arena that follows rotation to match the saved map rotation setting.
---@param arena ArenaRow
function SszorakMapUI.ApplyRotation(arena)
    local canvas = arena.canvas
    canvas.rotated = Sszorak:IsMapRotated()
    PlaceAll(canvas)
    StyleGroupMarkers(canvas)
    SszorakMapUI.LayoutArenaRow(arena)
end

function SszorakMapUI.RefreshEdgeMarkers()
    for _, canvas in ipairs(canvases) do
        RefreshEdgeMarkers(canvas)
    end
end

function SszorakMapUI.RefreshPositionMarkers()
    for _, canvas in ipairs(canvases) do
        if canvas.bossMarker then
            RefreshPositionMarkers(canvas)
        end
    end
end

function SszorakMapUI.RefreshWindHighlights()
    for _, canvas in ipairs(canvases) do
        if canvas.windHighlights then
            local interactive = Sszorak:IsWindHelperInteractive()
            local baseLevel = canvas:GetFrameLevel()
            for edge, icon in pairs(canvas.edgeIcons) do
                local selected = interactive and Sszorak:IsWindVent(edge)
                icon:SetSize(selected and EDGE_MARKER_SELECTED_SIZE or EDGE_MARKER_SIZE,
                    selected and EDGE_MARKER_SELECTED_SIZE or EDGE_MARKER_SIZE)
                local button = canvas.edgeButtons[edge]
                if button then
                    -- Selected markers sit above neighbors so a second click unselects instead of
                    -- hitting an overlapping unselected hit box (which no-ops at the 3-vent cap).
                    button:SetFrameLevel(baseLevel + (selected and 3 or 1))
                end
            end
        end
    end
end
