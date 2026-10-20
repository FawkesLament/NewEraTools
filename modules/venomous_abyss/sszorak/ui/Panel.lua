local _, ns = ...
local L = ns.L
local Util = ns.Util
local Assets = ns.Assets
local Combat = ns.Api.Combat
local AddonCheckPanel = ns.AddonCheckPanel
local ActionRow = ns.ActionRow
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Widgets = ns.Widgets
local PendingClock = ns.PendingClock

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")
local Map = ns.SszorakMap
local Window = ns.SszorakWindow
local Callout = ns.SszorakCalloutUI

-- Distance between opposite edges of the octagon in the panel's marker editor.
local EDITOR_ARENA_SIZE = 160

local PICKER_COLUMNS = 5
local PICKER_ICON_SIZE = 20
local PICKER_CELL_SIZE = PICKER_ICON_SIZE + 2 * Spacing.SMALL
local PICKER_CELL_STEP = PICKER_CELL_SIZE + Spacing.TINY
-- Markers on other walls stay clickable (picking one swaps), but recede so the free ones stand out.
local PICKER_IN_USE_ALPHA = 0.45
local HINT_ROW_HEIGHT = 16

local MARKER_NAMES = Map.MARKER_NAMES

local picker
local modeCell
local modeControl
local resetButton
local createMacrosRow
local createMacrosButton
local addonCheckButton
local syncRow
local mapSection
local mapBody
local roleLabel
local roleStatus
---@type AddonCheckPanel|nil
local addonCheckPanel

-- Segmented-control values for the player's side. They do not turn the map.
local GROUP_LEFT = "LEFT"
local GROUP_RIGHT = "RIGHT"

local function HidePicker()
    if picker then
        picker:Hide()
    end
end

local function AddPickerCellTooltip(cell)
    Widgets.AttachTooltip(cell, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_NAMES[cell.marker])
        local owner = Sszorak:FindEdgeWithMarker(cell.marker)
        if owner and owner ~= picker.edge then
            tooltip:AddLine(L.SSZORAK_MARKER_SWAP, Widgets.UnpackColor(Colors.TEXT_MUTED))
        end
    end)
end

local function CreatePickerCell(frame, index, marker, columns)
    local cell = CreateFrame("Button", nil, frame, Assets.Templates.BACKDROP)
    cell:SetSize(PICKER_CELL_SIZE, PICKER_CELL_SIZE)
    local x, y = Layout.GridCell(index, columns, PICKER_CELL_STEP, PICKER_CELL_STEP)
    cell:SetPoint("TOPLEFT", frame, "TOPLEFT", Spacing.SMALL + x, y - Spacing.SMALL)
    Widgets.AddHoverHighlight(cell)
    cell.marker = marker

    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(PICKER_ICON_SIZE, PICKER_ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexture(Assets.WORLD_MARKER_ICONS[marker])

    cell:SetScript("OnClick", function()
        Sszorak:SetEdgeMarker(picker.edge, marker)
        HidePicker()
    end)
    AddPickerCellTooltip(cell)
    return cell
end

-- A full-screen catcher behind the picker closes it when the player clicks anywhere else.
local function CreatePicker()
    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:RegisterForClicks("AnyUp")
    blocker:SetScript("OnClick", HidePicker)
    blocker:Hide()

    local frame = Widgets.CreateSurface(blocker, Colors.SURFACE_RAISED, Colors.BORDER)
    frame:EnableMouse(true)
    blocker.frame = frame

    local markers = Sszorak.WORLD_MARKERS
    local columns = math.min(#markers, PICKER_COLUMNS)
    blocker.cells = {}
    for index, marker in ipairs(markers) do
        blocker.cells[index] = CreatePickerCell(frame, index, marker, columns)
    end
    frame:SetSize(
        2 * Spacing.SMALL + (columns - 1) * PICKER_CELL_STEP + PICKER_CELL_SIZE,
        2 * Spacing.SMALL + Layout.GridHeight(#markers, columns, PICKER_CELL_STEP) - Spacing.TINY
    )
    frame:SetClampedToScreen(true)
    return blocker
end

local function ShowPicker(anchor, edge)
    if not Sszorak:IsMapEnabled() then
        return
    end
    picker = picker or CreatePicker()
    picker.edge = edge

    local current = Sszorak:GetEdgeMarker(edge)
    for _, cell in ipairs(picker.cells) do
        local owner = Sszorak:FindEdgeWithMarker(cell.marker)
        Widgets.ApplyBackdrop(cell, Colors.SURFACE, cell.marker == current and Colors.ACCENT or Colors.BORDER)
        cell:SetAlpha((owner and owner ~= edge) and PICKER_IN_USE_ALPHA or 1)
    end

    -- The picker lives on UIParent so the panel's scroll area can't clip it, but should match the panel's scale.
    local frame = picker.frame
    frame:SetScale(anchor:GetEffectiveScale() / picker:GetEffectiveScale())
    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -Spacing.SMALL)
    picker:Show()
end

local function UpdateResetButton()
    if not resetButton then
        return
    end
    resetButton:SetShown(Sszorak:IsMapEnabled() and not Sszorak:IsDefaultEdgeMarkers())
end

---Shows or collapses a commander-only stack row and refreshes the section height.
---@param row Frame|nil
---@param shown boolean
local function SetCommanderRowShown(row, shown)
    if not row or not mapBody or not mapSection then
        return
    end
    mapBody:SetEntryHeight(row, shown and Sizes.CONTROL_ROW_HEIGHT or 0)
    row:SetShown(shown)
    mapSection:SetContentHeight(mapBody:GetHeight())
end

---Macro status beside the create button: green when macros exist, red on create failure, empty otherwise.
---@param message string|nil
---@param color table|nil  Assets color; defaults to ERROR when message is set.
local function SetRoleStatus(message, color)
    if not roleStatus then
        return
    end
    roleStatus:SetText(message or "")
    if message and message ~= "" then
        roleStatus:SetTextColor(Widgets.UnpackColor(color or Colors.ERROR))
    end
end

---Wraps `text` in the accent color escape so it stands out inside a muted FontString.
---@param text string
---@return string
local function AccentText(text)
    local r, g, b = Widgets.UnpackColor(Colors.ACCENT)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5),
        text
    )
