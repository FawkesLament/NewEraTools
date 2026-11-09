local _, ns = ...
local Internals = ns.Modules.Internals("GearAlert")
local Equipment = ns.Api.Equipment
local Player = ns.Api.Player

-- Pure current-season tier-set evaluation and history check. Does not mutate SavedVariables.

local STATUS_OK = "ok"
local STATUS_UNKNOWN = "unknown"
local STATUS_UNSUPPORTED = "unsupported"

Internals.STATUS_OK = STATUS_OK
Internals.STATUS_UNKNOWN = STATUS_UNKNOWN
Internals.STATUS_UNSUPPORTED = STATUS_UNSUPPORTED

---@class TierSetScan
---@field seasonID integer|nil
---@field classFile string|nil
---@field slots EquipmentSlotScan[]

---@class TierSetState
---@field status "ok"|"unknown"|"unsupported"
---@field seasonID integer|nil
---@field setIDs integer[]
---@field itemIDs integer[]
---@field equipped integer|nil
---@field required integer
---@field complete boolean|nil

---@param list integer[]
---@param value integer
---@return boolean
local function Contains(list, value)
    for index = 1, #list do
        if list[index] == value then
            return true
        end
    end
    return false
end

---@param history table|nil
---@param seasonID integer
---@return boolean
local function HadFourPiece(history, seasonID)
    if type(history) ~= "table" then
        return false
    end
    local entry = history[seasonID] or history[tostring(seasonID)]
    return type(entry) == "table" and entry.hadFourPiece == true
end

---Reads equipped armor slots and the current Mythic+ season id.
---@return TierSetScan
function Internals.CollectScan()
    local slots = {}
    for _, slot in ipairs(Equipment.GetArmorSlots()) do
        slots[#slots + 1] = Equipment.GetSlotScan(slot)
    end
    return {
        seasonID = Equipment.GetCurrentSeasonID(),
        classFile = Player.GetClassFile(),
        slots = slots,
    }
end

---Counts current-season class tier pieces. Unrelated and old-season sets are ignored, not merged.
---@param scan TierSetScan
---@param catalog table<integer, TierSetSeasonCatalog>|nil
---@return TierSetState
function Internals.Evaluate(scan, catalog)
    catalog = catalog or Internals.Catalog
    local required = Internals.REQUIRED_PIECES
    local empty = {
        status = STATUS_UNKNOWN,
        seasonID = scan.seasonID,
        setIDs = {},
        itemIDs = {},
        equipped = nil,
        required = required,
        complete = nil,
    }

    if type(scan.seasonID) ~= "number" then
        empty.status = STATUS_UNKNOWN
        return empty
    end

    local season = catalog[scan.seasonID]
    if type(season) ~= "table" then
        empty.status = STATUS_UNSUPPORTED
        empty.seasonID = scan.seasonID
        return empty
    end
    if type(season.required) == "number" and season.required > 0 then
        required = season.required
        empty.required = required
    end

    if type(scan.classFile) ~= "string" or scan.classFile == "" then
        empty.status = STATUS_UNKNOWN
        return empty
    end

    local allowed = season.setsByClass and season.setsByClass[scan.classFile]
    if type(allowed) ~= "table" or #allowed == 0 then
        empty.status = STATUS_UNSUPPORTED
        return empty
    end

    local counts = {}
    local itemIDsBySet = {}
    local incomplete = false
    for _, slot in ipairs(scan.slots) do
        local status = slot.status
        if status == "secret" or status == "pending" then
            incomplete = true
        elseif status == "ready" and type(slot.setID) == "number" and Contains(allowed, slot.setID) then
            local setID = slot.setID
            counts[setID] = (counts[setID] or 0) + 1
            itemIDsBySet[setID] = itemIDsBySet[setID] or {}
            if type(slot.itemID) == "number" then
                itemIDsBySet[setID][#itemIDsBySet[setID] + 1] = slot.itemID
            end
        end
    end

    local equipped = 0
    local setIDs = {}
    local itemIDs = {}
    for setID, count in pairs(counts) do
        if count > equipped then
            equipped = count
            setIDs = { setID }
            itemIDs = itemIDsBySet[setID] or {}
        end
    end

    -- Incomplete slots must not look like a missing piece. Four confirmed pieces are enough.
    if incomplete and equipped < required then
        empty.status = STATUS_UNKNOWN
        empty.required = required
        empty.setIDs = setIDs
        empty.itemIDs = itemIDs
        return empty
    end

    return {
        status = STATUS_OK,
        seasonID = scan.seasonID,
        setIDs = setIDs,
        itemIDs = itemIDs,
        equipped = equipped,
        required = required,
        complete = equipped >= required,
    }
end

---@param history table|nil
---@param state TierSetState
---@return GearAlertPayload|nil
function Internals.CheckMissing(history, state)
    if type(state) ~= "table" or state.status ~= STATUS_OK then
        return nil
    end
    if type(state.seasonID) ~= "number" then
        return nil
    end
    if type(state.equipped) ~= "number" then
        return nil
    end
    if not HadFourPiece(history, state.seasonID) then
        return nil
    end
    if state.equipped >= state.required then
        return nil
    end
    return {
        type = "MISSING_TIER_SET",
        equipped = state.equipped,
        required = state.required,
    }
end

---Sets hadFourPiece when four current-season pieces are positively confirmed. Never clears it.
---@param history table|nil
---@param state TierSetState
function Internals.RecordHistory(history, state)
    if type(history) ~= "table" or type(state) ~= "table" then
        return
    end
    if state.status ~= STATUS_OK or state.complete ~= true then
        return
    end
    if type(state.seasonID) ~= "number" then
        return
    end
    local entry = history[state.seasonID]
    if type(entry) ~= "table" then
        entry = {}
        history[state.seasonID] = entry
    end
    entry.hadFourPiece = true
end

---@param history table|nil
---@param state TierSetState|nil
---@return boolean
function Internals.HistoryHadFourPiece(history, state)
    if type(state) ~= "table" or type(state.seasonID) ~= "number" then
        return false
    end
    return HadFourPiece(history, state.seasonID)
end
