local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Binding = ns.Api.Binding
local Combat = ns.Api.Combat
local Encounter = ns.Api.Encounter
local GameEvents = ns.Api.GameEvents
local Group = ns.Api.Group
local Timer = ns.Api.Timer
local UnitFrame = ns.Api.UnitFrame
local Dropdown = ns.Dropdown
local FeatureSection = ns.FeatureSection
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local InterruptClaim = ns.Modules.Get("InterruptClaim")

local BUTTON_NAME = ns.ADDON_NAME .. "InterruptClaim"
local MARKER_COLUMNS = 4
local MARKER_ICON_SIZE = 24
local MARKER_CELL_SIZE = MARKER_ICON_SIZE + 2 * Spacing.SMALL
local MARKER_CELL_STEP = MARKER_CELL_SIZE + Spacing.TINY

local MARKER_LABELS = {
    STAR = L.WORLD_MARKER_STAR,
    CIRCLE = L.WORLD_MARKER_CIRCLE,
    DIAMOND = L.WORLD_MARKER_DIAMOND,
    TRIANGLE = L.WORLD_MARKER_TRIANGLE,
    MOON = L.WORLD_MARKER_MOON,
    SQUARE = L.WORLD_MARKER_SQUARE,
    CROSS = L.WORLD_MARKER_CROSS,
    SKULL = L.WORLD_MARKER_SKULL,
}

-- Marks frames this feature configured so a reload can reclaim or release them.
local OWNER_ATTRIBUTE = "neweratools-interruptclaim"

local button
local bound = false
local boundKey
local boundMacro
local listening = false
---@type table<Frame, { typeKey: string, macroKey: string }>
local applied = {}
---@type table<Frame, boolean>
local pending = {}
-- True while this feature writes unit-frame attributes, so the write hook ignores them.
local writing = false
---@type Button[]
local markerCells = {}
---@type EditBox|nil
local announceBox
---@type FontString|nil
local announceCount
---@type FontString|nil
local announcePreview
---@type Frame|nil
local announceDetails
---@type SegmentedControl|nil
local announceChannelControl
local refreshingAnnounce = false

local function EnsureButton()
    if button then
        return button
    end
    -- Named so SetOverrideBindingClick can target it. Hidden; clicks arrive via the override.
    -- Execute on down regardless of ActionButtonUseKeyDown. `/tm` toggles, so an up-edge
    -- action would apply the mark and then clear it.
    button = CreateFrame("Button", BUTTON_NAME, nil, "SecureActionButtonTemplate")
    button:SetAttribute("useOnKeyDown", true)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", InterruptClaim:GetMacroText())
    button:EnableMouse(false)
    button:Hide()
    return button
end

-- Named frames cannot be destroyed. Unbinding and hiding is the removal; the same button is reused.
local function RemoveButton()
    if not button then
        bound = false
        boundKey = nil
        boundMacro = nil
        return
    end
    if bound then
        Binding.ClearOverrides(button)
        bound = false
        boundKey = nil
        boundMacro = nil
    end
    button:Hide()
    button:SetParent(nil)
end

local function SyncButton()
    if Combat.IsLockedDown() then
        return
    end
    if not InterruptClaim:IsEnabled() then
        RemoveButton()
        return
    end
    local frame = EnsureButton()
    local key = InterruptClaim:GetBindingKey()
    local macro = InterruptClaim:GetMacroText()
    if bound and boundKey == key and boundMacro == macro then
        return
    end
    if bound and boundKey ~= key then
        Binding.ClearOverrides(frame)
        bound = false
        boundKey = nil
    end
    if not bound then
        Binding.SetOverrideClick(frame, true, key, BUTTON_NAME)
        bound = true
        boundKey = key
    end
    frame:SetAttribute("macrotext", macro)
    boundMacro = macro
end

---@param typeKey string
---@return string
local function MacroKeyFromTypeKey(typeKey)
    return (typeKey:gsub("type", "macrotext", 1))
