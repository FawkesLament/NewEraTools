---Read-only assignment cards for one or more interrupt chains.
local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Spacing = Assets.Spacing

local ACCENT_WIDTH = 2
local CARD_HEADER = 18
local PLAYER_ROW_HEIGHT = 16
local EMPTY_HEIGHT = 18
local YOU_WIDTH = 56
local NUMBER_WIDTH = 56
local HIGHLIGHT_ALPHA = 0.12
local ACCENT_ALPHA = 0.9

local InterruptChainView = {}
ns.InterruptChainView = InterruptChainView

---Single interrupt or a consecutive run, e.g. `#3` or `#2–4`.
---@param first integer
---@param last integer|nil
---@return string
function InterruptChainView.FormatSequence(first, last)
    last = last or first
    if last <= first then
        return string.format(L.INTERRUPT_SEQUENCE, first)
    end
    return string.format(L.INTERRUPT_SEQUENCE_RANGE, first, last)
end

---Collapsed runs from sorted 1-based indices, e.g. `#1, #3, #5` or `#1–2, #4–6`.
---@param indices integer[]|nil
---@return string
function InterruptChainView.FormatIndices(indices)
    if type(indices) ~= "table" or not indices[1] then
        return ""
    end
    local parts = {}
    local runStart = indices[1]
    local runEnd = indices[1]
    for index = 2, #indices do
        local value = indices[index]
        if value == runEnd + 1 then
            runEnd = value
        else
            parts[#parts + 1] = InterruptChainView.FormatSequence(runStart, runEnd)
            runStart = value
            runEnd = value
        end
    end
    parts[#parts + 1] = InterruptChainView.FormatSequence(runStart, runEnd)
    return table.concat(parts, L.INTERRUPT_SEQUENCE_JOIN)
end

---@class InterruptChainViewEntry
---@field slot string|number  Displayed slot, e.g. "#1" or "#2–4".
---@field text string  Player name, unassigned placeholder, or custom text.
---@field highlight boolean|nil  Marks the local player's row.
---@field color { r: number, g: number, b: number }|nil  Name color when not using the default.

---@class InterruptChainViewChain
---@field title string
---@field accent { r: number, g: number, b: number }|nil
---@field entries InterruptChainViewEntry[]|nil
---@field emptyText string|nil  Shown when `entries` is empty.
---@field footer string|nil  Optional secondary line, such as a backup assignment.
---@field footerHighlight boolean|nil

---@class InterruptChainViewData
---@field youText string|nil  Marker on highlighted rows.
---@field chains InterruptChainViewChain[]

---@class InterruptChainViewWidget
---@field frame Frame
---@field SetData fun(self: InterruptChainViewWidget, data: InterruptChainViewData)
---@field GetHeight fun(self: InterruptChainViewWidget): number

---@param parent Frame
---@param color { r: number, g: number, b: number }
---@return Texture
local function AddAccentBar(parent, color)
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(ACCENT_WIDTH)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetColorTexture(color.r, color.g, color.b, ACCENT_ALPHA)
    return bar
end

---@param parent Frame
---@return Texture
local function AddYouHighlight(parent)
    local highlight = parent:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:Hide()
    return highlight
end

---@param row Frame
---@param accent { r: number, g: number, b: number }
---@param isYou boolean
---@param youText string
local function ApplyYouHighlight(row, accent, isYou, youText)
    if isYou then
        row.highlight:SetColorTexture(accent.r, accent.g, accent.b, HIGHLIGHT_ALPHA)
        row.highlight:Show()
        row.you:SetText(youText)
        row.you:SetTextColor(Widgets.UnpackColor(accent))
    else
        row.highlight:Hide()
        row.you:SetText("")
    end
end

---@param parent Frame
---@return Frame
local function CreateAssignmentCard(parent)
    local card = CreateFrame("Frame", nil, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(card, Colors.SURFACE_RAISED, Colors.BORDER)
    card.accent = AddAccentBar(card, Colors.ACCENT)

    local title = Widgets.CreateLabel(card, Fonts.BODY)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("MIDDLE")
    title:SetHeight(CARD_HEADER)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", Spacing.MEDIUM + ACCENT_WIDTH, -Spacing.MEDIUM)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -Spacing.SMALL, -Spacing.MEDIUM)
    card.title = title

    local backupRow = CreateFrame("Frame", nil, card)
    backupRow:SetHeight(PLAYER_ROW_HEIGHT)
    backupRow:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", Spacing.MEDIUM + ACCENT_WIDTH, Spacing.SMALL)
    backupRow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -Spacing.SMALL, Spacing.SMALL)
    backupRow.highlight = AddYouHighlight(backupRow)
    card.backupRow = backupRow

    local you = Widgets.CreateLabel(backupRow, Fonts.TINY_MUTED)
    you:SetJustifyH("RIGHT")
    you:SetWidth(YOU_WIDTH)
    you:SetPoint("RIGHT", backupRow, "RIGHT", -Spacing.MEDIUM, 0)
    backupRow.you = you

    local backup = Widgets.CreateLabel(backupRow, Fonts.TINY_MUTED)
    backup:SetJustifyH("LEFT")
    backup:SetJustifyV("MIDDLE")
    backup:SetPoint("LEFT", backupRow, "LEFT")
    backup:SetPoint("RIGHT", you, "LEFT", -Spacing.SMALL, 0)
    card.backup = backup

    local list = CreateFrame("Frame", nil, card)
    list:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Spacing.TINY)
    list:SetPoint("BOTTOMRIGHT", backupRow, "TOPRIGHT", 0, Spacing.TINY)
    card.list = list
    card.playerRows = {}

    local empty = Widgets.CreateLabel(list, Fonts.SMALL_MUTED)
    empty:SetJustifyH("LEFT")
    empty:SetPoint("TOPLEFT")
    empty:SetPoint("TOPRIGHT")
    empty:SetHeight(EMPTY_HEIGHT)
    card.empty = empty

    return card
end

---@param card Frame
---@param index number
---@return Frame
local function EnsurePlayerRow(card, index)
    local row = card.playerRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, card.list)
    row:SetHeight(PLAYER_ROW_HEIGHT)
    row.highlight = AddYouHighlight(row)

    local number = Widgets.CreateLabel(row, Fonts.EMPHASIS)
    number:SetJustifyH("RIGHT")
    number:SetWidth(NUMBER_WIDTH)
    number:SetPoint("LEFT", row, "LEFT")
    row.number = number

    local you = Widgets.CreateLabel(row, Fonts.TINY_MUTED)
    you:SetJustifyH("RIGHT")
    you:SetWidth(YOU_WIDTH)
    you:SetPoint("RIGHT", row, "RIGHT", -Spacing.MEDIUM, 0)
    row.you = you

    local name = Widgets.CreateLabel(row, Fonts.BODY)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetPoint("LEFT", number, "RIGHT", Spacing.SMALL, 0)
    name:SetPoint("RIGHT", you, "LEFT", -Spacing.SMALL, 0)
    row.name = name

    card.playerRows[index] = row
    return row
