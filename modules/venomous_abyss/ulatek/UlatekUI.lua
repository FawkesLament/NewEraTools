-- Settings page for Ulatek mechanic reminders and arena corner markers.
local _, ns = ...
local Internals = ns.Modules.Internals("Ulatek")
local L = ns.L
local Assets = ns.Assets
local Checkbox = ns.Checkbox
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local Ulatek = ns.Modules.Get("Ulatek")
local Map = Internals.Map
local Spell = ns.Api.Spell

local EGG_DEADLINE_SPELL_ID = 1301268
local CAUSTIC_WAVES_SPELL_ID = 1298570
local WRETCH_AOE_SPELL_ID = 1310763
-- 20px icon + 8px gap + name; matches Coiled Altar's reminder row rhythm.
local SPELL_ICON_SIZE = 20
local SPELL_ICON_CROP = 0.08
local SPELL_HINT_GAP = 8
local REMINDER_LABEL_WIDTH = 100

-- Distance between opposite edges of the octagon in the panel's marker editor.
local EDITOR_ARENA_SIZE = 160
local PICKER_COLUMNS = 5
local PICKER_ICON_SIZE = 20
local PICKER_CELL_SIZE = PICKER_ICON_SIZE + 2 * Spacing.SMALL
local PICKER_CELL_STEP = PICKER_CELL_SIZE + Spacing.TINY
-- Markers on other corners stay clickable (picking one swaps), but recede so the free ones stand out.
local PICKER_IN_USE_ALPHA = 0.45

local MARKER_NAMES = Map.MARKER_NAMES

local picker
local resetButton
local syncButton
local markersHeaderActions
local roleLabel

---@param holder Frame
---@param texture Texture
local function ApplyCroppedSpellIcon(holder, texture)
    texture:SetAllPoints()
    texture:SetTexCoord(SPELL_ICON_CROP, 1 - SPELL_ICON_CROP, SPELL_ICON_CROP, 1 - SPELL_ICON_CROP)
    local r, g, b, a = Widgets.UnpackColor(Colors.BORDER)
    local thickness = Sizes.BORDER
    local edges = {
        { height = thickness, p1 = "TOPLEFT", p2 = "TOPRIGHT" },
        { height = thickness, p1 = "BOTTOMLEFT", p2 = "BOTTOMRIGHT" },
        { width = thickness, p1 = "TOPLEFT", p2 = "BOTTOMLEFT" },
        { width = thickness, p1 = "TOPRIGHT", p2 = "BOTTOMRIGHT" },
    }
    for _, spec in ipairs(edges) do
        local edge = holder:CreateTexture(nil, "OVERLAY")
        if spec.width then
            edge:SetWidth(spec.width)
        else
            edge:SetHeight(spec.height)
        end
        edge:SetPoint(spec.p1)
        edge:SetPoint(spec.p2)
        edge:SetColorTexture(r, g, b, a)
    end
end

---@param parent Frame
---@param spellId integer
---@param labelText string
---@return Button
local function CreateSpellHint(parent, spellId, labelText)
    local hit = CreateFrame("Button", nil, parent)
    hit:RegisterForClicks("LeftButtonUp")
    local iconHolder = CreateFrame("Frame", nil, hit)
    iconHolder:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)
    iconHolder:SetPoint("LEFT")
    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Spell.GetTexture(spellId) or Assets.Icons.QUESTION_MARK)
    ApplyCroppedSpellIcon(iconHolder, icon)
    local label = Widgets.CreateLabel(hit, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetWidth(REMINDER_LABEL_WIDTH - SPELL_ICON_SIZE - SPELL_HINT_GAP)
    label:SetPoint("LEFT", iconHolder, "RIGHT", SPELL_HINT_GAP, 0)
    hit:SetSize(REMINDER_LABEL_WIDTH, Sizes.CONTROL_ROW_HEIGHT)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellId)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return hit
end

