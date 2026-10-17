local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")

local WALL_THICKNESS = 2
local GATE_THICKNESS = 4
-- Callout path from "You" to the resolved edge (exit / jailbreak destination).
local PATH_LINE_THICKNESS = 3
local PATH_TIP_SIZE = 10
local EDGE_MARKER_SIZE = 20
-- Enlarged icon after a commander fires that edge's callout macro during a pull/test.
local EDGE_MARKER_HIGHLIGHT_SIZE = 32
-- After this many distinct edge macros fire in a home-station cycle, further clicks are locked.
local EDGE_CLICK_LOCK_COUNT = 3
-- Clickable frame around each marker; larger than the icon so markers are easy to hit.
local EDGE_MARKER_HIT_SIZE = 56
-- Gap between a wall and the near side of its marker icon.
local EDGE_MARKER_GAP = Spacing.MEDIUM
-- How far the hit box reaches past the walls (icon center sits at GAP + SIZE/2 from the wall).
local EDGE_MARKER_REACH = EDGE_MARKER_GAP + EDGE_MARKER_SIZE / 2 + EDGE_MARKER_HIT_SIZE / 2
-- Gap between the icon rim and the near side of the click-order badge (outward along the edge).
local EDGE_CLICK_ORDER_GAP = Spacing.TINY
-- Circular badge diameter around the 1–3 click-order digit.
local EDGE_CLICK_ORDER_BADGE_SIZE = 28

local HALO_ALPHA = 0.3

-- Unprotected host: click-used flags can be cleared mid-combat when dots return home.
-- Secure marker buttons read these via FrameRef + WrapScript (SetAttribute on protected frames is locked).
---@type Frame|nil
local edgeClickState

local function GetEdgeClickState()
    if not edgeClickState then
        edgeClickState = CreateFrame("Frame")
        edgeClickState:Hide()
    end
    return edgeClickState
end

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
---@field edgeMarkerMacroName fun(edge: integer): string|nil  SecureActionButton macro name.
---@field followsRotation boolean|nil  Turns with the map rotation setting.

---@class ArenaPathMarker
---@field edge integer  Fixed destination edge this path aims at.
---@field from ArenaPoint
---@field to ArenaPoint
---@field line Line
---@field tip Texture

---@class EdgeClickOrderBadge: Frame
---@field label FontString

---@class ArenaCanvas: Frame
---@field scale number
---@field rotated boolean
---@field placements function[]
---@field bossMarker ArenaPositionMarker|nil
---@field groupMarkers table<string, ArenaPositionMarker>|nil
---@field pathMarkers table<integer, ArenaPathMarker>|nil
---@field edgeIcons table<integer, Texture>
---@field edgeButtons table<integer, Button>
---@field edgeOutward table<integer, ArenaPoint>|nil  Unit outward normals for markable edges.
---@field edgeClickOrders table<integer, EdgeClickOrderBadge>|nil  Click-order badges beside commander markers.
---@field edgeHighlighted table<integer, boolean>|nil

-- Callout shows a path from "You" to this edge (nil = hidden).
local pathArrowTargetEdge = nil

---@class ArenaRow
---@field row Frame
---@field canvas ArenaCanvas
---@field exitLabel FontString
---@field entranceLabel FontString
---@field exitCell Frame  Hosts exitLabel; Layout.Row needs frames when the canvas is protected.
---@field entranceCell Frame  Hosts entranceLabel.
---@field width number  Of the labels and octagon side by side.
---@field inset number  Gap from the row's left side to the first label.

-- Every drawn arena, so a new marker assignment reaches all of them.
local canvases = {}

local Map = {
    MARKER_NAMES = MARKER_NAMES,
}
ns.SszorakMap = Map

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

local function CopyPoint(dest, src)
    dest.x = src.x
    dest.y = src.y
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

local function PlacePathLine(canvas, line, from, to)
    line:SetStartPoint("CENTER", canvas, ToCanvas(canvas, from.x, from.y))
    line:SetEndPoint("CENTER", canvas, ToCanvas(canvas, to.x, to.y))
end

local function SetPathMarkerShown(marker, shown)
    marker.line:SetShown(shown)
    marker.tip:SetShown(shown)
