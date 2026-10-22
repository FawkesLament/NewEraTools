local _, ns = ...
local L = ns.L
local ActionFooter = ns.ActionFooter
local Assets = ns.Assets
local Layout = ns.Layout
local WarningWindow = ns.WarningWindow
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing
local Unit = ns.Api.Unit

local Chain = ns.TwinFangsInterruptChain

local LINE_HEIGHT = 11
local CARD_HEADER = 18
local CARD_GAP = Spacing.SMALL
local ACCENT_WIDTH = 2
local PLAYER_ROW_HEIGHT = Sizes.CONTROL_ROW_HEIGHT
local EMPTY_HEIGHT = 18
local CHAIN_ROW_GAP = 0

local REGION_ACCENTS = {
    [Chain.FRONT_LEFT] = { r = 0.31, g = 0.76, b = 0.71 },
    [Chain.FRONT_RIGHT] = { r = 0.45, g = 0.62, b = 0.90 },
    [Chain.BACK_LEFT] = { r = 0.62, g = 0.50, b = 0.86 },
    [Chain.BACK_RIGHT] = { r = 0.95, g = 0.64, b = 0.27 },
}

local STATUS_COLORS = {
    error = Colors.ERROR,
    warning = Colors.WARNING,
    unsynced = Colors.TEXT_MUTED,
    valid = Colors.SUCCESS,
}

local InterruptChainEditor = {}
ns.TwinFangsInterruptChainEditor = InterruptChainEditor

local session = Chain.NewState()

local function BindSession()
    local TwinFangs = ns.Modules.Get("TwinFangs")
    local chain = TwinFangs and TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
    session = Chain.NewState(chain)
end
local selectedRegion
local pendingAdd
---@type TwinFangsInterruptBackupPicker|nil
local backupPicker
---@type ActionFooterMessage|nil
local autoAssignNotice
local autoAssignAllowed = false
local confirmWindow
local ui

local Refresh
local NotifyHeight

local function CanEdit()
    return Chain.CanEdit()
end

---@param classFile string|nil
---@return { r: number, g: number, b: number }
local function ClassColor(classFile)
    return Unit.GetClassColor(classFile) or Colors.TEXT
end

---@param name string
---@param classFile string|nil
---@return string
local function ColorizeName(name, classFile)
    local color = ClassColor(classFile)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5),
        name
    )
end

---@param player TwinFangsInterruptPlayer|string|nil
---@return string
local function ColoredDisplayName(player)
    local name = Chain.DisplayName(session.roster, player)
    local member = Chain.GetMember(session, player)
    if not member then
        return name
    end
    return ColorizeName(name, member.classFile)
end

---@param parent Frame
---@param color table
---@return Texture
local function AddAccentBar(parent, color)
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(ACCENT_WIDTH)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetColorTexture(color.r, color.g, color.b, 0.9)
    return bar
end

