local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

local TOMB_INSTANCE_ID = 3004
local TOMB_SUBZONE_EN = "The Tomb of Ula'tek"
local TOMB_SUBZONE_ZH = "乌拉特克之墓"

describe("Ulatek tactical pad window", function()
    local ns, Ulatek, Window, Group, Instance
    local frames
    local registered
    local arenaCreates
    local lastCreateOptions

    local function MakeWindow()
        local frame = {
            shown = false,
            raises = 0,
        }
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:IsShown()
            return self.shown
        end
        function frame:Raise()
            self.raises = self.raises + 1
        end
        function frame:SetSize() end
        function frame:GetWidth()
            return 10
        end
        function frame:SetWindowPosition() end
        function frame:SetWindowScale(scale)
            self.scale = scale
        end
        frame.closeButton = {
            shown = true,
            SetShown = function(self, shown)
                self.shown = shown == true
            end,
            Hide = function(self)
                self.shown = false
            end,
        }
        table.insert(frames, frame)
        return frame
    end

    before_each(function()
        frames = {}
        registered = {}
        arenaCreates = 0
        lastCreateOptions = nil
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Ulatek = ns.Modules.Get("Ulatek")
        Group = ns.Api.Group
        Instance = ns.Api.Instance
        ns.FloatingWindow = {
            Create = function(options)
                lastCreateOptions = options
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
            Register = function(def)
                registered[def.id] = def
            end,
        }
        ns.Modules.Internals("Ulatek").Map = {
            GetArenaRowHeight = function()
                return 10
            end,
            CreateArenaRow = function(_, options)
                arenaCreates = arenaCreates + 1
                assert.is_nil(options.onCornerMarkerClick)
                assert.equals(24, options.markerSize)
                assert.is_true(options.showCalloutButtons)
                return { width = 10 }
            end,
            LayoutArenaRow = function() end,
            AttachWindowHint = function() end,
            SetTestTimer = function() end,
            SetCalloutMacroClicksEnabled = function()
                return true
            end,
        }
        assert(loadfile("modules/venomous_abyss/ulatek/ui/Window.lua"))("NewEraTools", ns)
        Window = ns.Modules.Internals("Ulatek").Window
        Group.isRaidLeader = true
    end)

    local function EnterTomb(subZone, difficultyID)
        Instance.info.instanceID = TOMB_INSTANCE_ID
        Instance.info.instanceType = "raid"
        Instance.info.difficultyID = difficultyID or Instance.DIFFICULTY_MYTHIC_RAID
        Instance.subZoneText = subZone or TOMB_SUBZONE_EN
    end

    local function LeaveTomb()
        Instance.subZoneText = "The Venomous Abyss"
    end

    it("opens a closable map with assigned markers when a commander starts the test", function()
        Window.StartPreview()
        assert.equals(1, #frames)
        assert.equals(1, arenaCreates)
        assert.is_true(frames[1]:IsShown())
        assert.is_true(frames[1].closeButton.shown)
        assert.is_true(lastCreateOptions.closable)
        assert.equals(1, lastCreateOptions.scale)
        assert(registered[Window.LAYOUT_ID], "layout element missing")
        assert.is_false(registered[Window.LAYOUT_ID].global)
        assert.equals(ns.L.ULATEK_SECTION_TACTICAL_PAD, registered[Window.LAYOUT_ID].label)
    end)

    it("does not open the pad for a raid member", function()
        Group.isRaidLeader = false
        Window.StartPreview()
        assert.equals(0, #frames)
    end)

    it("closes the pad from the window X", function()
        Window.StartPreview()
        lastCreateOptions.onClose()
        assert.is_false(frames[1]:IsShown())
    end)

    it("raises the existing pad instead of creating another", function()
        Window.StartPreview()
        local raises = frames[1].raises
        Window.StartPreview()
        assert.equals(1, #frames)
        assert.is_true(frames[1].raises > raises)
    end)

    it("hides the pad when the player stops being commander", function()
        Window.StartPreview()
        assert.is_true(frames[1]:IsShown())
        Group.isRaidLeader = false
        Window.Update()
        assert.is_false(frames[1]:IsShown())
        Group.isRaidLeader = true
        Window.Update()
        assert.is_false(frames[1]:IsShown())
    end)

    it("shows the pad without a close button while layout editing, then restores preview chrome", function()
        Window.StartPreview()
        local def = registered[Window.LAYOUT_ID]
        assert.is_true(def.isEnabled())
        def.onEditBegin()
        assert.is_true(frames[1]:IsShown())
        assert.is_false(frames[1].closeButton.shown)
        def.onEditEnd()
        assert.is_true(frames[1]:IsShown())
        assert.is_true(frames[1].closeButton.shown)

        Group.isRaidLeader = false
        assert.is_false(def.isEnabled())
    end)

    it("applies saved scale to the floating window", function()
        Ulatek:SetTacticalPadScale(1.2)
        Window.StartPreview()
        AssertNear(1.2, lastCreateOptions.scale)
        Window.ApplyScale(0.8)
        AssertNear(0.8, frames[1].scale)
    end)

    it("saves layout-editor position through the module", function()
        Window.Ensure()
        local def = registered[Window.LAYOUT_ID]
        def.setPosition({ point = "TOP", relativePoint = "CENTER", x = 8, y = -4 })
        assert.same({ point = "TOP", relativePoint = "CENTER", x = 8, y = -4 }, Ulatek:GetTacticalPadPosition())
        assert.same(Ulatek:GetTacticalPadPosition(), def.getPosition())
    end)

    it("defers creating and showing the pad until combat lockdown ends", function()
        local Combat = ns.Api.Combat
        Window.ListenForCombatDeferral()
        Combat.inCombat = true
        Window.StartPreview()
        assert.equals(0, #frames)

        Combat.FireLeave()
        assert.equals(1, #frames)
        assert.is_true(frames[1]:IsShown())
    end)

    it("shows the pad at the English or Chinese tomb and hides it elsewhere", function()
        Window.ListenForCombatDeferral()
        EnterTomb(TOMB_SUBZONE_EN)
        Window.Update()
        assert.is_true(frames[1]:IsShown())
        assert.is_false(frames[1].closeButton.shown)

        LeaveTomb()
        Instance.FireZoneChangedIndoors()
        assert.is_false(frames[1]:IsShown())

        EnterTomb(TOMB_SUBZONE_ZH)
        Instance.FireZoneChangedIndoors()
        assert.is_true(frames[1]:IsShown())

        Instance.info.instanceID = 0
        Window.Update()
        assert.is_false(frames[1]:IsShown())
    end)

    it("stays hidden at the tomb unless the raid is Mythic", function()
        Window.ListenForCombatDeferral()
        EnterTomb(TOMB_SUBZONE_EN, Instance.DIFFICULTY_HEROIC_RAID)
        Window.Update()
        assert.equals(0, #frames)

        EnterTomb(TOMB_SUBZONE_EN, Instance.DIFFICULTY_MYTHIC_RAID)
        Instance.FireEnteringWorld()
        assert.is_true(frames[1]:IsShown())

        Instance.info.difficultyID = Instance.DIFFICULTY_HEROIC_RAID
        Instance.FireEnteringWorld()
        assert.is_false(frames[1]:IsShown())
    end)

    it("stays hidden at the tomb for a raid member, unless a commander opens preview", function()
        Window.ListenForCombatDeferral()
        Group.isRaidLeader = false
        EnterTomb()
        Window.Update()
        assert.equals(0, #frames)

        Window.StartPreview()
        assert.equals(0, #frames)

        Group.isRaidLeader = true
        Window.Update()
        assert.is_true(frames[1]:IsShown())
    end)

    it("defers Show until combat ends when the tomb is entered during lockdown", function()
        local Combat = ns.Api.Combat
        Window.ListenForCombatDeferral()
        Combat.inCombat = true
        EnterTomb()
        Instance.FireZoneChangedIndoors()
        assert.equals(0, #frames)

        Combat.FireLeave()
        assert.equals(1, #frames)
        assert.is_true(frames[1]:IsShown())
    end)

    it("defers Hide until combat ends when the tomb is left during lockdown", function()
        local Combat = ns.Api.Combat
        Window.ListenForCombatDeferral()
        EnterTomb()
        Window.Update()
        assert.is_true(frames[1]:IsShown())

        Combat.inCombat = true
        LeaveTomb()
        Instance.FireZoneChangedIndoors()
        assert.is_true(frames[1]:IsShown())

        Combat.FireLeave()
        assert.is_false(frames[1]:IsShown())
    end)

    it("does not hide the pad when combat starts", function()
        local Combat = ns.Api.Combat
        Window.ListenForCombatDeferral()
        Window.StartPreview()
        assert.is_true(frames[1]:IsShown())
        frames[1].Show = function()
            error("ADDON_ACTION_BLOCKED Frame:Show()", 2)
        end
        frames[1].Hide = function()
            error("ADDON_ACTION_BLOCKED Frame:Hide()", 2)
        end
        frames[1].Raise = function()
            error("ADDON_ACTION_BLOCKED Frame:Raise()", 2)
        end
        Combat.inCombat = true
        Window.Update()
        assert.is_true(frames[1]:IsShown())
    end)

    it("ends the test on combat start but keeps the pad at the Mythic tomb without a close button", function()
        Window.ListenForCombatDeferral()
        EnterTomb()
        Window.StartPreview()
        assert.is_true(frames[1]:IsShown())
        assert.is_true(frames[1].closeButton.shown)
        assert.is_true(Ulatek:IsPadTestActive())

        local Combat = ns.Api.Combat
        Combat.FireEnter()
        assert.is_false(Ulatek:IsPadTestActive())
        assert.is_true(frames[1]:IsShown())
        assert.is_false(frames[1].closeButton.shown)
    end)

    it("hides the pad when combat starts the test outside the tomb", function()
        Window.ListenForCombatDeferral()
        Window.StartPreview()
        assert.is_true(frames[1]:IsShown())
        local Combat = ns.Api.Combat
        Combat.inCombat = true
        Combat.FireEnter()
        assert.is_true(frames[1]:IsShown())
        Combat.FireLeave()
        assert.is_false(frames[1]:IsShown())
        assert.is_false(Ulatek:IsPadTestActive())
    end)
end)