end

---@param canvas ArenaCanvas
---@param edge integer
---@return ArenaPathMarker
local function CreatePathMarker(canvas, edge)
    local from = { x = 0, y = 0 }
    local to = { x = 0, y = 0 }
    -- Above walls so the path stays visible over the octagon.
    local line = canvas:CreateLine(nil, "ARTWORK", nil, 2)
    line:SetThickness(PATH_LINE_THICKNESS)
    line:SetColorTexture(Widgets.UnpackColor(Colors.WARNING))
    local tip = CreateDot(canvas, to, 2)
    PaintDot(tip, PATH_TIP_SIZE, Colors.WARNING, 1)
    AddPlacement(canvas, function()
        PlacePathLine(canvas, line, from, to)
    end)
    ---@type ArenaPathMarker
    local marker = {
        edge = edge,
        from = from,
        to = to,
        line = line,
        tip = tip,
    }
    SetPathMarkerShown(marker, false)
    return marker
end

---@param canvas ArenaCanvas
local function CreatePathMarkers(canvas)
    canvas.pathMarkers = {}
    for edge = 1, Sszorak.ARENA_SIDES do
        canvas.pathMarkers[edge] = CreatePathMarker(canvas, edge)
    end
end

---@param edge integer
---@return boolean
local function ShouldShowPathMarker(edge)
    return pathArrowTargetEdge == edge
end

---Updates one edge's path from the current "You" position. Hides when `shown` is false.
---@param canvas ArenaCanvas
---@param edge integer
---@param shown boolean
local function UpdateCanvasPathMarker(canvas, edge, shown)
    local marker = canvas.pathMarkers and canvas.pathMarkers[edge]
    if not marker then
        return
    end
    if not shown then
        SetPathMarkerShown(marker, false)
        return
    end
    local from = Sszorak:GetGroupPosition(Sszorak:GetPlayerGroup())
    local to = Sszorak:GetEdgePathPoint(edge)
    local dx = to.x - from.x
    local dy = to.y - from.y
    if dx * dx + dy * dy < 1e-12 then
        SetPathMarkerShown(marker, false)
        return
    end
    CopyPoint(marker.from, from)
    CopyPoint(marker.to, to)
    SetPathMarkerShown(marker, true)
    PlacePathLine(canvas, marker.line, marker.from, marker.to)
end

---@param canvas ArenaCanvas
local function SyncCanvasPathMarkers(canvas)
    if not canvas.pathMarkers then
        return
    end
    for edge = 1, Sszorak.ARENA_SIDES do
        UpdateCanvasPathMarker(canvas, edge, ShouldShowPathMarker(edge))
    end
end

local function SyncAllPathMarkers()
    for _, canvas in ipairs(canvases) do
        SyncCanvasPathMarkers(canvas)
    end
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
    CreatePathMarkers(canvas)
end

local function RefreshPositionMarkers(canvas)
    MoveMarker(canvas.bossMarker, Sszorak:GetBossPosition())
    for group, marker in pairs(canvas.groupMarkers) do
        MoveMarker(marker, Sszorak:GetGroupPosition(group))
    end
    -- Keep path tips on "You" as the dots move during a callout.
    SyncCanvasPathMarkers(canvas)
    PlaceAll(canvas)
end

---Secure pre-click: while armed, first press per edge runs the macro; lock all after N edges.
local EDGE_MACRO_CLICK_WRAP = string.format(
    [[
    local state = self:GetFrameRef("clickState")
    if not state:GetAttribute("armed") then
        return
    end
    local used = tonumber(state:GetAttribute("usedCount")) or 0
    if used >= %d then
        return false
    end
    local id = self:GetAttribute("sszEdge")
    local key = "c" .. id
    if state:GetAttribute(key) then
        return false
    end
    state:SetAttribute(key, true)
    state:SetAttribute("usedCount", used + 1)
]],
    EDGE_CLICK_LOCK_COUNT
)

