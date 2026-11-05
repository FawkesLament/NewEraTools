local Loader = require("helpers.loader")

local INDICATOR_PATH = "ui/InterruptIndicator.lua"
local NAMEPLATES_PATH = "modules/venomous_abyss/coiled_altar/ui/Nameplates.lua"

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
        function texture:SetSnapToPixelGrid() end
        function texture:SetTexelSnappingBias() end
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

describe("CoiledAltar interrupt nameplate indicators", function()
    local ns, Nameplate, Unit, CoiledAltar, Nameplates, originalCreateFrame, originalFont, originalRandom, created

    local function LoadNameplates()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Nameplate = ns.Api.Nameplate
        Unit = ns.Api.Unit
        CoiledAltar = ns.Modules.Get("CoiledAltar")
        created = {}
        CreateFrame = function(_, _, parent)
            local frame = FakeFrame(parent)
            created[#created + 1] = frame
            return frame
        end
        assert(loadfile(INDICATOR_PATH))(Loader.ADDON_NAME, ns)
        assert(loadfile(NAMEPLATES_PATH))(Loader.ADDON_NAME, ns)
        Nameplates = ns.Modules.Internals("CoiledAltar").Nameplates
    end

    local function SetEnemy(unit, enemy)
        if enemy then
            Unit.SetForTests(unit, {
                exists = true,
                guid = "Creature-" .. unit,
                canAssist = false,
                canAttack = true,
            })
        else
            Unit.SetForTests(unit, {
                exists = true,
                guid = "Player-" .. unit,
                canAssist = true,
                canAttack = false,
            })
        end
    end

    local function Indicators()
        local list = {}
        for i = 1, #created do
            if created[i].SetAssignment then
                list[#list + 1] = created[i]
            end
        end
        return list
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalFont = STANDARD_TEXT_FONT
        originalRandom = math.random
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        LoadNameplates()
    end)

    after_each(function()
        if CoiledAltar then
            CoiledAltar:SetNameplateHintPreviewing(false)
            CoiledAltar:SetNameplateHintEnabled(false)
        end
        CreateFrame = originalCreateFrame
        STANDARD_TEXT_FONT = originalFont
        math.random = originalRandom
    end)

    local function StartPreview()
        CoiledAltar:SetNameplateHintEnabled(true)
        CoiledAltar:SetNameplateHintPreviewing(true)
    end

    it("previews sequence 24 and the local player name on visible enemy nameplates", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        StartPreview()

        local indicators = Indicators()
        assert.equals(1, #indicators)
        local indicator = indicators[1]
        assert.equals(plate, indicator.parent)
        assert.is_true(indicator:IsShown())
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals("You", indicator.fontStrings[2]:GetText())
        assert.equals(0.78, indicator.fontStrings[2].color.r)
        assert.equals("TOP", indicator.points[1].point)
        assert.equals(plate, indicator.points[1].relativeTo)
        assert.equals("BOTTOM", indicator.points[1].relativePoint)
        assert.is_false(indicator.mouseEnabled)
    end)

    it("attaches, hides, and reuses indicators as nameplates appear, disappear, and recycle", function()
        StartPreview()
        local plateA = FakeFrame(nil)
        local plateB = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", true)
        Nameplate.FireAdded("nameplate1", plateA)
        Nameplate.FireAdded("nameplate2", plateB)
        local indicators = Indicators()
        assert.equals(2, #indicators)
        assert.equals(plateA, indicators[1].parent)
        assert.equals(plateB, indicators[2].parent)

        Nameplate.FireRemoved("nameplate1")
        assert.is_false(indicators[1]:IsShown())
        assert.is_true(indicators[1].parent ~= plateA)
        assert.is_true(indicators[2]:IsShown())
        assert.equals(plateB, indicators[2].parent)

        local recycled = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", recycled)
        assert.equals(2, #Indicators())
        assert.equals(recycled, indicators[1].parent)
        assert.is_true(indicators[1]:IsShown())
        assert.equals(plateB, indicators[2].parent)
    end)

    it("picks a random color scheme only when a preview indicator is first attached", function()
        local rolls = { 2, 1, 2 }
        local index = 0
        math.random = function(n)
            assert.equals(2, n)
            index = index + 1
            return rolls[index]
        end

        StartPreview()
        local plateA = FakeFrame(nil)
        local plateB = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", true)
        Nameplate.FireAdded("nameplate1", plateA)
        Nameplate.FireAdded("nameplate2", plateB)
        local indicators = Indicators()
        local textures = ns.Assets.Textures
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, indicators[1].textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_CENTER_PALE_GREEN, indicators[1].textures[2].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_RIGHT_PALE_GREEN, indicators[1].textures[3].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_GOLD, indicators[2].textures[1].texture)
        assert.equals(2, index)

        Nameplate.FireAdded("nameplate1", plateA)
        CoiledAltar:SetNameplateHintScale(1.25)
        assert.equals(2, index)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, indicators[1].textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_GOLD, indicators[2].textures[1].texture)

        Nameplate.FireRemoved("nameplate1")
        local recycled = FakeFrame(nil)
        Nameplate.FireAdded("nameplate1", recycled)
        assert.equals(3, index)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, indicators[1].textures[1].texture)
    end)

    it("uses the gold scheme for live assignments", function()
        math.random = function()
            return 2
        end
        StartPreview()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.frames.nameplate1 = plate
        Nameplate.FireAdded("nameplate1", plate)
        local textures = ns.Assets.Textures
        local indicator = Indicators()[1]
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, indicator.textures[1].texture)

        CoiledAltar:SetNameplateHintPreviewing(false)
        math.random = function()
            error("live assignments must not roll a preview color")
        end
        Nameplates.Show("nameplate1", 4, "Rdu", "MAGE")
        assert.equals(1, #Indicators())
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_GOLD, indicator.textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_CENTER_GOLD, indicator.textures[2].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_RIGHT_GOLD, indicator.textures[3].texture)
    end)

    it("does not create extra indicators when the same unit is added twice", function()
        StartPreview()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        Nameplate.FireAdded("nameplate1", plate)
        assert.equals(1, #Indicators())
    end)

    it("releases every indicator when preview ends and ignores later nameplate events", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        StartPreview()
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.is_true(indicators[1]:IsShown())

        CoiledAltar:SetNameplateHintPreviewing(false)
        assert.is_false(indicators[1]:IsShown())

        SetEnemy("nameplate2", true)
        Nameplate.FireAdded("nameplate2", FakeFrame(nil))
        assert.equals(1, #Indicators())
    end)

    it("attaches only to enemy nameplates", function()
        StartPreview()
        local enemy = FakeFrame(nil)
        local friend = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", false)
        Nameplate.FireAdded("nameplate1", enemy)
        Nameplate.FireAdded("nameplate2", friend)
        Nameplate.FireAdded("nameplate3", FakeFrame(nil))
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.equals(enemy, indicators[1].parent)
        assert.is_true(indicators[1]:IsShown())
    end)

    it("applies appearance changes to the active preview immediately", function()
        StartPreview()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        local indicator = Indicators()[1]
        local defaultHeight = indicator:GetHeight()
        CoiledAltar:SetNameplateHintNumberFontSize(18)
        CoiledAltar:SetNameplateHintNameFontSize(9)
        assert.equals(18, indicator.fontStrings[1].font.size)
        assert.equals(9, indicator.fontStrings[2].font.size)
        CoiledAltar:SetNameplateHintScale(1.5)
        assert.equals(defaultHeight * 1.5, indicator:GetHeight())
        assert.equals(27, indicator.fontStrings[1].font.size)
        assert.equals(13.5, indicator.fontStrings[2].font.size)
        CoiledAltar:SetNameplateHintOffsetX(10)
        CoiledAltar:SetNameplateHintOffsetY(-6)
        assert.equals(10, indicator.points[1].x)
        assert.equals(-ns.InterruptIndicator.GAP - 6, indicator.points[1].y)
        CoiledAltar:SetNameplateHintSide(CoiledAltar.SIDE_TOP)
        assert.equals("BOTTOM", indicator.points[1].point)
        assert.equals("TOP", indicator.points[1].relativePoint)
        assert.equals(10, indicator.points[1].x)
        assert.equals(ns.InterruptIndicator.GAP - 6, indicator.points[1].y)
        assert.equals(1, #Indicators())
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals(0.78, indicator.fontStrings[2].color.r)
    end)

    it("does not attach indicators when the hint is enabled without a preview", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        CoiledAltar:SetNameplateHintEnabled(true)
        assert.equals(0, #Indicators())

        CoiledAltar:SetNameplateHintPreviewing(true)
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.is_true(indicators[1]:IsShown())

        CoiledAltar:SetNameplateHintEnabled(false)
        assert.is_false(CoiledAltar:IsNameplateHintPreviewing())
        assert.is_false(indicators[1]:IsShown())
    end)

    it("does not let a live assign overwrite a preview indicator", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        StartPreview()
        local indicator = Indicators()[1]
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals("You", indicator.fontStrings[2]:GetText())

        Nameplates.Show("nameplate1", 3, "Other", "MAGE")
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals("You", indicator.fontStrings[2]:GetText())
        Nameplates.Hide("nameplate1")
        assert.is_true(indicator:IsShown())
        Nameplates.Clear()
        assert.is_true(indicator:IsShown())
    end)

    it("attaches a live assignment and keeps it when appearance changes", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.frames.nameplate1 = plate
        Nameplates.Show("nameplate1", 4, "Rdu", "MAGE")
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.equals("4", indicators[1].fontStrings[1]:GetText())
        assert.equals("Rdu", indicators[1].fontStrings[2]:GetText())
        assert.equals(plate, indicators[1].parent)
        assert.is_true(indicators[1]:IsShown())

        CoiledAltar:SetNameplateHintScale(1.5)
        CoiledAltar:SetNameplateHintOffsetX(8)
        assert.equals(1, #Indicators())
        assert.equals("4", indicators[1].fontStrings[1]:GetText())
        assert.equals("Rdu", indicators[1].fontStrings[2]:GetText())
        assert.equals(ns.InterruptIndicator.HEIGHT * 1.5, indicators[1]:GetHeight())
        assert.equals(8, indicators[1].points[1].x)
    end)

    it("applies live views without recreating unchanged indicators", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.frames.nameplate1 = plate
        Nameplates.Apply({
            nameplate1 = { number = 1, name = "待标记" },
        })
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.equals("1", indicators[1].fontStrings[1]:GetText())
        assert.equals("待标记", indicators[1].fontStrings[2]:GetText())
        local first = indicators[1]

        Nameplates.Apply({
            nameplate1 = { number = 1, name = "待标记" },
        })
        assert.equals(1, #Indicators())
        assert(first == Indicators()[1], "unchanged views must reuse the existing indicator")

        Nameplates.Apply({
            nameplate1 = { number = 2, name = "MeleeTwo" },
        })
        assert.equals(1, #Indicators())
        assert(first == Indicators()[1], "bound updates must reuse the existing indicator")
        assert.equals("2", first.fontStrings[1]:GetText())
        assert.equals("MeleeTwo", first.fontStrings[2]:GetText())
    end)

    it("colors live indicators pale green for melee and gold when ranged or the chain is unknown", function()
        local textures = ns.Assets.Textures
        local ranged = FakeFrame(nil)
        local melee = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", true)
        Nameplate.frames.nameplate1 = ranged
        Nameplate.frames.nameplate2 = melee
        Nameplates.Apply({
            nameplate1 = { number = 1, name = "待标记", scheme = ns.InterruptIndicator.SCHEME_GOLD },
            nameplate2 = { number = 1, name = "MeleeOne", scheme = ns.InterruptIndicator.SCHEME_PALE_GREEN },
        })
        local function IndicatorOn(plate)
            local list = Indicators()
            for i = 1, #list do
                if list[i].parent == plate then
                    return list[i]
                end
            end
            return nil
        end
        local gold = IndicatorOn(ranged)
        local green = IndicatorOn(melee)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_GOLD, gold.textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, green.textures[1].texture)

        Nameplates.Apply({
            nameplate1 = { number = 1, name = "RangeOne", scheme = ns.InterruptIndicator.SCHEME_GOLD },
            nameplate2 = { number = 1, name = "MeleeOne", scheme = ns.InterruptIndicator.SCHEME_PALE_GREEN },
        })
        assert.equals(2, #Indicators())
        assert(gold == IndicatorOn(ranged), "ranged indicator must be reused")
        assert(green == IndicatorOn(melee), "melee indicator must be reused")
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_GOLD, gold.textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_CENTER_GOLD, gold.textures[2].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_LEFT_PALE_GREEN, green.textures[1].texture)
        assert.equals(textures.INTERRUPT_INDICATOR_CENTER_PALE_GREEN, green.textures[2].texture)
    end)

    it("hides a live indicator as soon as its nameplate is removed", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.frames.nameplate1 = plate
        Nameplates.Apply({
            nameplate1 = { number = 1, name = "待标记" },
        })
        local indicator = Indicators()[1]
        assert.is_true(indicator:IsShown())
        Nameplate.FireRemoved("nameplate1")
        assert.is_false(indicator:IsShown())
        Nameplates.Apply({})
        assert.is_false(indicator:IsShown())
    end)

    it("does not let live combat views overwrite a menu preview", function()
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        StartPreview()
        local indicator = Indicators()[1]
        assert.equals("24", indicator.fontStrings[1]:GetText())
        Nameplates.Apply({
            nameplate1 = { number = 1, name = "待标记" },
        })
        assert.equals("24", indicator.fontStrings[1]:GetText())
        assert.equals("You", indicator.fontStrings[2]:GetText())
        assert.is_true(indicator:IsShown())
    end)

    it("clears live indicators when the encounter ends without changing preview settings", function()
        CoiledAltar:SetNameplateHintEnabled(true)
        local plate = FakeFrame(nil)
        SetEnemy("nameplate1", true)
        Nameplate.frames.nameplate1 = plate
        assert.is_true(CoiledAltar:AssignInterruptPlayer("MELEE", 1, "PlayerA"))
        CoiledAltar:ListenForEncounter()
        ns.Api.Encounter.FireStart(CoiledAltar.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
        Unit.SetForTests("boss3", { exists = true })
        Unit.SetForTests("boss4", { exists = true })
        ns.Api.Encounter.FireEngageUnit()
        ns.Api.Timer.Advance(0)
        Unit.SetForTests("nameplate1", { exists = true, level = 92, canAttack = true, canAssist = false })
        ns.Api.Nameplate.FireAdded("nameplate1", plate)
        ns.Api.Timer.Advance(0)
        local indicators = Indicators()
        assert.equals(1, #indicators)
        assert.is_true(indicators[1]:IsShown())
        assert.equals("1", indicators[1].fontStrings[1]:GetText())

        ns.Api.Encounter.FireEnd(CoiledAltar.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
        assert.is_false(indicators[1]:IsShown())
        assert.is_true(CoiledAltar:IsNameplateHintEnabled())
        assert.is_false(CoiledAltar:IsNameplateHintPreviewing())
    end)
end)
