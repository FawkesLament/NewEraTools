local Harness = require("helpers.sszorak")

local ARENA_SIZE = 200
-- Heroic timeline: first jump leaves home for the center station.
local CENTER_TIME = 42.9

describe("Sszorak map during combat lockdown", function()
    local ns, Sszorak, Map, Combat, Timer
    local originalCreateFrame
    local protectedSetPoints
    local regions

    local function MakeRegion(kind, template)
        local region = {
            kind = kind,
            protected = type(template) == "string" and template:find("SecureActionButton", 1, true) ~= nil,
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
            if self.protected then
                protectedSetPoints = protectedSetPoints + 1
            end
            local x, y = select(4, ...)
            if type(x) == "number" then
                self.anchorX = x
            end
            if type(y) == "number" then
                self.anchorY = y
            end
        end
        function region:CreateTexture()
            return MakeRegion("Texture")
        end
        function region:CreateFontString()
            return MakeRegion("FontString")
        end
        function region:CreateLine()
            return MakeRegion("Line")
        end
        function region:CreateMaskTexture()
            return MakeRegion("Mask")
        end
        function region:GetStringWidth()
            return 40
        end
        function region:GetWidth()
            return 40
        end
        function region:SetID(id)
            if self.protected and Combat.IsLockedDown() then
                error("ADDON_ACTION_BLOCKED Button:SetID()", 2)
            end
            self.id = id
        end
        function region:GetID()
            return self.id or 0
        end
        function region:GetFrameLevel()
            return 1
        end
        function region:SetFrameLevel() end
        function region:SetShown(shown)
            self.shown = shown and true or false
        end
        function region:HookScript(script, handler)
            self.hooks = self.hooks or {}
            self.hooks[script] = handler
        end
        function region:WrapScript(frame, script, preBody)
            self.wraps = self.wraps or {}
            table.insert(self.wraps, { frame = frame, script = script, preBody = preBody })
        end
        local function noop() end
        for _, name in ipairs({
            "AddMaskTexture",
            "ClearAllPoints",
            "EnableMouse",
            "Hide",
            "RegisterForClicks",
            "SetAllPoints",
            "SetAttribute",
            "SetColorTexture",
            "SetEndPoint",
            "SetFrameRef",
            "SetJustifyH",
            "SetScript",
            "SetSize",
            "SetStartPoint",
            "SetText",
            "SetTextColor",
            "SetTexture",
            "SetThickness",
            "SetWidth",
            "SetWordWrap",
            "Show",
        }) do
            region[name] = noop
        end
        table.insert(regions, region)
        return region
    end

    local function CreateArena()
        local row = MakeRegion("Frame")
        return Map.CreateArenaRow(row, {
            size = ARENA_SIZE,
            showPositions = true,
            followsRotation = true,
            edgeMarkerMacroName = function(edge)
                return Sszorak:GetEdgeMacroName(edge)
            end,
        })
    end

    local function TextureAnchoredAt(x)
        for _, region in ipairs(regions) do
            if region.kind == "Texture" and region.anchorX == x then
                return true
            end
        end
        return false
    end

    before_each(function()
        protectedSetPoints = 0
        regions = {}
        ns, Sszorak = Harness.Start()
        Combat = ns.Api.Combat
        Timer = ns.Api.Timer
        originalCreateFrame = CreateFrame
        CreateFrame = function(kind, name, _, template)
            local region = MakeRegion(kind or "Frame", template)
            region.name = name
            return region
        end
        ns.Widgets = {
            UnpackColor = function(color)
                return color.r, color.g, color.b, color.a
            end,
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
        assert(loadfile("ui/Layout.lua"))("NewEraTools", ns)
        assert(loadfile("modules/venomous_abyss/sszorak/ui/Map.lua"))("NewEraTools", ns)
        Map = ns.SszorakMap
        Sszorak.OnPositionsChanged = function()
            Map.RefreshPositionMarkers()
        end
    end)

    after_each(function()
        CreateFrame = originalCreateFrame
    end)

    it("moves the position dots without reanchoring secure edge buttons", function()
        CreateArena()
        assert.is_true(protectedSetPoints > 0)
        local anchored = protectedSetPoints
        Combat.inCombat = true

        Sszorak:StartMapAnimation()
        Timer.Advance(CENTER_TIME)

        assert.equals(anchored, protectedSetPoints)
        assert.is_true(TextureAnchoredAt(0))
    end)

    it("still reanchors secure edge buttons outside combat lockdown", function()
        local arena = CreateArena()
        local before
        for _, region in ipairs(regions) do
            if region.protected and region.anchorX and region.anchorX ~= 0 then
                before = region.anchorX
                break
            end
        end
        assert(before, "expected a secure edge button anchor")
        Sszorak:SetMapRotation(180)
        Map.ApplyRotation(arena)
        local flipped = false
        for _, region in ipairs(regions) do
            if region.protected and region.anchorX == -before then
                flipped = true
                break
            end
        end
        assert.is_true(flipped)
    end)

    it("moves the entrance and exit labels with the map rotation", function()
        local arena = CreateArena()
        assert.is_true(arena.entranceLabel.anchorX > 0)
        assert.is_true(arena.exitLabel.anchorX < 0)

        Sszorak:SetMapRotation(180)
        Map.ApplyRotation(arena)
        assert.is_true(arena.entranceLabel.anchorX < 0)
        assert.is_true(arena.exitLabel.anchorX > 0)

        Sszorak:SetMapRotation(90)
        Map.ApplyRotation(arena)
        assert.is_true(math.abs(arena.entranceLabel.anchorX) < 1e-6)
        assert.is_true(arena.entranceLabel.anchorY > 0)
        assert.is_true(math.abs(arena.exitLabel.anchorX) < 1e-6)
        assert.is_true(arena.exitLabel.anchorY < 0)
    end)

    it("does not move secure edge buttons when only the side changes", function()
        local arena = CreateArena()
        local before = {}
        for _, region in ipairs(regions) do
            if region.protected and region.anchorX then
                before[region] = region.anchorX
            end
        end
        assert(next(before), "expected a secure edge button anchor")
        Sszorak:SetPlayerSide(Sszorak.SIDE_RIGHT)
        Map.ApplyRotation(arena)
        Map.RefreshPlayerGroup()
        for region, x in pairs(before) do
            assert.equals(x, region.anchorX)
        end
    end)

    it("locks further edge clicks during combat without SetID", function()
        CreateArena()
        local buttons = {}
        for _, region in ipairs(regions) do
            if region.protected then
                table.insert(buttons, region)
                assert.is_nil(region.wraps)
            end
        end
        assert.is_true(#buttons >= 3)

        Combat.inCombat = true
        Map.SetEdgeClickTrackingArmed(true)
        for _, button in ipairs(buttons) do
            assert.is_true(button.clickCover ~= nil)
            assert.is_false(button.clickCover.shown)
        end

        buttons[1].hooks.PostClick()
        assert.is_true(buttons[1].clickCover.shown)
        assert.is_false(buttons[2].clickCover.shown)

        buttons[2].hooks.PostClick()
        buttons[3].hooks.PostClick()
        for _, button in ipairs(buttons) do
            assert.is_true(button.clickCover.shown)
        end

        Map.ResetEdgeClickHighlights()
        for _, button in ipairs(buttons) do
            assert.is_false(button.clickCover.shown)
        end

        Map.SetEdgeClickTrackingArmed(false)
        buttons[1].hooks.PostClick()
        assert.is_false(buttons[1].clickCover.shown)
    end)
end)
