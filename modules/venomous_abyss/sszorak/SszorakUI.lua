local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Widgets = ns.Widgets
local SszorakMapUI = ns.SszorakMapUI

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Sszorak = ns.Modules.Get("Sszorak")

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
-- Status line under the floating map for wind-vent progress and cyst shot-calls.
local WIND_STATUS_HEIGHT = 18

local MARKER_NAMES = SszorakMapUI.MARKER_NAMES

local window
local windowArena
local windowCloseButton
local windowStack
local windowWindStatusRow
---@class WindHelperStatusLabels
---@field progress FontString
---@field round1Label FontString
---@field round1Markers FontString
---@field round2Label FontString
---@field round2Markers FontString
local windowWindStatus
local picker
local resetButton
local broadcast
local mapSection
-- Session-only: temporary map outside the boss fight. Independent of the saved mapEnabled setting.
local previewVisible = false
local CreateArenaWindow
local UpdateResetButton
local UpdateBroadcastButton
local UpdateWindHelperDisplay

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

local function UpdateWindow()
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
        -- Animation start notifies before the window exists; refresh once the status row is built.
        UpdateWindHelperDisplay()
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
        Sszorak:StartMapAnimation({ rate = Sszorak.ANIM_PREVIEW_RATE })
    else
        Sszorak:StopMapAnimation()
    end
    UpdateWindow()
end

local function TogglePreview()
    SetPreviewVisible(not previewVisible)
end

local function FormatMarkerList(edges)
    local names = {}
    for _, edge in ipairs(edges) do
        table.insert(names, MARKER_NAMES[Sszorak:GetEdgeMarker(edge)])
    end
    return table.concat(names, L.SSZORAK_WIND_HELPER_MARKER_SEP)
end

-- Locale templates are "Round N: %s"; the label is everything except the marker list.
local function RoundLabelText(template)
    return (template:gsub("%%s", ""))
end

