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
            self.attributes[key] = value
        end
        function region:RegisterForClicks(...)
            self.clicks = { ... }
        end
        function region:SetSize(width, height)
            self.width = width
            self.height = height
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
        function region:CreateFontString()
            return MakeRegion("FontString")
        end
        function region:CreateLine()
            return MakeRegion("Line")
        end
        function region:GetStringWidth()
            return 40
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
        return Map.CreateArenaRow(row, {
            size = 220,
            markerSize = 24,
            showCalloutButtons = true,
        })
    end

    it("creates four secure buttons with no macro action", function()
        local arena = CreatePad()
        local buttons = arena.canvas.calloutButtons
        local ids = { "WAVE_LEFT", "WAVE_RIGHT", "BOSS_LEFT", "BOSS_RIGHT" }
        for _, id in ipairs(ids) do
            local button = buttons[id]
            assert(button, "missing " .. id)
            assert(button.template:find("SecureActionButtonTemplate", 1, true))
            assert.is_nil(button.attributes.type)
            assert.is_nil(button.attributes.macrotext)
            assert.is_nil(button.attributes.macro)
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

    it("leaves the settings editor without callout buttons", function()
        local row = MakeRegion("Frame")
        local arena = Map.CreateArenaRow(row, { size = 160, onCornerMarkerClick = function() end })
        assert.is_nil(arena.canvas.calloutButtons)
        assert.equals(0, protectedSetPoints)
    end)

    it("flashes the boss dashed circle white for 0.2s after a click", function()
        local arena = CreatePad()
        local button = arena.canvas.calloutButtons.BOSS_LEFT
        local icon
        for _, region in ipairs(regions) do
            if region.kind == "Texture" and region.parent == button then
                icon = region
                break
            end
        end
        assert(icon)
        local Timer = ns.Api.Timer
        button.hooks.PostClick()
        assert.equals(1, icon.vertexR)
        assert.equals(1, icon.vertexG)
        assert.equals(1, icon.vertexB)
        assert.equals(1, icon.vertexA)
        Timer.Advance(0.2)
        assert.equals(0.22, icon.vertexR)
        assert.equals(0.74, icon.vertexG)
        assert.equals(0.97, icon.vertexB)
        assert.equals(0.80, icon.vertexA)
    end)

    it("does not reanchor or hide callout buttons during combat lockdown", function()
        local arena = CreatePad()
        local anchored = protectedSetPoints
        Combat.inCombat = true
        for _, place in ipairs(arena.canvas.placements) do
            place()
        end
        assert.equals(anchored, protectedSetPoints)
        for _, button in pairs(arena.canvas.calloutButtons) do
            assert.equals(1, button.setPointCount)
            assert.is_true(button.shown)
        end
    end)
end)