---@param issues TwinFangsInterruptChainIssue[]
---@return string
local function JoinIssueTexts(issues)
    local texts = {}
    for _, issue in ipairs(issues) do
        texts[#texts + 1] = issue.text
    end
    return table.concat(texts, "  ")
end

local function CardHeight()
    local extra = 1
    for _, regionId in ipairs(Chain.REGION_IDS) do
        extra = math.max(extra, #session.regions[regionId].players)
    end
    extra = math.min(extra, 5)
    return Spacing.MEDIUM * 2 + CARD_HEADER + LINE_HEIGHT * extra + LINE_HEIGHT
end

local function OverviewHeight()
    local card = CardHeight()
    return card * 2 + CARD_GAP
end

---@param card Button
---@param regionId string
local function RefreshCard(card, regionId)
    local region = Chain.GetRegion(session, regionId)
    local issues = Chain.IssuesFor(Chain.Validate(session), regionId)
    card.title:SetText(string.format("%s  ·  %s", Chain.RegionLabel(regionId), Chain.GroupLabel(region.group)))
    if #region.players == 0 then
        card.players:SetText(L.TWIN_FANGS_INTERRUPT_CHAIN_EMPTY_ASSIGNED)
        card.players:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
    else
        local lines = {}
        for index, player in ipairs(region.players) do
            lines[#lines + 1] = string.format("%d  %s", index, ColoredDisplayName(player))
        end
        card.players:SetText(table.concat(lines, "\n"))
        card.players:SetTextColor(Widgets.UnpackColor(Colors.TEXT))
    end
    local backupName = region.backup and ColoredDisplayName(region.backup) or L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    card.backup:SetText(string.format(L.TWIN_FANGS_INTERRUPT_BACKUP_LINE, backupName))

    local hasError
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            hasError = true
            break
        end
    end
    Widgets.ApplyBackdrop(card, Colors.SURFACE_RAISED, hasError and Colors.ERROR or Colors.BORDER)
end

local function BuildOverview(parent)
    local grid = CreateFrame("Frame", nil, parent)
    -- Anchored halves follow the grid's width, so cards place correctly before it is measured.
    local gridStack = Layout.Stack(grid, { spacing = CARD_GAP })
    local topRow = gridStack:AddRow(CardHeight())
    local bottomRow = gridStack:AddRow(CardHeight())
    local cells = {}
    cells[1], cells[2] = Layout.SplitRow(topRow, CARD_GAP)
    cells[3], cells[4] = Layout.SplitRow(bottomRow, CARD_GAP)
    local cards = {}
    for index, regionId in ipairs(Chain.REGION_IDS) do
        local card = CreateFrame("Button", nil, cells[index], Assets.Templates.BACKDROP) --[[@as Button]]
        card:SetAllPoints(cells[index])
        Widgets.ApplyBackdrop(card, Colors.SURFACE_RAISED, Colors.BORDER)
        Widgets.AddHoverHighlight(card)
        AddAccentBar(card, REGION_ACCENTS[regionId])
        card:SetScript("OnClick", function()
            selectedRegion = regionId
            pendingAdd = nil
            backupPicker = nil
            Refresh()
        end)

        local title = Widgets.CreateLabel(card, Fonts.BODY)
        title:SetJustifyH("LEFT")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", Spacing.MEDIUM + ACCENT_WIDTH, -Spacing.MEDIUM)
        title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -Spacing.SMALL, -Spacing.MEDIUM)
        card.title = title

        local players = Widgets.CreateLabel(card, Fonts.SMALL_MUTED)
        players:SetJustifyH("LEFT")
        players:SetJustifyV("TOP")
        players:SetWordWrap(true)
        players:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Spacing.TINY)
        players:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -Spacing.TINY)
        card.players = players

        local backup = Widgets.CreateLabel(card, Fonts.TINY_MUTED)
        backup:SetJustifyH("LEFT")
        backup:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", Spacing.MEDIUM + ACCENT_WIDTH, Spacing.SMALL)
        backup:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -Spacing.SMALL, Spacing.SMALL)
        card.backup = backup

        cards[regionId] = card
    end

    local function LayoutCards()
        local cardHeight = CardHeight()
        gridStack:BeginUpdate()
        gridStack:SetEntryHeight(topRow, cardHeight)
        gridStack:SetEntryHeight(bottomRow, cardHeight)
        gridStack:EndUpdate()
    end

    grid.cards = cards
    grid.LayoutCards = LayoutCards
    return grid
end

