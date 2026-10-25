local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts
local Sizes = Assets.Sizes
local Spacing = Assets.Spacing
local Unit = ns.Api.Unit

local Chain = Internals.InterruptChain
local Labels = Internals.InterruptChainLabels

local ACCENT_WIDTH = 2
local CARD_HEADER = 18
local PLAYER_ROW_HEIGHT = 16
local EMPTY_HEIGHT = 18
local YOU_WIDTH = 56
local HIGHLIGHT_ALPHA = 0.12

local REGION_ACCENTS = {
    [Chain.FRONT_LEFT] = { r = 0.31, g = 0.76, b = 0.71 },
    [Chain.FRONT_RIGHT] = { r = 0.45, g = 0.62, b = 0.90 },
    [Chain.BACK_LEFT] = { r = 0.62, g = 0.50, b = 0.86 },
    [Chain.BACK_RIGHT] = { r = 0.95, g = 0.64, b = 0.27 },
}

local MemberView = {}
Internals.InterruptChainMemberView = MemberView

local ui
local lastNotifiedHeight

---@param classFile string|nil
---@return { r: number, g: number, b: number }
local function ClassColor(classFile)
    return Unit.GetClassColor(classFile) or Colors.TEXT
end

---@return RaidMember[]
local function Roster()
    return ns.Api.Group.GetRaidMembers()
end

---@param name string|nil
---@param roster RaidMember[]
---@return RaidMember|nil
local function RosterMember(name, roster)
    name = Chain.PlayerName(name)
    if not name then
        return nil
    end
    for _, member in ipairs(roster) do
        if Chain.PlayerName(member.fullName or member.name) == name then
            return member
        end
    end
end

---@return TwinFangsInterruptChainSettings|nil
local function SavedChain()
    local TwinFangs = ns.Modules.Get("TwinFangs")
    return TwinFangs and TwinFangs.db and TwinFangs.db.interruptReminder and TwinFangs.db.interruptReminder.chain
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
local function ApplyYouHighlight(row, accent, isYou)
    if isYou then
        row.highlight:SetColorTexture(accent.r, accent.g, accent.b, HIGHLIGHT_ALPHA)
        row.highlight:Show()
        row.you:SetText(L.TWIN_FANGS_INTERRUPT_YOU)
        row.you:SetTextColor(Widgets.UnpackColor(accent))
    else
        row.highlight:Hide()
        row.you:SetText("")
    end
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

    local empty = Widgets.CreateLabel(list, Fonts.SMALL_MUTED, L.TWIN_FANGS_INTERRUPT_CHAIN_EMPTY_ASSIGNED)
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
    number:SetJustifyH("CENTER")
    number:SetWidth(18)
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
    return Spacing.MEDIUM + CARD_HEADER + Spacing.TINY + listHeight + Spacing.TINY + PLAYER_ROW_HEIGHT + Spacing.SMALL
end