end

local function HideAddonCheckPanel()
    if addonCheckPanel then
        addonCheckPanel:Hide()
    end
end

---Restores lasting macro status for the raid leader (drops transient create errors).
local function UpdateRoleStatus()
    if not Sszorak:IsRaidCommander() then
        SetRoleStatus(nil)
        return
    end
    if Sszorak:HasAllEdgeMacros() then
        SetRoleStatus(L.SSZORAK_MACROS_READY, Colors.SUCCESS)
    else
        SetRoleStatus(L.SSZORAK_MACROS_NEEDED, Colors.WARNING)
    end
end

---Keeps role label, commander-only rows, and map macro clicks aligned with raid leadership.
local function UpdateCommanderControls()
    local isCommander = Sszorak:IsRaidCommander()
    if roleLabel then
        local roleName = isCommander and L.SSZORAK_RAID_ROLE_COMMANDER or L.SSZORAK_RAID_ROLE_MEMBER
        roleLabel:SetFormattedText(L.SSZORAK_RAID_ROLE_MODE, AccentText(roleName))
    end
    SetCommanderRowShown(createMacrosRow, isCommander)
    SetCommanderRowShown(syncRow, isCommander)
    if not isCommander then
        HideAddonCheckPanel()
    end
    if createMacrosButton and Sszorak:IsMapEnabled() then
        createMacrosButton:SetEnabled(isCommander)
        createMacrosButton:SetAlpha(1)
    end
    if addonCheckButton and Sszorak:IsMapEnabled() then
        addonCheckButton:SetEnabled(isCommander)
        addonCheckButton:SetAlpha(1)
    end
    UpdateRoleStatus()
    Window.UpdateMacroClicks()
end

local function SszorakAddonCheckColumns()
    return {
        {
            key = "enabled",
            title = L.SSZORAK_ADDONCHECK_COL_ENABLED,
            format = function(value)
                if value == true then
                    return L.FEATURE_ON
                end
                if value == false then
                    return L.FEATURE_OFF
                end
                return nil
            end,
        },
        {
            key = "side",
            title = L.SSZORAK_ADDONCHECK_COL_SIDE,
            format = function(value)
                if value == Sszorak.SIDE_LEFT then
                    return L.SSZORAK_GROUP_LEFT
                end
                if value == Sszorak.SIDE_RIGHT then
                    return L.SSZORAK_GROUP_RIGHT
                end
                return nil
            end,
        },
        {
            key = "mode",
            title = L.SSZORAK_CALLOUT_MODE,
            format = function(value)
                if value == Sszorak.CALLOUT_MODE_NORMAL then
                    return L.SSZORAK_CALLOUT_MODE_NORMAL
                end
                if value == Sszorak.CALLOUT_MODE_JAILBREAK then
                    return L.SSZORAK_CALLOUT_MODE_JAILBREAK
                end
                return nil
            end,
        },
    }