end

---@class InterruptClaimFrameSpec
---@field typeKey string
---@field macroKey string
---@field typeValue string
---@field macroValue string|nil

-- What this feature writes for the current settings. Rebuilt only after a settings change, so
-- frame walks and the attribute hook only compare. Also stored per frame as what was written.
---@type InterruptClaimFrameSpec|nil
local desired

---@return InterruptClaimFrameSpec
local function Desired()
    if not desired then
        local mark = InterruptClaim:IsMarkEnabled()
        desired = {
            typeKey = InterruptClaim:GetUnitFrameTypeAttribute(),
            macroKey = InterruptClaim:GetUnitFrameMacroAttribute(),
            typeValue = mark and "macro" or "focus",
            macroValue = mark and InterruptClaim:GetMacroText() or nil,
        }
    end
    return desired
end

---@param frame Frame
local function ReleaseFrame(frame)
    local typeKey = frame.GetAttribute and frame:GetAttribute(OWNER_ATTRIBUTE)
    if type(typeKey) ~= "string" then
        local spec = applied[frame]
        if not spec then
            pending[frame] = nil
            return
        end
        typeKey = spec.typeKey
    end
    local wasWriting = writing
    writing = true
    frame:SetAttribute(typeKey, nil)
    frame:SetAttribute(MacroKeyFromTypeKey(typeKey), nil)
    frame:SetAttribute(OWNER_ATTRIBUTE, nil)
    writing = wasWriting
    applied[frame] = nil
    pending[frame] = nil
end

---Gives up a frame without touching the click attributes another addon now owns.
---@param frame Frame
local function YieldFrame(frame)
    local wasWriting = writing
    writing = true
    frame:SetAttribute(OWNER_ATTRIBUTE, nil)
    writing = wasWriting
    applied[frame] = nil
    pending[frame] = nil
end

-- Set when a sync was skipped or a frame was queued, so the next safe point does one pass.
local unitFramesDirty = false

-- Click-casting addons (DandersFrames) blank every modifier click on frames they manage, at
-- registration, on later rescans, and on each hover of Blizzard frames. A blank found on a frame
-- this feature owns is restored, and that frame is then watched so later blanks are undone at
-- once. Only such frames are hooked, keeping the hook off busy raid frames that are never blanked.
-- A real binding written by another addon always wins.
---@param frame Frame
local function ApplyFrame(frame)
    if Combat.IsLockedDown() then
        pending[frame] = true
        unitFramesDirty = true
        return
    end
    if not InterruptClaim:IsEnabled() then
        ReleaseFrame(frame)
        return
    end
    pending[frame] = nil
    if frame == button or not UnitFrame.IsConfigurable(frame) then
        return
    end

    local spec = Desired()
    local typeKey = spec.typeKey
    local owner = frame:GetAttribute(OWNER_ATTRIBUTE)
    local current = frame:GetAttribute(typeKey)
    if owner == typeKey then
        local written = applied[frame]
        if current == spec.typeValue then
            if frame:GetAttribute(spec.macroKey) == spec.macroValue then
                applied[frame] = spec
                return
            end
        elseif current == nil or current == "" then
            UnitFrame.WatchAttributes(frame)
        elseif not (written and current == written.typeValue) then
            YieldFrame(frame)
            return
        end
    else
        if owner ~= nil then
            ReleaseFrame(frame)
            current = frame:GetAttribute(typeKey)
        end
        if current ~= nil and current ~= "" then
            return
        end
    end

    local wasWriting = writing
    writing = true
    frame:SetAttribute(typeKey, spec.typeValue)
    frame:SetAttribute(spec.macroKey, spec.macroValue)
    frame:SetAttribute(OWNER_ATTRIBUTE, typeKey)
    writing = wasWriting
    applied[frame] = spec
end

