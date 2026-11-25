local Loader = require("helpers.loader")

local CURRENT_RAID = 1001
local CURRENT_DUNGEON = 2001
local OLD_RAID = 9001

describe("low-level gear detection", function()
    local ns, Internals, Equipment, Instance, GearAlert, Timer

    local ITEM_LINK = "|cffffffff|Hitem:11::::::::80:257::::::|h[Old Helm]|h|r"

    local function Slot(slot, status, itemLevel, itemID)
        return { slot = slot, status = status, itemLevel = itemLevel, itemID = itemID }
    end

    local function Bag(status, itemLevel, slots, itemID)
        return { status = status, itemLevel = itemLevel, slots = slots, itemID = itemID }
    end

    local function Scan(average, slots, bags)
        return {
            averageItemLevel = average,
            slots = slots or {},
            bags = bags or {},
        }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Internals = ns.Modules.Internals("GearAlert")
        Equipment = ns.Api.Equipment
        Instance = ns.Api.Instance
        GearAlert = ns.Modules.Get("GearAlert")
        Timer = ns.Api.Timer
        Equipment.ClearSlotsForTests()
        Equipment.ClearBagsForTests()
        Instance.currentRaidIds[CURRENT_RAID] = true
        Instance.currentDungeonIds[CURRENT_DUNGEON] = true
    end)

    local function EnterRaid(instanceID)
        Instance.info = {
            name = "Raid",
            instanceType = "raid",
            difficultyID = Instance.DIFFICULTY_MYTHIC_RAID,
            instanceID = instanceID or CURRENT_RAID,
        }
    end

    local function EnterDungeon(instanceID, difficultyID)
        Instance.info = {
            name = "Dungeon",
            instanceType = "party",
            difficultyID = difficultyID or Instance.DIFFICULTY_MYTHIC_DUNGEON,
            instanceID = instanceID or CURRENT_DUNGEON,
        }
    end

    local function LowLevelReadyToAlert()
        Equipment.averageItemLevel = 700
        Equipment.SetSlotForTests(1, { status = "ready", itemID = 11, itemLevel = 30, link = ITEM_LINK })
        Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 1 } })
        local seen
        GearAlert:SetFindingListener(function(finding)
            seen = finding
        end)
        GearAlert:StartMonitoring()
        Instance.FireEnteringWorld()
        Timer.Advance(GearAlert.SCAN_DELAY)
        return seen
    end

    describe("EvaluateLowLevel", function()
        it("reports a low-level item only when a higher-level bag item fills that slot", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 30),
                Slot(2, "ready", 100),
            }, {
                Bag("ready", 80, { 1 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(1, state.lowCount)
            assert.equals(30, state.itemLevel)
            assert.equals(100, state.averageItemLevel)
            assert.equals(30, state.threshold)
        end)

        it("does not report a low-level item with no bag replacement", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 30),
                Slot(2, "ready", 100),
            }))
            assert.equals("ok", state.status)
            assert.equals(0, state.lowCount)
            assert.is_nil(state.itemLevel)
        end)

        it("does not treat a high-level bag item for a different slot as a replacement", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 30),
            }, {
                Bag("ready", 80, { 2 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(0, state.lowCount)
        end)

        it("treats a bag ring as a replacement for either finger slot", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(11, "ready", 20),
                Slot(12, "ready", 100),
            }, {
                Bag("ready", 80, { 11, 12 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(1, state.lowCount)
            assert.equals(20, state.itemLevel)
        end)

        it("does not report an item just above 30% of average item level", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 31),
                Slot(2, "ready", 100),
            }, {
                Bag("ready", 80, { 1 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(0, state.lowCount)
            assert.is_nil(state.itemLevel)
        end)

        it("does not treat a bag item at the low-level cutoff as high-level", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 10),
            }, {
                Bag("ready", 30, { 1 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(0, state.lowCount)
        end)

        it("keeps every low slot and the lowest item level when several slots have replacements", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "ready", 200),
                Slot(2, "ready", 40),
                Slot(3, "ready", 80),
            }, {
                Bag("ready", 700, { 1 }),
                Bag("ready", 700, { 2 }),
                Bag("ready", 700, { 3 }),
            }))
            assert.equals(3, state.lowCount)
            assert.equals(40, state.itemLevel)
            assert.same({
                { itemLevel = 200, slot = 1 },
                { itemLevel = 40, slot = 2 },
                { itemLevel = 80, slot = 3 },
            }, state.items)
        end)

        it("does not treat unknown item data as a low-level item", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "pending", nil, 4001),
                Slot(2, "ready", 700),
            }))
            assert.equals("unknown", state.status)
            assert.is_nil(state.lowCount)
        end)

        it("still reports a confirmed low-level item when another equipped slot is pending", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "ready", 30),
                Slot(2, "pending", nil, 4001),
            }, {
                Bag("ready", 700, { 1 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(1, state.lowCount)
            assert.equals(30, state.itemLevel)
        end)

        it("does not invent a finding while a possible bag replacement is still loading", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "ready", 30),
            }, {
                Bag("pending", nil, {}, 4001),
            }))
            assert.equals("unknown", state.status)
            assert.is_nil(state.lowCount)
        end)

        it("still reports when a replacement is confirmed and another bag item is pending", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "ready", 30),
            }, {
                Bag("ready", 700, { 1 }),
                Bag("pending", nil, {}, 4001),
            }))
            assert.equals("ok", state.status)
            assert.equals(1, state.lowCount)
        end)

        it("does not invent a finding without an average item level", function()
            local state = Internals.EvaluateLowLevel(Scan(nil, {
                Slot(1, "ready", 30),
            }, {
                Bag("ready", 700, { 1 }),
            }))
            assert.equals("unknown", state.status)
        end)

        it("reports an empty slot when a higher-level bag item fills that slot", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "empty"),
                Slot(2, "ready", 100),
            }, {
                Bag("ready", 80, { 1 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(1, state.lowCount)
            assert.equals(0, state.itemLevel)
        end)

        it("does not report an empty slot with no bag replacement", function()
            local state = Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "empty"),
                Slot(2, "ready", 100),
            }))
            assert.equals("ok", state.status)
            assert.equals(0, state.lowCount)
            assert.is_nil(state.itemLevel)
        end)

        it("does not invent a finding while a possible bag replacement for an empty slot is still loading", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "empty"),
            }, {
                Bag("pending", nil, {}, 4001),
            }))
            assert.equals("unknown", state.status)
            assert.is_nil(state.lowCount)
        end)

        it("records an empty slot and a low-level equipped item together", function()
            local state = Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "empty"),
                Slot(2, "ready", 30),
            }, {
                Bag("ready", 700, { 1 }),
                Bag("ready", 700, { 2 }),
            }))
            assert.equals("ok", state.status)
            assert.equals(2, state.lowCount)
            assert.equals(0, state.itemLevel)
            assert.same({
                { itemLevel = 0, slot = 1 },
                { itemLevel = 30, slot = 2 },
            }, state.items)
        end)
    end)

    describe("CheckLowLevel", function()
        it("returns a payload for each low or empty slot that has a bag replacement", function()
            Equipment.SetSlotForTests(1, { link = ITEM_LINK })
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 30,
                    averageItemLevel = 100,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                    itemLink = ITEM_LINK,
                },
            }, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 30),
            }, {
                Bag("ready", 80, { 1 }),
            }))))
            assert.same({}, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 30),
            }))))
            assert.same({}, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "ready", 100),
            }, {
                Bag("ready", 80, { 1 }),
            }))))
            assert.same({}, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "pending", nil, 1),
            }))))
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 0,
                    averageItemLevel = 100,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                },
            }, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "empty"),
            }, {
                Bag("ready", 80, { 1 }),
            }))))
            assert.same({}, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(100, {
                Slot(1, "empty"),
            }))))
            Equipment.SetSlotForTests(2, { link = ITEM_LINK })
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 0,
                    averageItemLevel = 700,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                },
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 30,
                    averageItemLevel = 700,
                    slot = 2,
                    slotName = Equipment.GetSlotName(2),
                    itemLink = ITEM_LINK,
                },
            }, Internals.CheckLowLevel(Internals.EvaluateLowLevel(Scan(700, {
                Slot(1, "empty"),
                Slot(2, "ready", 30),
            }, {
                Bag("ready", 700, { 1 }),
                Bag("ready", 700, { 2 }),
            }))))
        end)
    end)

    describe("equipment monitoring", function()
        it("alerts in a current-expansion raid when a low-level item is equipped", function()
            EnterRaid()
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 30,
                    averageItemLevel = 700,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                    itemLink = ITEM_LINK,
                },
            }, LowLevelReadyToAlert())
        end)

        it("alerts in a current-expansion raid when a gear slot is empty", function()
            Equipment.averageItemLevel = 700
            Equipment.SetSlotForTests(1, { status = "empty" })
            Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 1 } })
            EnterRaid()
            local seen
            GearAlert:SetFindingListener(function(finding)
                seen = finding
            end)
            GearAlert:StartMonitoring()
            Instance.FireEnteringWorld()
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 0,
                    averageItemLevel = 700,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                },
            }, seen)
        end)

        it("alerts in a current-expansion Mythic dungeon", function()
            EnterDungeon()
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 30,
                    averageItemLevel = 700,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                    itemLink = ITEM_LINK,
                },
            }, LowLevelReadyToAlert())
        end)

        it("does not pop the warning outside a current-expansion raid or Mythic dungeon", function()
            assert.is_nil(LowLevelReadyToAlert())

            EnterRaid(OLD_RAID)
            assert.is_nil(LowLevelReadyToAlert())

            EnterDungeon(CURRENT_DUNGEON, Instance.DIFFICULTY_HEROIC_RAID)
            assert.is_nil(LowLevelReadyToAlert())
        end)

        it("does not alert when the low-level check is disabled", function()
            GearAlert:SetLowLevelCheckEnabled(false)
            EnterRaid()
            assert.is_nil(LowLevelReadyToAlert())
        end)

        it("does not alert when bags have no replacement for the low-level slot", function()
            Equipment.averageItemLevel = 700
            Equipment.SetSlotForTests(1, { status = "ready", itemID = 11, itemLevel = 30 })
            EnterRaid()
            local seen
            GearAlert:SetFindingListener(function(finding)
                seen = finding
            end)
            GearAlert:StartMonitoring()
            Instance.FireEnteringWorld()
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.is_nil(seen)
        end)

        it("alerts for a low-level item and a missing set together", function()
            Equipment.SetEquippedSetForTests(2057, 4)
            Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
            Equipment.SetEquippedSetForTests(2057, 3)
            Equipment.averageItemLevel = 700
            Equipment.SetSlotForTests(1, {
                status = "ready",
                itemID = 11,
                setID = 2057,
                itemLevel = 30,
                link = ITEM_LINK,
            })
            Equipment.SetBagItemForTests({ status = "ready", itemID = 22, itemLevel = 700, slots = { 1 } })
            EnterRaid()
            local seen
            GearAlert:SetFindingListener(function(finding)
                seen = finding
            end)
            GearAlert:StartMonitoring()
            Instance.FireEnteringWorld()
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.same({
                {
                    type = "LOW_LEVEL_ITEM",
                    itemLevel = 30,
                    averageItemLevel = 700,
                    slot = 1,
                    slotName = Equipment.GetSlotName(1),
                    itemLink = ITEM_LINK,
                },
                {
                    type = "MISSING_TIER_SET",
                    equipped = 3,
                    required = 4,
                    missingSlotNames = {
                        Equipment.GetSlotName(10),
                        Equipment.GetSlotName(7),
                    },
                },
            }, seen)
        end)
    end)
end)
