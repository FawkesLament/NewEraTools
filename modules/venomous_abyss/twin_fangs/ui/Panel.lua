local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local ActionRow = ns.ActionRow
local CollapsibleSection = ns.CollapsibleSection
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local LayoutEditor = ns.LayoutEditor
local Widgets = ns.Widgets

local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = ns.TwinFangsSchema
local Callout = ns.TwinFangsCalloutUI

local SCOPE_ID = "twin_fangs"
local interruptRoleLabel
local syncInterruptChainEditor

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
    local toolsButtons = ActionRow.Apply(toolsRow, {
        title = L.TWIN_FANGS_TOOLS_LAYOUT,
        description = L.TWIN_FANGS_TOOLS_LAYOUT_DESC,
        buttons = {
            {
                text = L.TWIN_FANGS_PREVIEW_NAMEPLATE,
                onClick = function()
                    if not TwinFangs:IsNameplateHintEnabled() then
                        return
                    end
                    TwinFangs:SetNameplateHintPreviewing(not TwinFangs:IsNameplateHintPreviewing())
                end,
            },
            { text = L.TWIN_FANGS_EDIT_POSITION, onClick = BeginEditPosition, layout = true },
        },
    })
    local previewButton = toolsButtons[1]
    Widgets.AttachTooltip(previewButton, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.TWIN_FANGS_PREVIEW_NAMEPLATE_TOOLTIP)
    end)

    local function SyncPreviewButton()
        previewButton:SetShown(TwinFangs:IsNameplateHintEnabled())
        previewButton:SetText(
            TwinFangs:IsNameplateHintPreviewing() and L.TWIN_FANGS_STOP_PREVIEW_NAMEPLATE
                or L.TWIN_FANGS_PREVIEW_NAMEPLATE
        )
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
    SyncPreviewButton()

    content:HookScript("OnShow", function()
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end)
    content:HookScript("OnHide", function()
        TwinFangs:SetNameplateHintPreviewing(false)
    end)

    local soak = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_SOAK_REMINDER,
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
    local groupLabel = Widgets.CreateLabel(groupRow, Fonts.BODY, L.TWIN_FANGS_SOAK_GROUP)
    groupLabel:SetJustifyH("LEFT")
    local groupControl
    groupControl = Widgets.CreateSegmentedControl(groupRow, {
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
    Layout.Row(groupRow, { groupLabel, groupControl }, Spacing.LARGE)
    soak:SetContentHeight(soakBody:GetHeight())
    soak:RefreshContentInteractive()

    local interrupt = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_INTERRUPT_REMINDER,
        divider = true,
        enabled = TwinFangs:IsInterruptReminderEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetInterruptReminderEnabled(enabled)
            if LayoutEditor.IsEditing() then
                LayoutEditor.Refresh()
            end
        end,
    })
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

    local voiceRow = interruptBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local voiceBox = Widgets.CreateCheckbox(voiceRow)
    voiceBox:SetChecked(TwinFangs:IsInterruptVoiceEnabled())
    voiceBox:SetScript("OnClick", function(self)
        if not TwinFangs:IsInterruptReminderEnabled() then
            self:SetChecked(TwinFangs:IsInterruptVoiceEnabled())
            return
        end
        TwinFangs:SetInterruptVoiceEnabled(self:GetChecked())
    end)
    local voiceLabel = Widgets.CreateLabel(voiceRow, Fonts.BODY, L.TWIN_FANGS_INTERRUPT_VOICE)
    voiceLabel:SetJustifyH("LEFT")
    Layout.Row(voiceRow, { voiceBox, voiceLabel }, Spacing.SMALL)
    voiceBox:SetHitRectInsets(0, -(voiceLabel:GetStringWidth() + Spacing.SMALL), 0, 0)

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
            ns.TwinFangsInterruptChainEditor.Refresh()
            return
        end
        ns.TwinFangsInterruptChainEditor.Mount(chainHost, ApplyChainHostHeight)
        editorMounted = true
    end

    local function EnsureMemberView()
        if memberViewMounted then
            ns.TwinFangsInterruptChainMemberView.Refresh()
            return
        end
        ns.TwinFangsInterruptChainMemberView.Mount(chainHost, ApplyChainHostHeight)
        memberViewMounted = true
    end

    function syncInterruptChainEditor()
        if interruptRoleLabel then
            ns.RaidRoleModeLabel.Update(interruptRoleLabel)
        end
        local canEdit = ns.TwinFangsInterruptChain.CanEdit()
        local showEditor
        showEditor, preferMemberView = ns.TwinFangsInterruptChain.ResolveSettingsView(canEdit, preferMemberView)
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
            ns.TwinFangsInterruptChainMemberView.SetShown(false)
            EnsureChainEditor()
            ns.TwinFangsInterruptChainEditor.SetShown(true)
        else
            ns.TwinFangsInterruptChainEditor.SetShown(false)
            EnsureMemberView()
            ns.TwinFangsInterruptChainMemberView.SetShown(true)
        end
    end

    syncInterruptChainEditor()

    interrupt:SetContentHeight(interruptBody:GetHeight())
    interrupt:RefreshContentInteractive()

    local hint = FeatureSection.Create(body, {
        title = L.TWIN_FANGS_NAMEPLATE_HINT,
        tooltip = L.TWIN_FANGS_NAMEPLATE_HINT_TOOLTIP,
        divider = true,
        enabled = TwinFangs:IsNameplateHintEnabled(),
        onEnabledChanged = function(enabled)
            TwinFangs:SetNameplateHintEnabled(enabled)
        end,
    })
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
    local sizeSlider = Widgets.CreateSlider(sizeCell, Schema.SIZE_MIN, Schema.SIZE_MAX, Schema.SIZE_STEP)
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
    offsetXStepper = Widgets.CreateNumberStepper(
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
    offsetYStepper = Widgets.CreateNumberStepper(
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
    local opacitySlider = Widgets.CreateSlider(
        opacityRow,
        Schema.OPACITY_MIN,
        Schema.OPACITY_MAX,
        Schema.OPACITY_STEP,
        { percentage = true }
    )
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
    fontDropdown = Widgets.CreateFontDropdown(fontCell, L.TWIN_FANGS_NAMEPLATE_HINT_FONT, function(font)
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
        Widgets.CreateSlider(fontSizeCell, Schema.FONT_SIZE_MIN, Schema.FONT_SIZE_MAX, Schema.FONT_SIZE_STEP)
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
    fontColorSwatch = Widgets.CreateColorSwatch(fontColorRow, TwinFangs:GetNameplateHintFontColor(), function(color)
        if not TwinFangs:IsNameplateHintEnabled() then
            fontColorSwatch:SetColor(TwinFangs:GetNameplateHintFontColor())
            return
        end
        TwinFangs:SetNameplateHintFontColor(color)
        fontColorSwatch:SetColor(TwinFangs:GetNameplateHintFontColor())
    end)
    Layout.Row(fontColorRow, { fontColorLabel, fontColorSwatch }, Spacing.LARGE)
    advanced:SetContentHeight(advancedBody:GetHeight())

    local resetButton = Widgets.CreateTextButton(hint, L.TWIN_FANGS_NAMEPLATE_HINT_RESET, function()
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
    hint:SetHeaderAction(resetButton)

    hint:SetContentHeight(hintBody:GetHeight())
    hint:RefreshContentInteractive()

    return body:GetHeight()
end

function TwinFangs:OnEnable()
    LayoutEditor.RegisterScope({
        id = SCOPE_ID,
        label = L.TWIN_FANGS_LAYOUT_SCOPE,
        order = 6,
        elementIds = { Callout.LAYOUT_ID },
        prepare = function()
            Callout.Ensure()
        end,
    })
    ns.MainPanel:RegisterSection({
        title = L.TWIN_FANGS_TITLE,
        group = ns.PanelGroups.VENOMOUS_ABYSS,
        tooltip = L.TWIN_FANGS_HINT,
        build = BuildContent,
    })
    self:ListenForEncounter()
    self:ListenForInterruptChain()
    self:ListenForInterruptMacro()
    self.OnInterruptChainChanged = function()
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end
    ns.Api.Group.OnChanged(function()
        if syncInterruptChainEditor then
            syncInterruptChainEditor()
        end
    end)
    -- TEMP: nameplate-hint casts listen outside the encounter for in-game testing.
    self:ListenForNameplateHint()
    Callout.Ensure()
    Callout.Update()
end
