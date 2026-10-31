local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local ActionRow = ns.ActionRow
local CollapsibleSection = ns.CollapsibleSection
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local ColorSwatch = ns.ColorSwatch
local Dropdown = ns.Dropdown
local NumberStepper = ns.NumberStepper
local Slider = ns.Slider
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local SoakTimeline = Internals.SoakTimeline
local InterruptStatusHud = Internals.InterruptStatusHudUI
local SoakTimelineHud = Internals.SoakTimelineUI
local AddonCheckPanel = ns.AddonCheckPanel

local SCOPE_ID = "twin_fangs"
local interruptRoleLabel
local syncInterruptChainEditor
local syncTestButton
local addonCheckRow
local addonCheckButton
---@type AddonCheckPanel|nil
local addonCheckPanel

local function HideAddonCheckPanel()
    if addonCheckPanel then
        addonCheckPanel:Hide()
    end
end

local function EnsureAddonCheckPanel()
    if addonCheckPanel then
        return addonCheckPanel
    end
    addonCheckPanel = AddonCheckPanel.Create({
        moduleId = TwinFangs.ADDON_CHECK_MODULE_ID,
        name = "NewEraToolsTwinFangsAddonCheck",
        title = L.ADDONCHECK_TITLE,
        columns = TwinFangs.AddonCheckColumns(),
        validator = TwinFangs.ValidateAddonCheckConfig,
        rowHeight = 32,
        listRows = 7,
    })
    return addonCheckPanel
end

local function ShowAddonCheckPanel()
    if not TwinFangs:IsRaidCommander() then
        return
    end
    EnsureAddonCheckPanel():Show()
end

local function BeginEditPosition()
    LayoutEditor.BeginScope(SCOPE_ID)
end

