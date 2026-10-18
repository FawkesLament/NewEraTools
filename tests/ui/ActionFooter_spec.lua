describe("ActionFooter", function()
    local ns, ActionFooter, originalCreateFrame

    local function FakeRegion()
        local region = { points = {}, children = {}, shown = true }
        function region:SetJustifyH() end
        function region:SetJustifyV(justify)
            self.justifyV = justify
        end
        function region:SetWordWrap(wrap)
            self.wordWrap = wrap
        end
        function region:ClearAllPoints()
            self.points = {}
        end
        function region:SetPoint(point, relativeTo, relativePoint, x, y)
            self.points[point] = { relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
        end
        function region:SetHeight(height)
            self.height = height
        end
        function region:SetWidth(width)
            self.width = width
        end
        function region:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function region:GetWidth()
            return self.width or 0
        end
        function region:GetStringWidth()
            return self.stringWidth or 0
        end
        function region:GetStringHeight()
            if self.width and self.stringWidth and self.stringWidth > self.width then
                return 22
            end
            return 11
        end
        function region:SetText(text)
            self.text = text
        end
        function region:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function region:SetTexture(texture)
            self.texture = texture
        end
        function region:SetColorTexture(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function region:Show()
            self.shown = true
        end
        function region:Hide()
            self.shown = false
        end
        function region:SetScript(name, handler)
            self.scripts = self.scripts or {}
            self.scripts[name] = handler
        end
        function region:CreateTexture()
            local texture = FakeRegion()
            self.children[#self.children + 1] = texture
            texture.parent = self
            return texture
        end
        return region
    end

    local function Track(parent, region)
        parent.children[#parent.children + 1] = region
        region.parent = parent
        return region
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        ns = {
            Assets = {
                Fonts = { SMALL_MUTED = "SmallMuted" },
                FontStyles = { SmallMuted = { size = 11 } },
                Sizes = { CONTROL_HEIGHT = 22 },
                Spacing = { SMALL = 4, MEDIUM = 8, LARGE = 12 },
                Colors = {
                    DIVIDER = { r = 0.2, g = 0.2, b = 0.2, a = 1 },
                    WARNING = { r = 1, g = 0.6, b = 0.2, a = 1 },
                    ERROR = { r = 0.9, g = 0.2, b = 0.2, a = 1 },
                    SUCCESS = { r = 0.3, g = 0.8, b = 0.4, a = 1 },
                    TEXT_MUTED = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
                },
                Icons = {
                    WARNING = "warning",
                    READY_CHECK_NOT_READY = "error",
                    READY_CHECK_READY = "success",
                    INFO = "info",
                },
            },
            Widgets = {},
        }
        CreateFrame = function(_, _, parent)
            return Track(parent, FakeRegion())
        end
        function ns.Widgets.UnpackColor(color)
            return color.r, color.g, color.b, color.a
        end
        function ns.Widgets.CreateLabel(parent, font, text)
            local label = Track(parent, FakeRegion())
            label.font = font
            label.text = text
            label.stringWidth = 40
            return label
        end
        function ns.Widgets.CreateButton(parent, text, onClick, variant)
            local button = Track(parent, FakeRegion())
            button.text = text
            button.onClick = onClick
            button.variant = variant
            button.width = 80
            button.height = 22
            return button
        end
        assert(loadfile("ui/ActionFooter.lua"))("NewEraTools", ns)
        ActionFooter = ns.ActionFooter
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    local function Create(overrides)
        local heights = {}
        local onClick = function() end
        local options = {
            text = "Start Lottery",
            onClick = onClick,
            onHeightChanged = function(height)
                table.insert(heights, height)
            end,
        }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        local parent = FakeRegion()
        local footer = ActionFooter.Create(parent, options)
        return footer, heights, onClick
    end

    it("keeps a content-sized accent button under the divider when there is no message", function()
        local footer, heights, onClick = Create()
        local divider, icon, label = footer.children[1], footer.children[2], footer.children[3]

        -- 1px rule + 8px gap + 22px button. The callback waits until Create returns.
        assert.equals(31, footer:GetHeight())
        assert.equals(0, #heights)
        assert.equals("accent", footer.button.variant)
        assert.equals("Start Lottery", footer.button.text)
        assert.is_true(footer.button.onClick == onClick)
        assert.equals(80, footer.button.width)
        assert.is_nil(footer.button.points.LEFT)
        assert.is_true(footer.button.points.TOPRIGHT.relativeTo == footer)
        assert.equals(-9, footer.button.points.TOPRIGHT.y)
        assert.equals(1, divider.height)
        assert.same({ r = 0.2, g = 0.2, b = 0.2, a = 1 }, divider.color)
        assert.is_false(icon.shown)
        assert.is_false(label.shown)
    end)

    it("places a short warning on the button row without growing", function()
        local footer, heights = Create()
        footer.width = 400
        local icon, label = footer.children[2], footer.children[3]
        label.stringWidth = 100

        footer:SetMessage({ text = "You are not in a raid.", severity = "warning" })

        assert.equals(31, footer:GetHeight())
        assert.equals(0, #heights)
        assert.is_true(icon.shown)
        assert.equals("warning", icon.texture)
        assert.same({ r = 1, g = 0.6, b = 0.2, a = 1 }, label.color)
        assert.equals("You are not in a raid.", label.text)
        assert.is_false(label.wordWrap)
        -- 400 - 80 - 12 - 14 - 4
        assert.equals(290, label.width)
        assert.is_nil(label.points.RIGHT)
        assert.is_true(label.points.LEFT.relativeTo == icon)
        assert.equals(4, label.points.LEFT.x)
        assert.is_true(icon.points.LEFT.relativeTo == footer)
        assert.equals(-20, icon.points.LEFT.y)
    end)

    it("moves a message that cannot sit beside the button onto a line above it", function()
        local footer, heights = Create()
        footer.width = 400
        local icon, label = footer.children[2], footer.children[3]
        -- Wider than the inline room (290) but still one line across the footer (382).
        label.stringWidth = 300

        footer:SetMessage({ text = "Only the raid leader or an assistant can use Raid Lottery.", severity = "warning" })

        -- Icon is taller than one line: 1 + 8 + 14 + 8 + 22.
        assert.equals(53, footer:GetHeight())
        assert.same({ 53 }, heights)
        assert.is_true(label.wordWrap)
        assert.equals("TOP", label.justifyV)
        assert.equals(382, label.width)
        assert.is_true(icon.points.TOPLEFT.relativeTo == footer)
        assert.equals(-9, icon.points.TOPLEFT.y)
        assert.is_true(label.points.TOPLEFT.relativeTo == icon)
        assert.is_nil(footer.button.points.LEFT)
        assert.equals(-31, footer.button.points.TOPRIGHT.y)
    end)

    it("grows for a wrapped message and shrinks again when the message is cleared", function()
        local footer, heights = Create()
        footer.width = 400
        local icon, label = footer.children[2], footer.children[3]
        label.stringWidth = 500

        footer:SetMessage({ text = "Not enough eligible members.", severity = "error" })

        -- Wrapped text is 22px: 1 + 8 + 22 + 8 + 22.
        assert.equals(61, footer:GetHeight())
        assert.equals("error", icon.texture)
        assert.same({ r = 0.9, g = 0.2, b = 0.2, a = 1 }, label.color)
        assert.equals(22, label:GetStringHeight())

        footer:SetMessage(nil)

        assert.equals(31, footer:GetHeight())
        assert.same({ 61, 31 }, heights)
        assert.is_false(icon.shown)
        assert.is_false(label.shown)
        assert.equals(-9, footer.button.points.TOPRIGHT.y)
    end)

    it("stays on one row until the footer width is known", function()
        local footer, heights = Create()
        local label = footer.children[3]
        label.stringWidth = 500

        footer:SetMessage({ text = "Not enough eligible members.", severity = "warning" })

        assert.equals(31, footer:GetHeight())
        assert.equals(0, #heights)

        footer.width = 400
        footer.scripts.OnSizeChanged()

        assert.equals(61, footer:GetHeight())
        assert.same({ 61 }, heights)
    end)

    it("uses the severity icon and color for success and info", function()
        local footer = Create()
        footer.width = 400
        local icon, label = footer.children[2], footer.children[3]

        footer:SetMessage({ text = "Sent.", severity = "success" })
        assert.equals("success", icon.texture)
        assert.same({ r = 0.3, g = 0.8, b = 0.4, a = 1 }, label.color)

        footer:SetMessage({ text = "Ready.", severity = "info" })
        assert.equals("info", icon.texture)
        assert.same({ r = 0.5, g = 0.5, b = 0.5, a = 1 }, label.color)
        assert.equals(31, footer:GetHeight())
    end)

    it("treats a blank message as no message and rejects an unknown severity", function()
        local footer = Create()
        footer.width = 400
        local icon = footer.children[2]
        footer:SetMessage({ text = "You are not in a raid.", severity = "warning" })

        footer:SetMessage({ text = "", severity = "warning" })

        assert.equals(31, footer:GetHeight())
        assert.is_false(icon.shown)
        assert.is_false(pcall(function()
            footer:SetMessage({ text = "Nope", severity = "fatal" })
        end))
    end)
end)