---@param card Frame
---@param assignment TwinFangsInterruptMemberAssignment
---@param playerName string|nil
---@param roster RaidMember[]
local function RefreshAssignmentCard(card, assignment, playerName, roster)
    local accent = REGION_ACCENTS[assignment.regionId] or Colors.ACCENT
    card.accent:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
    card.title:SetText(
        string.format("%s  ·  %s", Labels.RegionLabel(assignment.regionId), Labels.GroupLabel(assignment.group))
    )

    local players = assignment.players
    local count = #players
    card.playerCount = count
    if count == 0 then
        card.empty:Show()
        for _, row in ipairs(card.playerRows) do
            row:Hide()
        end
    else
        card.empty:Hide()
        for index, player in ipairs(players) do
            local row = EnsurePlayerRow(card, index)
            local name = Chain.PlayerName(player)
            local isYou = name ~= nil and name == playerName
            row.number:SetText(tostring(index))
            row.number:SetTextColor(Widgets.UnpackColor(accent))
            row.name:SetText(Labels.DisplayName({}, player))
            local member = RosterMember(name, roster)
            ApplyYouHighlight(row, accent, isYou)
            if isYou then
                row.name:SetTextColor(Widgets.UnpackColor(accent))
            else
                row.name:SetTextColor(Widgets.UnpackColor(ClassColor(member and member.classFile)))
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", card.list, "TOPLEFT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:SetPoint("TOPRIGHT", card.list, "TOPRIGHT", 0, -((index - 1) * PLAYER_ROW_HEIGHT))
            row:Show()
        end
        for index = count + 1, #card.playerRows do
            card.playerRows[index]:Hide()
        end
    end

    local backup = assignment.backup
    local backupName = Chain.PlayerName(backup)
    local isYouBackup = backupName ~= nil and backupName == playerName
    local backupName = backup and Labels.DisplayName({}, backup) or L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    card.backup:SetText(string.format(L.TWIN_FANGS_INTERRUPT_BACKUP_LINE, backupName))
    if isYouBackup then
        card.backup:SetTextColor(Widgets.UnpackColor(accent))
    else
        card.backup:SetTextColor(Widgets.UnpackColor(Colors.TEXT_MUTED))
    end
    ApplyYouHighlight(card.backupRow, accent, isYouBackup)
end

local function NotifyHeight()
    if not ui or not ui.onHeightChanged or not ui.panel:IsShown() then
        return
    end
    local height = ui.stack:GetHeight()
    if height == lastNotifiedHeight then
        return
    end
    lastNotifiedHeight = height
    ui.onHeightChanged(height)
end

---Shows the generate-macro button only for a raid member with a primary assignment.
---@param show boolean
local function ApplyMacroButton(show)
    if not ui or not ui.macroRow then
        return
    end
    ui.macroRow:SetShown(show == true)
    if not show then
        ui.stack:SetEntryHeight(ui.macroRow, 1)
        Internals.InterruptChainMacroPopup.Hide()
        return
    end
    ui.stack:SetEntryHeight(ui.macroRow, Sizes.CONTROL_ROW_HEIGHT)
    local width = math.max(ui.macroButton:GetTextWidth() + Sizes.BUTTON_TEXT_PADDING, Sizes.BUTTON_MIN_WIDTH)
    ui.macroButton:SetSize(width, Sizes.CONTROL_HEIGHT)
end

local function Refresh()
    if not ui then
        return
    end
    local inRaid = ns.Api.Group.GetRaidChatType() ~= nil
    local chain = SavedChain()
    local playerName = ns.Api.Player.GetFullName()
    local view = inRaid and Chain.GetMemberView(chain, playerName) or { backups = {} }
    local roster = Roster()
    local hasPrimary = view.primary ~= nil
    local extraBackup = hasPrimary and view.backups[1] or nil
    local loneBackup = (not hasPrimary) and view.backups[1] or nil
    local mainAssignment = view.primary or loneBackup
    local hasAssignment = mainAssignment ~= nil

    ui.empty:SetShown(not hasAssignment)
    if not hasAssignment then
        ui.emptyLabel:SetText(Labels.MemberViewEmptyText(chain, inRaid))
    end

    if hasAssignment then
        ui.stack:SetEntryHeight(ui.empty, 1)
    else
        ui.stack:SetEntryHeight(ui.empty, EMPTY_HEIGHT)
    end

    local showMacro = inRaid and hasPrimary
    ApplyMacroButton(showMacro)
    if showMacro then
        local TwinFangs = ns.Modules.Get("TwinFangs")
        local body = TwinFangs and TwinFangs.GetInterruptMacroBody and TwinFangs:GetInterruptMacroBody()
        if body then
            Internals.InterruptChainMacroPopup.RefreshIfShown(body)
        end
    end

    if extraBackup and mainAssignment then
        RefreshAssignmentCard(ui.primary, mainAssignment, playerName, roster)
        RefreshAssignmentCard(ui.backup, extraBackup, playerName, roster)
        PlaceCard(ui.primary, ui.left)
        PlaceCard(ui.backup, ui.right)
        ui.left:Show()
        ui.right:Show()
        ui.primary:Show()
        ui.backup:Show()
        ui.stack:SetEntryHeight(ui.cardsRow, math.max(CardHeight(ui.primary), CardHeight(ui.backup)))
    elseif mainAssignment then
        RefreshAssignmentCard(ui.primary, mainAssignment, playerName, roster)
        PlaceCard(ui.primary, ui.cardsRow)
        ui.left:Hide()
        ui.right:Hide()
        ui.primary:Show()
        ui.backup:Hide()
        ui.stack:SetEntryHeight(ui.cardsRow, CardHeight(ui.primary))
    else
        ui.left:Hide()
        ui.right:Hide()
        ui.primary:Hide()
        ui.backup:Hide()
        ui.stack:SetEntryHeight(ui.cardsRow, 1)
    end

    NotifyHeight()
