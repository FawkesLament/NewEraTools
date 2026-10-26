local Loader = require("helpers.loader")

local TARGET_CLICKS_PATH = "modules/combat/interrupt_claim/ui/TargetFrameClicks.lua"

local function FakeFrame(name)
    local frame = {
        name = name or "TargetFrame",
        attributes = {
            ["*type1"] = "target",
            ["*type2"] = "menu",
            unit = "target",
        },
        setCount = 0,
        forbidden = false,
    }

    function frame:GetName()
        return self.name
    end

    function frame:SetAttribute(key, value)
        self.setCount = self.setCount + 1
        self.attributes[key] = value
    end

    function frame:GetAttribute(key)
        return self.attributes[key]
    end

    function frame:IsForbidden()
        return self.forbidden == true
    end

    return frame
end

describe("InterruptClaim target frame clicks", function()
    local ns, Module, Macro, Combat, TargetFrame, TargetFrameClicks

    local function Start()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("InterruptClaim")
        Macro = ns.Api.Macro
        Combat = ns.Api.Combat
        TargetFrame = ns.Api.TargetFrame
        assert(loadfile(TARGET_CLICKS_PATH))(Loader.ADDON_NAME, ns)
        TargetFrameClicks = ns.Modules.Internals("InterruptClaim").TargetFrameClicks
    end

    before_each(function()
        Start()
        TargetFrame.frame = FakeFrame()
        Module:SetBindTargetFrame(true)
        TargetFrameClicks.Start()
    end)

    it("binds Shift+Left on the default Target Frame to the named NETFocus macro", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        local frame = TargetFrame.frame
        assert.equals("macro", frame:GetAttribute("shift-type1"))
        assert.equals("NETFocus", frame:GetAttribute("shift-macro1"))
        assert.equals(nil, frame:GetAttribute("macrotext"))
        assert.equals(nil, frame:GetAttribute("shift-macrotext1"))
        assert.equals("target", frame:GetAttribute("*type1"))
        assert.equals("menu", frame:GetAttribute("*type2"))
        assert.equals("target", frame:GetAttribute("unit"))
    end)

    it("restores the original Shift+Left attributes when disabled", function()
        TargetFrame.frame.attributes["shift-type1"] = "focus"
        TargetFrame.frame.attributes["shift-macro1"] = "OldMacro"
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
        Module:SetEnabled(false)
        assert.equals("focus", TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals("OldMacro", TargetFrame.frame:GetAttribute("shift-macro1"))
        assert.equals("target", TargetFrame.frame:GetAttribute("*type1"))
    end)

    it("does not bind when the focus macro is missing", function()
        Module:SetEnabled(true)
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-macro1"))
    end)

    it("does not rewrite attributes that are already bound", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        local afterBind = TargetFrame.frame.setCount
        Module:ApplyTargetFrameClicks()
        assert.equals(afterBind, TargetFrame.frame.setCount)
    end)

    it("defers Target Frame attribute changes during combat", function()
        Module:ListenForNameplateClicks()
        Module:CreateFocusMacro()
        Combat.FireEnter()
        Module:SetEnabled(true)
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
        Combat.FireLeave()
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals("NETFocus", TargetFrame.frame:GetAttribute("shift-macro1"))
    end)

    it("ignores a missing or forbidden Target Frame without errors", function()
        TargetFrame.frame = nil
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        TargetFrame.frame = FakeFrame()
        TargetFrame.frame.forbidden = true
        Module:ApplyTargetFrameClicks()
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("does not bind FocusFrame or other unit frames", function()
        local focus = FakeFrame("FocusFrame")
        focus.attributes["*type1"] = "target"
        TargetFrame.frame = focus
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals(nil, focus:GetAttribute("shift-type1"))
        assert.equals("target", focus:GetAttribute("*type1"))
    end)

    it("uses the shared click sync so nameplate apply still runs", function()
        local plates = 0
        function Module:ApplyNameplateClicks()
            plates = plates + 1
        end
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals(1, plates)
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("binds the EllesmereUI Target Frame when that addon is active", function()
        local eui = FakeFrame("EllesmereUIUnitFrames_Target")
        TargetFrame.ellesmereFrame = eui
        TargetFrame.ellesmereLoaded = true
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals("macro", eui:GetAttribute("shift-type1"))
        assert.equals("NETFocus", eui:GetAttribute("shift-macro1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals("target", eui:GetAttribute("*type1"))
    end)

    it("waits for a delayed EllesmereUI Target Frame and restores Blizzard", function()
        Module:ListenForNameplateClicks()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))

        local eui = FakeFrame("EllesmereUIUnitFrames_Target")
        TargetFrame.ellesmereFrame = eui
        TargetFrame.ellesmereLoaded = true
        TargetFrame.FireReady()
        assert.equals("macro", eui:GetAttribute("shift-type1"))
        assert.equals("NETFocus", eui:GetAttribute("shift-macro1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("restores EllesmereUI Shift+Left attributes when disabled", function()
        local eui = FakeFrame("EllesmereUIUnitFrames_Target")
        eui.attributes["shift-type1"] = "focus"
        TargetFrame.ellesmereFrame = eui
        TargetFrame.ellesmereLoaded = true
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals("macro", eui:GetAttribute("shift-type1"))
        Module:SetEnabled(false)
        assert.equals("focus", eui:GetAttribute("shift-type1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("defers an EllesmereUI ready update during combat", function()
        Module:ListenForNameplateClicks()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        Combat.FireEnter()
        local eui = FakeFrame("EllesmereUIUnitFrames_Target")
        TargetFrame.ellesmereFrame = eui
        TargetFrame.ellesmereLoaded = true
        TargetFrame.FireReady()
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals(nil, eui:GetAttribute("shift-type1"))
        Combat.FireLeave()
        assert.equals("macro", eui:GetAttribute("shift-type1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("does not rewrite attributes after repeated ready or apply calls", function()
        Module:ListenForNameplateClicks()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        local afterBind = TargetFrame.frame.setCount
        TargetFrame.FireReady()
        TargetFrame.FireReady()
        Module:ApplyTargetFrameClicks()
        TargetFrameClicks.Start()
        Module:SyncNameplateClicks()
        assert.equals(afterBind, TargetFrame.frame.setCount)
    end)

    it("restores original attributes only once when disabled repeatedly", function()
        TargetFrame.frame.attributes["shift-type1"] = "focus"
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        Module:SetEnabled(false)
        local afterRestore = TargetFrame.frame.setCount
        Module:SetEnabled(false)
        TargetFrameClicks.Apply()
        TargetFrameClicks.Apply()
        assert.equals(afterRestore, TargetFrame.frame.setCount)
        assert.equals("focus", TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("does not reapply Target Frame clicks when a nameplate is added or removed", function()
        local applies = 0
        local apply = Module.ApplyTargetFrameClicks
        function Module:ApplyTargetFrameClicks()
            applies = applies + 1
            apply(self)
        end
        Module:ListenForNameplateClicks()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals(1, applies)
        local afterBind = TargetFrame.frame.setCount
        ns.Api.Nameplate.FireAdded("nameplate1", { attributes = {} })
        ns.Api.Nameplate.FireRemoved("nameplate1")
        assert.equals(1, applies)
        assert.equals(afterBind, TargetFrame.frame.setCount)
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
    end)

    it("does not accumulate listeners across repeated Start calls", function()
        Module:ListenForNameplateClicks()
        local readyCount = #TargetFrame.readyCallbacks
        TargetFrameClicks.Start()
        TargetFrameClicks.Start()
        Module:ListenForNameplateClicks()
        assert.equals(readyCount, #TargetFrame.readyCallbacks)
        assert.equals(1, #ns.Api.Nameplate.added)
        assert.equals(1, #ns.Api.Combat.leaveCallbacks)
    end)

    it("does not bind the Target Frame when coverage is off", function()
        Module:SetBindTargetFrame(false)
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals(nil, TargetFrame.frame:GetAttribute("shift-macro1"))
        assert.equals("target", TargetFrame.frame:GetAttribute("*type1"))
    end)

    it("restores the previous shortcut before applying a new one", function()
        TargetFrame.frame.attributes["shift-type1"] = "focus"
        TargetFrame.frame.attributes["ctrl-type1"] = "assist"
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        assert.equals("macro", TargetFrame.frame:GetAttribute("shift-type1"))
        Module:SetModifier("ctrl")
        assert.equals("focus", TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals("macro", TargetFrame.frame:GetAttribute("ctrl-type1"))
        assert.equals("NETFocus", TargetFrame.frame:GetAttribute("ctrl-macro1"))
        Module:SetEnabled(false)
        assert.equals("focus", TargetFrame.frame:GetAttribute("shift-type1"))
        assert.equals("assist", TargetFrame.frame:GetAttribute("ctrl-type1"))
    end)

    it("binds each modifier and mouse combination on the Target Frame", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        local previous
        for _, modifier in ipairs(Module.MODIFIERS) do
            for _, mouseButton in ipairs(Module.MOUSE_BUTTONS) do
                Module:SetModifier(modifier)
                Module:SetMouseButton(mouseButton)
                local binding = Module:GetClickBinding()
                local frame = TargetFrame.frame
                assert.equals("macro", frame:GetAttribute(binding.typeAttribute))
                assert.equals("NETFocus", frame:GetAttribute(binding.macroAttribute))
                if previous then
                    assert.is_true(frame:GetAttribute(previous.typeAttribute) ~= "macro")
                end
                previous = binding
            end
        end
    end)
end)
