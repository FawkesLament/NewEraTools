local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Assets = ns.Assets
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local NumberStepper = ns.NumberStepper
local Slider = ns.Slider
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CoiledAltar = ns.Modules.Get("CoiledAltar")
local InterruptRotationTracker = Internals.InterruptRotationTrackerUI

local SCOPE_ID = "coiled_altar"
local syncInterruptAssignments

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
        spacing = Spacing.SMALL,
    })

    local editLayout = Widgets.CreateLayoutEditButton(content.header, L.COILED_ALTAR_EDIT_POSITION, BeginEditPosition)
    content:SetHeaderAction(editLayout)

    local titleRow = body:AddRow(Sizes.CONTENT_SECTION_HEADER)
    Widgets.LayoutSectionHeader(titleRow, L.COILED_ALTAR_INTERRUPT_ASSIGNMENTS)
    local preferMemberView = false
    local viewSwitch = Widgets.CreateTextButton(titleRow, L.COILED_ALTAR_INTERRUPT_VIEW_MEMBER, function()
        preferMemberView = not preferMemberView
        if syncInterruptAssignments then
            syncInterruptAssignments()
        end
    end)
    viewSwitch:SetPoint("RIGHT", titleRow, "RIGHT")

    local interruptRoleRow = body:AddRow(ns.RaidRoleModeLabel.HEIGHT)
    local interruptRoleLabel =
        ns.RaidRoleModeLabel.Create(interruptRoleRow, L.COILED_ALTAR_INTERRUPT_RAID_ROLE_TOOLTIP)
    local addonCheck = Widgets.CreateButton(interruptRoleRow, L.ADDONCHECK_BUTTON, function() end, "primary")
    local syncStatusRow = body:AddRow(1)
    local syncStatus = Widgets.CreateLabel(syncStatusRow, Fonts.SMALL_MUTED)
    syncStatus:SetJustifyH("RIGHT")
    syncStatus:SetJustifyV("TOP")
    syncStatus:SetWordWrap(true)
    syncStatus:SetPoint("TOPLEFT")
    syncStatus:SetPoint("TOPRIGHT")
    local syncStatusKind

    local function SetSyncStatus(kind, text)
        syncStatusKind = kind
        if not text or text == "" then
            syncStatus:SetText("")
            body:SetEntryHeight(syncStatusRow, 1)
            return
        end
        syncStatus:SetText(text)
        if kind == "success" then
            syncStatus:SetTextColor(Widgets.UnpackColor(Colors.SUCCESS))
        else
            syncStatus:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
        end
        local width = math.max(content:GetWidth() or 0, 1)
        syncStatus:SetWidth(width)
        body:SetEntryHeight(syncStatusRow, math.max(syncStatus:GetStringHeight() or 0, 16))
        content:SetContentHeight(body:GetHeight())
    end

    local function ClearSyncError()
        if syncStatusKind == "error" then
            SetSyncStatus(nil)
        end
    end

    local function PublishInterruptAssignments()
        local ok, reason, issue = Internals.InterruptSync.Publish()
        local text, kind = Internals.InterruptSync.StatusText(ok, reason, issue)
        SetSyncStatus(kind, text)
    end

    local sync = Widgets.CreateButton(
        interruptRoleRow,
        L.COILED_ALTAR_INTERRUPT_SYNC,
        PublishInterruptAssignments,
        "primary"
    )
    sync:SetPoint("RIGHT", interruptRoleRow, "RIGHT")
    addonCheck:SetPoint("RIGHT", sync, "LEFT", -Spacing.SMALL, 0)

    local chainHost = body:Add(CreateFrame("Frame", nil, content), 1)
    local editorMounted
    local memberViewMounted
    local function ApplyChainHostHeight(height)
        body:SetEntryHeight(chainHost, height)
        content:SetContentHeight(body:GetHeight())
    end

    local function EnsureChainEditor()
        if editorMounted then
            Internals.InterruptAssignmentsUI.Refresh()
            return
        end
        Internals.InterruptAssignmentsUI.Mount(chainHost, ApplyChainHostHeight)
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
        local showEditor
        showEditor, preferMemberView =
            Internals.InterruptAssignments.ResolveSettingsView(canEdit, preferMemberView)
        viewSwitch:SetShown(canEdit)
        if canEdit then
            viewSwitch:SetText(
                preferMemberView and L.COILED_ALTAR_INTERRUPT_VIEW_EDITOR or L.COILED_ALTAR_INTERRUPT_VIEW_MEMBER
            )
            viewSwitch:SetSize(viewSwitch:GetTextWidth() + 2 * Spacing.SMALL, Sizes.CONTROL_HEIGHT)
        end
        addonCheck:SetShown(showEditor)
        sync:SetShown(showEditor)
        if not showEditor then
            body:SetEntryHeight(syncStatusRow, 1)
        elseif syncStatus:GetText() ~= "" then
            body:SetEntryHeight(syncStatusRow, math.max(syncStatus:GetStringHeight() or 0, 16))
        else
            body:SetEntryHeight(syncStatusRow, 1)
        end
        body:SetEntryHeight(
            interruptRoleRow,
            showEditor and Sizes.CONTROL_ROW_HEIGHT or ns.RaidRoleModeLabel.HEIGHT
        )
        if not content:IsVisible() then
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
        content:SetContentHeight(body:GetHeight())
    end

    content:HookScript("OnShow", function()
        if syncInterruptAssignments then
            syncInterruptAssignments()
        end
    end)

    syncInterruptAssignments()

    local previousAssignmentsChanged = CoiledAltar.OnInterruptAssignmentsChanged
    function CoiledAltar:OnInterruptAssignmentsChanged()
        ClearSyncError()
        if previousAssignmentsChanged then
            previousAssignmentsChanged(self)
        end
    end

    local previousSetMarkedChain = CoiledAltar.SetMarkedChain
    function CoiledAltar:SetMarkedChain(chainId)
        local changed = previousSetMarkedChain(self, chainId)
        if changed then
            ClearSyncError()
        end
        return changed
    end

    local reminder = FeatureSection.Create(body, {
        title = L.COILED_ALTAR_MECHANIC_REMINDER,
        divider = true,
        toggle = false,
    })
    local reminderBody = Layout.Stack(reminder.content, { paddingY = Spacing.SMALL })
    local interruptRow = reminderBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local interruptBox = Widgets.CreateCheckbox(interruptRow)
    interruptBox:SetChecked(CoiledAltar:IsInterruptReminderEnabled())
    interruptBox:SetScript("OnClick", function(self)
        CoiledAltar:SetInterruptReminderEnabled(self:GetChecked())
        self:SetChecked(CoiledAltar:IsInterruptReminderEnabled())
        if LayoutEditor.IsEditing() then
            LayoutEditor.Refresh()
        end
    end)
    local interruptLabel = Widgets.CreateLabel(interruptRow, Fonts.BODY, L.COILED_ALTAR_INTERRUPT_REMINDER)
    interruptLabel:SetJustifyH("LEFT")
    interruptLabel:SetWordWrap(false)
    Layout.Row(interruptRow, { interruptBox, interruptLabel }, Spacing.SMALL)
    interruptBox:SetHitRectInsets(0, -(interruptLabel:GetStringWidth() + Spacing.SMALL), 0, 0)
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
    ns.Callout.SetScopePreview(
        SCOPE_ID,
        L.COILED_ALTAR_INTERRUPT_CALLOUT,
        CoiledAltar.INTERRUPT_CALLOUT_DURATION
    )
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
