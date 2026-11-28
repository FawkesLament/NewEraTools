-- Floating arena map for Ulatek's tactical pad: tomb auto-show, preview, and layout editing.
local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local FloatingWindow = ns.FloatingWindow
local Instance = ns.Api.Instance
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor

local Spacing = Assets.Spacing
local Sizes = Assets.Sizes

local Ulatek = ns.Modules.Get("Ulatek")
local Map = Internals.Map

-- Distance between opposite edges of the drawn octagon in the floating map.
local ARENA_SIZE = 220
-- Slightly larger than the settings-panel editor icons.
local MARKER_SIZE = 24
-- Factory default: 80% of the max on-screen CENTER X (right of center); Y stays centered.
local DEFAULT_PAD_X_RATIO = 0.8

local LAYOUT_ID = "Ulatek:tacticalPad"

local Window = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.Window = Window

local window
local windowCloseButton
local padLayoutRegistered = false
local layoutEditCount = 0
-- Session-only: temporary pad outside a live encounter display.
local previewVisible = false
-- True when Show/Hide was skipped because secure callout buttons cannot change during lockdown.
local visibilityDirty = false
-- True when role-driven macro click binding couldn't apply during combat lockdown.
local macroClicksDirty = false

-- Venomous Abyss. GetInstanceInfo instanceID.
local TOMB_INSTANCE_ID = 3004
-- Exact GetSubZoneText values for Ulatek's room (enUS / zhCN).
local TOMB_SUBZONES = {
    ["The Tomb of Ula'tek"] = true,
    ["乌拉特克之墓"] = true,
}

local function CanChangeVisibility()
    return not Combat.IsLockedDown()
end

---@param frame Frame|nil
local function CanConfigure(frame)
    return not Combat.IsLockedDown() or not frame or not frame.IsProtected or not frame:IsProtected()
end

local function IsAtTomb()
    local info = Instance.GetInfo()
    return info.instanceID == TOMB_INSTANCE_ID
        and info.difficultyID == Instance.DIFFICULTY_MYTHIC_RAID
        and TOMB_SUBZONES[Instance.GetSubZoneText()] == true
end

---@param frame Frame
---@return UlatekPadPosition
local function DefaultPadPosition(frame)
    local parentWidth = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0
    local frameWidth = (frame.GetWidth and frame:GetWidth()) or 0
    local maxX = math.max((parentWidth - frameWidth) / 2, 0)
    return {
        point = "CENTER",
        relativePoint = "CENTER",
        x = maxX * DEFAULT_PAD_X_RATIO,
        y = 0,
    }
end

local function IsFactoryPadPosition(position)
    return position.point == "CENTER" and position.relativePoint == "CENTER" and position.x == 0 and position.y == 0
end

---What the commander should see. Preview always shows; otherwise only in Mythic Ulatek's tomb.
local function IsPadVisible()
    if not Ulatek:IsRaidCommander() then
        return false
    end
    if previewVisible then
        return true
    end
    return IsAtTomb()
end

function Window.IsLayoutEditing()
    return layoutEditCount > 0
end

function Window.BeginLayoutEdit()
    layoutEditCount = layoutEditCount + 1
end

function Window.EndLayoutEdit()
    layoutEditCount = math.max(0, layoutEditCount - 1)
    if layoutEditCount == 0 then
        Window.Update()
    end
end

---@param scale number
function Window.ApplyScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

function Window.Update()
    if Window.IsLayoutEditing() then
        return
    end
    if not Ulatek:IsRaidCommander() then
        previewVisible = false
        Ulatek:EndPadTest()
    end
    local visible = IsPadVisible()
    if not visible and not window then
        visibilityDirty = false
        return
    end
    if not window then
        if not CanChangeVisibility() then
            visibilityDirty = true
            return
        end
        window = Window.Create()
    end
    if windowCloseButton and CanConfigure(windowCloseButton) then
        windowCloseButton:SetShown(previewVisible)
    end
    if not CanChangeVisibility() then
        visibilityDirty = visible ~= window:IsShown()
        return
    end
    visibilityDirty = false
    if visible then
        if not window:IsShown() then
            window:Show()
        end
        window:Raise()
    elseif window:IsShown() then
        window:Hide()
    end
end

---Clears the 3x test. The pad stays up when the commander is still in Mythic Ulatek's tomb.
function Window.DismissPreview()
    previewVisible = false
    Ulatek:EndPadTest()
    Window.Update()
end

