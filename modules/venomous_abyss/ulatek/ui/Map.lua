-- Octagon arena canvas for Ulatek: walls, entrance, corner markers, and combat-safe callout buttons.
local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
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
-- Clicked icon scale; the secure hit box stays the same size.
local CALLOUT_SELECTED_SCALE = 1.3
local CALLOUT_DIMMED_ALPHA = 0.35
-- Gap from the octagon's vertical edge to the near side of the hit box.
local BOSS_OUTSIDE_GAP = 11
local BOSS_FLASH_DURATION = 0.2
-- Test-mode clock in the pad's bottom-left; hidden during a live pull.
local TEST_CLOCK_INSET = Spacing.SMALL
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
local GROUP_WAVE = Internals.Timeline.PAD_WAVE
local GROUP_BOSS = Internals.Timeline.PAD_BOSS
local GROUP_MARKERS = Internals.Timeline.PAD_MARKERS
local GROUP_BUTTON_IDS = {
    [GROUP_WAVE] = { WAVE_LEFT, WAVE_RIGHT },
    [GROUP_BOSS] = { BOSS_LEFT, BOSS_RIGHT },
    [GROUP_MARKERS] = { 4, 5, 7 },
}
-- Named macros stay in sync via EditMacro; the button only needs the stable name.
local CALLOUT_MACRO_INDEX = {
    [WAVE_LEFT] = 1,
    [WAVE_RIGHT] = 2,
    [BOSS_LEFT] = 1,
    [BOSS_RIGHT] = 2,
}
local MARKER_MACRO_INDEX = {
    [4] = 1,
    [5] = 2,
    [7] = 3,
}
local GROUP_HINTS = {
    [GROUP_WAVE] = L.ULATEK_PAD_HINT_WAVE,
    [GROUP_BOSS] = L.ULATEK_PAD_HINT_BOSS,
    [GROUP_MARKERS] = L.ULATEK_PAD_HINT_MARKERS,
}
-- Pad world-markers stay hidden; corners 4, 5, and 7 fade in for [325s, 340s].
local MARKER_CLICK_CORNERS = {
    [4] = true,
    [5] = true,
    [7] = true,
}
-- Clickable frame around each marker; larger than the icon so markers are easy to hit.
local CORNER_MARKER_HIT_SIZE = 56
-- Gap from a vertex inward to the near side of its marker icon.
local CORNER_MARKER_GAP = Spacing.MEDIUM
-- Entrance caption sits just outside the bottom wall.
local ENTRANCE_LABEL_REACH = Spacing.MEDIUM + Assets.FontStyles[Fonts.BODY].size

---@param markerSize number
---@return number
local function MarkerInset(markerSize)
    return CORNER_MARKER_GAP + markerSize / 2
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
---@field markerStates table<integer, UlatekCalloutButtonState>|nil
---@field calloutButtons table<string, Button>|nil
---@field calloutStates table<string, UlatekCalloutButtonState>|nil
---@field testClock FontString|nil
---@field windowHint FontString|nil

---@class ArenaRow
---@field row Frame
---@field canvas ArenaCanvas
---@field entranceLabel FontString  Sits outside the entrance gate.
---@field width number  Octagon plus room for corner icons on either side.
---@field inset number  Gap from the row's left side to the octagon's reserved box.

local canvases = {}

---@class UlatekPadGroupState
---@field active boolean
---@field locked boolean
---@field selected string|nil

---@class UlatekCalloutButtonState
---@field id string
---@field group UlatekPadGroupId
---@field button Button
---@field icon Texture
---@field lockMask Frame
---@field defaultSize number
---@field idleColor table
---@field hoverColor table
---@field flashColor table
---@field hovered boolean
---@field flashing boolean
---@field flashGeneration number
---@field flashDuration number

---@type table<UlatekPadGroupId, UlatekPadGroupState>
local groupStates = {
    [GROUP_WAVE] = { active = false, locked = true, selected = nil },
    [GROUP_BOSS] = { active = false, locked = true, selected = nil },
    [GROUP_MARKERS] = { active = false, locked = true, selected = nil },
}

local Map = {
    MARKER_NAMES = MARKER_NAMES,
    GROUP_WAVE = GROUP_WAVE,
    GROUP_BOSS = GROUP_BOSS,
    GROUP_MARKERS = GROUP_MARKERS,
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

---@param region Region
local function SnapToPixel(region)
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(true)
        region:SetTexelSnappingBias(0)
    end
end

---@param button Button
---@param macroName string|nil
local function ApplyMacroAttribute(button, macroName)
    if macroName then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", macroName)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macro", nil)
    end
