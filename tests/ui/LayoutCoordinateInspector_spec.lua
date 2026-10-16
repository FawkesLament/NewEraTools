local Loader = require("helpers.loader")

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        points = {},
        children = {},
        shown = false,
        scripts = {},
        hooks = {},
        scale = 1,
        text = "",
        width = 0,
        height = 0,
    }

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        if type(relativeTo) == "string" then
            relativePoint, x, y = relativeTo, relativePoint, x
            relativeTo = self.parent
        end
        self.points[#self.points + 1] = {
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

    function frame:SetAllPoints() end
    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function frame:GetWidth()
        return self.width
    end
    function frame:GetHeight()
        return self.height
    end
    function frame:SetWidth(width)
        self.width = width
    end
    function frame:SetHeight(height)
        self.height = height
    end
    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end
    function frame:GetFrameStrata()
        return self.frameStrata or "MEDIUM"
    end
    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end
    function frame:GetFrameLevel()
        return self.frameLevel or 1
    end
    function frame:SetToplevel() end
    function frame:SetClampedToScreen() end
    function frame:SetMovable() end
    function frame:SetParent(parentFrame)
        self.parent = parentFrame
    end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end
    function frame:HookScript(name, handler)
        self.hooks[name] = self.hooks[name] or {}
        table.insert(self.hooks[name], handler)
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
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetScale(scale)
        self.scale = scale
    end
    function frame:GetScale()
        return self.scale
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
    function frame:GetCenter()
        return 100, 100
    end
    function frame:GetLeft()
        return self.left
    end
    function frame:GetRight()
        return self.right
    end
    function frame:GetTop()
        return self.top
    end
    function frame:GetBottom()
        return self.bottom
    end
    function frame:SetWindowScale(scale)
        self.scale = scale
    end
    function frame:SetText(text)
        self.text = text or ""
    end
    function frame:GetText()
        return self.text
    end
    function frame:SetTextColor() end
    function frame:SetJustifyH() end
    function frame:SetWordWrap() end
    function frame:SetFontObject() end
    function frame:SetAutoFocus() end
    function frame:SetNumeric() end
    function frame:SetMaxLetters() end
    function frame:ClearFocus() end
    function frame:Enable() end
    function frame:Disable() end
    function frame:SetEnabled() end
    function frame:GetTextWidth()
        return 40
    end
    function frame:GetStringWidth()
        return 40
    end
    function frame:CreateTexture()
        local texture = {}
        function texture:SetAllPoints() end
        function texture:SetColorTexture() end
        function texture:SetPoint() end
        function texture:SetSize() end
        function texture:SetTexture() end
        function texture:SetHeight() end
        return texture
    end
    function frame:CreateFontString()
        return FakeFrame(nil)
    end
    function frame:CreateLine()
        local line = {}
        function line:SetThickness() end
        function line:SetColorTexture() end
        function line:SetSnapToPixelGrid() end
        function line:SetTexelSnappingBias() end
        function line:SetStartPoint() end
        function line:SetEndPoint() end
        return line
    end

    if parent and parent.children then
        table.insert(parent.children, frame)
    end

    return frame
end

describe("LayoutCoordinateInspector", function()
    local Inspector
    local LayoutEditor
    local MainPanel
    local originalCreateFrame
    local UIParent
    local applied

    before_each(function()
        applied = {}
        originalCreateFrame = CreateFrame
        UIParent = FakeFrame()
        UIParent.left = 0
        UIParent.bottom = 0
        UIParent.width = 1000
        UIParent.height = 800
        function UIParent:GetWidth()
            return self.width
        end
        function UIParent:GetHeight()
            return self.height
        end
        function UIParent:GetCenter()
            return self.width / 2, self.height / 2
        end
        _G.UIParent = UIParent
        CreateFrame = function(_, name, parent)
            return FakeFrame(parent)
        end

        MainPanel = {
            db = {
                scale = 1.25,
                layoutInspectorPosition = {
                    point = "CENTER",
                    relativePoint = "CENTER",
                    x = 260,
                    y = 40,
                },
            },
            GetScale = function()
                return MainPanel.db.scale
            end,
            OnScaleChanged = function(callback)
                MainPanel.scaleListener = callback
                return function() end
            end,
        }

        local ns = {
            ADDON_NAME = Loader.ADDON_NAME,
            MainPanel = MainPanel,
            L = {
                LAYOUT_INSPECTOR_X = "X",
                LAYOUT_INSPECTOR_Y = "Y",
                LAYOUT_INSPECTOR_RESET = "Reset",
            },
            Util = {},
        }
        local function DeepCopy(value)
            if type(value) ~= "table" then
                return value
            end
            local copy = {}
            for key, nested in pairs(value) do
                copy[key] = DeepCopy(nested)
            end
            return copy
        end
        ns.Util.DeepCopy = DeepCopy
        ns.Assets = {
            Colors = {
                BG = { r = 0.07, g = 0.07, b = 0.09, a = 0.95 },
                BG_TRANSLUCENT = { r = 0, g = 0, b = 0, a = 0.6 },
                SURFACE = { r = 0.1, g = 0.1, b = 0.1, a = 1 },
                BORDER = { r = 0.2, g = 0.2, b = 0.2, a = 1 },
                ACCENT = { r = 0, g = 1, b = 0, a = 1 },
                TEXT = { r = 1, g = 1, b = 1 },
                TEXT_MUTED = { r = 0.5, g = 0.5, b = 0.5 },
                HOVER = { r = 1, g = 1, b = 1, a = 0.06 },
            },
            Fonts = {
                BODY = "Body",
                SMALL_MUTED = "Small",
                GLYPH = "Glyph",
            },
            Glyphs = { CLOSE = "x", DECREASE = "–", INCREASE = "+" },
            Spacing = { TINY = 2, SMALL = 4, MEDIUM = 8, LARGE = 12 },
            Sizes = {
                BORDER = 1,
                CLOSE_BUTTON = 18,
                CONTROL_HEIGHT = 22,
                CONTROL_ROW_HEIGHT = 30,
                INPUT_HEIGHT = 24,
                INPUT_DIGIT_WIDTH = 8,
                INPUT_TEXT_PADDING = 16,
                BUTTON_MIN_WIDTH = 64,
                BUTTON_TEXT_PADDING = 20,
                LAYOUT_INSPECTOR_WIDTH = 240,
                LAYOUT_INSPECTOR_OFFSET_DIGITS = 5,
            },
            Textures = { WHITE = "white" },
            Templates = { BACKDROP = "BackdropTemplate" },
        }

        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a or 1
            end,
            ApplyBackdrop = function() end,
            EnsureFonts = function() end,
            AddHoverHighlight = function() end,
            CreateSurface = function(parent, _, _, name)
                local frame = FakeFrame(parent)
                frame.name = name
                return frame
            end,
            CreateLabel = function(parent, _, text)
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
                return button
            end,
            CreateGlyphButton = function(parent, glyph, onClick)
                local button = FakeFrame(parent)
                button.text = glyph
                button.onClick = onClick
                button.width = 18
                button.height = 18
                return button
            end,
            CreateCloseButton = function(parent, onClick)
                return ns.Widgets.CreateGlyphButton(parent, "x", onClick)
            end,
            CreateNumberBox = function(parent)
                local box = FakeFrame(parent)
                box.text = "0"
                function box:SetEnabled() end
                return box
            end,
            CreateNumberStepper = function(parent, _, _, _, onValueChanged)
                local stepper = FakeFrame(parent)
                local box = ns.Widgets.CreateNumberBox(stepper)
                local current = 0
                local function Format(value)
                    return tostring(math.floor(value + 0.5))
                end
                function stepper:SetValue(value)
                    current = math.floor(value + 0.5)
                    box:SetText(Format(current))
                end
                function stepper:SetIncreaseLimit() end
                local function Commit()
                    local parsed = tonumber(box:GetText())
                    if parsed == nil then
                        box:SetText(Format(current))
                        return
                    end
                    current = math.floor(parsed + 0.5)
                    onValueChanged(current)
                end
                box:HookScript("OnEditFocusLost", Commit)
                box:HookScript("OnEnterPressed", Commit)
                return stepper
            end,
        }

        ns.Layout = {
            Stack = function(container, options)
                options = options or {}
                local stack = {
                    container = container,
                    height = options.paddingY or 0,
                    entries = {},
                }
                function stack:AddRow(height, spacingBefore)
                    local row = FakeFrame(container)
                    row.height = height
                    self.height = self.height + (spacingBefore or options.spacing or 0) + height
                    self.entries[#self.entries + 1] = row
                    return row
                end
                function stack:GetHeight()
                    return self.height + (options.paddingY or 0)
                end
                return stack
            end,
        }

        assert(loadfile("ui/Position.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/FloatingWindow.lua"))(Loader.ADDON_NAME, ns)
        LayoutEditor = {
            ApplyPosition = function(frame, position)
                applied[#applied + 1] = { frame = frame, position = position }
                frame.points[1] = {
                    point = position.point,
                    relativeTo = UIParent,
                    relativePoint = position.relativePoint,
                    x = position.x,
                    y = position.y,
                }
            end,
        }
        ns.LayoutEditor = LayoutEditor
        assert(loadfile("ui/LayoutCoordinateInspector.lua"))(Loader.ADDON_NAME, ns)
        Inspector = ns.LayoutCoordinateInspector
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        _G.UIParent = nil
    end)

    local function MakeDef(position)
        local frame = FakeFrame(UIParent)
        local defaultPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 }
        return {
            id = "CombatTimer:1",
            label = "Timer",
            frame = frame,
            getPosition = function()
                return position
            end,
            setPosition = function(next)
                position.point = next.point
                position.relativePoint = next.relativePoint
                position.x = next.x
                position.y = next.y
            end,
            getDefaultPosition = function()
                return {
                    point = defaultPosition.point,
                    relativePoint = defaultPosition.relativePoint,
                    x = defaultPosition.x,
                    y = defaultPosition.y,
                }
            end,
        }
    end

    it("shows one inspector window and updates coordinates for the selected element", function()
        local position = { point = "CENTER", relativePoint = "CENTER", x = 10, y = -20 }
        local def = MakeDef(position)
        Inspector.Show(def)
        assert.is_true(Inspector.IsShown())
        assert.equals("CombatTimer:1", Inspector.GetSelectedId())

        local other = MakeDef({ point = "CENTER", relativePoint = "CENTER", x = 1, y = 2 })
        other.id = "AuraTracker:1"
        other.label = "Aura"
        Inspector.Show(other)
        assert.equals("AuraTracker:1", Inspector.GetSelectedId())
        assert.is_true(Inspector.IsShown())

        Inspector.Hide()
        assert.is_false(Inspector.IsShown())
        assert.is_nil(Inspector.GetSelectedId())
    end)

    it("applies the main panel scale to the inspector window", function()
        local def = MakeDef({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 })
        Inspector.Show(def)
        local win = nil
        for _, child in ipairs(UIParent.children) do
            if child.name == Loader.ADDON_NAME .. "LayoutCoordinateInspector" then
                win = child
                break
            end
        end
        assert.is_false(win == nil)
        assert.equals(1.25, win:GetScale())
        MainPanel.db.scale = 0.8
        MainPanel.scaleListener(0.8)
        assert.equals(0.8, win:GetScale())
        Inspector.Hide()
    end)

    it("clamps off-screen typed offsets to the screen edge", function()
        local position = { point = "CENTER", relativePoint = "CENTER", x = -200, y = 0 }
        local def = MakeDef(position)
        def.frame.width = 100
        def.frame.height = 40
        def.frame.scale = 1
        -- Sync fake GetLeft with SetPoint so ClampToScreen can measure the true (unclamped) rect.
        local originalSetPoint = def.frame.SetPoint
        function def.frame:SetPoint(point, relativeTo, relativePoint, x, y)
            originalSetPoint(self, point, relativeTo, relativePoint, x, y)
            local parentWidth = UIParent:GetWidth()
            local parentHeight = UIParent:GetHeight()
            local centerX = parentWidth / 2 + (x or 0)
            local centerY = parentHeight / 2 + (y or 0)
            self.left = centerX - self.width / 2
            self.right = centerX + self.width / 2
            self.bottom = centerY - self.height / 2
            self.top = centerY + self.height / 2
        end
        Inspector.Show(def)

        local win = nil
        for _, child in ipairs(UIParent.children) do
            if child.name == Loader.ADDON_NAME .. "LayoutCoordinateInspector" then
                win = child
                break
            end
        end
        local boxes = {}
        local function collect(frame)
            if frame.GetText and frame.hooks and frame.hooks.OnEditFocusLost then
                boxes[#boxes + 1] = frame
            end
            for _, child in ipairs(frame.children or {}) do
                collect(child)
            end
        end
        collect(win)

        -- Jump from a negative X to a huge positive X (the case that broke engine clamp).
        boxes[1]:SetText("9999")
        for _, handler in ipairs(boxes[1].hooks.OnEditFocusLost) do
            handler(boxes[1])
        end
        -- Max CENTER offset for a 100-wide frame on a 1000-wide parent is 450.
        assert.equals(450, position.x)
        assert.equals("CENTER", position.point)
        assert.equals("CENTER", position.relativePoint)
        Inspector.Hide()
    end)

    it("commits valid offsets and reverts invalid text without moving", function()
        local position = { point = "CENTER", relativePoint = "CENTER", x = 10, y = -20 }
        local def = MakeDef(position)
        def.frame.width = 100
        def.frame.height = 40
        def.frame.scale = 1
        local originalSetPoint = def.frame.SetPoint
        function def.frame:SetPoint(point, relativeTo, relativePoint, x, y)
            originalSetPoint(self, point, relativeTo, relativePoint, x, y)
            local centerX = UIParent:GetWidth() / 2 + (x or 0)
            local centerY = UIParent:GetHeight() / 2 + (y or 0)
            self.left = centerX - self.width / 2
            self.right = centerX + self.width / 2
            self.bottom = centerY - self.height / 2
            self.top = centerY + self.height / 2
        end
        Inspector.Show(def)

        -- Reach into the created number boxes via the latest ApplyPosition path after nudge/commit.
        -- Drive commits through the hooked focus-lost handlers registered on the boxes.
        local win = nil
        for _, child in ipairs(UIParent.children) do
            if child.name == Loader.ADDON_NAME .. "LayoutCoordinateInspector" then
                win = child
                break
            end
        end
        assert.is_false(win == nil)

        local boxes = {}
        local function collect(frame)
            if frame.GetText and frame.hooks and frame.hooks.OnEditFocusLost then
                boxes[#boxes + 1] = frame
            end
            for _, child in ipairs(frame.children or {}) do
                collect(child)
            end
        end
        collect(win)
        assert.equals(2, #boxes)

        local xBox, yBox = boxes[1], boxes[2]
        xBox:SetText("33")
        for _, handler in ipairs(xBox.hooks.OnEditFocusLost) do
            handler(xBox)
        end
        assert.equals(33, position.x)
        assert.equals(-20, position.y)
        assert.equals("CENTER", position.point)

        local beforeY = position.y
        yBox:SetText("nope")
        for _, handler in ipairs(yBox.hooks.OnEditFocusLost) do
            handler(yBox)
        end
        assert.equals(beforeY, position.y)
        assert.equals("-20", yBox:GetText())
    end)

    it("resets to the element's default position", function()
        local position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -50 }
        local def = MakeDef(position)
        Inspector.Show(def)

        local win = nil
        for _, child in ipairs(UIParent.children) do
            if child.name == Loader.ADDON_NAME .. "LayoutCoordinateInspector" then
                win = child
                break
            end
        end
        local resetButton
        local function findReset(frame)
            if frame.text == "Reset" and frame.onClick then
                resetButton = frame
            end
            for _, child in ipairs(frame.children or {}) do
                findReset(child)
            end
        end
        findReset(win)
        assert.is_false(resetButton == nil)
        resetButton.onClick()
        assert.equals("CENTER", position.point)
        assert.equals(0, position.x)
        assert.equals(120, position.y)
    end)
end)
