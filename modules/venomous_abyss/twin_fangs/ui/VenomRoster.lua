local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets
local Aura = ns.Api.Aura
local Combat = ns.Api.Combat
local Instance = ns.Api.Instance
local Unit = ns.Api.Unit

local Colors = Assets.Colors
local Fonts = Assets.Fonts

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local VenomRoster = Internals.VenomRoster

local LAYOUT_ID = "TwinFangs:venomRoster"
local SLOT_KEY = "venom"
local STACK_HOST_WIDTH = 16
local NAME_STACK_GAP = 0
local ELLIPSIS = "…"
local STACK_COLOR = Colors.TEXT_GOLD

---@class TwinFangsVenomRosterRow
---@field frame Frame
---@field nameText FontString
---@field stackHost Frame
---@field stackText FontString
---@field liveStackText FontString|nil  Native SetApplicationCount target; never written by mock preview.
---@field container Frame|nil
---@field auraButton Frame|nil
---@field boundUnit string|nil
---@field auraPending boolean|nil
---@field applicationCountBound boolean|nil
---@field member TwinFangsVenomRosterMember|nil

---@class TwinFangsVenomRosterColumnFrame
---@field frame Frame
---@field rows TwinFangsVenomRosterRow[]

---@class TwinFangsVenomRosterInstance
---@field root Frame
---@field columns TwinFangsVenomRosterColumnFrame[]
---@field boundColumns TwinFangsVenomRosterColumn[]|nil
---@field boundStacks table<number, number>|nil
---@field liveDisplay boolean|nil

local VenomRosterUI = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.VenomRosterUI = VenomRosterUI

---@type TwinFangsVenomRosterInstance|nil
local instance
---@type LazyEncounterUI
local helper
local layoutRegistered = false
local layoutEditing = false
local slashPreviewing = false
local rosterListening = false
local zoneListening = false
local scaleListening = false

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---@param frame Frame
local function ApplyScale(frame)
    local scale = MainPanelScale()
    local oldScale = frame:GetScale() or 1
    if math.abs(oldScale - scale) < 0.001 then
        return
    end
    frame:SetScale(scale)
    ns.LayoutEditor.ApplyPosition(frame, TwinFangs:GetVenomRosterPosition())
end

local function ListenForScale()
    if scaleListening then
        return
    end
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    scaleListening = true
    mainPanel.OnScaleChanged(function(scale)
        if not instance then
            return
        end
        instance.root:SetScale(scale)
        ns.LayoutEditor.ApplyPosition(instance.root, TwinFangs:GetVenomRosterPosition())
    end)
end

