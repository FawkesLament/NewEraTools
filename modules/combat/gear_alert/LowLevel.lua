local _, ns = ...
local Internals = ns.Modules.Internals("GearAlert")
local Equipment = ns.Api.Equipment

-- Detects empty gear slots or equipped items at or below 30% of average item level
-- when a higher-level replacement for that slot is in the bags. Does not mutate SavedVariables.

local STATUS_OK = Internals.STATUS_OK
local STATUS_UNKNOWN = Internals.STATUS_UNKNOWN
local LOW_LEVEL_RATIO = 0.3

Internals.LOW_LEVEL_RATIO = LOW_LEVEL_RATIO

---@class GearScan
---@field averageItemLevel number|nil
---@field slots EquipmentSlotScan[]
---@field bags EquipmentBagItemScan[]

---@class LowLevelItem
---@field itemLevel number
---@field slot integer

---@class LowLevelState
---@field status "ok"|"unknown"
---@field averageItemLevel number|nil
---@field threshold number|nil
---@field itemLevel number|nil
---@field lowCount integer|nil
---@field items LowLevelItem[]|nil

---@return GearScan
function Internals.CollectGearScan()
    local slots = {}
    for _, slot in ipairs(Equipment.GetGearSlots()) do
        slots[#slots + 1] = Equipment.GetSlotScan(slot)
    end
    return {
        averageItemLevel = Equipment.GetAverageItemLevel(),
        slots = slots,
        bags = Equipment.GetBagScans(),
    }
end

---Finds empty or equipped slots at or below 30% of average item level that have a
---higher-level bag item for the same slot. Empty slots count as item level 0.
---@param scan GearScan
---@return LowLevelState
function Internals.EvaluateLowLevel(scan)
    local average = scan and scan.averageItemLevel
    if type(average) ~= "number" or average <= 0 then
        return { status = STATUS_UNKNOWN }
    end

    local threshold = average * LOW_LEVEL_RATIO
    local highBySlot = {}
    local bagsIncomplete = false
    for _, bag in ipairs(scan.bags or {}) do
        local status = bag.status
        if status == "secret" or status == "pending" then
            bagsIncomplete = true
        elseif status == "ready" then
            local itemLevel = bag.itemLevel
            local slots = bag.slots
            if type(slots) == "table" and #slots > 0 then
                if type(itemLevel) ~= "number" or itemLevel <= 0 then
                    bagsIncomplete = true
                elseif itemLevel > threshold then
                    for index = 1, #slots do
                        highBySlot[slots[index]] = true
                    end
                end
            end
        end
    end

    local lowest
    local items = {}
    local equippedIncomplete = false
    local unmatchedLow = false

    local function RecordLow(itemLevel, slot)
        items[#items + 1] = { itemLevel = itemLevel, slot = slot }
        if not lowest or itemLevel < lowest then
            lowest = itemLevel
        end
    end

    for _, slot in ipairs(scan.slots) do
        local status = slot.status
        if status == "secret" or status == "pending" then
            equippedIncomplete = true
        elseif status == "empty" then
            if highBySlot[slot.slot] then
                RecordLow(0, slot.slot)
            else
                unmatchedLow = true
            end
        elseif status == "ready" then
            local itemLevel = slot.itemLevel
            if type(itemLevel) ~= "number" or itemLevel <= 0 then
                equippedIncomplete = true
            elseif itemLevel <= threshold then
                if highBySlot[slot.slot] then
                    RecordLow(itemLevel, slot.slot)
                else
                    unmatchedLow = true
                end
            end
        end
    end

    local lowCount = #items
    if lowCount > 0 then
        return {
            status = STATUS_OK,
            averageItemLevel = average,
            threshold = threshold,
            itemLevel = lowest,
            lowCount = lowCount,
            items = items,
        }
    end
    if equippedIncomplete or (unmatchedLow and bagsIncomplete) then
        return {
            status = STATUS_UNKNOWN,
            averageItemLevel = average,
            threshold = threshold,
        }
    end
    return {
        status = STATUS_OK,
        averageItemLevel = average,
        threshold = threshold,
        lowCount = 0,
    }
end

---@param state LowLevelState
---@return GearAlertPayload[]
function Internals.CheckLowLevel(state)
    if type(state) ~= "table" or state.status ~= STATUS_OK then
        return {}
    end
    if type(state.averageItemLevel) ~= "number" then
        return {}
    end
    local findings = {}
    for _, item in ipairs(state.items or {}) do
        if type(item) == "table" and type(item.itemLevel) == "number" then
            local finding = {
                type = "LOW_LEVEL_ITEM",
                itemLevel = item.itemLevel,
                averageItemLevel = state.averageItemLevel,
                slot = item.slot,
                slotName = Equipment.GetSlotName(item.slot),
            }
            if item.itemLevel <= 0 then
                findings[#findings + 1] = finding
            else
                local itemLink = Equipment.GetSlotLink(item.slot)
                if type(itemLink) == "string" and itemLink ~= "" then
                    finding.itemLink = itemLink
                    findings[#findings + 1] = finding
                end
            end
        end
    end
    return findings
end
