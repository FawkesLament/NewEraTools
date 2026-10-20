local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local CollapsibleSection = ns.CollapsibleSection
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local AuraTracker = ns.Modules.Get("AuraTracker")

-- Lightweight editor title block: spell icon + name/subtitle column, then a 1px divider.
local EDITOR_HEADER_ICON_SIZE = 32
local EDITOR_HEADER_TITLE_HEIGHT = 22
local EDITOR_HEADER_SUBTITLE_HEIGHT = 14
local EDITOR_HEADER_BODY_HEIGHT =
    math.max(EDITOR_HEADER_ICON_SIZE, EDITOR_HEADER_TITLE_HEIGHT + EDITOR_HEADER_SUBTITLE_HEIGHT)
local EDITOR_HEADER_HEIGHT = EDITOR_HEADER_BODY_HEIGHT + Spacing.SMALL + Sizes.BORDER

---@class AuraTrackerUI
local UI = ns.AuraTrackerUI or {}
ns.AuraTrackerUI = UI

local Controls = UI.Controls

local sharedMediaListening = false
local fontListListening = false

---Scroll frame overlay that clips the aura header to the page viewport.
---Parented beside the scroll frame so it draws above the scroll child.
---@param scroll ScrollFrame
---@return Frame
local function EnsureEditorHeaderClip(scroll)
    if UI.editorHeaderClip and UI.editorHeaderClip.scroll == scroll then
        return UI.editorHeaderClip
    end
    local clip = CreateFrame("Frame", nil, scroll:GetParent())
    clip:SetAllPoints(scroll)
    clip:SetClipsChildren(true)
    -- The clip covers the page only to crop the header. It must not take clicks or hover from the settings under it.
    clip:EnableMouse(false)
    clip:SetMouseClickEnabled(false)
    clip:SetMouseMotionEnabled(false)
    clip.scroll = scroll
    clip:SetFrameLevel(scroll:GetFrameLevel() + 20)
    UI.editorHeaderClip = clip
    scroll:HookScript("OnVerticalScroll", function()
        UI.SyncEditorHeaderPosition()
    end)
    scroll:HookScript("OnSizeChanged", function()
        UI.SyncEditorHeaderPosition()
    end)
    scroll:HookScript("OnShow", function()
        UI.SyncEditorHeaderPosition()
    end)
    return clip
end

---Keeps the selected-aura header in place once it reaches the top of the page.
function UI.SyncEditorHeaderPosition()
    local header = UI.editorHeader
    local placeholder = UI.editorHeaderPlaceholder
    local container = UI.settingsContainer
    local clip = UI.editorHeaderClip
    if not header or not placeholder or not container or not clip or not UI.contentBody or not UI.editorStack then
        return
    end
    if not UI.editorHost or not UI.editorHost:IsShown() or not container:IsVisible() then
        header:Hide()
        return
    end
    local scroll = clip.scroll
    if not scroll then
        header:Hide()
        return
    end
    local section = container:GetParent()
    local pageHeaderHeight = (section and section.headerHeight) or 0
    local layoutOffset = pageHeaderHeight
        + UI.contentBody:GetOffset(UI.editorHost)
        + UI.editorStack:GetOffset(placeholder)
    local y = scroll:GetVerticalScroll() - layoutOffset
    local pinned = y >= 0
    if pinned then
        y = 0
    end
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, y)
    header:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, y)
    if UI.editorHeaderBackground then
        UI.editorHeaderBackground:SetShown(pinned)
    end
    header:SetAlpha(container:GetAlpha())
    header:Show()
end

---The header sits above the scroll child, so wheel events over it must reach the page.
---@param _ Frame
---@param delta number
local function ForwardEditorHeaderWheel(_, delta)
    local scroll = UI.PageScrollFrame(UI.settingsContainer)
    if not scroll then
        return
    end
    local handler = scroll:GetScript("OnMouseWheel")
    if handler then
        handler(scroll, delta)
        return
    end
    local range = scroll:GetVerticalScrollRange()
    local nextScroll = scroll:GetVerticalScroll() - delta * Sizes.CONTROL_ROW_HEIGHT
    if nextScroll < 0 then
        nextScroll = 0
    elseif nextScroll > range then
        nextScroll = range
    end
    scroll:SetVerticalScroll(nextScroll)
end

---@return boolean
function UI.CanEditSelected()
    return AuraTracker:IsEnabled() and UI.ResolveSelectedTrackerId() ~= nil
end

---LibSharedMedia fires this after a successful Register; refresh the texture picker list.
---@param _ any
---@param mediaType string
local function OnSharedMediaRegistered(_, mediaType)
    if mediaType == "statusbar" then
        UI.RefreshTextureDropdown()
    end
end

