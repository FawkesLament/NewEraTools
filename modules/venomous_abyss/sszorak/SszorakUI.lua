local _, ns = ...
local L = ns.L
local Util = ns.Util
local Assets = ns.Assets
local Chat = ns.Api.Chat
local Combat = ns.Api.Combat
local FeatureSection = ns.FeatureSection
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local CalloutMessage = ns.CalloutMessage
local LayoutEditor = ns.LayoutEditor
local Widgets = ns.Widgets
local SszorakMapUI = ns.SszorakMapUI

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")

local LAYOUT_ID_MAP = "Sszorak:map"
local LAYOUT_ID_CALLOUT = "Sszorak:callout"

-- Distance between opposite edges of the drawn octagon, in the map window and in the panel's editor.
local ARENA_SIZE = 220
local EDITOR_ARENA_SIZE = 160

local PICKER_COLUMNS = 5
local PICKER_ICON_SIZE = 20
local PICKER_CELL_SIZE = PICKER_ICON_SIZE + 2 * Spacing.SMALL
local PICKER_CELL_STEP = PICKER_CELL_SIZE + Spacing.TINY
-- Markers on other walls stay clickable (picking one swaps), but recede so the free ones stand out.
local PICKER_IN_USE_ALPHA = 0.45
local HINT_ROW_HEIGHT = 16
-- Large enough for the callout font plus a short raid-marker message.
local CALLOUT_WIDTH = 420
local CALLOUT_HEIGHT = 72

local MARKER_NAMES = SszorakMapUI.MARKER_NAMES

local window
local windowArena
local windowCloseButton
local calloutWindow
local picker
local resetButton
local broadcast
local mapSection
local mapBody
local roleRow
local roleStatus
-- Session-only: temporary map outside the boss fight. Independent of the saved mapEnabled setting.
local previewVisible = false
local mapLayoutRegistered = false
local calloutLayoutRegistered = false
-- Counts concurrent layout-edit attachments (map + callout share Edit Position).
local layoutEditCount = 0
-- True when role-driven macro click binding couldn't apply during combat lockdown.
local macroClicksDirty = false
local CreateArenaWindow
local CreateCalloutWindow
local UpdateWindow
local UpdateResetButton
local UpdateBroadcastButton
local UpdateCalloutWindow
local SyncRoleRowHeight
local SetRoleStatus
local UpdateRoleStatus
local UpdateWindowMacroClicks
local RegisterMapLayoutElement
local RegisterCalloutLayoutElement

local function IsLayoutEditing()
    return layoutEditCount > 0
end

local function BeginLayoutEdit()
    layoutEditCount = layoutEditCount + 1
end

local function EndLayoutEdit()
    layoutEditCount = math.max(0, layoutEditCount - 1)
    if layoutEditCount == 0 then
        UpdateWindow()
        UpdateCalloutWindow()
    end
end

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

local function ApplyWindowScale(scale)
    if window then
        window:SetWindowScale(scale)
    end
end

local function IsWindowWanted()
    if Sszorak:IsInEncounter() then
        return Sszorak:IsMapEnabled()
    end
    return previewVisible
end

function UpdateWindow()
    if IsLayoutEditing() then
        return
    end
    local wanted = IsWindowWanted()
    if not wanted and not window then
        return
    end
    window = window or CreateArenaWindow()
    if windowCloseButton then
        -- Encounter mode keeps the map up for the whole fight; only preview can be dismissed.
        windowCloseButton:SetShown(not Sszorak:IsInEncounter())
    end
    if wanted then
        if not window:IsShown() then
            window:Show()
        end
        window:Raise()
    elseif window:IsShown() then
        window:Hide()
    end
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
    UpdateWindow()
end

---Opens the floating map test. Closing is via the window's X; never toggles to "End Test".
local function StartPreview()
    if Sszorak:IsInEncounter() then
        return
    end
    if previewVisible then
        -- Already open: raise the existing window instead of starting a second test.
        UpdateWindow()
        return
    end
    SetPreviewVisible(true)
