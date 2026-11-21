local Loader = require("helpers.loader")

describe("Checkbox", function()
    local ns, Checkbox, originalCreateFrame, originalHooksecurefunc

    local function FakeCheckButton()
        local button = {
            enabled = true,
            alpha = 1,
            checked = false,
            clipsChildren = true,
            scripts = {},
            hooks = {},
            textures = {},
        }

        function button:SetBackdrop() end
        function button:SetBackdropColor(r, g, b, a)
            self.fill = { r = r, g = g, b = b, a = a }
        end
        function button:SetBackdropBorderColor(r, g, b, a)
            self.border = { r = r, g = g, b = b, a = a }
        end
        function button:SetClipsChildren(clips)
            self.clipsChildren = clips == true
        end
        function button:CreateTexture(_, layer, _, subLevel)
            local texture = { shown = true, layer = layer, subLevel = subLevel, points = {} }
            function texture:SetAllPoints() end
            function texture:SetPoint(point, relativeTo, relativePoint, x, y)
                self.points[point] = {
                    relativeTo = relativeTo,
                    relativePoint = relativePoint,
                    x = x,
                    y = y,
                }
            end
            function texture:SetSize(width, height)
                self.width = width
                self.height = height
            end
            function texture:SetTexture(path)
                self.texture = path
            end
            function texture:SetVertexColor(r, g, b, a)
                self.vertexColor = { r = r, g = g, b = b, a = a }
            end
            function texture:SetColorTexture(r, g, b, a)
                self.color = { r = r, g = g, b = b, a = a }
            end
            function texture:Show()
                self.shown = true
            end
            function texture:Hide()
                self.shown = false
            end
            self.textures[#self.textures + 1] = texture
            return texture
        end
        function button:SetCheckedTexture(texture)
            self.checkedTexture = texture
        end
        function button:SetScript(name, handler)
            self.scripts[name] = handler
        end
        function button:HookScript(name, handler)
            self.hooks[name] = self.hooks[name] or {}
            self.hooks[name][#self.hooks[name] + 1] = handler
        end
        function button:SetSize(width, height)
            self.width = width
            self.height = height
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
        function button:GetChecked()
            return self.checked
        end
        function button:SetChecked(checked)
            self.checked = checked and true or false
        end

        return button
    end

    local function FireOnClick(box)
        for _, handler in ipairs(box.hooks.OnClick or {}) do
            handler(box)
        end
    end

    ---Native CheckButton toggles checked, then runs OnClick (and any hooks).
    local function Click(box)
        box:SetChecked(not box:GetChecked())
        FireOnClick(box)
    end

    local function Checkmark(box)
        return box.textures[3]
    end

    local function CheckmarkShadow(box)
        return box.textures[4]
    end

    local function TgaAlpha(pixels, width, height, x, y)
        -- Uncompressed TGA: bottom-up BGRA.
        local row = height - 1 - y
        local index = (row * width + x) * 4 + 4
        return pixels:byte(index)
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalHooksecurefunc = hooksecurefunc
        CreateFrame = function()
            return FakeCheckButton()
        end
        hooksecurefunc = function(target, method, hook)
            local original = target[method]
            target[method] = function(...)
                original(...)
                hook(...)
            end
        end
        ns = { ADDON_NAME = Loader.ADDON_NAME, L = {}, Util = {} }
        assert(loadfile("ui/Assets.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/Widgets.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/Checkbox.lua"))(Loader.ADDON_NAME, ns)
        Checkbox = ns.Checkbox
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        hooksecurefunc = originalHooksecurefunc
    end)

    it("ships an uncompressed 128x128 32-bit checkmark TGA with a clear margin", function()
        local file = assert(io.open("media/icons/checkmark.tga", "rb"))
        local header = file:read(18)
        local rest = file:read("*a")
        file:close()
        local width = header:byte(13) + header:byte(14) * 256
        local height = header:byte(15) + header:byte(16) * 256

        assert.equals(18, #header)
        assert.equals(2, header:byte(3))
        assert.equals(128, width)
        assert.equals(128, height)
        assert.equals(32, header:byte(17))
        assert.equals(8, header:byte(18))
        assert.equals(128 * 128 * 4, #rest)

        for x = 0, width - 1 do
            assert.equals(0, TgaAlpha(rest, width, height, x, 0))
            assert.equals(0, TgaAlpha(rest, width, height, x, height - 1))
        end
        for y = 1, height - 2 do
            assert.equals(0, TgaAlpha(rest, width, height, 0, y))
            assert.equals(0, TgaAlpha(rest, width, height, width - 1, y))
        end
    end)

    it("starts unchecked with a hollow well and a hidden breaking checkmark", function()
        local box = Checkbox.Create(FakeCheckButton())
        local Colors = ns.Assets.Colors
        local mark = Checkmark(box)
        local shadow = CheckmarkShadow(box)
        local markSize = ns.Assets.Sizes.CHECKBOX * 1.45

        assert.equals(ns.Assets.Sizes.CHECKBOX, box.width)
        assert.equals(ns.Assets.Sizes.CHECKBOX, box.height)
        assert.is_false(box.clipsChildren)
        assert(box.checkedTexture == box.textures[2], "native checked texture should stay transparent")
        assert.equals(0, box.checkedTexture.color.a)
        assert.is_false(box:GetChecked())
        assert.equals(Colors.SURFACE.r, box.fill.r)
        assert.equals(Colors.BORDER.r, box.border.r)
        assert.equals(ns.Assets.Textures.CHECKMARK, mark.texture)
        assert.equals(ns.Assets.Textures.CHECKMARK, shadow.texture)
        assert.equals(2, mark.subLevel)
        assert.equals(1, shadow.subLevel)
        assert.equals(markSize, mark.width)
        assert.equals(markSize, shadow.width)
        assert.equals(2, mark.points.CENTER.x)
        assert.equals(2, mark.points.CENTER.y)
        assert.equals("CENTER", mark.points.CENTER.relativePoint)
        assert.equals("CENTER", shadow.points.CENTER.relativePoint)
        assert(shadow.points.CENTER.relativeTo == mark, "shadow should follow the checkmark")
        assert.equals(1, shadow.points.CENTER.x)
        assert.equals(-1, shadow.points.CENTER.y)
        assert.equals(0, shadow.vertexColor.r)
        assert.equals(0.55, shadow.vertexColor.a)
        assert.is_true(mark.vertexColor.r > Colors.MENU_ACCENT.r)
        assert.is_false(mark.shown)
        assert.is_false(shadow.shown)
        assert.is_false(box.textures[1].shown)
        assert.equals(1, box.alpha)
    end)

    it("tints the well and shows the checkmark with its shadow when SetChecked", function()
        local box = Checkbox.Create(FakeCheckButton())
        local Colors = ns.Assets.Colors
        local glow = 0.18
        local mark = Checkmark(box)
        local shadow = CheckmarkShadow(box)

        box:SetChecked(true)

        assert.is_true(box:GetChecked())
        assert.equals(Colors.SURFACE.r * (1 - glow) + Colors.MENU_ACCENT.r * glow, box.fill.r)
        assert.equals(1, box.fill.a)
        assert.equals(Colors.MENU_ACCENT.r, box.border.r)
        assert.equals(0.72, box.border.a)
        assert.is_true(mark.shown)
        assert.is_true(shadow.shown)

        box:SetChecked(false)

        assert.is_false(box:GetChecked())
        assert.equals(Colors.SURFACE.r, box.fill.r)
        assert.equals(Colors.BORDER.r, box.border.r)
        assert.is_false(mark.shown)
        assert.is_false(shadow.shown)
    end)

    it("syncs chrome after a click toggles the native checked state", function()
        local box = Checkbox.Create(FakeCheckButton())
        local Colors = ns.Assets.Colors
        local mark = Checkmark(box)
        local shadow = CheckmarkShadow(box)

        Click(box)

        assert.is_true(box:GetChecked())
        assert.is_true(box.fill.r > Colors.SURFACE.r)
        assert.is_true(box.fill.r < Colors.MENU_ACCENT.r)
        assert.is_true(mark.shown)
        assert.is_true(shadow.shown)

        Click(box)

        assert.is_false(box:GetChecked())
        assert.equals(Colors.SURFACE.r, box.fill.r)
        assert.is_false(mark.shown)
        assert.is_false(shadow.shown)
    end)

    it("dims when disabled and keeps the checkmark pair visible", function()
        local box = Checkbox.Create(FakeCheckButton())
        local mark = Checkmark(box)
        local shadow = CheckmarkShadow(box)

        box:SetChecked(true)
        box:SetEnabled(false)

        assert.is_false(box:IsEnabled())
        assert.equals(0.4, box.alpha)
        assert.is_true(mark.shown)
        assert.is_true(shadow.shown)

        box:SetEnabled(true)

        assert.is_true(box:IsEnabled())
        assert.equals(1, box.alpha)
        assert.is_true(mark.shown)
        assert.is_true(shadow.shown)
    end)
end)
