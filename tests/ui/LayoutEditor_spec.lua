local Loader = require("helpers.loader")

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        points = {},
        children = {},
        shown = true,
        movable = false,
        clamped = false,
        mouseEnabled = false,
        frameLevel = parent and ((parent.frameLevel or 0) + 1) or 1,
        frameStrata = "MEDIUM",
        scripts = {},
        scale = 1,
    }

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        if type(relativeTo) == "string" then
            relativePoint, x, y = relativeTo, relativePoint, x
            relativeTo = self.parent
        end
        self.points[1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end

    function frame:GetPoint()
        local p = self.points[1]
        if not p then
            return nil
        end
        return p.point, p.relativeTo, p.relativePoint, p.x, p.y
    end

    function frame:SetAllPoints(target)
        self.allPoints = target
    end

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:GetWidth()
        return self.width or 0
    end

    function frame:GetHeight()
        return self.height or 0
    end

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:GetFrameStrata()
        return self.frameStrata
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel
    end

    function frame:SetToplevel() end

    function frame:CreateTexture()
        local texture = {
            points = {},
        }
        function texture:SetAllPoints() end
        function texture:SetColorTexture() end
        function texture:SetPoint() end
        function texture:SetSize() end
        function texture:SetTexture() end
        function texture:SetHeight() end
        return texture
    end

    function frame:SetParent(parentFrame)
        self.parent = parentFrame
    end

    function frame:SetMovable(movable)
        self.movable = movable == true
    end

    function frame:SetClampedToScreen(clamped)
        self.clamped = clamped == true
    end

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled == true
    end

    function frame:RegisterForDrag() end

    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end

    function frame:SetBackdrop() end

    function frame:SetBackdropColor() end

    function frame:SetBackdropBorderColor() end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:Raise() end

    function frame:StartMoving()
        self.moving = true
    end

    function frame:StopMovingOrSizing()
        self.moving = false
    end

    function frame:SetText() end

    function frame:GetTextWidth()
        return 40
    end

    function frame:SetTextColor() end

    function frame:SetJustifyH() end

    function frame:SetWordWrap() end

    function frame:SetScale(scale)
        self.scale = scale
    end

    function frame:GetScale()
        return self.scale or 1
    end

    function frame:GetEffectiveScale()
        local scale = self.scale or 1
        local ancestor = self.parent
        while ancestor do
            scale = scale * (ancestor.scale or 1)
            ancestor = ancestor.parent
        end
        return scale
    end

    if parent and parent.children then
        table.insert(parent.children, frame)
    end

    return frame
end

describe("LayoutEditor", function()
    local LayoutEditor
    local MainPanel
    local Combat
    local printed
    local originalCreateFrame
    local UIParent

    before_each(function()
        printed = {}
        originalCreateFrame = CreateFrame
        UIParent = FakeFrame()
        _G.UIParent = UIParent

        CreateFrame = function(_, name, parent)
            return FakeFrame(parent)
        end

        Combat = {
            inCombat = false,
            enterCallbacks = {},
        }
        function Combat.IsInCombat()
            return Combat.inCombat
        end
        function Combat.IsLockedDown()
            return Combat.inCombat
        end
        function Combat.OnEnter(callback)
            table.insert(Combat.enterCallbacks, callback)
        end

        MainPanel = {
            db = { scale = 1.2 },
            panelFrame = nil,
            GetFrame = function(self)
                return self.panelFrame
            end,
        }

        local ns = {
            ADDON_NAME = Loader.ADDON_NAME,
            Api = { Combat = Combat },
            MainPanel = MainPanel,
            L = {
                LAYOUT_EDIT_DONE = "Done",
                LAYOUT_EDIT_IN_COMBAT = "in combat",
                LAYOUT_EDIT_NONE = "none",
            },
            Util = {
                Print = function(message)
                    table.insert(printed, message)
                end,
            },
            Assets = {
                Colors = {
                    BG = { r = 0, g = 0, b = 0, a = 1 },
                    ACCENT = { r = 0, g = 1, b = 0, a = 1 },
                    LAYOUT_EDIT_OUTLINE = { r = 0, g = 1, b = 0, a = 0.5 },
                    LAYOUT_EDIT_LABEL = { r = 0, g = 1, b = 0, a = 1 },
                    LAYOUT_EDIT_DIMMER = { r = 0, g = 0, b = 0, a = 0.55 },
                },
                Fonts = { SMALL_MUTED = "Font", LAYOUT_EDIT_DONE = "LayoutEditDone" },
                Spacing = { TINY = 2, LARGE = 12, XLARGE = 16, MEDIUM = 8 },
                Sizes = {
                    CONTROL_HEIGHT = 22,
                    BUTTON_TEXT_PADDING = 20,
                    BUTTON_MIN_WIDTH = 64,
                    BORDER = 1,
                    LAYOUT_EDIT_DONE_HEIGHT = 36,
                    LAYOUT_EDIT_DONE_MIN_WIDTH = 120,
                    LAYOUT_EDIT_DONE_TEXT_PADDING = 36,
                },
                Textures = { WHITE = "white" },
                Templates = { BACKDROP = "BackdropTemplate" },
            },
        }

        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a or 1
            end,
            CreateLabel = function(parent, _, text)
                -- FontStrings are not listed in Frame:GetChildren(); keep them off the children list.
                local label = FakeFrame(nil)
                label.parent = parent
                label.text = text
                return label
            end,
            CreateButton = function(parent, text, onClick)
                local button = FakeFrame(parent)
                button.text = text
                button.onClick = onClick
                button.width = 64
                button.height = 22
                function button:SetNormalFontObject() end
                function button:SetDisabledFontObject() end
                function button:GetTextWidth()
                    return 40
                end
                function button:SetSize(width, height)
                    self.width = width
                    self.height = height
                end
                function button:GetWidth()
                    return self.width
                end
                function button:GetHeight()
                    return self.height
                end
                return button
            end,
            CreateSurface = function(parent)
                return FakeFrame(parent)
            end,
        }

        assert(loadfile("ui/Position.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/FloatingWindow.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/LayoutEditor.lua"))(Loader.ADDON_NAME, ns)
        LayoutEditor = ns.LayoutEditor
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        _G.UIParent = nil
    end)

    local function RegisterElement(id, opts)
        opts = opts or {}
        local frame = FakeFrame(UIParent)
        local position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
        local calls = { begin = 0, ending = 0 }
        LayoutEditor.Register({
            id = id,
            label = id,
            frame = frame,
            global = opts.global ~= false,
            isEnabled = function()
                return opts.enabled ~= false
            end,
            getPosition = function()
                return position
            end,
            setPosition = function(next)
                position.point = next.point
                position.relativePoint = next.relativePoint
                position.x = next.x
                position.y = next.y
            end,
            onEditBegin = function()
                calls.begin = calls.begin + 1
                frame:Show()
            end,
            onEditEnd = function()
                calls.ending = calls.ending + 1
            end,
        })
        return frame, position, calls
    end

    it("applies and reads UIParent anchors", function()
        local frame = FakeFrame(UIParent)
        LayoutEditor.ApplyPosition(frame, { point = "TOP", relativePoint = "CENTER", x = 4, y = -8 })
        local position = LayoutEditor.ReadPosition(frame)
        assert.equals("TOP", position.point)
        assert.equals("CENTER", position.relativePoint)
        assert.equals(4, position.x)
        assert.equals(-8, position.y)
    end)

    it("begins global edit for enabled global elements only", function()
        local _, _, globalCalls = RegisterElement("CombatTimer:1", { global = true, enabled = true })
        local _, _, disabledCalls = RegisterElement("AuraTracker:1", { global = true, enabled = false })
        local _, _, localCalls = RegisterElement("Sszorak:map", { global = false, enabled = true })

        assert.is_true(LayoutEditor.BeginGlobal())
        assert.is_true(LayoutEditor.IsEditing())
        assert.equals(1, globalCalls.begin)
        assert.equals(0, disabledCalls.begin)
        assert.equals(0, localCalls.begin)

        LayoutEditor.End()
        assert.is_false(LayoutEditor.IsEditing())
        assert.equals(1, globalCalls.ending)
        assert.equals(0, localCalls.ending)
    end)

    it("Refresh shows and hides elements when isEnabled changes during global edit", function()
        local auraOpts = { global = true, enabled = true }
        local _, _, auraCalls = RegisterElement("AuraTracker:1", auraOpts)
        local _, _, timerCalls = RegisterElement("CombatTimer:1", { global = true, enabled = true })

        assert.is_true(LayoutEditor.BeginGlobal())
        assert.equals(1, auraCalls.begin)
        assert.equals(1, timerCalls.begin)

        auraOpts.enabled = false
        LayoutEditor.Refresh()
        assert.equals(1, auraCalls.ending)
        assert.equals(0, timerCalls.ending)
        assert.is_true(LayoutEditor.IsEditing())

        auraOpts.enabled = true
        LayoutEditor.Refresh()
        assert.equals(2, auraCalls.begin)
        assert.equals(1, auraCalls.ending)
        assert.equals(1, timerCalls.begin)

        LayoutEditor.End()
        assert.equals(2, auraCalls.ending)
        assert.equals(1, timerCalls.ending)
    end)

    it("Refresh ends the session when every element becomes disabled", function()
        local opts = { global = true, enabled = true }
        local _, _, calls = RegisterElement("AuraTracker:1", opts)
        assert.is_true(LayoutEditor.BeginGlobal())
        opts.enabled = false
        LayoutEditor.Refresh()
        assert.is_false(LayoutEditor.IsEditing())
        assert.equals(1, calls.ending)
    end)

    it("begins local edit for a single element", function()
        RegisterElement("CombatTimer:1", { global = true, enabled = true })
        local _, _, localCalls = RegisterElement("Sszorak:map", { global = false, enabled = true })

        assert.is_true(LayoutEditor.BeginLocal("Sszorak:map"))
        assert.equals(1, localCalls.begin)
        LayoutEditor.End()
        assert.equals(1, localCalls.ending)
    end)

    it("begins local edit for multiple elements", function()
        local _, _, mapCalls = RegisterElement("Sszorak:map", { global = false, enabled = true })
        local _, _, calloutCalls = RegisterElement("Sszorak:callout", { global = false, enabled = true })

        assert.is_true(LayoutEditor.BeginLocal({ "Sszorak:map", "Sszorak:callout" }))
        assert.equals(1, mapCalls.begin)
        assert.equals(1, calloutCalls.begin)
        LayoutEditor.End()
        assert.equals(1, mapCalls.ending)
        assert.equals(1, calloutCalls.ending)
    end)

    it("refuses to edit in combat", function()
        RegisterElement("CombatTimer:1")
        Combat.inCombat = true
        assert.is_false(LayoutEditor.BeginGlobal())
        assert.same({ "in combat" }, printed)
        assert.is_false(LayoutEditor.IsEditing())
    end)

    it("ends editing when combat starts", function()
        local _, _, calls = RegisterElement("CombatTimer:1")
        assert.is_true(LayoutEditor.BeginGlobal())
        assert.equals(1, #Combat.enterCallbacks)
        Combat.inCombat = true
        Combat.enterCallbacks[1]()
        assert.is_false(LayoutEditor.IsEditing())
        assert.equals(1, calls.ending)
    end)

    it("persists position after a drag stop", function()
        local frame, position = RegisterElement("CombatTimer:1")
        assert.is_true(LayoutEditor.BeginGlobal())
        frame.points[1] = {
            point = "TOPLEFT",
            relativeTo = UIParent,
            relativePoint = "BOTTOMLEFT",
            x = 12,
            y = 34,
        }
        -- Overlay is the last child created on the element frame during BeginSession.
        local overlay = frame.children[#frame.children]
        overlay.scripts.OnDragStop()
        assert.equals("TOPLEFT", position.point)
        assert.equals(12, position.x)
        assert.equals(34, position.y)
        LayoutEditor.End()
    end)

    it("dims the screen and raises editable frames while editing", function()
        local frame, _, calls = RegisterElement("CombatTimer:1")
        frame.frameStrata = "MEDIUM"
        assert.is_true(LayoutEditor.BeginGlobal())
        assert.equals("TOOLTIP", frame.frameStrata)
        LayoutEditor.End()
        assert.equals("MEDIUM", frame.frameStrata)
        assert.equals(1, calls.ending)
    end)

    it("keeps the main panel above the dimmer but behind editable frames", function()
        local frame = RegisterElement("CombatTimer:1")
        frame.frameStrata = "MEDIUM"
        local panelFrame = FakeFrame(UIParent)
        panelFrame.frameStrata = "DIALOG"
        panelFrame.shown = true
        MainPanel.panelFrame = panelFrame
        assert.is_true(LayoutEditor.BeginGlobal())
        assert.equals("FULLSCREEN_DIALOG", panelFrame.frameStrata)
        assert.equals("TOOLTIP", frame.frameStrata)
        LayoutEditor.End()
        assert.equals("DIALOG", panelFrame.frameStrata)
        assert.equals("MEDIUM", frame.frameStrata)
    end)

    it("scales identifying labels to the main panel, not the element", function()
        local frame = FakeFrame(UIParent)
        frame.scale = 2
        local position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
        LayoutEditor.Register({
            id = "CombatTimer:1",
            label = "Timer",
            frame = frame,
            global = true,
            isEnabled = function()
                return true
            end,
            getPosition = function()
                return position
            end,
            setPosition = function() end,
            onEditBegin = function() end,
            onEditEnd = function() end,
        })
        assert.is_true(LayoutEditor.BeginGlobal())
        local overlay = frame.children[#frame.children]
        -- Main panel scale 1.2; element effective scale 2 → label scale 0.6.
        assert.equals(0.6, overlay.label.scale)
        LayoutEditor.End()
    end)
end)
