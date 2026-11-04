local Loader = require("helpers.loader")

describe("CoiledAltar interrupt assignments", function()
    local ns, Module, Assignments

    local function Slot(slotType, value)
        return { type = slotType, value = value }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("CoiledAltar")
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
    end)

    local function EmptyChain()
        local chain = {}
        for index = 1, Assignments.SLOT_COUNT do
            chain[index] = Slot(Assignments.TYPE_EMPTY)
        end
        return chain
    end

    it("starts both chains with six empty slots", function()
        local saved = Module:GetInterruptAssignments()
        assert.equals(Assignments.SLOT_COUNT, #saved.MELEE)
        assert.equals(Assignments.SLOT_COUNT, #saved.RANGED)
        for index = 1, Assignments.SLOT_COUNT do
            assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, index))
            assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.RANGED, index))
        end
    end)

    it("assigns a player by click-order without consuming them from later slots", function()
        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerA"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 3, "PlayerB"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 4, "PlayerA"))
        assert.is_true(Module:AssignInterruptPlayer(Assignments.RANGED, 2, "PlayerA"))

        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 1))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, 2))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerB-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 3))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 4))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot(Assignments.RANGED, 2))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.RANGED, 1))
    end)

    it("stores custom text without resolving it to a player", function()
        assert.is_true(Module:AssignInterruptText(Assignments.MELEE, 2, "点名近战"))
        local slot = Module:GetInterruptSlot(Assignments.MELEE, 2)
        assert.equals(Assignments.TYPE_TEXT, slot.type)
        assert.equals("点名近战", slot.value)
    end)

    it("replaces, switches type, and clears a slot without touching neighbors", function()
        Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerA")
        Module:AssignInterruptPlayer(Assignments.MELEE, 2, "PlayerB")
        assert.is_true(Module:AssignInterruptText(Assignments.MELEE, 1, "点名近战"))
        assert.same(Slot(Assignments.TYPE_TEXT, "点名近战"), Module:GetInterruptSlot(Assignments.MELEE, 1))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerB-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 2))

        assert.is_true(Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerC"))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerC-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 1))

        assert.is_true(Module:ClearInterruptAssignment(Assignments.MELEE, 1))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, 1))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerB-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 2))
    end)

    it("rejects empty names, empty text, and text longer than 12 characters", function()
        assert.is_false(Module:AssignInterruptPlayer(Assignments.MELEE, 1, "  "))
        assert.is_false(Module:AssignInterruptText(Assignments.MELEE, 1, "   "))
        assert.is_false(Module:AssignInterruptText(Assignments.MELEE, 1, "一二三四五六七八九十甲乙丙"))
        assert.is_true(Module:AssignInterruptText(Assignments.MELEE, 1, "一二三四五六七八九十甲乙"))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, 2))
        assert.equals("一二三四五六七八九十甲乙", Module:GetInterruptSlot(Assignments.MELEE, 1).value)
    end)

    it("does not wrap slot 6 into slot 1", function()
        Module:AssignInterruptPlayer(Assignments.MELEE, 6, "PlayerA")
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot(Assignments.MELEE, 6))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, 1))
        assert.is_nil(Module:GetInterruptSlot(Assignments.MELEE, 7))
        assert.is_false(Module:AssignInterruptPlayer(Assignments.MELEE, 7, "PlayerB"))
    end)

    it("repairs malformed saved data into two six-slot chains", function()
        local repaired = Assignments.SanitizeSaved({
            MELEE = {
                { type = "player", value = "Aric" },
                { type = "nope", value = "x" },
                { type = "text", value = "点名近战" },
            },
            RANGED = "bad",
            extra = true,
        })
        assert.equals(6, #repaired.MELEE)
        assert.equals(6, #repaired.RANGED)
        assert.same(Slot(Assignments.TYPE_PLAYER, "Aric-TestRealm"), repaired.MELEE[1])
        assert.same(Slot(Assignments.TYPE_EMPTY), repaired.MELEE[2])
        assert.same(Slot(Assignments.TYPE_TEXT, "点名近战"), repaired.MELEE[3])
        assert.is_nil(repaired.extra)
        for index = 1, 6 do
            assert.equals(Assignments.TYPE_EMPTY, repaired.RANGED[index].type)
        end
    end)

    it("restores player, text, empty, and repeated slots after a reload", function()
        Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerA")
        Module:AssignInterruptText(Assignments.MELEE, 2, "点名近战")
        Module:AssignInterruptPlayer(Assignments.MELEE, 3, "PlayerB")
        Module:AssignInterruptPlayer(Assignments.MELEE, 4, "PlayerA")
        Module:AssignInterruptPlayer(Assignments.RANGED, 6, "PlayerC")

        local snapshot = {
            schemaVersion = 10,
            modules = {
                CoiledAltar = {
                    nameplateHint = Module.db.nameplateHint,
                    assignments = Module.db.assignments,
                },
            },
        }

        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(snapshot))
        Module = ns.Modules.Get("CoiledAltar")

        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot("MELEE", 1))
        assert.same(Slot(Assignments.TYPE_TEXT, "点名近战"), Module:GetInterruptSlot("MELEE", 2))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerB-TestRealm"), Module:GetInterruptSlot("MELEE", 3))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerA-TestRealm"), Module:GetInterruptSlot("MELEE", 4))
        assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot("MELEE", 5))
        assert.same(Slot(Assignments.TYPE_PLAYER, "PlayerC-TestRealm"), Module:GetInterruptSlot("RANGED", 6))
        assert.is_true(Module.db.nameplateHint.enabled == false)
    end)

    it("clears every slot in both chains at once", function()
        Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerA")
        Module:AssignInterruptText(Assignments.MELEE, 6, "点名近战")
        Module:AssignInterruptPlayer(Assignments.RANGED, 3, "PlayerB")
        assert.is_true(Module:HasInterruptAssignments())
        assert.is_true(Module:ClearAllInterruptAssignments())
        assert.is_false(Module:HasInterruptAssignments())
        assert.is_false(Module:ClearAllInterruptAssignments())
        for index = 1, Assignments.SLOT_COUNT do
            assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.MELEE, index))
            assert.same(Slot(Assignments.TYPE_EMPTY), Module:GetInterruptSlot(Assignments.RANGED, index))
        end
    end)

    it("keeps nameplate hint settings independent of assignments", function()
        Module:SetNameplateHintEnabled(true)
        Module:AssignInterruptPlayer(Assignments.MELEE, 1, "PlayerA")
        assert.is_true(Module:IsNameplateHintEnabled())
        Module:ClearInterruptAssignment(Assignments.MELEE, 1)
        assert.is_true(Module:IsNameplateHintEnabled())
        assert.same(EmptyChain(), Module:GetInterruptAssignments().MELEE)
    end)
end)
