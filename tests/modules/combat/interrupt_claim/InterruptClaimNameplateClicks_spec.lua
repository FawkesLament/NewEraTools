local Loader = require("helpers.loader")

local NAMEPLATE_CLICKS_PATH = "modules/combat/interrupt_claim/ui/NameplateClicks.lua"

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        shown = true,
        points = {},
        attributes = {},
        frameLevel = 1,
        mouseEnabled = false,
        passThrough = {},
        clicks = {},
    }

    function frame:SetAttribute(name, value)
        self.setCount = (self.setCount or 0) + 1
        self.setCounts = self.setCounts or {}
        self.setCounts[name] = (self.setCounts[name] or 0) + 1
        self.attributes[name] = value
    end

    function frame:GetAttribute(name)
        return self.attributes[name]
    end

    function frame:RegisterForClicks(...)
        self.clicks = { ... }
    end

    function frame:SetPassThroughButtons(...)
        self.passThrough = { ... }
    end

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled == true
    end

    function frame:SetParent(parentFrame)
        self.parent = parentFrame
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:SetAllPoints(relativeTo)
        self.allPoints = relativeTo or self.parent
    end

    function frame:ClearAllPoints()
        self.points = {}
        self.allPoints = nil
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:IsForbidden()
        return self.forbidden == true
    end

    return frame
end

