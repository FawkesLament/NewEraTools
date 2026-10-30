local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local SoakTimeline = Internals.SoakTimeline
local Timer = ns.Api.Timer

local LAYOUT_ID = "TwinFangs:soakTimeline"
local WINDOW_WIDTH = 268
local WINDOW_HEIGHT = 40
local BAR_WIDTH = 220
local BAR_HEIGHT = 6
local NODE_SIZE = 22
local DIGIT_SIZE = 14
local GLOW_SIZE = 30
local PULSE_SPEED = 8

-- Cool ice-blue fills so the widget stays readable over the green venom arena.
local COLOR_FILL = { r = 125 / 255, g = 214 / 255, b = 1, a = 1 }
local COLOR_COMPLETED = { r = 0.86, g = 0.92, b = 0.98, a = 1 }
local COLOR_PENDING = { r = 0.28, g = 0.30, b = 0.34, a = 1 }
local COLOR_BAR_BG = { r = 0.16, g = 0.17, b = 0.20, a = 1 }
local COLOR_FLASH = { r = 0.95, g = 0.98, b = 1, a = 1 }
local COLOR_GLOW = { r = 0.55, g = 0.82, b = 1, a = 1 }
local COLOR_NODE_TEXT = { r = 0.95, g = 0.98, b = 1, a = 1 }
local COLOR_NODE_TEXT_PENDING = { r = 0.55, g = 0.58, b = 0.62, a = 1 }
local COLOR_NODE_TEXT_DONE = { r = 0.22, g = 0.32, b = 0.42, a = 1 }

local SoakTimelineUI = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.SoakTimelineUI = SoakTimelineUI

local window
local fill
---@type { glow: Texture, fill: Texture, label: FontString }[]
local nodes
local layoutRegistered = false
local layoutEditing = false
local previewElapsed = 0
---@type number|nil
local liveBeginAt
local scaleListening = false

local function PaintTexture(texture, color, alpha)
    texture:SetVertexColor(color.r, color.g, color.b, alpha or color.a or 1)
end

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---@param frame Frame
local function ApplyScale(frame)
    local scale = MainPanelScale()
    local oldScale = frame:GetScale() or 1
    if math.abs(oldScale - scale) < 0.001 then
        return
    end
    frame:SetScale(scale)
    ns.LayoutEditor.ApplyPosition(frame, TwinFangs:GetSoakTimelinePosition())
end

local function ListenForScale()
    if scaleListening then
        return
    end
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    scaleListening = true
    mainPanel.OnScaleChanged(function(scale)
        if not window then
            return
        end
        window:SetScale(scale)
        ns.LayoutEditor.ApplyPosition(window, TwinFangs:GetSoakTimelinePosition())
    end)
end

---@param parent Frame
---@param size number
---@param drawLayer string
---@return Frame, Texture
local function CreateCircle(parent, size, drawLayer)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame:EnableMouse(false)
    local texture = frame:CreateTexture(nil, drawLayer)
    texture:SetAllPoints()
    texture:SetTexture(Assets.Textures.WHITE)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture(Assets.Textures.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
    return frame, texture
end

---@param state TwinFangsSoakTimelineState
local function ApplyState(state)
    if not window or not fill or not nodes then
        return
    end
    local fillWidth = state.progress * BAR_WIDTH
    if fillWidth <= 0 then
        fill:Hide()
    else
        fill:SetWidth(math.max(fillWidth, 1))
        fill:Show()
    end

    local pulseClock = liveBeginAt and (Timer.GetTime() - liveBeginAt) or previewElapsed
    local pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(pulseClock * PULSE_SPEED))
    for index = 1, SoakTimeline.HIT_COUNT do
        local node = nodes[index]
        local nodeState = state.nodes[index]
        node.label:SetText(tostring(index))
        if nodeState.flashing then
            PaintTexture(node.fill, COLOR_FLASH)
            PaintTexture(node.glow, COLOR_GLOW, 0.9)
            node.label:SetTextColor(Widgets.UnpackColor(COLOR_NODE_TEXT_DONE))
        elseif nodeState.status == "completed" then
            -- Keep the digit; a checkmark glyph is missing from the overlay font and draws as a box.
            PaintTexture(node.fill, COLOR_COMPLETED)
            PaintTexture(node.glow, COLOR_GLOW, 0)
            node.label:SetTextColor(Widgets.UnpackColor(COLOR_NODE_TEXT_DONE))
        elseif nodeState.status == "active" then
            PaintTexture(node.fill, COLOR_FILL)
            PaintTexture(node.glow, COLOR_GLOW, pulse)
            node.label:SetTextColor(Widgets.UnpackColor(COLOR_NODE_TEXT))
        else
            PaintTexture(node.fill, COLOR_PENDING)
            PaintTexture(node.glow, COLOR_GLOW, 0)
            node.label:SetTextColor(Widgets.UnpackColor(COLOR_NODE_TEXT_PENDING))
        end
    end
