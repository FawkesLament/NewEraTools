local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local L = ns.L

local CoiledAltar = ns.Modules.Get("CoiledAltar")
local Assignments = Internals.InterruptAssignments

---@class CoiledAltarAddonCheckSlot
---@field chain CoiledAltarInterruptChainId
---@field slot integer

---@class CoiledAltarAddonCheckExpectedSlot: CoiledAltarAddonCheckSlot
---@field player string

---@class CoiledAltarAddonCheckMismatch
---@field mismatch true
---@field expected any
---@field reported any

---@class CoiledAltarAddonCheckConfig
---@field player string|nil
---@field assignments CoiledAltarAddonCheckSlot[]|CoiledAltarAddonCheckMismatch
---@field markedChain CoiledAltarInterruptChainId|CoiledAltarAddonCheckMismatch
---@field reminder boolean
---@field expectedSlots CoiledAltarAddonCheckExpectedSlot[]|nil  Raid-leader snapshot only; freezes expected assignments.

---@param value any
---@return boolean
local function IsMismatch(value)
    return type(value) == "table" and value.mismatch == true
end

---@param value any
---@return any
local function Unwrap(value)
    if IsMismatch(value) then
        return value.reported
    end
    return value
end

---@param chainId any
---@return string|nil
local function ChainLabel(chainId)
    if chainId == Assignments.MELEE then
        return L.COILED_ALTAR_MARKED_SIDE_MELEE
    end
    if chainId == Assignments.RANGED then
        return L.COILED_ALTAR_MARKED_SIDE_RANGED
    end
end

---Sorted unique (chain, slot) pairs. Invalid input returns nil.
---@param value any
---@return CoiledAltarAddonCheckSlot[]|nil
local function NormalizeAssignments(value)
    value = Unwrap(value)
    if type(value) ~= "table" then
        return nil
    end
    local list = {}
    local seen = {}
    for index = 1, #value do
        local item = value[index]
        if type(item) ~= "table" then
            return nil
        end
        local chainId = item.chain
        local slot = item.slot
        if not Assignments.IsChain(chainId) then
            return nil
        end
        if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Assignments.SLOT_COUNT then
            return nil
        end
        local key = chainId .. ":" .. tostring(slot)
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { chain = chainId, slot = slot }
        end
    end
    table.sort(list, function(left, right)
        if left.chain ~= right.chain then
            return left.chain < right.chain
        end
        return left.slot < right.slot
    end)
    return list
end

---@param left CoiledAltarAddonCheckSlot[]
---@param right CoiledAltarAddonCheckSlot[]
---@return boolean
local function AssignmentSetsEqual(left, right)
    if #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index].chain ~= right[index].chain or left[index].slot ~= right[index].slot then
            return false
        end
    end
    return true
end