end

---Unprotected cover above a secure callout. Showing it swallows clicks and stays legal in lockdown.
---@param button Button
---@return Frame
local function CreateCalloutLockMask(button)
    local mask = CreateFrame("Frame", nil, button)
    mask:SetAllPoints()
    mask:EnableMouse(true)
    if button.GetFrameLevel and mask.SetFrameLevel then
        mask:SetFrameLevel(button:GetFrameLevel() + 5)
    end
    mask:Show()
    return mask
end

---@param state UlatekCalloutButtonState
local function PaintMarker(state)
    local group = groupStates[GROUP_MARKERS]
    local selected = group.selected == state.id
    local dimmed = group.active and group.locked and group.selected ~= nil and not selected
    local size = selected and (state.defaultSize * CALLOUT_SELECTED_SCALE) or state.defaultSize
    state.icon:SetSize(size, size)
    local alpha = 0
    if group.active then
        alpha = dimmed and CALLOUT_DIMMED_ALPHA or 1
    end
    state.icon:SetAlpha(alpha)
    state.lockMask:SetShown(not group.active or group.locked)
end

local function PaintMarkerGroup()
    for _, canvas in ipairs(canvases) do
        local states = canvas.markerStates
        if states then
            for _, corner in ipairs(GROUP_BUTTON_IDS[GROUP_MARKERS]) do
                if states[corner] then
                    PaintMarker(states[corner])
                end
            end
        end
    end
end

---@param canvas ArenaCanvas
---@param corner integer
---@param options ArenaCanvasOptions
---@param x number
---@param y number
local function CreatePadMarkerButton(canvas, corner, options, x, y)
    local button = CreateFrame("Button", nil, canvas, Assets.Templates.SECURE_ACTION_BUTTON)
    button:SetSize(CORNER_MARKER_HIT_SIZE, CORNER_MARKER_HIT_SIZE)
    SnapToPixel(button)
    button:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, x, y))

    local icon = button:CreateTexture(nil, "ARTWORK")
    local markerSize = CornerMarkerSize(options)
    icon:SetSize(markerSize, markerSize)
    icon:SetPoint("CENTER")

    local lockMask = CreateCalloutLockMask(button)
    ---@type UlatekCalloutButtonState
    local state = {
        id = corner,
        group = GROUP_MARKERS,
        button = button,
        icon = icon,
        lockMask = lockMask,
        defaultSize = markerSize,
        idleColor = WAVE_ARROW_IDLE,
        hoverColor = WAVE_ARROW_HOVER,
        flashColor = WAVE_ARROW_FLASH,
        hovered = false,
        flashing = false,
        flashGeneration = 0,
        flashDuration = WAVE_FLASH_DURATION,
    }
    canvas.markerStates[corner] = state
    canvas.cornerButtons[corner] = button
    button.calloutIcon = icon
    button.lockMask = lockMask
    button:RegisterForClicks("AnyDown", "AnyUp")
    ApplyMacroAttribute(button, Ulatek:GetSignalMacroName(MARKER_MACRO_INDEX[corner]))
    button:HookScript("PostClick", function()
        local group = groupStates[GROUP_MARKERS]
        if not group.active or group.locked then
            return
        end
        group.selected = corner
        group.locked = true
        PaintMarkerGroup()
    end)
    PaintMarker(state)
    return button, icon
end

---@param options ArenaCanvasOptions
local function CreateCornerMarkers(canvas, options)
    local circumradius = 1 / math.cos(math.pi / Ulatek.ARENA_SIDES)
    local markerSize = CornerMarkerSize(options)
    local distance = circumradius - MarkerInset(markerSize) / canvas.scale
    canvas.cornerIcons = {}
    canvas.cornerButtons = {}
    local clickable = options.onCornerMarkerClick ~= nil
    local padMarkers = options.showCalloutButtons == true
    if padMarkers then
        canvas.markerStates = {}
    end
    for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
        local unit = circumradius
        local x, y = cornerMarker.x / unit * distance, cornerMarker.y / unit * distance
        local region, icon
        if clickable then
            region, icon = CreateCornerMarkerButton(canvas, cornerMarker.corner, options)
            canvas.cornerButtons[cornerMarker.corner] = region
        elseif padMarkers and MARKER_CLICK_CORNERS[cornerMarker.corner] then
            region, icon = CreatePadMarkerButton(canvas, cornerMarker.corner, options, x, y)
        else
            icon = canvas:CreateTexture(nil, "OVERLAY")
            icon:SetSize(markerSize, markerSize)
            region = icon
        end
        icon:SetTexture(Assets.WORLD_MARKER_ICONS[cornerMarker.marker])
        canvas.cornerIcons[cornerMarker.corner] = icon
        if padMarkers and not MARKER_CLICK_CORNERS[cornerMarker.corner] then
            icon:SetAlpha(0)
        end
        if not (region.IsProtected and region:IsProtected()) then
            AddPlacement(canvas, function()
                region:SetPoint("CENTER", canvas, "CENTER", ToCanvas(canvas, x, y))
            end)
        end
    end
