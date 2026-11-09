local _, ns = ...
local GameEvents = ns.Api.GameEvents
local Secrets = ns.Api.Secrets

-- Equipped-item and season adapters. Feature code must not call inventory APIs directly.
local Equipment = {}
ns.Api.Equipment = Equipment

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIDForItemInfo = C_Item and C_Item.GetItemIDForItemInfo
local RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID
local GetCurrentSeason = C_MythicPlus and C_MythicPlus.GetCurrentSeason
local RequestMapInfo = C_MythicPlus and C_MythicPlus.RequestMapInfo

-- Modern PvE tier occupies these armor slots (cloak and jewelry are not set pieces).
local SLOT_SPECS = {
    { name = "HeadSlot", fallback = 1 },
    { name = "ShoulderSlot", fallback = 3 },
    { name = "ChestSlot", fallback = 5 },
    { name = "HandsSlot", fallback = 10 },
    { name = "LegsSlot", fallback = 7 },
}

local armorSlots
local requestedSeasonInfo = false

local function SlotId(spec)
    if type(GetInventorySlotInfo) == "function" then
        local slot = GetInventorySlotInfo(spec.name)
        if type(slot) == "number" and slot > 0 then
            return slot
        end
    end
    return spec.fallback
end

---@return integer[]
function Equipment.GetArmorSlots()
    if armorSlots then
        return armorSlots
    end
    armorSlots = {}
    for index, spec in ipairs(SLOT_SPECS) do
        armorSlots[index] = SlotId(spec)
    end
    return armorSlots
end

---@param item any
---@return integer|nil
local function ItemIdFromInfo(item)
    if type(GetItemIDForItemInfo) == "function" then
        local itemID = GetItemIDForItemInfo(item)
        if type(itemID) == "number" and itemID > 0 then
            return math.floor(itemID)
        end
    end
    if type(item) == "number" and item > 0 then
        return math.floor(item)
    end
    if type(item) == "string" then
        local id = item:match("item:(%d+)")
        if id then
            return tonumber(id)
        end
    end
    return nil
end

---@class EquipmentItemInfo
---@field itemID integer|nil
---@field setID integer|nil

---Looks up cached item metadata. Does not treat a missing setID as an error.
---@param item number|string
---@return EquipmentItemInfo|nil
---@return "ready"|"pending"|"secret"
function Equipment.GetItemInfo(item)
    if Secrets.IsSecret(item) then
        return nil, "secret"
    end
    if not GetItemInfo then
        return nil, "pending"
    end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = GetItemInfo(item)
    if name == nil then
        return nil, "pending"
    end
    local itemID = ItemIdFromInfo(item)
    local normalizedSetID
    if type(setID) == "number" and setID > 0 and not Secrets.IsSecret(setID) then
        normalizedSetID = math.floor(setID)
    end
    return { itemID = itemID, setID = normalizedSetID }, "ready"
end

---Asks the client to cache item metadata. No-op when the item id is unavailable.
---@param itemID integer|nil
function Equipment.RequestItem(itemID)
    if type(itemID) ~= "number" or itemID < 1 then
        return
    end
    if type(RequestLoadItemDataByID) == "function" then
        RequestLoadItemDataByID(itemID)
    end
end

---@class EquipmentSlotScan
---@field slot integer
---@field status "empty"|"secret"|"pending"|"ready"
---@field itemID integer|nil
---@field setID integer|nil

---Reads one equipped armor slot. Empty is known; uncached or secret is not a missing piece.
---@param slot integer
---@return EquipmentSlotScan
function Equipment.GetSlotScan(slot)
    local scan = { slot = slot, status = "empty" }
    local link
    if type(GetInventoryItemLink) == "function" then
        link = GetInventoryItemLink("player", slot)
    end
    local itemID
    if type(GetInventoryItemID) == "function" then
        itemID = GetInventoryItemID("player", slot)
    end

    if Secrets.IsSecret(link) or Secrets.IsSecret(itemID) then
        scan.status = "secret"
        return scan
    end

    local item = link
    if item == nil and type(itemID) == "number" and itemID > 0 then
        item = itemID
    end
    if item == nil then
        return scan
    end

    local info, status = Equipment.GetItemInfo(item)
    scan.status = status
    if info then
        scan.itemID = info.itemID
        scan.setID = info.setID
    elseif type(itemID) == "number" and itemID > 0 then
        scan.itemID = math.floor(itemID)
    else
        scan.itemID = ItemIdFromInfo(item)
    end
    return scan
end

---Mythic+ season id used as the current PvE season key, or nil when the client has not resolved it.
---@return integer|nil
function Equipment.GetCurrentSeasonID()
    if type(GetCurrentSeason) ~= "function" then
        return nil
    end
    local seasonID = GetCurrentSeason()
    if type(seasonID) ~= "number" then
        return nil
    end
    if seasonID < 1 then
        if not requestedSeasonInfo and type(RequestMapInfo) == "function" then
            requestedSeasonInfo = true
            RequestMapInfo()
        end
        return nil
    end
    return math.floor(seasonID)
end

---Calls `callback` after an equipment slot may have changed.
---@param callback fun()
function Equipment.OnChanged(callback)
    GameEvents.Listen("PLAYER_EQUIPMENT_CHANGED", callback)
end

---Calls `callback(itemID, success)` when the client finishes (or fails) an item-info query.
---@param callback fun(itemID: any, success: any)
function Equipment.OnItemInfoReceived(callback)
    GameEvents.Listen("GET_ITEM_INFO_RECEIVED", callback)
end
