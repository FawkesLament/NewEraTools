local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local NumberStepper = ns.NumberStepper
local Slider = ns.Slider
local Checkbox = ns.Checkbox
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CoiledAltar = ns.Modules.Get("CoiledAltar")
local InterruptRotationTracker = Internals.InterruptRotationTrackerUI
local AddonCheckPanel = ns.AddonCheckPanel
local Spell = ns.Api.Spell

local INTERRUPT_SPELL_ID = 1286399
local GHOST_CHASE_SPELL_ID = 1285911
local VULNERABILITY_SPELL_ID = 1304033
local ORB_CARRY_SPELL_ID = 1282403
local SOAK_SPELL_ID = 1283489
-- 20px icon + 8px gap + name; matches the nameplate card's two-column rhythm.
local SPELL_ICON_SIZE = 20
local SPELL_ICON_CROP = 0.08
local SPELL_HINT_GAP = 8
local REMINDER_LABEL_WIDTH = 100
local CHECKBOX_TEXT_GAP = 10
local PHASE_GROUP_GAP = 20

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

local SCOPE_ID = "coiled_altar"
local syncInterruptAssignments
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
        moduleId = CoiledAltar.ADDON_CHECK_MODULE_ID,
        name = "NewEraToolsCoiledAltarAddonCheck",
        title = L.ADDONCHECK_TITLE,
        columns = CoiledAltar.AddonCheckColumns(),
        validator = CoiledAltar.ValidateAddonCheckConfig,
        rowHeight = 32,
        listRows = 7,
    })
    return addonCheckPanel
end

local function ShowAddonCheckPanel()
    if not CoiledAltar:IsRaidCommander() then
        return
    end
    EnsureAddonCheckPanel():Show()
end

local function BeginEditPosition()
    LayoutEditor.BeginScope(SCOPE_ID)
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

