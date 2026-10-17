local Harness = require("helpers.sszorak")

describe("Sszorak map window during combat lockdown", function()
    local ns, Sszorak, Window, Combat, Instance
    local frames
    local shields
    local originalCreateFrame

    local function MakeWindow()
        local frame = {
            shown = false,
            protected = true,
            raises = 0,
        }
        function frame:Show()
            if Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Frame:Show()", 2)
            end
            self.shown = true
        end
        function frame:Hide()
            if Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Frame:Hide()", 2)
            end
            self.shown = false
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:IsProtected()
            return self.protected
        end
        function frame:Raise()
            if Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Frame:Raise()", 2)
            end
            self.raises = self.raises + 1
        end
        function frame:SetSize() end
        function frame:SetAlpha(alpha)
            self.alpha = alpha
        end
        function frame:GetFrameLevel()
            return 1
        end
        frame.alpha = 1
        frame.closeButton = {
            SetShown = function() end,
        }
        table.insert(frames, frame)
        return frame
    end

    before_each(function()
        frames = {}
        shields = {}
        ns, Sszorak = Harness.Start()
        Combat = ns.Api.Combat
        Instance = ns.Api.Instance
        originalCreateFrame = CreateFrame
        CreateFrame = function()
            local shield = { shown = false }
            function shield:SetAllPoints() end
            function shield:EnableMouse() end
            function shield:SetFrameLevel() end
            function shield:Hide()
                self.shown = false
            end
            function shield:SetShown(shown)
                self.shown = shown and true or false
            end
            table.insert(shields, shield)
            return shield
        end
        ns.FloatingWindow = {
            Create = function()
                return MakeWindow()
            end,
        }
        ns.Layout = {
            Stack = function()
                return {
                    AddRow = function()
                        return {}
                    end,
                    GetHeight = function()
                        return 10
                    end,
                }
            end,
        }
        ns.LayoutEditor = {
            Register = function() end,
        }
        ns.SszorakMap = {
            GetArenaRowHeight = function()
                return 10
            end,
            CreateArenaRow = function()
                return { width = 10 }
            end,
            LayoutArenaRow = function() end,
            SetEdgeMacroClicksEnabled = function()
                return true
            end,
            SetEdgeClickTrackingArmed = function() end,
        }
        assert(loadfile("modules/venomous_abyss/sszorak/ui/Window.lua"))("NewEraTools", ns)
        Window = ns.SszorakWindow
        Sszorak:ListenForEncounter()
        Sszorak.OnEncounterChanged = function()
            Window.Update()
        end
        Window.ListenForCombatDeferral()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("fades the map in when the pull starts and out when the pull ends", function()
        Instance.info.instanceType = "raid"
        Window.Update()
        assert.is_true(frames[1]:IsShown())
        assert.equals(0, frames[1].alpha)
        assert.is_true(shields[1].shown)

        Combat.inCombat = true
        ns.Api.Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
        assert.is_true(frames[1]:IsShown())
        assert.equals(1, frames[1].alpha)
        assert.is_false(shields[1].shown)
        assert.equals(0, frames[1].raises)

        ns.Api.Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
        assert.equals(0, frames[1].alpha)
        assert.is_true(shields[1].shown)
    end)

    it("defers Show until combat ends when the pull starts with the map still closed", function()
        Combat.inCombat = true
        ns.Api.Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
        assert.equals(0, #frames)

        Combat.FireLeave()
        assert.equals(1, #frames)
        assert.is_true(frames[1]:IsShown())
        assert.equals(1, frames[1].alpha)
    end)
end)
