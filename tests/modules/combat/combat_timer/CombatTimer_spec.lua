local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("CombatTimer", function()
    local ns, CombatTimer, Combat, Timer

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        CombatTimer = ns.Modules.Get("CombatTimer")
        Combat = ns.Api.Combat
        Timer = ns.Api.Timer
        CombatTimer:ListenForCombat()
    end)

    it("is registered with saved settings", function()
        assert.is_false(CombatTimer == nil)
        assert.equals("table", type(CombatTimer.db))
        assert.is_false(CombatTimer:IsEnabled())
    end)

    describe("enabled", function()
        it("toggles and notifies the UI hook", function()
            local seen = {}
            function CombatTimer:OnEnabledChanged()
                table.insert(seen, self:IsEnabled())
            end
            CombatTimer:SetEnabled(true)
            CombatTimer:SetEnabled(true)
            CombatTimer:SetEnabled(false)
            assert.same({ true, false }, seen)
            assert.is_false(CombatTimer:IsEnabled())
        end)
    end)

    describe("position", function()
        it("stores a valid anchor", function()
            CombatTimer:SetPosition({ point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -20 })
            local position = CombatTimer:GetPosition()
            assert.equals("TOPLEFT", position.point)
            assert.equals("TOPLEFT", position.relativePoint)
            assert.equals(10, position.x)
            assert.equals(-20, position.y)
        end)

        it("rejects a bad anchor", function()
            assert.is_false(pcall(CombatTimer.SetPosition, CombatTimer, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
            }))
        end)
    end)

    describe("scale", function()
        it("is 100% by default", function()
            AssertNear(1, CombatTimer:GetScale())
        end)

        it("is saved and snapped to the step", function()
            CombatTimer:SetScale(1.22)
            AssertNear(1.2, CombatTimer:GetScale())
            AssertNear(1.2, CombatTimer.db.scale)
        end)

        it("clamps to the allowed range", function()
            CombatTimer:SetScale(0.1)
            AssertNear(CombatTimer.SCALE_MIN, CombatTimer:GetScale())
            CombatTimer:SetScale(3)
            AssertNear(CombatTimer.SCALE_MAX, CombatTimer:GetScale())
        end)

        it("rejects non-numbers", function()
            assert.is_false(pcall(CombatTimer.SetScale, CombatTimer, "big"))
            AssertNear(1, CombatTimer:GetScale())
        end)
    end)

    describe("combat", function()
        it("starts at zero and not in combat", function()
            assert.is_false(CombatTimer:IsInCombat())
            assert.equals(0, CombatTimer:GetElapsed())
        end)

        it("tracks elapsed time while in combat", function()
            Timer.now = 100
            Combat.FireEnter()
            assert.is_true(CombatTimer:IsInCombat())
            assert.equals(0, CombatTimer:GetElapsed())

            Timer.now = 165
            assert.equals(65, CombatTimer:GetElapsed())
        end)

        it("clears live elapsed when leaving combat but keeps the last duration for display", function()
            Timer.now = 10
            Combat.FireEnter()
            Timer.now = 40
            Combat.FireLeave()
            assert.is_false(CombatTimer:IsInCombat())
            assert.equals(0, CombatTimer:GetElapsed())
            assert.equals(30, CombatTimer:GetDisplayElapsed())
        end)

        it("notifies the UI hook on enter and leave", function()
            local events = {}
            function CombatTimer:OnCombatChanged()
                table.insert(events, self:IsInCombat())
            end
            Combat.FireEnter()
            Combat.FireLeave()
            assert.same({ true, false }, events)
        end)

        it("adopts an in-progress fight when the listener starts", function()
            ns = Loader.Load()
            ns.Modules.Start(ns.Database.Load(nil))
            CombatTimer = ns.Modules.Get("CombatTimer")
            Combat = ns.Api.Combat
            Timer = ns.Api.Timer
            Combat.inCombat = true
            Timer.now = 50
            CombatTimer:ListenForCombat()
            assert.is_true(CombatTimer:IsInCombat())
            Timer.now = 80
            assert.equals(30, CombatTimer:GetElapsed())
        end)
    end)

    describe("format", function()
        it("defaults to mm:ss", function()
            assert.equals(CombatTimer.FORMAT_MMSS, CombatTimer:GetFormat())
        end)

        it("stores a known format", function()
            CombatTimer:SetFormat(CombatTimer.FORMAT_SECONDS)
            assert.equals(CombatTimer.FORMAT_SECONDS, CombatTimer:GetFormat())
        end)

        it("rejects an unknown format", function()
            assert.is_false(pcall(CombatTimer.SetFormat, CombatTimer, "HOURS"))
            assert.equals(CombatTimer.FORMAT_MMSS, CombatTimer:GetFormat())
        end)
    end)

    describe("FormatElapsed", function()
        it("formats minutes and seconds as MM:SS", function()
            CombatTimer:SetFormat(CombatTimer.FORMAT_MMSS)
            assert.equals("00:00", CombatTimer:FormatElapsed(0))
            assert.equals("00:05", CombatTimer:FormatElapsed(5.9))
            assert.equals("01:02", CombatTimer:FormatElapsed(62))
            assert.equals("12:34", CombatTimer:FormatElapsed(754))
        end)

        it("keeps counting minutes past one hour", function()
            CombatTimer:SetFormat(CombatTimer.FORMAT_MMSS)
            assert.equals("60:00", CombatTimer:FormatElapsed(3600))
            assert.equals("62:03", CombatTimer:FormatElapsed(3723))
        end)

        it("formats whole seconds when that format is selected", function()
            CombatTimer:SetFormat(CombatTimer.FORMAT_SECONDS)
            assert.equals("0 s", CombatTimer:FormatElapsed(0))
            assert.equals("5 s", CombatTimer:FormatElapsed(5.9))
            assert.equals("120 s", CombatTimer:FormatElapsed(120))
            assert.equals("3723 s", CombatTimer:FormatElapsed(3723))
        end)

        it("floors fractional seconds and clamps negatives", function()
            CombatTimer:SetFormat(CombatTimer.FORMAT_MMSS)
            assert.equals("00:00", CombatTimer:FormatElapsed(-3))
            assert.equals("00:01", CombatTimer:FormatElapsed(1.999))
            CombatTimer:SetFormat(CombatTimer.FORMAT_SECONDS)
            assert.equals("0 s", CombatTimer:FormatElapsed(-3))
            assert.equals("1 s", CombatTimer:FormatElapsed(1.999))
        end)
    end)

    it("exposes a combat monitoring panel group", function()
        assert.equals("table", type(ns.PanelGroups.COMBAT))
        assert.equals(1, ns.PanelGroups.COMBAT.order)
    end)
end)
