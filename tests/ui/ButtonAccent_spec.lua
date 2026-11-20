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
        local texture = { shown = true, points = {} }
        function texture:SetAllPoints() end
        function texture:ClearAllPoints()
            self.points = {}
        end
        function texture:SetPoint(point, _, relativePoint, x, y)
            self.points[point] = { relativePoint = relativePoint, x = x, y = y }
        end
        function texture:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function texture:SetWidth(width)
            self.width = width
        end
        function texture:SetHeight(height)
            self.height = height
        end
        function texture:SetColorTexture(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:SetSnapToPixelGrid() end
        function texture:SetTexelSnappingBias() end
        function texture:Show()
            self.shown = true
        end
        function texture:Hide()
            self.shown = false
        end
        return texture
    end

    local function FakeButton()
        local button = { enabled = true, alpha = 1, shown = true, scripts = {}, hooks = {} }

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
            function label:SetAllPoints() end
            function label:SetJustifyH() end
            function label:SetJustifyV() end
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
        function button:ClearAllPoints()
            self.points = {}
        end
        function button:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points = self.points or {}
            self.points[point] = {
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
        function button:Show()
            self.shown = true
        end
        function button:Hide()
            self.shown = false
        end
        function button:SetAlpha(alpha)
            self.alpha = alpha
        end
        function button:IsEnabled()
            return self.enabled
        end
        function button:Enable()
            self.enabled = true
        end
        function button:Disable()
            self.enabled = false
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

        assert.equals(ns.Assets.Colors.MENU_ACCENT.r, button.fill.r)
        assert.equals(ns.Assets.Colors.MENU_ACCENT.g, button.fill.g)
        button:SetEnabled(false)
        assert.equals(0.4, button.alpha)
        assert.equals(ns.Assets.Colors.MENU_ACCENT.r, button.fill.r)
    end)

    it("uses a turquoise edge, shows a wash while pressed, and turns neutral when disabled", function()
        local button = Widgets.CreateButton(FakeButton(), "Draw", function() end, "accent")
        local accent = ns.Assets.Colors.MENU_ACCENT

        assert.equals(ns.Assets.Colors.SURFACE_RAISED.r, button.fill.r)
        assert.equals(accent.r, button.border.r)
        assert.equals(accent.g, button.border.g)
        assert.equals(ns.Assets.Fonts.SUBTITLE, button.normalFont)
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
        local last
        local control = Widgets.CreateSegmentedControl(nil, {
            { value = "all", text = "All" },
            { value = "healer", text = "Healer" },
        }, function(value)
            last = value
        end)

        -- created[1] is the track; [2] is the thumb; segments follow in item order.
        local track = created[1]
        local thumb = created[2]
        local allSegment = created[3]
        local healerSegment = created[4]
        local inset = ns.Assets.Sizes.TOGGLE_THUMB_INSET

        assert.equals(ns.Assets.Colors.TOGGLE_TRACK_OFF.r, track.textures[1].color.r)
        assert.equals(ns.Assets.Colors.TOGGLE_TRACK_OFF_BORDER.r, track.textures[2].color.r)
        assert.equals(ns.Assets.Colors.SEGMENT_THUMB_BG.r, thumb.textures[1].color.r)
        assert.equals(ns.Assets.Colors.SEGMENT_THUMB_BORDER.r, thumb.textures[2].color.r)
        assert.is_false(thumb.shown)

        control:SetSelected("healer")

        assert.is_true(thumb.shown)
        assert.equals(healerSegment, thumb.points.TOPLEFT.relativeTo)
        assert.equals(healerSegment, thumb.points.BOTTOMRIGHT.relativeTo)
        assert.equals(ns.Assets.Colors.TEXT_PRIMARY.r, healerSegment.label.color.r)
        assert.equals(ns.Assets.Colors.TEXT_BODY.r, allSegment.label.color.r)
        assert.equals(ns.Assets.Sizes.CONTROL_HEIGHT - inset * 2, healerSegment.height)
        assert.equals(2 * healerSegment.width + inset * 2, track.width)

        control:SetEnabled(false)
        assert.is_false(control:IsEnabled())
        assert.equals(1, control.alpha)
        assert.equals(1, healerSegment.alpha)
        healerSegment.scripts.OnClick()
        assert.equals(nil, last)

        control:SetEnabled(true)
        assert.is_true(control:IsEnabled())
        assert.equals(ns.Assets.Colors.TEXT_PRIMARY.r, healerSegment.label.color.r)
        assert.equals(ns.Assets.Colors.TEXT_BODY.r, allSegment.label.color.r)

        allSegment.scripts.OnClick()
        assert.equals("all", last)
        assert.is_true(thumb.shown)
        assert.equals(healerSegment, thumb.points.TOPLEFT.relativeTo)
    end)

    it("keeps a toggle switch controlled and dims it when disabled", function()
        local last
        local toggle = Widgets.CreateToggleSwitch(FakeButton(), function(value)
            last = value
        end)
        local inset = ns.Assets.Sizes.TOGGLE_THUMB_INSET

        assert.equals(ns.Assets.Sizes.TOGGLE_WIDTH, toggle.width)
        assert.equals(ns.Assets.Sizes.TOGGLE_HEIGHT, toggle.height)
        assert.is_false(toggle:IsChecked())
        assert.equals(ns.Assets.Colors.TOGGLE_TRACK_OFF.r, toggle.textures[1].color.r)
        assert.equals("LEFT", toggle.textures[6].points.LEFT.relativePoint)
        assert.equals(inset, toggle.textures[6].points.LEFT.x)

        toggle.scripts.OnClick()
        assert.equals(true, last)
        assert.is_false(toggle:IsChecked())

        toggle:SetChecked(true)
        assert.is_true(toggle:IsChecked())
        assert.equals(ns.Assets.Colors.MENU_ACCENT.r, toggle.textures[1].color.r)
        assert.equals("RIGHT", toggle.textures[6].points.RIGHT.relativePoint)
        assert.equals(-inset, toggle.textures[6].points.RIGHT.x)

        toggle:SetEnabled(false)
        assert.is_false(toggle:IsEnabled())
        assert.equals(0.4, toggle.alpha)
        toggle.scripts.OnClick()
        assert.equals(true, last)
    end)

    it("draws a plus glyph in accent and mutes it when disabled", function()
        local button = Widgets.CreateButton(FakeButton(), "Add Aura", function() end, "accent", "+")

        assert.equals("+", button.accentGlyph.text)
        assert.equals(ns.Assets.Colors.MENU_ACCENT.r, button.accentGlyph.color.r)
        assert.equals("Add Aura", button.accentCaption.text)
        assert.is_true(button.width > ns.Assets.Sizes.BUTTON_MIN_WIDTH)

        button:SetEnabled(false)

        assert.equals(ns.Assets.Colors.TEXT_MUTED.r, button.accentGlyph.color.r)
        assert.equals(ns.Assets.Colors.TEXT_MUTED.r, button.accentCaption.color.r)
    end)
end)