end

local function WindowEdgeMacroName(edge)
    return Sszorak:GetEdgeMacroName(edge)
end

function RegisterMapLayoutElement(frame)
    if mapLayoutRegistered then
        return
    end
    mapLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID_MAP,
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
        onEditBegin = function()
            BeginLayoutEdit()
            local win = window or CreateArenaWindow()
            if windowCloseButton then
                windowCloseButton:Hide()
            end
            win:Show()
            win:Raise()
        end,
        onEditEnd = function()
            EndLayoutEdit()
        end,
    })
end

function RegisterCalloutLayoutElement(frame)
    if calloutLayoutRegistered then
        return
    end
    calloutLayoutRegistered = true
    LayoutEditor.Register({
        id = LAYOUT_ID_CALLOUT,
        label = L.SSZORAK_CALLOUT_TITLE,
        frame = frame,
        global = false,
        isEnabled = function()
            return Sszorak:IsMapEnabled()
        end,
        getPosition = function()
            return Sszorak:GetCalloutPosition()
        end,
        setPosition = function(position)
            Sszorak:SetCalloutPosition(position)
        end,
        onEditBegin = function()
            BeginLayoutEdit()
            local win = calloutWindow or CreateCalloutWindow()
            win:ShowPreview(
                Chat.ReplaceIconAndGroupExpressions(L.SSZORAK_CALLOUT_PREVIEW),
                Sszorak.CALLOUT_DURATION_ENCOUNTER,
                true
            )
        end,
        onEditEnd = function()
            EndLayoutEdit()
        end,
    })
end

function CreateArenaWindow()
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
    local body = stack:AddRow(SszorakMapUI.GetArenaRowHeight(ARENA_SIZE))

    local arena = SszorakMapUI.CreateArenaRow(body, {
        size = ARENA_SIZE,
        showPositions = true,
        followsRotation = true,
        edgeMarkerMacroName = WindowEdgeMacroName,
    })
    SszorakMapUI.LayoutArenaRow(arena)
    windowArena = arena
    UpdateWindowMacroClicks()

    frame:SetSize(arena.width + 2 * Spacing.LARGE, stack:GetHeight())
    RegisterMapLayoutElement(frame)
    return frame
end

function CreateCalloutWindow()
    -- Plain host: text only (no backdrop). LayoutEditor moves this frame in Edit Position.
    local frame = CalloutMessage.Create({
        name = ns.ADDON_NAME .. "SszorakCallout",
        width = CALLOUT_WIDTH,
        height = CALLOUT_HEIGHT,
        wrap = L.SSZORAK_CALLOUT_WRAP,
    })
    LayoutEditor.ApplyPosition(frame, Sszorak:GetCalloutPosition())
    RegisterCalloutLayoutElement(frame)
    return frame
end

function UpdateCalloutWindow()
    if IsLayoutEditing() then
        return
    end
    calloutWindow = calloutWindow or CreateCalloutWindow()
    local text = Sszorak:GetDisplayedCallout()
    if text == nil then
        calloutWindow:Clear()
        return
    end
    local remaining = Sszorak:GetCalloutRemainingSeconds()
    if remaining == nil then
        calloutWindow:Clear()
        return
    end
    -- Remaining seconds come from callout logic so edits mid-callout do not reset the countdown.
    calloutWindow:SetMessage(text, remaining, Sszorak:GetCalloutAppendTimer())
end

local function BeginEditPosition()
    if Combat.IsInCombat() or Combat.IsLockedDown() then
        Util.Print(L.LAYOUT_EDIT_IN_COMBAT)
        return
    end
    if not Sszorak:IsMapEnabled() then
        Util.Print(L.LAYOUT_EDIT_NONE)
        return
    end
    window = window or CreateArenaWindow()
    calloutWindow = calloutWindow or CreateCalloutWindow()
    LayoutEditor.BeginLocal({ LAYOUT_ID_MAP, LAYOUT_ID_CALLOUT })