---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.MEDIUM,
    })

    local editLayout = Widgets.CreateLayoutEditButton(content.header, L.COILED_ALTAR_EDIT_POSITION, BeginEditPosition)
    content:SetHeaderAction(editLayout)

    local assignments = FeatureSection.Create(body, {
        title = L.COILED_ALTAR_INTERRUPT_ASSIGNMENTS,
        divider = true,
        toggle = false,
    })
    local preferMemberView = false
    local assignmentsBody = Layout.Stack(assignments.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })
    local interruptRoleRow = assignmentsBody:AddRow(Sizes.CONTROL_HEIGHT)
    local interruptRoleLabel = ns.RaidRoleModeLabel.Create(interruptRoleRow, L.COILED_ALTAR_INTERRUPT_RAID_ROLE_TOOLTIP)
    local viewSwitch = Widgets.CreateTextButton(interruptRoleRow, L.COILED_ALTAR_INTERRUPT_VIEW_MEMBER, function()
        preferMemberView = not preferMemberView
        if syncInterruptAssignments then
            syncInterruptAssignments()
        end
    end)
    viewSwitch:SetPoint("RIGHT", interruptRoleRow, "RIGHT")

    local function NotifyAssignmentsHeight()
        assignments:SetContentHeight(assignmentsBody:GetHeight())
        content:SetContentHeight(body:GetHeight())
        assignments:RefreshContentInteractive()
    end

    local chainHost = assignmentsBody:Add(CreateFrame("Frame", nil, assignments.content), 1)
    local editorMounted
    local memberViewMounted
    local function ApplyChainHostHeight(height)
        assignmentsBody:SetEntryHeight(chainHost, height)
        NotifyAssignmentsHeight()
    end

    local function EnsureChainEditor()
        if editorMounted then
            Internals.InterruptAssignmentsUI.Refresh()
            return
        end
        Internals.InterruptAssignmentsUI.Mount(chainHost, ApplyChainHostHeight, {
            onAddonCheck = ShowAddonCheckPanel,
        })
        editorMounted = true
    end

    local function EnsureMemberView()
        if memberViewMounted then
            Internals.InterruptAssignmentsMemberView.Refresh()
            return
        end
        Internals.InterruptAssignmentsMemberView.Mount(chainHost, ApplyChainHostHeight)
        memberViewMounted = true
    end

    function syncInterruptAssignments()
        ns.RaidRoleModeLabel.Update(interruptRoleLabel)
        local canEdit = Internals.InterruptAssignments.CanEdit()
        if not canEdit then
            HideAddonCheckPanel()
        end
        local showEditor
        showEditor, preferMemberView = Internals.InterruptAssignments.ResolveSettingsView(canEdit, preferMemberView)
        viewSwitch:SetShown(canEdit)
        if canEdit then
            viewSwitch:SetText(
                preferMemberView and L.COILED_ALTAR_INTERRUPT_VIEW_EDITOR or L.COILED_ALTAR_INTERRUPT_VIEW_MEMBER
            )
            viewSwitch:SetSize(viewSwitch:GetTextWidth() + 2 * Spacing.SMALL, Sizes.CONTROL_HEIGHT)
        end
        assignmentsBody:SetEntryHeight(interruptRoleRow, Sizes.CONTROL_HEIGHT)
        if not content:IsVisible() then
            NotifyAssignmentsHeight()
            return
        end
        chainHost:Show()
        if showEditor then
            Internals.InterruptAssignmentsMemberView.SetShown(false)
            EnsureChainEditor()
            Internals.InterruptAssignmentsUI.SetShown(true)
        else
            Internals.InterruptAssignmentsUI.SetShown(false)
            EnsureMemberView()
            Internals.InterruptAssignmentsMemberView.SetShown(true)
        end
        NotifyAssignmentsHeight()
    end

    content:HookScript("OnShow", function()
        if syncInterruptAssignments then
            syncInterruptAssignments()
        end
    end)

    syncInterruptAssignments()

    local reminder = FeatureSection.Create(body, {
        title = L.COILED_ALTAR_MECHANIC_REMINDER,
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
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end)
        local hint = CreateSpellHint(cell, spellId, labelText)
        hint:SetScript("OnClick", function()
            box:Click()
        end)
        Layout.Row(cell, { hint, box }, 0)
    end

    local reminderRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local interruptCell, ghostChaseCell = Layout.SplitRow(reminderRow, Spacing.MEDIUM)
    AddReminderCheckbox(interruptCell, function()
        return CoiledAltar:IsInterruptReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetInterruptReminderEnabled(enabled)
    end, L.COILED_ALTAR_INTERRUPT_REMINDER, INTERRUPT_SPELL_ID)
    AddReminderCheckbox(ghostChaseCell, function()
        return CoiledAltar:IsGhostChaseReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetGhostChaseReminderEnabled(enabled)
    end, L.COILED_ALTAR_GHOST_CHASE_REMINDER, GHOST_CHASE_SPELL_ID)

    local vulnerabilityRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local vulnerabilityCell = Layout.SplitRow(vulnerabilityRow, Spacing.MEDIUM)
    AddReminderCheckbox(vulnerabilityCell, function()
        return CoiledAltar:IsVulnerabilityReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetVulnerabilityReminderEnabled(enabled)
    end, L.COILED_ALTAR_VULNERABILITY_REMINDER, VULNERABILITY_SPELL_ID)

    ---@param cell Frame
    ---@param isEnabled fun(): boolean
    ---@param setEnabled fun(enabled: boolean)
    ---@param labelText string
    ---@return Frame
    local function AddLabeledCheckbox(cell, isEnabled, setEnabled, labelText)
        local group = CreateFrame("Frame", nil, cell)
        local box = Checkbox.Create(group)
        box:SetChecked(isEnabled())
        box:SetScript("OnClick", function(self)
            setEnabled(self:GetChecked())
            self:SetChecked(isEnabled())
        end)
        local label = Widgets.CreateLabel(group, Fonts.BODY, labelText)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Layout.Row(group, { box, label }, CHECKBOX_TEXT_GAP)
        local labelWidth = label:GetStringWidth() or 0
        box:SetHitRectInsets(0, -(labelWidth + CHECKBOX_TEXT_GAP), 0, 0)
        group:SetSize(Sizes.CHECKBOX + CHECKBOX_TEXT_GAP + labelWidth, Sizes.CONTROL_ROW_HEIGHT)
        return group
    end

    local orbRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local orbHint = CreateSpellHint(orbRow, ORB_CARRY_SPELL_ID, L.COILED_ALTAR_ORB_CARRY_REMINDER)
    local oddGroup = AddLabeledCheckbox(orbRow, function()
        return CoiledAltar:IsOrbCarryOddReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetOrbCarryOddReminderEnabled(enabled)
    end, L.COILED_ALTAR_ORB_CARRY_ODD_WAVE)
    local evenGroup = AddLabeledCheckbox(orbRow, function()
        return CoiledAltar:IsOrbCarryEvenReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetOrbCarryEvenReminderEnabled(enabled)
    end, L.COILED_ALTAR_ORB_CARRY_EVEN_WAVE)
    local p3Group = AddLabeledCheckbox(orbRow, function()
        return CoiledAltar:IsOrbCarryP3ReminderEnabled()
    end, function(enabled)
        CoiledAltar:SetOrbCarryP3ReminderEnabled(enabled)
    end, L.COILED_ALTAR_ORB_CARRY_P3)
    Layout.Row(orbRow, { orbHint, oddGroup }, 0)
    evenGroup:ClearAllPoints()
    evenGroup:SetPoint("LEFT", oddGroup, "RIGHT", PHASE_GROUP_GAP, 0)
    p3Group:ClearAllPoints()
    p3Group:SetPoint("LEFT", evenGroup, "RIGHT", PHASE_GROUP_GAP, 0)

    ---@param row Frame
    ---@param lead Frame
    ---@param groups Frame[]
    local function PlacePhaseCheckboxes(row, lead, groups)
        Layout.Row(row, { lead, groups[1] }, 0)
        for i = 2, #groups do
            groups[i]:ClearAllPoints()
            groups[i]:SetPoint("LEFT", groups[i - 1], "RIGHT", PHASE_GROUP_GAP, 0)
        end
    end

    -- Five soak labels do not fit beside the spell hint; wrap P3 under the checkbox column.
    local soakP1Row = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local soakHint = CreateSpellHint(soakP1Row, SOAK_SPELL_ID, L.COILED_ALTAR_SOAK_REMINDER)
    local soakP1Groups = {
        AddLabeledCheckbox(soakP1Row, function()
            return CoiledAltar:IsSoakP1FirstReminderEnabled()
        end, function(enabled)
            CoiledAltar:SetSoakP1FirstReminderEnabled(enabled)
        end, L.COILED_ALTAR_SOAK_P1_FIRST),
        AddLabeledCheckbox(soakP1Row, function()
            return CoiledAltar:IsSoakP1SecondReminderEnabled()
        end, function(enabled)
            CoiledAltar:SetSoakP1SecondReminderEnabled(enabled)
        end, L.COILED_ALTAR_SOAK_P1_SECOND),
    }
    PlacePhaseCheckboxes(soakP1Row, soakHint, soakP1Groups)

    local soakP3Row = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local soakIndent = CreateFrame("Frame", nil, soakP3Row)
    soakIndent:SetSize(REMINDER_LABEL_WIDTH, Sizes.CONTROL_ROW_HEIGHT)
    local soakP3Groups = {
        AddLabeledCheckbox(soakP3Row, function()
            return CoiledAltar:IsSoakP3FirstReminderEnabled()
        end, function(enabled)
            CoiledAltar:SetSoakP3FirstReminderEnabled(enabled)
        end, L.COILED_ALTAR_SOAK_P3_FIRST),
        AddLabeledCheckbox(soakP3Row, function()
            return CoiledAltar:IsSoakP3SecondReminderEnabled()
        end, function(enabled)
            CoiledAltar:SetSoakP3SecondReminderEnabled(enabled)
        end, L.COILED_ALTAR_SOAK_P3_SECOND),
        AddLabeledCheckbox(soakP3Row, function()
            return CoiledAltar:IsSoakP3ThirdReminderEnabled()
        end, function(enabled)
            CoiledAltar:SetSoakP3ThirdReminderEnabled(enabled)
        end, L.COILED_ALTAR_SOAK_P3_THIRD),
    }
    PlacePhaseCheckboxes(soakP3Row, soakIndent, soakP3Groups)

    reminder:SetContentHeight(reminderBody:GetHeight())
    reminder:RefreshContentInteractive()

    local hint = FeatureSection.Create(body, {
        title = L.COILED_ALTAR_NAMEPLATE_HINT,
        divider = true,
        enabled = CoiledAltar:IsNameplateHintEnabled(),
        onEnabledChanged = function(enabled)
            CoiledAltar:SetNameplateHintEnabled(enabled)
        end,
        onStackHeightChanged = function(stackHeight)
            content:SetContentHeight(stackHeight)
        end,
    })

    local previewButton = Widgets.CreateButton(hint, L.COILED_ALTAR_PREVIEW_NAMEPLATE, function()
        if not CoiledAltar:IsNameplateHintEnabled() then
            return
        end
        CoiledAltar:SetNameplateHintPreviewing(not CoiledAltar:IsNameplateHintPreviewing())
    end)
    Widgets.AttachTooltip(previewButton, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.COILED_ALTAR_PREVIEW_NAMEPLATE_TOOLTIP)
    end)

    local function SyncPreviewButton()
        previewButton:SetEnabled(CoiledAltar:IsNameplateHintEnabled())
        previewButton:SetText(
            CoiledAltar:IsNameplateHintPreviewing() and L.COILED_ALTAR_STOP_PREVIEW_NAMEPLATE
                or L.COILED_ALTAR_PREVIEW_NAMEPLATE
        )
        previewButton:SetSize(
            math.max(previewButton:GetTextWidth() + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH),
            Sizes.CONTROL_HEIGHT
        )
    end

    function CoiledAltar:OnNameplateHintChanged()
        SyncPreviewButton()
    end

    local notifyPreview = CoiledAltar.OnNameplateHintPreviewChanged
    function CoiledAltar:OnNameplateHintPreviewChanged()
        if notifyPreview then
            notifyPreview(self)
        end
        SyncPreviewButton()
    end

    hint:SetHeaderAction(previewButton)
    SyncPreviewButton()

    local hintBody = Layout.Stack(hint.content, { paddingY = Spacing.SMALL, spacing = Spacing.SMALL })

    local positionScaleRow = hintBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local positionCell, scaleCell = Layout.SplitRow(positionScaleRow, Spacing.MEDIUM)

    local positionLabel = Widgets.CreateLabel(positionCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_POSITION)
    positionLabel:SetJustifyH("LEFT")
    local positionControl
    positionControl = Widgets.CreateSegmentedControl(positionCell, {
        { value = CoiledAltar.SIDE_TOP, text = L.COILED_ALTAR_NAMEPLATE_HINT_SIDE_TOP },
        { value = CoiledAltar.SIDE_BOTTOM, text = L.COILED_ALTAR_NAMEPLATE_HINT_SIDE_BOTTOM },
    }, function(side)
        if not CoiledAltar:IsNameplateHintEnabled() then
            return
        end
        CoiledAltar:SetNameplateHintSide(side)
        positionControl:SetSelected(side)
    end)
    positionControl:SetSelected(CoiledAltar:GetNameplateHintSide())
    Layout.Row(positionCell, { positionLabel, positionControl }, Spacing.LARGE)

    local scaleLabel = Widgets.CreateLabel(scaleCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_SCALE)
    local scaleSlider = Slider.Create(
        scaleCell,
        CoiledAltar.SCALE_MIN,
        CoiledAltar.SCALE_MAX,
        CoiledAltar.SCALE_STEP,
        { percentage = true }
    )
    scaleSlider:SetValue(CoiledAltar:GetNameplateHintScale())
    scaleSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not CoiledAltar:IsNameplateHintEnabled() then
            return
        end
        CoiledAltar:SetNameplateHintScale(rawValue)
    end)
    PlaceSlider(scaleCell, scaleLabel, scaleSlider)

    local offsetRow = hintBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local offsetXCell, offsetYCell = Layout.SplitRow(offsetRow, Spacing.MEDIUM)
    local offsetXLabel = Widgets.CreateLabel(offsetXCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_OFFSET_X)
    offsetXLabel:SetJustifyH("LEFT")
    local offsetXStepper
    offsetXStepper = NumberStepper.Create(
        offsetXCell,
        CoiledAltar.OFFSET_MIN,
        CoiledAltar.OFFSET_MAX,
        CoiledAltar.OFFSET_STEP,
        function(value)
            if not CoiledAltar:IsNameplateHintEnabled() then
                offsetXStepper:SetValue(CoiledAltar:GetNameplateHintOffsetX())
                return
            end
            CoiledAltar:SetNameplateHintOffsetX(value)
        end
    )
    offsetXStepper:SetValue(CoiledAltar:GetNameplateHintOffsetX())
    Layout.Row(offsetXCell, { offsetXLabel, offsetXStepper }, Spacing.LARGE)

    local offsetYLabel = Widgets.CreateLabel(offsetYCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_OFFSET_Y)
    offsetYLabel:SetJustifyH("LEFT")
    local offsetYStepper
    offsetYStepper = NumberStepper.Create(
        offsetYCell,
        CoiledAltar.OFFSET_MIN,
        CoiledAltar.OFFSET_MAX,
        CoiledAltar.OFFSET_STEP,
        function(value)
            if not CoiledAltar:IsNameplateHintEnabled() then
                offsetYStepper:SetValue(CoiledAltar:GetNameplateHintOffsetY())
                return
            end
            CoiledAltar:SetNameplateHintOffsetY(value)
        end
    )
    offsetYStepper:SetValue(CoiledAltar:GetNameplateHintOffsetY())
    Layout.Row(offsetYCell, { offsetYLabel, offsetYStepper }, Spacing.LARGE)

    local fontSizeRow = hintBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local numberFontCell, nameFontCell = Layout.SplitRow(fontSizeRow, Spacing.MEDIUM)

    local numberFontLabel =
        Widgets.CreateLabel(numberFontCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_NUMBER_FONT_SIZE)
    local numberFontSlider = Slider.Create(
        numberFontCell,
        CoiledAltar.NUMBER_FONT_SIZE_MIN,
        CoiledAltar.NUMBER_FONT_SIZE_MAX,
        CoiledAltar.NUMBER_FONT_SIZE_STEP
    )
    numberFontSlider:SetValue(CoiledAltar:GetNameplateHintNumberFontSize())
    numberFontSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not CoiledAltar:IsNameplateHintEnabled() then
            return
        end
        CoiledAltar:SetNameplateHintNumberFontSize(rawValue)
    end)
    PlaceSlider(numberFontCell, numberFontLabel, numberFontSlider)

    local nameFontLabel = Widgets.CreateLabel(nameFontCell, Fonts.BODY, L.COILED_ALTAR_NAMEPLATE_HINT_NAME_FONT_SIZE)
    local nameFontSlider = Slider.Create(
        nameFontCell,
        CoiledAltar.NAME_FONT_SIZE_MIN,
        CoiledAltar.NAME_FONT_SIZE_MAX,
        CoiledAltar.NAME_FONT_SIZE_STEP
    )
    nameFontSlider:SetValue(CoiledAltar:GetNameplateHintNameFontSize())
    nameFontSlider:SetScript("OnValueChanged", function(_, rawValue)
        if not CoiledAltar:IsNameplateHintEnabled() then
            return
        end
        CoiledAltar:SetNameplateHintNameFontSize(rawValue)
    end)
    PlaceSlider(nameFontCell, nameFontLabel, nameFontSlider)

    hint:SetContentHeight(hintBody:GetHeight())
    hint:RefreshContentInteractive()

    -- Collapse hides this page; only closing the settings window should end previews.
    local getFrame = ns.MainPanel and ns.MainPanel.GetFrame
    local mainPanel = getFrame and ns.MainPanel:GetFrame()
    if mainPanel then
        mainPanel:HookScript("OnHide", function()
            CoiledAltar:SetNameplateHintPreviewing(false)
        end)
    end

    return body:GetHeight()
end

function CoiledAltar:OnInterruptStateChanged()
    InterruptRotationTracker.Update()
end

function CoiledAltar:OnEnable()
    LayoutEditor.RegisterScope({
        id = SCOPE_ID,
        label = L.COILED_ALTAR_LAYOUT_SCOPE,
        order = 7,
        elementIds = {
            ns.Callout.LAYOUT_ID,
            InterruptRotationTracker.LAYOUT_ID,
        },
        prepare = function()
            ns.Callout.Ensure()
            InterruptRotationTracker.Ensure()
        end,
    })
    ns.Callout.SetScopePreview(SCOPE_ID, L.COILED_ALTAR_INTERRUPT_CALLOUT, CoiledAltar.INTERRUPT_CALLOUT_DURATION)
    ns.MainPanel:RegisterSection({
        title = L.COILED_ALTAR_TITLE,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        build = BuildContent,
    })
    self:ListenForEncounter()
    self:ListenForInterruptSync()
    ns.Api.Group.OnChanged(function()
        if syncInterruptAssignments then
            syncInterruptAssignments()
        end
    end)
    InterruptRotationTracker.Ensure()
    InterruptRotationTracker.Update()
end