local function HidePicker()
    if picker then
        picker:Hide()
    end
end

local function AddPickerCellTooltip(cell)
    Widgets.AttachTooltip(cell, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_NAMES[cell.marker])
        local owner = Ulatek:FindCornerWithMarker(cell.marker)
        if owner and owner ~= picker.corner then
            tooltip:AddLine(L.ULATEK_MARKER_SWAP, Widgets.UnpackColor(Colors.TEXT_MUTED))
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
        Ulatek:SetCornerMarker(picker.corner, marker)
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

    local markers = Ulatek.WORLD_MARKERS
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

local function ShowPicker(anchor, corner)
    picker = picker or CreatePicker()
    picker.corner = corner

    local current = Ulatek:GetCornerMarker(corner)
    for _, cell in ipairs(picker.cells) do
        local owner = Ulatek:FindCornerWithMarker(cell.marker)
        Widgets.ApplyBackdrop(cell, Colors.SURFACE, cell.marker == current and Colors.MENU_ACCENT or Colors.BORDER)
        cell:SetAlpha((owner and owner ~= corner) and PICKER_IN_USE_ALPHA or 1)
    end

    local frame = picker.frame
    frame:SetScale(anchor:GetEffectiveScale() / picker:GetEffectiveScale())
    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -Spacing.SMALL)
    picker:Show()
end

local function LayoutMarkersHeaderActions()
    if not markersHeaderActions or not syncButton then
        return
    end
    local showSync = Ulatek:IsRaidCommander()
    syncButton:SetShown(showSync)
    local showReset = resetButton and resetButton:IsShown()
    if resetButton then
        resetButton:ClearAllPoints()
        if showSync then
            resetButton:SetPoint("RIGHT", syncButton, "LEFT", -Spacing.MEDIUM, 0)
        else
            resetButton:SetPoint("RIGHT", markersHeaderActions, "RIGHT")
        end
    end
    local width = 0
    if showSync then
        width = width + syncButton:GetWidth()
    end
    if showReset then
        if width > 0 then
            width = width + Spacing.MEDIUM
        end
        width = width + resetButton:GetWidth()
    end
    markersHeaderActions:SetWidth(width)
end

local function UpdateResetButton()
    if not resetButton then
        return
    end
    resetButton:SetShown(not Ulatek:IsDefaultCornerMarkers())
    LayoutMarkersHeaderActions()
end

local function UpdateCommanderControls()
    if roleLabel then
        ns.RaidRoleModeLabel.Update(roleLabel)
    end
    LayoutMarkersHeaderActions()
end