---@param assignments CoiledAltarInterruptAssignments|nil
---@return CoiledAltarAddonCheckExpectedSlot[]
local function SnapshotExpectedSlots(assignments)
    local slots = {}
    if type(assignments) ~= "table" then
        return slots
    end
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local chain = assignments[chainId]
        if type(chain) == "table" then
            for index = 1, Assignments.SLOT_COUNT do
                local slot = chain[index]
                if type(slot) == "table" and slot.type == Assignments.TYPE_PLAYER then
                    local name = Assignments.QualifyName(slot.value)
                    if name then
                        slots[#slots + 1] = { player = name, chain = chainId, slot = index }
                    end
                end
            end
        end
    end
    return slots
end

---@param expectedSlots CoiledAltarAddonCheckExpectedSlot[]|nil
---@param playerName string|nil
---@return CoiledAltarAddonCheckSlot[]
local function AssignmentsForPlayer(expectedSlots, playerName)
    local name = Assignments.QualifyName(playerName)
    local slots = {}
    if not name or type(expectedSlots) ~= "table" then
        return slots
    end
    for index = 1, #expectedSlots do
        local entry = expectedSlots[index]
        if type(entry) == "table" and entry.player == name and Assignments.IsChain(entry.chain) then
            local slot = entry.slot
            if type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= Assignments.SLOT_COUNT then
                slots[#slots + 1] = { chain = entry.chain, slot = slot }
            end
        end
    end
    return assert(NormalizeAssignments(slots))
end

---@param localConfig any
---@param playerName string|nil
---@return CoiledAltarAddonCheckSlot[]
local function ExpectedAssignments(localConfig, playerName)
    if type(localConfig) == "table" and type(localConfig.expectedSlots) == "table" then
        return AssignmentsForPlayer(localConfig.expectedSlots, playerName)
    end
    return AssignmentsForPlayer(SnapshotExpectedSlots(CoiledAltar.db and CoiledAltar.db.assignments), playerName)
end

---@param marked any
---@return CoiledAltarInterruptChainId|nil
local function NormalizeMarkedChain(marked)
    marked = Unwrap(marked)
    if Assignments.IsChain(marked) then
        return marked
    end
end

---Live AddonCheck snapshot. Reads current settings; does not mutate them.
---@return CoiledAltarAddonCheckConfig
function CoiledAltar:GetAddonCheckConfig()
    local player = Assignments.ResolveLocalPlayerName()
    local config = {
        player = player,
        assignments = Assignments.PlayerSlots(self.db.assignments, player),
        markedChain = self:GetMarkedChain(),
        reminder = self:IsInterruptReminderEnabled(),
    }
    -- Only the raid leader's StartCheck snapshot needs expected sets; members stay compact on the wire.
    if self:IsRaidCommander() then
        config.expectedSlots = SnapshotExpectedSlots(self.db.assignments)
    end
    return config
end

---AddonCheck panel validator: column keys to highlight, or nil when ok.
---Flags personal interrupt assignments and marked-enemy side against the commander.
---Does not wrap reminder; version/reminder follow the shared AddonCheck panel rules.
---@param config any
---@param localConfig any
---@return string[]|nil
function CoiledAltar.ValidateAddonCheckConfig(config, localConfig)
    if type(config) ~= "table" then
        return { "assignments", "markedChain" }
    end
    local flagged = {}
    local reported = NormalizeAssignments(config.assignments)
    local playerName = Assignments.QualifyName(config.player)
    local expected = ExpectedAssignments(localConfig, playerName)
    if not playerName or not reported then
        flagged[#flagged + 1] = "assignments"
    elseif not AssignmentSetsEqual(reported, expected) then
        flagged[#flagged + 1] = "assignments"
        config.assignments = {
            mismatch = true,
            expected = expected,
            reported = reported,
        }
    else
        config.assignments = reported
    end

    local reportedMarked = NormalizeMarkedChain(config.markedChain)
    local expectedMarked = type(localConfig) == "table" and NormalizeMarkedChain(localConfig.markedChain) or nil
    if not reportedMarked then
        flagged[#flagged + 1] = "markedChain"
    elseif expectedMarked and reportedMarked ~= expectedMarked then
        flagged[#flagged + 1] = "markedChain"
        config.markedChain = {
            mismatch = true,
            expected = expectedMarked,
            reported = reportedMarked,
        }
    else
        config.markedChain = reportedMarked
    end

    if #flagged == 0 then
        return nil
    end
    return flagged
end

---@param value any
---@return string|nil
function CoiledAltar.FormatAddonCheckAssignment(value)
    if IsMismatch(value) then
        return string.format(
            L.COILED_ALTAR_ADDONCHECK_MISMATCH,
            CoiledAltar.FormatAddonCheckAssignment(value.expected) or L.COILED_ALTAR_ADDONCHECK_UNASSIGNED,
            CoiledAltar.FormatAddonCheckAssignment(value.reported) or L.COILED_ALTAR_ADDONCHECK_UNASSIGNED
        )
    end
    local list = NormalizeAssignments(value)
    if not list then
        return nil
    end
    if #list == 0 then
        return L.COILED_ALTAR_ADDONCHECK_UNASSIGNED
    end
    local parts = {}
    for _, chainId in ipairs(Assignments.CHAIN_IDS) do
        local slots = {}
        for index = 1, #list do
            local item = list[index]
            if item.chain == chainId then
                slots[#slots + 1] = tostring(item.slot)
            end
        end
        if #slots > 0 then
            parts[#parts + 1] = string.format(
                L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS,
                ChainLabel(chainId),
                table.concat(slots, L.COILED_ALTAR_ADDONCHECK_SLOT_JOIN)
            )
        end
    end
    return table.concat(parts, L.COILED_ALTAR_ADDONCHECK_CHAIN_JOIN)
end

---@param value any
---@return string|nil
function CoiledAltar.FormatAddonCheckMarked(value)
    if IsMismatch(value) then
        return string.format(
            L.COILED_ALTAR_ADDONCHECK_MISMATCH,
            CoiledAltar.FormatAddonCheckMarked(value.expected) or L.ADDONCHECK_EM_DASH,
            CoiledAltar.FormatAddonCheckMarked(value.reported) or L.ADDONCHECK_EM_DASH
        )
    end
    return ChainLabel(value)
end

---@param value any
---@return string|nil
function CoiledAltar.FormatAddonCheckReminder(value)
    if value == true then
        return L.COILED_ALTAR_ADDONCHECK_REMINDER_ON
    end
    if value == false then
        return L.COILED_ALTAR_ADDONCHECK_REMINDER_OFF
    end
end

---@return AddonCheckPanelColumn[]
function CoiledAltar.AddonCheckColumns()
    return {
        {
            key = "assignments",
            title = L.COILED_ALTAR_ADDONCHECK_COL_ASSIGNMENT,
            format = CoiledAltar.FormatAddonCheckAssignment,
            flex = 2,
        },
        {
            key = "markedChain",
            title = L.COILED_ALTAR_ADDONCHECK_COL_MARKED,
            format = CoiledAltar.FormatAddonCheckMarked,
        },
        {
            key = "reminder",
            title = L.COILED_ALTAR_ADDONCHECK_COL_REMINDER,
            format = CoiledAltar.FormatAddonCheckReminder,
        },
    }
end
