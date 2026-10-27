local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ActionRow = ns.ActionRow
local Dropdown = ns.Dropdown
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local InterruptClaim = ns.Modules.Get("InterruptClaim")

local MARKER_COLUMNS = 4
local MARKER_ICON_SIZE = 18
local MARKER_CELL_SIZE = MARKER_ICON_SIZE + 2 * Spacing.SMALL
local MARKER_CELL_STEP = MARKER_CELL_SIZE + Spacing.TINY

local page
local body
local shortcutSection
local shortcutBody
local claimSection
local claimBody

local markerRow
local announceRow
local macroRow

local markerCells
local announceControl
local createButton
local bindStatus
local bindStatusRow

---@param reason string|nil
---@return string
local function FailureMessage(reason)
    if reason == "combat" then
        return L.INTERRUPT_CLAIM_MACRO_FAILED_COMBAT
    end
    if reason == "conflict" then
        return L.INTERRUPT_CLAIM_MACRO_FAILED_CONFLICT
    end
    return L.INTERRUPT_CLAIM_MACRO_FAILED_SLOTS
end

---@param message string
---@param color table|nil
local function SetMacroDescription(message, color)
    if macroRow and macroRow.SetDescription then
        macroRow:SetDescription(message, color)
    end
end

---@param stack LayoutStack
---@param row Frame
---@param shown boolean
---@param height number
local function SetRowShown(stack, row, shown, height)
    row:SetShown(shown)
    stack:SetEntryHeight(row, shown and height or 0)
end

---@return number
local function MarkerGridHeight()
    return Layout.GridHeight(InterruptClaim.MARKER_MAX, MARKER_COLUMNS, MARKER_CELL_STEP)
end

local function UpdateMarkerSelection()
    if not markerCells then
        return
    end
    local selected = InterruptClaim:GetMarker()
    for marker, cell in pairs(markerCells) do
        Widgets.ApplyBackdrop(cell, Colors.SURFACE, marker == selected and Colors.ACCENT or Colors.BORDER)
    end
end

local function UpdateBindStatus()
    local pending = ns.Api.Combat.IsLockedDown()
    if bindStatus then
        bindStatus:SetText(pending and L.SETTINGS_PENDING_COMBAT or "")
    end
    if shortcutBody and bindStatusRow then
        SetRowShown(shortcutBody, bindStatusRow, pending, 14)
    end
end

local function UpdateMacroUi()
    if not createButton then
        return
    end
    local status = InterruptClaim:GetFocusMacroStatus()
    if status == InterruptClaim.MACRO_STATUS_READY then
        SetMacroDescription(L.INTERRUPT_CLAIM_MACRO_READY, Colors.SUCCESS)
    elseif status == InterruptClaim.MACRO_STATUS_CONFLICT then
        SetMacroDescription(L.INTERRUPT_CLAIM_MACRO_CONFLICT, Colors.WARNING)
    else
        SetMacroDescription(L.INTERRUPT_CLAIM_MACRO_MISSING, Colors.WARNING)
    end
    createButton:Show()
    createButton:SetEnabled(InterruptClaim:IsEnabled())
end

local function RefreshPageHeight()
    if not body or not page then
        return
    end
    if shortcutSection and shortcutBody then
        shortcutSection:SetContentHeight(shortcutBody:GetHeight())
    end
    if claimSection and claimBody then
        claimSection:SetContentHeight(claimBody:GetHeight())
    end
    page:SetContentHeight(body:GetHeight())
    if page.RefreshContentInteractive then
        page:RefreshContentInteractive()
    end
end

local function RefreshDependentRows()
    if not claimBody then
        return
    end
    local marking = InterruptClaim:ShouldSetMarker()
    SetRowShown(claimBody, markerRow, marking, MarkerGridHeight())
    SetRowShown(claimBody, announceRow, marking, Sizes.CONTROL_ROW_HEIGHT)
    if announceControl then
        announceControl:SetSelected(InterruptClaim:GetAnnounce())
    end
    UpdateMarkerSelection()
    UpdateBindStatus()
    RefreshPageHeight()
    UpdateMacroUi()
end

