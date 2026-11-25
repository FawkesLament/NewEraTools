local _, ns = ...
local GameEvents = ns.Api.GameEvents
local Secrets = ns.Api.Secrets

-- Equipped-item and season adapters. Feature code must not call inventory APIs directly.
local Equipment = {}
ns.Api.Equipment = Equipment

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIDForItemInfo = C_Item and C_Item.GetItemIDForItemInfo
local RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local GetCurrentItemLevel = C_Item and C_Item.GetCurrentItemLevel
local GetAverageItemLevel = GetAverageItemLevel
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
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

-- Equipped slots that contribute to average item level. Shirt and tabard are excluded.
local GEAR_SLOT_SPECS = {
    { name = "HeadSlot", fallback = 1 },
    { name = "NeckSlot", fallback = 2 },
    { name = "ShoulderSlot", fallback = 3 },
    { name = "ChestSlot", fallback = 5 },
    { name = "WaistSlot", fallback = 6 },
    { name = "LegsSlot", fallback = 7 },
    { name = "FeetSlot", fallback = 8 },
    { name = "WristSlot", fallback = 9 },
    { name = "HandsSlot", fallback = 10 },
    { name = "Finger0Slot", fallback = 11 },
    { name = "Finger1Slot", fallback = 12 },
    { name = "Trinket0Slot", fallback = 13 },
    { name = "Trinket1Slot", fallback = 14 },
    { name = "BackSlot", fallback = 15 },
    { name = "MainHandSlot", fallback = 16 },
    { name = "SecondaryHandSlot", fallback = 17 },
}

-- Inventory types that can occupy the gear slots above. Shirt and tabard are excluded.
local EQUIP_LOC_SLOT_NAMES = {
    INVTYPE_HEAD = { "HeadSlot" },
    INVTYPE_NECK = { "NeckSlot" },
    INVTYPE_SHOULDER = { "ShoulderSlot" },
    INVTYPE_CHEST = { "ChestSlot" },
    INVTYPE_ROBE = { "ChestSlot" },
    INVTYPE_WAIST = { "WaistSlot" },
    INVTYPE_LEGS = { "LegsSlot" },
    INVTYPE_FEET = { "FeetSlot" },
    INVTYPE_WRIST = { "WristSlot" },
    INVTYPE_HAND = { "HandsSlot" },
    INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_CLOAK = { "BackSlot" },
    INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
    INVTYPE_2HWEAPON = { "MainHandSlot" },
    INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
    INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
    INVTYPE_SHIELD = { "SecondaryHandSlot" },
    INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
    INVTYPE_RANGED = { "MainHandSlot" },
    INVTYPE_RANGEDRIGHT = { "MainHandSlot" },
}

local armorSlots
local gearSlots
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

---@param name string
---@return integer|nil
local function SlotIdByName(name)
    for _, spec in ipairs(GEAR_SLOT_SPECS) do
        if spec.name == name then
            return SlotId(spec)
        end
    end
    return nil
end

