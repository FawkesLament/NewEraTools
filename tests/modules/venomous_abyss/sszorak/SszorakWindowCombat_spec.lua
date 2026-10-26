local Harness = require("helpers.sszorak")

local ALTAR_INSTANCE_ID = 3004
local ALTAR_SUBZONE_EN = "Altar of the Six Winds"
local ALTAR_SUBZONE_ZH = "六风祭坛"

describe("Sszorak map window visibility", function()
    local ns, Sszorak, Window, Combat, Instance
    local frames

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
        function frame:GetWidth()
            return 10
        end
        function frame:SetWindowPosition() end
        function frame:GetFrameLevel()
            return 1
        end
        frame.closeButton = {
            SetShown = function() end,
        }
        table.insert(frames, frame)
        return frame
    end

    local function EnterAltar(subZone)
        Instance.info.instanceID = ALTAR_INSTANCE_ID
        Instance.info.instanceType = "raid"
        Instance.subZoneText = subZone or ALTAR_SUBZONE_EN
    end

    local function LeaveAltar()
        Instance.subZoneText = "The Venomous Abyss"
    end

    before_each(function()
        frames = {}
        ns, Sszorak = Harness.Start()
        Combat = ns.Api.Combat
        Instance = ns.Api.Instance
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
        ns.Modules.Internals("Sszorak").Map = {
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
        Window = ns.Modules.Internals("Sszorak").Window
        Sszorak:ListenForEncounter()
        Sszorak.OnEncounterChanged = function()
            Window.DismissPreview()
            Window.Update()
        end
        Window.ListenForCombatDeferral()
        Sszorak:SetMapEnabled(true)
    end)

    it("shows the map at the English or Chinese altar and hides it elsewhere", function()
        EnterAltar(ALTAR_SUBZONE_EN)
        Window.Update()
        assert.is_true(frames[1]:IsShown())

        LeaveAltar()
        Instance.FireZoneChangedIndoors()
        assert.is_false(frames[1]:IsShown())

        EnterAltar(ALTAR_SUBZONE_ZH)
        Instance.FireZoneChangedIndoors()
        assert.is_true(frames[1]:IsShown())

        Instance.info.instanceID = 0
        Window.Update()
        assert.is_false(frames[1]:IsShown())
    end)

    it("stays hidden at the altar when the feature is off, unless preview is open", function()
        Sszorak:SetMapEnabled(false)
        EnterAltar()
        Window.Update()
        assert.equals(0, #frames)

        Window.StartPreview()
        assert.is_true(frames[1]:IsShown())
    end)

    it("defers Show until combat ends when the altar is entered during lockdown", function()
        Combat.inCombat = true
        EnterAltar()
        Instance.FireZoneChangedIndoors()
        assert.equals(0, #frames)

        Combat.FireLeave()
        assert.equals(1, #frames)
        assert.is_true(frames[1]:IsShown())
    end)

    it("defers Hide until combat ends when the altar is left during lockdown", function()
        EnterAltar()
        Window.Update()
        assert.is_true(frames[1]:IsShown())

        Combat.inCombat = true
        LeaveAltar()
        Instance.FireZoneChangedIndoors()
        assert.is_true(frames[1]:IsShown())

        Combat.FireLeave()
        assert.is_false(frames[1]:IsShown())
    end)

    it("does not change visibility when the pull starts or ends at the altar", function()
        EnterAltar()
        Window.Update()
        assert.is_true(frames[1]:IsShown())

        Combat.inCombat = true
        ns.Api.Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
        assert.is_true(frames[1]:IsShown())

        ns.Api.Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
        assert.is_true(frames[1]:IsShown())
    end)
end)