---@param row Frame
---@param labelText string
---@param onClick fun(checked: boolean)
---@return CheckButton
local function AddCheckbox(row, labelText, onClick)
    local box = Widgets.CreateCheckbox(row)
    local label = Widgets.CreateLabel(row, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    Layout.Row(row, { box, label }, Spacing.SMALL)
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    box:SetScript("OnClick", function(self)
        if not InterruptClaim:IsEnabled() then
            self:SetChecked(not self:GetChecked())
            return
        end
        onClick(self:GetChecked() == true)
        self:SetChecked(self:GetChecked())
    end)
    return box
end

local function BuildShortcutSection()
    shortcutSection = FeatureSection.Create(body, {
        title = L.INTERRUPT_CLAIM_SECTION_SHORTCUT,
        toggle = false,
        divider = true,
    })
    shortcutBody = Layout.Stack(shortcutSection.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    local comboRow = shortcutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local modifierCell, mouseCell = Layout.SplitRow(comboRow, Spacing.MEDIUM)

    local modifierLabel = Widgets.CreateLabel(modifierCell, Fonts.BODY, L.INTERRUPT_CLAIM_MODIFIER)
    modifierLabel:SetJustifyH("LEFT")
    local modifierDropdown
    modifierDropdown = Dropdown.Create(modifierCell, {
        { value = InterruptClaim.MODIFIER_SHIFT, text = L.INTERRUPT_CLAIM_MODIFIER_SHIFT },
        { value = InterruptClaim.MODIFIER_CTRL, text = L.INTERRUPT_CLAIM_MODIFIER_CTRL },
        { value = InterruptClaim.MODIFIER_ALT, text = L.INTERRUPT_CLAIM_MODIFIER_ALT },
    }, function(modifier)
        if not InterruptClaim:IsEnabled() then
            return
        end
        InterruptClaim:SetModifier(modifier)
        modifierDropdown:SetSelected(InterruptClaim:GetModifier())
        UpdateBindStatus()
        RefreshPageHeight()
    end)
    modifierDropdown:SetSelected(InterruptClaim:GetModifier())
    Layout.Row(modifierCell, { modifierLabel, modifierDropdown }, Spacing.LARGE)

    local mouseLabel = Widgets.CreateLabel(mouseCell, Fonts.BODY, L.INTERRUPT_CLAIM_MOUSE_BUTTON)
    mouseLabel:SetJustifyH("LEFT")
    local mouseDropdown
    mouseDropdown = Dropdown.Create(mouseCell, {
        { value = InterruptClaim.MOUSE_LEFT, text = L.INTERRUPT_CLAIM_MOUSE_LEFT },
        { value = InterruptClaim.MOUSE_RIGHT, text = L.INTERRUPT_CLAIM_MOUSE_RIGHT },
    }, function(mouseButton)
        if not InterruptClaim:IsEnabled() then
            return
        end
        InterruptClaim:SetMouseButton(mouseButton)
        mouseDropdown:SetSelected(InterruptClaim:GetMouseButton())
        UpdateBindStatus()
        RefreshPageHeight()
    end)
    mouseDropdown:SetSelected(InterruptClaim:GetMouseButton())
    Layout.Row(mouseCell, { mouseLabel, mouseDropdown }, Spacing.LARGE)

    local targetRow = shortcutBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local targetBox = AddCheckbox(targetRow, L.INTERRUPT_CLAIM_BIND_TARGET_FRAME, function(checked)
        InterruptClaim:SetBindTargetFrame(checked)
        UpdateBindStatus()
        RefreshPageHeight()
    end)
    targetBox:SetChecked(InterruptClaim:IsTargetFrameBound())
    Widgets.AttachTooltip(targetBox, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.INTERRUPT_CLAIM_BIND_TARGET_FRAME_TOOLTIP)
    end)

    bindStatusRow = shortcutBody:AddRow(14)
    bindStatus = Widgets.CreateLabel(bindStatusRow, Fonts.TINY_MUTED)
    bindStatus:SetJustifyH("LEFT")
    bindStatus:SetTextColor(Widgets.UnpackColor(Colors.WARNING))
    bindStatus:SetPoint("LEFT", bindStatusRow, "LEFT")
    bindStatus:SetPoint("RIGHT", bindStatusRow, "RIGHT")

    shortcutSection:SetContentHeight(shortcutBody:GetHeight())
end

local function BuildClaimSection()
    claimSection = FeatureSection.Create(body, {
        title = L.INTERRUPT_CLAIM_SECTION_CLAIM,
        toggle = false,
        divider = true,
        spacingBefore = Spacing.LARGE,
    })
    local raidNote = CreateFrame("Frame", nil, claimSection)
    function raidNote:SetEnabled() end
    local raidNoteLabel = Widgets.CreateLabel(raidNote, Fonts.TINY_MUTED, L.INTERRUPT_CLAIM_RAID_NOTE)
    raidNoteLabel:SetJustifyH("RIGHT")
    raidNoteLabel:SetPoint("RIGHT")
    raidNote:SetSize(raidNoteLabel:GetStringWidth(), Sizes.CONTROL_HEIGHT)
    claimSection:SetHeaderAction(raidNote)
    claimBody = Layout.Stack(claimSection.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    local markerToggleRow = claimBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local markerBox = AddCheckbox(markerToggleRow, L.INTERRUPT_CLAIM_SET_MARKER, function(checked)
        InterruptClaim:SetSetMarker(checked)
        RefreshDependentRows()
    end)
    markerBox:SetChecked(InterruptClaim:ShouldSetMarker())

    markerRow = claimBody:AddRow(MarkerGridHeight())
    markerCells = {}
    for marker = InterruptClaim.MARKER_MIN, InterruptClaim.MARKER_MAX do
        local cell = CreateFrame("Button", nil, markerRow, Assets.Templates.BACKDROP)
        cell:SetSize(MARKER_CELL_SIZE, MARKER_CELL_SIZE)
        local x, y = Layout.GridCell(marker, MARKER_COLUMNS, MARKER_CELL_STEP, MARKER_CELL_STEP)
        cell:SetPoint("TOPLEFT", markerRow, "TOPLEFT", x, y)
        Widgets.AddHoverHighlight(cell)
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(MARKER_ICON_SIZE, MARKER_ICON_SIZE)
        icon:SetPoint("CENTER")
        icon:SetTexture(InterruptClaim.GetRaidMarkerIcon(marker))
        cell:SetScript("OnClick", function()
            if not InterruptClaim:IsEnabled() then
                return
            end
            InterruptClaim:SetMarker(marker)
        end)
        markerCells[marker] = cell
    end

    announceRow = claimBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local announceLabel = Widgets.CreateLabel(announceRow, Fonts.BODY, L.INTERRUPT_CLAIM_ANNOUNCE)
    announceLabel:SetJustifyH("LEFT")
    announceControl = Widgets.CreateSegmentedControl(announceRow, {
        { value = InterruptClaim.ANNOUNCE_OFF, text = L.INTERRUPT_CLAIM_ANNOUNCE_OFF },
        { value = InterruptClaim.CHANNEL_PARTY, text = L.INTERRUPT_CLAIM_CHANNEL_PARTY },
        { value = InterruptClaim.CHANNEL_SAY, text = L.INTERRUPT_CLAIM_CHANNEL_SAY },
        { value = InterruptClaim.CHANNEL_EMOTE, text = L.INTERRUPT_CLAIM_CHANNEL_EMOTE },
    }, function(announce)
        if not InterruptClaim:IsEnabled() then
            return
        end
        InterruptClaim:SetAnnounce(announce)
        announceControl:SetSelected(InterruptClaim:GetAnnounce())
    end)
    announceControl:SetSelected(InterruptClaim:GetAnnounce())
    Layout.Row(announceRow, { announceLabel, announceControl }, Spacing.LARGE)

    local clearEmptyRow = claimBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local clearEmptyBox = AddCheckbox(clearEmptyRow, L.INTERRUPT_CLAIM_CLEAR_FOCUS_ON_EMPTY, function(checked)
        InterruptClaim:SetClearFocusOnEmpty(checked)
    end)
    clearEmptyBox:SetChecked(InterruptClaim:ShouldClearFocusOnEmpty())

    claimSection:SetContentHeight(claimBody:GetHeight())
end

local function BuildMacroRow()
    macroRow = body:AddRow(ActionRow.HEIGHT, Spacing.LARGE)
    local buttons = ActionRow.Apply(macroRow, {
        title = string.format(L.INTERRUPT_CLAIM_MACRO_TITLE, InterruptClaim.GetFocusMacroName()),
        description = L.INTERRUPT_CLAIM_MACRO_MISSING,
        buttons = {
            {
                text = L.INTERRUPT_CLAIM_MACRO_CREATE,
                variant = "primary",
                onClick = function()
                    if not InterruptClaim:IsEnabled() or InterruptClaim:HasFocusMacro() then
                        return
                    end
                    local ok, reason = InterruptClaim:CreateFocusMacro()
                    if not ok then
                        SetMacroDescription(FailureMessage(reason), Colors.ERROR)
                        return
                    end
                    RefreshPageHeight()
                    UpdateMacroUi()
                end,
            },
        },
    })
    createButton = buttons[1]
    -- FeatureSection re-enables descendants when the page is on. Keep create locked
    -- while an account-wide NETFocus already occupies the name.
    local rawSetEnabled = createButton.SetEnabled
    function createButton:SetEnabled(enabled)
        rawSetEnabled(
            self,
            enabled == true and InterruptClaim:GetFocusMacroStatus() == InterruptClaim.MACRO_STATUS_MISSING
        )
    end
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    page = content
    body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    BuildShortcutSection()
    BuildClaimSection()
    BuildMacroRow()
    InterruptClaim:SyncFocusMacro()
    RefreshDependentRows()

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    container:RefreshContentInteractive()
    UpdateMacroUi()
    return height
end

function InterruptClaim:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.INTERRUPT_CLAIM_TITLE,
        tooltip = L.INTERRUPT_CLAIM_HINT,
        group = ns.PanelGroups.COMBAT,
        enabled = InterruptClaim:IsEnabled(),
        onEnabledChanged = function(enabled)
            InterruptClaim:SetEnabled(enabled)
        end,
        build = Build,
    })
    self:ListenForMacros()
    self:SyncFocusMacro()
    ns.Modules.Internals("InterruptClaim").NameplateClicks.Start()
    ns.Modules.Internals("InterruptClaim").TargetFrameClicks.Start()
    ns.Modules.Internals("InterruptClaim").WorldClicks.Start()
end

function InterruptClaim:OnMacrosChanged()
    RefreshPageHeight()
    UpdateMacroUi()
end

function InterruptClaim:OnSettingsChanged()
    RefreshDependentRows()
end