---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.MEDIUM,
    })

    local roleRow = body:AddRow(ns.RaidRoleModeLabel.HEIGHT)
    roleLabel = ns.RaidRoleModeLabel.Create(roleRow, L.ULATEK_RAID_ROLE_MODE_TOOLTIP)

    local reminder = FeatureSection.Create(body, {
        title = L.ULATEK_MECHANIC_REMINDER,
        divider = true,
        toggle = false,
    })
    local reminderBody = Layout.Stack(reminder.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    ---@param cell Frame
    ---@param isEnabled fun(): boolean
    ---@param setEnabled fun(enabled: boolean)
    ---@param labelText string
    ---@param spellId integer
    local function AddReminderCheckbox(cell, isEnabled, setEnabled, labelText, spellId)
        local box = Checkbox.Create(cell)
        box:SetChecked(isEnabled())
        box:SetScript("OnClick", function(self)
            setEnabled(self:GetChecked())
            self:SetChecked(isEnabled())
        end)
        local hint = CreateSpellHint(cell, spellId, labelText)
        hint:SetScript("OnClick", function()
            box:Click()
        end)
        Layout.Row(cell, { hint, box }, 0)
    end

    local firstRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local eggCell, wavesCell = Layout.SplitRow(firstRow, Spacing.MEDIUM)
    AddReminderCheckbox(eggCell, function()
        return Ulatek:IsEggDeadlineReminderEnabled()
    end, function(enabled)
        Ulatek:SetEggDeadlineReminderEnabled(enabled)
    end, L.ULATEK_EGG_DEADLINE, EGG_DEADLINE_SPELL_ID)
    AddReminderCheckbox(wavesCell, function()
        return Ulatek:IsCausticWavesReminderEnabled()
    end, function(enabled)
        Ulatek:SetCausticWavesReminderEnabled(enabled)
    end, L.ULATEK_CAUSTIC_WAVES, CAUSTIC_WAVES_SPELL_ID)

    local secondRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local wretchCell = Layout.SplitRow(secondRow, Spacing.MEDIUM)
    AddReminderCheckbox(wretchCell, function()
        return Ulatek:IsWretchAoeReminderEnabled()
    end, function(enabled)
        Ulatek:SetWretchAoeReminderEnabled(enabled)
    end, L.ULATEK_WRETCH_AOE, WRETCH_AOE_SPELL_ID)

    reminder:SetContentHeight(reminderBody:GetHeight())
    reminder:RefreshContentInteractive()

    local markersSection = FeatureSection.Create(body, {
        title = L.ULATEK_SECTION_MARKERS,
        divider = true,
        toggle = false,
    })
    local headerActions = CreateFrame("Frame", nil, markersSection)
    headerActions:SetHeight(Sizes.CONTROL_HEIGHT)
    syncButton = Widgets.CreateButton(headerActions, L.ULATEK_BROADCAST, function()
        Ulatek:BroadcastCornerMarkers()
    end, "accent")
    resetButton = Widgets.CreateTextButton(headerActions, L.ULATEK_MARKERS_RESET, function()
        Ulatek:ResetCornerMarkers()
    end)
    syncButton:SetPoint("RIGHT", headerActions, "RIGHT")
    resetButton:SetPoint("RIGHT", syncButton, "LEFT", -Spacing.MEDIUM, 0)
    function headerActions:SetEnabled(isEnabled)
        syncButton:SetEnabled(isEnabled)
        resetButton:SetEnabled(isEnabled)
        self:SetAlpha(1)
    end
    markersHeaderActions = headerActions
    markersSection:SetHeaderAction(headerActions)
    UpdateResetButton()

    local hint = Widgets.CreateLabel(markersSection.titleLabel:GetParent(), Fonts.SMALL_MUTED, L.ULATEK_MARKERS_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetPoint("LEFT", markersSection.titleLabel, "RIGHT", Spacing.MEDIUM, 0)

    local markersBody = Layout.Stack(markersSection.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })
    local editorRow = markersBody:AddRow(Map.GetArenaRowHeight(EDITOR_ARENA_SIZE))
    local editorArena = Map.CreateArenaRow(editorRow, { size = EDITOR_ARENA_SIZE, onCornerMarkerClick = ShowPicker })
    local function CenterEditorArena()
        local width = editorRow:GetWidth()
        if width and width > 0 then
            editorArena.inset = math.max(0, (width - editorArena.width) / 2)
        end
        Map.LayoutArenaRow(editorArena)
    end
    editorRow:SetScript("OnSizeChanged", CenterEditorArena)
    CenterEditorArena()

    markersSection:SetContentHeight(markersBody:GetHeight())
    markersSection:RefreshContentInteractive()

    return body:GetHeight()
end

function Ulatek:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.ULATEK_TITLE,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        build = function(container)
            local height = BuildContent(container)
            container:HookScript("OnShow", UpdateCommanderControls)
            container:HookScript("OnHide", HidePicker)
            return height
        end,
    })
    ns.Api.Group.OnChanged(UpdateCommanderControls)
    self:ListenForBroadcasts()
    self:ListenForEncounter()
end

function Ulatek:OnCornerMarkersChanged()
    Map.RefreshCornerMarkers()
    UpdateResetButton()
end