---@param parent Frame
---@return Frame
local function BuildEditor(parent)
    local editor = CreateFrame("Frame", nil, parent)
    local stack = Layout.Stack(editor, { spacing = Spacing.SMALL })
    editor.stack = stack

    local navRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local back = Widgets.CreateTextButton(navRow, L.TWIN_FANGS_INTERRUPT_BACK, function()
        selectedRegion = nil
        pendingAdd = nil
        Refresh()
    end)
    local nav
    nav = Widgets.CreateSegmentedControl(navRow, {
        { value = Chain.FRONT_LEFT, text = L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT },
        { value = Chain.FRONT_RIGHT, text = L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT },
        { value = Chain.BACK_LEFT, text = L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT },
        { value = Chain.BACK_RIGHT, text = L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT },
    }, function(regionId)
        selectedRegion = regionId
        pendingAdd = nil
        backupPicker = nil
        Refresh()
    end)
    Layout.Row(navRow, { back, nav }, Spacing.MEDIUM)
    editor.nav = nav

    local headingRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local heading = Widgets.CreateLabel(headingRow, Fonts.BODY)
    heading:SetJustifyH("LEFT")
    local groupDropdown
    groupDropdown = Widgets.CreateDropdown(headingRow, {}, function(group)
        Chain.SetGroup(session, selectedRegion, group)
        pendingAdd = nil
        Refresh()
    end)
    Layout.Row(headingRow, { heading, groupDropdown }, Spacing.LARGE)
    editor.heading = heading
    editor.groupDropdown = groupDropdown

    local chainHeader = stack:AddRow(Sizes.CONTENT_SECTION_HEADER)
    Widgets.LayoutSectionHeader(chainHeader, L.TWIN_FANGS_INTERRUPT_CHAIN_SECTION)

    local chainList = stack:Add(CreateFrame("Frame", nil, editor), PLAYER_ROW_HEIGHT)
    editor.chainList = chainList
    editor.playerRows = {}

    local empty = Widgets.CreateLabel(chainList, Fonts.SMALL_MUTED)
    empty:SetJustifyH("LEFT")
    empty:SetPoint("TOPLEFT", chainList, "TOPLEFT", 0, 0)
    editor.empty = empty

    local addRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local addDropdown
    addDropdown = Widgets.CreateDropdown(addRow, {}, function(value)
        pendingAdd = value
        Refresh()
    end)
    addDropdown:SetAutoWidth(false)
    local addButton = Widgets.CreateButton(addRow, L.TWIN_FANGS_INTERRUPT_ADD, function()
        if type(pendingAdd) == "string" and Chain.AddPlayer(session, selectedRegion, pendingAdd) then
            pendingAdd = nil
            Refresh()
        end
    end)
    addDropdown:SetPoint("LEFT", addRow, "LEFT")
    addDropdown:SetPoint("RIGHT", addButton, "LEFT", -Spacing.SMALL, 0)
    addButton:SetPoint("RIGHT", addRow, "RIGHT")
    local rawAddSetEnabled = addButton.SetEnabled
    function addButton:SetEnabled(enabled)
        rawAddSetEnabled(self, enabled == true and type(pendingAdd) == "string")
    end
    editor.addDropdown = addDropdown
    editor.addButton = addButton

    local backupHeader = stack:AddRow(Sizes.CONTENT_SECTION_HEADER, Spacing.MEDIUM)
    Widgets.LayoutSectionHeader(backupHeader, L.TWIN_FANGS_INTERRUPT_BACKUP_SECTION)

    local backupRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local groupCell, playerCell = Layout.SplitRow(backupRow, Spacing.SMALL)
    local backupGroupLabel = Widgets.CreateLabel(groupCell, Fonts.BODY, L.TWIN_FANGS_INTERRUPT_BACKUP_GROUP)
    backupGroupLabel:SetJustifyH("LEFT")
    local backupGroupDropdown
    backupGroupDropdown = Widgets.CreateDropdown(groupCell, {}, function(group)
        if backupPicker then
            Chain.PickBackupGroup(backupPicker, group)
        end
        Refresh()
    end)
    backupGroupDropdown:SetAutoWidth(false)
    Layout.Row(groupCell, { backupGroupLabel, backupGroupDropdown }, Spacing.SMALL)
    local function SyncBackupGroupWidth(_, cellWidth)
        if not cellWidth or cellWidth <= 0 then
            return
        end
        backupGroupDropdown:SetWidth(math.max(cellWidth - backupGroupLabel:GetStringWidth() - Spacing.SMALL, 1))
    end
    groupCell:HookScript("OnSizeChanged", SyncBackupGroupWidth)

    local backupPlayerLabel = Widgets.CreateLabel(playerCell, Fonts.BODY, L.TWIN_FANGS_INTERRUPT_BACKUP_PLAYER)
    backupPlayerLabel:SetJustifyH("LEFT")
    local backupClear = Widgets.CreateTextButton(playerCell, L.TWIN_FANGS_INTERRUPT_BACKUP_CLEAR, function()
        if not selectedRegion then
            return
        end
        Chain.SetBackup(session, selectedRegion, nil)
        backupPicker = nil
        Refresh()
    end)
    local backupPlayerDropdown
    backupPlayerDropdown = Widgets.CreateDropdown(playerCell, {}, function(value)
        if type(value) == "string" then
            Chain.SetBackup(session, selectedRegion, value)
            backupPicker = nil
        end
        Refresh()
    end)
    backupPlayerDropdown:SetAutoWidth(false)
    backupPlayerLabel:SetPoint("LEFT", playerCell, "LEFT")
    backupClear:SetPoint("RIGHT", playerCell, "RIGHT")
    backupPlayerDropdown:SetPoint("LEFT", backupPlayerLabel, "RIGHT", Spacing.SMALL, 0)
    backupPlayerDropdown:SetPoint("RIGHT", backupClear, "LEFT", -Spacing.TINY, 0)
    local rawClearSetEnabled = backupClear.SetEnabled
    function backupClear:SetEnabled(enabled)
        local region = selectedRegion and session.regions[selectedRegion]
        local canClear = enabled == true and region ~= nil and region.backup ~= nil
        rawClearSetEnabled(self, canClear)
        -- Text buttons have no OnEnable fade restore. FeatureSection only restyles
        -- alpha when the page height changes, so an empty interrupt list can leave
        -- 清除 stuck dim after a backup is assigned.
        if canClear then
            self:SetAlpha(1)
        elseif enabled then
            self:SetAlpha(0.4)
        else
            self:SetAlpha(1)
        end
    end
    editor.backupGroupDropdown = backupGroupDropdown
    editor.backupPlayerDropdown = backupPlayerDropdown
    editor.backupClear = backupClear

    local hintRow = stack:AddRow(28)
    local hint = Widgets.CreateLabel(hintRow, Fonts.TINY_MUTED, L.TWIN_FANGS_INTERRUPT_BACKUP_HINT)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetWordWrap(true)
    hint:SetPoint("TOPLEFT")
    hint:SetPoint("TOPRIGHT")
    editor.hintRow = hintRow
    editor.hint = hint

    local validationRow = stack:AddRow(1)
    local validation = Widgets.CreateLabel(validationRow, Fonts.SMALL_MUTED)
    validation:SetJustifyH("LEFT")
    validation:SetJustifyV("TOP")
    validation:SetWordWrap(true)
    validation:SetPoint("TOPLEFT")
    validation:SetPoint("TOPRIGHT")
    editor.validationRow = validationRow
    editor.validation = validation

    return editor