function UI.ListenForSharedMedia()
    if not fontListListening then
        fontListListening = true
        ns.SharedMedia.OnFontsRegistered(function()
            UI.RefreshTextFontDropdowns()
        end)
    end
    if sharedMediaListening or LibStub == nil then
        return
    end
    local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok or not lsm or not lsm.RegisterCallback then
        return
    end
    sharedMediaListening = true
    lsm.RegisterCallback(AuraTracker, "LibSharedMedia_Registered", OnSharedMediaRegistered)
end

---@param trackerId integer
function UI.RefreshEditorHeader(trackerId)
    local spellId = AuraTracker:GetSpellId(trackerId)
    if UI.editorSpellIcon then
        UI.ApplySpellIcon(UI.editorSpellIcon, spellId)
    end
    if UI.editorNameLabel then
        UI.editorNameLabel:SetText(AuraTracker:GetDisplayName(trackerId))
    end
    if UI.editorSubtitleLabel then
        local spellText = spellId > 0 and tostring(spellId) or "-"
        UI.editorSubtitleLabel:SetText(string.format(L.AURA_TRACKER_EDITOR_SUBTITLE, spellText))
    end
end

---@param content Frame
---@return number
function UI.BuildEditorContent(content)
    local body = Layout.Stack(content, { spacing = Spacing.SMALL })
    UI.editorStack = body

    local function OnEditorHeightChanged()
        UI.RelayoutSettings()
    end

    -- Holds the header's place in the scroll content. The visible header is an overlay so it can stick.
    local placeholder = body:Add(CreateFrame("Frame", nil, content), EDITOR_HEADER_HEIGHT)
    UI.editorHeaderPlaceholder = placeholder

    local scroll = UI.PageScrollFrame(UI.settingsContainer)
    local clip = scroll and EnsureEditorHeaderClip(scroll) or nil
    local header = CreateFrame("Frame", nil, clip or content)
    header:SetHeight(EDITOR_HEADER_HEIGHT)
    -- Settings stack is inset from the scroll viewport; the overlay itself spans the viewport.
    local inset = clip and UI.contentBody.paddingX or 0
    if clip then
        UI.editorHeader = header
        header:Hide()
        header:EnableMouse(true)
        header:EnableMouseWheel(true)
        header:SetScript("OnMouseWheel", ForwardEditorHeaderWheel)
        local background = header:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        local bg = Colors.BG
        background:SetColorTexture(bg.r, bg.g, bg.b, 1)
        background:Hide()
        UI.editorHeaderBackground = background
    else
        body:Add(header, EDITOR_HEADER_HEIGHT)
        body:SetEntryHeight(placeholder, 0)
    end

    UI.editorSpellIcon = header:CreateTexture(nil, "ARTWORK")
    UI.editorSpellIcon:SetSize(EDITOR_HEADER_ICON_SIZE, EDITOR_HEADER_ICON_SIZE)
    UI.editorSpellIcon:SetPoint("TOPLEFT", header, "TOPLEFT", inset, 0)
    UI.ApplySpellIcon(UI.editorSpellIcon, 0)

    UI.editorNameLabel = Widgets.CreateLabel(header, Fonts.TITLE, L.AURA_TRACKER_UNTITLED)
    UI.editorNameLabel:SetJustifyH("LEFT")
    UI.editorNameLabel:SetWordWrap(false)
    UI.editorNameLabel:SetPoint("TOPLEFT", UI.editorSpellIcon, "TOPRIGHT", Spacing.SMALL, 0)
    UI.editorNameLabel:SetHeight(EDITOR_HEADER_TITLE_HEIGHT)

    local deleteButton = Widgets.CreateTextButton(header, L.AURA_TRACKER_DELETE, function()
        if not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        UI.PromptDeleteTracker(trackerId)
    end, Fonts.LINK_DANGER)
    deleteButton:SetPoint(
        "TOPRIGHT",
        header,
        "TOPRIGHT",
        -inset,
        -(EDITOR_HEADER_TITLE_HEIGHT - Sizes.CONTROL_HEIGHT) / 2
    )

    -- No dedicated copy icon in shared widgets; match Delete as a compact text action.
    local duplicateButton = Widgets.CreateTextButton(header, L.AURA_TRACKER_DUPLICATE, function()
        if not UI.CanEditSelected() then
            return
        end
        local trackerId = UI.ResolveSelectedTrackerId()
        if not trackerId then
            return
        end
        local newId = AuraTracker:DuplicateTracker(trackerId)
        UI.SelectTracker(newId)
    end)
    duplicateButton:SetPoint("RIGHT", deleteButton, "LEFT", -Spacing.MEDIUM, 0)
    UI.editorNameLabel:SetPoint("RIGHT", duplicateButton, "LEFT", -Spacing.MEDIUM, 0)

    UI.editorSubtitleLabel = Widgets.CreateLabel(header, Fonts.SMALL_MUTED, "")
    UI.editorSubtitleLabel:SetJustifyH("LEFT")
    UI.editorSubtitleLabel:SetWordWrap(false)
    UI.editorSubtitleLabel:SetPoint("TOPLEFT", UI.editorNameLabel, "BOTTOMLEFT")
    UI.editorSubtitleLabel:SetPoint("TOPRIGHT", header, "TOPRIGHT", -inset, 0)
    UI.editorSubtitleLabel:SetHeight(EDITOR_HEADER_SUBTITLE_HEIGHT)

    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(Sizes.BORDER)
    divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", inset, 0)
    divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -inset, 0)
    divider:SetColorTexture(Widgets.UnpackColor(Colors.DIVIDER))

    UI.basicSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BASIC,
        expanded = UI.editorBasicExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorBasicExpanded = expanded
        end,
    })
    UI.basicSection:SetContentHeight(UI.BuildBasicSection(UI.basicSection.content))

    UI.trackingSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_TRACKING,
        expanded = UI.editorTrackingExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorTrackingExpanded = expanded
        end,
    })
    UI.trackingSection:SetContentHeight(UI.BuildTrackingSection(UI.trackingSection.content))

    UI.appearanceSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BAR_APPEARANCE,
        expanded = UI.editorAppearanceExpanded ~= false,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorAppearanceExpanded = expanded
        end,
    })
    UI.appearanceSection:SetContentHeight(UI.BuildAppearanceSection(UI.appearanceSection.content))

    UI.borderSection = CollapsibleSection.Create(body, {
        title = L.AURA_TRACKER_SECTION_BORDER,
        expanded = UI.editorBorderExpanded == true,
        spacingBefore = Spacing.MEDIUM,
        onStackHeightChanged = OnEditorHeightChanged,
        onExpandedChanged = function(expanded)
            UI.editorBorderExpanded = expanded
        end,
    })
    UI.borderSection:SetContentHeight(UI.BuildBorderSection(UI.borderSection.content))

    UI.BuildTextSections(body, OnEditorHeightChanged)

    UI.RefreshTrackingModeControls()
    UI.SyncEditorHeaderPosition()

    return body:GetHeight()