end

local function RefreshCornerMarkers(canvas)
    for _, cornerMarker in ipairs(Ulatek:GetCornerMarkers()) do
        local icon = canvas.cornerIcons[cornerMarker.corner]
        icon:SetTexture(Assets.WORLD_MARKER_ICONS[cornerMarker.marker])
        if canvas.markerStates then
            local state = canvas.markerStates[cornerMarker.corner]
            if state then
                PaintMarker(state)
            else
                icon:SetAlpha(0)
            end
        end
    end
end

---@param state UlatekCalloutButtonState
local function PaintCallout(state)
    local group = groupStates[state.group]
    local selected = group.selected == state.id
    local dimmed = group.active and group.locked and group.selected ~= nil and not selected
    local size = selected and (state.defaultSize * CALLOUT_SELECTED_SCALE) or state.defaultSize
    state.icon:SetSize(size, size)

    local color = state.idleColor
    if state.flashing then
        color = state.flashColor
    elseif selected then
        color = state.hoverColor
    elseif state.hovered and group.active and not group.locked then
        color = state.hoverColor
    end
    state.icon:SetVertexColor(Widgets.UnpackColor(color))

    local alpha = 0
    if group.active then
        alpha = dimmed and CALLOUT_DIMMED_ALPHA or 1
    end
    state.icon:SetAlpha(alpha)
    state.lockMask:SetShown(not group.active or group.locked)
end

local function PaintCalloutGroup(group)
    for _, canvas in ipairs(canvases) do
        local states = canvas.calloutStates
        if states then
            for _, id in ipairs(GROUP_BUTTON_IDS[group]) do
                if states[id] then
                    PaintCallout(states[id])
                end
            end
        end
    end
end

local function ActiveWindowHintText()
    for _, group in ipairs({ GROUP_WAVE, GROUP_BOSS, GROUP_MARKERS }) do
        if groupStates[group].active then
            return GROUP_HINTS[group]
        end
    end
    return nil
end

---Combat-safe: SetText / SetAlpha only.
local function PaintWindowHint()
    local text = ActiveWindowHintText()
    local alpha = text and 1 or 0
    for _, canvas in ipairs(canvases) do
        local hint = canvas.windowHint
        if hint then
            hint:SetText(text or "")
            hint:SetAlpha(alpha)
        end
    end
end

---@param group UlatekPadGroupId
---@param active boolean
function Map.SetCalloutGroupActive(group, active)
    local state = groupStates[group]
    if not state then
        return
    end
    if active then
        state.active = true
        state.locked = false
        state.selected = nil
    else
        state.active = false
        state.locked = true
        state.selected = nil
    end
    for _, canvas in ipairs(canvases) do
        local states = canvas.calloutStates
        if states then
            for _, id in ipairs(GROUP_BUTTON_IDS[group]) do
                local buttonState = states[id]
                if buttonState then
                    buttonState.hovered = false
                    buttonState.flashing = false
                    buttonState.flashGeneration = buttonState.flashGeneration + 1
                end
            end
        end
    end
    if group == GROUP_MARKERS then
        PaintMarkerGroup()
    else
        PaintCalloutGroup(group)
    end
    PaintWindowHint()
end

function Map.ResetCalloutGroups()
    Map.SetCalloutGroupActive(GROUP_WAVE, false)
    Map.SetCalloutGroupActive(GROUP_BOSS, false)
    Map.SetCalloutGroupActive(GROUP_MARKERS, false)
end

---@param seconds number
---@return string
local function FormatTimelineTime(seconds)
    seconds = math.floor(seconds + 1e-6)
    if seconds < 0 then
        seconds = 0
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---Combat-safe: only SetText / SetAlpha on the test clock, never the secure buttons.
---@param elapsed number
---@param duration number
---@param visible boolean
function Map.SetTestTimer(elapsed, duration, visible)
    if elapsed < 0 then
        elapsed = 0
    elseif duration and elapsed > duration then
        elapsed = duration
    end
    local text = FormatTimelineTime(elapsed)
    local alpha = visible and 1 or 0
    for _, canvas in ipairs(canvases) do
        local clock = canvas.testClock
        if clock then
            clock:SetText(text)
            clock:SetAlpha(alpha)
        end
    end
