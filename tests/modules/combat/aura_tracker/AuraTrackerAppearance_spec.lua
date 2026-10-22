local Harness = require("helpers.aura_tracker")

describe("appearance", function()
    local ns, AuraTracker, Schema

    before_each(function()
        local _
        ns, AuraTracker, _, Schema = Harness.Start()
    end)

    it("uses the original bar defaults", function()
        local id = AuraTracker:AddTracker()
        assert.equals(200, AuraTracker:GetWidth(id))
        assert.equals(18, AuraTracker:GetHeight(id))
        assert.equals(1, AuraTracker:GetBackgroundOpacity(id))
        assert.is_false(AuraTracker:GetReverseFill(id))
        assert.is_false(AuraTracker:GetVertical(id))
        assert.is_false(AuraTracker:GetShowBorder(id))
        assert.is_true(AuraTracker:GetShowStackDividers(id))
        assert.equals(1, AuraTracker:GetLineThickness(id))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
        assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(id))
        assert.equals(10, AuraTracker:GetMaxStacks(id))
        assert.equals("default", AuraTracker:GetTextDisplayFont(id, Schema.TEXT_DURATION))
        assert.equals(12, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
        assert.equals("flat", AuraTracker:GetTexture(id))
        assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))
        local fill = AuraTracker:GetFillColor(id)
        assert.equals(0.310, fill.r)
        assert.equals(0.765, fill.g)
        assert.equals(0.710, fill.b)
        local line = AuraTracker:GetLineColor(id)
        assert.equals(0.180, line.r)
        assert.equals(0.196, line.g)
        assert.equals(0.231, line.b)
    end)

    it("notifies OnAppearanceChanged without OnTrackerChanged", function()
        local id = AuraTracker:AddTracker()
        local appearanceCalls = 0
        local trackerCalls = 0
        function AuraTracker:OnAppearanceChanged(trackerId)
            assert.equals(id, trackerId)
            appearanceCalls = appearanceCalls + 1
        end
        function AuraTracker:OnTrackerChanged()
            trackerCalls = trackerCalls + 1
        end
        AuraTracker:SetWidth(id, 240)
        AuraTracker:SetHeight(id, 24)
        AuraTracker:SetFillColor(id, { r = 1, g = 0, b = 0 })
        AuraTracker:SetTexture(id, "default")
        AuraTracker:SetBackgroundColor(id, { r = 0, g = 0, b = 0 })
        AuraTracker:SetBackgroundOpacity(id, 0.5)
        AuraTracker:SetReverseFill(id, true)
        AuraTracker:SetVertical(id, true)
        AuraTracker:SetShowBorder(id, true)
        AuraTracker:SetLineColor(id, { r = 1, g = 1, b = 1 })
        AuraTracker:SetLineThickness(id, 3)
        AuraTracker:SetShowStackDividers(id, false)
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_DURATION, false)
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_STACKS, true)
        AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 16)
        AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_STACKS, 30)
        assert.equals(16, appearanceCalls)
        assert.equals(0, trackerCalls)
        assert.equals(240, AuraTracker:GetWidth(id))
        assert.equals(24, AuraTracker:GetHeight(id))
        assert.equals("default", AuraTracker:GetTexture(id))
        assert.equals(ns.Assets.Textures.STATUS_BAR, AuraTracker:GetTexturePath(id))
        assert.is_true(AuraTracker:GetReverseFill(id))
        assert.is_true(AuraTracker:GetVertical(id))
        assert.is_true(AuraTracker:GetShowBorder(id))
        assert.equals(1, AuraTracker:GetLineColor(id).r)
        assert.equals(3, AuraTracker:GetLineThickness(id))
        assert.is_false(AuraTracker:GetShowStackDividers(id))
        assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        assert.equals(16, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
        assert.equals(30, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        local background = AuraTracker:GetBackgroundColor(id)
        assert.equals(0, background.r)
        assert.equals(0, background.g)
        assert.equals(0, background.b)
        assert.equals(0, AuraTracker.db.trackers[1].backgroundColor.r)
        assert.equals(0, AuraTracker.db.trackers[1].backgroundColor.g)
        assert.equals(0, AuraTracker.db.trackers[1].backgroundColor.b)
    end)

    it("keeps line style and stack-divider settings independent per tracker", function()
        local a = AuraTracker:AddTracker()
        local b = AuraTracker:AddTracker()
        AuraTracker:SetLineColor(a, { r = 1, g = 0, b = 0 })
        AuraTracker:SetLineThickness(a, 4)
        AuraTracker:SetShowStackDividers(a, false)
        assert.equals(1, AuraTracker:GetLineColor(a).r)
        assert.equals(0.180, AuraTracker:GetLineColor(b).r)
        assert.equals(4, AuraTracker:GetLineThickness(a))
        assert.equals(1, AuraTracker:GetLineThickness(b))
        assert.is_false(AuraTracker:GetShowStackDividers(a))
        assert.is_true(AuraTracker:GetShowStackDividers(b))
    end)

    it("clamps line thickness", function()
        local id = AuraTracker:AddTracker()
        local tracker = AuraTracker.db.trackers[1]
        AuraTracker:SetLineThickness(id, 0)
        assert.equals(Schema.LINE_THICKNESS_MIN, tracker.lineThickness)
        assert.equals(Schema.LINE_THICKNESS_MIN, AuraTracker:GetLineThickness(id))
        AuraTracker:SetLineThickness(id, 99)
        assert.equals(Schema.LINE_THICKNESS_MAX, tracker.lineThickness)
        assert.equals(Schema.LINE_THICKNESS_MAX, AuraTracker:GetLineThickness(id))
    end)

    it("clamps size, opacity, and font size", function()
        local id = AuraTracker:AddTracker()
        local tracker = AuraTracker.db.trackers[1]
        AuraTracker:SetWidth(id, 1)
        assert.equals(Schema.WIDTH_MIN, tracker.width)
        assert.equals(Schema.WIDTH_MIN, AuraTracker:GetWidth(id))
        AuraTracker:SetHeight(id, 999)
        assert.equals(Schema.HEIGHT_MAX, tracker.height)
        assert.equals(Schema.HEIGHT_MAX, AuraTracker:GetHeight(id))
        AuraTracker:SetBackgroundOpacity(id, 2)
        assert.equals(1, tracker.backgroundOpacity)
        assert.equals(1, AuraTracker:GetBackgroundOpacity(id))
        AuraTracker:SetBackgroundOpacity(id, 0.53)
        assert.equals(0.55, tracker.backgroundOpacity)
        AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 1)
        assert.equals(Schema.FONT_SIZE_MIN, tracker.textDisplays[Schema.TEXT_DURATION].fontSize)
        assert.equals(Schema.FONT_SIZE_MIN, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
    end)

    it("keeps text offsets when orientation, fill direction, or progress mode change", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, -20)
        AuraTracker:SetTextDisplayOffsetY(id, Schema.TEXT_STACKS, 12)
        AuraTracker:SetVertical(id, true)
        AuraTracker:SetReverseFill(id, true)
        AuraTracker:SetProgressMode(id, Schema.PROGRESS_MODE_STACKS)
        assert.equals(-20, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
        assert.equals(12, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
    end)

    it("clamps text offsets", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, -999)
        AuraTracker:SetTextDisplayOffsetY(id, Schema.TEXT_STACKS, 999)
        assert.equals(Schema.TEXT_OFFSET_MIN, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        assert.equals(Schema.TEXT_OFFSET_MAX, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
    end)

    it("does not notify when appearance is unchanged", function()
        local id = AuraTracker:AddTracker()
        local calls = 0
        function AuraTracker:OnAppearanceChanged()
            calls = calls + 1
        end
        AuraTracker:SetWidth(id, 200)
        AuraTracker:SetTexture(id, "flat")
        AuraTracker:SetReverseFill(id, false)
        assert.equals(0, calls)
    end)

    it("rejects unknown textures and falls back when saved value is invalid", function()
        local id = AuraTracker:AddTracker()
        assert.is_false(pcall(AuraTracker.SetTexture, AuraTracker, id, "missing"))
        local tracker = AuraTracker.db.trackers[1]
        tracker.texture = "missing"
        assert.equals("flat", AuraTracker:GetTexture(id))
        assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))
        -- Keep the raw id so a late LibSharedMedia register can restore it.
        assert.equals("missing", tracker.texture)
    end)

    it("lists only built-in textures when LibSharedMedia is absent", function()
        local ids = ns.Modules.Internals("AuraTracker").Media.ListTextureIds()
        assert.same({ "flat", "default", "raid" }, ids)
    end)
end)

