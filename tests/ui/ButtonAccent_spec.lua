local Loader = require("helpers.loader")

describe("Accent button", function()
    local ns, Widgets, originalCreateFrame, originalCreateFont, originalFont

    local function FakeFont()
        return {
            SetFont = function() end,
            SetTextColor = function() end,
            SetShadowOffset = function() end,
            SetShadowColor = function() end,
        }
    end

    local function FakeTexture()
        local texture = { shown = true }
        function texture:SetAllPoints() end
        function texture:SetColorTexture(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:Show()
            self.shown = true
        end
        function texture:Hide()
            self.shown = false
        end
        return texture
    end

    local function FakeButton()
        local button = { enabled = true, alpha = 1, scripts = {}, hooks = {} }

        function button:SetBackdrop() end
        function button:SetBackdropColor(r, g, b, a)
            self.fill = { r = r, g = g, b = b, a = a }
        end
        function button:SetBackdropBorderColor(r, g, b, a)
            self.border = { r = r, g = g, b = b, a = a }
        end
        function button:CreateTexture()
            local texture = FakeTexture()
            self.textures = self.textures or {}
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function button:CreateFontString()
            local label = { text = "" }
            function label:SetText(text)
                self.text = text
            end
            function label:SetTextColor(r, g, b)
                self.color = { r = r, g = g, b = b }
            end
            function label:GetStringWidth()
                return #self.text * 8
            end
            function label:Hide()
                self.hidden = true
            end
            function label:SetPoint() end
            return label
        end
        function button:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function button:HookScript(name, handler)
            self.hooks[name] = handler
        end
        function button:SetNormalFontObject(font)
            self.normalFont = font
        end
        function button:SetDisabledFontObject(font)
            self.disabledFont = font
        end
        function button:SetText(text)
            self.text = text
        end
        function button:GetTextWidth()
            return 48
        end
        function button:GetFontString()
            return nil
        end
        function button:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function button:GetFrameLevel()
            return self.level or 1
        end
        function button:SetFrameLevel(level)
            self.level = level
        end
        function button:ClearAllPoints() end
        function button:SetPoint() end
        function button:SetAlpha(alpha)
            self.alpha = alpha
        end
        function button:IsEnabled()
            return self.enabled
        end
        function button:SetEnabled(enabled)
            self.enabled = enabled == true
            local script = self.enabled and self.scripts.OnEnable or self.scripts.OnDisable
            if script then
                script(self)
            end
        end

        return button
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalCreateFont = CreateFont
        originalFont = STANDARD_TEXT_FONT
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        CreateFont = function()
            return FakeFont()
        end
        CreateFrame = function()
            return FakeButton()
        end
        ns = { ADDON_NAME = Loader.ADDON_NAME, L = {}, Util = {} }
        assert(loadfile("ui/Assets.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/Widgets.lua"))(Loader.ADDON_NAME, ns)
        Widgets = ns.Widgets
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        CreateFont = originalCreateFont
        STANDARD_TEXT_FONT = originalFont
    end)

    it("keeps a solid primary fill and fades it when disabled", function()
        local button = Widgets.CreateButton(FakeButton(), "Draw", function() end, "primary")

        assert.equals(ns.Assets.Colors.ACCENT.r, button.fill.r)
        assert.equals(ns.Assets.Colors.ACCENT.g, button.fill.g)
        button:SetEnabled(false)
        assert.equals(0.4, button.alpha)
        assert.equals(ns.Assets.Colors.ACCENT.r, button.fill.r)
    end)

    it("uses a turquoise edge, shows a wash while pressed, and turns neutral when disabled", function()
        local button = Widgets.CreateButton(FakeButton(), "Draw", function() end, "accent")
        local accent = ns.Assets.Colors.ACCENT

        assert.equals(ns.Assets.Colors.SURFACE_RAISED.r, button.fill.r)
        assert.equals(accent.r, button.border.r)
        assert.equals(accent.g, button.border.g)
        assert.equals(ns.Assets.Fonts.BODY, button.normalFont)
        assert.equals(1, button.alpha)
        assert.is_true(button.width >= ns.Assets.Sizes.BUTTON_MIN_WIDTH)
        assert.equals(ns.Assets.Sizes.CONTROL_HEIGHT, button.height)

        button.hooks.OnMouseDown(button)
        local wash
        for _, texture in ipairs(button.textures) do
            if texture.color and texture.color.a == 0.16 then
                wash = texture
            end
        end
        assert.is_true(wash.shown)
        assert.equals(accent.r, wash.color.r)
        button.hooks.OnMouseUp()
        assert.is_false(wash.shown)

        button:SetEnabled(false)
        assert.equals(1, button.alpha)
        assert.equals(ns.Assets.Colors.SURFACE.r, button.fill.r)
        assert.equals(ns.Assets.Colors.BORDER.r, button.border.r)
        assert.equals(ns.Assets.Fonts.MUTED, button.normalFont)
        assert.is_false(wash.shown)
    end)

    it("highlights the selected segment of a segmented control", function()
        local created = {}
        CreateFrame = function()
            local button = FakeButton()
            created[#created + 1] = button
            return button
        end
        local control = Widgets.CreateSegmentedControl(created[1], {
            { value = "all", text = "All" },
            { value = "healer", text = "Healer" },
        }, function() end)

        control:SetSelected("healer")

        local accent = ns.Assets.Colors.ACCENT
        -- created[1] is the control; the segments follow in item order.
        assert.equals(ns.Assets.Colors.SURFACE_RAISED.r, created[2].fill.r)
        assert.equals(accent.r, created[3].fill.r)
        assert.equals(accent.g, created[3].fill.g)

        control:SetEnabled(false)
        control:SetEnabled(true)

        assert.equals(accent.r, created[3].fill.r)
        assert.equals(ns.Assets.Colors.SURFACE_RAISED.r, created[2].fill.r)
    end)

    it("draws a plus glyph in accent and mutes it when disabled", function()
        local button = Widgets.CreateButton(FakeButton(), "Add Aura", function() end, "accent", "+")

        assert.equals("+", button.accentGlyph.text)
        assert.equals(ns.Assets.Colors.ACCENT.r, button.accentGlyph.color.r)
        assert.equals("Add Aura", button.accentCaption.text)
        assert.is_true(button.width > ns.Assets.Sizes.BUTTON_MIN_WIDTH)

        button:SetEnabled(false)

        assert.equals(ns.Assets.Colors.TEXT_MUTED.r, button.accentGlyph.color.r)
        assert.equals(ns.Assets.Colors.TEXT_MUTED.r, button.accentCaption.color.r)
    end)
end)