end

---@param card Frame
---@param host Frame
local function PlaceCard(card, host)
    card:SetParent(host)
    card:ClearAllPoints()
    card:SetAllPoints(host)
end

---@param card Frame
---@return number
local function CardHeight(card)
    local count = card.playerCount or 0
    local listHeight = count == 0 and EMPTY_HEIGHT or count * PLAYER_ROW_HEIGHT
    local footerHeight = card.hasFooter and (Spacing.TINY + PLAYER_ROW_HEIGHT + Spacing.SMALL) or Spacing.SMALL
    return Spacing.MEDIUM + CARD_HEADER + Spacing.TINY + listHeight + footerHeight
end

---@param card Frame
---@param hasFooter boolean
local function AnchorList(card, hasFooter)
    card.list:ClearAllPoints()
    card.list:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -Spacing.TINY)
    if hasFooter then
        card.list:SetPoint("BOTTOMRIGHT", card.backupRow, "TOPRIGHT", 0, Spacing.TINY)
    else
        card.list:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -Spacing.SMALL, Spacing.SMALL)
    end
end

---@param card Frame
---@param chain InterruptChainViewChain
---@param youText string
local function RefreshAssignmentCard(card, chain, youText)
    local accent = chain.accent or Colors.ACCENT
    card.accent:SetColorTexture(accent.r, accent.g, accent.b, ACCENT_ALPHA)
    card.title:SetText(chain.title or "")

    local entries = chain.entries or {}
    local count = #entries
    card.playerCount = count
    if count == 0 then
        card.empty:SetText(chain.emptyText or "")
        card.empty:Show()
        for _, row in ipairs(card.playerRows) do
            row:Hide()
        end
    else
        card.empty:Hide()
        for index, entry in ipairs(entries) do
            local row = EnsurePlayerRow(card, index)
            local isYou = entry.highlight == true
            local color = entry.color
            if not color then
                color = isYou and accent or Colors.TEXT
            end
            row.number:SetText(tostring(entry.slot or ""))
            row.number:SetTextColor(Widgets.UnpackColor(accent))
            row.name:SetText(entry.text or "")
            row.name:SetTextColor(Widgets.UnpackColor(color))
            ApplyYouHighlight(row, accent, isYou, youText)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", card.list, "TOPLEFT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:SetPoint("TOPRIGHT", card.list, "TOPRIGHT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:Show()
        end
        for index = count + 1, #card.playerRows do
            card.playerRows[index]:Hide()
        end
    end

    local footer = chain.footer
    local hasFooter = footer ~= nil
    card.hasFooter = hasFooter
    AnchorList(card, hasFooter)
    if hasFooter then
        card.backup:SetText(footer)
        if chain.footerHighlight then
            card.backup:SetTextColor(Widgets.UnpackColor(accent))
        else
            card.backup:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
        end
        ApplyYouHighlight(card.backupRow, accent, chain.footerHighlight == true, youText)
        card.backupRow:Show()
    else
        card.backupRow:Hide()
    end
end

---Creates a reusable read-only chain display that fills `parent`.
---@param parent Frame
---@return InterruptChainViewWidget
function InterruptChainView.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    ---@type Frame[]
    local cells = {}
    ---@type Frame[]
    local cards = {}
    local height = 1
    local columnCount = 0

    local function ApplyColumnWidths(width)
        if not width or width <= 0 or columnCount < 3 then
            return
        end
        local gap = Spacing.MEDIUM
        local cellWidth = math.max((width - gap * (columnCount - 1)) / columnCount, 1)
        for index = 1, columnCount do
            local x = (index - 1) * (cellWidth + gap)
            local cell = cells[index]
            cell:ClearAllPoints()
            cell:SetWidth(cellWidth)
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
            cell:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
        end
    end

    ---@param count integer
    local function ShowCells(count)
        columnCount = count
        while #cells < count do
            cells[#cells + 1] = CreateFrame("Frame", nil, frame)
        end
        for index, cell in ipairs(cells) do
            if index <= count then
                cell:Show()
            else
                cell:Hide()
            end
        end
        if count == 2 then
            local halfGap = Spacing.MEDIUM / 2
            cells[1]:ClearAllPoints()
            cells[1]:SetPoint("TOPLEFT")
            cells[1]:SetPoint("BOTTOMLEFT")
            cells[1]:SetPoint("RIGHT", frame, "CENTER", -halfGap, 0)
            cells[2]:ClearAllPoints()
            cells[2]:SetPoint("TOPRIGHT")
            cells[2]:SetPoint("BOTTOMRIGHT")
            cells[2]:SetPoint("LEFT", frame, "CENTER", halfGap, 0)
        elseif count > 2 then
            ApplyColumnWidths(frame:GetWidth())
        end
    end

    ---@param index integer
    ---@return Frame
    local function EnsureCard(index)
        local card = cards[index]
        if card then
            return card
        end
        card = CreateAssignmentCard(frame)
        cards[index] = card
        return card
    end

    frame:HookScript("OnSizeChanged", function(_, width)
        ApplyColumnWidths(width)
    end)

    local view = { frame = frame }

    ---Applies prepared chain display data. Callers own encounter-specific models.
    ---@param data InterruptChainViewData
    function view:SetData(data)
        assert(type(data) == "table", "InterruptChainView.SetData requires a data table")
        local chains = data.chains or {}
        local youText = data.youText or ""
        local count = #chains

        if count == 0 then
            ShowCells(0)
            for _, card in ipairs(cards) do
                card:Hide()
            end
            height = 1
            return
        end

        if count == 1 then
            ShowCells(0)
            local card = EnsureCard(1)
            RefreshAssignmentCard(card, chains[1], youText)
            PlaceCard(card, frame)
            card:Show()
            for index = 2, #cards do
                cards[index]:Hide()
            end
            height = CardHeight(card)
            return
        end

        ShowCells(count)
        local tallest = 1
        for index, chain in ipairs(chains) do
            local card = EnsureCard(index)
            RefreshAssignmentCard(card, chain, youText)
            PlaceCard(card, cells[index])
            card:Show()
            tallest = math.max(tallest, CardHeight(card))
        end
        for index = count + 1, #cards do
            cards[index]:Hide()
        end
        height = tallest
    end

    ---@return number
    function view:GetHeight()
        return height
    end

    return view
end