end

---@param editor Frame
local function EnsurePlayerRow(editor, index)
    local row = editor.playerRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, editor.chainList)
    local number = Widgets.CreateLabel(row, Fonts.EMPHASIS)
    number:SetJustifyH("RIGHT")
    number:SetWidth(18)
    number:SetPoint("LEFT", row, "LEFT")
    row.number = number

    local name = Widgets.CreateLabel(row, Fonts.BODY)
    name:SetJustifyH("LEFT")
    name:SetPoint("LEFT", number, "RIGHT", Spacing.SMALL, 0)
    row.name = name

    local remove = Widgets.CreateTextButton(row, L.TWIN_FANGS_INTERRUPT_REMOVE, function()
        Chain.RemovePlayer(session, selectedRegion, row.index)
        Refresh()
    end, Fonts.LINK_DANGER)
    local down = Widgets.CreateTextButton(row, L.TWIN_FANGS_INTERRUPT_MOVE_DOWN, function()
        Chain.MovePlayer(session, selectedRegion, row.index, 1)
        Refresh()
    end)
    local up = Widgets.CreateTextButton(row, L.TWIN_FANGS_INTERRUPT_MOVE_UP, function()
        Chain.MovePlayer(session, selectedRegion, row.index, -1)
        Refresh()
    end)
    remove:SetPoint("RIGHT", row, "RIGHT")
    down:SetPoint("RIGHT", remove, "LEFT", -Spacing.TINY, 0)
    up:SetPoint("RIGHT", down, "LEFT", -Spacing.TINY, 0)
    name:SetPoint("RIGHT", up, "LEFT", -Spacing.SMALL, 0)
    row.canMoveUp = false
    row.canMoveDown = false
    local rawUpSetEnabled = up.SetEnabled
    function up:SetEnabled(enabled)
        rawUpSetEnabled(self, enabled == true and row.canMoveUp)
    end
    local rawDownSetEnabled = down.SetEnabled
    function down:SetEnabled(enabled)
        rawDownSetEnabled(self, enabled == true and row.canMoveDown)
    end
    row.remove = remove
    row.down = down
    row.up = up
    editor.playerRows[index] = row
    return row