---@param equipLoc string|nil
---@return integer[]
local function SlotsForEquipLoc(equipLoc)
    local names = type(equipLoc) == "string" and EQUIP_LOC_SLOT_NAMES[equipLoc]
    if not names then
        return {}
    end
    local slots = {}
    for _, name in ipairs(names) do
        local slot = SlotIdByName(name)
        if type(slot) == "number" then
            slots[#slots + 1] = slot
        end
    end
    return slots
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

---@return integer[]
function Equipment.GetGearSlots()
    if gearSlots then
        return gearSlots
    end
    gearSlots = {}
    for index, spec in ipairs(GEAR_SLOT_SPECS) do
        gearSlots[index] = SlotId(spec)
    end
    return gearSlots
end

---Localized paper-doll name for a gear slot (`HEADSLOT`, `FINGER0SLOT`, …).
---@param slot integer
---@return string|nil
function Equipment.GetSlotName(slot)
    if type(slot) ~= "number" then
        return nil
    end
    for _, spec in ipairs(GEAR_SLOT_SPECS) do
        if SlotId(spec) == slot then
            local name = _G[string.upper(spec.name)]
            if type(name) == "string" and name ~= "" then
                return name
            end
            return nil
        end
    end
    return nil
end

---Equipped item link for `slot`, or nil when empty, uncached, or secret.
---@param slot integer
---@return string|nil
function Equipment.GetSlotLink(slot)
    if type(slot) ~= "number" or type(GetInventoryItemLink) ~= "function" then
        return nil
    end
    local link = GetInventoryItemLink("player", slot)
    if Secrets.IsSecret(link) then
        return nil
    end
    if type(link) == "string" and link ~= "" then
        return link
    end
    return nil
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
---@field name string|nil
---@field quality integer|nil
---@field setID integer|nil
---@field itemLevel integer|nil
---@field equipLoc string|nil

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
    local name, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, _, _, _, _, setID = GetItemInfo(item)
    if name == nil then
        return nil, "pending"
    end
    if
        Secrets.IsSecret(name)
        or Secrets.IsSecret(quality)
        or Secrets.IsSecret(itemLevel)
        or Secrets.IsSecret(equipLoc)
    then
        return nil, "secret"
    end
    local itemID = ItemIdFromInfo(item)
    local normalizedName
    if type(name) == "string" and name ~= "" then
        normalizedName = name
    end
    local normalizedQuality
    if type(quality) == "number" then
        normalizedQuality = math.floor(quality)
    end
    local normalizedSetID
    if type(setID) == "number" and setID > 0 and not Secrets.IsSecret(setID) then
        normalizedSetID = math.floor(setID)
    end
    local normalizedItemLevel
    if type(itemLevel) == "number" and itemLevel > 0 then
        normalizedItemLevel = math.floor(itemLevel)
    end
    local normalizedEquipLoc
    if type(equipLoc) == "string" and equipLoc ~= "" then
        normalizedEquipLoc = equipLoc
    end
    return {
        itemID = itemID,
        name = normalizedName,
        quality = normalizedQuality,
        setID = normalizedSetID,
        itemLevel = normalizedItemLevel,
        equipLoc = normalizedEquipLoc,
    },
        "ready"
end

---Quality color markup prefix from `ITEM_QUALITY_COLORS` (includes `|c`).
---@param quality integer|nil
---@return string|nil
function Equipment.GetItemQualityHex(quality)
    if type(quality) ~= "number" then
        return nil
    end
    local colors = ITEM_QUALITY_COLORS
    if type(colors) ~= "table" then
        return nil
    end
    local color = colors[quality]
    if type(color) ~= "table" then
        color = colors[math.floor(quality)]
    end
    if type(color) ~= "table" or type(color.hex) ~= "string" or color.hex == "" then
        return nil
    end
    return color.hex
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
---@field name string|nil
---@field setID integer|nil
---@field itemLevel integer|nil

---@class EquipmentBagItemScan
---@field status "secret"|"pending"|"ready"
---@field itemID integer|nil
---@field itemLevel integer|nil
---@field slots integer[]

---@param scan table
local function MarkScanSecret(scan)
    scan.status = "secret"
    scan.name = nil
    scan.setID = nil
    scan.itemLevel = nil
    scan.slots = nil
end

---Item links can report a scaled preview level (Heart of Azeroth) that does not match the
---character-sheet item level. Prefer the location API; fall back to the link-based detailed level.
---@param scan table
---@param item number|string
---@param location table|nil
local function OverlayItemLevel(scan, item, location)
    if scan.status ~= "ready" then
        return
    end
    if location and type(GetCurrentItemLevel) == "function" then
        local current = GetCurrentItemLevel(location)
        if Secrets.IsSecret(current) then
            MarkScanSecret(scan)
            return
        end
        if type(current) == "number" and current > 0 then
            scan.itemLevel = math.floor(current)
            return
        end
    end
    if type(GetDetailedItemLevelInfo) ~= "function" then
        return
    end
    local detailed = GetDetailedItemLevelInfo(item)
    if Secrets.IsSecret(detailed) then
        MarkScanSecret(scan)
        return
    end
    if type(detailed) == "number" and detailed > 0 then
        scan.itemLevel = math.floor(detailed)
    end
end

---@param slot integer
---@return table|nil
local function EquipmentItemLocation(slot)
    if type(ItemLocation) ~= "table" or type(ItemLocation.CreateFromEquipmentSlot) ~= "function" then
        return nil
    end
    return ItemLocation:CreateFromEquipmentSlot(slot)
end

---@param bag integer
---@param bagSlot integer
---@return table|nil
local function BagItemLocation(bag, bagSlot)
    if type(ItemLocation) ~= "table" or type(ItemLocation.CreateFromBagAndSlot) ~= "function" then
        return nil
    end
    return ItemLocation:CreateFromBagAndSlot(bag, bagSlot)
end

---@param scan table
---@param item number|string
---@param itemID integer|nil
---@param location table|nil
local function FillItemScan(scan, item, itemID, location)
    local info, status = Equipment.GetItemInfo(item)
    scan.status = status
    if info then
        scan.itemID = info.itemID
        scan.name = info.name
        scan.setID = info.setID
        scan.itemLevel = info.itemLevel
        scan.equipLoc = info.equipLoc
    elseif type(itemID) == "number" and itemID > 0 then
        scan.itemID = math.floor(itemID)
    else
        scan.itemID = ItemIdFromInfo(item)
    end
    OverlayItemLevel(scan, item, location)
end

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

    FillItemScan(scan, item, itemID, EquipmentItemLocation(slot))
    return scan
end

---@return integer
local function LastBagIndex()
    if type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS >= 0 then
        return NUM_BAG_SLOTS
    end
    return 4
end

---Reads backpack and equipped bags. Empty slots are omitted; uncached or secret items are kept.
---@return EquipmentBagItemScan[]
function Equipment.GetBagScans()
    local scans = {}
    if type(GetContainerNumSlots) ~= "function" then
        return scans
    end
    for bag = 0, LastBagIndex() do
        local numSlots = GetContainerNumSlots(bag)
        if type(numSlots) == "number" then
            for bagSlot = 1, numSlots do
                local link
                if type(GetContainerItemLink) == "function" then
                    link = GetContainerItemLink(bag, bagSlot)
                end
                local itemID
                if type(GetContainerItemID) == "function" then
                    itemID = GetContainerItemID(bag, bagSlot)
                end
                if Secrets.IsSecret(link) or Secrets.IsSecret(itemID) then
                    scans[#scans + 1] = { status = "secret", slots = {} }
                else
                    local item = link
                    if item == nil and type(itemID) == "number" and itemID > 0 then
                        item = itemID
                    end
                    if item ~= nil then
                        local scan = { status = "pending", slots = {} }
                        FillItemScan(scan, item, itemID, BagItemLocation(bag, bagSlot))
                        if scan.status == "ready" then
                            scan.slots = SlotsForEquipLoc(scan.equipLoc)
                        end
                        scan.equipLoc = nil
                        scan.setID = nil
                        scans[#scans + 1] = scan
                    end
                end
            end
        end
    end
    return scans
end

---Equipped average item level, or overall when equipped is unavailable.
---@return number|nil
function Equipment.GetAverageItemLevel()
    if type(GetAverageItemLevel) ~= "function" then
        return nil
    end
    local overall, equipped = GetAverageItemLevel()
    if Secrets.IsSecret(overall) or Secrets.IsSecret(equipped) then
        return nil
    end
    local value = equipped
    if type(value) ~= "number" or value <= 0 then
        value = overall
    end
    if type(value) ~= "number" or value <= 0 then
        return nil
    end
    return value
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