end

local function EnsureAddonCheckPanel()
    if addonCheckPanel then
        return addonCheckPanel
    end
    addonCheckPanel = AddonCheckPanel.Create({
        moduleId = Sszorak.ADDON_CHECK_MODULE_ID,
        name = "NewEraToolsSszorakAddonCheck",
        title = L.ADDONCHECK_TITLE,
        columns = SszorakAddonCheckColumns(),
        validator = Sszorak.ValidateAddonCheckConfig,
    })
    return addonCheckPanel
end

local function ShowAddonCheckPanel()
    if not Sszorak:IsRaidCommander() then
        return
    end
    EnsureAddonCheckPanel():Show()
end

local SCOPE_ID = "sszorak"

local function BeginEditPosition()
    if Combat.IsInCombat() or Combat.IsLockedDown() then
        Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
        return
    end
    if not Sszorak:IsMapEnabled() then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return
    end
    LayoutEditor.BeginScope(SCOPE_ID)
end

---Creates the mode toggle once jailbreak is registered, and selects the mode that is actually in use.
local function RefreshCalloutModeControl()
    if not modeCell or not Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK) then
        return
    end
    if not modeControl then
        local modeLabel = Widgets.CreateLabel(modeCell, Fonts.BODY, L.SSZORAK_CALLOUT_MODE)
        modeLabel:SetJustifyH("LEFT")
        -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
        local modeHit = CreateFrame("Frame", nil, modeCell)
        modeHit:SetPoint("TOPLEFT", modeLabel, "TOPLEFT")
        modeHit:SetPoint("BOTTOMRIGHT", modeLabel, "BOTTOMRIGHT")
        modeHit:EnableMouse(true)
        Widgets.AttachTooltip(modeHit, "ANCHOR_TOP", function(tooltip)
            tooltip:SetText(L.SSZORAK_CALLOUT_MODE_TOOLTIP)
        end)
        modeControl = Widgets.CreateSegmentedControl(modeCell, {
            { value = Sszorak.CALLOUT_MODE_NORMAL, text = L.SSZORAK_CALLOUT_MODE_NORMAL },
            { value = Sszorak.CALLOUT_MODE_JAILBREAK, text = L.SSZORAK_CALLOUT_MODE_JAILBREAK },
        }, function(modeId)
            if not Sszorak:IsMapEnabled() then
                return
            end
            Sszorak:SetCalloutMode(modeId)
            modeControl:SetSelected(Sszorak:GetCalloutMode())
        end)
        Layout.Row(modeCell, { modeLabel, modeControl }, Spacing.LARGE)
    end
    modeControl:SetSelected(Sszorak:GetCalloutMode())
end

function Sszorak:OnCalloutModesChanged()
    RefreshCalloutModeControl()
end

local RebuildMapSettings

local function ResetBuiltControls()
    modeCell = nil
    modeControl = nil
    resetButton = nil
    createMacrosRow = nil
    createMacrosButton = nil
    addonCheckButton = nil
    syncRow = nil
    mapBody = nil
    roleLabel = nil
    roleStatus = nil
end