end

---@param parent Frame
---@param canvas ArenaCanvas
local function CreateTestClock(parent, canvas)
    local clock = Widgets.CreateLabel(parent, Fonts.BODY)
    clock:SetJustifyH("LEFT")
    clock:SetWordWrap(false)
    clock:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", TEST_CLOCK_INSET, TEST_CLOCK_INSET)
    clock:SetAlpha(0)
    canvas.testClock = clock
end

---Centered instruction on the floating pad header. Combat-safe after create: SetText / SetAlpha only.
---@param parent Frame
---@param canvas ArenaCanvas
function Map.AttachWindowHint(parent, canvas)
    local hint = Widgets.CreateLabel(parent, Fonts.EMPHASIS)
    hint:SetJustifyH("CENTER")
    hint:SetWordWrap(false)
    hint:SetPoint("CENTER", parent, "CENTER")
    hint:SetAlpha(0)
    canvas.windowHint = hint
end

Internals.BindPadTestUi({
    OnTick = function(elapsed, duration)
        Map.SetTestTimer(elapsed, duration, true)
    end,
    OnFinished = function()
        Ulatek:EndPadTest()
    end,
    OnEnded = function()
        Map.SetTestTimer(0, Internals.Timeline.PAD_TEST_DURATION, false)
    end,
})

Internals.BindPadCallouts({
    SetCalloutGroupActive = Map.SetCalloutGroupActive,
    ResetCalloutGroups = Map.ResetCalloutGroups,
})