local function CreateRoot()
    local root = CreateFrame("Frame", ns.ADDON_NAME .. "TwinFangsVenomRoster", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetToplevel(true)
    root:SetClampedToScreen(true)
    root:EnableMouse(false)
    root:SetScale(MainPanelScale())
    ns.LayoutEditor.ApplyPosition(root, TwinFangs:GetVenomRosterPosition())
    root:Hide()
    ListenForScale()
    return root
end

---@return number
local function NameColumnWidth()
    return TwinFangs:GetVenomRosterNameColumnWidth()
end

---@return number
local function ColumnWidth()
    return NameColumnWidth() + STACK_HOST_WIDTH + NAME_STACK_GAP
end

---@param text string
---@return number
local function Utf8Len(text)
    local n = 0
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c < 192 then
            i = i + 1
        elseif c < 224 then
            i = i + 2
        elseif c < 240 then
            i = i + 3
        else
            i = i + 4
        end
        n = n + 1
    end
    return n
end

---@param text string
---@param charCount number
---@return string
local function Utf8Prefix(text, charCount)
    if charCount <= 0 then
        return ""
    end
    local i = 1
    local n = 0
    local len = #text
    while i <= len and n < charCount do
        local c = text:byte(i)
        if c < 192 then
            i = i + 1
        elseif c < 224 then
            i = i + 2
        elseif c < 240 then
            i = i + 3
        else
            i = i + 4
        end
        n = n + 1
    end
    return text:sub(1, i - 1)
end

---Fits `text` into `fontString`'s current width, appending an ellipsis when it overflows.
---@param fontString FontString
---@param text string
local function SetTruncatedText(fontString, text)
    fontString:SetText(text)
    local maxWidth = fontString:GetWidth()
    if type(maxWidth) ~= "number" or maxWidth <= 0 or not fontString.GetStringWidth then
        return
    end
    if fontString:GetStringWidth() <= maxWidth then
        return
    end
    local low, high = 0, Utf8Len(text)
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        fontString:SetText(Utf8Prefix(text, mid) .. ELLIPSIS)
        if fontString:GetStringWidth() <= maxWidth then
            low = mid
        else
            high = mid - 1
        end
    end
    if low <= 0 then
        fontString:SetText(ELLIPSIS)
        return
    end
    fontString:SetText(Utf8Prefix(text, low) .. ELLIPSIS)
end

---@param parent Frame
---@return TwinFangsVenomRosterColumnFrame
local function CreateColumn(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    return {
        frame = frame,
        rows = {},
    }
end

---@param fontString FontString
---@param fontName string
---@param size number
local function ApplyFont(fontString, fontName, size)
    local style = Assets.FontStyles[fontName]
    fontString:SetFont(style.path or STANDARD_TEXT_FONT, size, style.flags or "")
end

---@param fontString FontString
local function ApplyStackFont(fontString)
    ApplyFont(fontString, Fonts.OVERLAY_DIGIT, TwinFangs:GetVenomRosterStackFontSize())
    fontString:SetTextColor(Widgets.UnpackColor(STACK_COLOR))
end

---@param row TwinFangsVenomRosterRow
local function ApplyRowFonts(row)
    ApplyFont(row.nameText, Fonts.BODY, TwinFangs:GetVenomRosterNameFontSize())
    ApplyStackFont(row.stackText)
    if row.liveStackText then
        ApplyStackFont(row.liveStackText)
    end
end

---@param parent Frame
---@return TwinFangsVenomRosterRow
local function CreateRow(parent)
    local rowHeight = TwinFangs:GetVenomRosterRowSpacing()
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame:SetHeight(rowHeight)

    local stackHost = CreateFrame("Frame", nil, frame)
    stackHost:EnableMouse(false)
    stackHost:SetSize(STACK_HOST_WIDTH, rowHeight)
    stackHost:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local stackText = Widgets.CreateLabel(stackHost, Fonts.OVERLAY_DIGIT)
    stackText:SetJustifyH("RIGHT")
    stackText:SetPoint("RIGHT", stackHost, "RIGHT", 0, 0)

    local nameText = Widgets.CreateLabel(frame, Fonts.BODY)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    if nameText.SetMaxLines then
        nameText:SetMaxLines(1)
    end
    nameText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    nameText:SetWidth(NameColumnWidth())

    local row = {
        frame = frame,
        nameText = nameText,
        stackHost = stackHost,
        stackText = stackText,
        liveStackText = nil,
        container = nil,
        auraButton = nil,
        boundUnit = nil,
        auraPending = nil,
        applicationCountBound = nil,
        member = nil,
    }
    ApplyRowFonts(row)
    return row
end

---@param container Frame|nil
---@return boolean
local function CanConfigureAura(container)
    if Combat.IsLockedDown() then
        return false
    end
    if container and container.CanChangeProtectedState and not container:CanChangeProtectedState() then
        return false
    end
    return true
end

---@param row TwinFangsVenomRosterRow
---@return FontString
local function EnsureLiveStackText(row)
    if row.liveStackText then
        return row.liveStackText
    end
    local liveStackText = Widgets.CreateLabel(row.stackHost, Fonts.OVERLAY_DIGIT)
    liveStackText:SetJustifyH("RIGHT")
    liveStackText:SetPoint("RIGHT", row.stackHost, "RIGHT", 0, 0)
    if liveStackText.Hide then
        liveStackText:Hide()
    end
    row.liveStackText = liveStackText
    ApplyStackFont(liveStackText)
    return liveStackText
end

-- CreateFrame/AddAuraSlot are combat-protected. SetUnit on an existing container is allowed
-- in combat. Pending creates flush on combat leave. PlaceRow still ClearAllPoints/SetPoint on
-- ordinary row frames; if lockdown ever blocks that, names stay on the previous layout until
-- the next out-of-combat roster refresh. No speculative in-combat reanchor is attempted.
---@param row TwinFangsVenomRosterRow
---@return Frame|nil
local function EnsureAuraContainer(row)
    if row.container then
        return row.container
    end
    if not Aura.HasExpirationOnlyReverseSort() then
        return nil
    end
    if not CanConfigureAura() then
        row.auraPending = true
        return nil
    end
    local ok, container = pcall(
        CreateFrame,
        "AuraContainer",
        nil,
        row.stackHost,
        "CustomAuraContainerTemplate"
    )
    if not ok or not container then
        row.auraPending = true
        return nil
    end
    container:SetAllPoints(row.stackHost)
    container:EnableMouse(false)
    local sortMethod, sortDirection = Aura.GetExpirationOnlyReverseSort()
    local auraButton
    local configured = pcall(function()
        auraButton = container:AddAuraSlot(SLOT_KEY, Aura.FILTER_HARMFUL, {
            filterString = Aura.FILTER_HARMFUL,
            candidateFilters = {
                isFromPlayerOrPlayerPet = false,
                isBossOrRoleAura = false,
            },
            sortMethod = sortMethod,
            sortDirection = sortDirection,
            initializeFrame = function(button)
                row.auraButton = button
                if button.EnableMouse then
                    button:EnableMouse(false)
                end
                local icon = button.Icon or button.icon
                if icon and icon.Hide then
                    icon:Hide()
                end
                local liveStackText = EnsureLiveStackText(row)
                if not row.applicationCountBound then
                    local bound = pcall(function()
                        button:SetApplicationCount(liveStackText, {})
                    end)
                    if bound then
                        row.applicationCountBound = true
                    end
                end
            end,
        })
        if not auraButton then
            error("AddAuraSlot returned nil")
        end
        row.auraButton = auraButton
        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled(SLOT_KEY, false)
        end
        container:SetEnabled(false)
        container:Hide()
    end)
    if not configured then
        row.auraPending = true
        return nil
    end
    row.container = container
    row.auraPending = nil
    return container
end

---@param row TwinFangsVenomRosterRow
local function HideLiveStack(row)
    if row.liveStackText and row.liveStackText.Hide then
        row.liveStackText:Hide()
    end
    if row.stackText.Show then
        row.stackText:Show()
    end
end

---@param row TwinFangsVenomRosterRow
local function ShowLiveStack(row)
    if row.stackText.Hide then
        row.stackText:Hide()
    end
    row.stackText:SetText("")
    local liveStackText = row.liveStackText
    if liveStackText and liveStackText.Show then
        liveStackText:Show()
    end
end

---@param row TwinFangsVenomRosterRow
---@param clearBinding boolean|nil
local function DisableAuraContainer(row, clearBinding)
    local container = row.container
    if container then
        pcall(function()
            if container.SetAuraSlotEnabled then
                container:SetAuraSlotEnabled(SLOT_KEY, false)
            end
            if container.SetEnabled then
                container:SetEnabled(false)
            end
            container:Hide()
        end)
    end
    if clearBinding ~= false then
        row.boundUnit = nil
    end
    HideLiveStack(row)
end

---@param rosterInstance TwinFangsVenomRosterInstance
local function DisableAllAuras(rosterInstance)
    for _, column in ipairs(rosterInstance.columns) do
        for _, row in ipairs(column.rows) do
            DisableAuraContainer(row, false)
        end
    end
    rosterInstance.liveDisplay = false
end

---@param row TwinFangsVenomRosterRow
---@param unit string
---@param enable boolean|nil
local function BindAuraUnit(row, unit, enable)
    local container = EnsureAuraContainer(row)
    if not container then
        row.stackText:SetText("")
        HideLiveStack(row)
        return
    end
    if row.boundUnit ~= unit then
        pcall(function()
            container:SetUnit(unit)
        end)
        row.boundUnit = unit
    end
    if enable == false then
        DisableAuraContainer(row, false)
        return
    end
    if not CanConfigureAura(container) then
        ShowLiveStack(row)
        return
    end
    pcall(function()
        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled(SLOT_KEY, true)
        end
        container:SetEnabled(true)
        container:Show()
    end)
    ShowLiveStack(row)
end

---@param column TwinFangsVenomRosterColumnFrame
---@param slot number
---@param rowHeight number
---@param nameWidth number
local function PlaceRow(column, slot, rowHeight, nameWidth)
    local row = column.rows[slot]
    local y = -((slot - 1) * rowHeight)
    row.frame:ClearAllPoints()
    row.frame:SetHeight(rowHeight)
    row.frame:SetPoint("TOPLEFT", column.frame, "TOPLEFT", 0, y)
    row.frame:SetPoint("TOPRIGHT", column.frame, "TOPRIGHT", 0, y)
    row.stackHost:SetHeight(rowHeight)
    row.nameText:SetWidth(nameWidth)
end

---@param column TwinFangsVenomRosterColumnFrame
---@param slot number
---@return TwinFangsVenomRosterRow
local function EnsureRow(column, slot)
    local row = column.rows[slot]
    if row then
        return row
    end
    row = CreateRow(column.frame)
    column.rows[slot] = row
    return row
end

---@param rosterInstance TwinFangsVenomRosterInstance
---@param slot number
---@return TwinFangsVenomRosterColumnFrame
local function EnsureColumn(rosterInstance, slot)
    local column = rosterInstance.columns[slot]
    if column then
        return column
    end
    column = CreateColumn(rosterInstance.root)
    rosterInstance.columns[slot] = column
    return column
end

---@param row TwinFangsVenomRosterRow
---@param member TwinFangsVenomRosterMember|nil
---@param stack number|nil
---@param live boolean|nil
---@param enableAuras boolean|nil
local function BindRow(row, member, stack, live, enableAuras)
    row.member = member
    if not member then
        row.nameText:SetText("")
        row.stackText:SetText("")
        DisableAuraContainer(row)
        return
    end
    SetTruncatedText(row.nameText, member.name)
    local color = Unit.GetClassColor(member.classFile) or Colors.TEXT
    row.nameText:SetTextColor(Widgets.UnpackColor(color))
    if live then
        local unit = member.unit
        if type(unit) == "string" and unit ~= "" then
            BindAuraUnit(row, unit, enableAuras)
        else
            DisableAuraContainer(row)
            row.stackText:SetText("")
        end
        return
    end
    DisableAuraContainer(row, false)
    if stack ~= nil then
        row.stackText:SetText(tostring(stack))
    else
        row.stackText:SetText("")
    end
end

---@param rosterInstance TwinFangsVenomRosterInstance
local function ApplyFonts(rosterInstance)
    for _, column in ipairs(rosterInstance.columns) do
        for _, row in ipairs(column.rows) do
            ApplyRowFonts(row)
        end
    end
end

---@param rosterInstance TwinFangsVenomRosterInstance
---@param columns TwinFangsVenomRosterColumn[]
---@param stacks table<number, number>|nil
---@param live boolean|nil
---@param enableAuras boolean|nil
local function ApplyLayout(rosterInstance, columns, stacks, live, enableAuras)
    rosterInstance.boundColumns = columns
    rosterInstance.boundStacks = stacks
    rosterInstance.liveDisplay = live == true
    local aurasOn = live == true and enableAuras ~= false
    local rowHeight = TwinFangs:GetVenomRosterRowSpacing()
    local columnGap = TwinFangs:GetVenomRosterColumnSpacing()
    local nameWidth = NameColumnWidth()
    local columnWidth = ColumnWidth()
    local populated = #columns
    local maxRows = 0
    for slot = 1, populated do
        local data = columns[slot]
        maxRows = math.max(maxRows, #data.members)
        local column = EnsureColumn(rosterInstance, slot)
        column.frame:Show()
        column.frame:ClearAllPoints()
        column.frame:SetPoint("TOPLEFT", rosterInstance.root, "TOPLEFT", (slot - 1) * (columnWidth + columnGap), 0)
        column.frame:SetSize(columnWidth, #data.members * rowHeight)
        for rowSlot = 1, #data.members do
            local member = data.members[rowSlot]
            local row = EnsureRow(column, rowSlot)
            PlaceRow(column, rowSlot, rowHeight, nameWidth)
            row.frame:Show()
            local stack = stacks and stacks[member.index] or nil
            BindRow(row, member, stack, live, aurasOn)
        end
        for rowSlot = #data.members + 1, #column.rows do
            local row = column.rows[rowSlot]
            BindRow(row, nil)
            row.frame:Hide()
        end
    end
    for slot = populated + 1, #rosterInstance.columns do
        local column = rosterInstance.columns[slot]
        column.frame:Hide()
        for _, row in ipairs(column.rows) do
            BindRow(row, nil)
            row.frame:Hide()
        end
    end
    ApplyFonts(rosterInstance)
    ApplyScale(rosterInstance.root)
    if populated == 0 then
        rosterInstance.root:SetSize(0, 0)
        return
    end
    rosterInstance.root:SetSize(
        populated * columnWidth + (populated - 1) * columnGap,
        maxRows * rowHeight
    )
end

local function ClearBoundRoster()
    if not instance then
        return
    end
    ApplyLayout(instance, {}, nil)
end

local function ShowRoot()
    if not instance then
        return
    end
    instance.root:Show()
    instance.root:Raise()
end

local function HideRoot()
    if instance then
        instance.root:Hide()
    end
end

local function ApplyPreview(spec)
    local members = VenomRoster.BuildPreviewMembers(VenomRoster.CoercePreviewSpec(spec))
    local rosterInstance = VenomRosterUI.Ensure()
    ApplyLayout(rosterInstance, VenomRoster.Organize(members), VenomRoster.PreviewStacksByIndex(members), false)
end

---@param enableAuras boolean|nil
local function ApplyLiveRoster(enableAuras)
    local rosterInstance = VenomRosterUI.Ensure()
    local members = VenomRoster.CollectLiveMembers()
    local columns = VenomRoster.Organize(members)
    ApplyLayout(rosterInstance, columns, nil, true, enableAuras ~= false)
end

local function FlushPendingAuras()
    if layoutEditing or slashPreviewing then
        return
    end
    if helper:IsActive() then
        ApplyLiveRoster(true)
        return
    end
    if instance and TwinFangs:IsVenomRosterEnabled() and VenomRoster.IsInPitOfFangs() then
        ApplyLiveRoster(false)
        HideRoot()
    end
end

local function ListenForLiveRoster()
    if rosterListening then
        return
    end
    rosterListening = true
    ns.Api.Group.OnRosterChanged(function()
        if helper:IsActive() and not layoutEditing and not slashPreviewing then
            VenomRosterUI.Update()
        end
    end)
    ns.Api.Combat.OnLeave(FlushPendingAuras)
end

local function Register(frame)
    if layoutRegistered then
        return
    end
    layoutRegistered = true
    ns.LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.TWIN_FANGS_VENOM_ROSTER,
        frame = frame,
        global = false,
        isEnabled = function()
            return TwinFangs:IsVenomRosterEnabled()
        end,
        getPosition = function()
            return TwinFangs:GetVenomRosterPosition()
        end,
        setPosition = function(position)
            TwinFangs:SetVenomRosterPosition(position)
        end,
        getDefaultPosition = function()
            return Schema.DefaultVenomRosterPosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            ApplyPreview(VenomRoster.DEFAULT_PREVIEW_SPEC)
            ShowRoot()
        end,
        onEditEnd = function()
            layoutEditing = false
            ClearBoundRoster()
            VenomRosterUI.Update()
        end,
    })
end

local function CreateInstance()
    instance = {
        root = CreateRoot(),
        columns = {},
        boundColumns = nil,
        boundStacks = nil,
        liveDisplay = nil,
    }
    Register(instance.root)
    return instance
end

helper = ns.LazyEncounterUI.Create({
    create = CreateInstance,
    activate = function(rosterInstance)
        ListenForLiveRoster()
        if layoutEditing then
            return
        end
        ApplyLiveRoster(true)
        rosterInstance.root:Show()
        rosterInstance.root:Raise()
    end,
    deactivate = function(rosterInstance)
        DisableAllAuras(rosterInstance)
        rosterInstance.root:Hide()
    end,
})

function VenomRosterUI.Ensure()
    helper:Prepare()
    ApplyScale(instance.root)
    return instance
end

function VenomRosterUI.RefreshAppearance()
    if not instance then
        return
    end
    if instance.boundColumns then
        ApplyLayout(instance, instance.boundColumns, instance.boundStacks, instance.liveDisplay, helper:IsActive())
        return
    end
    ApplyScale(instance.root)
    ApplyFonts(instance)
end

local updating = false

function VenomRosterUI.Update()
    if updating then
        return
    end
    updating = true
    local ok, err = pcall(function()
        if layoutEditing then
            return
        end
        if not TwinFangs:IsVenomRosterEnabled() then
            HideRoot()
            return
        end
        if slashPreviewing then
            ShowRoot()
            return
        end
        if helper:IsActive() then
            ApplyLiveRoster(true)
            ShowRoot()
            return
        end
        HideRoot()
    end)
    updating = false
    if not ok then
        error(err)
    end
end

---@param members TwinFangsVenomRosterMember[]|nil
---@param stacks table<number, number>|nil
function VenomRosterUI.Apply(members, stacks)
    local rosterInstance = VenomRosterUI.Ensure()
    ApplyLayout(rosterInstance, VenomRoster.Organize(members), stacks, false)
end

---Creates AuraContainers in Pit of Fangs when the feature is on. No-op after the first success.
function VenomRosterUI.PrepareIfNeeded()
    if helper:IsPrepared() then
        return
    end
    if not TwinFangs:IsVenomRosterEnabled() then
        return
    end
    if not VenomRoster.IsInPitOfFangs() then
        return
    end
    helper:Prepare()
    if not helper:IsActive() then
        ApplyLiveRoster(false)
        HideRoot()
    end
end

---Enables or disables live AuraContainer binding. Encounter lifecycle and `/netvenom live` call this.
---@param active boolean
function VenomRosterUI.SetLiveActive(active)
    ListenForLiveRoster()
    if active then
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        slashPreviewing = false
        helper:SetActive(true)
    else
        slashPreviewing = false
        helper:SetActive(false)
    end
    VenomRosterUI.Update()
end

---@return boolean
function VenomRosterUI.IsLiveActive()
    return helper:IsActive()
end

---@return boolean
function VenomRosterUI.IsPrepared()
    return helper:IsPrepared()
end

---Development-only preview. Isolated from live combat; Edit Mode reuses the same mock builders.
---@param spec number|string|table|nil
function VenomRosterUI.ShowPreview(spec)
    slashPreviewing = true
    ApplyPreview(spec)
    helper:Prepare()
    ShowRoot()
end

function VenomRosterUI.HidePreview()
    slashPreviewing = false
    if not layoutEditing and not helper:IsActive() then
        ClearBoundRoster()
    end
    VenomRosterUI.Update()
end

function TwinFangs:OnVenomRosterEnabledChanged()
    if not TwinFangs:IsVenomRosterEnabled() then
        slashPreviewing = false
        if helper:IsActive() then
            VenomRosterUI.SetLiveActive(false)
        elseif instance and not layoutEditing then
            DisableAllAuras(instance)
            HideRoot()
        end
        if not layoutEditing then
            ClearBoundRoster()
        end
    else
        VenomRosterUI.PrepareIfNeeded()
        if TwinFangs:IsInEncounter() then
            VenomRosterUI.SetLiveActive(true)
        end
    end
    if ns.LayoutEditor.IsEditing() then
        ns.LayoutEditor.Refresh()
    end
    VenomRosterUI.Update()
end

function TwinFangs:PrepareVenomRoster()
    VenomRosterUI.PrepareIfNeeded()
end

function TwinFangs:SetVenomRosterEncounterActive(active)
    VenomRosterUI.SetLiveActive(active)
end

function TwinFangs:OnVenomRosterAppearanceChanged()
    VenomRosterUI.RefreshAppearance()
end

---@param spec number|string|table|nil
function TwinFangs:PreviewVenomRoster(spec)
    if spec == "hide" or spec == "off" or spec == false then
        VenomRosterUI.SetLiveActive(false)
        VenomRosterUI.HidePreview()
        return
    end
    if spec == "live" then
        VenomRosterUI.SetLiveActive(true)
        return
    end
    VenomRosterUI.ShowPreview(spec)
end

local function ListenForPitOfFangs()
    if zoneListening then
        return
    end
    zoneListening = true
    local function EvaluatePrewarm()
        VenomRosterUI.PrepareIfNeeded()
    end
    Instance.OnEnteringWorld(EvaluatePrewarm)
    Instance.OnZoneChangedIndoors(EvaluatePrewarm)
    Instance.OnZoneChangedNewArea(EvaluatePrewarm)
end

local previousEnable = TwinFangs.OnEnable
function TwinFangs:OnEnable()
    if previousEnable then
        previousEnable(self)
    end
    ListenForLiveRoster()
    ListenForPitOfFangs()
    VenomRosterUI.PrepareIfNeeded()
    VenomRosterUI.Update()
    ns.Api.Slash.Register("NEWERATOOLSTWINFANGSVENOM", { "/netvenom" }, function(input)
        input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
        if input == "" or input == "hide" or input == "off" then
            VenomRosterUI.SetLiveActive(false)
            VenomRosterUI.HidePreview()
            return
        end
        if input == "live" then
            VenomRosterUI.SetLiveActive(true)
            return
        end
        if input == "live off" then
            VenomRosterUI.SetLiveActive(false)
            return
        end
        local size = tonumber(input)
        VenomRosterUI.ShowPreview(size or input)
    end)
end
