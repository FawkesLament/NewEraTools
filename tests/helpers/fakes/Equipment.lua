return function()
    local Equipment = {
        seasonID = 18,
        slots = {},
        armorSlots = { 1, 3, 5, 10, 7 },
        requestItemCalls = {},
        requestSeasonCalls = 0,
        changedCallbacks = {},
        itemInfoCallbacks = {},
        getSlotScanCalls = 0,
    }

    function Equipment.GetArmorSlots()
        return Equipment.armorSlots
    end

    ---@param slot integer
    ---@param data { status: string, itemID: integer|nil, setID: integer|nil }|nil
    function Equipment.SetSlotForTests(slot, data)
        Equipment.slots[slot] = data
    end

    function Equipment.ClearSlotsForTests()
        Equipment.slots = {}
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
            setID = data.setID,
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