describe("LibSharedMedia textures", function()
    local ns, AuraTracker
    local previousLibStub
    local fakeLSM
    local registeredCallbacks

    before_each(function()
        ns, AuraTracker = Harness.Start()
    end)

    before_each(function()
        previousLibStub = rawget(_G, "LibStub")
        registeredCallbacks = {}
        fakeLSM = {
            MediaType = { STATUSBAR = "statusbar" },
            media = {
                statusbar = {
                    Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
                    Smooth = "Interface\\Buttons\\YELLOWORANGE64",
                    FlatLSM = "Interface\\Buttons\\WHITE8x8",
                },
                font = {
                    Friz = "Fonts\\FRIZQT__.TTF",
                },
            },
        }
        function fakeLSM:List(mediaType)
            local names = {}
            for name in pairs(self.media[mediaType] or {}) do
                names[#names + 1] = name
            end
            table.sort(names)
            return names
        end
        function fakeLSM:Fetch(mediaType, key, noDefault)
            local path = self.media[mediaType] and self.media[mediaType][key]
            if path then
                return path
            end
            if not noDefault then
                return self.media[mediaType] and self.media[mediaType].Blizzard
            end
            return nil
        end
        function fakeLSM.RegisterCallback(_, event, handler)
            registeredCallbacks[#registeredCallbacks + 1] = { event = event, handler = handler }
        end
        _G.LibStub = function(name, silent)
            if name == "LibSharedMedia-3.0" then
                return fakeLSM
            end
            if silent then
                return nil
            end
            error("library not found: " .. tostring(name))
        end
    end)

    after_each(function()
        _G.LibStub = previousLibStub
    end)

    it("resolves and stores LSM statusbar handles without storing paths", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetTexture(id, "Smooth")
        assert.equals("Smooth", AuraTracker:GetTexture(id))
        assert.equals("Smooth", AuraTracker.db.trackers[1].texture)
        assert.equals("Interface\\Buttons\\YELLOWORANGE64", AuraTracker:GetTexturePath(id))
    end)

    it("skips LSM entries that duplicate built-in ids or paths", function()
        local ids = ns.Modules.Internals("AuraTracker").Media.ListTextureIds()
        assert.same({ "flat", "default", "raid", "Smooth" }, ids)
    end)

    it("falls back while an LSM handle is missing, then resolves after registration", function()
        local id = AuraTracker:AddTracker()
        AuraTracker.db.trackers[1].texture = "Later"
        assert.equals("flat", AuraTracker:GetTexture(id))
        assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))

        fakeLSM.media.statusbar.Later = "Interface\\Buttons\\BLUE64"
        assert.equals("Later", AuraTracker:GetTexture(id))
        assert.equals("Interface\\Buttons\\BLUE64", AuraTracker:GetTexturePath(id))
    end)

    it("falls back for an unknown font and resolves one LSM font handle", function()
        local Schema = ns.Modules.Internals("AuraTracker").Schema
        local id = AuraTracker:AddTracker()
        local display = AuraTracker.db.trackers[1].textDisplays[Schema.TEXT_DURATION]
        assert.equals("default", display.font)
        assert.is_nil(ns.SharedMedia.ResolveFontPath("default"))
        assert.is_nil(AuraTracker:GetTextDisplayFontPath(id, Schema.TEXT_DURATION))
        assert.is_false(pcall(AuraTracker.SetTextDisplayFont, AuraTracker, id, Schema.TEXT_DURATION, "missing"))
        assert.equals("default", display.font)
        display.font = "missing"
        assert.equals("default", AuraTracker:GetTextDisplayFont(id, Schema.TEXT_DURATION))
        assert.equals("missing", display.font)
        AuraTracker:SetTextDisplayFont(id, Schema.TEXT_DURATION, "Friz")
        assert.equals("Friz", display.font)
        assert.equals("Fonts\\FRIZQT__.TTF", ns.SharedMedia.ResolveFontPath("Friz"))
        assert.equals("Fonts\\FRIZQT__.TTF", AuraTracker:GetTextDisplayFontPath(id, Schema.TEXT_DURATION))
    end)
end)

