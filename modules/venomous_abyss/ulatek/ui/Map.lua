-- Octagon arena canvas for Ulatek: walls, entrance, corner markers, and combat-safe callout buttons.
local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local Assets = ns.Assets
local Timer = ns.Api.Timer
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local Ulatek = ns.Modules.Get("Ulatek")

local WALL_THICKNESS = 2
local GATE_THICKNESS = 4
local CORNER_MARKER_SIZE = 20
-- Transparent wave-order hit targets; chevrons are tinted addon textures.
local WAVE_BUTTON_WIDTH = 48
local WAVE_BUTTON_HEIGHT = 44
local WAVE_BUTTON_GAP = 18
local WAVE_ARROW_SIZE = 48
local WAVE_FLASH_DURATION = 0.2
-- Transparent boss-rise hit targets; dashed circles are tinted addon textures.
local BOSS_HIT_SIZE = 36
local BOSS_ICON_SIZE = 45
-- Gap from the octagon's vertical edge to the near side of the hit box.
local BOSS_OUTSIDE_GAP = 11
local BOSS_FLASH_DURATION = 0.2
-- Wave chevrons (#34D399 idle, #6EE7B7 hover).
local WAVE_ARROW_IDLE = { r = 0.20, g = 0.83, b = 0.60, a = 0.85 }
local WAVE_ARROW_HOVER = { r = 0.43, g = 0.91, b = 0.72, a = 1 }
local WAVE_ARROW_FLASH = { r = 1, g = 1, b = 1, a = 1 }
-- Boss dashed circles (#38BDF8 idle, #7DD3FC hover).
local BOSS_ICON_IDLE = { r = 0.22, g = 0.74, b = 0.97, a = 0.80 }
local BOSS_ICON_HOVER = { r = 0.49, g = 0.83, b = 0.99, a = 1 }
local BOSS_ICON_FLASH = { r = 1, g = 1, b = 1, a = 1 }
local WAVE_LEFT = "WAVE_LEFT"
local WAVE_RIGHT = "WAVE_RIGHT"
local BOSS_LEFT = "BOSS_LEFT"
local BOSS_RIGHT = "BOSS_RIGHT"
-- Clickable frame around each marker; larger than the icon so markers are easy to hit.
local CORNER_MARKER_HIT_SIZE = 56
-- Gap between a vertex and the near side of its marker icon.
local CORNER_MARKER_GAP = Spacing.MEDIUM

---@param markerSize number
---@return number
local function CornerMarkerReach(markerSize)
    return CORNER_MARKER_GAP + markerSize / 2 + CORNER_MARKER_HIT_SIZE / 2
end

---@param options ArenaCanvasOptions
---@return number
local function CornerMarkerSize(options)
    return options.markerSize or CORNER_MARKER_SIZE
end

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
---@field markerSize number|nil  Corner icon size. Defaults to 20.
---@field onCornerMarkerClick fun(button: Button, corner: integer)|nil  Makes the marker icons clickable.
---@field showCalloutButtons boolean|nil  Secure raid-warning buttons on the floating pad only.

---@class ArenaCanvas: Frame
---@field scale number
---@field placements function[]
---@field cornerIcons table<integer, Texture>
---@field cornerButtons table<integer, Button>
---@field calloutButtons table<string, Button>|nil

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
    local markerSize = CornerMarkerSize(options)
    icon:SetSize(markerSize, markerSize)
    icon:SetPoint("CENTER")
    return button, icon
end

---@param options ArenaCanvasOptions
local function CreateCornerMarkers(canvas, options)
    local circumradius = 1 / math.cos(math.pi / Ulatek.ARENA_SIDES)
    local markerSize = CornerMarkerSize(options)
    local distance = circumradius + (CORNER_MARKER_GAP + markerSize / 2) / canvas.scale
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
            icon:SetSize(markerSize, markerSize)
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

---@param region Region
local function SnapToPixel(region)
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(true)
        region:SetTexelSnappingBias(0)
    end
end

---Transparent secure hit target with a tinted double-chevron texture. No box; color-only hover.
---@param canvas ArenaCanvas
---@param spec { pointingLeft: boolean, x: number, y: number }
---@return Button
local function CreateWaveButton(canvas, spec)
    local button = CreateFrame("Button", nil, canvas, Assets.Templates.SECURE_ACTION_BUTTON)
    button:SetSize(WAVE_BUTTON_WIDTH, WAVE_BUTTON_HEIGHT)
    SnapToPixel(button)
    button:SetPoint("CENTER", canvas, "CENTER", math.floor(spec.x + 0.5), math.floor(spec.y + 0.5))

    local arrow = button:CreateTexture(nil, "ARTWORK")
    local path = spec.pointingLeft and Assets.Textures.ARROW_DOUBLE_CHEVRON_LEFT
        or Assets.Textures.ARROW_DOUBLE_CHEVRON_RIGHT
    arrow:SetTexture(path, "CLAMP", "CLAMP", "TRILINEAR")
    arrow:SetSize(WAVE_ARROW_SIZE, WAVE_ARROW_SIZE)
    arrow:SetPoint("CENTER")

    local hovered = false
    local flashing = false
    local function PaintArrow()
        local color = WAVE_ARROW_IDLE
        if flashing then
            color = WAVE_ARROW_FLASH
        elseif hovered then
            color = WAVE_ARROW_HOVER
        end
        arrow:SetVertexColor(Widgets.UnpackColor(color))
    end
    PaintArrow()

    button:SetScript("OnEnter", function()
        hovered = true
        PaintArrow()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        PaintArrow()
    end)
    local flashGeneration = 0
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:HookScript("PostClick", function()
        flashGeneration = flashGeneration + 1
        local id = flashGeneration
        flashing = true
        PaintArrow()
        Timer.After(WAVE_FLASH_DURATION, function()
            if id ~= flashGeneration then
                return
            end
            flashing = false
            PaintArrow()
        end)
    end)
    return button
end

---Transparent secure hit target with a tinted dashed-circle texture. No box; color-only hover.
---@param canvas ArenaCanvas
---@param spec { x: number, y: number }
---@return Button
local function CreateBossButton(canvas, spec)
    local button = CreateFrame("Button", nil, canvas, Assets.Templates.SECURE_ACTION_BUTTON)
    button:SetSize(BOSS_HIT_SIZE, BOSS_HIT_SIZE)
    SnapToPixel(button)
    button:SetPoint("CENTER", canvas, "CENTER", math.floor(spec.x + 0.5), math.floor(spec.y + 0.5))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Assets.Textures.DASHED_CIRCLE_8_DOT, "CLAMP", "CLAMP", "TRILINEAR")
    icon:SetSize(BOSS_ICON_SIZE, BOSS_ICON_SIZE)
    icon:SetPoint("CENTER")

    local hovered = false
    local flashing = false
    local function PaintIcon()
        local color = BOSS_ICON_IDLE
        if flashing then
            color = BOSS_ICON_FLASH
        elseif hovered then
            color = BOSS_ICON_HOVER
        end
        icon:SetVertexColor(Widgets.UnpackColor(color))
    end
    PaintIcon()

    button:SetScript("OnEnter", function()
        hovered = true
        PaintIcon()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        PaintIcon()
    end)
    local flashGeneration = 0
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:HookScript("PostClick", function()
        flashGeneration = flashGeneration + 1
        local id = flashGeneration
        flashing = true
        PaintIcon()
        Timer.After(BOSS_FLASH_DURATION, function()
            if id ~= flashGeneration then
                return
            end
            flashing = false
            PaintIcon()
        end)
    end)
    return button
end

---@param canvas ArenaCanvas
---@param edge integer
---@return number x, number y
local function BossButtonOffset(canvas, edge)
    local mid = Ulatek:GetEdgeMidpoint(edge)
    local fromCenter = canvas.scale + BOSS_OUTSIDE_GAP + BOSS_HIT_SIZE / 2
    return mid.x * fromCenter, mid.y * fromCenter
end

---@param canvas ArenaCanvas
local function CreateCalloutButtons(canvas)
    local waveOffsetX = WAVE_BUTTON_WIDTH / 2 + WAVE_BUTTON_GAP / 2
    local leftX, leftY = BossButtonOffset(canvas, Ulatek.LEFT_EDGE)
    local rightX, rightY = BossButtonOffset(canvas, Ulatek.RIGHT_EDGE)

    canvas.calloutButtons = {
        [WAVE_LEFT] = CreateWaveButton(canvas, {
            pointingLeft = true,
            x = -waveOffsetX,
            y = 0,
        }),
        [WAVE_RIGHT] = CreateWaveButton(canvas, {
            pointingLeft = false,
            x = waveOffsetX,
            y = 0,
        }),
        [BOSS_LEFT] = CreateBossButton(canvas, {
            x = leftX,
            y = leftY,
        }),
        [BOSS_RIGHT] = CreateBossButton(canvas, {
            x = rightX,
            y = rightY,
        }),
    }
end

---@param options ArenaCanvasOptions
---@return ArenaCanvas
local function CreateArenaCanvas(parent, options)
    local canvas = CreateFrame("Frame", nil, parent) --[[@as ArenaCanvas]]
    canvas:SetSize(options.size, options.size)
    canvas.scale = options.size / 2
    canvas.placements = {}

    CreateCornerMarkers(canvas, options)
    if options.showCalloutButtons then
        CreateCalloutButtons(canvas)
    end
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
        width = options.size + 2 * math.max(
            CornerMarkerReach(CornerMarkerSize(options)),
            options.showCalloutButtons and (BOSS_OUTSIDE_GAP + BOSS_HIT_SIZE / 2 + Spacing.SMALL) or 0
        ),
        inset = 0,
    }
end

---Height of a row holding an arena, with room for the marker icons outside the top and bottom walls.
---@param size number
---@param markerSize number|nil
---@return number
function Map.GetArenaRowHeight(size, markerSize)
    return size + 2 * CornerMarkerReach(markerSize or CORNER_MARKER_SIZE)
end

function Map.RefreshCornerMarkers()
    for _, canvas in ipairs(canvases) do
        RefreshCornerMarkers(canvas)
    end
end