---Opens the floating pad and starts the 3x timeline. Closing is via the window's X.
function Window.StartPreview()
    if not Ulatek:IsRaidCommander() then
        return
    end
    previewVisible = true
    Window.Update()
    Ulatek:StartPadTest()
end

local function RegisterPadLayoutElement(frame)
    if padLayoutRegistered then
        return
    end
    padLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.ULATEK_SECTION_TACTICAL_PAD,
        frame = frame,
        global = false,
        isEnabled = function()
            return Ulatek:IsRaidCommander()
        end,
        getPosition = function()
            return Ulatek:GetTacticalPadPosition()
        end,
        setPosition = function(position)
            Ulatek:SetTacticalPadPosition(position)
        end,
        getDefaultPosition = function()
            return DefaultPadPosition(frame)
        end,
        onEditBegin = function()
            Window.BeginLayoutEdit()
            local win = window or Window.Create()
            if windowCloseButton then
                windowCloseButton:Hide()
            end
            win:Show()
            win:Raise()
        end,
        onEditEnd = function()
            Window.EndLayoutEdit()
        end,
    })
end

---Creates the floating arena map with the current corner-marker assignment.
---Secure callout buttons are created here, out of combat, and keep a fixed layout.
function Window.Create()
    if window then
        return window
    end
    local frame = FloatingWindow.Create({
        scale = Ulatek:GetTacticalPadScale(),
        position = Ulatek:GetTacticalPadPosition(),
        draggable = false,
        onPositionChanged = function(position)
            Ulatek:SetTacticalPadPosition(position)
        end,
        closable = true,
        onClose = function()
            Window.DismissPreview()
        end,
    })
    windowCloseButton = frame.closeButton

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.LARGE,
        paddingY = Spacing.MEDIUM,
    })
    -- Header overlays the top of the stack; keep a small gap below it.
    stack:AddRow(Sizes.FLOATING_HEADER_HEIGHT - Spacing.MEDIUM + Spacing.SMALL)
    local body = stack:AddRow(Map.GetArenaRowHeight(ARENA_SIZE, MARKER_SIZE))

    local arena = Map.CreateArenaRow(body, {
        size = ARENA_SIZE,
        markerSize = MARKER_SIZE,
        showCalloutButtons = true,
    })
    Map.AttachWindowHint(frame.header, arena.canvas)
    Map.LayoutArenaRow(arena)
    Window.UpdateMacroClicks()

    frame:SetSize(arena.width + 2 * Spacing.LARGE, stack:GetHeight())
    if IsFactoryPadPosition(Ulatek:GetTacticalPadPosition()) then
        local position = DefaultPadPosition(frame)
        Ulatek:SetTacticalPadPosition(position)
        frame:SetWindowPosition(position)
    end
    window = frame
    RegisterPadLayoutElement(frame)
    return frame
end

---Creates the pad on first use so layout editing can show it and secure buttons exist before pulls.
function Window.Ensure()
    if window then
        return window
    end
    if Combat.IsLockedDown() then
        visibilityDirty = true
        return nil
    end
    window = Window.Create()
    Window.Update()
    return window
end

---Members' pad clicks must not fire signal macros; commanders keep them bound.
function Window.UpdateMacroClicks()
    if Map.SetCalloutMacroClicksEnabled(Ulatek:IsRaidCommander()) then
        macroClicksDirty = false
    else
        macroClicksDirty = true
    end
end

---Applies Show/Hide that combat lockdown deferred. Called from OnEnable.
function Window.ListenForCombatDeferral()
    Combat.OnEnter(function()
        Window.DismissPreview()
    end)
    Combat.OnLeave(function()
        if macroClicksDirty then
            Window.UpdateMacroClicks()
        end
        if visibilityDirty then
            Window.Update()
        end
    end)
    -- Zoning into the raid is out of combat, which is the last chance to Show the protected pad.
    Instance.OnEnteringWorld(function()
        Window.Update()
    end)
    Instance.OnZoneChangedIndoors(function()
        Window.Update()
    end)
end

function Ulatek.OnEncounterChanged()
    Window.DismissPreview()
end

Internals.BindPadTestUi({
    OnTick = function(elapsed, duration)
        if Map.SetTestTimer then
            Map.SetTestTimer(elapsed, duration, true)
        end
    end,
    OnFinished = function()
        Window.DismissPreview()
    end,
    OnEnded = function()
        if Map.SetTestTimer then
            Map.SetTestTimer(0, Internals.Timeline.PAD_TEST_DURATION, false)
        end
    end,
})