---Fills the encounter-map feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildMapContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.MEDIUM,
    })
    mapBody = body

    local toolsRow = body:AddRow(ActionRow.HEIGHT)
    ActionRow.Apply(toolsRow, {
        title = L.SSZORAK_TOOLS_PREVIEW,
        description = L.SSZORAK_TOOLS_PREVIEW_DESC,
        buttons = {
            { text = L.SSZORAK_START_TEST, onClick = Window.StartPreview },
            { text = L.SSZORAK_EDIT_POSITION, onClick = BeginEditPosition, layout = true },
        },
    })

    local roleRow = body:AddRow(HINT_ROW_HEIGHT)
    roleLabel = Widgets.CreateLabel(roleRow, Fonts.SMALL_MUTED)
    roleLabel:SetJustifyH("LEFT")
    roleLabel:SetPoint("LEFT", roleRow, "LEFT")
    -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
    local roleHit = CreateFrame("Frame", nil, roleRow)
    roleHit:SetPoint("TOPLEFT", roleLabel, "TOPLEFT")
    roleHit:SetPoint("BOTTOMRIGHT", roleLabel, "BOTTOMRIGHT")
    roleHit:EnableMouse(true)
    Widgets.AttachTooltip(roleHit, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.SSZORAK_RAID_ROLE_MODE_TOOLTIP)
    end)

    -- A. Basic Settings
    Widgets.LayoutSectionHeader(body:AddRow(Sizes.CONTENT_SECTION_HEADER), L.SSZORAK_SECTION_BASIC)

    createMacrosRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local macrosCell, addonCheckCell = Layout.SplitRow(createMacrosRow, Spacing.MEDIUM)
    createMacrosButton = Widgets.CreateButton(macrosCell, L.SSZORAK_CREATE_MACROS, function()
        if not Sszorak:IsMapEnabled() or not Sszorak:IsRaidCommander() then
            return
        end
        if Combat.IsInCombat() or Combat.IsLockedDown() then
            SetRoleStatus(L.SSZORAK_RAID_ROLE_IN_COMBAT, Colors.ERROR)
            return
        end
        local ok, createReason = Sszorak:CreateEdgeMacros()
        if not ok then
            SetRoleStatus(
                createReason == "combat" and L.SSZORAK_RAID_ROLE_IN_COMBAT or L.SSZORAK_MACROS_FAILED,
                Colors.ERROR
            )
            return
        end
        SetRoleStatus(L.SSZORAK_MACROS_READY, Colors.SUCCESS)
        Window.UpdateMacroClicks()
    end, "primary")
    roleStatus = Widgets.CreateLabel(macrosCell, Fonts.SMALL_MUTED)
    roleStatus:SetJustifyH("LEFT")
    createMacrosButton:SetPoint("LEFT", macrosCell, "LEFT")
    roleStatus:SetPoint("LEFT", createMacrosButton, "RIGHT", Spacing.MEDIUM, 0)
    roleStatus:SetPoint("RIGHT", macrosCell, "RIGHT")

    addonCheckButton = Widgets.CreateButton(addonCheckCell, L.ADDONCHECK_BUTTON, function()
        if not Sszorak:IsMapEnabled() or not Sszorak:IsRaidCommander() then
            return
        end
        ShowAddonCheckPanel()
    end, "primary")
    Widgets.AttachTooltip(addonCheckButton, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.ADDONCHECK_BUTTON_TOOLTIP)
    end)
    addonCheckButton:SetPoint("LEFT", addonCheckCell, "LEFT")

    local groupRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local groupCell
    groupCell, modeCell = Layout.SplitRow(groupRow, Spacing.MEDIUM)
    local groupLabel = Widgets.CreateLabel(groupCell, Fonts.BODY, L.SSZORAK_GROUP_LABEL)
    groupLabel:SetJustifyH("LEFT")
    local groupControl
    groupControl = Widgets.CreateSegmentedControl(groupCell, {
        { value = GROUP_LEFT, text = L.SSZORAK_GROUP_LEFT },
        { value = GROUP_RIGHT, text = L.SSZORAK_GROUP_RIGHT },
    }, function(group)
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:SetPlayerSide(group == GROUP_RIGHT and Sszorak.SIDE_RIGHT or Sszorak.SIDE_LEFT)
        groupControl:SetSelected(group)
        Map.RefreshPlayerGroup()
    end)
    groupControl:SetSelected(Sszorak:GetPlayerSide() == Sszorak.SIDE_RIGHT and GROUP_RIGHT or GROUP_LEFT)
    Layout.Row(groupCell, { groupLabel, groupControl }, Spacing.LARGE)

    -- The right cell stays empty until jailbreak is registered. A later registration fills it in place.
    RefreshCalloutModeControl()

    -- B. Marker Configuration
    local markersHeader = body:AddRow(Sizes.CONTENT_SECTION_HEADER, Spacing.LARGE)
    Widgets.LayoutSectionHeader(markersHeader, L.SSZORAK_SECTION_MARKERS)
    resetButton = Widgets.CreateTextButton(markersHeader, L.SSZORAK_MARKERS_RESET, function()
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:ResetEdgeMarkers()
    end)
    resetButton:SetPoint("RIGHT", markersHeader, "RIGHT")
    UpdateResetButton()

    local editorRow = body:AddRow(Map.GetArenaRowHeight(EDITOR_ARENA_SIZE))
    local editorArena = Map.CreateArenaRow(editorRow, { size = EDITOR_ARENA_SIZE, onEdgeMarkerClick = ShowPicker })
    local function CenterEditorArena()
        local width = editorRow:GetWidth()
        if width and width > 0 then
            editorArena.inset = math.max(0, (width - editorArena.width) / 2)
        end
        Map.LayoutArenaRow(editorArena)
    end
    editorRow:SetScript("OnSizeChanged", CenterEditorArena)
    CenterEditorArena()

    local hintRow = body:AddRow(HINT_ROW_HEIGHT)
    local hint = Widgets.CreateLabel(hintRow, Fonts.SMALL_MUTED, L.SSZORAK_MARKERS_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetPoint("LEFT", hintRow, "LEFT")
    hint:SetPoint("RIGHT", hintRow, "RIGHT")

    syncRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local syncButton = Widgets.CreateButton(syncRow, L.SSZORAK_BROADCAST, function()
        Sszorak:BroadcastEdgeMarkers()
    end, "primary")
    syncButton:SetPoint("RIGHT", syncRow, "RIGHT")

    -- C. UI Tools
    Widgets.LayoutSectionHeader(body:AddRow(Sizes.CONTENT_SECTION_HEADER, Spacing.LARGE), L.SSZORAK_SECTION_TOOLS)

    ---Label, flexible slider, value box, and optional suffix, filling one half of a row.
    ---@param cell Frame
    ---@param label FontString
    ---@param slider SliderControl
    local function PlaceHalfSlider(cell, label, slider)
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", cell, "LEFT")
        local box = slider.valueBox
        local suffix = slider.valueSuffix
        if suffix then
            suffix:ClearAllPoints()
            suffix:SetPoint("RIGHT", cell, "RIGHT")
            box:ClearAllPoints()
            box:SetPoint("RIGHT", suffix, "LEFT", -Spacing.TINY, 0)
        else
            box:ClearAllPoints()
            box:SetPoint("RIGHT", cell, "RIGHT")
        end
        slider:ClearAllPoints()
        -- LARGE leaves room for the pending-combat clock between the label and the slider.
        slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
        slider:SetPoint("RIGHT", box, "LEFT", -Spacing.MEDIUM, 0)
    end

    ---Saves `rawValue` immediately. The live map waits until combat ends; the slider stays editable.
    ---@param slider SliderControl
    ---@param clock PendingClockFrame
    ---@param write fun(value: number)
    ---@param apply fun()
    local function BindDeferredSlider(slider, clock, write, apply)
        slider:SetScript("OnValueChanged", function(_, rawValue)
            if not Sszorak:IsMapEnabled() then
                return
            end
            write(rawValue)
            PendingClock.Defer(clock, apply, RebuildMapSettings)
        end)
    end

    local sliderRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local scaleCell, rotationCell = Layout.SplitRow(sliderRow, Spacing.MEDIUM)

    local scaleLabel = Widgets.CreateLabel(scaleCell, Fonts.BODY, L.SSZORAK_MAP_SCALE)
    local scaleClock = PendingClock.Attach(scaleLabel)
    local scaleSlider = Widgets.CreateSlider(
        scaleCell,
        Sszorak.MAP_SCALE_MIN,
        Sszorak.MAP_SCALE_MAX,
        Sszorak.MAP_SCALE_STEP,
        { percentage = true }
    )
    Widgets.AttachTooltip(scaleSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.SSZORAK_MAP_SCALE_TOOLTIP)
    end)
    scaleSlider:SetValue(Sszorak:GetMapScale())
    BindDeferredSlider(scaleSlider, scaleClock, function(rawValue)
        Sszorak:SetMapScale(rawValue)
    end, function()
        Window.ApplyScale(Sszorak:GetMapScale())
    end)
    PlaceHalfSlider(scaleCell, scaleLabel, scaleSlider)

    local rotationLabel = Widgets.CreateLabel(rotationCell, Fonts.BODY, L.SSZORAK_MAP_ROTATION)
    local rotationClock = PendingClock.Attach(rotationLabel)
    local rotationSlider = Widgets.CreateSlider(
        rotationCell,
        Sszorak.MAP_ROTATION_MIN,
        Sszorak.MAP_ROTATION_MAX,
        Sszorak.MAP_ROTATION_STEP,
        { suffix = L.DEGREE_SUFFIX }
    )
    Widgets.AttachTooltip(rotationSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.SSZORAK_MAP_ROTATION_TOOLTIP)
    end)
    rotationSlider:SetValue(Sszorak:GetMapRotation())
    BindDeferredSlider(rotationSlider, rotationClock, function(rawValue)
        Sszorak:SetMapRotation(rawValue)
    end, function()
        Window.ApplyRotation()
    end)
    PlaceHalfSlider(rotationCell, rotationLabel, rotationSlider)

    return body:GetHeight()