---Pixel offset from the icon center to the click-order badge center, outward along the edge normal.
---@param canvas ArenaCanvas
---@param edge integer
---@return number x, number y
local function EdgeClickOrderOffset(canvas, edge)
    local outward = canvas.edgeOutward and canvas.edgeOutward[edge]
    if not outward then
        return 0, 0
    end
    local ux, uy = outward.x, outward.y
    if canvas.rotated then
        ux, uy = -ux, -uy
    end
    local iconSize = (canvas.edgeHighlighted and canvas.edgeHighlighted[edge]) and EDGE_MARKER_HIGHLIGHT_SIZE
        or EDGE_MARKER_SIZE
    local dist = iconSize / 2 + EDGE_CLICK_ORDER_GAP + EDGE_CLICK_ORDER_BADGE_SIZE / 2
    return ux * dist, uy * dist
end

---@param canvas ArenaCanvas
---@param edge integer
local function PlaceEdgeClickOrder(canvas, edge)
    local badge = canvas.edgeClickOrders and canvas.edgeClickOrders[edge]
    local icon = canvas.edgeIcons[edge]
    if not badge or not icon then
        return
    end
    local ox, oy = EdgeClickOrderOffset(canvas, edge)
    badge:ClearAllPoints()
    badge:SetPoint("CENTER", icon, "CENTER", ox, oy)
end

---@param parent Frame
---@return EdgeClickOrderBadge
local function CreateEdgeClickOrderBadge(parent)
    local badge = CreateFrame("Frame", nil, parent) --[[@as EdgeClickOrderBadge]]
    badge:SetSize(EDGE_CLICK_ORDER_BADGE_SIZE, EDGE_CLICK_ORDER_BADGE_SIZE)
    -- Must not steal clicks from the secure edge-macro button underneath.
    badge:EnableMouse(false)
    badge:Hide()
    local fill = badge:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(Widgets.UnpackColor(Colors.SURFACE_RAISED))
    local mask = badge:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture(Assets.Textures.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fill:AddMaskTexture(mask)
    local label = Widgets.CreateLabel(badge, Fonts.OVERLAY_DIGIT)
    label:SetJustifyH("CENTER")
    label:SetPoint("CENTER")
    badge.label = label
    return badge
end

---@param canvas ArenaCanvas
---@param edge integer
---@param highlighted boolean
---@param clickOrder integer|nil  1–3 when highlighting after a commander click; ignored when clearing.
local function SetEdgeIconHighlighted(canvas, edge, highlighted, clickOrder)
    local icon = canvas.edgeIcons[edge]
    if not icon then
        return
    end
    canvas.edgeHighlighted = canvas.edgeHighlighted or {}
    canvas.edgeHighlighted[edge] = highlighted or nil
    icon:SetSize(
        highlighted and EDGE_MARKER_HIGHLIGHT_SIZE or EDGE_MARKER_SIZE,
        highlighted and EDGE_MARKER_HIGHLIGHT_SIZE or EDGE_MARKER_SIZE
    )
    local badge = canvas.edgeClickOrders and canvas.edgeClickOrders[edge]
    if not badge then
        return
    end
    if highlighted and clickOrder then
        badge.label:SetText(tostring(clickOrder))
        PlaceEdgeClickOrder(canvas, edge)
        badge:Show()
    else
        badge.label:SetText("")
        badge:Hide()
    end
end

---@param options ArenaCanvasOptions
local function CreateEdgeMarkerButton(canvas, edge, options)
    local macroName = options.edgeMarkerMacroName and options.edgeMarkerMacroName(edge)
    local template = macroName and Assets.Templates.SECURE_ACTION_BUTTON or nil
    local button = CreateFrame("Button", nil, canvas, template)
    button:SetSize(EDGE_MARKER_HIT_SIZE, EDGE_MARKER_HIT_SIZE)
    Widgets.AddHoverHighlight(button)
    if macroName then
        -- Named macros stay in sync via EditMacro; the button only needs the stable name.
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", macroName)
        -- One-shot + highlight while a pull/test is armed (see SetEdgeClickTrackingArmed).
        local clickState = GetEdgeClickState()
        button:SetAttribute("sszEdge", edge)
        button:SetFrameRef("clickState", clickState)
        button:WrapScript(button, "OnClick", EDGE_MACRO_CLICK_WRAP)
        button:HookScript("PostClick", function()
            if not clickState:GetAttribute("armed") then
                return
            end
            if not clickState:GetAttribute("c" .. edge) then
                return
            end
            -- WrapScript already bumped usedCount; that value is this click's order (1–3).
            local order = tonumber(clickState:GetAttribute("usedCount")) or 0
            SetEdgeIconHighlighted(canvas, edge, true, order)
        end)
    else
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", function(self)
            options.onEdgeMarkerClick(self, edge)
        end)
    end
    Widgets.AttachTooltip(button, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_NAMES[Sszorak:GetEdgeMarker(edge)])
    end)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
    icon:SetPoint("CENTER")
    ---@type EdgeClickOrderBadge|nil
    local orderBadge
    if macroName then
        -- Circular digit badge sits beside the icon (outward); placement follows the edge markers.
        orderBadge = CreateEdgeClickOrderBadge(button)
    end
    return button, icon, orderBadge
