local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local WarningWindow = ns.WarningWindow
local Widgets = ns.Widgets
local Group = ns.Api.Group
local Player = ns.Api.Player
local Unit = ns.Api.Unit

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing

local CoiledAltar = ns.Modules.Get("CoiledAltar")
local Assignments = Internals.InterruptAssignments

local MODE_PLAYER = "player"
local MODE_TEXT = "text"
local SLOT_HEIGHT = Sizes.CONTROL_HEIGHT
local SEQUENCE_WIDTH = 16
local GROUP_HEADER_HEIGHT = 16
local ROSTER_ROW_HEIGHT = 20
local GROUP_COLUMNS = 4
local DESC_MIN_HEIGHT = 16

local CHAIN_ACCENTS = {
    [Assignments.MELEE] = Colors.ACCENT,
    [Assignments.RANGED] = Colors.STATUS_HUD_STANDBY,
}

local Editor = {}
Internals.InterruptAssignmentsUI = Editor

local selectedChain = Assignments.MELEE
local selectedIndex = 1
local editMode = MODE_PLAYER
local lastAssignError
local ui
local confirmWindow
local Refresh

---@param classFile string|nil
---@return { r: number, g: number, b: number }
local function ClassColor(classFile)
    return Unit.GetClassColor(classFile) or Colors.TEXT
end

---@param name string
---@return string
local function ShortName(name)
    return name:match("^([^-]+)") or name
end

---@param slot CoiledAltarInterruptSlot
---@param roster RaidMember[]
---@return string, { r: number, g: number, b: number }
local function SlotDisplay(slot, roster)
    if slot.type == Assignments.TYPE_TEXT then
        return slot.value or "", Colors.TEXT_GOLD
    end
    if slot.type == Assignments.TYPE_PLAYER then
        local stored = slot.value or ""
        for _, member in ipairs(roster) do
            if Assignments.QualifyName(member.fullName or member.name) == stored then
                return member.name, ClassColor(member.classFile)
            end
        end
        return ShortName(stored), Colors.TEXT
    end
    return L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY, Colors.TEXT_MUTED
end

---Raid members when grouped; otherwise only the local character.
---@return RaidMember[]
local function EditorRoster()
    if Group.IsInGroup() then
        return Group.GetRaidMembers()
    end
    local fullName = Player.GetFullName()
    if not fullName then
        return {}
    end
    local name = Unit.GetName("player") or ShortName(fullName)
    return {
        {
            name = name,
            fullName = fullName,
            guid = Player.GetGUID(),
            index = 1,
            subgroup = 0,
            classFile = Player.GetClassFile(),
            role = Player.GetRole() or "NONE",
            unit = "player",
        },
    }
end

---@param occupiedChain CoiledAltarInterruptChainId|nil
---@return string
local function CrossChainAssignText(occupiedChain)
    if occupiedChain == Assignments.MELEE then
        return L.COILED_ALTAR_INTERRUPT_CROSS_CHAIN_MELEE
    end
    return L.COILED_ALTAR_INTERRUPT_CROSS_CHAIN_RANGED
end

---@param name string
local function TryAssignPlayer(name)
    local ok, err, occupiedChain = CoiledAltar:AssignInterruptPlayer(selectedChain, selectedIndex, name)
    if ok then
        return
    end
    if err == "CROSS_CHAIN" then
        lastAssignError = CrossChainAssignText(occupiedChain)
        Refresh()
    end
end

