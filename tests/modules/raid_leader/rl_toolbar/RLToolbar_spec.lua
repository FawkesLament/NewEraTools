local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("RLToolbar", function()
    local ns, RLToolbar, Combat, Group

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        RLToolbar = ns.Modules.Get("RLToolbar")
        Combat = ns.Api.Combat
        Group = ns.Api.Group
        RLToolbar:ListenForVisibility()
    end)

    it("starts disabled with the factory anchor", function()
        assert.is_false(RLToolbar:IsEnabled())
        assert.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 200 }, RLToolbar:GetPosition())
        assert.same(RLToolbar:GetPosition(), RLToolbar:GetDefaultPosition())
        assert.is_false(RLToolbar:GetPosition() == RLToolbar:GetDefaultPosition())
    end)

    describe("visibility", function()
        it("is hidden until the feature is on, the player leads, and combat has not started", function()
            assert.is_false(RLToolbar:ShouldShow())
            RLToolbar:SetEnabled(true)
            assert.is_false(RLToolbar:ShouldShow())
            Group.isRaidLeader = true
            assert.is_true(RLToolbar:ShouldShow())
            Combat.inCombat = true
            assert.is_false(RLToolbar:ShouldShow())
        end)

        it("preview skips leadership but still hides in combat or when disabled", function()
            RLToolbar:SetEnabled(true)
            assert.is_true(RLToolbar:ShouldShow(true))
            Combat.inCombat = true
            assert.is_false(RLToolbar:ShouldShow(true))
            Combat.inCombat = false
            RLToolbar:SetEnabled(false)
            assert.is_false(RLToolbar:ShouldShow(true))
        end)

        it("notifies when enable, leadership, or combat change", function()
            local seen = {}
            function RLToolbar:OnVisibilityChanged()
                table.insert(seen, self:ShouldShow())
            end
            RLToolbar:SetEnabled(true)
            Group.isRaidLeader = true
            Group.FireChanged()
            Combat.FireEnter()
            Combat.FireLeave()
            RLToolbar:SetEnabled(true)
            RLToolbar:SetEnabled(false)
            assert.same({ false, true, false, true, false }, seen)
        end)
    end)

    describe("scale", function()
        it("is 100% by default", function()
            assert.equals(1, RLToolbar:GetScale())
        end)

        it("is saved and snapped to the step", function()
            RLToolbar:SetScale(1.22)
            AssertNear(1.2, RLToolbar:GetScale())
            AssertNear(1.2, RLToolbar.db.scale)
        end)

        it("clamps to the allowed range", function()
            RLToolbar:SetScale(0.1)
            assert.equals(RLToolbar.SCALE_MIN, RLToolbar:GetScale())
            RLToolbar:SetScale(3)
            assert.equals(RLToolbar.SCALE_MAX, RLToolbar:GetScale())
        end)

        it("rejects non-numbers", function()
            assert.is_false(pcall(RLToolbar.SetScale, RLToolbar, "big"))
            assert.equals(1, RLToolbar:GetScale())
        end)
    end)

    describe("optional countdown buttons", function()
        it("shows the 5s and 15s buttons by default", function()
            assert.is_true(RLToolbar:IsCountdown5Shown())
            assert.is_true(RLToolbar:IsCountdown15Shown())
            assert.is_true(RLToolbar:IsButtonShown("readyCheck"))
            assert.is_true(RLToolbar:IsButtonShown("countdown10"))
            assert.is_true(RLToolbar:IsButtonShown("cancelCountdown"))
        end)

        it("hides only the toggled countdown buttons", function()
            local seen = 0
            function RLToolbar:OnLayoutChanged()
                seen = seen + 1
            end
            RLToolbar:SetCountdown5Shown(false)
            RLToolbar:SetCountdown5Shown(false)
            RLToolbar:SetCountdown15Shown(false)
            assert.is_false(RLToolbar:IsButtonShown("countdown5"))
            assert.is_false(RLToolbar:IsButtonShown("countdown15"))
            assert.is_true(RLToolbar:IsButtonShown("readyCheck"))
            assert.is_true(RLToolbar:IsButtonShown("countdown10"))
            assert.is_true(RLToolbar:IsButtonShown("cancelCountdown"))
            assert.equals(2, seen)
        end)
    end)

    describe("position", function()
        it("stores a valid anchor", function()
            RLToolbar:SetPosition({ point = "TOP", relativePoint = "TOP", x = 12, y = -40 })
            local position = RLToolbar:GetPosition()
            assert.equals("TOP", position.point)
            assert.equals("TOP", position.relativePoint)
            assert.equals(12, position.x)
            assert.equals(-40, position.y)
        end)

        it("rejects a bad anchor", function()
            assert.is_false(pcall(RLToolbar.SetPosition, RLToolbar, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
            }))
        end)
    end)

    describe("actions", function()
        local function MakeLive()
            RLToolbar:SetEnabled(true)
            Group.isRaidLeader = true
        end

        it("does nothing while the toolbar is not live", function()
            local seen = {}
            function RLToolbar:OnAction(action)
                table.insert(seen, action)
            end
            RLToolbar:RunAction("readyCheck")
            assert.same({}, seen)
            assert.equals(0, Group.readyChecks)
        end)

        it("sends each raid command", function()
            local seen = {}
            function RLToolbar:OnAction(action)
                table.insert(seen, action)
            end
            MakeLive()
            for _, action in ipairs(RLToolbar.ACTIONS) do
                RLToolbar:RunAction(action)
            end
            assert.same({
                "readyCheck",
                "countdown5",
                "countdown10",
                "countdown15",
                "cancelCountdown",
            }, seen)
            assert.equals(1, Group.readyChecks)
            assert.same({ 5, 10, 15 }, Group.countdowns)
            assert.equals(1, Group.cancels)
        end)

        it("rejects an unknown action", function()
            MakeLive()
            assert.is_false(pcall(RLToolbar.RunAction, RLToolbar, "pull"))
        end)
    end)
end)