end

-- The default map has the entrance on the right; rotating 180° is the right-side view.
local GROUP_LEFT = "LEFT"
local GROUP_RIGHT = "RIGHT"

function UpdateResetButton()
    if not resetButton then
        return
    end
    resetButton:SetShown(Sszorak:IsMapEnabled() and not Sszorak:IsDefaultEdgeMarkers())
end

function UpdateBroadcastButton()
    if not broadcast then
        return
    end
    if not Sszorak:IsMapEnabled() then
        broadcast.button:SetEnabled(false)
        broadcast.button:SetAlpha(1)
        broadcast.reason:SetText("")
        return
    end
    local reason = Sszorak:GetBroadcastBlockedReason()
    broadcast.button:SetEnabled(not reason)
    broadcast.reason:SetText(reason or "")
end

---Grows the role row so a wrapping status line next to the toggle is never clipped.
function SyncRoleRowHeight()
    if not roleRow or not mapBody or not mapSection or not roleStatus then
        return
    end
    local height = Sizes.CONTROL_ROW_HEIGHT
    local text = roleStatus:GetText()
    if text and text ~= "" then
        height = math.max(height, roleStatus:GetStringHeight())
    end
    if math.abs(roleRow:GetHeight() - height) < 0.5 then
        return
    end
    mapBody:SetEntryHeight(roleRow, height)
    mapSection:SetContentHeight(mapBody:GetHeight())
end

---Status text beside the role toggle: green when commander, red on create failure, empty for member.
---@param message string|nil
---@param color table|nil  Assets color; defaults to ERROR when message is set.
function SetRoleStatus(message, color)
    if not roleStatus then
        return
    end
    roleStatus:SetText(message or "")
    if message and message ~= "" then
        roleStatus:SetTextColor(Widgets.UnpackColor(color or Colors.ERROR))
    end
    SyncRoleRowHeight()
end

---Restores the lasting status for the saved role (drops transient create errors).
function UpdateRoleStatus()
    if Sszorak:IsRaidCommander() then
        SetRoleStatus(L.SSZORAK_MACROS_READY, Colors.SUCCESS)
    else
        SetRoleStatus(nil)
    end
end

---Members' map clicks must not fire callout macros; commanders keep them bound.
---Commander pull/test also arms one-shot highlight tracking on the floating map.
function UpdateWindowMacroClicks()
    if SszorakMapUI.SetEdgeMacroClicksEnabled(Sszorak:IsRaidCommander()) then
        macroClicksDirty = false
    else
        macroClicksDirty = true
    end
    SszorakMapUI.SetEdgeClickTrackingArmed(Sszorak:IsRaidCommander() and Sszorak:IsMapAnimating())
end