---@param parent Frame
---@param maxLetters integer
---@return EditBox
local function CreateTextBox(parent, maxLetters)
    local box = CreateFrame("EditBox", nil, parent, Assets.Templates.BACKDROP)
    Widgets.ApplyBackdrop(box, Colors.SURFACE, Colors.BORDER)
    Widgets.EnsureFonts()
    box:SetFontObject(Fonts.BODY)
    box:SetHeight(Sizes.INPUT_HEIGHT)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    box:SetJustifyH("LEFT")
    box:SetTextInsets(Spacing.MEDIUM, Spacing.MEDIUM, 0, 0)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.ACCENT))
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(Widgets.UnpackColor(Colors.BORDER))
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
---@param chainId CoiledAltarInterruptChainId
---@return Frame
local function BuildChain(parent, chainId)
    local chain = CreateFrame("Frame", nil, parent)
    local title = Widgets.CreateLabel(chain, Fonts.BODY)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetTextColor(Widgets.UnpackColor(CHAIN_ACCENTS[chainId] or Colors.TEXT))
    if chainId == Assignments.MELEE then
        title:SetText(L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE)
    else
        title:SetText(L.COILED_ALTAR_INTERRUPT_CHAIN_RANGED)
    end

    local slots = {}
    for index = 1, Assignments.SLOT_COUNT do
        local slot = CreateFrame("Button", nil, chain, Assets.Templates.BACKDROP) --[[@as Button]]
        Widgets.ApplyBackdrop(slot, Colors.SURFACE_RAISED, Colors.BORDER)
        Widgets.AddHoverHighlight(slot)
        local y = -(GROUP_HEADER_HEIGHT + (index - 1) * SLOT_HEIGHT)
        slot:SetPoint("TOPLEFT", chain, "TOPLEFT", 0, y)
        slot:SetPoint("TOPRIGHT", chain, "TOPRIGHT", 0, y)
        slot:SetHeight(SLOT_HEIGHT)

        local number = Widgets.CreateLabel(slot, Fonts.EMPHASIS, tostring(index))
        number:SetJustifyH("CENTER")
        number:SetWidth(SEQUENCE_WIDTH)
        number:SetPoint("LEFT", slot, "LEFT", Spacing.TINY, 0)
        number:SetTextColor(Widgets.UnpackColor(CHAIN_ACCENTS[chainId] or Colors.TEXT))
        slot.number = number

        local name = Widgets.CreateLabel(slot, Fonts.BODY)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetPoint("LEFT", number, "RIGHT", Spacing.SMALL, 0)
        slot.name = name

        local clear = Widgets.CreateTextButton(slot, Assets.Glyphs.CLOSE, function()
            CoiledAltar:ClearInterruptAssignment(chainId, index)
        end, Fonts.LINK_DANGER)
        clear:SetPoint("RIGHT", slot, "RIGHT", -Spacing.TINY, 0)
        clear:SetFrameLevel(slot:GetFrameLevel() + 1)
        name:SetPoint("RIGHT", clear, "LEFT", -Spacing.TINY, 0)
        slot.clear = clear

        slot:SetScript("OnClick", function()
            selectedChain = chainId
            selectedIndex = index
            lastAssignError = nil
            local assigned = CoiledAltar:GetInterruptSlot(chainId, index)
            if assigned and assigned.type == Assignments.TYPE_TEXT then
                editMode = MODE_TEXT
            else
                editMode = MODE_PLAYER
            end
            Refresh()
        end)
        slots[index] = slot
    end
    chain.slots = slots
    return chain
end

---@param parent Frame
---@return Frame
local function BuildChains(parent)
    local row = CreateFrame("Frame", nil, parent)
    local left, right = Layout.SplitRow(row, Spacing.MEDIUM)
    row.melee = BuildChain(left, Assignments.MELEE)
    row.ranged = BuildChain(right, Assignments.RANGED)
    row.melee:SetAllPoints(left)
    row.ranged:SetAllPoints(right)
    return row
end

