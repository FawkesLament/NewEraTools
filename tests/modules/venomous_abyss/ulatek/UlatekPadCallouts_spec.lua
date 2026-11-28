local Loader = require("helpers.loader")

describe("Ulatek tactical pad callout buttons", function()
    local ns, Map, Combat
    local originalCreateFrame
    local originalGameTooltip
    local regions
    local protectedSetPoints

    local function MakeRegion(kind, template)
        local region = {
            kind = kind,
            template = template,
            protected = type(template) == "string" and template:find("SecureActionButton", 1, true) ~= nil,
            attributes = {},
            setPointCount = 0,
            shown = true,
        }
        if region.protected then
            function region:IsProtected()
                return true
            end
        end
        function region:SetPoint(...)
            if self.protected and Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Button:SetPoint()", 2)
            end
            self.setPointCount = self.setPointCount + 1
            if self.protected then
                protectedSetPoints = protectedSetPoints + 1
            end
            local x, y = select(4, ...)
            self.anchorX = x
            self.anchorY = y
        end
        function region:SetShown(shown)
            if self.protected and Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Button:SetShown()", 2)
            end
            self.shown = shown and true or false
        end
        function region:Show()
            self:SetShown(true)
        end
        function region:Hide()
            self:SetShown(false)
        end
        function region:SetAttribute(key, value)
            if self.protected and Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Button:SetAttribute()", 2)
            end
            self.attributes[key] = value
        end
        function region:RegisterForClicks(...)
            self.clicks = { ... }
        end
        function region:SetSize(width, height)
            if self.protected and Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Button:SetSize()", 2)
            end
            self.width = width
            self.height = height
        end
        function region:GetFrameLevel()
            return self.frameLevel or 1
        end
        function region:SetFrameLevel(level)
            self.frameLevel = level
        end
        function region:EnableMouse(enabled)
            self.mouseEnabled = enabled == true
        end
        function region:SetAllPoints()
            self.allPoints = true
        end
        function region:SetHeight(height)
            self.height = height
        end
        function region:SetMinMaxValues(minValue, maxValue)
            self.minValue = minValue
            self.maxValue = maxValue
        end
        function region:SetValue(value)
            self.value = value
        end
        function region:SetStatusBarTexture(path)
            self.statusBarTexture = path
        end
        function region:SetStatusBarColor(r, g, b, a)
            self.barR, self.barG, self.barB, self.barA = r, g, b, a
        end
        function region:SetSnapToPixelGrid(enabled)
            self.snapToPixelGrid = enabled == true
        end
        function region:SetTexelSnappingBias(bias)
            self.texelSnappingBias = bias
        end
        function region:SetAlpha(alpha)
            self.alpha = alpha
        end
        function region:HookScript(script, handler)
            self.hooks = self.hooks or {}
            self.hooks[script] = handler
        end
        function region:CreateTexture()
            local texture = MakeRegion("Texture")
            texture.parent = self
            return texture
        end
        function region:SetTexture(path)
            self.texture = path
        end
        function region:SetVertexColor(r, g, b, a)
            self.vertexR, self.vertexG, self.vertexB, self.vertexA = r, g, b, a
        end
        function region:SetDesaturation(amount)
            self.desaturation = amount
        end
        function region:CreateFontString()
            return MakeRegion("FontString")
        end
        function region:CreateLine()
            return MakeRegion("Line")
        end
        function region:GetStringWidth()
            return 40
        end
        function region:SetText(text)
            self.text = text
        end
        function region:GetWidth()
            return 40
        end
        local function noop() end
        for _, name in ipairs({
            "ClearAllPoints",
            "EnableMouse",
            "SetAllPoints",
            "SetColorTexture",
            "SetEndPoint",
            "SetJustifyH",
            "SetScript",
            "SetStartPoint",
            "SetText",
            "SetTextColor",
            "SetTexture",
            "SetThickness",
            "SetWordWrap",
            "SetJustifyV",
            "SetRotation",
            "SetVertexColor",
            "SetBlendMode",
            "SetBackdrop",
            "SetBackdropBorderColor",
            "SetShadowOffset",
            "SetShadowColor",
            "SetGradient",
            "SetGradientAlpha",
            "SetWidth",
            "SetAtlas",
            "SetDesaturated",
            "SetTexCoord",
        }) do
            if region[name] == nil then
                region[name] = noop
            end
        end
        table.insert(regions, region)
        return region
    end

    before_each(function()
        regions = {}
        protectedSetPoints = 0
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Combat = ns.Api.Combat
        originalCreateFrame = CreateFrame
        originalGameTooltip = GameTooltip
        GameTooltip = {
            SetOwner = function() end,
            SetText = function() end,
            Show = function() end,
            Hide = function() end,
            NumLines = function()
                return 1
            end,
        }
        CreateFrame = function(kind, _, _, template)
            return MakeRegion(kind or "Frame", template)
        end
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
            ApplyBackdrop = function() end,
            AddHoverHighlight = function(frame)
                frame:CreateTexture()
            end,
            CreateLabel = function(parent, _, text)
                local label = parent:CreateFontString()
                if text then
                    label:SetText(text)
                end
                return label
            end,
            AttachTooltip = function() end,
        }
        assert(loadfile("modules/venomous_abyss/ulatek/ui/Map.lua"))("NewEraTools", ns)
        Map = ns.Modules.Internals("Ulatek").Map
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
        GameTooltip = originalGameTooltip
    end)

    local function CreatePad()
        local row = MakeRegion("Frame")
        local arena = Map.CreateArenaRow(row, {
            size = 220,
            markerSize = 24,
            showCalloutButtons = true,
        })
        Map.AttachWindowHint(row, arena.canvas)
        return arena
    end

    it("binds signal macros on wave, boss, and soak callouts", function()
        local arena = CreatePad()
        local Ulatek = ns.Modules.Get("Ulatek")
        local buttons = arena.canvas.calloutButtons
        local expected = {
            WAVE_LEFT = 1,
            WAVE_RIGHT = 2,
            BOSS_LEFT = 1,
            BOSS_RIGHT = 2,
        }
        for id, index in pairs(expected) do
            local button = buttons[id]
            assert(button, "missing " .. id)
            assert(button.template:find("SecureActionButtonTemplate", 1, true))
            assert.equals("macro", button.attributes.type)
            assert.equals(Ulatek:GetSignalMacroName(index), button.attributes.macro)
            assert.is_nil(button.attributes.macrotext)
            assert.equals(1, button.setPointCount)
            assert.is_true(button.snapToPixelGrid)
        end
        assert.equals(48, buttons.WAVE_LEFT.width)
        assert.equals(44, buttons.WAVE_LEFT.height)
        assert.equals(36, buttons.BOSS_LEFT.width)
        assert.equals(36, buttons.BOSS_LEFT.height)
        assert.is_true(buttons.WAVE_LEFT.anchorX < 0)
        assert.is_true(buttons.WAVE_RIGHT.anchorX > 0)
        assert.is_true(buttons.BOSS_LEFT.anchorX < buttons.WAVE_LEFT.anchorX)
        assert.is_true(buttons.BOSS_RIGHT.anchorX > buttons.WAVE_RIGHT.anchorX)
        local scale = 110
        local leftGap = math.abs(buttons.BOSS_LEFT.anchorX) - buttons.BOSS_LEFT.width / 2 - scale
        local rightGap = math.abs(buttons.BOSS_RIGHT.anchorX) - buttons.BOSS_RIGHT.width / 2 - scale
        assert.is_true(leftGap >= 10 and leftGap <= 12)
        assert.is_true(rightGap >= 10 and rightGap <= 12)
        local lines = 0
        for _, region in ipairs(regions) do
            if region.kind == "Line" then
                lines = lines + 1
            end
        end
        assert.equals(8, lines)
    end)

    it("clears pad macro bindings for members and refuses SetAttribute in combat", function()
        local arena = CreatePad()
        local left = arena.canvas.calloutButtons.WAVE_LEFT
        local soak = arena.canvas.cornerButtons[4]
        assert.equals("macro", left.attributes.type)
        assert.is_true(Map.SetCalloutMacroClicksEnabled(false))
        assert.is_nil(left.attributes.type)
        assert.is_nil(left.attributes.macro)
        assert.is_nil(soak.attributes.type)
        assert.is_nil(soak.attributes.macro)

        Combat.inCombat = true
        assert.is_false(Map.SetCalloutMacroClicksEnabled(true))
        assert.is_nil(left.attributes.macro)
        Combat.inCombat = false
        assert.is_true(Map.SetCalloutMacroClicksEnabled(true))
        assert.equals(ns.Modules.Get("Ulatek"):GetSignalMacroName(1), left.attributes.macro)
        assert.equals(ns.Modules.Get("Ulatek"):GetSignalMacroName(1), soak.attributes.macro)
    end)

    it("leaves the settings editor without callout buttons", function()
        local row = MakeRegion("Frame")
        local arena = Map.CreateArenaRow(row, { size = 160, onCornerMarkerClick = function() end })
        assert.is_nil(arena.canvas.calloutButtons)
        assert.equals(0, protectedSetPoints)
    end)

    it("places all eight corner markers inside the octagon", function()
        local function assertInside(canvas, size)
            local vertexReach = (size / 2) / math.cos(math.pi / 8)
            for corner = 1, 8 do
                local region = canvas.cornerButtons[corner] or canvas.cornerIcons[corner]
                local r = math.sqrt((region.anchorX or 0) ^ 2 + (region.anchorY or 0) ^ 2)
                assert.is_true(r < vertexReach, "corner " .. corner)
                assert.is_true(r > vertexReach * 0.5, "corner " .. corner)
            end
        end
        assertInside(CreatePad().canvas, 220)
        local row = MakeRegion("Frame")
        local editor = Map.CreateArenaRow(row, { size = 160, onCornerMarkerClick = function() end })
        assertInside(editor.canvas, 160)
    end)

    it("starts hidden, default-sized, and locked until a group window opens", function()
        local arena = CreatePad()
        local buttons = arena.canvas.calloutButtons
        for _, id in ipairs({ "WAVE_LEFT", "WAVE_RIGHT", "BOSS_LEFT", "BOSS_RIGHT" }) do
            local button = buttons[id]
            assert.equals(0, button.calloutIcon.alpha)
            assert.is_true(button.lockMask.shown)
            assert.is_true(button.lockMask.mouseEnabled)
            assert.is_true(button.lockMask.frameLevel > 1)
        end
        assert.equals(48, buttons.WAVE_LEFT.calloutIcon.width)
        assert.equals(45, buttons.BOSS_LEFT.calloutIcon.width)
        assert.equals(0, arena.canvas.windowHint.alpha)
    end)

    it("shows a header hint for the active click window", function()
        local arena = CreatePad()
        local hint = arena.canvas.windowHint
        local L = ns.L
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, true)
        assert.equals(L.ULATEK_PAD_HINT_WAVE, hint.text)
        assert.equals(1, hint.alpha)

        Map.SetCalloutGroupActive(Map.GROUP_WAVE, false)
        Map.SetCalloutGroupActive(Map.GROUP_BOSS, true)
        assert.equals(L.ULATEK_PAD_HINT_BOSS, hint.text)
        assert.equals(1, hint.alpha)

        Map.SetCalloutGroupActive(Map.GROUP_BOSS, false)
        Map.SetCalloutGroupActive(Map.GROUP_MARKERS, true)
        assert.equals(L.ULATEK_PAD_HINT_MARKERS, hint.text)
        assert.equals(1, hint.alpha)

        Map.ResetCalloutGroups()
        assert.equals(0, hint.alpha)
    end)

    it("unlocks a group at full alpha, then locks both after a click with enlarge and dim", function()
        local arena = CreatePad()
        local left = arena.canvas.calloutButtons.WAVE_LEFT
        local right = arena.canvas.calloutButtons.WAVE_RIGHT
        local Timer = ns.Api.Timer
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, true)
        assert.equals(1, left.calloutIcon.alpha)
        assert.equals(1, right.calloutIcon.alpha)
        assert.is_false(left.lockMask.shown)
        assert.is_false(right.lockMask.shown)

        left.hooks.PostClick()
        assert.equals(1, left.calloutIcon.vertexR)
        assert.equals(1, left.calloutIcon.vertexG)
        assert.equals(1, left.calloutIcon.vertexB)
        assert.equals(48 * 1.3, left.calloutIcon.width)
        assert.equals(48, right.calloutIcon.width)
        assert.equals(0.35, right.calloutIcon.alpha)
        assert.is_true(left.lockMask.shown)
        assert.is_true(right.lockMask.shown)

        Timer.Advance(0.2)
        assert.equals(0.43, left.calloutIcon.vertexR)
        assert.equals(0.91, left.calloutIcon.vertexG)
        assert.equals(0.72, left.calloutIcon.vertexB)

        right.hooks.PostClick()
        assert.equals(48, right.calloutIcon.width)
        assert.equals(0.35, right.calloutIcon.alpha)
    end)

    it("hides and relocks a group when its window ends", function()
        local arena = CreatePad()
        local left = arena.canvas.calloutButtons.WAVE_LEFT
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, true)
        left.hooks.PostClick()
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, false)
        assert.equals(0, left.calloutIcon.alpha)
        assert.equals(48, left.calloutIcon.width)
        assert.is_true(left.lockMask.shown)
        assert.equals(0, arena.canvas.calloutButtons.WAVE_RIGHT.calloutIcon.alpha)
    end)

    it("does not reanchor, hide, or resize secure buttons during combat lockdown", function()
        local arena = CreatePad()
        local left = arena.canvas.calloutButtons.WAVE_LEFT
        local buttonWidth = left.width
        local anchored = protectedSetPoints
        Combat.inCombat = true
        for _, place in ipairs(arena.canvas.placements) do
            place()
        end
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, true)
        left.hooks.PostClick()
        Map.SetCalloutGroupActive(Map.GROUP_WAVE, false)
        assert.equals(anchored, protectedSetPoints)
        for _, button in pairs(arena.canvas.calloutButtons) do
            assert.equals(1, button.setPointCount)
            assert.is_true(button.shown)
            assert.equals(button == left and buttonWidth or button.width, button.width)
        end
        assert.equals(0, left.calloutIcon.alpha)
        assert.is_true(left.lockMask.shown)
    end)

    it("opens and closes pad groups on the Mythic encounter timeline", function()
        local arena = CreatePad()
        local wave = arena.canvas.calloutButtons.WAVE_LEFT
        local boss = arena.canvas.calloutButtons.BOSS_LEFT
        local Timer = ns.Api.Timer
        local Instance = ns.Api.Instance
        ns.Modules.Get("Ulatek"):ListenForEncounter()
        ns.Api.Encounter.FireStart(ns.Modules.Get("Ulatek").ENCOUNTER_ID, "Ulatek", Instance.DIFFICULTY_MYTHIC_RAID, 20)

        Timer.Advance(50)
        assert.equals(1, wave.calloutIcon.alpha)
        assert.is_false(wave.lockMask.shown)
        assert.equals(0, boss.calloutIcon.alpha)

        Timer.Advance(12)
        assert.equals(0, wave.calloutIcon.alpha)
        assert.is_true(wave.lockMask.shown)

        Timer.Advance(11.4)
        assert.equals(1, boss.calloutIcon.alpha)
        assert.is_false(boss.lockMask.shown)

        Timer.Advance(12)
        assert.equals(0, boss.calloutIcon.alpha)

        Timer.Advance(21.6)
        assert.equals(1, wave.calloutIcon.alpha)
        wave.hooks.PostClick()
        assert.is_true(wave.lockMask.shown)

        Timer.Advance(12)
        assert.equals(0, wave.calloutIcon.alpha)
        assert.equals(48, wave.calloutIcon.width)
    end)

    it("cancels pending pad windows and resets on encounter end", function()
        local arena = CreatePad()
        local wave = arena.canvas.calloutButtons.WAVE_LEFT
        local Timer = ns.Api.Timer
        local Instance = ns.Api.Instance
        local Ulatek = ns.Modules.Get("Ulatek")
        Ulatek:ListenForEncounter()
        ns.Api.Encounter.FireStart(Ulatek.ENCOUNTER_ID, "Ulatek", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Timer.Advance(50)
        assert.equals(1, wave.calloutIcon.alpha)
        ns.Api.Encounter.FireEnd(Ulatek.ENCOUNTER_ID, "Ulatek", Instance.DIFFICULTY_MYTHIC_RAID, 20, 0)
        assert.equals(0, wave.calloutIcon.alpha)
        assert.is_true(wave.lockMask.shown)
        Timer.Advance(70)
        assert.equals(0, wave.calloutIcon.alpha)
        assert.equals(0, arena.canvas.calloutButtons.BOSS_LEFT.calloutIcon.alpha)
    end)

    it("does not open pad groups on Heroic", function()
        local arena = CreatePad()
        local Timer = ns.Api.Timer
        local Instance = ns.Api.Instance
        local Ulatek = ns.Modules.Get("Ulatek")
        Ulatek:ListenForEncounter()
        ns.Api.Encounter.FireStart(Ulatek.ENCOUNTER_ID, "Ulatek", Instance.DIFFICULTY_HEROIC_RAID, 20)
        Timer.Advance(50)
        assert.equals(0, arena.canvas.calloutButtons.WAVE_LEFT.calloutIcon.alpha)
        assert.is_true(arena.canvas.calloutButtons.WAVE_LEFT.lockMask.shown)
    end)

    it("runs pad groups at 3x during a pad test and shows the timer", function()
        local arena = CreatePad()
        local wave = arena.canvas.calloutButtons.WAVE_LEFT
        local Timer = ns.Api.Timer
        local Timeline = ns.Modules.Internals("Ulatek").Timeline
        local Ulatek = ns.Modules.Get("Ulatek")
        local clock = arena.canvas.testClock
        assert(clock)
        assert.equals(0, clock.alpha)

        Ulatek:StartPadTest()
        assert.equals(1, clock.alpha)
        assert.equals("0:00", clock.text)

        Timer.Advance(50 / Timeline.PAD_TEST_RATE)
        assert.equals(1, wave.calloutIcon.alpha)
        assert.is_false(wave.lockMask.shown)
        assert.equals("0:50", clock.text)

        Timer.Advance(12 / Timeline.PAD_TEST_RATE)
        assert.equals(0, wave.calloutIcon.alpha)
        Ulatek:EndPadTest()
        assert.equals(0, clock.alpha)
        assert.is_false(Ulatek:IsPadTestActive())
    end)

    it("ends the pad test when the clock reaches 11:00", function()
        local arena = CreatePad()
        local Timer = ns.Api.Timer
        local Timeline = ns.Modules.Internals("Ulatek").Timeline
        local Ulatek = ns.Modules.Get("Ulatek")
        local clock = arena.canvas.testClock
        Ulatek:StartPadTest()
        Timer.Advance((Timeline.PAD_TEST_DURATION - 1) / Timeline.PAD_TEST_RATE)
        assert.is_true(Ulatek:IsPadTestActive())
        assert.equals("10:59", clock.text)

        Timer.Advance(1 / Timeline.PAD_TEST_RATE)
        assert.is_false(Ulatek:IsPadTestActive())
        assert.equals(0, clock.alpha)
    end)

    it("cancels a 3x pad test when the Mythic encounter starts", function()
        local arena = CreatePad()
        local wave = arena.canvas.calloutButtons.WAVE_LEFT
        local Timer = ns.Api.Timer
        local Instance = ns.Api.Instance
        local Timeline = ns.Modules.Internals("Ulatek").Timeline
        local Ulatek = ns.Modules.Get("Ulatek")
        Ulatek:ListenForEncounter()
        Ulatek:StartPadTest()
        Timer.Advance(50 / Timeline.PAD_TEST_RATE)
        assert.equals(1, wave.calloutIcon.alpha)

        ns.Api.Encounter.FireStart(Ulatek.ENCOUNTER_ID, "Ulatek", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        assert.equals(0, wave.calloutIcon.alpha)
        assert.is_false(Ulatek:IsPadTestActive())

        Timer.Advance(50)
        assert.equals(1, wave.calloutIcon.alpha)
    end)

    it("hides pad markers and only shows corners 4, 5, and 7 in their window", function()
        local arena = CreatePad()
        local buttons = arena.canvas.cornerButtons
        for corner = 1, 8 do
            assert.equals(0, arena.canvas.cornerIcons[corner].alpha)
        end
        local Ulatek = ns.Modules.Get("Ulatek")
        local markerMacros = { [4] = 1, [5] = 2, [7] = 3 }
        for _, corner in ipairs({ 4, 5, 7 }) do
            local button = buttons[corner]
            assert(button.template:find("SecureActionButtonTemplate", 1, true))
            assert.equals("macro", button.attributes.type)
            assert.equals(Ulatek:GetSignalMacroName(markerMacros[corner]), button.attributes.macro)
            assert.is_true(button.lockMask.shown)
            assert.equals(1, button.setPointCount)
        end
        assert.is_nil(buttons[1])
        assert.is_nil(buttons[8])

        local Timeline = ns.Modules.Internals("Ulatek").Timeline
        local Timer = ns.Api.Timer
        Ulatek:StartPadTest()
        Timer.Advance(325 / Timeline.PAD_TEST_RATE)
        assert.equals(1, arena.canvas.cornerIcons[4].alpha)
        assert.equals(1, arena.canvas.cornerIcons[5].alpha)
        assert.equals(1, arena.canvas.cornerIcons[7].alpha)
        assert.equals(0, arena.canvas.cornerIcons[1].alpha)
        assert.equals(0, arena.canvas.cornerIcons[8].alpha)
        assert.is_false(buttons[4].lockMask.shown)

        buttons[4].hooks.PostClick()
        assert.equals(24 * 1.3, arena.canvas.cornerIcons[4].width)
        assert.equals(24, arena.canvas.cornerIcons[5].width)
        assert.equals(0.35, arena.canvas.cornerIcons[5].alpha)
        assert.is_true(buttons[4].lockMask.shown)
        assert.is_true(buttons[5].lockMask.shown)
        assert.is_true(buttons[7].lockMask.shown)

        buttons[7].hooks.PostClick()
        assert.equals(24, arena.canvas.cornerIcons[7].width)

        Timer.Advance(15 / Timeline.PAD_TEST_RATE)
        assert.equals(0, arena.canvas.cornerIcons[4].alpha)
        assert.equals(24, arena.canvas.cornerIcons[4].width)
        assert.is_true(buttons[4].lockMask.shown)
        Ulatek:EndPadTest()
    end)
end)
