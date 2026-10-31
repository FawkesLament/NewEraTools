local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets
local Unit = ns.Api.Unit

local Colors = Assets.Colors
local Fonts = Assets.Fonts

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local VenomRoster = Internals.VenomRoster

local LAYOUT_ID = "TwinFangs:venomRoster"
local STACK_HOST_WIDTH = 16
local NAME_STACK_GAP = 0
local ELLIPSIS = "…"
local STACK_COLOR = Colors.TEXT_GOLD

---@class TwinFangsVenomRosterRow
---@field frame Frame
---@field nameText FontString
---@field stackHost Frame
---@field stackText FontString
---@field member TwinFangsVenomRosterMember|nil

---@class TwinFangsVenomRosterColumnFrame
---@field frame Frame
---@field rows TwinFangsVenomRosterRow[]

---@class TwinFangsVenomRosterInstance
---@field root Frame
---@field columns TwinFangsVenomRosterColumnFrame[]
---@field boundColumns TwinFangsVenomRosterColumn[]|nil
---@field boundStacks table<number, number>|nil

local VenomRosterUI = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.VenomRosterUI = VenomRosterUI

---@type TwinFangsVenomRosterInstance|nil
local instance
local layoutRegistered = false
local layoutEditing = false
local slashPreviewing = false
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

---@param row TwinFangsVenomRosterRow
local function ApplyRowFonts(row)
    ApplyFont(row.nameText, Fonts.BODY, TwinFangs:GetVenomRosterNameFontSize())
    ApplyFont(row.stackText, Fonts.OVERLAY_DIGIT, TwinFangs:GetVenomRosterStackFontSize())
    row.stackText:SetTextColor(Widgets.UnpackColor(STACK_COLOR))
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
        member = nil,
    }
    ApplyRowFonts(row)
    return row
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
local function BindRow(row, member, stack)
    row.member = member
    if not member then
        row.nameText:SetText("")
        row.stackText:SetText("")
        return
    end
    SetTruncatedText(row.nameText, member.name)
    local color = Unit.GetClassColor(member.classFile) or Colors.TEXT
    row.nameText:SetTextColor(Widgets.UnpackColor(color))
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
local function ApplyLayout(rosterInstance, columns, stacks)
    rosterInstance.boundColumns = columns
    rosterInstance.boundStacks = stacks
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
            BindRow(row, member, stack)
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
    ApplyLayout(rosterInstance, VenomRoster.Organize(members), VenomRoster.PreviewStacksByIndex(members))
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
    }
    Register(instance.root)
    return instance
end

local helper = ns.LazyEncounterUI.Create({
    create = CreateInstance,
    activate = function(rosterInstance)
        rosterInstance.root:Show()
        rosterInstance.root:Raise()
    end,
    deactivate = function(rosterInstance)
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
        ApplyLayout(instance, instance.boundColumns, instance.boundStacks)
        return
    end
    ApplyScale(instance.root)
    ApplyFonts(instance)
end

function VenomRosterUI.Update()
    if layoutEditing then
        return
    end
    if slashPreviewing and TwinFangs:IsVenomRosterEnabled() then
        ShowRoot()
        return
    end
    HideRoot()
end

---@param members TwinFangsVenomRosterMember[]|nil
---@param stacks table<number, number>|nil
function VenomRosterUI.Apply(members, stacks)
    local rosterInstance = VenomRosterUI.Ensure()
    ApplyLayout(rosterInstance, VenomRoster.Organize(members), stacks)
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
    if not layoutEditing then
        ClearBoundRoster()
    end
    VenomRosterUI.Update()
end

function TwinFangs:OnVenomRosterEnabledChanged()
    if not TwinFangs:IsVenomRosterEnabled() then
        slashPreviewing = false
        if not layoutEditing then
            ClearBoundRoster()
        end
    end
    if ns.LayoutEditor.IsEditing() then
        ns.LayoutEditor.Refresh()
    end
    VenomRosterUI.Update()
end

function TwinFangs:OnVenomRosterAppearanceChanged()
    VenomRosterUI.RefreshAppearance()
end

---@param spec number|string|table|nil
function TwinFangs:PreviewVenomRoster(spec)
    if spec == "hide" or spec == "off" or spec == false then
        VenomRosterUI.HidePreview()
        return
    end
    VenomRosterUI.ShowPreview(spec)
end

local previousEnable = TwinFangs.OnEnable
function TwinFangs:OnEnable()
    if previousEnable then
        previousEnable(self)
    end
    VenomRosterUI.Ensure()
    VenomRosterUI.Update()
    ns.Api.Slash.Register("NEWERATOOLSTWINFANGSVENOM", { "/netvenom" }, function(input)
        input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
        if input == "" or input == "hide" or input == "off" then
            VenomRosterUI.HidePreview()
            return
        end
        local size = tonumber(input)
        VenomRosterUI.ShowPreview(size or input)
    end)
end
