local _, ns = ...
local L = ns.L
local CollapsibleSection = ns.CollapsibleSection
local Layout = ns.Layout
local WarningWindow = ns.WarningWindow
local Widgets = ns.Widgets
local AuraTrackerBarUI = ns.AuraTrackerBarUI
local Profile = ns.AuraTrackerProfile

local Assets = ns.Assets
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local PENDING_NOTICE_HEIGHT = 36

local AuraTracker = ns.Modules.Get("AuraTracker")

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

---Builds a module-level labeled checkbox into `parent`.
---@param parent Frame
---@param text string
---@param getChecked fun(): boolean
---@param setChecked fun(checked: boolean)
---@return CheckButton
local function AddModuleCheckbox(parent, text, getChecked, setChecked)
    local box = Widgets.CreateCheckbox(parent)
    box:SetChecked(getChecked())
    box:SetScript("OnClick", function(self)
        if UI.refreshingControls then
            self:SetChecked(getChecked())
            return
        end
        setChecked(self:GetChecked())
        self:SetChecked(getChecked())
    end)

    local label = Widgets.CreateLabel(parent, Fonts.BODY, text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    Layout.Row(parent, { box, label }, Spacing.SMALL)
    box:SetHitRectInsets(0, -(label:GetStringWidth() + Spacing.SMALL), 0, 0)
    return box
end

---@param content Frame
---@return number
local function BuildVisibilityContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.TINY })

    local hint = body:AddRow(Sizes.CONTROL_HEIGHT)
    local hintLabel = Widgets.CreateLabel(hint, Fonts.SMALL_MUTED, L.AURA_TRACKER_VISIBILITY_HINT)
    hintLabel:SetJustifyH("LEFT")
    hintLabel:SetWordWrap(false)
    hintLabel:SetPoint("LEFT", hint, "LEFT")
    hintLabel:SetPoint("RIGHT", hint, "RIGHT")

    local skyridingRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    UI.hideSkyridingCheckbox = AddModuleCheckbox(skyridingRow, L.AURA_TRACKER_HIDE_SKYRIDING, function()
        return AuraTracker:GetHideDuringSkyriding()
    end, function(checked)
        AuraTracker:SetHideDuringSkyriding(checked)
    end)

    local petBattleRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    UI.hidePetBattlesCheckbox = AddModuleCheckbox(petBattleRow, L.AURA_TRACKER_HIDE_PET_BATTLES, function()
        return AuraTracker:GetHideDuringPetBattles()
    end, function(checked)
        AuraTracker:SetHideDuringPetBattles(checked)
    end)

    local cinematicRow = body:AddRow(Sizes.CONTROL_HEIGHT)
    UI.hideCinematicsCheckbox = AddModuleCheckbox(cinematicRow, L.AURA_TRACKER_HIDE_CINEMATICS, function()
        return AuraTracker:GetHideDuringCinematics()
    end, function(checked)
        AuraTracker:SetHideDuringCinematics(checked)
    end)

    return body:GetHeight()
end

function UI.RefreshVisibilityControls()
    if not UI.hideSkyridingCheckbox then
        return
    end
    UI.refreshingControls = true
    UI.hideSkyridingCheckbox:SetChecked(AuraTracker:GetHideDuringSkyriding())
    UI.hidePetBattlesCheckbox:SetChecked(AuraTracker:GetHideDuringPetBattles())
    UI.hideCinematicsCheckbox:SetChecked(AuraTracker:GetHideDuringCinematics())
    UI.refreshingControls = false
end

---@type WarningWindow|nil
local deleteConfirmWindow
---@type integer|nil
local pendingDeleteTrackerId

local function HideDeleteConfirm()
    pendingDeleteTrackerId = nil
    if deleteConfirmWindow then
        deleteConfirmWindow:Hide()
    end
end

local function ConfirmPendingDelete()
    local trackerId = pendingDeleteTrackerId
    HideDeleteConfirm()
    if not trackerId or not AuraTracker:HasTracker(trackerId) then
        return
    end
    AuraTracker:RemoveTracker(trackerId)
    UI.selectedTrackerId = nil
    local nextId = UI.ResolveSelectedTrackerId()
    if nextId then
        UI.SyncTrackerRow(nextId)
    end
    UI.RefreshSelectedEditor()
end

