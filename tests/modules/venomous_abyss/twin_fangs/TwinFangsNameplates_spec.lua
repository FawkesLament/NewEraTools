local Loader = require("helpers.loader")

local HINT_PATH = "modules/venomous_abyss/twin_fangs/ui/Hint.lua"
local BADGE_PATH = "modules/venomous_abyss/twin_fangs/ui/InterruptBadge.lua"
local NAMEPLATES_PATH = "modules/venomous_abyss/twin_fangs/ui/Nameplates.lua"

local function FakeFrame(parent)
    local frame = {
        parent = parent,
        shown = true,
        points = {},
        width = 0,
        height = 0,
        mouseEnabled = true,
        wordWrap = true,
    }

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

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled == true
    end

    function frame:CreateTexture()
        local texture = FakeFrame(self)
        function texture:SetTexture(path)
            self.texture = path
        end
        self.textures = self.textures or {}
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
        self.fontString = label
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

    function frame:SetAlpha(alpha)
        self.alpha = alpha
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

describe("TwinFangs interrupt nameplate badges", function()
    local ns, Nameplate, Nameplates, Badge, Unit, TwinFangs, Schema
    local created
    local originalCreateFrame
    local originalFont

    local function LoadNameplates()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Nameplate = ns.Api.Nameplate
        Unit = ns.Api.Unit
        created = {}
        CreateFrame = function(_, _, parent)
            local frame = FakeFrame(parent)
            created[#created + 1] = frame
            return frame
        end
        assert(loadfile(HINT_PATH))(Loader.ADDON_NAME, ns)
        assert(loadfile(BADGE_PATH))(Loader.ADDON_NAME, ns)
        assert(loadfile(NAMEPLATES_PATH))(Loader.ADDON_NAME, ns)
        Badge = ns.TwinFangsInterruptBadge
        Nameplates = ns.TwinFangsNameplates
        TwinFangs = ns.Modules.Get("TwinFangs")
        Schema = ns.TwinFangsSchema
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

    local function MakePlate()
        return FakeFrame(nil)
    end

    local function Badges()
        local badges = {}
        for i = 1, #created do
            if created[i].fontString then
                badges[#badges + 1] = created[i]
            end
        end
        return badges
    end

    before_each(function()
        originalCreateFrame = CreateFrame
        originalFont = STANDARD_TEXT_FONT
        STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        LoadNameplates()
    end)

    after_each(function()
        if Nameplates then
            Nameplates.SetActive(false)
        end
        CreateFrame = originalCreateFrame
        STANDARD_TEXT_FONT = originalFont
    end)

    it("creates a compact ice-blue HUD badge with a centered ice-blue number", function()
        local badge = Badge.Create(nil)
        badge:SetNumber(24)
        local label = badge.fontString
        local background = badge.textures and badge.textures[1]
        local defaultColor = Schema.FONT_COLOR_DEFAULT
        assert.equals(24, badge:GetWidth())
        assert.equals(24, badge:GetHeight())
        assert.is_false(badge.mouseEnabled)
        assert.equals(ns.Assets.Textures.ROUNDED_SQUARE, background.texture)
        assert.equals("24", label:GetText())
        assert.equals(defaultColor.r, label.color.r)
        assert.equals(defaultColor.g, label.color.g)
        assert.equals(defaultColor.b, label.color.b)
        assert.equals("CENTER", label.justifyH)
        assert.equals("MIDDLE", label.justifyV)
        assert.equals("OUTLINE", label.font.flags)
        assert.is_true(label.allPoints == badge)
        assert.is_false(label.wordWrap)
        assert.equals(15, label.font.size)
        assert.equals(STANDARD_TEXT_FONT, label.font.path)
        assert.equals(24, badge:GetWidth())
        assert.equals(24, badge:GetHeight())
    end)

    it("resizes the background and applies a chosen font without tying size to badge size", function()
        local badge = Badge.Create(nil)
        badge:SetNumber(10)
        badge:ApplyAppearance(48, 0.5, "Fonts\\CUSTOM.TTF", 20, { r = 0, g = 1, b = 0 })
        assert.equals("10", badge.fontString:GetText())
        assert.equals(48, badge:GetWidth())
        assert.equals(48, badge:GetHeight())
        assert.equals(20, badge.fontString.font.size)
        assert.equals("Fonts\\CUSTOM.TTF", badge.fontString.font.path)
        assert.equals(0.5, badge.alpha)
        assert.equals(0, badge.fontString.color.r)
        assert.equals(1, badge.fontString.color.g)
        assert.equals(0, badge.fontString.color.b)
        badge:ApplyAppearance(24, 1)
        assert.equals(24, badge:GetWidth())
        assert.equals(15, badge.fontString.font.size)
        assert.equals(STANDARD_TEXT_FONT, badge.fontString.font.path)
        assert.equals(1, badge.alpha)
        local defaultColor = Schema.FONT_COLOR_DEFAULT
        assert.equals(defaultColor.r, badge.fontString.color.r)
        assert.equals(defaultColor.g, badge.fontString.color.g)
        assert.equals(defaultColor.b, badge.fontString.color.b)
    end)

    it("uses the client font when the saved font id is default or unknown", function()
        local badge = Badge.Create(nil)
        badge:ApplyAppearance(24, 1, ns.SharedMedia.ResolveFontPath("default") or STANDARD_TEXT_FONT, 15)
        assert.equals(STANDARD_TEXT_FONT, badge.fontString.font.path)
        badge:ApplyAppearance(24, 1, ns.SharedMedia.ResolveFontPath("Missing") or STANDARD_TEXT_FONT, 15)
        assert.equals(STANDARD_TEXT_FONT, badge.fontString.font.path)
    end)

    it("anchors a badge to the left of a visible Blizzard nameplate", function()
        local plate = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        Nameplates.SetActive(true)

        local badges = Badges()
        assert.equals(1, #badges)
        local badge = badges[1]
        assert.equals(plate, badge.parent)
        assert.is_true(badge:IsShown())
        assert.equals(1, #badge.points)
        assert.equals("RIGHT", badge.points[1].point)
        assert.equals(plate, badge.points[1].relativeTo)
        assert.equals("LEFT", badge.points[1].relativePoint)
        assert.equals(-7, badge.points[1].x)
        assert.equals(0, badge.points[1].y)
        assert.equals("24", badge.fontString:GetText())
    end)

    it("attaches, hides, and reuses badges as nameplates appear, disappear, and recycle", function()
        Nameplates.SetActive(true)
        local plateA = MakePlate()
        local plateB = MakePlate()
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", true)
        Nameplate.FireAdded("nameplate1", plateA)
        Nameplate.FireAdded("nameplate2", plateB)
        local badges = Badges()
        assert.equals(2, #badges)
        assert.equals(plateA, badges[1].parent)
        assert.equals(plateB, badges[2].parent)

        Nameplate.FireRemoved("nameplate1")
        assert.is_false(badges[1]:IsShown())
        assert.is_true(badges[1].parent ~= plateA)
        assert.is_true(badges[2]:IsShown())
        assert.equals(plateB, badges[2].parent)

        local recycled = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", recycled)
        assert.equals(2, #Badges())
        assert.equals(recycled, badges[1].parent)
        assert.is_true(badges[1]:IsShown())
        assert.equals(plateB, badges[2].parent)
    end)

    it("does not create extra badges when the same unit is added twice", function()
        Nameplates.SetActive(true)
        local plate = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        Nameplate.FireAdded("nameplate1", plate)
        assert.equals(1, #Badges())
    end)

    it("releases every badge when disabled and ignores later nameplate events", function()
        local plate = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        Nameplates.SetActive(true)
        local badges = Badges()
        assert.equals(1, #badges)
        assert.is_true(badges[1]:IsShown())

        Nameplates.SetActive(false)
        assert.is_false(badges[1]:IsShown())

        SetEnemy("nameplate2", true)
        Nameplate.FireAdded("nameplate2", MakePlate())
        assert.equals(1, #Badges())
    end)

    it("attaches only to enemy nameplates", function()
        Nameplates.SetActive(true)
        local enemy = MakePlate()
        local friend = MakePlate()
        SetEnemy("nameplate1", true)
        SetEnemy("nameplate2", false)
        Nameplate.FireAdded("nameplate1", enemy)
        Nameplate.FireAdded("nameplate2", friend)
        Nameplate.FireAdded("nameplate3", MakePlate())
        local badges = Badges()
        assert.equals(1, #badges)
        assert.equals(enemy, badges[1].parent)
        assert.is_true(badges[1]:IsShown())
    end)

    it("drops a badge when a recycled nameplate becomes friendly", function()
        Nameplates.SetActive(true)
        local plate = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        local badges = Badges()
        assert.equals(1, #badges)
        assert.is_true(badges[1]:IsShown())

        Nameplate.FireRemoved("nameplate1")
        SetEnemy("nameplate1", false)
        Nameplate.FireAdded("nameplate1", plate)
        assert.equals(1, #Badges())
        assert.is_false(badges[1]:IsShown())
        assert.is_true(badges[1].parent ~= plate)
    end)

    local function ShownBadge(plate)
        Nameplates.SetActive(true)
        SetEnemy("nameplate1", true)
        Nameplate.FireAdded("nameplate1", plate)
        local badges = Badges()
        assert.equals(1, #badges)
        return badges[1]
    end

    it("keeps the default left gap when appearance settings are unchanged", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        assert.equals(24, badge:GetWidth())
        assert.equals(24, badge:GetHeight())
        assert.equals(1, badge.alpha)
        assert.equals("RIGHT", badge.points[1].point)
        assert.equals("LEFT", badge.points[1].relativePoint)
        assert.equals(-7, badge.points[1].x)
        assert.equals(0, badge.points[1].y)
    end)

    it("anchors on the right, top, or bottom of the Blizzard nameplate", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)

        TwinFangs:SetNameplateHintSide(Schema.SIDE_RIGHT)
        assert.equals("LEFT", badge.points[1].point)
        assert.equals("RIGHT", badge.points[1].relativePoint)
        assert.equals(7, badge.points[1].x)
        assert.equals(0, badge.points[1].y)

        TwinFangs:SetNameplateHintSide(Schema.SIDE_TOP)
        assert.equals("BOTTOM", badge.points[1].point)
        assert.equals("TOP", badge.points[1].relativePoint)
        assert.equals(0, badge.points[1].x)
        assert.equals(7, badge.points[1].y)

        TwinFangs:SetNameplateHintSide(Schema.SIDE_BOTTOM)
        assert.equals("TOP", badge.points[1].point)
        assert.equals("BOTTOM", badge.points[1].relativePoint)
        assert.equals(0, badge.points[1].x)
        assert.equals(-7, badge.points[1].y)
        assert.equals(1, #Badges())
    end)

    it("applies saved offsets after the chosen side", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        TwinFangs:SetNameplateHintOffsetX(10)
        TwinFangs:SetNameplateHintOffsetY(-5)
        assert.equals(-7 + 10, badge.points[1].x)
        assert.equals(0 - 5, badge.points[1].y)

        TwinFangs:SetNameplateHintSide(Schema.SIDE_RIGHT)
        assert.equals(7 + 10, badge.points[1].x)
        assert.equals(0 - 5, badge.points[1].y)
    end)

    it("resizes live badges without changing the saved font size", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        TwinFangs:SetNameplateHintSize(40)
        assert.equals(40, badge:GetWidth())
        assert.equals(40, badge:GetHeight())
        assert.equals(15, badge.fontString.font.size)
        assert.equals("24", badge.fontString:GetText())
        TwinFangs:SetNameplateHintSize(64)
        assert.equals(64, badge:GetWidth())
        assert.equals(15, badge.fontString.font.size)
        assert.equals("24", badge.fontString:GetText())
    end)

    it("applies saved opacity to live badges", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        TwinFangs:SetNameplateHintOpacity(0.3)
        assert.equals(0.3, badge.alpha)
    end)

    it("applies saved font size to live badges", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        TwinFangs:SetNameplateHintFontSize(22)
        assert.equals(22, badge.fontString.font.size)
        assert.equals(STANDARD_TEXT_FONT, badge.fontString.font.path)
    end)

    it("applies saved font color to live badges", function()
        local plate = MakePlate()
        local badge = ShownBadge(plate)
        TwinFangs:SetNameplateHintFontColor({ r = 1, g = 0, b = 0 })
        assert.equals(1, badge.fontString.color.r)
        assert.equals(0, badge.fontString.color.g)
        assert.equals(0, badge.fontString.color.b)
        assert.equals(1, badge.fontString.color.a)
    end)

    it("does not attach badges when the hint is enabled without a preview", function()
        local plate = MakePlate()
        SetEnemy("nameplate1", true)
        Nameplate.visible[1] = { unit = "nameplate1", frame = plate }
        Nameplate.frames.nameplate1 = plate
        TwinFangs:SetNameplateHintEnabled(true)
        assert.equals(0, #Badges())

        TwinFangs:SetNameplateHintPreviewing(true)
        local badges = Badges()
        assert.equals(1, #badges)
        assert.equals(plate, badges[1].parent)
        assert.is_true(badges[1]:IsShown())

        TwinFangs:SetNameplateHintEnabled(false)
        assert.is_false(TwinFangs:IsNameplateHintPreviewing())
        assert.is_false(badges[1]:IsShown())
    end)

    it("does not create badges when appearance changes while inactive", function()
        TwinFangs:SetNameplateHintSize(40)
        TwinFangs:SetNameplateHintSide(Schema.SIDE_RIGHT)
        assert.equals(0, #Badges())
        Nameplates.Refresh()
        assert.equals(0, #Badges())
    end)
end)