---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local toolsRow = body:AddRow(ActionRow.HEIGHT)
    ActionRow.Apply(toolsRow, {
        title = L.TWIN_FANGS_TOOLS_LAYOUT,
        description = L.TWIN_FANGS_TOOLS_LAYOUT_DESC,
        buttons = {
            { text = L.TWIN_FANGS_EDIT_POSITION, onClick = BeginEditPosition, layout = true },
        },
    })

    addonCheckRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    addonCheckButton = Widgets.CreateButton(addonCheckRow, L.ADDONCHECK_BUTTON, function()
        if not TwinFangs:IsRaidCommander() then
            return
        end
        ShowAddonCheckPanel()
    end, "primary")
    Widgets.AttachTooltip(addonCheckButton, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.ADDONCHECK_BUTTON_TOOLTIP)
    end)
    addonCheckButton:SetPoint("LEFT", addonCheckRow, "LEFT")

    content:HookScript("OnShow", function()
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end)
    -- Collapse hides this page; only closing the settings window should end previews.
    local getFrame = ns.MainPanel and ns.MainPanel.GetFrame
    local mainPanel = getFrame and ns.MainPanel:GetFrame()
    if mainPanel then
        mainPanel:HookScript("OnHide", function()
            TwinFangs:SetNameplateHintPreviewing(false)
            TwinFangs:SetInterruptStatusTestMode(false)
        end)
    end

    local soak = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_SOAK_REMINDER,
        titleFont = Fonts.MUTED,
        divider = true,
        enabled = TwinFangs:IsSoakReminderEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetSoakReminderEnabled(enabled)
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
    })
    local soakBody = Layout.Stack(soak.content, { paddingY = Spacing.SMALL })
    local groupRow = soakBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local groupCell, timelineCell = Layout.SplitRow(groupRow, Spacing.LARGE)
    local groupLabel = Widgets.CreateLabel(groupCell, Fonts.BODY, L.TWIN_FANGS_SOAK_GROUP)
    groupLabel:SetJustifyH("LEFT")
    local groupControl
    groupControl = Widgets.CreateSegmentedControl(groupCell, {
        { value = Schema.GROUP_LEFT, text = L.TWIN_FANGS_SOAK_GROUP_LEFT },
        { value = Schema.GROUP_MIDDLE, text = L.TWIN_FANGS_SOAK_GROUP_MIDDLE },
        { value = Schema.GROUP_RIGHT, text = L.TWIN_FANGS_SOAK_GROUP_RIGHT },
    }, function(group)
        if not TwinFangs:IsSoakReminderEnabled() then
            return
        end
        TwinFangs:SetSoakGroup(group)
        groupControl:SetSelected(group)
    end)
    groupControl:SetSelected(TwinFangs:GetSoakGroup())
    Layout.Row(groupCell, { groupLabel, groupControl }, Spacing.LARGE)

    local timelineBox = Widgets.CreateCheckbox(timelineCell)
    timelineBox:SetChecked(TwinFangs:IsSoakTimelineEnabled())
    timelineBox:SetScript("OnClick", function(self)
        if not TwinFangs:IsSoakReminderEnabled() then
            self:SetChecked(TwinFangs:IsSoakTimelineEnabled())
            return
        end
        TwinFangs:SetSoakTimelineEnabled(self:GetChecked())
        self:SetChecked(TwinFangs:IsSoakTimelineEnabled())
        if LayoutEditor.IsEditing() then
            LayoutEditor.Refresh()
        end
    end)
    local timelineLabel = Widgets.CreateLabel(timelineCell, Fonts.BODY, L.TWIN_FANGS_SOAK_TIMELINE_SHOW)
    timelineLabel:SetJustifyH("LEFT")
    timelineLabel:SetWordWrap(false)
    Layout.Row(timelineCell, { timelineBox, timelineLabel }, Spacing.SMALL)
    timelineBox:SetHitRectInsets(0, -(timelineLabel:GetStringWidth() + Spacing.SMALL), 0, 0)

    soak:SetContentHeight(soakBody:GetHeight())
    soak:RefreshContentInteractive()

    local interrupt = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_INTERRUPT_REMINDER,
        titleFont = Fonts.MUTED,
        divider = true,
        enabled = TwinFangs:IsInterruptReminderEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetInterruptReminderEnabled(enabled)
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
    })
    local testButton = Widgets.CreateButton(interrupt, L.TWIN_FANGS_TEST_INTERRUPT_STATUS, function()
        if not TwinFangs:IsInterruptReminderEnabled() then
            return
        end
        if not TwinFangs:IsInterruptStatusTestMode() and not ns.Api.Group.IsInRaid() then
            return
        end
        TwinFangs:SetInterruptStatusTestMode(not TwinFangs:IsInterruptStatusTestMode())
    end)
    local rawTestSetEnabled = testButton.SetEnabled
    function testButton:SetEnabled(enabled)
        rawTestSetEnabled(self, enabled == true and (ns.Api.Group.IsInRaid() or TwinFangs:IsInterruptStatusTestMode()))
    end
    Widgets.AttachTooltip(testButton, "ANCHOR_TOP", function(tooltip)
        if not ns.Api.Group.IsInRaid() and not TwinFangs:IsInterruptStatusTestMode() then
            tooltip:SetText(L.TWIN_FANGS_INTERRUPT_NOT_IN_RAID)
        end
    end)
    local function SyncTestButton()
        testButton:SetEnabled(TwinFangs:IsInterruptReminderEnabled())
        testButton:SetText(
            TwinFangs:IsInterruptStatusTestMode() and L.TWIN_FANGS_STOP_TEST_INTERRUPT_STATUS
                or L.TWIN_FANGS_TEST_INTERRUPT_STATUS
        )
    end
    syncTestButton = SyncTestButton
    function TwinFangs:OnInterruptReminderChanged()
        SyncTestButton()
    end
    function TwinFangs:OnInterruptStatusTestModeChanged()
        SyncTestButton()
    end
    interrupt:SetHeaderAction(testButton)
    SyncTestButton()

    local interruptBody = Layout.Stack(interrupt.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })
    local interruptRoleRow = interruptBody:AddRow(Sizes.CONTROL_HEIGHT)
    interruptRoleLabel = ns.RaidRoleModeLabel.Create(interruptRoleRow, L.TWIN_FANGS_INTERRUPT_RAID_ROLE_TOOLTIP)
    local preferMemberView = false
    local viewSwitch = Widgets.CreateTextButton(interruptRoleRow, L.TWIN_FANGS_INTERRUPT_VIEW_MEMBER, function()
        preferMemberView = not preferMemberView
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end)
    viewSwitch:SetPoint("RIGHT", interruptRoleRow, "RIGHT")

    local chainHost = interruptBody:Add(CreateFrame("Frame", nil, interrupt.content), 1)
    local editorMounted
    local memberViewMounted
    local function ApplyChainHostHeight(height)
        interruptBody:SetEntryHeight(chainHost, height)
        interrupt:SetContentHeight(interruptBody:GetHeight())
        content:SetContentHeight(body:GetHeight())
        interrupt:RefreshContentInteractive()
    end

    local function EnsureChainEditor()
        if editorMounted then
            Internals.InterruptChainEditor.Refresh()
            return
        end
        Internals.InterruptChainEditor.Mount(chainHost, ApplyChainHostHeight)
        editorMounted = true
    end

    local function EnsureMemberView()
        if memberViewMounted then
            Internals.InterruptChainMemberView.Refresh()
            return
        end
        Internals.InterruptChainMemberView.Mount(chainHost, ApplyChainHostHeight)
        memberViewMounted = true
    end

    function syncInterruptChainEditor()
        if interruptRoleLabel then
            ns.RaidRoleModeLabel.Update(interruptRoleLabel)
        end
        local canEdit = Internals.InterruptChain.CanEdit()
        local isCommander = TwinFangs:IsRaidCommander()
        if addonCheckRow then
            addonCheckRow:SetShown(isCommander)
            body:SetEntryHeight(addonCheckRow, isCommander and Sizes.CONTROL_ROW_HEIGHT or 0)
        end
        if addonCheckButton then
            addonCheckButton:SetShown(isCommander)
        end
        if not isCommander then
            HideAddonCheckPanel()
        end
        local showEditor
        showEditor, preferMemberView = Internals.InterruptChain.ResolveSettingsView(canEdit, preferMemberView)
        viewSwitch:SetShown(canEdit)
        if canEdit then
            viewSwitch:SetText(
                preferMemberView and L.TWIN_FANGS_INTERRUPT_VIEW_EDITOR or L.TWIN_FANGS_INTERRUPT_VIEW_MEMBER
            )
            viewSwitch:SetSize(viewSwitch:GetTextWidth() + 2 * Spacing.SMALL, Sizes.CONTROL_HEIGHT)
        end
        -- Frames mounted under a hidden page keep an unresolved rect until hidden and shown again.
        -- Role changes can arrive while the page is closed; its OnShow runs this again.
        if not content:IsVisible() then
            return
        end
        chainHost:Show()
        if showEditor then
            Internals.InterruptChainMemberView.SetShown(false)
            EnsureChainEditor()
            Internals.InterruptChainEditor.SetShown(true)
        else
            Internals.InterruptChainEditor.SetShown(false)
            EnsureMemberView()
            Internals.InterruptChainMemberView.SetShown(true)
        end
        interrupt:SetContentHeight(interruptBody:GetHeight())
        content:SetContentHeight(body:GetHeight())
        interrupt:RefreshContentInteractive()
    end

    syncInterruptChainEditor()

    interrupt:SetContentHeight(interruptBody:GetHeight())
    interrupt:RefreshContentInteractive()

    local hint = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_NAMEPLATE_HINT,
        titleFont = Fonts.MUTED,
        tooltip = L.TWIN_FANGS_NAMEPLATE_HINT_TOOLTIP,
        divider = true,
        enabled = TwinFangs:IsNameplateHintEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetNameplateHintEnabled(enabled)
        end,
    })
    local hintHeaderActions = CreateFrame("Frame", nil, hint)
    hintHeaderActions:SetHeight(Sizes.CONTROL_HEIGHT)
    local previewButton = Widgets.CreateButton(hintHeaderActions, L.TWIN_FANGS_PREVIEW_NAMEPLATE, function()
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintPreviewing(not TwinFangs:IsNameplateHintPreviewing())
    end)
    Widgets.AttachTooltip(previewButton, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.TWIN_FANGS_PREVIEW_NAMEPLATE_TOOLTIP)
    end)
    local function LayoutHintHeaderActions()
        local reset = hintHeaderActions.resetButton
        local width = previewButton:GetWidth()
        if reset then
            width = width + Spacing.MEDIUM + reset:GetWidth()
        end
        hintHeaderActions:SetWidth(width)
    end
    local function SyncPreviewButton()
        previewButton:SetEnabled(TwinFangs:IsNameplateHintEnabled())
        previewButton:SetText(
            TwinFangs:IsNameplateHintPreviewing() and L.TWIN_FANGS_STOP_PREVIEW_NAMEPLATE
                or L.TWIN_FANGS_PREVIEW_NAMEPLATE
        )
        previewButton:SetSize(
            math.max(previewButton:GetTextWidth() + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH),
            Sizes.CONTROL_HEIGHT
        )
        LayoutHintHeaderActions()
    end
    function TwinFangs:OnNameplateHintChanged()
        SyncPreviewButton()
    end
    local notifyPreview = TwinFangs.OnNameplateHintPreviewChanged
    function TwinFangs:OnNameplateHintPreviewChanged()
        if notifyPreview then
            notifyPreview(self)
        end
        SyncPreviewButton()
    end
    function hintHeaderActions:SetEnabled(enabled)
        previewButton:SetEnabled(enabled)
        if self.resetButton then
            self.resetButton:SetEnabled(enabled)
        end
    end
    local hintBody = Layout.Stack(hint.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    local function SyncHintLayout()
        hint:SetContentHeight(hintBody:GetHeight())
        content:SetContentHeight(body:GetHeight())
    end

    ---@param row Frame
    ---@param label FontString
    ---@param slider SliderControl
    local function PlaceSlider(row, label, slider)
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", row, "LEFT")
        local box = slider.valueBox
        local suffix = slider.valueSuffix
        if suffix then
            suffix:ClearAllPoints()
            suffix:SetPoint("RIGHT", row, "RIGHT")
            box:ClearAllPoints()
            box:SetPoint("RIGHT", suffix, "LEFT", -Spacing.TINY, 0)
        else
            box:ClearAllPoints()
            box:SetPoint("RIGHT", row, "RIGHT")
        end
        slider:ClearAllPoints()
        slider:SetPoint("LEFT", label, "RIGHT", Spacing.LARGE, 0)
        slider:SetPoint("RIGHT", box, "LEFT", -Spacing.MEDIUM, 0)
    end

    local positionSizeRow = hintBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local positionCell, sizeCell = Layout.SplitRow(positionSizeRow, Spacing.MEDIUM)

    local positionLabel = Widgets.CreateLabel(positionCell, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_POSITION)
    positionLabel:SetJustifyH("LEFT")
    local positionControl
    positionControl = Widgets.CreateSegmentedControl(positionCell, {
        { value = Schema.SIDE_LEFT, text = L.TWIN_FANGS_NAMEPLATE_HINT_SIDE_LEFT },
        { value = Schema.SIDE_RIGHT, text = L.TWIN_FANGS_NAMEPLATE_HINT_SIDE_RIGHT },
        { value = Schema.SIDE_TOP, text = L.TWIN_FANGS_NAMEPLATE_HINT_SIDE_TOP },
        { value = Schema.SIDE_BOTTOM, text = L.TWIN_FANGS_NAMEPLATE_HINT_SIDE_BOTTOM },
    }, function(side)
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintSide(side)
        positionControl:SetSelected(side)
    end)
    positionControl:SetSelected(TwinFangs:GetNameplateHintSide())
    Layout.Row(positionCell, { positionLabel, positionControl }, Spacing.LARGE)

    local sizeLabel = Widgets.CreateLabel(sizeCell, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_SIZE)
    local sizeSlider = Slider.Create(sizeCell, Schema.SIZE_MIN, Schema.SIZE_MAX, Schema.SIZE_STEP)
    sizeSlider:SetValue(TwinFangs:GetNameplateHintSize())
    sizeSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintSize(rawValue)
    end)
    PlaceSlider(sizeCell, sizeLabel, sizeSlider)

    local offsetRow = hintBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local offsetXCell, offsetYCell = Layout.SplitRow(offsetRow, Spacing.MEDIUM)
    local offsetXLabel = Widgets.CreateLabel(offsetXCell, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_OFFSET_X)
    offsetXLabel:SetJustifyH("LEFT")
    local offsetXStepper
    offsetXStepper = NumberStepper.Create(
        offsetXCell,
        Schema.OFFSET_MIN,
        Schema.OFFSET_MAX,
        Schema.OFFSET_STEP,
        function(value)
            if not TwinFangs:IsNameplateHintEnabled() then
                offsetXStepper:SetValue(TwinFangs:GetNameplateHintOffsetX())
                return
            end
            TwinFangs:SetNameplateHintOffsetX(value)
        end
    )
    offsetXStepper:SetValue(TwinFangs:GetNameplateHintOffsetX())
    Layout.Row(offsetXCell, { offsetXLabel, offsetXStepper }, Spacing.LARGE)

    local offsetYLabel = Widgets.CreateLabel(offsetYCell, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_OFFSET_Y)
    offsetYLabel:SetJustifyH("LEFT")
    local offsetYStepper
    offsetYStepper = NumberStepper.Create(
        offsetYCell,
        Schema.OFFSET_MIN,
        Schema.OFFSET_MAX,
        Schema.OFFSET_STEP,
        function(value)
            if not TwinFangs:IsNameplateHintEnabled() then
                offsetYStepper:SetValue(TwinFangs:GetNameplateHintOffsetY())
                return
            end
            TwinFangs:SetNameplateHintOffsetY(value)
        end
    )
    offsetYStepper:SetValue(TwinFangs:GetNameplateHintOffsetY())
    Layout.Row(offsetYCell, { offsetYLabel, offsetYStepper }, Spacing.LARGE)

    local advanced = CollapsibleSection.Create(hintBody, {
        title = L.TWIN_FANGS_NAMEPLATE_HINT_ADVANCED,
        expanded = false,
        onStackHeightChanged = function()
            SyncHintLayout()
        end,
    })
    local advancedBody = Layout.Stack(advanced.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })
    local opacityRow = advancedBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local opacityLabel = Widgets.CreateLabel(opacityRow, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_OPACITY)
    local opacitySlider =
        Slider.Create(opacityRow, Schema.OPACITY_MIN, Schema.OPACITY_MAX, Schema.OPACITY_STEP, { percentage = true })
    opacitySlider:SetValue(TwinFangs:GetNameplateHintOpacity())
    opacitySlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintOpacity(rawValue)
    end)
    PlaceSlider(opacityRow, opacityLabel, opacitySlider)

    local fontRow = advancedBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontCell, fontSizeCell = Layout.SplitRow(fontRow, Spacing.MEDIUM)
    local fontDropdown
    fontDropdown = Dropdown.CreateFont(fontCell, L.TWIN_FANGS_NAMEPLATE_HINT_FONT, function(font)
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintFont(font)
        fontDropdown:SetSelected(font)
    end)
    fontDropdown:SetSelected(TwinFangs:GetNameplateHintFont())

    local fontSizeLabel = Widgets.CreateLabel(fontSizeCell, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_FONT_SIZE)
    fontSizeLabel:SetJustifyH("LEFT")
    local fontSizeSlider =
        Slider.Create(fontSizeCell, Schema.FONT_SIZE_MIN, Schema.FONT_SIZE_MAX, Schema.FONT_SIZE_STEP)
    fontSizeSlider:SetValue(TwinFangs:GetNameplateHintFontSize())
    fontSizeSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:SetNameplateHintFontSize(rawValue)
    end)
    Layout.Row(fontSizeCell, { fontSizeLabel, fontSizeSlider }, Spacing.LARGE)

    local fontColorRow = advancedBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local fontColorLabel = Widgets.CreateLabel(fontColorRow, Fonts.BODY, L.TWIN_FANGS_NAMEPLATE_HINT_FONT_COLOR)
    fontColorLabel:SetJustifyH("LEFT")
    local fontColorSwatch
    fontColorSwatch = ColorSwatch.Create(fontColorRow, TwinFangs:GetNameplateHintFontColor(), function(color)
        if not TwinFangs:IsNameplateHintEnabled() then
            fontColorSwatch:SetColor(TwinFangs:GetNameplateHintFontColor())
            return
        end
        TwinFangs:SetNameplateHintFontColor(color)
        fontColorSwatch:SetColor(TwinFangs:GetNameplateHintFontColor())
    end)
    Layout.Row(fontColorRow, { fontColorLabel, fontColorSwatch }, Spacing.LARGE)
    advanced:SetContentHeight(advancedBody:GetHeight())

    local resetButton = Widgets.CreateTextButton(hintHeaderActions, L.TWIN_FANGS_NAMEPLATE_HINT_RESET, function()
        if not TwinFangs:IsNameplateHintEnabled() then
            return
        end
        TwinFangs:ResetNameplateHintAppearance()
        positionControl:SetSelected(TwinFangs:GetNameplateHintSide())
        sizeSlider:SetValue(TwinFangs:GetNameplateHintSize())
        offsetXStepper:SetValue(TwinFangs:GetNameplateHintOffsetX())
        offsetYStepper:SetValue(TwinFangs:GetNameplateHintOffsetY())
        opacitySlider:SetValue(TwinFangs:GetNameplateHintOpacity())
        fontDropdown:RefreshItems()
        fontDropdown:SetSelected(TwinFangs:GetNameplateHintFont())
        fontSizeSlider:SetValue(TwinFangs:GetNameplateHintFontSize())
        fontColorSwatch:SetColor(TwinFangs:GetNameplateHintFontColor())
    end)
    hintHeaderActions.resetButton = resetButton
    resetButton:SetPoint("RIGHT", hintHeaderActions, "RIGHT")
    previewButton:ClearAllPoints()
    previewButton:SetPoint("RIGHT", resetButton, "LEFT", -Spacing.MEDIUM, 0)
    hint:SetHeaderAction(hintHeaderActions)
    SyncPreviewButton()

    hint:SetContentHeight(hintBody:GetHeight())
    hint:RefreshContentInteractive()

    local venom = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_VENOM_STACKS,
        titleFont = Fonts.MUTED,
        divider = true,
        enabled = TwinFangs:IsVenomRosterEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetVenomRosterEnabled(enabled)
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
    })
    local venomBody = Layout.Stack(venom.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })
    local venomSpacingRow = venomBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local rowSpacingCell, columnSpacingCell = Layout.SplitRow(venomSpacingRow, Spacing.MEDIUM)
    local rowSpacingLabel = Widgets.CreateLabel(rowSpacingCell, Fonts.BODY, L.TWIN_FANGS_VENOM_ROSTER_ROW_SPACING)
    rowSpacingLabel:SetJustifyH("LEFT")
    local rowSpacingSlider = Slider.Create(
        rowSpacingCell,
        Schema.VENOM_ROSTER_ROW_SPACING_MIN,
        Schema.VENOM_ROSTER_ROW_SPACING_MAX,
        Schema.VENOM_ROSTER_ROW_SPACING_STEP
    )
    rowSpacingSlider:SetValue(TwinFangs:GetVenomRosterRowSpacing())
    rowSpacingSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        TwinFangs:SetVenomRosterRowSpacing(rawValue)
        rowSpacingSlider:SetValue(TwinFangs:GetVenomRosterRowSpacing())
    end)
    Layout.Row(rowSpacingCell, { rowSpacingLabel, rowSpacingSlider }, Spacing.LARGE)

    local columnSpacingLabel =
        Widgets.CreateLabel(columnSpacingCell, Fonts.BODY, L.TWIN_FANGS_VENOM_ROSTER_COLUMN_SPACING)
    columnSpacingLabel:SetJustifyH("LEFT")
    local columnSpacingSlider = Slider.Create(
        columnSpacingCell,
        Schema.VENOM_ROSTER_COLUMN_SPACING_MIN,
        Schema.VENOM_ROSTER_COLUMN_SPACING_MAX,
        Schema.VENOM_ROSTER_COLUMN_SPACING_STEP
    )
    columnSpacingSlider:SetValue(TwinFangs:GetVenomRosterColumnSpacing())
    columnSpacingSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        TwinFangs:SetVenomRosterColumnSpacing(rawValue)
        columnSpacingSlider:SetValue(TwinFangs:GetVenomRosterColumnSpacing())
    end)
    Layout.Row(columnSpacingCell, { columnSpacingLabel, columnSpacingSlider }, Spacing.LARGE)

    local nameWidthRow = venomBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local nameWidthLabel = Widgets.CreateLabel(nameWidthRow, Fonts.BODY, L.TWIN_FANGS_VENOM_ROSTER_NAME_WIDTH)
    local nameWidthSlider = Slider.Create(
        nameWidthRow,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MIN,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_MAX,
        Schema.VENOM_ROSTER_NAME_COLUMN_WIDTH_STEP
    )
    nameWidthSlider:SetValue(TwinFangs:GetVenomRosterNameColumnWidth())
    nameWidthSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        TwinFangs:SetVenomRosterNameColumnWidth(rawValue)
        nameWidthSlider:SetValue(TwinFangs:GetVenomRosterNameColumnWidth())
    end)
    PlaceSlider(nameWidthRow, nameWidthLabel, nameWidthSlider)

    local venomFontRow = venomBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local nameFontCell, stackFontCell = Layout.SplitRow(venomFontRow, Spacing.MEDIUM)
    local nameFontLabel = Widgets.CreateLabel(nameFontCell, Fonts.BODY, L.TWIN_FANGS_VENOM_ROSTER_NAME_FONT_SIZE)
    nameFontLabel:SetJustifyH("LEFT")
    local nameFontSlider = Slider.Create(
        nameFontCell,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_NAME_FONT_SIZE_STEP
    )
    nameFontSlider:SetValue(TwinFangs:GetVenomRosterNameFontSize())
    nameFontSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        TwinFangs:SetVenomRosterNameFontSize(rawValue)
        nameFontSlider:SetValue(TwinFangs:GetVenomRosterNameFontSize())
    end)
    Layout.Row(nameFontCell, { nameFontLabel, nameFontSlider }, Spacing.LARGE)

    local stackFontLabel = Widgets.CreateLabel(stackFontCell, Fonts.BODY, L.TWIN_FANGS_VENOM_ROSTER_STACK_FONT_SIZE)
    stackFontLabel:SetJustifyH("LEFT")
    local stackFontSlider = Slider.Create(
        stackFontCell,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MIN,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_MAX,
        Schema.VENOM_ROSTER_STACK_FONT_SIZE_STEP
    )
    stackFontSlider:SetValue(TwinFangs:GetVenomRosterStackFontSize())
    stackFontSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        TwinFangs:SetVenomRosterStackFontSize(rawValue)
        stackFontSlider:SetValue(TwinFangs:GetVenomRosterStackFontSize())
    end)
    Layout.Row(stackFontCell, { stackFontLabel, stackFontSlider }, Spacing.LARGE)

    venom:SetContentHeight(venomBody:GetHeight())
    venom:RefreshContentInteractive()

    return body:GetHeight()
