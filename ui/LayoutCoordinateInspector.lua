local _, ns = ...
local L = ns.L
local Util = ns.Util
local Assets = ns.Assets
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local LayoutCoordinateInspector = {}
ns.LayoutCoordinateInspector = LayoutCoordinateInspector

local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 260, y = 40 }
local INSPECTOR_STRATA = "TOOLTIP"

---@type FloatingWindow|nil
local window = nil
---@type FontString|nil
local titleLabel = nil
---@type NumberStepper|nil
local xStepper = nil
---@type NumberStepper|nil
local yStepper = nil
---@type LayoutElementDef|nil
local selectedDef = nil
local scaleListening = false

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

local function SyncScale()
    if window then
        window:SetWindowScale(MainPanelScale())
    end
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
        if window then
            window:SetWindowScale(scale)
        end
    end)
end

---@return LayoutPosition
local function GetSavedPosition()
    local mainPanel = ns.MainPanel
    local saved = mainPanel and mainPanel.db and mainPanel.db.layoutInspectorPosition
    if FloatingWindow.IsValidPosition(saved) then
        return {
            point = saved.point,
            relativePoint = saved.relativePoint,
            x = saved.x,
            y = saved.y,
        }
    end
    return Util.DeepCopy(DEFAULT_POSITION)
end

---@param position LayoutPosition
local function SavePosition(position)
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.db then
        return
    end
    local saved = mainPanel.db.layoutInspectorPosition
    if type(saved) ~= "table" then
        saved = {}
        mainPanel.db.layoutInspectorPosition = saved
    end
    saved.point = position.point
    saved.relativePoint = position.relativePoint
    saved.x = position.x
    saved.y = position.y
end

---Saved/displayed offsets in CENTER/CENTER space (same as drag normalization).
---@return LayoutPosition
local function CenterPosition()
    local position = selectedDef.getPosition()
    if position.point == "CENTER" and position.relativePoint == "CENTER" then
        return {
            point = "CENTER",
            relativePoint = "CENTER",
            x = position.x,
            y = position.y,
        }
    end
    local normalized = FloatingWindow.NormalizePosition(selectedDef.frame)
    selectedDef.setPosition(normalized)
    return normalized
end

---Applies an axis offset, then clamps the element so it stays on screen.
---@param axis "x"|"y"
---@param value number
local function ApplyAxis(axis, value)
    if not selectedDef then
        return
    end
    local next = CenterPosition()
    next[axis] = value
    selectedDef.setPosition(FloatingWindow.ClampToScreen(selectedDef.frame, next))
end

---@param parent Frame
---@param axisLabel string
---@param axis "x"|"y"
---@return NumberStepper
local function CreateAxisRow(parent, axisLabel, axis)
    local label = Widgets.CreateLabel(parent, Fonts.SMALL_MUTED, axisLabel)
    label:SetPoint("LEFT")
    label:SetWidth(88)
    label:SetJustifyH("LEFT")

    -- Five signed digits, matching the previous inspector box. Screen clamp happens in ApplyAxis.
    local maxOffset = 10 ^ Sizes.LAYOUT_INSPECTOR_OFFSET_DIGITS - 1
    local stepper = Widgets.CreateNumberStepper(parent, -maxOffset, maxOffset, 1, function(value)
        ApplyAxis(axis, value)
        LayoutCoordinateInspector.RefreshCoordinates()
    end)
    stepper:SetPoint("LEFT", label, "RIGHT", Spacing.SMALL, 0)
    return stepper
end

local function EnsureWindow()
    if window then
        return window
    end

    window = FloatingWindow.Create({
        name = ns.ADDON_NAME .. "LayoutCoordinateInspector",
        fill = Colors.BG,
        scale = MainPanelScale(),
        position = GetSavedPosition(),
        closable = true,
        onClose = function()
            -- Deselect through LayoutEditor so the overlay highlight clears with the window.
            if ns.LayoutEditor and ns.LayoutEditor.Deselect then
                ns.LayoutEditor.Deselect()
            else
                LayoutCoordinateInspector.Hide()
            end
        end,
        onPositionChanged = function(position)
            SavePosition(position)
        end,
    })
    window:SetFrameStrata(INSPECTOR_STRATA)
    window:SetToplevel(true)
    ListenForScale()

    titleLabel = Widgets.CreateLabel(window.header, Fonts.BODY)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetWordWrap(false)
    titleLabel:SetPoint("LEFT", Spacing.SMALL, 0)
    if window.closeButton then
        titleLabel:SetPoint("RIGHT", window.closeButton, "LEFT", -Spacing.SMALL, 0)
    else
        titleLabel:SetPoint("RIGHT", -Spacing.SMALL, 0)
    end

    local body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", Sizes.BORDER, -(Sizes.CLOSE_BUTTON + Spacing.SMALL))
    body:SetPoint("BOTTOMRIGHT", -Sizes.BORDER, Sizes.BORDER)

    local stack = Layout.Stack(body, {
        paddingX = Spacing.MEDIUM,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local xRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    xStepper = CreateAxisRow(xRow, L.LAYOUT_INSPECTOR_X, "x")

    local yRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    yStepper = CreateAxisRow(yRow, L.LAYOUT_INSPECTOR_Y, "y")

    local resetRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.MEDIUM)
    local resetButton = Widgets.CreateButton(resetRow, L.LAYOUT_INSPECTOR_RESET, function()
        if not selectedDef then
            return
        end
        local defaultPosition = selectedDef.getDefaultPosition()
        selectedDef.setPosition(FloatingWindow.ClampToScreen(selectedDef.frame, {
            point = "CENTER",
            relativePoint = "CENTER",
            x = defaultPosition.x or 0,
            y = defaultPosition.y or 0,
        }))
        LayoutCoordinateInspector.RefreshCoordinates()
    end)
    resetButton:SetPoint("LEFT")
    resetButton:SetPoint("RIGHT")

    window:SetSize(
        Sizes.LAYOUT_INSPECTOR_WIDTH,
        Sizes.CLOSE_BUTTON + stack:GetHeight() + Spacing.SMALL + 2 * Sizes.BORDER
    )
    return window
end

function LayoutCoordinateInspector.RefreshCoordinates()
    if not selectedDef or not xStepper or not yStepper then
        return
    end
    local position = CenterPosition()
    xStepper:SetValue(position.x)
    yStepper:SetValue(position.y)
end

---@param def LayoutElementDef
function LayoutCoordinateInspector.Show(def)
    selectedDef = def
    local win = EnsureWindow()
    if titleLabel then
        titleLabel:SetText(def.label)
    end
    SyncScale()
    LayoutCoordinateInspector.RefreshCoordinates()
    win:SetWindowPosition(GetSavedPosition())
    win:Show()
    win:Raise()
end

function LayoutCoordinateInspector.Hide()
    selectedDef = nil
    if window then
        window:Hide()
    end
end

---@return boolean
function LayoutCoordinateInspector.IsShown()
    return window ~= nil and window:IsShown()
end

---@return string|nil
function LayoutCoordinateInspector.GetSelectedId()
    return selectedDef and selectedDef.id or nil
end

function LayoutCoordinateInspector.Raise()
    if window and window:IsShown() then
        window:Raise()
    end
end
