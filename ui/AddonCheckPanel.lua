local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local AddonCheck = ns.AddonCheck
local FloatingWindow = ns.FloatingWindow
local Layout = ns.Layout
local Unit = ns.Api.Unit
local Widgets = ns.Widgets
local Model = ns.AddonCheckPanelModel

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Glyphs = Assets.Glyphs
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local STATUS_ICON_SIZE = 16

local AddonCheckPanel = {}
ns.AddonCheckPanel = AddonCheckPanel

AddonCheckPanel.Category = Model.Category
AddonCheckPanel.Filter = Model.Filter
AddonCheckPanel.SortColumn = Model.SortColumn
AddonCheckPanel.ConfigSortKey = Model.ConfigSortKey
AddonCheckPanel.BuildViewModel = Model.BuildViewModel
AddonCheckPanel.IndexRowsByKey = Model.IndexRowsByKey

local SortColumn = AddonCheckPanel.SortColumn

local LIST_ROW_HEIGHT = 22
local LIST_VISIBLE_ROWS = 8
-- Inset from the window chrome on every side.
local POPUP_PADDING = Spacing.XLARGE
-- Title bar: taller than the close control, with matching horizontal inset.
local HEADER_BAR_PADDING = Spacing.MEDIUM
local HEADER_BAR_HEIGHT = Sizes.CLOSE_BUTTON + 2 * HEADER_BAR_PADDING
-- Fixed table columns after party: player, version, status (module columns are extra).
local FIXED_TABLE_COLUMNS = 3
local COLUMN_SLOT_WIDTH = 80
-- Narrow leading party (#) column; digit-sized, not a full slot.
local PARTY_COLUMN_WIDTH = 28
local POPUP_MIN_WIDTH = 360
-- Match list rows: header must leave the same space as the scrollbar gutter.
local SCROLL_GUTTER = Sizes.SCROLL_BAR_WIDTH + Spacing.SMALL

---Window width from module column count so the table stays readable.
---@param moduleColumnCount integer
---@return number
local function ComputePopupWidth(moduleColumnCount)
    local flexibleColumns = FIXED_TABLE_COLUMNS + math.max(moduleColumnCount, 0)
    local cellCount = flexibleColumns + 1
    local gaps = Spacing.SMALL * math.max(cellCount - 1, 0)
    local tableWidth = PARTY_COLUMN_WIDTH + flexibleColumns * COLUMN_SLOT_WIDTH + gaps + SCROLL_GUTTER
    local width = tableWidth + 2 * POPUP_PADDING + 2 * Sizes.BORDER
    return math.max(POPUP_MIN_WIDTH, width)
end

---@class AddonCheckPanelOptions
---@field moduleId string
---@field columns AddonCheckPanelColumn[]
---@field title string|nil  Popup title; defaults to L.ADDONCHECK_TITLE.
---@field name string|nil  Optional global frame name for the popup (must be NewEraTools-prefixed).
---@field rowHeight number|nil  Member-row height; defaults to 22.
---@field listRows integer|nil  Visible row count; defaults to 8.
---@field isConfigMismatch fun(config: any, localConfig: any): boolean|nil  Optional; true → attention.
---@field validator fun(config: any, localConfig: any): string[]|nil  Optional; nil/empty = ok, else column `key`s to highlight.

---@param parent Frame
---@param font string
---@param wrap boolean|nil
---@return FontString
local function CreateCell(parent, font, wrap)
    local label = Widgets.CreateLabel(parent, font)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    if label.SetWordWrap then
        label:SetWordWrap(wrap == true)
    end
    return label
end

---@class AddonCheckPanelHeaderCell: Button
---@field baseTitle string
---@field sortKey string
---@field label FontString
---@field SetSortDirection fun(self: AddonCheckPanelHeaderCell, direction: "asc"|"desc"|nil)

---Clickable column header; shows ▲/▼ when this column is the active sort.
---@param parent Frame
---@param title string
---@param sortKey string
---@param onClick fun(sortKey: string)
---@param justifyH string|nil  Defaults to LEFT.
---@return AddonCheckPanelHeaderCell
local function CreateHeaderCell(parent, title, sortKey, onClick, justifyH)
    local cell = CreateFrame("Button", nil, parent) --[[@as AddonCheckPanelHeaderCell]]
    cell:SetHeight(LIST_ROW_HEIGHT)
    cell.baseTitle = title
    cell.sortKey = sortKey
    Widgets.AddHoverHighlight(cell)

    local label = Widgets.CreateLabel(cell, Fonts.MUTED)
    label:SetJustifyH(justifyH or "LEFT")
    label:SetJustifyV("MIDDLE")
    if label.SetWordWrap then
        label:SetWordWrap(false)
    end
    label:SetPoint("LEFT", cell, "LEFT", 0, 0)
    label:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
    label:SetText(title)
    cell.label = label

    function cell:SetSortDirection(direction)
        if direction == "asc" then
            self.label:SetText(self.baseTitle .. " " .. Glyphs.SORT_ASC)
        elseif direction == "desc" then
            self.label:SetText(self.baseTitle .. " " .. Glyphs.SORT_DESC)
        else
            self.label:SetText(self.baseTitle)
        end
    end

    cell:SetScript("OnClick", function()
        onClick(sortKey)
    end)
    return cell
end

---Status column host: icon with a tooltip for the detail label.
---Uses OVERLAY so the mark draws above row FontStrings (also OVERLAY).
---@param parent Frame
---@return Frame
local function CreateStatusCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:EnableMouse(true)
    cell:SetHeight(LIST_ROW_HEIGHT)
    local icon = cell:CreateTexture(nil, "OVERLAY")
    icon:SetSize(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
    icon:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cell.icon = icon
    Widgets.AttachTooltip(cell, "ANCHOR_TOP", function(tooltip)
        if cell.statusLabel and cell.statusLabel ~= "" then
            tooltip:SetText(cell.statusLabel)
        end
    end)
    return cell
end

---Lays out `cells` across `row` (minus optional `rightInset`, e.g. scrollbar gutter).
---First cell is a fixed narrow party column; remaining cells share the leftover width evenly.
---Pins TOPLEFT and height so Frame cells (status icons) are not left at 0×N and culled.
---@param row Frame
---@param cells Region[]
---@param spacing number
---@param rightInset number|nil
local function LayoutFullWidthRow(row, cells, spacing, rightInset)
    local count = #cells
    if count == 0 then
        return
    end
    local width = row:GetWidth() - (rightInset or 0)
    if not width or width <= 0 then
        return
    end
    local rowHeight = row:GetHeight()
    if not rowHeight or rowHeight < 1 then
        rowHeight = LIST_ROW_HEIGHT
    end

    local partyWidth = math.min(PARTY_COLUMN_WIDTH, width)
    local flexibleCount = count - 1
    local flexibleWidth = 0
    if flexibleCount > 0 then
        local remaining = width - partyWidth - spacing * (count - 1)
        if remaining < flexibleCount then
            return
        end
        flexibleWidth = remaining / flexibleCount
    end

    for i = 1, count do
        local cell = cells[i]
        local cellWidth = (i == 1) and partyWidth or flexibleWidth
        cell:ClearAllPoints()
        cell:SetSize(cellWidth, rowHeight)
        if i == 1 then
            cell:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        else
            cell:SetPoint("TOPLEFT", cells[i - 1], "TOPRIGHT", spacing, 0)
        end
    end
end

---Creates a floating results popup. Starts hidden; call Show() to open.
---@param options AddonCheckPanelOptions
---@return AddonCheckPanel
function AddonCheckPanel.Create(options)
    assert(type(options) == "table", "AddonCheckPanel.Create requires options")
    assert(type(options.moduleId) == "string" and options.moduleId ~= "", "AddonCheckPanel requires moduleId")
    assert(type(options.columns) == "table", "AddonCheckPanel requires columns")

    local moduleId = options.moduleId
    local columns = options.columns
    local rowHeight = options.rowHeight or LIST_ROW_HEIGHT
    local listHeight = (options.listRows or LIST_VISIBLE_ROWS) * rowHeight
    local unsubscribe = nil
    local unsubscribeScale = nil
    local listening = false
    local startError = nil
    ---@type string|nil  Active header sort; nil keeps raid roster order.
    local sortKey = nil
    local sortAscending = true
    ---@type integer|nil  Only the session started (or observed) while this popup is open.
    local boundSessionId = nil

    ---@type AddonCheckPanel
    local panel

    -- MainPanel loads after this file; resolve at call time.
    local function MainPanelScale()
        local mainPanel = ns.MainPanel
        if mainPanel and mainPanel.GetScale then
            return mainPanel.GetScale()
        end
        return 1
    end

    local window = FloatingWindow.Create({
        name = options.name,
        closable = true,
        scale = MainPanelScale(),
        onClose = function()
            panel:Hide()
        end,
    })
    Widgets.ApplyBackdrop(window, Colors.BG, Colors.BORDER)
    local popupWidth = ComputePopupWidth(#columns)
    window:SetSize(popupWidth, 200)
    window:SetFrameStrata("DIALOG")

    window.header:SetHeight(HEADER_BAR_HEIGHT)
    if window.closeButton then
        window.closeButton:ClearAllPoints()
        window.closeButton:SetPoint("RIGHT", window.header, "RIGHT", -HEADER_BAR_PADDING, 0)
    end

    local titleLabel = Widgets.CreateLabel(window.header, Fonts.TITLE, options.title or L.ADDONCHECK_TITLE)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetPoint("LEFT", window.header, "LEFT", HEADER_BAR_PADDING, 0)
    if window.closeButton then
        titleLabel:SetPoint("RIGHT", window.closeButton, "LEFT", -HEADER_BAR_PADDING, 0)
    else
        titleLabel:SetPoint("RIGHT", window.header, "RIGHT", -HEADER_BAR_PADDING, 0)
    end

    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", POPUP_PADDING, -(HEADER_BAR_HEIGHT + POPUP_PADDING))
    content:SetPoint("TOPRIGHT", -POPUP_PADDING, -(HEADER_BAR_HEIGHT + POPUP_PADDING))

    local body = Layout.Stack(content, { spacing = Spacing.SMALL })

    ---@type AddonCheckPanelHeaderCell[]
    local headerCells = {}
    local panelRefresh
    local UpdateHeaderSortIndicators
    local SetListening
    local BeginCheck

    local function OnHeaderSortClick(clickedKey)
        if sortKey == clickedKey then
            sortAscending = not sortAscending
        else
            sortKey = clickedKey
            sortAscending = true
        end
        UpdateHeaderSortIndicators()
        panelRefresh()
    end

    local headerRow = body:AddRow(LIST_ROW_HEIGHT)
    headerCells[#headerCells + 1] =
        CreateHeaderCell(headerRow, L.ADDONCHECK_COL_PARTY, SortColumn.PARTY, OnHeaderSortClick, "CENTER")
    headerCells[#headerCells + 1] =
        CreateHeaderCell(headerRow, L.ADDONCHECK_COL_PLAYER, SortColumn.PLAYER, OnHeaderSortClick)
    headerCells[#headerCells + 1] =
        CreateHeaderCell(headerRow, L.ADDONCHECK_COL_VERSION, SortColumn.VERSION, OnHeaderSortClick)
    for i = 1, #columns do
        headerCells[#headerCells + 1] =
            CreateHeaderCell(headerRow, columns[i].title, AddonCheckPanel.ConfigSortKey(i), OnHeaderSortClick)
    end
    headerCells[#headerCells + 1] =
        CreateHeaderCell(headerRow, L.ADDONCHECK_COL_STATUS, SortColumn.STATUS, OnHeaderSortClick)

    function UpdateHeaderSortIndicators()
        local direction = sortAscending and "asc" or "desc"
        for i = 1, #headerCells do
            local cell = headerCells[i]
            if sortKey and cell.sortKey == sortKey then
                cell:SetSortDirection(direction)
            else
                cell:SetSortDirection(nil)
            end
        end
    end

    headerRow:HookScript("OnSizeChanged", function()
        LayoutFullWidthRow(headerRow, headerCells, Spacing.SMALL, SCROLL_GUTTER)
    end)

    local listHost = body:Add(CreateFrame("Frame", nil, content), listHeight)
    local scrollFrame = CreateFrame("ScrollFrame", nil, listHost)
    scrollFrame:SetPoint("TOPLEFT", listHost, "TOPLEFT")
    scrollFrame:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(1)
    local scrollBar = CreateFrame("EventFrame", nil, listHost, Assets.Templates.SCROLL_BAR)
    scrollBar:SetPoint("TOPRIGHT", listHost, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT")
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)

    ---@type Frame[]
    local rowFrames = {}

    local function EnsureRowFrame(index)
        local row = rowFrames[index]
        if row then
            return row
        end
        row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(rowHeight)
        row.party = CreateCell(row, Fonts.BODY)
        row.party:SetJustifyH("CENTER")
        row.name = CreateCell(row, Fonts.BODY)
        row.version = CreateCell(row, Fonts.BODY)
        row.config = {}
        for i = 1, #columns do
            row.config[i] = CreateCell(row, Fonts.BODY)
        end
        row.status = CreateStatusCell(row)
        local cells = { row.party, row.name, row.version }
        for i = 1, #row.config do
            cells[#cells + 1] = row.config[i]
        end
        cells[#cells + 1] = row.status
        row.cells = cells
        row:HookScript("OnSizeChanged", function()
            LayoutFullWidthRow(row, row.cells, Spacing.SMALL)
        end)
        rowFrames[index] = row
        return row
    end

    local function ApplyNameColor(label, classFile)
        local color = Unit.GetClassColor(classFile) or Colors.TEXT
        label:SetTextColor(color.r, color.g, color.b, 1)
    end

    local function ApplyRowColor(label, category)
        if category == AddonCheckPanel.Category.ATTENTION then
            label:SetTextColor(Widgets.UnpackColor(Colors.WARNING))
        elseif category == AddonCheckPanel.Category.NO_RESPONSE then
            label:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
        else
            label:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
        end
    end

    ---@param invalidColumns string[]|nil
    ---@return table<string, boolean>
    local function InvalidColumnSet(invalidColumns)
        local set = {}
        if invalidColumns then
            for i = 1, #invalidColumns do
                set[invalidColumns[i]] = true
            end
        end
        return set
    end

    local function ApplyStatusIcon(cell, data)
        cell.statusLabel = data.statusLabel
        cell.icon:SetTexture(data.statusIcon)
        cell.icon:SetAlpha(1)
    end

    local function SyncWindowSize()
        local bodyHeight = body:GetHeight()
        content:SetHeight(math.max(bodyHeight, 1))
        local height = HEADER_BAR_HEIGHT + POPUP_PADDING + bodyHeight + POPUP_PADDING + 2 * Sizes.BORDER
        window:SetSize(popupWidth, height)
        LayoutFullWidthRow(headerRow, headerCells, Spacing.SMALL, SCROLL_GUTTER)
    end

    local function ResolveSession()
        local active = AddonCheck.GetActiveSession(moduleId)
        if active then
            return active
        end
        if boundSessionId then
            return AddonCheck.GetSession(boundSessionId)
        end
        return nil
    end

    function panelRefresh()
        local session = ResolveSession()
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = moduleId,
            columns = columns,
            filter = AddonCheckPanel.Filter.ALL,
            isConfigMismatch = options.isConfigMismatch,
            validator = options.validator,
            startError = startError,
            sortKey = sortKey,
            sortAscending = sortAscending,
        })

        local visibleCount = #model.visibleRows
        for i = 1, math.max(visibleCount, #rowFrames) do
            local frame = EnsureRowFrame(i)
            local data = model.visibleRows[i]
            if data then
                frame:Show()
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * rowHeight)
                frame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * rowHeight)
                frame.party:SetText(data.party)
                frame.name:SetText(data.playerName)
                frame.version:SetText(data.version)
                for c = 1, #columns do
                    local text = data.configValues[c] or L.ADDONCHECK_EM_DASH
                    frame.config[c]:SetText(text)
                    if frame.config[c].SetWordWrap then
                        frame.config[c]:SetWordWrap(text:find("\n", 1, true) ~= nil)
                    end
                end
                ApplyStatusIcon(frame.status, data)
                ApplyNameColor(frame.name, data.classFile)
                local invalidSet = InvalidColumnSet(data.invalidColumns)
                local hasInvalidColumns = next(invalidSet) ~= nil
                if hasInvalidColumns then
                    -- Only flagged config cells use warning; leave name/version/other cols normal.
                    frame.party:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
                    frame.version:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
                else
                    ApplyRowColor(frame.party, data.category)
                    ApplyRowColor(frame.version, data.category)
                end
                for c = 1, #columns do
                    local formatColor = data.configColors and data.configColors[c]
                    if formatColor then
                        frame.config[c]:SetTextColor(Widgets.UnpackColor(formatColor))
                    elseif invalidSet[columns[c].key] then
                        frame.config[c]:SetTextColor(Widgets.UnpackColor(Colors.WARNING))
                    elseif hasInvalidColumns then
                        frame.config[c]:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
                    else
                        ApplyRowColor(frame.config[c], data.category)
                    end
                end
                LayoutFullWidthRow(frame, frame.cells, Spacing.SMALL)
            else
                frame:Hide()
            end
        end
        scrollChild:SetHeight(math.max(visibleCount * rowHeight, 1))
        local listWidth = listHost:GetWidth()
        if listWidth and listWidth > 0 then
            local childWidth = math.max(listWidth - SCROLL_GUTTER, 1)
            scrollChild:SetWidth(childWidth)
            LayoutFullWidthRow(headerRow, headerCells, Spacing.SMALL, SCROLL_GUTTER)
            for i = 1, visibleCount do
                LayoutFullWidthRow(rowFrames[i], rowFrames[i].cells, Spacing.SMALL)
            end
        end

        SyncWindowSize()
    end

    function BeginCheck()
        startError = nil
        -- Never reuse a prior completed session's rows; each open starts clean.
        boundSessionId = nil
        local session, err = AddonCheck.StartCheck(moduleId)
        if not session then
            startError = string.format(L.ADDONCHECK_START_FAILED, tostring(err))
            panelRefresh()
            return
        end
        boundSessionId = session.id
        startError = nil
        panelRefresh()
    end

    local function OnSessionUpdated(session, _requestId)
        if not listening or not window:IsShown() then
            return
        end
        if session.moduleId ~= moduleId then
            return
        end
        -- Ignore updates for sessions other than the one this popup started.
        if boundSessionId and session.id ~= boundSessionId then
            return
        end
        boundSessionId = session.id
        panelRefresh()
    end

    local function SyncScale()
        window:SetWindowScale(MainPanelScale())
    end

    function SetListening(enabled)
        if enabled == listening then
            return
        end
        if unsubscribe then
            unsubscribe()
            unsubscribe = nil
        end
        if unsubscribeScale then
            unsubscribeScale()
            unsubscribeScale = nil
        end
        listening = enabled
        if enabled then
            SyncScale()
            unsubscribe = AddonCheck.OnUpdated(OnSessionUpdated)
            local mainPanel = ns.MainPanel
            if mainPanel and mainPanel.OnScaleChanged then
                unsubscribeScale = mainPanel.OnScaleChanged(function(scale)
                    window:SetWindowScale(scale)
                end)
            end
            panelRefresh()
        end
    end

    panel = {
        frame = window,
        window = window,
    }

    function panel:Show()
        boundSessionId = nil
        SetListening(true)
        SyncScale()
        BeginCheck()
        window:Show()
    end

    function panel:Hide()
        SetListening(false)
        boundSessionId = nil
        window:Hide()
    end

    function panel:IsShown()
        return window:IsShown()
    end

    function panel:Refresh()
        if window:IsShown() then
            panelRefresh()
        end
    end

    ---Unsubscribes listeners and hides the popup.
    function panel:Destroy()
        SetListening(false)
        boundSessionId = nil
        window:Hide()
    end

    window:Hide()
    return panel
end