---@param members RaidMember[]
---@return number[], table<number, RaidMember[]>
local function GroupedRoster(members)
    local groups = {}
    local order = {}
    for _, member in ipairs(members) do
        local subgroup = member.subgroup
        if type(subgroup) ~= "number" then
            subgroup = 0
        end
        if not groups[subgroup] then
            groups[subgroup] = {}
            order[#order + 1] = subgroup
        end
        groups[subgroup][#groups[subgroup] + 1] = member
    end
    table.sort(order)
    for _, subgroup in ipairs(order) do
        table.sort(groups[subgroup], function(left, right)
            return (left.index or 0) < (right.index or 0)
        end)
    end
    return order, groups
end

---@param parent Frame
---@param index integer
---@return Frame
local function EnsureGroupColumn(parent, index)
    local column = parent.columns[index]
    if column then
        return column
    end
    column = CreateFrame("Frame", nil, parent)
    column.header = Widgets.CreateLabel(column, Fonts.TINY_MUTED)
    column.header:SetJustifyH("LEFT")
    column.header:SetPoint("TOPLEFT")
    column.header:SetPoint("TOPRIGHT")
    column.buttons = {}
    parent.columns[index] = column
    return column
end

---@param column Frame
---@param index integer
---@return Button
local function EnsureRosterButton(column, index)
    local button = column.buttons[index]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, column, Assets.Templates.BACKDROP) --[[@as Button]]
    Widgets.ApplyBackdrop(button, Colors.SURFACE, Colors.BORDER)
    Widgets.AddHoverHighlight(button)
    button:SetHeight(ROSTER_ROW_HEIGHT)
    local name = Widgets.CreateLabel(button, Fonts.BODY)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetPoint("LEFT", button, "LEFT", Spacing.SMALL, 0)
    name:SetPoint("RIGHT", button, "RIGHT", -Spacing.SMALL, 0)
    button.name = name
    button:SetScript("OnClick", function(self)
        if not self.member then
            return
        end
        TryAssignPlayer(self.member.fullName or self.member.name)
    end)
    Widgets.AttachTooltip(button, "ANCHOR_TOP", function(tooltip)
        if not button.blocked or not button.blockedText then
            return
        end
        local r, g, b = Widgets.UnpackColor(Colors.ERROR)
        tooltip:AddLine(button.blockedText, r, g, b)
    end)
    column.buttons[index] = button
    return button
end

local function RefreshSlots()
    local roster = EditorRoster()
    local function Paint(chainFrame, chainId)
        for index, slot in ipairs(chainFrame.slots) do
            local assigned = CoiledAltar:GetInterruptSlot(chainId, index) or { type = Assignments.TYPE_EMPTY }
            local text, color = SlotDisplay(assigned, roster)
            slot.name:SetText(text)
            slot.name:SetTextColor(Widgets.UnpackColor(color))
            local occupied = assigned.type == Assignments.TYPE_PLAYER or assigned.type == Assignments.TYPE_TEXT
            slot.clear:SetShown(occupied)
            if occupied then
                slot.name:SetPoint("RIGHT", slot.clear, "LEFT", -Spacing.TINY, 0)
            else
                slot.name:SetPoint("RIGHT", slot, "RIGHT", -Spacing.SMALL, 0)
            end
            local selected = selectedChain == chainId and selectedIndex == index
            Widgets.ApplyBackdrop(slot, Colors.SURFACE_RAISED, selected and Colors.ACCENT or Colors.BORDER)
        end
    end
    Paint(ui.chains.melee, Assignments.MELEE)
    Paint(ui.chains.ranged, Assignments.RANGED)
end

local function HidePlayerExtras()
    ui.emptyHint:Hide()
    ui.rosterGrid:Hide()
    ui.playerStack:SetEntryHeight(ui.emptyHintRow, 1)
    ui.playerStack:SetEntryHeight(ui.rosterGrid, 1)
end

local function RefreshValidation()
    local text = lastAssignError
    if not text then
        local names = Assignments.CrossChainPlayers(CoiledAltar:GetInterruptAssignments())
        if #names > 0 then
            local shown = {}
            for index, name in ipairs(names) do
                shown[index] = ShortName(name)
            end
            text = string.format(L.COILED_ALTAR_INTERRUPT_CROSS_CHAIN_WARNING, table.concat(shown, "、"))
        end
    end
    if text then
        ui.validation:SetText(text)
        ui.validation:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
        ui.validation:SetWidth(math.max(ui.desc:GetWidth() or 0, 1))
        ui.stack:SetEntryHeight(ui.validationRow, math.max(ui.validation:GetStringHeight() or 0, DESC_MIN_HEIGHT))
        return
    end
    ui.validation:SetText("")
    ui.stack:SetEntryHeight(ui.validationRow, 1)
end

local function RefreshRoster()
    local members = EditorRoster()
    local grid = ui.rosterGrid
    if #members == 0 then
        grid:Hide()
        ui.emptyHint:Show()
        ui.emptyHint:SetText(L.COILED_ALTAR_INTERRUPT_ROSTER_EMPTY)
        ui.playerStack:SetEntryHeight(ui.emptyHintRow, math.max(ui.emptyHint:GetStringHeight(), DESC_MIN_HEIGHT))
        ui.playerStack:SetEntryHeight(grid, 1)
        return
    end

    ui.emptyHint:Hide()
    ui.playerStack:SetEntryHeight(ui.emptyHintRow, 1)

    local order, groups = GroupedRoster(members)
    local width = math.max(grid:GetWidth() or 0, 1)
    local columns = math.min(GROUP_COLUMNS, math.max(#order, 1))
    local gap = Spacing.SMALL
    local columnWidth = math.max((width - gap * (columns - 1)) / columns, 1)
    local rows = math.max(math.ceil(math.max(#order, 1) / columns), 1)
    local tallest = 1
    for _, subgroup in ipairs(order) do
        tallest = math.max(tallest, #groups[subgroup])
    end
    local columnHeight = GROUP_HEADER_HEIGHT + tallest * ROSTER_ROW_HEIGHT
    local height = rows * columnHeight + math.max(rows - 1, 0) * gap

    for index, subgroup in ipairs(order) do
        local column = EnsureGroupColumn(grid, index)
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x = col * (columnWidth + gap)
        local y = -row * (columnHeight + gap)
        column:ClearAllPoints()
        column:SetPoint("TOPLEFT", grid, "TOPLEFT", x, y)
        column:SetSize(columnWidth, columnHeight)
        if subgroup > 0 then
            column.header:SetText(string.format(L.COILED_ALTAR_INTERRUPT_RAID_GROUP, subgroup))
        else
            column.header:SetText(L.COILED_ALTAR_INTERRUPT_RAID_GROUP_UNKNOWN)
        end
        column:Show()
        local list = groups[subgroup]
        for memberIndex, member in ipairs(list) do
            local button = EnsureRosterButton(column, memberIndex)
            button.member = member
            button.name:SetText(member.name)
            local yOffset = -(GROUP_HEADER_HEIGHT + (memberIndex - 1) * ROSTER_ROW_HEIGHT)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", column, "TOPLEFT", 0, yOffset)
            button:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, yOffset)
            local assigned = CoiledAltar:GetInterruptSlot(selectedChain, selectedIndex)
            local identity = Assignments.QualifyName(member.fullName or member.name)
            local onSlot = assigned and assigned.type == Assignments.TYPE_PLAYER and assigned.value == identity
            local opposite = Assignments.OppositeChain(selectedChain)
            local blocked = opposite
                and Assignments.ChainHasPlayer(CoiledAltar:GetInterruptAssignments(), opposite, identity)
            button.blocked = blocked
            button.blockedText = blocked and CrossChainAssignText(opposite) or nil
            button:SetAlpha(blocked and 0.4 or 1)
            local nameColor = blocked and Colors.TEXT_MUTED or ClassColor(member.classFile)
            button.name:SetTextColor(Widgets.UnpackColor(nameColor))
            Widgets.ApplyBackdrop(button, Colors.SURFACE, onSlot and Colors.ACCENT or Colors.BORDER)
            button:Show()
        end
        for extra = #list + 1, #column.buttons do
            column.buttons[extra]:Hide()
            column.buttons[extra].member = nil
            column.buttons[extra].blocked = nil
            column.buttons[extra].blockedText = nil
        end
    end
    for extra = #order + 1, #grid.columns do
        grid.columns[extra]:Hide()
    end

    grid:Show()
    ui.playerStack:SetEntryHeight(grid, math.max(height, 1))
end

local function RefreshEditor()
    ui.mode:SetSelected(editMode)
    ui.playerPane:SetShown(editMode == MODE_PLAYER)
    ui.textPane:SetShown(editMode == MODE_TEXT)

    local assigned = CoiledAltar:GetInterruptSlot(selectedChain, selectedIndex)
    ui.clear:SetEnabled(CoiledAltar:HasInterruptAssignments())

    if editMode == MODE_TEXT then
        HidePlayerExtras()
        ui.stack:SetEntryHeight(ui.playerPane, 1)
        ui.stack:SetEntryHeight(ui.textPane, Sizes.CONTROL_ROW_HEIGHT)
        local current = assigned and assigned.type == Assignments.TYPE_TEXT and assigned.value or ""
        if ui.textBox:GetText() ~= current and not ui.textBox:HasFocus() then
            ui.textBox:SetText(current)
        end
        ui.charCount:SetText(
            string.format("%d/%d", Assignments.Utf8Len(ui.textBox:GetText() or ""), Assignments.TEXT_MAX_CHARS)
        )
        return
    end

    RefreshRoster()
    ui.stack:SetEntryHeight(ui.textPane, 1)
    ui.stack:SetEntryHeight(ui.playerPane, math.max(ui.playerStack:GetHeight(), 1))
end

local function NotifyHeight()
    if ui and ui.onHeightChanged then
        ui.onHeightChanged(ui.stack:GetHeight())
    end
end

function Refresh()
    if not ui then
        return
    end
    RefreshSlots()
    RefreshEditor()
    RefreshValidation()
    NotifyHeight()
end

local function AssignSelectedText()
    local text = ui.textBox:GetText() or ""
    CoiledAltar:AssignInterruptText(selectedChain, selectedIndex, text)
end

local function HideClearConfirm()
    if confirmWindow then
        confirmWindow:Hide()
    end
end

local function ApplyClearAll()
    HideClearConfirm()
    CoiledAltar:ClearAllInterruptAssignments()
end

local function PromptClearAll()
    if not CoiledAltar:HasInterruptAssignments() then
        return
    end
    if not confirmWindow then
        confirmWindow = WarningWindow.Create({
            name = ns.ADDON_NAME .. "CoiledAltarClearAssignmentsConfirm",
            title = L.COILED_ALTAR_INTERRUPT_CLEAR_ALL_TITLE,
            hint = L.COILED_ALTAR_INTERRUPT_CLEAR_ALL_HINT,
            actionText = L.COILED_ALTAR_INTERRUPT_CLEAR_ALL_CONFIRM,
            onAction = ApplyClearAll,
            closable = true,
            onClose = HideClearConfirm,
            draggable = true,
            onClick = function() end,
        })
        confirmWindow:SetFrameStrata("DIALOG")
    end
    local panelScale = (ns.MainPanel and ns.MainPanel.db and ns.MainPanel.db.scale) or 1
    confirmWindow:SetWindowScale(panelScale)
    confirmWindow:SetWarningText(L.COILED_ALTAR_INTERRUPT_CLEAR_ALL_TITLE, L.COILED_ALTAR_INTERRUPT_CLEAR_ALL_HINT)
    confirmWindow:Show()
    confirmWindow:Raise()
end

---@param host Frame
---@param onHeightChanged fun(height: number)
---@return number
function Editor.Mount(host, onHeightChanged)
    selectedChain = Assignments.MELEE
    selectedIndex = 1
    editMode = MODE_PLAYER
    lastAssignError = nil

    -- Stack on the host row itself. An extra top-only wrapper would have height 0 and
    -- WoW would leave its children unplaced, which reserves space with nothing visible.
    local stack = Layout.Stack(host, { spacing = Spacing.SMALL })

    local header = stack:AddRow(Sizes.CONTENT_SECTION_HEADER)
    Widgets.LayoutSectionHeader(header, L.COILED_ALTAR_INTERRUPT_ASSIGNMENTS)

    local descRow = stack:AddRow(DESC_MIN_HEIGHT)
    local desc = Widgets.CreateLabel(descRow, Fonts.TINY_MUTED, L.COILED_ALTAR_INTERRUPT_ASSIGNMENTS_DESC)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetPoint("TOPLEFT")
    desc:SetPoint("TOPRIGHT")

    local chainHeight = GROUP_HEADER_HEIGHT + Assignments.SLOT_COUNT * SLOT_HEIGHT
    local chains = stack:Add(BuildChains(host), chainHeight)

    local validationRow = stack:AddRow(1)
    local validation = Widgets.CreateLabel(validationRow, Fonts.SMALL_MUTED)
    validation:SetJustifyH("LEFT")
    validation:SetJustifyV("TOP")
    validation:SetWordWrap(true)
    validation:SetPoint("TOPLEFT")
    validation:SetPoint("TOPRIGHT")

    local modeRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local mode
    mode = Widgets.CreateSegmentedControl(modeRow, {
        { value = MODE_PLAYER, text = L.COILED_ALTAR_INTERRUPT_MODE_PLAYER },
        { value = MODE_TEXT, text = L.COILED_ALTAR_INTERRUPT_MODE_TEXT },
    }, function(value)
        editMode = value
        lastAssignError = nil
        Refresh()
    end)
    local clear =
        Widgets.CreateTextButton(modeRow, L.COILED_ALTAR_INTERRUPT_CLEAR_ALL, PromptClearAll, Fonts.LINK_DANGER)
    clear:SetPoint("RIGHT", modeRow, "RIGHT")
    mode:SetPoint("LEFT", modeRow, "LEFT")

    local playerPane = stack:Add(CreateFrame("Frame", nil, host), 1)
    local playerStack = Layout.Stack(playerPane, { spacing = Spacing.SMALL })

    local emptyHintRow = playerStack:AddRow(DESC_MIN_HEIGHT)
    local emptyHint = Widgets.CreateLabel(emptyHintRow, Fonts.TINY_MUTED, L.COILED_ALTAR_INTERRUPT_ROSTER_EMPTY)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetJustifyV("TOP")
    emptyHint:SetWordWrap(true)
    emptyHint:SetPoint("TOPLEFT")
    emptyHint:SetPoint("TOPRIGHT")

    local rosterGrid = playerStack:Add(CreateFrame("Frame", nil, playerPane), 1)
    rosterGrid.columns = {}

    local textPane = stack:Add(CreateFrame("Frame", nil, host), Sizes.CONTROL_ROW_HEIGHT)
    local textLabel = Widgets.CreateLabel(textPane, Fonts.BODY, L.COILED_ALTAR_INTERRUPT_TEXT_HINT)
    textLabel:SetJustifyH("LEFT")
    local apply = Widgets.CreateButton(textPane, L.COILED_ALTAR_INTERRUPT_APPLY, AssignSelectedText)
    local charCount = Widgets.CreateLabel(textPane, Fonts.TINY_MUTED)
    charCount:SetJustifyH("RIGHT")
    local textBox = CreateTextBox(textPane, Assignments.TEXT_MAX_CHARS)
    textLabel:SetPoint("LEFT", textPane, "LEFT")
    apply:SetPoint("RIGHT", textPane, "RIGHT")
    charCount:SetPoint("RIGHT", apply, "LEFT", -Spacing.SMALL, 0)
    charCount:SetWidth(36)
    textBox:SetPoint("LEFT", textLabel, "RIGHT", Spacing.SMALL, 0)
    textBox:SetPoint("RIGHT", charCount, "LEFT", -Spacing.SMALL, 0)
    textBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        AssignSelectedText()
    end)
    textBox:SetScript("OnTextChanged", function(self)
        charCount:SetText(string.format("%d/%d", Assignments.Utf8Len(self:GetText() or ""), Assignments.TEXT_MAX_CHARS))
    end)

    ui = {
        stack = stack,
        playerStack = playerStack,
        onHeightChanged = onHeightChanged,
        descRow = descRow,
        desc = desc,
        chains = chains,
        validationRow = validationRow,
        validation = validation,
        mode = mode,
        clear = clear,
        playerPane = playerPane,
        emptyHintRow = emptyHintRow,
        emptyHint = emptyHint,
        rosterGrid = rosterGrid,
        textPane = textPane,
        textBox = textBox,
        charCount = charCount,
    }

    function CoiledAltar:OnInterruptAssignmentsChanged()
        lastAssignError = nil
        Refresh()
    end

    Group.OnRosterChanged(function()
        if ui then
            Refresh()
        end
    end)

    local function LayoutForWidth()
        if not ui then
            return
        end
        local width = math.max(host:GetWidth() or 0, 1)
        ui.desc:SetWidth(width)
        ui.stack:SetEntryHeight(ui.descRow, math.max(ui.desc:GetStringHeight() or 0, DESC_MIN_HEIGHT))
        ui.emptyHint:SetWidth(width)
        ui.validation:SetWidth(width)
        Refresh()
    end

    host:HookScript("OnSizeChanged", LayoutForWidth)
    local getFrame = ns.MainPanel and ns.MainPanel.GetFrame
    local mainPanel = getFrame and ns.MainPanel:GetFrame()
    if mainPanel then
        mainPanel:HookScript("OnHide", HideClearConfirm)
    end
    LayoutForWidth()
    -- First show can report width 0 until the following layout pass.
    ns.Api.Timer.After(0, LayoutForWidth)
    return stack:GetHeight()
end

function Editor.Refresh()
    Refresh()
end