end

---Drops the settings widgets and builds them again from the saved values.
---Used after a combat-deferred scale or rotation is applied, so the pending clocks are gone.
function RebuildMapSettings()
    if not mapSection then
        return
    end
    HidePicker()
    local children = { mapSection:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    ResetBuiltControls()
    mapSection:SetContentHeight(BuildMapContent(mapSection))
    mapSection:RefreshContentInteractive()
    UpdateCommanderControls()
end

---@param container Frame
---@return number
local function Build(container)
    mapSection = container
    local height = BuildMapContent(container)
    container:SetContentHeight(height)
    -- Building the body created enabled controls; match them to the saved feature state.
    container:RefreshContentInteractive()
    UpdateCommanderControls()

    container:HookScript("OnShow", function()
        UpdateCommanderControls()
    end)
    container:HookScript("OnHide", function()
        HidePicker()
    end)
    return height
end

function Sszorak:OnEnable()
    LayoutEditor.RegisterScope({
        id = SCOPE_ID,
        label = L.SSZORAK_LAYOUT_SCOPE,
        order = 5,
        elementIds = { Window.LAYOUT_ID, Callout.LAYOUT_ID },
        prepare = function()
            Window.Ensure()
            Callout.Ensure()
        end,
    })
    ns.MainPanel:RegisterSection({
        title = L.SSZORAK_TITLE,
        headerTitle = L.SSZORAK_DROP_BALL,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        enabled = Sszorak:IsMapEnabled(),
        onEnabledChanged = function(enabled)
            Sszorak:SetMapEnabled(enabled)
            if not enabled then
                HidePicker()
            end
            UpdateResetButton()
            UpdateCommanderControls()
            -- Enabling or disabling never opens or closes a preview; during a fight it shows or hides the map.
            Window.Update()
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
        build = Build,
    })
    self:ListenForBroadcasts()
    self:ListenForEncounter()
    self:ListenForCalloutMode()
    self:ListenForMacroSync()
    -- Register layout elements before the map is first shown.
    -- Secure marker buttons must be created out of combat; OnEnable runs before pulls.
    -- Show now when a raid pull could start, because Show is blocked once combat lockdown begins.
    Window.Ensure()
    Callout.Ensure()
    Window.Update()
    -- Window markers are created with macro bindings; strip them for members.
    Window.UpdateMacroClicks()
    Window.ListenForCombatDeferral()
    ns.Api.Group.OnChanged(function()
        UpdateCommanderControls()
    end)
end

function Sszorak:OnEdgeMarkersChanged()
    Map.RefreshEdgeMarkers()
    if resetButton then
        UpdateResetButton()
    end
end

function Sszorak:OnEncounterChanged()
    -- Leaving preview behind when the fight starts (or ends) so it never outlives the pull.
    -- Animation start/stop is handled in Encounter.lua so a pull resets a running preview timer.
    Window.DismissPreview()
    Window.Update()
    Callout.Update()
end

function Sszorak:OnPositionsChanged()
    Map.RefreshPositionMarkers()
    -- Each return to the entrance-side home station clears fired-marker highlights for the next cycle.
    if Sszorak:IsAtHomeStation() then
        Map.ResetEdgeClickHighlights()
    end
end

function Sszorak:OnMapAnimationStarted()
    Window.UpdateMacroClicks()
end

function Sszorak:OnMapAnimationStopped()
    Map.SetEdgeClickTrackingArmed(false)
end

function Sszorak:OnCalloutChanged()
    Callout.Update()
    local resolve = Sszorak:GetDisplayedCalloutResolve()
    Map.SetPathArrow(resolve and resolve.targetEdge or nil)
end