end

function TwinFangs:OnEnable()
    LayoutEditor.RegisterScope({
        id = SCOPE_ID,
        label = L.TWIN_FANGS_LAYOUT_SCOPE,
        order = 6,
        elementIds = {
            ns.Callout.LAYOUT_ID,
            InterruptStatusHud.LAYOUT_ID,
            SoakTimelineHud.LAYOUT_ID,
            Internals.VenomRosterUI.LAYOUT_ID,
        },
        prepare = function()
            ns.Callout.Ensure()
            InterruptStatusHud.Ensure()
            SoakTimelineHud.Ensure()
            Internals.VenomRosterUI.Ensure()
        end,
    })
    local calloutKindText = {
        enter = L.TWIN_FANGS_SOAK_ENTER,
        prepare = L.TWIN_FANGS_SOAK_PREPARE,
        now = L.TWIN_FANGS_SOAK_NOW,
    }
    ns.Callout.SetScopePreview(SCOPE_ID, L.TWIN_FANGS_SOAK_ENTER, TwinFangs.HIT1_LEAD, {
        tick = function()
            SoakTimeline.BeginPreviewClock()
            local assignedHit = SoakTimeline.AssignedHitForGroup(TwinFangs:GetSoakGroup())
            local callout = SoakTimeline.PreviewCallout(SoakTimeline.PreviewElapsed(), assignedHit)
            if not callout then
                return nil
            end
            return calloutKindText[callout.kind], callout.remaining
        end,
        onEnd = function()
            SoakTimeline.EndPreviewClock()
        end,
    })
    ns.MainPanel:RegisterSection({
        title = L.TWIN_FANGS_TITLE,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        build = BuildContent,
    })
    self:ListenForEncounter()
    self:ListenForInterruptChain()
    self.OnInterruptChainChanged = function()
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end
    ns.Api.Group.OnChanged(function()
        if syncTestButton then
            syncTestButton()
        end
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end)
    InterruptStatusHud.Ensure()
    InterruptStatusHud.Update()
    SoakTimelineHud.Ensure()
    SoakTimelineHud.Update()
    Internals.VenomRosterUI.Ensure()
    Internals.VenomRosterUI.Update()
end
