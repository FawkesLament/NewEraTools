---Read-only Coiled Altar interrupt-chain Member View built on InterruptChainView.
local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L
local Assets = ns.Assets
local Layout = ns.Layout
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

local MemberView = {}
Internals.InterruptAssignmentsMemberView = MemberView

local CHAIN_ACCENTS = {
    [Assignments.MELEE] = Colors.ACCENT,
    [Assignments.RANGED] = Colors.STATUS_HUD_STANDBY,
}

local ui
local lastNotifiedHeight

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

---@return RaidMember[]
local function Roster()
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

---@param slot CoiledAltarInterruptSlot
---@param roster RaidMember[]
---@param accent { r: number, g: number, b: number }
---@param playerName string|nil
---@return InterruptChainViewEntry
local function EntryFromSlot(slot, roster, accent, playerName, index)
    local identity = Assignments.QualifyName(playerName)
    if slot.type == Assignments.TYPE_TEXT then
        return {
            slot = ns.InterruptChainView.FormatSequence(index),
            text = slot.value or "",
            color = Colors.TEXT_GOLD,
        }
    end
    if slot.type == Assignments.TYPE_PLAYER then
        local stored = slot.value or ""
        local isYou = identity ~= nil and stored == identity
        local text = ShortName(stored)
        local color = isYou and accent or Colors.TEXT
        for _, member in ipairs(roster) do
            if Assignments.QualifyName(member.fullName or member.name) == stored then
                text = member.name
                if not isYou then
                    color = ClassColor(member.classFile)
                end
                break
            end
        end
        return {
            slot = ns.InterruptChainView.FormatSequence(index),
            text = text,
            highlight = isYou or nil,
            color = color,
        }
    end
    return {
        slot = ns.InterruptChainView.FormatSequence(index),
        text = L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY,
        color = Colors.TEXT_MUTED,
    }
end

---@param chainId CoiledAltarInterruptChainId
---@param roster RaidMember[]
---@param playerName string|nil
---@return InterruptChainViewChain
local function ChainDisplay(chainId, roster, playerName)
    local accent = CHAIN_ACCENTS[chainId] or Colors.ACCENT
    local title = chainId == Assignments.MELEE and L.COILED_ALTAR_INTERRUPT_CHAIN_MELEE
        or L.COILED_ALTAR_INTERRUPT_CHAIN_RANGED
    local entries = {}
    for index = 1, Assignments.SLOT_COUNT do
        local slot = CoiledAltar:GetInterruptSlot(chainId, index) or { type = Assignments.TYPE_EMPTY }
        entries[index] = EntryFromSlot(slot, roster, accent, playerName, index)
    end
    return {
        title = title,
        accent = accent,
        entries = entries,
    }
end

---@param chainId CoiledAltarInterruptChainId
---@return string
local function MarkedSideText(chainId)
    if chainId == Assignments.RANGED then
        return L.COILED_ALTAR_MARKED_SIDE_RANGED
    end
    return L.COILED_ALTAR_MARKED_SIDE_MELEE
end

local function RefreshMarkedChain()
    local chainId = CoiledAltar:GetMarkedChain()
    local accent = CHAIN_ACCENTS[chainId] or Colors.ACCENT
    ui.markedValue:SetText(MarkedSideText(chainId))
    ui.markedValue:SetTextColor(Widgets.UnpackColor(accent))
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

local function Refresh()
    if not ui then
        return
    end
    local roster = Roster()
    local playerName = Player.GetFullName()
    ui.chainView:SetData({
        youText = L.COILED_ALTAR_INTERRUPT_YOU,
        chains = {
            ChainDisplay(Assignments.MELEE, roster, playerName),
            ChainDisplay(Assignments.RANGED, roster, playerName),
        },
    })
    RefreshMarkedChain()
    ui.stack:SetEntryHeight(ui.cardsRow, ui.chainView:GetHeight())
    NotifyHeight()
end

---Mounts the read-only melee and ranged assignment view inside a host row.
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

    local markedRow = stack:AddRow(Sizes.CONTROL_ROW_HEIGHT)
    local markedLabel = Widgets.CreateLabel(markedRow, Fonts.BODY, L.COILED_ALTAR_MARKED_CORRESPONDS)
    markedLabel:SetJustifyH("LEFT")
    markedLabel:SetWordWrap(false)
    local markedHit = CreateFrame("Frame", nil, markedRow)
    markedHit:SetPoint("TOPLEFT", markedLabel, "TOPLEFT")
    markedHit:SetPoint("BOTTOMRIGHT", markedLabel, "BOTTOMRIGHT")
    markedHit:EnableMouse(true)
    Widgets.AttachTooltip(markedHit, "ANCHOR_TOP", function(tooltip)
        tooltip:SetText(L.COILED_ALTAR_MARKED_CORRESPONDS_TOOLTIP)
    end)
    local markedValue = Widgets.CreateLabel(markedRow, Fonts.BODY)
    markedValue:SetJustifyH("RIGHT")
    markedLabel:SetPoint("LEFT", markedRow, "LEFT")
    markedValue:SetPoint("RIGHT", markedRow, "RIGHT")
    ui.markedValue = markedValue

    ui.cardsRow = stack:AddRow(1)
    ui.chainView = ns.InterruptChainView.Create(ui.cardsRow)

    local previousAssignmentsChanged = CoiledAltar.OnInterruptAssignmentsChanged
    function CoiledAltar:OnInterruptAssignmentsChanged()
        Refresh()
        if previousAssignmentsChanged then
            previousAssignmentsChanged(self)
        end
    end

    Group.OnRosterChanged(function()
        if ui and ui.panel:IsShown() then
            Refresh()
        end
    end)

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