end

local function HideWindow()
    previewElapsed = 0
    if window then
        window:SetScript("OnUpdate", nil)
        window:Hide()
    end
end

local function TickLive()
    if not liveBeginAt then
        HideWindow()
        return
    end
    local elapsed = Timer.GetTime() - liveBeginAt
    if elapsed >= SoakTimeline.DURATION then
        liveBeginAt = nil
        HideWindow()
        return
    end
    ApplyState(SoakTimeline.SequenceState(elapsed))
end

local function ShowLive()
    if not window then
        return
    end
    ApplyScale(window)
    window:Show()
    window:Raise()
    window:SetScript("OnUpdate", function()
        TickLive()
    end)
    TickLive()
end

local function StartPreview()
    previewElapsed = 0
    ApplyState(SoakTimeline.StateAt(0))
    window:Show()
    window:Raise()
    window:SetScript("OnUpdate", function(_, elapsed)
        previewElapsed = previewElapsed + elapsed
        ApplyState(SoakTimeline.StateAt(previewElapsed))
    end)
end

local function Register(frame)
    if layoutRegistered then
        return
    end
    layoutRegistered = true
    ns.LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.TWIN_FANGS_SOAK_TIMELINE,
        frame = frame,
        global = false,
        isEnabled = function()
            return TwinFangs:IsSoakReminderEnabled() and TwinFangs:IsSoakTimelineEnabled()
        end,
        getPosition = function()
            return TwinFangs:GetSoakTimelinePosition()
        end,
        setPosition = function(position)
            TwinFangs:SetSoakTimelinePosition(position)
        end,
        getDefaultPosition = function()
            return Schema.DefaultSoakTimelinePosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            SoakTimelineUI.Ensure()
            StartPreview()
        end,
        onEditEnd = function()
            layoutEditing = false
            SoakTimelineUI.Update()
        end,
    })
end

local function CreateWindow()
    local frame = Widgets.CreateSurface(
        UIParent,
        Colors.BG_TRANSLUCENT,
        Colors.BORDER_SUBTLE,
        ns.ADDON_NAME .. "TwinFangsSoakTimeline"
    )
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetScale(MainPanelScale())
    ns.LayoutEditor.ApplyPosition(frame, TwinFangs:GetSoakTimelinePosition())
    frame:Hide()

    local bar = frame:CreateTexture(nil, "BACKGROUND")
    bar:SetTexture(Assets.Textures.WHITE)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar:SetPoint("CENTER", frame, "CENTER", 0, 0)
    PaintTexture(bar, COLOR_BAR_BG)

    fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(Assets.Textures.WHITE)
    fill:SetHeight(BAR_HEIGHT)
    fill:SetPoint("LEFT", bar, "LEFT")
    PaintTexture(fill, COLOR_FILL)
    fill:Hide()

    nodes = {}
    for index = 1, SoakTimeline.HIT_COUNT do
        local glowFrame, glow = CreateCircle(frame, GLOW_SIZE, "BACKGROUND")
        glowFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
        local nodeFrame, nodeFill = CreateCircle(frame, NODE_SIZE, "ARTWORK")
        nodeFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
        local x = SoakTimeline.HitFraction(index) * BAR_WIDTH
        glowFrame:SetPoint("CENTER", bar, "LEFT", x, 0)
        nodeFrame:SetPoint("CENTER", bar, "LEFT", x, 0)
        local digitStyle = Assets.FontStyles[Fonts.OVERLAY_DIGIT]
        local label = Widgets.CreateLabel(nodeFrame, Fonts.OVERLAY_DIGIT, tostring(index))
        label:SetFont(digitStyle.path or STANDARD_TEXT_FONT, DIGIT_SIZE, digitStyle.flags or "OUTLINE")
        label:SetJustifyH("CENTER")
        label:SetPoint("CENTER")
        nodes[index] = { glow = glow, fill = nodeFill, label = label }
    end

    ListenForScale()
    Register(frame)
    return frame
end

function SoakTimelineUI.Ensure()
    window = window or CreateWindow()
    ApplyScale(window)
    return window
end

function SoakTimelineUI.Update()
    if layoutEditing then
        return
    end
    if liveBeginAt then
        ShowLive()
        return
    end
    HideWindow()
end

---@param beginAt number
function TwinFangs:StartSoakTimeline(beginAt)
    liveBeginAt = beginAt
    if layoutEditing then
        return
    end
    if not TwinFangs:IsSoakReminderEnabled() or not TwinFangs:IsSoakTimelineEnabled() then
        liveBeginAt = nil
        HideWindow()
        return
    end
    SoakTimelineUI.Ensure()
    ShowLive()
end

function TwinFangs:StopSoakTimeline()
    liveBeginAt = nil
    if layoutEditing then
        return
    end
    HideWindow()
end