local function EnsureDeleteConfirmWindow()
    if deleteConfirmWindow then
        return deleteConfirmWindow
    end

    deleteConfirmWindow = WarningWindow.Create({
        name = ns.ADDON_NAME .. "AuraTrackerDeleteConfirm",
        title = L.AURA_TRACKER_DELETE_CONFIRM_TITLE,
        hint = "",
        actionText = L.AURA_TRACKER_DELETE_CONFIRM,
        onAction = ConfirmPendingDelete,
        closable = true,
        onClose = HideDeleteConfirm,
        draggable = true,
        -- Absorb body clicks so they don't fall through to the main panel.
        onClick = function() end,
    })
    -- Main panel is DIALOG; keep the confirm prompt above it.
    deleteConfirmWindow:SetFrameStrata("DIALOG")
    return deleteConfirmWindow
end

---Shows a confirm warning before permanently removing a tracker.
---@param trackerId integer
function UI.PromptDeleteTracker(trackerId)
    assert(type(trackerId) == "number", "Bad tracker id")
    if not AuraTracker:HasTracker(trackerId) then
        return
    end

    pendingDeleteTrackerId = trackerId
    local window = EnsureDeleteConfirmWindow()
    local panelScale = (ns.MainPanel and ns.MainPanel.db and ns.MainPanel.db.scale) or 1
    window:SetWindowScale(panelScale)
    window:SetWarningText(
        L.AURA_TRACKER_DELETE_CONFIRM_TITLE,
        string.format(L.AURA_TRACKER_DELETE_CONFIRM_HINT, AuraTracker:GetDisplayName(trackerId))
    )
    window:Show()
    window:Raise()
end

---@param parent Frame
---@return Frame
local function BuildPendingNotice(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", Spacing.TINY, 0)
    icon:SetAtlas(Assets.Icons.CLOCK)
    local muted = Assets.Colors.TEXT_MUTED
    icon:SetVertexColor(muted.r, muted.g, muted.b, 1)

    local title = Widgets.CreateLabel(frame, Fonts.BODY, L.AURA_TRACKER_PENDING_TITLE)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", Spacing.SMALL, 1)
    title:SetPoint("RIGHT", frame, "RIGHT", -Spacing.SMALL, 0)

    local hint = Widgets.CreateLabel(frame, Fonts.SMALL_MUTED, L.AURA_TRACKER_PENDING_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Spacing.TINY)
    hint:SetPoint("RIGHT", frame, "RIGHT", -Spacing.SMALL, 0)
    UI.pendingIcon = icon
    UI.pendingTitle = title
    UI.pendingHint = hint
    return frame
end

---Shows or hides the pending copy. The row height stays put, so the scroll offset does not move.
function UI.RefreshPendingStatus()
    if UI.pendingIcon then
        local showPending = ns.AuraTrackerBarUI.HasPendingAppearance()
        UI.pendingIcon:SetShown(showPending)
        UI.pendingTitle:SetShown(showPending)
        UI.pendingHint:SetShown(showPending)
    end
    if UI.RefreshPendingClocks then
        UI.RefreshPendingClocks()
    end
end

---@param content Frame
---@return number
local function BuildContent(content)
    UI.contentBody = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.MEDIUM,
    })

    -- Fixed slot: clearing the message hides the icon and text without changing page height.
    UI.pendingNoticeHeight = PENDING_NOTICE_HEIGHT
    UI.pendingNotice = UI.contentBody:Add(BuildPendingNotice(content), PENDING_NOTICE_HEIGHT)

    UI.visibilitySection = CollapsibleSection.Create(UI.contentBody, {
        title = L.AURA_TRACKER_SECTION_VISIBILITY,
        expanded = UI.visibilityExpanded == true,
        onStackHeightChanged = function()
            UI.RelayoutSettings()
        end,
        onExpandedChanged = function(expanded)
            UI.visibilityExpanded = expanded
        end,
    })
    UI.visibilitySection:SetContentHeight(BuildVisibilityContent(UI.visibilitySection.content))

    UI.listHost = UI.contentBody:Add(CreateFrame("Frame", nil, content), 0)

    UI.emptyEditorHost = UI.contentBody:Add(CreateFrame("Frame", nil, content), Sizes.CONTROL_ROW_HEIGHT)
    UI.emptyEditorLabel = Widgets.CreateLabel(UI.emptyEditorHost, Fonts.MUTED, L.AURA_TRACKER_EMPTY)
    UI.emptyEditorLabel:SetJustifyH("LEFT")
    UI.emptyEditorLabel:SetPoint("LEFT", UI.emptyEditorHost, "LEFT")
    UI.editorHost = UI.contentBody:Add(CreateFrame("Frame", nil, content), 0)
    UI.editorHost:Hide()

    UI.RefreshTrackerList()
    UI.RefreshVisibilityControls()
    UI.RefreshSelectedEditor()
    UI.RefreshPendingStatus()

    return UI.contentBody:GetHeight()
end

