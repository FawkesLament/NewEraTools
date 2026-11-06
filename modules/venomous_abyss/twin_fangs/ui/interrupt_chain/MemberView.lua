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
local Preview = Internals.InterruptChainPreview

local EMPTY_HEIGHT = 18

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

---@param assignment TwinFangsInterruptMemberAssignment
---@param playerName string|nil
---@param roster RaidMember[]
---@return InterruptChainViewChain
local function ChainDisplay(assignment, playerName, roster)
    local accent = REGION_ACCENTS[assignment.regionId] or Colors.ACCENT
    local entries = {}
    for _, block in ipairs(Chain.Blocks(assignment.players)) do
        local name = block.name
        local isYou = name ~= nil and name == playerName
        local member = RosterMember(name, roster)
        local color = isYou and accent or ClassColor(member and member.classFile)
        entries[#entries + 1] = {
            slot = Preview.FormatSequence(block.first, block.last),
            text = Labels.DisplayName({}, block.player),
            highlight = isYou,
            color = color,
        }
    end

    local backup = assignment.backup
    local backupName = Chain.PlayerName(backup)
    local backupDisplay = backup and Labels.DisplayName({}, backup) or L.TWIN_FANGS_INTERRUPT_BACKUP_NONE
    return {
        title = Labels.AssignmentTitle(assignment.regionId, assignment.group, assignment.channel),
        accent = accent,
        entries = entries,
        emptyText = L.TWIN_FANGS_INTERRUPT_CHAIN_EMPTY_ASSIGNED,
        footer = string.format(L.TWIN_FANGS_INTERRUPT_BACKUP_LINE, backupDisplay),
        footerHighlight = backupName ~= nil and backupName == playerName,
    }
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

    local chains = {}
    if extraBackup and mainAssignment then
        chains[1] = ChainDisplay(mainAssignment, playerName, roster)
        chains[2] = ChainDisplay(extraBackup, playerName, roster)
    elseif mainAssignment then
        chains[1] = ChainDisplay(mainAssignment, playerName, roster)
    end
    ui.chainView:SetData({
        youText = L.TWIN_FANGS_INTERRUPT_YOU,
        chains = chains,
    })
    ui.stack:SetEntryHeight(ui.cardsRow, ui.chainView:GetHeight())

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
    ui.chainView = ns.InterruptChainView.Create(ui.cardsRow)

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