end

---Mounts the read-only member assignment view inside a host row.
---@param host Frame
---@param onHeightChanged fun(height: number)
---@return number
function MemberView.Mount(host, onHeightChanged)
    local panel = Widgets.CreateSurface(host, Colors.SURFACE, Colors.BORDER)
    panel:SetPoint("TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT")

    local stack = Layout.Stack(panel, {
        paddingX = Spacing.XLARGE,
        paddingY = Spacing.XLARGE,
        spacing = Spacing.SMALL,
    })
    lastNotifiedHeight = nil
    ui = { stack = stack, panel = panel, onHeightChanged = onHeightChanged }

    local header = stack:AddRow(20)
    local title = Widgets.CreateLabel(header, Fonts.BODY, L.TWIN_FANGS_INTERRUPT_MY_ASSIGNMENT)
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", header, "LEFT")

    ui.empty = stack:AddRow(EMPTY_HEIGHT)
    local empty = Widgets.CreateLabel(ui.empty, Fonts.SMALL_MUTED, L.TWIN_FANGS_INTERRUPT_SYNC_NONE)
    empty:SetJustifyH("LEFT")
    empty:SetPoint("LEFT", ui.empty, "LEFT")
    ui.emptyLabel = empty

    ui.cardsRow = stack:AddRow(1)
    ui.left, ui.right = Layout.SplitRow(ui.cardsRow, Spacing.MEDIUM)
    ui.primary = CreateAssignmentCard(ui.left)
    ui.backup = CreateAssignmentCard(ui.right)

    ui.macroRow = stack:AddRow(1)
    ui.macroButton = Widgets.CreateButton(ui.macroRow, L.TWIN_FANGS_INTERRUPT_MACRO_CREATE, function()
        local TwinFangs = ns.Modules.Get("TwinFangs")
        local body = TwinFangs and TwinFangs.GetInterruptMacroBody and TwinFangs:GetInterruptMacroBody()
        if not body then
            return
        end
        Internals.InterruptChainMacroPopup.Show(body)
    end, "primary")
    ui.macroButton:SetPoint("LEFT", ui.macroRow, "LEFT")
    ui.macroRow:Hide()

    panel:HookScript("OnShow", function()
        lastNotifiedHeight = nil
        Refresh()
    end)

    Refresh()
    return stack:GetHeight()
end

function MemberView.Refresh()
    if not ui or not ui.panel:IsShown() then
        return
    end
    lastNotifiedHeight = nil
    Refresh()
end

---Shows or hides the member view.
---@param shown boolean
function MemberView.SetShown(shown)
    shown = shown == true
    if not ui then
        return
    end
    if shown then
        ui.panel:Show()
        MemberView.Refresh()
        return
    end
    lastNotifiedHeight = nil
    ui.panel:Hide()
end