describe("InterruptClaim nameplate clicks", function()
    local ns, Module, Macro, Combat, Nameplate, Unit

    local function Start()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("InterruptClaim")
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
        Nameplate = ns.Api.Nameplate
        Unit = ns.Api.Unit
    end

    describe("lifecycle", function()
        local applies

        before_each(function()
            Start()
            applies = 0
            function Module:ApplyNameplateClicks()
                applies = applies + 1
            end
        end)

        it("does not bind when the feature is off or the focus macro is missing", function()
            assert.is_false(Module:ShouldBindNameplateClicks())
            Module:SetEnabled(true)
            assert.is_false(Module:ShouldBindNameplateClicks())
            assert.equals(1, applies)
            Module:CreateFocusMacro()
            Module:ListenForMacros()
            Macro.FireChanged()
            assert.is_true(Module:ShouldBindNameplateClicks())
        end)

        it("binds when enabled and a character-only NETFocus macro exists", function()
            Macro.Create(Module.GetFocusMacroName(), 1, "/focus", true)
            Module:SetEnabled(true)
            assert.is_true(Module:ShouldBindNameplateClicks())
        end)

        it("clears the desired binding when disabled", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            assert.is_true(Module:ShouldBindNameplateClicks())
            Module:SetEnabled(false)
            assert.is_false(Module:ShouldBindNameplateClicks())
            assert.equals(2, applies)
        end)

        it("defers protected updates during combat and applies them after", function()
            Module:CreateFocusMacro()
            Module:ListenForNameplateClicks()
            Combat.FireEnter()
            local ok, reason = Module:SyncNameplateClicks()
            assert.is_false(ok)
            assert.equals("combat", reason)
            assert.equals(0, applies)
            Module:SetEnabled(true)
            assert.equals(0, applies)
            Combat.FireLeave()
            assert.equals(1, applies)
            assert.is_true(Module:ShouldBindNameplateClicks())
        end)

        it("does not resync on combat leave when no click update was deferred", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            Module:ListenForNameplateClicks()
            local before = applies
            Combat.FireEnter()
            Combat.FireLeave()
            assert.equals(before, applies)
        end)

        it("does not defer nameplate events in combat when clicks should not bind", function()
            Module:ListenForNameplateClicks()
            Combat.FireEnter()
            Nameplate.FireAdded("nameplate1", FakeFrame())
            Nameplate.FireRemoved("nameplate1")
            Combat.FireLeave()
            assert.equals(0, applies)
        end)

        it("does not register nameplate listeners twice", function()
            Module:ListenForNameplateClicks()
            Module:ListenForNameplateClicks()
            assert.equals(1, #Nameplate.added)
            assert.equals(1, #Nameplate.removed)
        end)

        it("updates one nameplate without a full click resync", function()
            local added, removed = 0, 0
            function Module:ApplyNameplateAdded()
                added = added + 1
            end
            function Module:ApplyNameplateRemoved()
                removed = removed + 1
            end
            Module:ListenForNameplateClicks()
            Nameplate.FireAdded("nameplate1", FakeFrame())
            Nameplate.FireRemoved("nameplate1")
            assert.equals(1, added)
            assert.equals(1, removed)
            assert.equals(0, applies)
        end)

        it("defers a nameplate add during combat without a full resync until leave", function()
            function Module:ApplyNameplateAdded()
                applies = applies + 10
            end
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            Module:ListenForNameplateClicks()
            assert.equals(1, applies)
            Combat.FireEnter()
            Nameplate.FireAdded("nameplate1", FakeFrame())
            assert.equals(1, applies)
            Combat.FireLeave()
            assert.equals(2, applies)
        end)
    end)

    describe("overlays", function()
        local created
        local originalCreateFrame
        local NameplateClicks

        local function OverlayButtons()
            local buttons = {}
            for i = 1, #created do
                local frame = created[i]
                if frame.GetAttribute then
                    buttons[#buttons + 1] = frame
                end
            end
            return buttons
        end

        local function VisibleOverlays()
            local buttons = {}
            local binding = Module:GetClickBinding()
            for _, frame in ipairs(OverlayButtons()) do
                if frame:IsShown() and frame:GetAttribute(binding.typeAttribute) == "macro" then
                    buttons[#buttons + 1] = frame
                end
            end
            return buttons
        end

        local function MakePlate(forbidden)
            local unitFrame = FakeFrame()
            unitFrame.frameLevel = 4
            unitFrame.forbidden = forbidden == true
            local plate = FakeFrame()
            plate.UnitFrame = unitFrame
            plate.forbidden = forbidden == true
            return plate
        end

        local function SetEnemy(unit, enemy)
            if enemy then
                Unit.SetForTests(unit, {
                    exists = true,
                    guid = "Creature-" .. unit,
                    canAssist = false,
                    canAttack = true,
                })
            else
                Unit.SetForTests(unit, {
                    exists = true,
                    guid = "Player-" .. unit,
                    canAssist = true,
                    canAttack = false,
                })
            end
        end

        before_each(function()
            originalCreateFrame = CreateFrame
            created = {}
            CreateFrame = function(_, _, parent)
                local frame = FakeFrame(parent)
                created[#created + 1] = frame
                return frame
            end
            Start()
            assert(loadfile(NAMEPLATE_CLICKS_PATH))(Loader.ADDON_NAME, ns)
            NameplateClicks = ns.Modules.Internals("InterruptClaim").NameplateClicks
            NameplateClicks.Start()
        end)

        after_each(function()
            CreateFrame = originalCreateFrame
        end)

        it("binds Shift+Left on an enemy nameplate to the named NETFocus macro", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            local plate = MakePlate()
            Nameplate.FireAdded("nameplate1", plate)
            local overlays = VisibleOverlays()
            assert.equals(1, #overlays)
            local overlay = overlays[1]
            assert.equals("macro", overlay:GetAttribute("shift-type1"))
            assert.equals("NETFocus", overlay:GetAttribute("shift-macro1"))
            assert.equals(nil, overlay:GetAttribute("macrotext"))
            assert.equals(nil, overlay:GetAttribute("shift-macrotext1"))
            assert.equals("target", overlay:GetAttribute("*type1"))
            assert.equals("nameplate1", overlay:GetAttribute("unit"))
            assert.equals(plate.UnitFrame, overlay.parent)
            assert.equals(plate.UnitFrame, overlay.allPoints)
            local pass = overlay.passThrough
            local passedRight = false
            for i = 1, #pass do
                if pass[i] == "RightButton" then
                    passedRight = true
                end
            end
            assert.is_true(passedRight)
        end)

        it("does not place an overlay when the focus macro is missing", function()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            assert.equals(0, #VisibleOverlays())
        end)

        it("restores default clicks when disabled and reuses one overlay across cycles", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            local createdAfterBind = #created
            Module:SetEnabled(false)
            assert.equals(0, #VisibleOverlays())
            Module:SetEnabled(true)
            assert.equals(1, #VisibleOverlays())
            assert.equals(createdAfterBind, #created)
        end)

        it("ignores friendly and forbidden nameplates", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            local friendly = MakePlate()
            friendly.canAttack = false
            Nameplate.FireAdded("nameplate1", friendly)
            Nameplate.FireAdded("nameplate2", MakePlate(true))
            assert.equals(0, #VisibleOverlays())
        end)

        it("does not create overlays during combat and binds after combat ends", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            Combat.FireEnter()
            Nameplate.FireAdded("nameplate1", MakePlate())
            assert.equals(0, #VisibleOverlays())
            Combat.FireLeave()
            assert.equals(1, #VisibleOverlays())
        end)

        it("does not rewrite stable overlay attributes on a repeated full sync", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            local overlay = VisibleOverlays()[1]
            local typeWrites = overlay.setCounts["shift-type1"]
            local macroWrites = overlay.setCounts["shift-macro1"]
            local targetWrites = overlay.setCounts["*type1"]
            Module:SyncNameplateClicks()
            Module:SyncNameplateClicks()
            assert.equals(typeWrites, overlay.setCounts["shift-type1"])
            assert.equals(macroWrites, overlay.setCounts["shift-macro1"])
            assert.equals(targetWrites, overlay.setCounts["*type1"])
            assert.equals("NETFocus", overlay:GetAttribute("shift-macro1"))
        end)

        it("attaches a new nameplate without rewriting an existing overlay", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            SetEnemy("nameplate2", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            local first = VisibleOverlays()[1]
            local setCount = first.setCount
            Nameplate.FireAdded("nameplate2", MakePlate())
            assert.equals(2, #VisibleOverlays())
            assert.equals(setCount, first.setCount)
        end)

        it("removes one overlay without rewriting a remaining overlay", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            SetEnemy("nameplate2", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            Nameplate.FireAdded("nameplate2", MakePlate())
            local remaining
            for _, overlay in ipairs(VisibleOverlays()) do
                if overlay:GetAttribute("unit") == "nameplate1" then
                    remaining = overlay
                end
            end
            local setCount = remaining.setCount
            Nameplate.FireRemoved("nameplate2")
            assert.equals(1, #VisibleOverlays())
            assert.equals(setCount, remaining.setCount)
            assert.equals("nameplate1", remaining:GetAttribute("unit"))
        end)

        it("binds each modifier and mouse combination and clears the previous one", function()
            Module:CreateFocusMacro()
            Module:SetEnabled(true)
            SetEnemy("nameplate1", true)
            Nameplate.FireAdded("nameplate1", MakePlate())
            local previous
            for _, modifier in ipairs(Module.MODIFIERS) do
                for _, mouseButton in ipairs(Module.MOUSE_BUTTONS) do
                    Module:SetModifier(modifier)
                    Module:SetMouseButton(mouseButton)
                    local overlays = VisibleOverlays()
                    assert.equals(1, #overlays)
                    local overlay = overlays[1]
                    local binding = Module:GetClickBinding()
                    assert.equals("macro", overlay:GetAttribute(binding.typeAttribute))
                    assert.equals("NETFocus", overlay:GetAttribute(binding.macroAttribute))
                    assert.equals(binding.click, overlay.clicks[1])
                    if previous then
                        assert.equals(nil, overlay:GetAttribute(previous.typeAttribute))
                        assert.equals(nil, overlay:GetAttribute(previous.macroAttribute))
                    end
                    previous = binding
                end
            end
        end)
    end)
end)