end

---@param options ArenaCanvasOptions
local function CreateEdgeMarkers(canvas, options)
    -- Edge midpoints lie 1 from the center, so each one is also its edge's outward unit normal.
    -- `distance` is in arena units, like the midpoints.
    local distance = 1 + (EDGE_MARKER_GAP + EDGE_MARKER_SIZE / 2) / canvas.scale
    canvas.edgeIcons = {}
    canvas.edgeButtons = {}
    canvas.edgeOutward = {}
    canvas.edgeClickOrders = {}
    local clickable = options.onEdgeMarkerClick or options.edgeMarkerMacroName
    for _, edgeMarker in ipairs(Sszorak:GetEdgeMarkers()) do
        local region, icon, orderBadge
        if clickable then
            region, icon, orderBadge = CreateEdgeMarkerButton(canvas, edgeMarker.edge, options)
            canvas.edgeButtons[edgeMarker.edge] = region
            if orderBadge then
                canvas.edgeClickOrders[edgeMarker.edge] = orderBadge
            end
        else
            icon = canvas:CreateTexture(nil, "OVERLAY")
            icon:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
            region = icon
        end
        -- Midpoint is the outward unit normal for the octagon of radius 1.
        canvas.edgeOutward[edgeMarker.edge] = { x = edgeMarker.x, y = edgeMarker.y }
        icon:SetTexture(Assets.WORLD_MARKER_ICONS[edgeMarker.marker])
        canvas.edgeIcons[edgeMarker.edge] = icon
        local x, y = edgeMarker.x * distance, edgeMarker.y * distance
        AddPlacement(canvas, function()
            region:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, x, y))
            if orderBadge then
                PlaceEdgeClickOrder(canvas, edgeMarker.edge)
            end
        end)
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

---Frame cell that sizes to the label so Layout.Row never anchors a protected canvas to a FontString.
---@param parent Frame
---@param edge integer
---@return Frame cell
---@return FontString label
local function CreateGateCell(parent, edge)
    local cell = CreateFrame("Frame", nil, parent)
    local label = CreateGateLabel(cell, edge)
    label:SetPoint("CENTER")
    return cell, label
end

---Lines up the gate labels on either side of the octagon, next to their edges: the exit is on the left
---unless the arena is rotated.
---@param arena ArenaRow
function Map.LayoutArenaRow(arena)
    local leftCell, rightCell = arena.exitCell, arena.entranceCell
    local leftLabel, rightLabel = arena.exitLabel, arena.entranceLabel
    if arena.canvas.rotated then
        leftCell, rightCell = rightCell, leftCell
        leftLabel, rightLabel = rightLabel, leftLabel
    end
    leftLabel:SetJustifyH("RIGHT")
    rightLabel:SetJustifyH("LEFT")
    -- Cells are frames: SecureActionButton children make the canvas protected, and protected
    -- frames cannot SetPoint to FontString/Texture regions.
    Layout.Row(arena.row, { leftCell, arena.canvas, rightCell }, Spacing.MEDIUM, arena.inset)
end

