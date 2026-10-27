local Loader = require("helpers.loader")

local WORLD_CLICKS_PATH = "modules/combat/interrupt_claim/ui/WorldClicks.lua"

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

    function frame:SetPropagateMouseClicks(enabled)
        self.propagateClicks = enabled == true
    end

    function frame:SetPropagateMouseMotion(enabled)
        self.propagateMotion = enabled == true
    end

    function frame:SetParent(parentFrame)
        self.parent = parentFrame
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

    return frame
end

describe("InterruptClaim world clicks", function()
    local ns, Module, Combat, WorldFrame
    local created
    local originalCreateFrame

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

    local function VisibleOverlay()
        local binding = Module:GetClickBinding()
        for _, frame in ipairs(OverlayButtons()) do
            if frame:IsShown() and frame:GetAttribute(binding.typeAttribute) == "macro" then
                return frame
            end
        end
        return nil
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        created = {}
        CreateFrame = function(_, _, parent)
            local frame = FakeFrame(parent)
            created[#created + 1] = frame
            return frame
        end
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("InterruptClaim")
        Combat = ns.Api.Combat
        WorldFrame = ns.Api.WorldFrame
        WorldFrame.frame = FakeFrame()
        WorldFrame.frame.frameLevel = 0
        assert(loadfile(WORLD_CLICKS_PATH))(Loader.ADDON_NAME, ns)
        Module:ListenForNameplateClicks()
        ns.Modules.Internals("InterruptClaim").WorldClicks.Start()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("does not bind WorldFrame until empty-space clear is on and NETFocus exists", function()
        assert.is_false(Module:ShouldBindWorldClicks())
        Module:SetEnabled(true)
        Module:CreateFocusMacro()
        assert.is_false(Module:ShouldBindWorldClicks())
        assert.equals(nil, VisibleOverlay())
        Module:SetClearFocusOnEmpty(true)
        assert.is_true(Module:ShouldBindWorldClicks())
        local overlay = VisibleOverlay()
        assert.is_true(overlay ~= nil)
        assert.equals(WorldFrame.frame, overlay.parent)
        assert.equals(WorldFrame.frame, overlay.allPoints)
        assert.equals("macro", overlay:GetAttribute("shift-type1"))
        assert.equals("NETFocus", overlay:GetAttribute("shift-macro1"))
        assert.equals(nil, overlay:GetAttribute("*type1"))
        assert.is_true(overlay.propagateClicks)
        assert.is_true(overlay.propagateMotion)
    end)

    it("clears the WorldFrame overlay when empty-space clear is turned off", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        Module:SetClearFocusOnEmpty(true)
        assert.is_true(VisibleOverlay() ~= nil)
        Module:SetClearFocusOnEmpty(false)
        assert.equals(nil, VisibleOverlay())
    end)

    it("does not create a WorldFrame overlay during combat and binds after combat ends", function()
        Module:CreateFocusMacro()
        Module:SetEnabled(true)
        Combat.FireEnter()
        Module:SetClearFocusOnEmpty(true)
        assert.equals(nil, VisibleOverlay())
        Combat.FireLeave()
        assert.is_true(VisibleOverlay() ~= nil)
    end)
end)
