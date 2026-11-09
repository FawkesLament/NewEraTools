describe("Equipment production", function()
    local saved = {}

    local function SaveGlobals()
        saved.GetInventorySlotInfo = GetInventorySlotInfo
        saved.GetInventoryItemLink = GetInventoryItemLink
        saved.GetInventoryItemID = GetInventoryItemID
        saved.C_Item = C_Item
        saved.C_MythicPlus = C_MythicPlus
        saved.issecretvalue = issecretvalue
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
        C_MythicPlus = nil
        issecretvalue = nil
    end)

    after_each(function()
        GetInventorySlotInfo = saved.GetInventorySlotInfo
        GetInventoryItemLink = saved.GetInventoryItemLink
        GetInventoryItemID = saved.GetInventoryItemID
        C_Item = saved.C_Item
        C_MythicPlus = saved.C_MythicPlus
        issecretvalue = saved.issecretvalue
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
                    return "Chest",
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        nil,
                        11,
                        2057
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
        assert.equals(2057, scan.setID)
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
end)
