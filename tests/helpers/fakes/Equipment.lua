return function()
    local Equipment = {
        seasonID = 18,
        slots = {},
        bags = {},
        armorSlots = { 1, 3, 5, 10, 7 },
        gearSlots = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 },
        averageItemLevel = nil,
        requestItemCalls = {},
        requestSeasonCalls = 0,
        changedCallbacks = {},
        itemInfoCallbacks = {},
        getSlotScanCalls = 0,
        slotNames = {
            [1] = "Head",
            [2] = "Neck",
            [3] = "Shoulder",
            [5] = "Chest",
            [6] = "Waist",
            [7] = "Legs",
            [8] = "Feet",
            [9] = "Wrist",
            [10] = "Hands",
            [11] = "Finger",
            [12] = "Finger",
            [13] = "Trinket",
            [14] = "Trinket",
            [15] = "Back",
            [16] = "Main Hand",
            [17] = "Off Hand",
        },
    }

    function Equipment.GetArmorSlots()
        return Equipment.armorSlots
    end

    function Equipment.GetGearSlots()
        return Equipment.gearSlots
    end

    function Equipment.GetAverageItemLevel()
        return Equipment.averageItemLevel
    end

    ---@param slot integer
    ---@return string|nil
    function Equipment.GetSlotName(slot)
        return Equipment.slotNames[slot]
    end

    ---@param slot integer
    ---@return string|nil
    function Equipment.GetSlotLink(slot)
        local data = Equipment.slots[slot]
        if type(data) == "table" and type(data.link) == "string" and data.link ~= "" then
            return data.link
        end
        return nil
    end

    ---@param slot integer
    ---@param data { status: string, itemID: integer|nil, name: string|nil, link: string|nil, setID: integer|nil, itemLevel: number|nil }|nil
    function Equipment.SetSlotForTests(slot, data)
        Equipment.slots[slot] = data
    end

    function Equipment.ClearSlotsForTests()
        Equipment.slots = {}
    end

    function Equipment.ClearBagsForTests()
        Equipment.bags = {}
    end

    ---@param data { status: string, itemID: integer|nil, itemLevel: number|nil, slots: integer[] }
    function Equipment.SetBagItemForTests(data)
        Equipment.bags[#Equipment.bags + 1] = data
    end

    function Equipment.GetBagScans()
        return Equipment.bags
    end

    ---Fills armor slots with `count` pieces of `setID`, then empty remaining slots.
    ---@param setID integer
    ---@param count integer
    ---@param itemIDBase integer|nil
    function Equipment.SetEquippedSetForTests(setID, count, itemIDBase)
        local base = itemIDBase or (setID * 100)
        Equipment.ClearSlotsForTests()
        for index, slot in ipairs(Equipment.armorSlots) do
            if index <= count then
                Equipment.slots[slot] = {
                    status = "ready",
                    itemID = base + index,
                    setID = setID,
                }
            else
                Equipment.slots[slot] = { status = "empty" }
            end
        end
    end

    function Equipment.GetItemInfo()
        return nil, "pending"
    end

    function Equipment.GetItemQualityHex()
        return nil
    end

    function Equipment.RequestItem(itemID)
        table.insert(Equipment.requestItemCalls, itemID)
    end

    function Equipment.GetSlotScan(slot)
        Equipment.getSlotScanCalls = Equipment.getSlotScanCalls + 1
        local data = Equipment.slots[slot]
        if not data then
            return { slot = slot, status = "empty" }
        end
        return {
            slot = slot,
            status = data.status,
            itemID = data.itemID,
            name = data.name,
            setID = data.setID,
            itemLevel = data.itemLevel,
        }
    end

    function Equipment.GetCurrentSeasonID()
        if Equipment.seasonID == nil then
            Equipment.requestSeasonCalls = Equipment.requestSeasonCalls + 1
        end
        return Equipment.seasonID
    end

    function Equipment.OnChanged(callback)
        table.insert(Equipment.changedCallbacks, callback)
    end

    function Equipment.OnItemInfoReceived(callback)
        table.insert(Equipment.itemInfoCallbacks, callback)
    end

    function Equipment.FireChanged()
        for _, callback in ipairs(Equipment.changedCallbacks) do
            callback()
        end
    end

    function Equipment.FireItemInfoReceived(itemID, success)
        for _, callback in ipairs(Equipment.itemInfoCallbacks) do
            callback(itemID, success)
        end
    end

    return Equipment
end