end

---@param editor Frame
---@param region TwinFangsInterruptChainRegion
local function RefreshPlayerRows(editor, region)
    local count = #region.players
    local listHeight
    if count == 0 then
        editor.empty:Show()
        editor.empty:SetText(L.TWIN_FANGS_INTERRUPT_CHAIN_EMPTY_ASSIGNED)
        listHeight = EMPTY_HEIGHT
        for _, row in ipairs(editor.playerRows) do
            row:Hide()
        end
    else
        editor.empty:Hide()
        listHeight = count * PLAYER_ROW_HEIGHT + math.max(count - 1, 0) * CHAIN_ROW_GAP
        for index = 1, count do
            local row = EnsurePlayerRow(editor, index)
            row.index = index
            row.number:SetText(tostring(index))
            row.number:SetTextColor(Widgets.UnpackColor(REGION_ACCENTS[selectedRegion] or Colors.ACCENT))
            local member = Chain.GetMember(session, region.players[index])
            row.name:SetText(Chain.DisplayName(session.roster, region.players[index]))
            row.name:SetTextColor(Widgets.UnpackColor(ClassColor(member and member.classFile)))
            row.canMoveUp = index > 1
            row.canMoveDown = index < count
            row.up:SetEnabled(true)
            row.down:SetEnabled(true)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", editor.chainList, "TOPLEFT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:SetPoint("TOPRIGHT", editor.chainList, "TOPRIGHT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:SetHeight(PLAYER_ROW_HEIGHT)
            row:Show()
        end
        for index = count + 1, #editor.playerRows do
            editor.playerRows[index]:Hide()
        end
    end
    editor.stack:SetEntryHeight(editor.chainList, listHeight)
end

---@param editor Frame
local function RefreshEditor(editor)
    local regionId = selectedRegion
    local region = Chain.GetRegion(session, regionId)
    editor.nav:SetSelected(regionId)
    editor.heading:SetText(string.format("%s  ·  %s", Chain.RegionLabel(regionId), Chain.GroupLabel(region.group)))

    local groupItems = {}
    for _, group in ipairs(Chain.GetAssignableGroups(session, regionId)) do
        local text = string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP, group)
        if Chain.IsGroupAssignedElsewhere(session, regionId, group) then
            local warning = Colors.WARNING
            text = string.format(
                "%s  |cff%02x%02x%02x%s|r",
                text,
                math.floor(warning.r * 255 + 0.5),
                math.floor(warning.g * 255 + 0.5),
                math.floor(warning.b * 255 + 0.5),
                L.TWIN_FANGS_INTERRUPT_RAID_GROUP_TAKEN
            )
        end
        groupItems[#groupItems + 1] = {
            value = group,
            text = text,
        }
    end
    editor.groupDropdown:SetItems(groupItems)
    editor.groupDropdown:SetSelected(region.group)

    RefreshPlayerRows(editor, region)

    local addable = Chain.GetAddablePlayers(session, regionId)
    local addItems = { { value = Chain.ADD_NONE, text = L.TWIN_FANGS_INTERRUPT_ADD_PLAYER } }
    local pendingValid
    for _, member in ipairs(addable) do
        addItems[#addItems + 1] = { value = member.guid, text = ColorizeName(member.name, member.classFile) }
        if pendingAdd == member.guid then
            pendingValid = true
        end
    end
    if not pendingValid then
        pendingAdd = Chain.ADD_NONE
    end
    editor.addDropdown:SetItems(addItems)
    editor.addDropdown:SetSelected(pendingAdd)
    editor.addButton:SetEnabled(type(pendingAdd) == "string")
    if #addable == 0 and #region.players == 0 then
        editor.empty:SetText(L.TWIN_FANGS_INTERRUPT_CHAIN_EMPTY)
    end

    backupPicker = Chain.SyncBackupPicker(session, regionId, backupPicker)
    local backupGroupItems = {}
    for _, group in ipairs(Chain.GetBackupGroups(session, regionId)) do
        backupGroupItems[#backupGroupItems + 1] = {
            value = group,
            text = string.format(L.TWIN_FANGS_INTERRUPT_RAID_GROUP, group),
        }
    end
    editor.backupGroupDropdown:SetItems(backupGroupItems)
    editor.backupGroupDropdown:SetSelected(backupPicker.group)

    local backupPlayerItems = { { value = Chain.BACKUP_NONE, text = L.TWIN_FANGS_INTERRUPT_ADD_PLAYER } }
    local playerValid
    for _, member in ipairs(Chain.GetBackupPlayers(session, regionId, backupPicker.group)) do
        backupPlayerItems[#backupPlayerItems + 1] = {
            value = member.guid,
            text = ColorizeName(member.name, member.classFile),
        }
        if backupPicker.player == member.guid then
            playerValid = true
        end
    end
    if not playerValid then
        backupPicker.player = Chain.BACKUP_NONE
    end
    editor.backupPlayerDropdown:SetItems(backupPlayerItems)
    editor.backupPlayerDropdown:SetSelected(backupPicker.player)
    editor.backupClear:SetEnabled(true)

    local issues = Chain.IssuesFor(Chain.Validate(session), regionId)
    local errors = {}
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then
            errors[#errors + 1] = issue
        end
    end
    if #errors > 0 then
        editor.validation:SetText(JoinIssueTexts(errors))
        editor.validation:SetTextColor(Widgets.UnpackColor(Colors.ERROR))
        editor.stack:SetEntryHeight(editor.validationRow, 18)
    else
        editor.validation:SetText("")
        editor.stack:SetEntryHeight(editor.validationRow, 1)
    end
    editor.hint:SetWidth(math.max(editor:GetWidth() or 0, 1))
    local hintHeight = math.max(editor.hint:GetStringHeight() or 0, 20)
    editor.stack:SetEntryHeight(editor.hintRow, hintHeight)
end

---@param reason string|nil
---@return string
local function AutoAssignReasonText(reason)
    if reason == "not_in_raid" then
        return L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_NOT_IN_RAID
    elseif reason == "roster_unavailable" then
        return L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_ROSTER_UNAVAILABLE
    elseif reason == "groups_empty" then
        return L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_GROUPS_EMPTY
    end
    return L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_HINT
end

local function HideAutoAssignConfirm()
    if confirmWindow then
        confirmWindow:Hide()
    end
end

local autoAssignSectionEnabled = true
local autoAssignBlockReason

local function ApplyAutoAssignEnabled()
    if not ui or not ui.autoAssign then
        return
    end
    ui.autoAssign:SetEnabled(autoAssignSectionEnabled)
end

local function ApplyAutoAssign()
    HideAutoAssignConfirm()
    Chain.UseRaidRoster(session)
    local inRaid = ns.Api.Group.GetRaidChatType() ~= nil
    local complete = ns.Api.Group.HasCompleteRaidRoster()
    local ok, reason = Chain.AutoAssign(session, session.roster, inRaid, complete)
    if ok then
        autoAssignNotice = nil
        backupPicker = nil
    else
        autoAssignNotice = { text = AutoAssignReasonText(reason), severity = "warning" }
    end
    Refresh()
end

local function PromptAutoAssign()
    if not autoAssignAllowed then
        return
    end
    if not confirmWindow then
        confirmWindow = WarningWindow.Create({
            name = ns.ADDON_NAME .. "TwinFangsAutoAssignConfirm",
            title = L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_CONFIRM_TITLE,
            hint = L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_CONFIRM_HINT,
            actionText = L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_CONFIRM,
            onAction = ApplyAutoAssign,
            closable = true,
            onClose = HideAutoAssignConfirm,
            draggable = true,
            onClick = function() end,
        })
        confirmWindow:SetFrameStrata("DIALOG")
    end
    local panelScale = (ns.MainPanel and ns.MainPanel.db and ns.MainPanel.db.scale) or 1
    confirmWindow:SetWindowScale(panelScale)
    confirmWindow:SetWarningText(
        L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_CONFIRM_TITLE,
        L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_CONFIRM_HINT
    )
    confirmWindow:Show()
    confirmWindow:Raise()
end

local function RefreshHeader()
    local status = Chain.GetStatus(session)
    ui.status:SetText(status.text)
    ui.status:SetTextColor(Widgets.UnpackColor(STATUS_COLORS[status.level] or Colors.TEXT_MUTED))

    local inRaid = ns.Api.Group.GetRaidChatType() ~= nil
    autoAssignBlockReason = Chain.GetAutoAssignBlockReason(session.roster, inRaid, ns.Api.Group.HasCompleteRaidRoster())
    autoAssignAllowed = autoAssignBlockReason == nil
    ApplyAutoAssignEnabled()

    if not autoAssignAllowed and not autoAssignNotice then
        ui.footer:SetMessage({ text = AutoAssignReasonText(autoAssignBlockReason), severity = "info" })
        return
    end

    if autoAssignNotice then
        ui.footer:SetMessage(autoAssignNotice)
        return
    end
    local footerIssues = selectedRegion and Chain.IssuesFor(status.issues, selectedRegion) or status.issues
    local primary = Chain.PrimaryIssue(footerIssues)
    if primary then
        ui.footer:SetMessage({ text = primary.text, severity = primary.severity })
    else
        ui.footer:SetMessage(nil)
    end
    ui.footer.button:SetEnabled(Chain.CanEdit())
end

local lastNotifiedHeight
local shownView

function NotifyHeight()
    if not ui or not ui.onHeightChanged or not CanEdit() or not ui.panel:IsShown() then
        return
    end
    local height = ui.stack:GetHeight()
    if height == lastNotifiedHeight then
        return
    end
    lastNotifiedHeight = height
    ui.onHeightChanged(height)
end

local function LayoutShownView()
    if not ui or not CanEdit() or not ui.panel:IsShown() then
        return
    end
    local editing = selectedRegion ~= nil
    if editing then
        RefreshEditor(ui.editor)
        ui.stack:SetEntryHeight(ui.editor, math.max(ui.editor.stack:GetHeight(), 1))
    else
        local height = OverviewHeight()
        ui.stack:SetEntryHeight(ui.overview, height)
        ui.overview.LayoutCards()
        for regionId, card in pairs(ui.overview.cards) do
            RefreshCard(card, regionId)
        end
    end
    NotifyHeight()
end

function Refresh()
    if not ui then
        return
    end
    Chain.UseRaidRoster(session)
    local editing = selectedRegion ~= nil
    local view = editing and "editor" or "overview"
    ui.overview:SetShown(not editing)
    ui.editor:SetShown(editing)
    if editing then
        ui.stack:SetEntryHeight(ui.overview, 1)
    else
        ui.stack:SetEntryHeight(ui.editor, 1)
    end
    RefreshHeader()
    LayoutShownView()
    local TwinFangs = ns.Modules.Get("TwinFangs")
    if TwinFangs and TwinFangs.MaintainInterruptMacro then
        TwinFangs:MaintainInterruptMacro()
    end
    if shownView ~= view then
        shownView = view
        -- A newly shown frame can report width 0 until the next layout pass.
        ns.Api.Timer.After(0, LayoutShownView)
    end
end

---Mounts the raid-leader interrupt-chain editor inside a host row.
---@param host Frame
---@param onHeightChanged fun(height: number)
---@return number
function InterruptChainEditor.Mount(host, onHeightChanged)
    BindSession()
    local panel = Widgets.CreateSurface(host, Colors.SURFACE, Colors.BORDER)
    panel:SetPoint("TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT")

    local stack = Layout.Stack(panel, {
        paddingX = Spacing.XLARGE,
        paddingY = Spacing.XLARGE,
        spacing = Spacing.SMALL,
    })
    lastNotifiedHeight = nil
    shownView = nil
    ui = { stack = stack, panel = panel, onHeightChanged = onHeightChanged }

    local header = stack:AddRow(34)
    local title = Widgets.CreateLabel(header, Fonts.BODY, L.TWIN_FANGS_INTERRUPT_CHAIN)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", header, "TOPLEFT")
    local status = Widgets.CreateLabel(header, Fonts.SMALL_MUTED)
    status:SetJustifyH("RIGHT")
    status:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    local desc = Widgets.CreateLabel(header, Fonts.TINY_MUTED, L.TWIN_FANGS_INTERRUPT_CHAIN_DESC)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Spacing.TINY)
    desc:SetPoint("RIGHT", header, "RIGHT")
    ui.status = status

    ui.overview = stack:Add(BuildOverview(panel), OverviewHeight())
    ui.editor = stack:Add(BuildEditor(panel), 1)
    ui.editor:Hide()

    ui.footer = ActionFooter.Create(panel, {
        text = L.TWIN_FANGS_INTERRUPT_SYNC,
        onClick = function()
            Chain.UseRaidRoster(session)
            Chain.Publish(session)
            Refresh()
        end,
        onHeightChanged = function(height)
            stack:SetEntryHeight(ui.footer, height)
            NotifyHeight()
        end,
    })
    stack:Add(ui.footer, ui.footer:GetHeight(), Spacing.MEDIUM)
    Widgets.AttachTooltip(ui.footer.button, "ANCHOR_TOP", function(tooltip)
        if Chain.CanEdit() then
            tooltip:SetText(L.TWIN_FANGS_INTERRUPT_SYNC_HINT)
        else
            tooltip:SetText(L.TWIN_FANGS_INTERRUPT_SYNC_UNAVAILABLE)
        end
    end)

    ui.autoAssign = Widgets.CreateButton(ui.footer, L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN, PromptAutoAssign, "secondary")
    ui.autoAssign:SetPoint("RIGHT", ui.footer.button, "LEFT", -Spacing.SMALL, 0)
    local rawAutoAssignSetEnabled = ui.autoAssign.SetEnabled
    function ui.autoAssign:SetEnabled(enabled)
        autoAssignSectionEnabled = enabled ~= false
        rawAutoAssignSetEnabled(self, autoAssignSectionEnabled and autoAssignAllowed)
    end
    Widgets.AttachTooltip(ui.autoAssign, "ANCHOR_TOP", function(tooltip)
        if autoAssignAllowed then
            tooltip:SetText(L.TWIN_FANGS_INTERRUPT_AUTO_ASSIGN_HINT)
        else
            tooltip:SetText(AutoAssignReasonText(autoAssignBlockReason))
        end
    end)

    host:HookScript("OnSizeChanged", function()
        LayoutShownView()
    end)

    Refresh()
    return stack:GetHeight()
end

function InterruptChainEditor.Refresh()
    if not ui or not CanEdit() then
        return
    end
    lastNotifiedHeight = nil
    Refresh()
end

---Shows or hides the editor. Hiding also leaves the region editor and cancels confirm.
---@param shown boolean
function InterruptChainEditor.SetShown(shown)
    shown = shown == true
    if not shown then
        selectedRegion = nil
        pendingAdd = nil
        backupPicker = nil
        HideAutoAssignConfirm()
        lastNotifiedHeight = nil
        shownView = nil
        if ui then
            ui.overview:Hide()
            ui.editor:Hide()
            ui.panel:Hide()
        end
        return
    end
    if ui then
        ui.panel:Show()
    end
    InterruptChainEditor.Refresh()
end
