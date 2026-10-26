local _, ns = ...
local Internals = ns.Modules.Internals("Sszorak")
local L = ns.L
local Assets = ns.Assets
local Combat = ns.Api.Combat
local FloatingWindow = ns.FloatingWindow
local Instance = ns.Api.Instance
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor

local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")
local Map = Internals.Map

-- Distance between opposite edges of the drawn octagon in the floating map.
local ARENA_SIZE = 220
-- Factory default: 80% of the max on-screen CENTER X (right of center); Y stays centered.
local DEFAULT_MAP_X_RATIO = 0.8

local LAYOUT_ID = "Sszorak:map"

local Window = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.Window = Window

local window
local windowArena
local windowCloseButton
local mapLayoutRegistered = false
-- Counts concurrent layout-edit attachments (map + callout share Edit Position).
local layoutEditCount = 0
-- Session-only: temporary map outside the boss fight. Independent of the saved mapEnabled setting.
local previewVisible = false
-- True when role-driven macro click binding couldn't apply during combat lockdown.
local macroClicksDirty = false
-- True when Show/Hide was skipped because the protected window cannot change during lockdown.
local visibilityDirty = false

-- Venomous Abyss. GetInstanceInfo instanceID.
local ALTAR_INSTANCE_ID = 3004
-- Exact GetSubZoneText values for the Sszorak room (enUS / zhCN).
local ALTAR_SUBZONES = {
    ["Altar of the Six Winds"] = true,
    ["六风祭坛"] = true,
}

local function CanConfigure(frame)
    return not Combat.IsLockedDown() or not frame.IsProtected or not frame:IsProtected()
end

local function IsAtAltar()
    return Instance.GetInfo().instanceID == ALTAR_INSTANCE_ID and ALTAR_SUBZONES[Instance.GetSubZoneText()] == true
end

---@param frame Frame
---@return MapPosition
local function DefaultMapPosition(frame)
    local parentWidth = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0
    local frameWidth = (frame.GetWidth and frame:GetWidth()) or 0
    local maxX = math.max((parentWidth - frameWidth) / 2, 0)
    return {
        point = "CENTER",
        relativePoint = "CENTER",
        x = maxX * DEFAULT_MAP_X_RATIO,
        y = 0,
    }
end

local function IsFactoryMapPosition(position)
    return position.point == "CENTER"
        and position.relativePoint == "CENTER"
        and position.x == 0
        and position.y == 0
end

---What the player should see. Preview always shows; otherwise only at the altar when the feature is on.
local function IsMapVisible()
    if previewVisible then
        return true
    end
    return Sszorak:IsMapEnabled() and IsAtAltar()
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

local function ApplyWindowScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

---@param scale number
function Window.ApplyScale(scale)
    ApplyWindowScale(scale)
end

function Window.Update()
    if Window.IsLayoutEditing() then
        return
    end
    local visible = IsMapVisible()
    if not visible and not window then
        return
    end
    if not window then
        if Combat.IsLockedDown() then
            visibilityDirty = true
            return
        end
        window = Window.Create()
    end
    if windowCloseButton and CanConfigure(windowCloseButton) then
        windowCloseButton:SetShown(previewVisible and not Sszorak:IsInEncounter())
    end
    if not CanConfigure(window) then
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

---Clears the out-of-combat preview flag. Does not stop the timeline; encounter code owns that.
function Window.DismissPreview()
    previewVisible = false
end

local function SetPreviewVisible(visible)
    -- Preview is only meaningful outside the fight; encounter visibility uses mapEnabled alone.
    if Sszorak:IsInEncounter() then
        return
    end
    visible = visible == true
    if previewVisible == visible then
        return
    end
    previewVisible = visible
    if visible then
        Sszorak:StartMapTest()
    else
        Sszorak:EndMapTest()
    end
    Window.Update()
end

---Opens the floating map test. Closing is via the window's X; never toggles to "End Test".
function Window.StartPreview()
    if Sszorak:IsInEncounter() then
        return
    end
    if previewVisible then
        -- Already open: raise the existing window instead of starting a second test.
        Window.Update()
        return
    end
    SetPreviewVisible(true)
end

local function WindowEdgeMacroName(edge)
    return Sszorak:GetEdgeMacroName(edge)
end

local function RegisterMapLayoutElement(frame)
    if mapLayoutRegistered then
        return
    end
    mapLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.SSZORAK_TITLE,
        frame = frame,
        -- Boss-specific: excluded from the global layout editor.
        global = false,
        isEnabled = function()
            return Sszorak:IsMapEnabled()
        end,
        getPosition = function()
            return Sszorak:GetMapPosition()
        end,
        setPosition = function(position)
            Sszorak:SetMapPosition(position)
        end,
        getDefaultPosition = function()
            return DefaultMapPosition(frame)
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

---Creates the floating arena map. Secure marker buttons are created here, out of combat.
function Window.Create()
    -- Header overlays the empty space above the octagon so the drag strip and close button fit there.
    local frame = FloatingWindow.Create({
        scale = Sszorak:GetMapScale(),
        position = Sszorak:GetMapPosition(),
        -- Positioning uses LayoutEditor (module-local Edit Position); markers run callout macros.
        draggable = false,
        onPositionChanged = function(position)
            Sszorak:SetMapPosition(position)
        end,
        closable = true,
        onClose = function()
            SetPreviewVisible(false)
        end,
    })
    windowCloseButton = frame.closeButton

    local stack = Layout.Stack(frame, {
        paddingX = Spacing.LARGE,
        paddingY = Spacing.MEDIUM,
    })
    local body = stack:AddRow(Map.GetArenaRowHeight(ARENA_SIZE))

    local arena = Map.CreateArenaRow(body, {
        size = ARENA_SIZE,
        showPositions = true,
        followsRotation = true,
        edgeMarkerMacroName = WindowEdgeMacroName,
    })
    Map.LayoutArenaRow(arena)
    windowArena = arena
    Window.UpdateMacroClicks()

    frame:SetSize(arena.width + 2 * Spacing.LARGE, stack:GetHeight())
    if IsFactoryMapPosition(Sszorak:GetMapPosition()) then
        local position = DefaultMapPosition(frame)
        Sszorak:SetMapPosition(position)
        frame:SetWindowPosition(position)
    end
    RegisterMapLayoutElement(frame)
    return frame
end

---Creates the map on first use. OnEnable calls this before pulls so secure buttons exist out of combat.
function Window.Ensure()
    window = window or Window.Create()
    return window
end

function Window.ApplyRotation()
    if windowArena then
        Map.ApplyRotation(windowArena)
    end
end

---Members' map clicks must not fire callout macros; commanders keep them bound.
---Commander pull/test also arms one-shot highlight tracking on the floating map.
function Window.UpdateMacroClicks()
    if Map.SetEdgeMacroClicksEnabled(Sszorak:IsRaidCommander()) then
        macroClicksDirty = false
    else
        macroClicksDirty = true
    end
    Map.SetEdgeClickTrackingArmed(Sszorak:IsRaidCommander() and Sszorak:IsMapAnimating())
end

---Reapplies macro click bindings that combat lockdown deferred. Called from OnEnable.
function Window.ListenForCombatDeferral()
    Combat.OnLeave(function()
        if macroClicksDirty then
            Window.UpdateMacroClicks()
        end
        if visibilityDirty then
            Window.Update()
        end
    end)
    -- Zoning into the raid is out of combat, which is the last chance to Show the protected map.
    Instance.OnEnteringWorld(function()
        Window.Update()
    end)
    Instance.OnZoneChangedIndoors(function()
        Window.Update()
    end)
end
