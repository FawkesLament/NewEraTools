describe("Equipment production", function()
    local saved = {}

    local function SaveGlobals()
        saved.GetInventorySlotInfo = GetInventorySlotInfo
        saved.GetInventoryItemLink = GetInventoryItemLink
        saved.GetInventoryItemID = GetInventoryItemID
        saved.GetAverageItemLevel = GetAverageItemLevel
        saved.GetDetailedItemLevelInfo = GetDetailedItemLevelInfo
        saved.ItemLocation = ItemLocation
        saved.C_Item = C_Item
        saved.C_Container = C_Container
        saved.C_MythicPlus = C_MythicPlus
        saved.NUM_BAG_SLOTS = NUM_BAG_SLOTS
        saved.issecretvalue = issecretvalue
        saved.ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
        saved.HEADSLOT = _G.HEADSLOT
    end

    local function Load()
        local ns = {
            Api = {
                GameEvents = {
                    Listen = function()
                        return function() end
                    end,
                },
                Secrets = {
                    IsSecret = function(value)
                        return issecretvalue and issecretvalue(value)
                    end,
                },
            },
        }
        assert(loadfile("api/Equipment.lua"))("NewEraTools", ns)
        return ns.Api.Equipment
    end

    before_each(function()
        SaveGlobals()
        GetInventorySlotInfo = function(name)
            local slots = {
                HeadSlot = 1,
                ShoulderSlot = 3,
                ChestSlot = 5,
                HandsSlot = 10,
                LegsSlot = 7,
            }
            return slots[name]
        end
        GetInventoryItemLink = function()
            return nil
        end
        GetInventoryItemID = function()
            return nil
        end
        C_Item = nil
        C_Container = nil
        C_MythicPlus = nil
        NUM_BAG_SLOTS = 4
        GetAverageItemLevel = nil
        GetDetailedItemLevelInfo = nil
        ItemLocation = nil
        issecretvalue = nil
        ITEM_QUALITY_COLORS = nil
    end)

    after_each(function()
        GetInventorySlotInfo = saved.GetInventorySlotInfo
        GetInventoryItemLink = saved.GetInventoryItemLink
        GetInventoryItemID = saved.GetInventoryItemID
        GetAverageItemLevel = saved.GetAverageItemLevel
        GetDetailedItemLevelInfo = saved.GetDetailedItemLevelInfo
        ItemLocation = saved.ItemLocation
        C_Item = saved.C_Item
        C_Container = saved.C_Container
        C_MythicPlus = saved.C_MythicPlus
        NUM_BAG_SLOTS = saved.NUM_BAG_SLOTS
        issecretvalue = saved.issecretvalue
        ITEM_QUALITY_COLORS = saved.ITEM_QUALITY_COLORS
        _G.HEADSLOT = saved.HEADSLOT
    end)

    it("reads an equipped set item once item info is cached", function()
        GetInventoryItemLink = function(_, slot)
            if slot == 1 then
                return "item:271531"
            end
        end
        C_Item = {
            GetItemInfo = function(item)
                if item == "item:271531" then
                    return "Chest", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 11, 2057
                end
            end,
            GetItemIDForItemInfo = function()
                return 271531
            end,
        }
        local Equipment = Load()
        local scan = Equipment.GetSlotScan(1)
        assert.equals("ready", scan.status)
        assert.equals(271531, scan.itemID)
        assert.equals("Chest", scan.name)
        assert.equals(2057, scan.setID)
    end)

    it("prefers the detailed item level of an equipped item", function()
        GetInventoryItemLink = function(_, slot)
            if slot == 1 then
                return "item:271531"
            end
        end
        GetDetailedItemLevelInfo = function(item)
            if item == "item:271531" then
                return 684
            end
        end
        C_Item = {
            GetItemInfo = function(item)
                if item == "item:271531" then
                    return "Chest", nil, nil, 600
                end
            end,
            GetItemIDForItemInfo = function()
                return 271531
            end,
        }
        local Equipment = Load()
        local scan = Equipment.GetSlotScan(1)
        assert.equals("ready", scan.status)
        assert.equals(684, scan.itemLevel)
    end)

    it("prefers the equipped location item level over the link-based detailed level", function()
        GetInventoryItemLink = function(_, slot)
            if slot == 2 then
                return "item:158075"
            end
        end
        ItemLocation = {
            CreateFromEquipmentSlot = function(_, slot)
                return { slot = slot }
            end,
        }
        GetDetailedItemLevelInfo = function()
            return 207
        end
        C_Item = {
            GetItemInfo = function(item)
                if item == "item:158075" then
                    return "Heart of Azeroth", nil, nil, 207, nil, nil, nil, nil, "INVTYPE_NECK"
                end
            end,
            GetItemIDForItemInfo = function()
                return 158075
            end,
            GetCurrentItemLevel = function(location)
                if location and location.slot == 2 then
                    return 35
                end
            end,
        }
        local Equipment = Load()
        local scan = Equipment.GetSlotScan(2)
        assert.equals("ready", scan.status)
        assert.equals(35, scan.itemLevel)
    end)

    it("returns the equipped average item level", function()
        GetAverageItemLevel = function()
            return 700.4, 689.2, 650
        end
        local Equipment = Load()
        assert.equals(689.2, Equipment.GetAverageItemLevel())
    end)

    it("does not inspect a secret average item level", function()
        issecretvalue = function()
            return true
        end
        GetAverageItemLevel = function()
            return 700, 689
        end
        local Equipment = Load()
        assert.is_nil(Equipment.GetAverageItemLevel())
    end)

    it("marks uncached items pending instead of empty", function()
        GetInventoryItemID = function()
            return 271531
        end
        C_Item = {
            GetItemInfo = function()
                return nil
            end,
        }
        local Equipment = Load()
        local scan = Equipment.GetSlotScan(1)
        assert.equals("pending", scan.status)
        assert.equals(271531, scan.itemID)
        assert.is_nil(scan.setID)
    end)

    it("maps a bag item to the inventory slots it can fill", function()
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag == 0 then
                    return 1
                end
                return 0
            end,
            GetContainerItemLink = function(bag, slot)
                if bag == 0 and slot == 1 then
                    return "item:12345"
                end
            end,
            GetContainerItemID = function()
                return 12345
            end,
        }
        C_Item = {
            GetItemInfo = function(item)
                if item == "item:12345" then
                    return "Helm", nil, nil, 700, nil, nil, nil, nil, "INVTYPE_HEAD"
                end
            end,
            GetItemIDForItemInfo = function()
                return 12345
            end,
        }
        GetDetailedItemLevelInfo = function(item)
            if item == "item:12345" then
                return 710
            end
        end
        local Equipment = Load()
        local scans = Equipment.GetBagScans()
        assert.equals(1, #scans)
        assert.equals("ready", scans[1].status)
        assert.equals(12345, scans[1].itemID)
        assert.equals(710, scans[1].itemLevel)
        assert.same({ 1 }, scans[1].slots)
    end)

    it("prefers a bag item's location item level over the link-based detailed level", function()
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag == 0 then
                    return 1
                end
                return 0
            end,
            GetContainerItemLink = function(bag, slot)
                if bag == 0 and slot == 1 then
                    return "item:12345"
                end
            end,
            GetContainerItemID = function()
                return 12345
            end,
        }
        ItemLocation = {
            CreateFromBagAndSlot = function(_, bag, slot)
                return { bag = bag, slot = slot }
            end,
        }
        GetDetailedItemLevelInfo = function()
            return 710
        end
        C_Item = {
            GetItemInfo = function(item)
                if item == "item:12345" then
                    return "Helm", nil, nil, 700, nil, nil, nil, nil, "INVTYPE_HEAD"
                end
            end,
            GetItemIDForItemInfo = function()
                return 12345
            end,
            GetCurrentItemLevel = function(location)
                if location and location.bag == 0 and location.slot == 1 then
                    return 35
                end
            end,
        }
        local Equipment = Load()
        local scans = Equipment.GetBagScans()
        assert.equals(1, #scans)
        assert.equals(35, scans[1].itemLevel)
    end)

    it("does not inspect secret inventory values", function()
        issecretvalue = function(value)
            return value == "secret-link"
        end
        GetInventoryItemLink = function()
            return "secret-link"
        end
        local Equipment = Load()
        local scan = Equipment.GetSlotScan(1)
        assert.equals("secret", scan.status)
        assert.is_nil(scan.setID)
    end)

    it("returns the equipped item link for a slot", function()
        GetInventoryItemLink = function(unit, slot)
            if unit == "player" and slot == 1 then
                return "|cffffffff|Hitem:11|h[Helm]|h|r"
            end
        end
        local Equipment = Load()
        assert.equals("|cffffffff|Hitem:11|h[Helm]|h|r", Equipment.GetSlotLink(1))
        assert.is_nil(Equipment.GetSlotLink(2))
    end)

    it("returns the inventory slot label from the client global", function()
        _G.HEADSLOT = "Head"
        local Equipment = Load()
        assert.equals("Head", Equipment.GetSlotName(1))
        assert.is_nil(Equipment.GetSlotName(99))
    end)

    it("returns the Mythic+ season when the client has one", function()
        C_MythicPlus = {
            GetCurrentSeason = function()
                return 18
            end,
        }
        local Equipment = Load()
        assert.equals(18, Equipment.GetCurrentSeasonID())
    end)

    it("requests map info instead of inventing a season when none is ready", function()
        local requested = 0
        C_MythicPlus = {
            GetCurrentSeason = function()
                return -1
            end,
            RequestMapInfo = function()
                requested = requested + 1
            end,
        }
        local Equipment = Load()
        assert.is_nil(Equipment.GetCurrentSeasonID())
        assert.equals(1, requested)
        Equipment.GetCurrentSeasonID()
        assert.equals(1, requested)
    end)

    it("returns cached item quality and quality hex", function()
        ITEM_QUALITY_COLORS = { [1] = { hex = "|cff1eff00" } }
        C_Item = {
            GetItemInfo = function()
                return "Helm", nil, 1, 700
            end,
            GetItemIDForItemInfo = function()
                return 11
            end,
        }
        local Equipment = Load()
        local info, status = Equipment.GetItemInfo("item:11")
        assert.equals("ready", status)
        assert.equals("Helm", info.name)
        assert.equals(1, info.quality)
        assert.equals("|cff1eff00", Equipment.GetItemQualityHex(1))
        assert.is_nil(Equipment.GetItemQualityHex(2))
    end)
end)
