local Loader = require("helpers.loader")

local CURRENT_SET = 2057
local OTHER_SET = 9999
local OLD_SET = 1901
local CURRENT_RAID = 1001
local CURRENT_DUNGEON = 2001
local OLD_RAID = 9001

describe("tier-set detection", function()
    local ns, Internals, Player, Equipment, Instance, GearAlert, Timer

    local function Slot(status, setID, itemID)
        return { status = status, setID = setID, itemID = itemID }
    end

    local function Scan(equippedSet, count, extraSlots)
        local slots = {}
        for index = 1, 5 do
            if index <= count then
                slots[index] = Slot("ready", equippedSet, 1000 + index)
            else
                slots[index] = Slot("empty")
            end
        end
        if extraSlots then
            for index, slot in pairs(extraSlots) do
                slots[index] = slot
            end
        end
        return {
            seasonID = 18,
            classFile = "DRUID",
            slots = slots,
        }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Internals = ns.Modules.Internals("GearAlert")
        Player = ns.Api.Player
        Equipment = ns.Api.Equipment
        Instance = ns.Api.Instance
        GearAlert = ns.Modules.Get("GearAlert")
        Timer = ns.Api.Timer
        Player.SetContextForTests({ classFile = "DRUID", specializationId = 105, role = "HEALER" })
        Equipment.seasonID = 18
        Equipment.ClearSlotsForTests()
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

    local function MissingSetReadyToAlert()
        Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
        Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
        Equipment.SetEquippedSetForTests(CURRENT_SET, 3)
        local seen
        GearAlert:SetFindingListener(function(finding)
            seen = finding
        end)
        GearAlert:StartMonitoring()
        Instance.FireEnteringWorld()
        Timer.Advance(GearAlert.SCAN_DELAY)
        return seen
    end

    describe("Evaluate", function()
        it("counts zero current-season pieces as a known empty set", function()
            local state = Internals.Evaluate(Scan(CURRENT_SET, 0))
            assert.equals("ok", state.status)
            assert.equals(18, state.seasonID)
            assert.equals(0, state.equipped)
            assert.equals(4, state.required)
            assert.is_false(state.complete)
        end)

        it("does not combine unrelated set pieces", function()
            local scan = Scan(CURRENT_SET, 2)
            scan.slots[3] = Slot("ready", OTHER_SET, 2001)
            scan.slots[4] = Slot("ready", OTHER_SET, 2002)
            local state = Internals.Evaluate(scan)
            assert.equals(2, state.equipped)
            assert.same({ CURRENT_SET }, state.setIDs)
        end)

        it("does not count old-season tier pieces toward the current season", function()
            local state = Internals.Evaluate(Scan(OLD_SET, 4))
            assert.equals("ok", state.status)
            assert.equals(0, state.equipped)
            assert.is_false(state.complete)
        end)

        it("does not treat unknown item data as a missing piece", function()
            local scan = Scan(CURRENT_SET, 3)
            scan.slots[4] = Slot("pending", nil, 4001)
            local state = Internals.Evaluate(scan)
            assert.equals("unknown", state.status)
            assert.is_nil(state.equipped)
        end)

        it("does not treat an unsupported season as a missing piece", function()
            local scan = Scan(CURRENT_SET, 3)
            scan.seasonID = 99
            local state = Internals.Evaluate(scan)
            assert.equals("unsupported", state.status)
            assert.is_nil(state.equipped)
        end)
    end)

    describe("history and CheckMissing", function()
        it("records four pieces and keeps that history after later equipment changes", function()
            local history = {}
            Internals.RecordHistory(history, Internals.Evaluate(Scan(CURRENT_SET, 4)))
            assert.is_true(history[18].hadFourPiece)
            Internals.RecordHistory(history, Internals.Evaluate(Scan(CURRENT_SET, 2)))
            assert.is_true(history[18].hadFourPiece)
        end)

        it("reports a missing set only after four pieces were previously confirmed", function()
            local history = {}
            local nowThree = Internals.Evaluate(Scan(CURRENT_SET, 3))
            assert.is_nil(Internals.CheckMissing(history, nowThree))

            Internals.RecordHistory(history, Internals.Evaluate(Scan(CURRENT_SET, 4)))
            local finding = Internals.CheckMissing(history, nowThree)
            assert.same({ type = "MISSING_TIER_SET", equipped = 3, required = 4 }, finding)
        end)

        it("clears the current finding when four pieces are equipped again", function()
            local history = { [18] = { hadFourPiece = true } }
            assert.is_nil(Internals.CheckMissing(history, Internals.Evaluate(Scan(CURRENT_SET, 4))))
        end)

        it("does not warn on unknown item data or an unsupported season, even with history", function()
            local history = { [18] = { hadFourPiece = true }, [99] = { hadFourPiece = true } }
            local pending = Scan(CURRENT_SET, 3)
            pending.slots[4] = Slot("pending", nil, 4001)
            assert.is_nil(Internals.CheckMissing(history, Internals.Evaluate(pending)))

            local unsupported = Scan(CURRENT_SET, 3)
            unsupported.seasonID = 99
            assert.is_nil(Internals.CheckMissing(history, Internals.Evaluate(unsupported)))
        end)

        it("does not mutate history inside CheckMissing", function()
            local history = { [18] = { hadFourPiece = true } }
            Internals.CheckMissing(history, Internals.Evaluate(Scan(CURRENT_SET, 3)))
            assert.is_true(history[18].hadFourPiece)
            assert.equals(1, (function()
                local count = 0
                for _ in pairs(history) do
                    count = count + 1
                end
                return count
            end)())
        end)
    end)

    describe("character history", function()
        it("stores four-piece history per character and keeps it across specializations", function()
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            local state = GearAlert:GetCurrentState()
            Internals.RecordHistory(GearAlert:GetTierSetHistory(), state)
            assert.is_true(GearAlert:GetTierSetHistory()[18].hadFourPiece)

            Player.SetContextForTests({ specializationId = 102, role = "DAMAGER" })
            Equipment.SetEquippedSetForTests(CURRENT_SET, 1)
            assert.is_true(GearAlert:GetTierSetHistory()[18].hadFourPiece)
            assert.same({
                type = "MISSING_TIER_SET",
                equipped = 1,
                required = 4,
            }, Internals.CheckMissing(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState()))
        end)

        it("does not share history between characters", function()
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
            Player.guid = "Player-1-00000002"
            Player.fullName = "Other-TestRealm"
            assert.is_nil(GearAlert:GetTierSetHistory()[18])
        end)
    end)

    describe("equipment monitoring", function()
        it("coalesces duplicate equipment-change events into one scan", function()
            GearAlert:StartMonitoring()
            Equipment.getSlotScanCalls = 0
            Equipment.FireChanged()
            Equipment.FireChanged()
            assert.equals(0, Equipment.getSlotScanCalls)
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.equals(#Equipment.armorSlots, Equipment.getSlotScanCalls)
        end)

        it("keeps learning history while notifications are disabled", function()
            GearAlert:SetFourPieceCheckEnabled(false)
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            GearAlert:StartMonitoring()
            Instance.FireEnteringWorld()
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.is_true(GearAlert:GetTierSetHistory()[18].hadFourPiece)
        end)

        it("alerts in a current-expansion raid when four pieces were previously confirmed", function()
            EnterRaid()
            assert.same({ type = "MISSING_TIER_SET", equipped = 3, required = 4 }, MissingSetReadyToAlert())
        end)

        it("alerts in a current-expansion Mythic dungeon", function()
            EnterDungeon()
            assert.same({ type = "MISSING_TIER_SET", equipped = 3, required = 4 }, MissingSetReadyToAlert())
        end)

        it("does not pop the warning outside a current-expansion raid or Mythic dungeon", function()
            assert.is_nil(MissingSetReadyToAlert())

            EnterRaid(OLD_RAID)
            assert.is_nil(MissingSetReadyToAlert())

            EnterDungeon(CURRENT_DUNGEON, Instance.DIFFICULTY_HEROIC_RAID)
            assert.is_nil(MissingSetReadyToAlert())
        end)

        it("does not alert on an equipment swap after login", function()
            local seen = false
            GearAlert:SetFindingListener(function()
                seen = true
            end)
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
            Equipment.SetEquippedSetForTests(CURRENT_SET, 3)
            GearAlert:StartMonitoring()
            Equipment.FireChanged()
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.is_false(seen)
        end)

        it("survives a reload with the same saved variables", function()
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            Internals.RecordHistory(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
            assert.is_true(GearAlert:GetTierSetHistory()[18].hadFourPiece)
            local saved = {
                modules = {
                    GearAlert = { characters = ns.Util.DeepCopy(GearAlert.db.characters) },
                },
            }

            ns = Loader.Load()
            Player = ns.Api.Player
            Equipment = ns.Api.Equipment
            Player.SetContextForTests({ classFile = "DRUID" })
            Equipment.seasonID = 18
            Equipment.SetEquippedSetForTests(CURRENT_SET, 3)
            ns.Modules.Start(ns.Database.Load(saved))
            GearAlert = ns.Modules.Get("GearAlert")
            Internals = ns.Modules.Internals("GearAlert")
            local finding = Internals.CheckMissing(GearAlert:GetTierSetHistory(), GearAlert:GetCurrentState())
            assert.same({ type = "MISSING_TIER_SET", equipped = 3, required = 4 }, finding)
        end)

        it("ignores a stale item-info retry after a newer equipment change", function()
            local pendingSlot = Equipment.armorSlots[1]
            Equipment.SetSlotForTests(pendingSlot, { status = "pending", itemID = 11 })
            GearAlert:StartMonitoring()
            Equipment.FireChanged()
            Timer.Advance(GearAlert.SCAN_DELAY)
            Equipment.SetEquippedSetForTests(CURRENT_SET, 4)
            Equipment.FireChanged()
            Equipment.FireItemInfoReceived(11, true)
            Timer.Advance(0.4)
            assert.is_nil(GearAlert:GetTierSetHistory()[18])
            Timer.Advance(GearAlert.SCAN_DELAY)
            assert.is_true(GearAlert:GetTierSetHistory()[18].hadFourPiece)
        end)
    end)
end)
