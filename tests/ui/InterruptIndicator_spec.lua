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

    it("applies pale-green slice textures when that scheme is selected", function()
        local indicator = Indicator.Create(nil, Indicator.SCHEME_PALE_GREEN)
        local left, center, right = indicator.textures[1], indicator.textures[2], indicator.textures[3]
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, left.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_CENTER_PALE_GREEN, center.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_RIGHT_PALE_GREEN, right.texture)

        indicator:SetColorScheme(Indicator.SCHEME_GOLD)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_LEFT_GOLD, left.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_CENTER_GOLD, center.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_RIGHT_GOLD, right.texture)
    end)

    it("builds a three-slice chip that ignores mouse input", function()
        local indicator = Create()
        local left, center, right = indicator.textures[1], indicator.textures[2], indicator.textures[3]
        local number = indicator.fontStrings[1]
        local name = indicator.fontStrings[2]
        assert.is_false(indicator.mouseEnabled)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_LEFT_GOLD, left.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_CENTER_GOLD, center.texture)
        assert.equals(ns.Assets.Textures.INTERRUPT_INDICATOR_RIGHT_GOLD, right.texture)
        assert.equals(Indicator.HEIGHT, indicator:GetHeight())
        assert.equals(left:GetHeight(), center:GetHeight())
        assert.equals(center:GetHeight(), right:GetHeight())
        assert.equals("CENTER", number.justifyH)
        assert.equals("MIDDLE", number.justifyV)
        assert.is_false(number.wordWrap)
        assert.is_false(name.wordWrap)
        assert.equals(true, number.allPoints == left)
        assert.equals(false, left.snapToPixelGrid)
        assert.equals(0, left.texelSnappingBias)
        assert.equals(ns.Assets.FontFiles.EXPRESSWAY, number.font.path)
        assert.equals(Indicator.NUMBER_FONT_SIZE, number.font.size)
        assert.equals("", number.font.flags)
        assert.equals(Indicator.NUMBER_COLOR.r, number.color.r)
        assert.equals(Indicator.NUMBER_COLOR.g, number.color.g)
        assert.equals(Indicator.NUMBER_COLOR.b, number.color.b)
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

    it("widens the stretchable center for longer names without resizing the caps", function()
        local indicator = Create()
        indicator:SetAssignment(1, "Al", "WARRIOR")
        local left = indicator.textures[1]
        local center = indicator.textures[2]
        local right = indicator.textures[3]
        local shortCenter = center:GetWidth()
        local leftWidth = left:GetWidth()
        local rightWidth = right:GetWidth()
        local shortTotal = indicator:GetWidth()

        indicator:SetAssignment(1, "LongerName", "WARRIOR")
        assert.equals(leftWidth, left:GetWidth())
        assert.equals(rightWidth, right:GetWidth())
        assert.is_true(center:GetWidth() > shortCenter)
        assert.is_true(indicator:GetWidth() > shortTotal)
        assert.equals(Indicator.HEIGHT, indicator:GetHeight())
        assert.equals(left:GetHeight(), right:GetHeight())
    end)

    it("truncates names that exceed the maximum width", function()
        local indicator = Create()
        indicator:SetAssignment(2, string.rep("W", 40), "WARRIOR")
        local name = indicator.fontStrings[2]:GetText()
        assert.is_true(#name < 40)
        assert.equals("…", name:sub(-3))
        local maxCenter = Indicator.MAX_NAME_WIDTH + 10
        assert.is_true(indicator.textures[2]:GetWidth() <= maxCenter)
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
            assert.is_true(indicator.textures[2]:GetWidth() > 18)
        end
        MeasureWrong(0)
        MeasureWrong(8)
        MeasureWrong(1000)
    end)

    it("scales the chip uniformly without changing cap proportions", function()
        local indicator = Create()
        indicator:SetAssignment(24, "Rdu", "MAGE")
        local left = indicator.textures[1]
        local right = indicator.textures[3]
        local ratio = left:GetWidth() / right:GetWidth()
        indicator:SetScale(1.5)
        assert.equals(Indicator.HEIGHT * 1.5, indicator:GetHeight())
        assert.equals(left:GetHeight(), indicator:GetHeight())
        assert.equals(right:GetHeight(), indicator:GetHeight())
        local scaledRatio = left:GetWidth() / right:GetWidth()
        assert.is_true(math.abs(ratio - scaledRatio) < 1e-6)
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