describe("AuraTracker deferred appearance", function()
    local ns, AuraTracker

    before_each(function()
        ns, AuraTracker = Harness.Start()
    end)

    it("reports only the saved fields that differ from the last painted look", function()
        local id = AuraTracker:AddTracker()
        local painted = AuraTracker:CaptureDeferredAppearance(id)
        assert.same({}, AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id)))

        AuraTracker:SetWidth(id, 240)
        AuraTracker:SetFillColor(id, { r = 1, g = 0, b = 0 })
        AuraTracker:SetProgressMode(id, ns.Modules.Internals("AuraTracker").Schema.PROGRESS_MODE_STACKS)
        AuraTracker:SetTextDisplayEnabled(id, ns.Modules.Internals("AuraTracker").Schema.TEXT_STACKS, true)
        AuraTracker:SetSpellId(id, 774)
        local pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_true(pending.width)
        assert.is_true(pending.fillColor)
        assert.is_true(pending.progressMode)
        assert.is_true(pending["text.stacks.enabled"])
        assert.is_nil(pending.spellId)
        assert.is_nil(pending.height)

        AuraTracker:SetHeight(id, 24)
        pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_true(pending.height)
        assert.is_true(pending.width)
        AuraTracker:SetHeight(id, painted.height)
        pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_nil(pending.height)
        assert.is_true(pending.width)

        AuraTracker:SetWidth(id, painted.width)
        pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_nil(pending.width)
        assert.is_true(pending.fillColor)
    end)
end)