---@param frame Frame
---@param key string
---@param value any
local function OnUnitFrameAttributeSet(frame, key, value)
    if writing then
        return
    end
    local spec = applied[frame]
    if not spec then
        return
    end
    local expected
    if key == spec.typeKey then
        expected = spec.typeValue
    elseif key == spec.macroKey then
        expected = spec.macroValue
    else
        return
    end
    if value == expected then
        return
    end
    if value ~= nil and value ~= "" then
        YieldFrame(frame)
        return
    end
    ApplyFrame(frame)
end

-- Scratch storage reused by every sync pass.
---@type table<Frame, boolean>
local seenScratch = {}
---@type Frame[]
local listScratch = {}

---@param frame Frame
local function VisitForApply(frame)
    seenScratch[frame] = true
    ApplyFrame(frame)
end

---@param frame Frame
local function CollectForRelease(frame)
    listScratch[#listScratch + 1] = frame
end

local function ReleaseCollected()
    for i = 1, #listScratch do
        ReleaseFrame(listScratch[i])
        listScratch[i] = nil
    end
end

-- Encounters are deferred too: a dead player is out of combat lockdown while roster events keep
-- firing, and nothing here needs to change before the pull ends.
---@param ignoreEncounter boolean|nil  True right after ENCOUNTER_END, before the flag may clear.
local function SyncUnitFrames(ignoreEncounter)
    if Combat.IsLockedDown() or (not ignoreEncounter and Encounter.IsInProgress()) then
        unitFramesDirty = true
        return
    end
    unitFramesDirty = false
    if not InterruptClaim:IsEnabled() then
        for frame in pairs(applied) do
            CollectForRelease(frame)
        end
        UnitFrame.ForEach(CollectForRelease)
        ReleaseCollected()
        for frame in pairs(pending) do
            pending[frame] = nil
        end
        return
    end

    UnitFrame.ForEach(VisitForApply)
    for frame in pairs(pending) do
        listScratch[#listScratch + 1] = frame
    end
    for i = 1, #listScratch do
        VisitForApply(listScratch[i])
        listScratch[i] = nil
    end
    -- Frames dropped from ClickCastFrames are only noticed here; give their click back.
    for frame in pairs(applied) do
        if not seenScratch[frame] then
            CollectForRelease(frame)
        end
    end
    ReleaseCollected()
    for frame in pairs(seenScratch) do
        seenScratch[frame] = nil
    end
end

-- Click-casting addons rescan and blank newly registered frames up to a few seconds later.
local VERIFY_DELAY = 4

local rescanQueued = false
local verifyQueued = false

local function RunQueuedRescan()
    rescanQueued = false
    SyncUnitFrames()
end

local function RunVerifyRescan()
    verifyQueued = false
    SyncUnitFrames()
end

-- Other addons create or re-register unit frames in their own handlers for the same events, so
-- one pass runs on the next frame and a second catches their delayed blanking.
local function QueueUnitFrameRescan()
    if not InterruptClaim:IsEnabled() then
        return
    end
    if Combat.IsLockedDown() or Encounter.IsInProgress() then
        unitFramesDirty = true
        return
    end
    if not rescanQueued then
        rescanQueued = true
        Timer.After(0, RunQueuedRescan)
    end
    if not verifyQueued then
        verifyQueued = true
        Timer.After(VERIFY_DELAY, RunVerifyRescan)
    end
end

local function OnCombatLeave()
    SyncButton()
    if unitFramesDirty then
        SyncUnitFrames()
    end
end

local function RunEncounterEndSync()
    if unitFramesDirty then
        SyncUnitFrames(true)
    end
end

local function OnEncounterEnd()
    if unitFramesDirty then
        Timer.After(0, RunEncounterEndSync)
    end
end

---@return DropdownItem[]
local function ModifierItems()
    return {
        { value = InterruptClaim.MODIFIER_SHIFT, text = L.INTERRUPT_CLAIM_MODIFIER_SHIFT },
        { value = InterruptClaim.MODIFIER_CTRL, text = L.INTERRUPT_CLAIM_MODIFIER_CTRL },
        { value = InterruptClaim.MODIFIER_ALT, text = L.INTERRUPT_CLAIM_MODIFIER_ALT },
    }
end

---@return DropdownItem[]
local function MouseButtonItems()
    return {
        { value = InterruptClaim.MOUSE_LEFT, text = L.INTERRUPT_CLAIM_MOUSE_LEFT },
        { value = InterruptClaim.MOUSE_RIGHT, text = L.INTERRUPT_CLAIM_MOUSE_RIGHT },
        { value = InterruptClaim.MOUSE_MIDDLE, text = L.INTERRUPT_CLAIM_MOUSE_MIDDLE },
        { value = InterruptClaim.MOUSE_FORWARD, text = L.INTERRUPT_CLAIM_MOUSE_FORWARD },
        { value = InterruptClaim.MOUSE_BACK, text = L.INTERRUPT_CLAIM_MOUSE_BACK },
    }
end

---@param cell Frame
---@param labelText string
---@param items DropdownItem[]
---@param getValue fun(): any
---@param setValue fun(value: any)
---@return Dropdown
local function AddClickDropdown(cell, labelText, items, getValue, setValue)
    local label = Widgets.CreateLabel(cell, Fonts.BODY, labelText)
    label:SetJustifyH("LEFT")
    local dropdown
    dropdown = Dropdown.Create(cell, items, function(value)
        if not InterruptClaim:IsEnabled() then
            return
        end
        setValue(value)
        dropdown:SetSelected(getValue())
    end)
    dropdown:SetSelected(getValue())
    Layout.Row(cell, { label, dropdown }, Spacing.LARGE)
    return dropdown
end

local function RefreshMarkerSelection()
    local selected = InterruptClaim:GetMarkIndex()
    for index, cell in ipairs(markerCells) do
        Widgets.ApplyBackdrop(cell, Colors.SURFACE, index == selected and Colors.ACCENT or Colors.BORDER)
    end
end

---@return string
local function AnnouncePreviewText()
    local slash = InterruptClaim:GetAnnounceSlash()
    local message = InterruptClaim:GetAnnounceMessage()
    if not slash or message == "" then
        return L.INTERRUPT_CLAIM_ANNOUNCE_PREVIEW_EMPTY
    end
    local marker = InterruptClaim.MARKERS[InterruptClaim:GetMarkIndex()]
    local icon = "|T" .. Assets.WORLD_MARKER_ICONS[marker] .. ":12|t"
    local body = message:gsub(InterruptClaim.ANNOUNCE_PLACEHOLDER, icon)
    body = body:gsub("%%f", L.INTERRUPT_CLAIM_ANNOUNCE_PREVIEW_FOCUS)
    return slash .. " " .. body
end

local function RefreshAnnounceControls()
    if announceChannelControl then
        announceChannelControl:SetSelected(InterruptClaim:GetAnnounceChannel())
    end
    if announceDetails then
        local announceOn = InterruptClaim:IsAnnounceEnabled()
        FeatureSection.SetSubtreeInteractive(announceDetails, announceOn)
        if InterruptClaim:IsMarkEnabled() then
            announceDetails:SetAlpha(announceOn and 1 or 0.4)
        else
            announceDetails:SetAlpha(1)
        end
    end
    if not announceBox then
        return
    end
    local message = InterruptClaim:GetAnnounceMessage()
    refreshingAnnounce = true
    if announceBox:GetText() ~= message then
        announceBox:SetText(message)
    end
    refreshingAnnounce = false
    if announceCount then
        announceCount:SetText(InterruptClaim:GetAnnounceCharCount() .. "/" .. InterruptClaim.ANNOUNCE_MAX_CHARS)
    end
    if announcePreview then
        announcePreview:SetText(AnnouncePreviewText())
    end
end

---@param parent Frame
---@return EditBox
local function CreateAnnounceBox(parent)
    local box = CreateFrame("EditBox", nil, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    Widgets.EnsureFonts()
    box:SetFontObject(Fonts.BODY)
    box:SetHeight(Sizes.INPUT_HEIGHT)
    box:SetAutoFocus(false)
    box:SetMaxLetters(InterruptClaim.ANNOUNCE_MAX_CHARS)
    box:SetJustifyH("LEFT")
    box:SetTextInsets(Spacing.MEDIUM, Spacing.MEDIUM, 0, 0)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.ACCENT))
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER))
        if
            not InterruptClaim:IsEnabled()
            or not InterruptClaim:IsMarkEnabled()
            or not InterruptClaim:IsAnnounceEnabled()
        then
            return
        end
        InterruptClaim:SetAnnounceMessage(self:GetText())
        RefreshAnnounceControls()
    end)
    box:SetScript("OnTextChanged", function(self)
        if refreshingAnnounce then
            return
        end
        if
            not InterruptClaim:IsEnabled()
            or not InterruptClaim:IsMarkEnabled()
            or not InterruptClaim:IsAnnounceEnabled()
        then
            return
        end
        InterruptClaim:SetAnnounceMessage(self:GetText())
        RefreshAnnounceControls()
    end)
    function box:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end
    return box