---@param canvas ArenaCanvas
---@param spec {
---    id: string,
---    group: UlatekPadGroupId,
---    width: number,
---    height: number,
---    x: number,
---    y: number,
---    texture: string,
---    iconSize: number,
---    idleColor: table,
---    hoverColor: table,
---    flashColor: table,
---    flashDuration: number,
---}
---@return Button
local function CreateCalloutButton(canvas, spec)
    local button = CreateFrame("Button", nil, canvas, Assets.Templates.SECURE_ACTION_BUTTON)
    button:SetSize(spec.width, spec.height)
    SnapToPixel(button)
    button:SetPoint("CENTER", canvas, "CENTER", math.floor(spec.x + 0.5), math.floor(spec.y + 0.5))

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(spec.texture, "CLAMP", "CLAMP", "TRILINEAR")
    icon:SetSize(spec.iconSize, spec.iconSize)
    icon:SetPoint("CENTER")

    local lockMask = CreateCalloutLockMask(button)
    ---@type UlatekCalloutButtonState
    local state = {
        id = spec.id,
        group = spec.group,
        button = button,
        icon = icon,
        lockMask = lockMask,
        defaultSize = spec.iconSize,
        idleColor = spec.idleColor,
        hoverColor = spec.hoverColor,
        flashColor = spec.flashColor,
        hovered = false,
        flashing = false,
        flashGeneration = 0,
        flashDuration = spec.flashDuration,
    }
    canvas.calloutStates[spec.id] = state
    button.calloutIcon = icon
    button.lockMask = lockMask

    button:SetScript("OnEnter", function()
        state.hovered = true
        PaintCallout(state)
    end)
    button:SetScript("OnLeave", function()
        state.hovered = false
        PaintCallout(state)
    end)
    button:RegisterForClicks("AnyDown", "AnyUp")
    ApplyMacroAttribute(button, Ulatek:GetSignalMacroName(CALLOUT_MACRO_INDEX[spec.id]))
    button:HookScript("PostClick", function()
        local group = groupStates[state.group]
        if not group.active or group.locked then
            return
        end
        group.selected = state.id
        group.locked = true
        state.flashGeneration = state.flashGeneration + 1
        local flashId = state.flashGeneration
        state.flashing = true
        PaintCalloutGroup(state.group)
        Timer.After(state.flashDuration, function()
            if flashId ~= state.flashGeneration then
                return
            end
            state.flashing = false
            PaintCallout(state)
        end)
    end)
    PaintCallout(state)
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

    canvas.calloutStates = {}
    canvas.calloutButtons = {
        [WAVE_LEFT] = CreateCalloutButton(canvas, {
            id = WAVE_LEFT,
            group = GROUP_WAVE,
            width = WAVE_BUTTON_WIDTH,
            height = WAVE_BUTTON_HEIGHT,
            x = -waveOffsetX,
            y = 0,
            texture = Assets.Textures.ARROW_DOUBLE_CHEVRON_LEFT,
            iconSize = WAVE_ARROW_SIZE,
            idleColor = WAVE_ARROW_IDLE,
            hoverColor = WAVE_ARROW_HOVER,
            flashColor = WAVE_ARROW_FLASH,
            flashDuration = WAVE_FLASH_DURATION,
        }),
        [WAVE_RIGHT] = CreateCalloutButton(canvas, {
            id = WAVE_RIGHT,
            group = GROUP_WAVE,
            width = WAVE_BUTTON_WIDTH,
            height = WAVE_BUTTON_HEIGHT,
            x = waveOffsetX,
            y = 0,
            texture = Assets.Textures.ARROW_DOUBLE_CHEVRON_RIGHT,
            iconSize = WAVE_ARROW_SIZE,
            idleColor = WAVE_ARROW_IDLE,
            hoverColor = WAVE_ARROW_HOVER,
            flashColor = WAVE_ARROW_FLASH,
            flashDuration = WAVE_FLASH_DURATION,
        }),
        [BOSS_LEFT] = CreateCalloutButton(canvas, {
            id = BOSS_LEFT,
            group = GROUP_BOSS,
            width = BOSS_HIT_SIZE,
            height = BOSS_HIT_SIZE,
            x = leftX,
            y = leftY,
            texture = Assets.Textures.DASHED_CIRCLE_8_DOT,
            iconSize = BOSS_ICON_SIZE,
            idleColor = BOSS_ICON_IDLE,
            hoverColor = BOSS_ICON_HOVER,
            flashColor = BOSS_ICON_FLASH,
            flashDuration = BOSS_FLASH_DURATION,
        }),
        [BOSS_RIGHT] = CreateCalloutButton(canvas, {
            id = BOSS_RIGHT,
            group = GROUP_BOSS,
            width = BOSS_HIT_SIZE,
            height = BOSS_HIT_SIZE,
            x = rightX,
            y = rightY,
            texture = Assets.Textures.DASHED_CIRCLE_8_DOT,
            iconSize = BOSS_ICON_SIZE,
            idleColor = BOSS_ICON_IDLE,
            hoverColor = BOSS_ICON_HOVER,
            flashColor = BOSS_ICON_FLASH,
            flashDuration = BOSS_FLASH_DURATION,
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
    -- Extra row height is for the entrance label below the octagon, not empty space above it.
    canvas:SetPoint("LEFT", arena.row, "LEFT", left, ENTRANCE_LABEL_REACH / 2)
end

---Fills `row` with the octagon. Call LayoutArenaRow once `inset` is final.
---@param row Frame
---@param options ArenaCanvasOptions
---@return ArenaRow
function Map.CreateArenaRow(row, options)
    local canvas = CreateArenaCanvas(row, options)
    if options.showCalloutButtons then
        CreateTestClock(row, canvas)
    end
    local entranceLabel = CreateEntranceLabel(canvas)
    AddPlacement(canvas, function()
        PlaceEntranceLabel(canvas, entranceLabel)
    end)

    return {
        row = row,
        canvas = canvas,
        entranceLabel = entranceLabel,
        width = options.size
            + 2 * (options.showCalloutButtons and (BOSS_OUTSIDE_GAP + BOSS_HIT_SIZE / 2 + Spacing.SMALL) or 0),
        inset = 0,
    }
end

---Height of a row holding an arena, with room for the entrance label outside the bottom wall.
---@param size number
---@return number
function Map.GetArenaRowHeight(size)
    return size + ENTRANCE_LABEL_REACH
end

function Map.RefreshCornerMarkers()
    for _, canvas in ipairs(canvases) do
        RefreshCornerMarkers(canvas)
    end
end

---Binds or clears SecureActionButton macros on pad callouts and soak markers.
---Editor markers (plain buttons) are left alone. Blocked during combat lockdown.
---@param enabled boolean
---@return boolean applied
function Map.SetCalloutMacroClicksEnabled(enabled)
    if Combat.IsLockedDown() then
        return false
    end
    for _, canvas in ipairs(canvases) do
        for id, button in pairs(canvas.calloutButtons or {}) do
            if button.IsProtected and button:IsProtected() then
                local index = CALLOUT_MACRO_INDEX[id]
                ApplyMacroAttribute(button, enabled and Ulatek:GetSignalMacroName(index) or nil)
            end
        end
        for corner, button in pairs(canvas.cornerButtons or {}) do
            local index = MARKER_MACRO_INDEX[corner]
            if index and button.IsProtected and button:IsProtected() then
                ApplyMacroAttribute(button, enabled and Ulatek:GetSignalMacroName(index) or nil)
            end
        end
    end
    return true
end