end

function UI.RefreshPendingClocks()
    local trackerId = UI.ResolveSelectedTrackerId()
    local pending = trackerId and ns.AuraTrackerBarUI.PendingAppearanceKeys(trackerId) or {}
    for key, clock in pairs(UI.pendingClocks or {}) do
        clock:SetShown(pending[key] == true)
    end
end

function UI.RefreshSelectedEditor()
    local trackerId = UI.ResolveSelectedTrackerId()
    if not trackerId then
        UI.RefreshPendingClocks()
        UI.RelayoutSettings()
        return
    end

    if not UI.editorBuilt then
        UI.BuildEditorContent(UI.editorHost)
        UI.editorBuilt = true
    end

    UI.refreshingControls = true

    UI.RefreshEditorHeader(trackerId)
    if UI.spellIdBox then
        local spellId = AuraTracker:GetSpellId(trackerId)
        UI.spellIdBox:SetText(spellId > 0 and tostring(spellId) or "")
    end
    UI.RefreshSourceControls()
    UI.RefreshActivationScopeControl()
    if UI.fillSwatch then
        UI.fillSwatch:SetColor(AuraTracker:GetFillColor(trackerId))
    end
    if UI.backgroundSwatch then
        UI.backgroundSwatch:SetColor(AuraTracker:GetBackgroundColor(trackerId))
    end
    if UI.lineSwatch then
        UI.lineSwatch:SetColor(AuraTracker:GetLineColor(trackerId))
    end
    if UI.textureDropdown then
        UI.textureDropdown:SetSelected(AuraTracker:GetTexture(trackerId))
    end
    Controls.SyncSlider(UI.widthSlider, trackerId)
    Controls.SyncSlider(UI.heightSlider, trackerId)
    Controls.SyncSlider(UI.opacitySlider, trackerId)
    Controls.SyncSlider(UI.lineThicknessSlider, trackerId)
    if UI.reverseCheckbox then
        UI.reverseCheckbox:SetChecked(AuraTracker:GetReverseFill(trackerId))
    end
    if UI.verticalCheckbox then
        UI.verticalCheckbox:SetChecked(AuraTracker:GetVertical(trackerId))
    end
    if UI.borderCheckbox then
        UI.borderCheckbox:SetChecked(AuraTracker:GetShowBorder(trackerId))
    end
    if UI.stackDividerCheckbox then
        UI.stackDividerCheckbox:SetChecked(AuraTracker:GetShowStackDividers(trackerId))
    end
    UI.RefreshTrackingModeControls()
    UI.RefreshTextDisplayControls()
    UI.RefreshSizeLabels()

    UI.refreshingControls = false
    UI.RefreshPendingClocks()
    UI.RelayoutSettings()
end
