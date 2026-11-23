---Read-only Coiled Altar interrupt-chain Member View (single-chain list, not the M6 region cards).
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
local ACTIVE_CHAIN = Assignments.ACTIVE_CHAIN

local PAD_X = Spacing.LARGE
local HEADER_HEIGHT = Sizes.CONTENT_SECTION_HEADER
local ROW_HEIGHT = Sizes.CONTROL_ROW_HEIGHT
local SEQUENCE_WIDTH = 28
local YOU_WIDTH = 24
local ACCENT_WIDTH = 2
local HIGHLIGHT_ALPHA = 0.12
local ACCENT_ALPHA = 0.9
local DIVIDER_COLOR = Colors.MENU_DIVIDER

local MemberView = {}
Internals.InterruptAssignmentsMemberView = MemberView

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

---@class CoiledAltarMemberViewRowData
---@field slot string
---@field text string
---@field highlight boolean
---@field slotColor { r: number, g: number, b: number }
---@field textColor { r: number, g: number, b: number }

---@param slot CoiledAltarInterruptSlot
---@param roster RaidMember[]
---@param playerName string|nil
---@param index integer
---@return CoiledAltarMemberViewRowData
local function RowFromSlot(slot, roster, playerName, index)
    local identity = Assignments.QualifyName(playerName)
    local label = ns.InterruptChainView.FormatSequence(index)
    if slot.type == Assignments.TYPE_TEXT then
        return {
            slot = label,
            text = slot.value or "",
            highlight = false,
            slotColor = Colors.ACCENT,
            textColor = Colors.TEXT_GOLD,
        }
    end
    if slot.type == Assignments.TYPE_PLAYER then
        local stored = slot.value or ""
        local isYou = identity ~= nil and stored == identity
        local text = ShortName(stored)
        local color = Colors.TEXT
        for _, member in ipairs(roster) do
            if Assignments.QualifyName(member.fullName or member.name) == stored then
                text = member.name
                color = ClassColor(member.classFile)
                break
            end
        end
        return {
            slot = label,
            text = text,
            highlight = isYou,
            slotColor = Colors.ACCENT,
            textColor = color,
        }
    end
    return {
            slot = label,
            text = L.COILED_ALTAR_INTERRUPT_SLOT_EMPTY,
            highlight = false,
            slotColor = Colors.TEXT_MUTED,
            textColor = Colors.TEXT_MUTED,
    }
end

---@param slot CoiledAltarInterruptSlot|nil
---@return boolean
local function SlotIsOccupied(slot)
    return slot ~= nil and (slot.type == Assignments.TYPE_PLAYER or slot.type == Assignments.TYPE_TEXT)
end

---Last occupied slot, or 1 when the chain is empty so one unassigned row remains.
---@return integer
local function VisibleSlotCount()
    local last = 0
    for index = 1, Assignments.SLOT_COUNT do
        if SlotIsOccupied(CoiledAltar:GetInterruptSlot(ACTIVE_CHAIN, index)) then
            last = index
        end
    end
    if last == 0 then
        return 1
    end
    return last
end

---@return number
local function PanelHeight()
    return HEADER_HEIGHT + VisibleSlotCount() * ROW_HEIGHT
end

local function NotifyHeight()
    if not ui or not ui.onHeightChanged or not ui.panel:IsShown() then
        return
    end
    local height = PanelHeight()
    if height == lastNotifiedHeight then
        return
    end
    lastNotifiedHeight = height
    if ui.syncHost then
        ui.syncHost()
    end
    ui.onHeightChanged(height)
end

---@param parent Frame
---@param color { r: number, g: number, b: number, a: number|nil }
---@return Texture
local function AddDivider(parent, color)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", PAD_X, 0)
    line:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD_X, 0)
    line:SetColorTexture(color.r, color.g, color.b, color.a or 0.06)
    return line
end

---@param parent Frame
---@return Frame
local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    local y = -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:Hide()
    row.highlight = highlight

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(ACCENT_WIDTH)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:Hide()
    row.accent = accent

    local number = Widgets.CreateLabel(row, Fonts.BODY)
    number:SetJustifyH("LEFT")
    number:SetWidth(SEQUENCE_WIDTH)
    number:SetPoint("LEFT", row, "LEFT", PAD_X, 0)
    row.number = number

    local you = Widgets.CreateLabel(row, Fonts.TINY_MUTED)
    you:SetJustifyH("RIGHT")
    you:SetWidth(YOU_WIDTH)
    you:SetPoint("RIGHT", row, "RIGHT", -PAD_X, 0)
    row.you = you

    local name = Widgets.CreateLabel(row, Fonts.BODY)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetPoint("LEFT", number, "RIGHT", Spacing.SMALL, 0)
    name:SetPoint("RIGHT", you, "LEFT", -Spacing.SMALL, 0)
    row.name = name

    if index < Assignments.SLOT_COUNT then
        row.divider = AddDivider(row, DIVIDER_COLOR)
    end
    return row
end

---@param row Frame
---@param data CoiledAltarMemberViewRowData
local function ApplyRow(row, data)
    row.number:SetText(data.slot)
    row.number:SetTextColor(Widgets.UnpackColor(data.slotColor))
    row.name:SetText(data.text)
    row.name:SetTextColor(Widgets.UnpackColor(data.textColor))
    if data.highlight then
        local accent = Colors.ACCENT
        row.highlight:SetColorTexture(accent.r, accent.g, accent.b, HIGHLIGHT_ALPHA)
        row.highlight:Show()
        row.accent:SetColorTexture(accent.r, accent.g, accent.b, ACCENT_ALPHA)
        row.accent:Show()
        row.you:SetText(L.COILED_ALTAR_INTERRUPT_YOU)
        row.you:SetTextColor(Widgets.UnpackColor(accent))
    else
        row.highlight:Hide()
        row.accent:Hide()
        row.you:SetText("")
    end
end

local function Refresh()
    if not ui then
        return
    end
    local roster = Roster()
    local playerName = Player.GetFullName()
    local visibleCount = VisibleSlotCount()
    for index = 1, Assignments.SLOT_COUNT do
        local row = ui.rows[index]
        if index <= visibleCount then
            local slot = CoiledAltar:GetInterruptSlot(ACTIVE_CHAIN, index) or { type = Assignments.TYPE_EMPTY }
            ApplyRow(row, RowFromSlot(slot, roster, playerName, index))
            row:Show()
            if row.divider then
                row.divider:SetShown(index < visibleCount)
            end
        else
            row:Hide()
        end
    end
    NotifyHeight()
end

---Mounts the read-only interrupt assignment view inside a host row.
---@param host Frame
---@param onHeightChanged fun(height: number)
---@return number
function MemberView.Mount(host, onHeightChanged)
    local panel = Widgets.CreateSurface(host, Colors.SURFACE, Colors.BORDER)

    local title = Widgets.CreateLabel(panel, Fonts.BODY, L.COILED_ALTAR_INTERRUPT_STATUS_TITLE)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, 0)
    title:SetHeight(HEADER_HEIGHT)

    local rows = {}
    for index = 1, Assignments.SLOT_COUNT do
        rows[index] = CreateRow(panel, index)
    end

    lastNotifiedHeight = nil
    ui = {
        panel = panel,
        title = title,
        rows = rows,
        onHeightChanged = onHeightChanged,
    }
    ui.syncHost = Layout.MountInHost(panel, host, PanelHeight)

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
    return PanelHeight()
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
        if ui.syncHost then
            ui.syncHost()
        end
        MemberView.Refresh()
        return
    end
    lastNotifiedHeight = nil
    ui.panel:Hide()
end