---@param containerFrame Frame
---@return number
local function Build(containerFrame)
    -- Reset section-local state when the panel rebuilds the section.
    HideDeleteConfirm()
    UI.selectedTrackerId = nil
    UI.listActiveExpanded = true
    UI.listInactiveExpanded = false
    UI.visibilityExpanded = false
    UI.editorBasicExpanded = true
    UI.editorTrackingExpanded = true
    UI.editorAppearanceExpanded = true
    UI.editorBorderExpanded = false
    UI.editorValueExpanded = false
    UI.editorBuilt = false
    UI.listHost = nil
    UI.listStack = nil
    UI.visibilitySection = nil
    UI.hideSkyridingCheckbox = nil
    UI.hidePetBattlesCheckbox = nil
    UI.hideCinematicsCheckbox = nil
    UI.editorHost = nil
    UI.editorStack = nil
    UI.pendingNotice = nil
    UI.pendingIcon = nil
    UI.pendingTitle = nil
    UI.pendingHint = nil
    UI.pendingClocks = {}
    UI.listReady = false
    UI.trackerRows = nil
    UI.activeIds = nil
    UI.inactiveIds = nil
    UI.activeGroup = nil
    UI.inactiveGroup = nil
    UI.activeRowStack = nil
    UI.inactiveRowStack = nil
    UI.summaryLabel = nil
    UI.summaryText = nil
    UI.activationScopeSignature = nil
    UI.contentBody = nil
    UI.emptyEditorHost = nil
    UI.emptyEditorLabel = nil

    UI.settingsContainer = containerFrame
    local height = BuildContent(containerFrame)
    containerFrame:SetContentHeight(height)
    containerFrame:RefreshContentInteractive()
    -- Fires when this page is shown, including each time the main panel opens on it.
    containerFrame:HookScript("OnShow", function()
        UI.SelectFirstTrackerEnabledForCurrentPlayer()
    end)
    return height
end

function AuraTracker:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.AURA_TRACKER_TITLE,
        group = ns.PanelGroups.COMBAT,
        tooltip = L.AURA_TRACKER_HINT,
        enabled = AuraTracker:IsEnabled(),
        onEnabledChanged = function(enabled)
            AuraTracker:SetEnabled(enabled)
        end,
        build = Build,
    })
    UI.ListenForSharedMedia()
    AuraTrackerBarUI.Enable()
end

function AuraTracker:OnTrackerListChanged()
    AuraTrackerBarUI.Update(nil)
    if UI.listHost then
        UI.SyncTrackerList()
    end
end

---Live target, focus, and reaction changes. The settings list and editor stay as they are.
function AuraTracker:OnTrackingRefresh()
    AuraTrackerBarUI.Update(nil)
end

---@param trackerId integer|nil
function AuraTracker:OnTrackerChanged(trackerId)
    local started = Profile.Start()
    local scrollBefore, heightBefore, pendingBefore
    if Profile.IsRecording() and trackerId == nil then
        local scroll = UI.PageScrollFrame(UI.settingsContainer)
        scrollBefore = scroll and scroll:GetVerticalScroll() or nil
        heightBefore = UI.contentBody and UI.contentBody:GetHeight() or nil
        pendingBefore = AuraTrackerBarUI.HasPendingAppearance()
    end
    AuraTrackerBarUI.Update(trackerId)
    if UI.listHost then
        UI.RefreshPendingStatus()
        if trackerId == nil then
            UI.SyncTrackerList()
            if UI.RefreshActivationScopeControl then
                UI.RefreshActivationScopeControl()
            end
        else
            UI.SyncTrackerRow(trackerId)
            if trackerId == UI.selectedTrackerId and UI.RefreshEditorHeader then
                UI.RefreshEditorHeader(trackerId)
            end
        end
    end
    if Profile.IsRecording() and trackerId == nil then
        local scroll = UI.PageScrollFrame(UI.settingsContainer)
        if scroll and scrollBefore then
            Profile.Mark("ui.scrollDeltaPx", scroll:GetVerticalScroll() - scrollBefore)
        end
        if heightBefore and UI.contentBody then
            Profile.Mark("ui.contentHeightDeltaPx", UI.contentBody:GetHeight() - heightBefore)
        end
        if pendingBefore and not AuraTrackerBarUI.HasPendingAppearance() then
            Profile.Inc("ui.pendingCleared")
        end
    end
    Profile.Stop("ui.onTrackerChanged", started)
end

---@param trackerId integer
function AuraTracker:OnAppearanceChanged(trackerId)
    AuraTrackerBarUI.ApplyAppearance(trackerId)
    if not UI.refreshingControls then
        UI.RefreshPendingStatus()
    end
end