---Fills the encounter-map feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildMapContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.MEDIUM })
    mapBody = body

    -- A. Basic Settings
    Widgets.LayoutSectionHeader(body:AddRow(Sizes.CONTENT_SECTION_HEADER), L.SSZORAK_SECTION_BASIC)

    roleRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local roleLabel = Widgets.CreateLabel(roleRow, Fonts.BODY, L.SSZORAK_RAID_ROLE)
    roleLabel:SetJustifyH("LEFT")
    local roleControl
    roleControl = Widgets.CreateSegmentedControl(roleRow, {
        { value = Sszorak.RAID_ROLE_MEMBER, text = L.SSZORAK_RAID_ROLE_MEMBER },
        { value = Sszorak.RAID_ROLE_COMMANDER, text = L.SSZORAK_RAID_ROLE_COMMANDER },
    }, function(role)
        if not Sszorak:IsMapEnabled() then
            return
        end
        local previous = Sszorak:GetRaidRole()
        if role == previous then
            roleControl:SetSelected(previous)
            return
        end
        -- Secure marker attributes and CreateMacro are locked in combat; block either direction.
        if Combat.IsInCombat() or Combat.IsLockedDown() then
            roleControl:SetSelected(previous)
            SetRoleStatus(L.SSZORAK_RAID_ROLE_IN_COMBAT, Colors.ERROR)
            return
        end
        if role == Sszorak.RAID_ROLE_MEMBER then
            Sszorak:SetRaidRole(role)
            roleControl:SetSelected(role)
            SetRoleStatus(nil)
            UpdateWindowMacroClicks()
            return
        end
        -- Commander only after macros are written; keep the toggle on the previous role on failure.
        local ok, createReason = Sszorak:CreateEdgeMacros()
        if not ok then
            roleControl:SetSelected(previous)
            SetRoleStatus(
                createReason == "combat" and L.SSZORAK_RAID_ROLE_IN_COMBAT or L.SSZORAK_MACROS_FAILED,
                Colors.ERROR
            )
            return
        end
        Sszorak:SetRaidRole(role)
        roleControl:SetSelected(role)
        SetRoleStatus(L.SSZORAK_MACROS_READY, Colors.SUCCESS)
        UpdateWindowMacroClicks()
    end)
    roleControl:SetSelected(Sszorak:GetRaidRole())
    Layout.Row(roleRow, { roleLabel, roleControl }, Spacing.LARGE)
    roleStatus = Widgets.CreateLabel(roleRow, Fonts.SMALL_MUTED)
    roleStatus:SetJustifyH("LEFT")
    roleStatus:SetJustifyV("MIDDLE")
    roleStatus:SetWordWrap(true)
    roleStatus:SetNonSpaceWrap(true)
    roleStatus:SetPoint("LEFT", roleControl, "RIGHT", Spacing.MEDIUM, 0)
    roleStatus:SetPoint("RIGHT", roleRow, "RIGHT")
    roleRow:HookScript("OnSizeChanged", SyncRoleRowHeight)
    UpdateRoleStatus()

    local groupRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local groupLabel = Widgets.CreateLabel(groupRow, Fonts.BODY, L.SSZORAK_GROUP_LABEL)
    groupLabel:SetJustifyH("LEFT")
    local groupControl
    groupControl = Widgets.CreateSegmentedControl(groupRow, {
        { value = GROUP_LEFT, text = L.SSZORAK_GROUP_LEFT },
        { value = GROUP_RIGHT, text = L.SSZORAK_GROUP_RIGHT },
    }, function(group)
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:SetMapRotated(group == GROUP_RIGHT)
        groupControl:SetSelected(group)
        if windowArena then
            SszorakMapUI.ApplyRotation(windowArena)
        end
    end)
    groupControl:SetSelected(Sszorak:IsMapRotated() and GROUP_RIGHT or GROUP_LEFT)
    Layout.Row(groupRow, { groupLabel, groupControl }, Spacing.LARGE)

    -- Only when a private jailbreak implementation has registered; public stub leaves this hidden.
    if Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK) then
        local modeRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
        local modeLabel = Widgets.CreateLabel(modeRow, Fonts.BODY, L.SSZORAK_CALLOUT_MODE)
        modeLabel:SetJustifyH("LEFT")
        -- FontStrings can't take mouse; a matching hit frame carries the tooltip.
        local modeHit = CreateFrame("Frame", nil, modeRow)
        modeHit:SetPoint("TOPLEFT", modeLabel, "TOPLEFT")
        modeHit:SetPoint("BOTTOMRIGHT", modeLabel, "BOTTOMRIGHT")
        modeHit:EnableMouse(true)
        Widgets.AttachTooltip(modeHit, "ANCHOR_TOP", function(tooltip)
            tooltip:SetText(L.SSZORAK_CALLOUT_MODE_TOOLTIP)
        end)
        local modeControl
        modeControl = Widgets.CreateSegmentedControl(modeRow, {
            { value = Sszorak.CALLOUT_MODE_NORMAL, text = L.SSZORAK_CALLOUT_MODE_NORMAL },
            { value = Sszorak.CALLOUT_MODE_JAILBREAK, text = L.SSZORAK_CALLOUT_MODE_JAILBREAK },
        }, function(modeId)
            if not Sszorak:IsMapEnabled() then
                return
            end
            Sszorak:SetCalloutMode(modeId)
            modeControl:SetSelected(Sszorak:GetCalloutMode())
        end)
        modeControl:SetSelected(Sszorak:GetCalloutMode())
        Layout.Row(modeRow, { modeLabel, modeControl }, Spacing.LARGE)
    end

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

    local editorRow = body:AddRow(SszorakMapUI.GetArenaRowHeight(EDITOR_ARENA_SIZE))
    local editorArena =
        SszorakMapUI.CreateArenaRow(editorRow, { size = EDITOR_ARENA_SIZE, onEdgeMarkerClick = ShowPicker })
    local function CenterEditorArena()
        local width = editorRow:GetWidth()
        if width and width > 0 then
            editorArena.inset = math.max(0, (width - editorArena.width) / 2)
        end
        SszorakMapUI.LayoutArenaRow(editorArena)
    end
    editorRow:SetScript("OnSizeChanged", CenterEditorArena)
    CenterEditorArena()

    local hintRow = body:AddRow(HINT_ROW_HEIGHT)
    local hint = Widgets.CreateLabel(hintRow, Fonts.SMALL_MUTED, L.SSZORAK_MARKERS_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetPoint("LEFT", hintRow, "LEFT")
    hint:SetPoint("RIGHT", hintRow, "RIGHT")

    local syncRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local syncButton = Widgets.CreateButton(syncRow, L.SSZORAK_BROADCAST, function()
        Sszorak:BroadcastEdgeMarkers()
    end, "primary")
    syncButton:SetPoint("RIGHT", syncRow, "RIGHT")
    local reason = Widgets.CreateLabel(syncRow, Fonts.SMALL_MUTED)
    reason:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
    reason:SetJustifyH("RIGHT")
    reason:SetWordWrap(false)
    reason:SetPoint("RIGHT", syncButton, "LEFT", -Spacing.MEDIUM, 0)
    reason:SetPoint("LEFT", syncRow, "LEFT")
    broadcast = { button = syncButton, reason = reason }

    -- C. UI Tools
    Widgets.LayoutSectionHeader(body:AddRow(Sizes.CONTENT_SECTION_HEADER, Spacing.LARGE), L.SSZORAK_SECTION_TOOLS)

    local toolsHintRow = body:AddRow(HINT_ROW_HEIGHT)
    local toolsHint = Widgets.CreateLabel(toolsHintRow, Fonts.SMALL_MUTED, L.SSZORAK_TOOLS_HINT)
    toolsHint:SetJustifyH("LEFT")
    toolsHint:SetPoint("LEFT", toolsHintRow, "LEFT")
    toolsHint:SetPoint("RIGHT", toolsHintRow, "RIGHT")

    local scaleRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local scaleLabel = Widgets.CreateLabel(scaleRow, Fonts.BODY, L.SSZORAK_MAP_SCALE)
    scaleLabel:SetJustifyH("LEFT")
    local scaleValue = Widgets.CreateLabel(scaleRow, Fonts.SMALL_MUTED)
    scaleValue:SetWidth(Sizes.SLIDER_VALUE_WIDTH)
    scaleValue:SetJustifyH("RIGHT")
    local scaleSlider =
        Widgets.CreateSlider(scaleRow, Sszorak.MAP_SCALE_MIN, Sszorak.MAP_SCALE_MAX, Sszorak.MAP_SCALE_STEP)
    Widgets.AttachTooltip(scaleSlider, "ANCHOR_BOTTOM", function(tooltip)
        tooltip:SetText(L.SSZORAK_MAP_SCALE_TOOLTIP)
    end)
    local function ShowScaleValue(scale)
        scaleValue:SetFormattedText(L.MAIN_PANEL_SCALE_PERCENT, math.floor(scale * 100 + 0.5))
    end
    scaleSlider:SetValue(Sszorak:GetMapScale())
    ShowScaleValue(Sszorak:GetMapScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:SetMapScale(rawValue)
        local scale = Sszorak:GetMapScale()
        ShowScaleValue(scale)
        ApplyWindowScale(scale)
    end)
    Layout.Row(scaleRow, { scaleLabel }, 0)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", Spacing.LARGE, 0)
    scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", Spacing.MEDIUM, 0)

    local toolsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local preview = Widgets.CreateButton(toolsRow, L.SSZORAK_START_TEST, StartPreview)
    local editPosition = Widgets.CreateButton(toolsRow, L.SSZORAK_EDIT_POSITION, BeginEditPosition)
    Layout.Row(toolsRow, { preview, editPosition }, Spacing.MEDIUM)

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    mapSection = FeatureSection.Create(stack, {
        title = L.SSZORAK_MAP_ENABLED,
        enabled = Sszorak:IsMapEnabled(),
        onStackHeightChanged = function(height)
            container:SetContentHeight(height)
        end,
        onEnabledChanged = function(enabled)
            Sszorak:SetMapEnabled(enabled)
            if not enabled then
                HidePicker()
            end
            UpdateResetButton()
            -- Re-apply raid sync status after the section enables every control in the body.
            UpdateBroadcastButton()
            -- Enabling or disabling never opens or closes a preview; during a fight it shows or hides the map.
            UpdateWindow()
        end,
    })

    mapSection:SetContentHeight(BuildMapContent(mapSection.content))
    -- Building the body created enabled controls; match them to the saved feature state.
    mapSection:RefreshContentInteractive()
    UpdateBroadcastButton()

    container:HookScript("OnShow", function()
        UpdateBroadcastButton()
        UpdateRoleStatus()
    end)
    container:HookScript("OnHide", HidePicker)
    return stack:GetHeight()
end

function Sszorak:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.SSZORAK_TITLE,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        build = Build,
    })
    self:ListenForBroadcasts()
    self:ListenForEncounter()
    self:ListenForCalloutMode()
    self:ListenForMacroSync()
    -- Register with the layout editor (local-only) before the map is first shown.
    -- Secure marker buttons must be created out of combat; OnEnable runs before pulls.
    window = window or CreateArenaWindow()
    calloutWindow = calloutWindow or CreateCalloutWindow()
    -- Window markers are created with macro bindings; strip them for members.
    UpdateWindowMacroClicks()
    Combat.OnLeave(function()
        if macroClicksDirty then
            UpdateWindowMacroClicks()
        end
    end)
    ns.Api.Group.OnChanged(function()
        if broadcast then
            UpdateBroadcastButton()
        end
    end)
end

function Sszorak:OnEdgeMarkersChanged()
    SszorakMapUI.RefreshEdgeMarkers()
    if resetButton then
        UpdateResetButton()
    end
end

function Sszorak:OnEncounterChanged()
    -- Leaving preview behind when the fight starts (or ends) so it never outlives the pull.
    -- Animation start/stop is handled in the logic file so a pull resets a running preview timer.
    previewVisible = false
    UpdateWindow()
    UpdateCalloutWindow()
end

function Sszorak:OnPositionsChanged()
    SszorakMapUI.RefreshPositionMarkers()
    -- Each return to the entrance-side home station clears fired-marker highlights for the next cycle.
    if Sszorak:IsAtHomeStation() then
        SszorakMapUI.ResetEdgeClickHighlights()
    end
end

function Sszorak:OnMapAnimationStarted()
    UpdateWindowMacroClicks()
end

function Sszorak:OnMapAnimationStopped()
    SszorakMapUI.SetEdgeClickTrackingArmed(false)
end

function Sszorak:OnCalloutChanged()
    UpdateCalloutWindow()
    local resolve = Sszorak:GetDisplayedCalloutResolve()
    SszorakMapUI.SetPathArrow(resolve and resolve.targetEdge or nil)
end