---Fills `row` with the octagon between its gate labels. Call LayoutArenaRow once `inset` is final.
---@param row Frame
---@param options ArenaCanvasOptions
---@return ArenaRow
function Map.CreateArenaRow(row, options)
    local exitCell, exitLabel = CreateGateCell(row, Sszorak.EXIT_EDGE)
    local entranceCell, entranceLabel = CreateGateCell(row, Sszorak.ENTRANCE_EDGE)
    -- Equal label widths keep the octagon centered between them.
    local labelWidth = math.max(exitLabel:GetStringWidth(), entranceLabel:GetStringWidth())
    exitLabel:SetWidth(labelWidth)
    entranceLabel:SetWidth(labelWidth)
    exitCell:SetSize(labelWidth, options.size)
    entranceCell:SetSize(labelWidth, options.size)

    return {
        row = row,
        canvas = CreateArenaCanvas(row, options),
        exitLabel = exitLabel,
        entranceLabel = entranceLabel,
        exitCell = exitCell,
        entranceCell = entranceCell,
        width = options.size + 2 * (labelWidth + Spacing.MEDIUM),
        inset = 0,
    }
end

---Height of a row holding an arena, with room for the marker icons outside the top and bottom walls.
---@param size number
---@return number
function Map.GetArenaRowHeight(size)
    return size + 2 * EDGE_MARKER_REACH
end

---Turns an arena that follows rotation to match the saved map rotation setting.
---@param arena ArenaRow
function Map.ApplyRotation(arena)
    local canvas = arena.canvas
    canvas.rotated = Sszorak:IsMapRotated()
    StyleGroupMarkers(canvas)
    -- Player group follows rotation; rebuild paths from the new "You" dot.
    SyncCanvasPathMarkers(canvas)
    PlaceAll(canvas)
    Map.LayoutArenaRow(arena)
end

function Map.RefreshEdgeMarkers()
    for _, canvas in ipairs(canvases) do
        RefreshEdgeMarkers(canvas)
    end
end

function Map.RefreshPositionMarkers()
    for _, canvas in ipairs(canvases) do
        if canvas.bossMarker then
            RefreshPositionMarkers(canvas)
        end
    end
end

---Shows a path line from the player's group ("You") to `targetEdge` with a tip dot, or hides it when nil.
---Only canvases with position markers are updated.
---@param targetEdge integer|nil
function Map.SetPathArrow(targetEdge)
    pathArrowTargetEdge = targetEdge
    SyncAllPathMarkers()
end

---Binds or clears SecureActionButton macros on floating-map edge markers.
---Editor markers (plain buttons) are left alone. Blocked during combat lockdown.
---@param enabled boolean
---@return boolean applied
function Map.SetEdgeMacroClicksEnabled(enabled)
    if Combat.IsLockedDown() then
        return false
    end
    for _, canvas in ipairs(canvases) do
        for edge, button in pairs(canvas.edgeButtons or {}) do
            if button:IsProtected() then
                if enabled then
                    button:SetAttribute("type", "macro")
                    button:SetAttribute("macro", Sszorak:GetEdgeMacroName(edge))
                else
                    button:SetAttribute("type", nil)
                    button:SetAttribute("macro", nil)
                end
            end
        end
    end
    return true
end

local function ClearEdgeClickUsedFlags()
    local clickState = GetEdgeClickState()
    for _, edge in ipairs(Sszorak.MARKABLE_EDGES) do
        clickState:SetAttribute("c" .. edge, nil)
    end
    clickState:SetAttribute("usedCount", nil)
end

local function ClearEdgeClickHighlights()
    for _, canvas in ipairs(canvases) do
        if canvas.edgeHighlighted then
            for edge in pairs(canvas.edgeHighlighted) do
                SetEdgeIconHighlighted(canvas, edge, false)
            end
        end
    end
end

---Clears per-edge "already clicked" flags and icon highlights (safe during combat lockdown).
function Map.ResetEdgeClickHighlights()
    ClearEdgeClickUsedFlags()
    ClearEdgeClickHighlights()
end

---Arms one-shot macro clicks for commander pull/test. Unprotected attributes; safe in combat.
---@param armed boolean
function Map.SetEdgeClickTrackingArmed(armed)
    local clickState = GetEdgeClickState()
    if armed then
        clickState:SetAttribute("armed", true)
    else
        clickState:SetAttribute("armed", nil)
        Map.ResetEdgeClickHighlights()
    end
end