function UpdateWindHelperDisplay()
    SszorakMapUI.RefreshWindHighlights()
    if not windowWindStatus then
        return
    end
    local status = windowWindStatus
    local interactive = Sszorak:IsWindHelperInteractive()
    local plan = interactive and Sszorak:GetCystPlan() or nil
    local rowWidgets
    if plan then
        status.progress:Hide()
        status.round1Label:SetText(RoundLabelText(L.SSZORAK_WIND_HELPER_ROUND1))
        status.round1Markers:SetText(FormatMarkerList(plan.round1))
        status.round2Label:SetText(RoundLabelText(L.SSZORAK_WIND_HELPER_ROUND2))
        status.round2Markers:SetText(FormatMarkerList(plan.round2))
        status.round1Label:Show()
        status.round1Markers:Show()
        status.round2Label:Show()
        status.round2Markers:Show()
        rowWidgets = {
            status.round1Label,
            status.round1Markers,
            status.round2Label,
            status.round2Markers,
        }
    elseif interactive then
        status.round1Label:Hide()
        status.round1Markers:Hide()
        status.round2Label:Hide()
        status.round2Markers:Hide()
        status.progress:SetText(
            string.format(L.SSZORAK_WIND_HELPER_PROGRESS, #Sszorak:GetWindVents(), Sszorak.WIND_VENT_COUNT)
        )
        status.progress:Show()
        rowWidgets = { status.progress }
    else
        status.progress:Hide()
        status.round1Label:Hide()
        status.round1Markers:Hide()
        status.round2Label:Hide()
        status.round2Markers:Hide()
        rowWidgets = {}
    end
    if #rowWidgets > 0 then
        Layout.Row(windowWindStatusRow, rowWidgets, Spacing.SMALL)
    end
    local show = interactive
    -- Collapse outside the fight so preview stays tight; spacing is folded into the open height.
    windowStack:SetEntryHeight(windowWindStatusRow, show and (Spacing.SMALL + WIND_STATUS_HEIGHT) or 0)
    window:SetHeight(windowStack:GetHeight())
end

local function OnWindowEdgeMarkerClick(_, edge)
    Sszorak:ToggleWindVent(edge)
end

function CreateArenaWindow()
    -- Header overlays the empty space above the octagon so the drag strip and close button fit there.
    local frame = FloatingWindow.Create({
        scale = Sszorak:GetMapScale(),
        position = Sszorak:GetMapPosition(),
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
    windowStack = stack
    local body = stack:AddRow(SszorakMapUI.GetArenaRowHeight(ARENA_SIZE))

    local arena = SszorakMapUI.CreateArenaRow(body, {
        size = ARENA_SIZE,
        showPositions = true,
        followsRotation = true,
        onEdgeMarkerClick = OnWindowEdgeMarkerClick,
        windHighlights = true,
    })
    SszorakMapUI.LayoutArenaRow(arena)
    windowArena = arena

    -- Starts collapsed; UpdateWindHelperDisplay opens it during the encounter.
    windowWindStatusRow = stack:AddRow(0, 0)
    local progress = Widgets.CreateLabel(windowWindStatusRow, Fonts.HEADER)
    progress:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
    progress:SetWordWrap(false)
    local round1Label = Widgets.CreateLabel(windowWindStatusRow, Fonts.HEADER)
    round1Label:SetTextColor(Widgets.UnpackColor(Colors.ACCENT))
    round1Label:SetWordWrap(false)
    local round1Markers = Widgets.CreateLabel(windowWindStatusRow, Fonts.EMPHASIS)
    round1Markers:SetWordWrap(false)
    local round2Label = Widgets.CreateLabel(windowWindStatusRow, Fonts.HEADER)
    round2Label:SetTextColor(Widgets.UnpackColor(Colors.ACCENT))
    round2Label:SetWordWrap(false)
    local round2Markers = Widgets.CreateLabel(windowWindStatusRow, Fonts.EMPHASIS)
    round2Markers:SetWordWrap(false)
    progress:Hide()
    round1Label:Hide()
    round1Markers:Hide()
    round2Label:Hide()
    round2Markers:Hide()
    windowWindStatus = {
        progress = progress,
        round1Label = round1Label,
        round1Markers = round1Markers,
        round2Label = round2Label,
        round2Markers = round2Markers,
    }

    frame:SetSize(arena.width + 2 * Spacing.LARGE, stack:GetHeight())
    return frame
end

-- The default map has the entrance on the right; rotating 180° is the right-side view.
local GROUP_LEFT = "LEFT"
local GROUP_RIGHT = "RIGHT"

function UpdateResetButton()
    resetButton:SetShown(Sszorak:IsMapEnabled() and not Sszorak:IsDefaultEdgeMarkers())
end

function UpdateBroadcastButton()
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

---Fills the encounter-map feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildMapContent(content)
    local body = Layout.Stack(content)

    local controlsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local groupCell, scaleCell = Layout.SplitRow(controlsRow, Spacing.MEDIUM)

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
        Sszorak:SetMapRotated(group == GROUP_RIGHT)
        groupControl:SetSelected(group)
        if windowArena then
            SszorakMapUI.ApplyRotation(windowArena)
        end
    end)
    groupControl:SetSelected(Sszorak:IsMapRotated() and GROUP_RIGHT or GROUP_LEFT)
    Layout.Row(groupCell, { groupLabel, groupControl }, Spacing.LARGE)

    local scaleLabel = Widgets.CreateLabel(scaleCell, Fonts.BODY, L.SSZORAK_MAP_SCALE)
    scaleLabel:SetJustifyH("LEFT")
    local scaleValue = Widgets.CreateLabel(scaleCell, Fonts.SMALL_MUTED)
    scaleValue:SetWidth(Sizes.SLIDER_VALUE_WIDTH)
    scaleValue:SetJustifyH("RIGHT")
    local scaleSlider =
        Widgets.CreateSlider(scaleCell, Sszorak.MAP_SCALE_MIN, Sszorak.MAP_SCALE_MAX, Sszorak.MAP_SCALE_STEP)
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
    Layout.Row(scaleCell, { scaleLabel }, 0)
    scaleSlider:SetPoint("LEFT", scaleLabel, "RIGHT", Spacing.LARGE, 0)
    scaleValue:SetPoint("LEFT", scaleSlider, "RIGHT", Spacing.MEDIUM, 0)

    local editorHeader = body:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.MEDIUM)
    local markersLabel = Widgets.CreateLabel(editorHeader, Fonts.BODY, L.SSZORAK_MARKERS_HEADER)
    resetButton = Widgets.CreateTextButton(editorHeader, L.SSZORAK_MARKERS_RESET, function()
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:ResetEdgeMarkers()
    end)
    Layout.Row(editorHeader, { markersLabel, resetButton }, Spacing.MEDIUM)
    UpdateResetButton()

    local editorRow = body:AddRow(SszorakMapUI.GetArenaRowHeight(EDITOR_ARENA_SIZE))
    SszorakMapUI.LayoutArenaRow(
        SszorakMapUI.CreateArenaRow(editorRow, { size = EDITOR_ARENA_SIZE, onEdgeMarkerClick = ShowPicker })
    )

    local hintRow = body:AddRow(HINT_ROW_HEIGHT)
    local hint = Widgets.CreateLabel(hintRow, Fonts.SMALL_MUTED, L.SSZORAK_MARKERS_HINT)
    Layout.Row(hintRow, { hint }, 0)

    local actionsRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.MEDIUM)
    local preview = Widgets.CreateButton(actionsRow, L.SSZORAK_PREVIEW, TogglePreview)
    local syncButton = Widgets.CreateButton(actionsRow, L.SSZORAK_BROADCAST, function()
        Sszorak:BroadcastEdgeMarkers()
    end, "primary")
    local reason = Widgets.CreateLabel(actionsRow, Fonts.SMALL_MUTED)
    reason:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
    reason:SetJustifyH("LEFT")
    reason:SetWordWrap(false)
    Layout.Row(actionsRow, { preview, syncButton, reason }, Spacing.MEDIUM)
    reason:SetPoint("RIGHT", actionsRow, "RIGHT")
    broadcast = { button = syncButton, reason = reason }

    -- Subfeature of the encounter map: its own On/Off, dimmed with the parent when the map is off.
    local windRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT, Spacing.MEDIUM)
    local windTitle = Widgets.CreateLabel(windRow, Fonts.BODY, L.SSZORAK_WIND_HELPER)
    windTitle:SetJustifyH("LEFT")
    windTitle:SetPoint("LEFT", windRow, "LEFT")
    local windHit = CreateFrame("Frame", nil, windRow)
    windHit:SetPoint("TOPLEFT", windTitle, "TOPLEFT")
    windHit:SetPoint("BOTTOMRIGHT", windTitle, "BOTTOMRIGHT")
    windHit:EnableMouse(true)
    Widgets.AttachTooltip(windHit, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.SSZORAK_WIND_HELPER_TOOLTIP)
    end)
    local windToggle
    windToggle = Widgets.CreateSegmentedControl(windRow, {
        { value = true, text = L.FEATURE_ON },
        { value = false, text = L.FEATURE_OFF },
    }, function(enabled)
        if not Sszorak:IsMapEnabled() then
            return
        end
        Sszorak:SetWindHelperEnabled(enabled)
        windToggle:SetSelected(enabled)
        UpdateWindHelperDisplay()
    end)
    windToggle:SetPoint("RIGHT", windRow, "RIGHT")
    windToggle:SetSelected(Sszorak:IsWindHelperEnabled())

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local stack = Layout.Stack(container, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
    })

    mapSection = FeatureSection.Create(container, {
        title = L.SSZORAK_MAP_ENABLED,
        enabled = Sszorak:IsMapEnabled(),
        onEnabledChanged = function(enabled)
            Sszorak:SetMapEnabled(enabled)
            if not enabled then
                HidePicker()
            end
            UpdateResetButton()
            -- Re-apply raid sync rules after the section enables every control in the body.
            UpdateBroadcastButton()
            -- Enabling or disabling never opens or closes a preview; during a fight it shows or hides the map.
            UpdateWindow()
            UpdateWindHelperDisplay()
        end,
        onHeightChanged = function(height)
            stack:SetEntryHeight(mapSection, height)
            container:SetContentHeight(stack:GetHeight())
        end,
    })

    stack:Add(mapSection, 0)
    mapSection:SetContentHeight(BuildMapContent(mapSection.content))
    -- Building the body created enabled controls; match them to the saved feature state.
    mapSection:RefreshContentInteractive()
    UpdateBroadcastButton()

    container:HookScript("OnShow", UpdateBroadcastButton)
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
    UpdateWindHelperDisplay()
end

function Sszorak:OnPositionsChanged()
    SszorakMapUI.RefreshPositionMarkers()
end

function Sszorak:OnWindHelperChanged()
    UpdateWindHelperDisplay()
end
