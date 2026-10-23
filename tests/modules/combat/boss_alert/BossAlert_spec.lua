local Loader = require("helpers.loader")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("BossAlert", function()
    local ns, BossAlert

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        BossAlert = ns.Modules.Get("BossAlert")
    end)

    it("is registered with callout settings that match the existing look", function()
        assert.is_false(BossAlert == nil)
        assert.equals("table", type(BossAlert.db.callout))
        AssertNear(1, BossAlert:GetCalloutScale())
        assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
        assert.equals(ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].size, BossAlert:GetCalloutFontSize())
        local color = BossAlert:GetCalloutFontColor()
        local expected = ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].color
        assert.equals(expected.r, color.r)
        assert.equals(expected.g, color.g)
        assert.equals(expected.b, color.b)
    end)

    describe("callout scale", function()
        it("is saved and snapped to the step", function()
            BossAlert:SetCalloutScale(1.22)
            AssertNear(1.2, BossAlert:GetCalloutScale())
            AssertNear(1.2, BossAlert.db.callout.scale)
        end)

        it("clamps to the allowed range", function()
            BossAlert:SetCalloutScale(0.1)
            AssertNear(BossAlert.CALLOUT_SCALE_MIN, BossAlert:GetCalloutScale())
            BossAlert:SetCalloutScale(3)
            AssertNear(BossAlert.CALLOUT_SCALE_MAX, BossAlert:GetCalloutScale())
        end)

        it("rejects non-numbers", function()
            assert.is_false(pcall(BossAlert.SetCalloutScale, BossAlert, "big"))
            AssertNear(1, BossAlert:GetCalloutScale())
        end)
    end)

    describe("callout font", function()
        it("stores a typeface id", function()
            BossAlert:SetCalloutFont("Custom Font")
            assert.equals("Custom Font", BossAlert:GetCalloutFont())
        end)

        it("falls back to the built-in default when unset", function()
            BossAlert.db.callout.font = ""
            assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
            BossAlert.db.callout.font = nil
            assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
        end)

        it("rejects an empty typeface", function()
            assert.is_false(pcall(BossAlert.SetCalloutFont, BossAlert, ""))
            assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
        end)

        it("uses the existing CALLOUT face when the typeface is unset", function()
            assert.equals(ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].path, BossAlert:GetCalloutFontPath())
        end)
    end)

    describe("callout font size", function()
        it("is saved and snapped to the step", function()
            BossAlert:SetCalloutFontSize(40.4)
            assert.equals(40, BossAlert:GetCalloutFontSize())
        end)

        it("clamps to the allowed range", function()
            BossAlert:SetCalloutFontSize(2)
            assert.equals(BossAlert.CALLOUT_FONT_SIZE_MIN, BossAlert:GetCalloutFontSize())
            BossAlert:SetCalloutFontSize(200)
            assert.equals(BossAlert.CALLOUT_FONT_SIZE_MAX, BossAlert:GetCalloutFontSize())
        end)

        it("rejects non-numbers", function()
            local defaultSize = ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].size
            assert.is_false(pcall(BossAlert.SetCalloutFontSize, BossAlert, "big"))
            assert.equals(defaultSize, BossAlert:GetCalloutFontSize())
        end)
    end)

    describe("callout font color", function()
        it("stores a normalized RGB color", function()
            BossAlert:SetCalloutFontColor({ r = 0.2, g = 0.4, b = 0.8 })
            local color = BossAlert:GetCalloutFontColor()
            assert.equals(0.2, color.r)
            assert.equals(0.4, color.g)
            assert.equals(0.8, color.b)
        end)

        it("clamps out-of-range channels", function()
            BossAlert:SetCalloutFontColor({ r = 2, g = -1, b = 0.5 })
            local color = BossAlert:GetCalloutFontColor()
            assert.equals(1, color.r)
            assert.equals(0, color.g)
            assert.equals(0.5, color.b)
        end)

        it("rejects an incomplete color", function()
            assert.is_false(pcall(BossAlert.SetCalloutFontColor, BossAlert, nil))
            assert.is_false(pcall(BossAlert.SetCalloutFontColor, BossAlert, { r = 1, g = 1 }))
        end)
    end)

    describe("callout appearance", function()
        it("notifies the UI hook only when a setting changes", function()
            local seen = 0
            function BossAlert:OnCalloutAppearanceChanged()
                seen = seen + 1
            end
            BossAlert:SetCalloutScale(1.1)
            BossAlert:SetCalloutScale(1.1)
            BossAlert:SetCalloutFontSize(40)
            BossAlert:SetCalloutFontSize(40)
            BossAlert:SetCalloutFont("Custom Font")
            BossAlert:SetCalloutFont("Custom Font")
            BossAlert:SetCalloutFontColor({ r = 1, g = 0, b = 0 })
            BossAlert:SetCalloutFontColor({ r = 1, g = 0, b = 0 })
            assert.equals(4, seen)
        end)

        it("resolves the look CalloutMessage should apply", function()
            BossAlert:SetCalloutScale(1.1)
            BossAlert:SetCalloutFontSize(40)
            BossAlert:SetCalloutFontColor({ r = 0, g = 1, b = 0 })
            local appearance = BossAlert:GetCalloutAppearance()
            AssertNear(1.1, appearance.scale)
            assert.equals(ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].path, appearance.fontPath)
            assert.equals(40, appearance.fontSize)
            assert.equals(0, appearance.fontColor.r)
            assert.equals(1, appearance.fontColor.g)
            assert.equals(0, appearance.fontColor.b)
        end)
    end)

    describe("callout reset", function()
        it("restores the existing callout look and notifies once", function()
            local seen = 0
            function BossAlert:OnCalloutAppearanceChanged()
                seen = seen + 1
            end
            BossAlert:SetCalloutScale(1.2)
            BossAlert:SetCalloutFont("Custom Font")
            BossAlert:SetCalloutFontSize(40)
            BossAlert:SetCalloutFontColor({ r = 0, g = 1, b = 0 })
            seen = 0
            BossAlert:ResetCalloutAppearance()
            assert.equals(1, seen)
            AssertNear(1, BossAlert:GetCalloutScale())
            assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
            assert.equals(ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].size, BossAlert:GetCalloutFontSize())
            local color = BossAlert:GetCalloutFontColor()
            local expected = ns.Assets.FontStyles[ns.Assets.Fonts.CALLOUT].color
            assert.equals(expected.r, color.r)
            assert.equals(expected.g, color.g)
            assert.equals(expected.b, color.b)
        end)
    end)

    describe("callout TTS", function()
        local Speech, CalloutManager, Timer, savedIsSecret

        before_each(function()
            savedIsSecret = issecretvalue
            Speech = ns.Api.Speech
            CalloutManager = ns.CalloutManager
            Timer = ns.Api.Timer
            BossAlert:ListenForCalloutTts()
        end)

        after_each(function()
            issecretvalue = savedIsSecret
        end)

        it("is off by default", function()
            assert.is_false(BossAlert:IsCalloutTtsEnabled())
        end)

        it("toggles and persists on the callout settings", function()
            BossAlert:SetCalloutTtsEnabled(true)
            assert.is_true(BossAlert:IsCalloutTtsEnabled())
            assert.is_true(BossAlert.db.callout.tts)
            BossAlert:SetCalloutTtsEnabled(true)
            BossAlert:SetCalloutTtsEnabled(false)
            assert.is_false(BossAlert:IsCalloutTtsEnabled())
        end)

        it("does not speak when TTS is off", function()
            CalloutManager.Show({ source = "test", text = "Soak", duration = 5 })
            assert.same({}, Speech.spoken)
        end)

        it("speaks the displayed message when a new callout is shown", function()
            BossAlert:SetCalloutTtsEnabled(true)
            CalloutManager.Show({ source = "test", text = "Soak", duration = 5 })
            assert.same({ "Soak" }, Speech.spoken)
        end)

        it("applies wrap and omits the countdown", function()
            BossAlert:SetCalloutTtsEnabled(true)
            CalloutManager.Show({
                source = "test",
                text = "X",
                wrap = "Go %s drop",
                duration = 15,
                appendTimer = true,
            })
            assert.same({ "Go X drop" }, Speech.spoken)
        end)

        it("speaks again when a newer message replaces the current one", function()
            BossAlert:SetCalloutTtsEnabled(true)
            CalloutManager.Show({ source = "test", text = "First", duration = 5 })
            CalloutManager.Show({ source = "test", text = "Second", duration = 5 })
            assert.same({ "First", "Second" }, Speech.spoken)
        end)

        it("does not speak a secret callout", function()
            local secret = {}
            issecretvalue = function(value)
                return value == secret
            end
            BossAlert:SetCalloutTtsEnabled(true)
            CalloutManager.Show({ source = "test", text = secret, duration = 5, wrap = "Go %s drop" })
            assert.same({}, Speech.spoken)
        end)

        it("does not speak when a message hides", function()
            BossAlert:SetCalloutTtsEnabled(true)
            CalloutManager.Show({ source = "test", text = "Soak", duration = 3 })
            Timer.Advance(3)
            assert.same({ "Soak" }, Speech.spoken)
        end)

        it("keeps TTS on when appearance is reset", function()
            BossAlert:SetCalloutTtsEnabled(true)
            BossAlert:ResetCalloutAppearance()
            assert.is_true(BossAlert:IsCalloutTtsEnabled())
        end)
    end)

    it("sanitizes saved callout values on init", function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load({
            modules = {
                BossAlert = {
                    callout = {
                        scale = 9,
                        font = "",
                        fontSize = 2,
                        fontColor = { r = 5, g = -2, b = 0.3 },
                        tts = "yes",
                    },
                },
            },
        }))
        BossAlert = ns.Modules.Get("BossAlert")
        AssertNear(BossAlert.CALLOUT_SCALE_MAX, BossAlert:GetCalloutScale())
        assert.equals(ns.SharedMedia.FONT_DEFAULT, BossAlert:GetCalloutFont())
        assert.equals(BossAlert.CALLOUT_FONT_SIZE_MIN, BossAlert:GetCalloutFontSize())
        local color = BossAlert:GetCalloutFontColor()
        assert.equals(1, color.r)
        assert.equals(0, color.g)
        assert.equals(0.3, color.b)
        assert.is_false(BossAlert:IsCalloutTtsEnabled())
    end)
end)