end

---@param parent Frame
---@param index integer
---@param marker string
---@return Button
local function CreateMarkerCell(parent, index, marker)
    local cell = CreateFrame("Button", nil, parent, Assets.Templates.BACKDROP)
    cell:SetSize(MARKER_CELL_SIZE, MARKER_CELL_SIZE)
    local x, y = Layout.GridCell(index, MARKER_COLUMNS, MARKER_CELL_STEP, MARKER_CELL_STEP)
    cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    Widgets.AddHoverHighlight(cell)
    function cell:SetEnabled(enabled)
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
    end

    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(MARKER_ICON_SIZE, MARKER_ICON_SIZE)
    icon:SetPoint("CENTER")
    icon:SetTexture(Assets.WORLD_MARKER_ICONS[marker])

    Widgets.AttachTooltip(cell, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(MARKER_LABELS[marker])
    end)
    cell:SetScript("OnClick", function()
        if not InterruptClaim:IsEnabled() or not InterruptClaim:IsMarkEnabled() then
            return
        end
        InterruptClaim:SetMarkIndex(index)
        RefreshMarkerSelection()
    end)
    return cell
end

---@param parent Frame
---@return number
local function BuildMarkerGrid(parent)
    markerCells = {}
    local markers = InterruptClaim.MARKERS
    for index, marker in ipairs(markers) do
        markerCells[index] = CreateMarkerCell(parent, index, marker)
    end
    RefreshMarkerSelection()
    return Layout.GridHeight(#markers, MARKER_COLUMNS, MARKER_CELL_STEP)
end

---Fills the feature body. Returns the content height.
---@param content Frame
---@return number
local function BuildContent(content)
    local body = Layout.Stack(content, {
        paddingX = Spacing.SMALL,
        paddingY = Spacing.SMALL,
        spacing = Spacing.SMALL,
    })

    local clickRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local modifierCell, mouseCell = Layout.SplitRow(clickRow, Spacing.MEDIUM)
    AddClickDropdown(modifierCell, L.INTERRUPT_CLAIM_MODIFIER, ModifierItems(), function()
        return InterruptClaim:GetModifier()
    end, function(modifier)
        InterruptClaim:SetModifier(modifier)
    end)
    AddClickDropdown(mouseCell, L.INTERRUPT_CLAIM_MOUSE, MouseButtonItems(), function()
        return InterruptClaim:GetMouseButton()
    end, function(mouseButton)
        InterruptClaim:SetMouseButton(mouseButton)
    end)

    local clearFocusRow = body:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local clearFocusBox = Widgets.CreateCheckbox(clearFocusRow)
    clearFocusBox:SetChecked(InterruptClaim:IsClearFocusEnabled())
    clearFocusBox:SetScript("OnClick", function(self)
        if not InterruptClaim:IsEnabled() then
            return
        end
        InterruptClaim:SetClearFocusEnabled(self:GetChecked())
        self:SetChecked(InterruptClaim:IsClearFocusEnabled())
    end)
    local clearFocusLabel = Widgets.CreateLabel(clearFocusRow, Fonts.BODY, L.INTERRUPT_CLAIM_CLEAR_FOCUS)
    clearFocusLabel:SetJustifyH("LEFT")
    clearFocusLabel:SetWordWrap(false)
    Layout.Row(clearFocusRow, { clearFocusBox, clearFocusLabel }, Spacing.SMALL)
    clearFocusBox:SetHitRectInsets(0, -(clearFocusLabel:GetStringWidth() + Spacing.SMALL), 0, 0)

    local mark = FeatureSection.Create(body, {
        title = L.INTERRUPT_CLAIM_MARK,
        divider = true,
        enabled = InterruptClaim:IsMarkEnabled(),
        onEnabledChanged = function(enabled)
            InterruptClaim:SetMarkEnabled(enabled)
        end,
        onStackHeightChanged = function(stackHeight)
            content:SetContentHeight(stackHeight)
        end,
    })
    local markBody = Layout.Stack(mark.content, {
        spacing = Spacing.SMALL,
    })
    local grid = CreateFrame("Frame", nil, mark.content)
    markBody:Add(grid, BuildMarkerGrid(grid))
    local preventRow = markBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local preventBox = Widgets.CreateCheckbox(preventRow)
    preventBox:SetChecked(InterruptClaim:IsPreventOverwrite())
    preventBox:SetScript("OnClick", function(self)
        if not InterruptClaim:IsEnabled() or not InterruptClaim:IsMarkEnabled() then
            return
        end
        InterruptClaim:SetPreventOverwrite(self:GetChecked())
        self:SetChecked(InterruptClaim:IsPreventOverwrite())
    end)
    local preventLabel = Widgets.CreateLabel(preventRow, Fonts.BODY, L.INTERRUPT_CLAIM_PREVENT_OVERWRITE)
    preventLabel:SetJustifyH("LEFT")
    preventLabel:SetWordWrap(false)
    Layout.Row(preventRow, { preventBox, preventLabel }, Spacing.SMALL)
    preventBox:SetHitRectInsets(0, -(preventLabel:GetStringWidth() + Spacing.SMALL), 0, 0)

    local announce = FeatureSection.Create(markBody, {
        title = L.INTERRUPT_CLAIM_ANNOUNCE,
        tooltip = L.INTERRUPT_CLAIM_ANNOUNCE_TITLE_HINT,
        divider = true,
        toggle = false,
        onStackHeightChanged = function()
            mark:SetContentHeight(markBody:GetHeight())
        end,
    })
    announceChannelControl = Widgets.CreateSegmentedControl(announce, {
        { value = InterruptClaim.ANNOUNCE_OFF, text = L.INTERRUPT_CLAIM_ANNOUNCE_OFF },
        { value = InterruptClaim.CHANNEL_PARTY, text = L.INTERRUPT_CLAIM_CHANNEL_PARTY },
        { value = InterruptClaim.CHANNEL_SAY, text = L.INTERRUPT_CLAIM_CHANNEL_SAY },
        { value = InterruptClaim.CHANNEL_EMOTE, text = L.INTERRUPT_CLAIM_CHANNEL_EMOTE },
    }, function(channel)
        if not InterruptClaim:IsEnabled() or not InterruptClaim:IsMarkEnabled() then
            announceChannelControl:SetSelected(InterruptClaim:GetAnnounceChannel())
            return
        end
        InterruptClaim:SetAnnounceChannel(channel)
        announceChannelControl:SetSelected(InterruptClaim:GetAnnounceChannel())
    end)
    announceChannelControl:SetSelected(InterruptClaim:GetAnnounceChannel())
    announce:SetHeaderAction(announceChannelControl)
    announceDetails = announce.content

    local announceBody = Layout.Stack(announce.content, {
        spacing = Spacing.SMALL,
    })
    local messageRow = announceBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local messageLabel = Widgets.CreateLabel(messageRow, Fonts.BODY, L.INTERRUPT_CLAIM_ANNOUNCE_MESSAGE)
    messageLabel:SetJustifyH("LEFT")
    announceCount = Widgets.CreateLabel(messageRow, Fonts.SMALL_MUTED)
    announceBox = CreateAnnounceBox(messageRow)
    messageLabel:SetPoint("LEFT", messageRow, "LEFT")
    announceCount:SetPoint("RIGHT", messageRow, "RIGHT")
    announceBox:SetPoint("LEFT", messageLabel, "RIGHT", Spacing.LARGE, 0)
    announceBox:SetPoint("RIGHT", announceCount, "LEFT", -Spacing.SMALL, 0)

    local hintRow = announceBody:AddRow(16)
    local hint = Widgets.CreateLabel(hintRow, Fonts.SMALL_MUTED, L.INTERRUPT_CLAIM_ANNOUNCE_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetPoint("LEFT", hintRow, "LEFT")
    hint:SetPoint("RIGHT", hintRow, "RIGHT")

    local previewRow = announceBody:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local previewLabel = Widgets.CreateLabel(previewRow, Fonts.SMALL_MUTED, L.INTERRUPT_CLAIM_ANNOUNCE_PREVIEW)
    previewLabel:SetJustifyH("LEFT")
    announcePreview = Widgets.CreateLabel(previewRow, Fonts.BODY)
    announcePreview:SetJustifyH("LEFT")
    announcePreview:SetWordWrap(false)
    Layout.Row(previewRow, { previewLabel, announcePreview }, Spacing.LARGE)
    announce:SetContentHeight(announceBody:GetHeight())
    announce:RefreshContentInteractive()

    mark:SetContentHeight(markBody:GetHeight())
    mark:RefreshContentInteractive()
    RefreshAnnounceControls()

    return body:GetHeight()
end

---@param container Frame
---@return number
local function Build(container)
    local height = BuildContent(container)
    container:RefreshContentInteractive()
    RefreshAnnounceControls()
    return height
end

function InterruptClaim:OnEnable()
    ns.MainPanel:RegisterSection({
        title = L.INTERRUPT_CLAIM_TITLE,
        group = ns.PanelGroups.COMBAT,
        tooltip = L.INTERRUPT_CLAIM_HINT,
        enabled = InterruptClaim:IsEnabled(),
        onEnabledChanged = function(enabled)
            InterruptClaim:SetEnabled(enabled)
        end,
        build = Build,
    })
    if not listening then
        listening = true
        Combat.OnLeave(OnCombatLeave)
        GameEvents.Listen("PLAYER_ENTERING_WORLD", QueueUnitFrameRescan)
        Group.OnRosterChanged(QueueUnitFrameRescan)
        Encounter.OnEnd(OnEncounterEnd)
        UnitFrame.OnCreated(ApplyFrame)
        UnitFrame.OnAttributeSet(OnUnitFrameAttributeSet)
    end
    SyncButton()
    SyncUnitFrames()
end

function InterruptClaim:OnEnabledChanged()
    desired = nil
    SyncButton()
    SyncUnitFrames()
end

function InterruptClaim:OnClickChanged()
    desired = nil
    SyncButton()
    SyncUnitFrames()
end

function InterruptClaim:OnMarkChanged()
    desired = nil
    RefreshMarkerSelection()
    RefreshAnnounceControls()
    SyncButton()
    SyncUnitFrames()
end
