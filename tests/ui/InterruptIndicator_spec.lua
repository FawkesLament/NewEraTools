local Loader = require("helpers.loader")

local INDICATOR_PATH = "ui/InterruptIndicator.lua"

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        shown = true,
        points = {},
        width = 0,
        height = 0,
        mouseEnabled = true,
        textures = {},
        fontStrings = {},
    }

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetWidth(width)
        self.width = width
    end

    function frame:GetWidth()
        return self.width
    end

    function frame:GetHeight()
        return self.height
    end

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled == true
    end

    function frame:CreateTexture()
        local texture = FakeFrame(self)
        function texture:SetTexture(path)
            self.texture = path
        end
        function texture:SetColorTexture(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:SetVertexColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function texture:SetSnapToPixelGrid(enabled)
            self.snapToPixelGrid = enabled == true
        end
        function texture:SetTexelSnappingBias(bias)
            self.texelSnappingBias = bias
        end
        self.textures[#self.textures + 1] = texture
        return texture
    end

    function frame:CreateFontString()
        local label = FakeFrame(self)
        function label:SetFont(path, size, flags)
            self.font = { path = path, size = size, flags = flags }
        end
        function label:SetTextColor(r, g, b, a)
            self.color = { r = r, g = g, b = b, a = a }
        end
        function label:SetText(text)
            self.text = text
        end
        function label:GetText()
            return self.text
        end
        function label:GetStringWidth()
            return #(self.text or "") * 6
        end
        function label:GetUnboundedStringWidth()
            return self:GetStringWidth()
        end
        function label:SetJustifyH(justify)
            self.justifyH = justify
        end
        function label:SetJustifyV(justify)
            self.justifyV = justify
        end
        function label:SetWordWrap(enabled)
            self.wordWrap = enabled == true
        end
        function label:SetShadowOffset() end
        function label:SetShadowColor() end
        self.fontStrings[#self.fontStrings + 1] = label
        return label
    end

    function frame:SetParent(parentFrame)
        self.parent = parentFrame
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end

    function frame:SetAllPoints(relativeTo)
        self.allPoints = relativeTo or self.parent
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

describe("InterruptIndicator", function()
    local ns, Indicator, originalCreateFrame, originalFont

    local function LoadIndicator()
        ns = Loader.Load()
        CreateFrame = function(_, _, parent)
            return FakeFrame(parent)
        end
        assert(loadfile(INDICATOR_PATH))(Loader.ADDON_NAME, ns)
        Indicator = ns.InterruptIndicator
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalFont = STANDARD_TEXT_FONT
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        LoadIndicator()
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        STANDARD_TEXT_FONT = originalFont
    end)

    local function Create()
        return Indicator.Create(nil)
    end

    local GOLD_FILL = { r = 1.0, g = 0.78, b = 0.0, a = 1.0 }
    local GREEN_FILL = { r = 0.56, g = 0.90, b = 0.56, a = 1.0 }

    local function AssertColor(actual, expected)
        assert.equals(expected.r, actual.r)
        assert.equals(expected.g, actual.g)
        assert.equals(expected.b, actual.b)
        assert.equals(expected.a, actual.a)
    end

    it("applies pale-green badge fill when that scheme is selected", function()
        local indicator = Indicator.Create(nil, Indicator.SCHEME_PALE_GREEN)
        local border, fill = indicator.textures[1], indicator.textures[2]
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_BADGE_BORDER, border.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_BADGE_FILL, fill.texture)
        AssertColor(border.color, { r = 0, g = 0, b = 0, a = 0.95 })
        AssertColor(fill.color, GREEN_FILL)

        indicator:SetColorScheme(Indicator.SCHEME_GOLD)
        AssertColor(border.color, { r = 0, g = 0, b = 0, a = 0.95 })
        AssertColor(fill.color, GOLD_FILL)
    end)

    it("builds a square badge chip that ignores mouse input", function()
        local indicator = Create()
        local border, fill = indicator.textures[1], indicator.textures[2]
        local number = indicator.fontStrings[1]
        local name = indicator.fontStrings[2]
        assert.is_false(indicator.mouseEnabled)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_BADGE_BORDER, border.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_BADGE_FILL, fill.texture)
        AssertColor(border.color, { r = 0, g = 0, b = 0, a = 0.95 })
        AssertColor(fill.color, GOLD_FILL)
        assert.equals(Indicator.HEIGHT, indicator:GetHeight())
        assert.equals(Indicator.HEIGHT, border:GetWidth())
        assert.equals(Indicator.HEIGHT, border:GetHeight())
        assert.equals("CENTER", number.justifyH)
        assert.equals("MIDDLE", number.justifyV)
        assert.is_false(number.wordWrap)
        assert.is_false(name.wordWrap)
        assert.equals(true, number.allPoints == border)
        assert.equals(true, fill.allPoints == border)
        assert.equals(false, border.snapToPixelGrid)
        assert.equals(0, border.texelSnappingBias)
        assert.equals(false, fill.snapToPixelGrid)
        assert.equals(ns.Assets.FontFiles.EXPRESSWAY, number.font.path)
        assert.equals(Indicator.NUMBER_FONT_SIZE, number.font.size)
        assert.equals("", number.font.flags)
        assert.equals(Indicator.NUMBER_COLOR.r, number.color.r)
        assert.equals(Indicator.NUMBER_COLOR.g, number.color.g)
        assert.equals(Indicator.NUMBER_COLOR.b, number.color.b)
        assert.equals("OUTLINE", name.font.flags)
    end)

    it("scales independent number and name font sizes with the chip", function()
        local indicator = Create()
        indicator:SetNumberFontSize(18)
        indicator:SetNameFontSize(9)
        indicator:SetAssignment(1, "Rdu", "MAGE")
        assert.equals(18, indicator.fontStrings[1].font.size)
        assert.equals(9, indicator.fontStrings[2].font.size)
        indicator:SetScale(2)
        assert.equals(36, indicator.fontStrings[1].font.size)
        assert.equals(18, indicator.fontStrings[2].font.size)
    end)

    it("renders a sequence number and a player name", function()
        local indicator = Create()
        indicator:SetAssignment(24, "Rdu", "MAGE")
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals("Rdu", indicator.fontStrings[2]:GetText())
        local color = indicator.fontStrings[2].color
        assert.equals(0.78, color.r)
        assert.equals(0.61, color.g)
        assert.equals(0.43, color.b)
    end)

    it("uses gold for custom assignment text", function()
        local indicator = Create()
        local gold = ns.Assets.Colors.TEXT_GOLD
        indicator:SetAssignment(1, "点名近战", nil, gold)
        local color = indicator.fontStrings[2].color
        assert.equals(gold.r, color.r)
        assert.equals(gold.g, color.g)
        assert.equals(gold.b, color.b)
    end)

    it("widens the chip for longer names without resizing the square badge", function()
        local indicator = Create()
        indicator:SetAssignment(1, "Al", "WARRIOR")
        local badge = indicator.textures[1]
        local badgeWidth = badge:GetWidth()
        local badgeHeight = badge:GetHeight()
        local shortTotal = indicator:GetWidth()

        indicator:SetAssignment(1, "LongerName", "WARRIOR")
        assert.equals(badgeWidth, badge:GetWidth())
        assert.equals(badgeHeight, badge:GetHeight())
        assert.equals(badge:GetWidth(), badge:GetHeight())
        assert.is_true(indicator:GetWidth() > shortTotal)
        assert.equals(Indicator.HEIGHT, indicator:GetHeight())
        assert.equals(Indicator.HEIGHT + 5 + indicator.fontStrings[2]:GetUnboundedStringWidth(), indicator:GetWidth())
    end)

    it("truncates names that exceed the maximum width", function()
        local indicator = Create()
        indicator:SetAssignment(2, string.rep("W", 40), "WARRIOR")
        local name = indicator.fontStrings[2]:GetText()
        assert.is_true(#name < 40)
        assert.equals("…", name:sub(-3))
        local maxWidth = Indicator.HEIGHT + 5 + Indicator.MAX_NAME_WIDTH
        assert.is_true(indicator:GetWidth() <= maxWidth)
    end)

    it("keeps the full name when measured width is not plausible", function()
        local indicator = Create()
        local name = indicator.fontStrings[2]
        local function MeasureWrong(width)
            function name:GetStringWidth()
                return width
            end
            function name:GetUnboundedStringWidth()
                return width
            end
            indicator:SetAssignment(1, "Rdu", "MAGE")
            assert.equals("Rdu", name:GetText())
            assert.is_true(indicator:GetWidth() > Indicator.HEIGHT)
        end
        MeasureWrong(0)
        MeasureWrong(8)
        MeasureWrong(1000)
    end)

    it("scales the square badge uniformly", function()
        local indicator = Create()
        indicator:SetAssignment(24, "Rdu", "MAGE")
        local badge = indicator.textures[1]
        assert.equals(badge:GetWidth(), badge:GetHeight())
        indicator:SetScale(1.5)
        assert.equals(Indicator.HEIGHT * 1.5, indicator:GetHeight())
        assert.equals(badge:GetHeight(), indicator:GetHeight())
        assert.equals(badge:GetWidth(), badge:GetHeight())
        assert.equals(true, indicator.textures[2].allPoints == badge)
    end)

    it("anchors below a nameplate, or its cast bar when that child exists", function()
        local plate = FakeFrame(nil)
        local indicator = Create()
        indicator:SetAssignment(24, "Rdu", "MAGE")
        indicator:Attach(plate)
        assert.is_true(indicator.parent == plate)
        assert.is_true(indicator:IsShown())
        assert.equals(1, #indicator.points)
        assert.equals("TOP", indicator.points[1].point)
        assert.is_true(indicator.points[1].relativeTo == plate)
        assert.equals("BOTTOM", indicator.points[1].relativePoint)
        assert.equals(0, indicator.points[1].x)
        assert.equals(-Indicator.GAP, indicator.points[1].y)

        local castBar = FakeFrame(plate)
        plate.UnitFrame = { castBar = castBar }
        indicator:SetOffset(10, -5)
        assert.equals(1, #indicator.points)
        assert.is_true(indicator.points[1].relativeTo == castBar)
        assert.equals(10, indicator.points[1].x)
        assert.equals(-Indicator.GAP - 5, indicator.points[1].y)

        indicator:SetSide(Indicator.SIDE_TOP)
        assert.equals(1, #indicator.points)
        assert.equals("BOTTOM", indicator.points[1].point)
        assert.is_true(indicator.points[1].relativeTo == plate)
        assert.equals("TOP", indicator.points[1].relativePoint)
        assert.equals(10, indicator.points[1].x)
        assert.equals(Indicator.GAP - 5, indicator.points[1].y)
    end)

    it("does not accumulate texture or name anchors across assignment updates", function()
        local indicator = Create()
        indicator:SetAssignment(1, "Al", "WARRIOR")
        local leftPoints = #indicator.textures[1].points
        local namePoints = #indicator.fontStrings[2].points
        indicator:SetAssignment(2, "LongerName", "WARRIOR")
        indicator:SetAssignment(3, "Al", "WARRIOR")
        assert.equals(leftPoints, #indicator.textures[1].points)
        assert.equals(namePoints, #indicator.fontStrings[2].points)
    end)
end)
