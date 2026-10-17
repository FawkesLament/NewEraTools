local Harness = require("helpers.sszorak")
local Loader = require("helpers.loader")

describe("SszorakCallout", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    describe("callout mode", function()
        it("defaults to normal", function()
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("registers jailbreak alongside normal", function()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
        end)

        it("preserves a saved jailbreak mode", function()
            ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak.db.calloutMode)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
        end)

        it("switches between normal and jailbreak", function()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetActiveCalloutMode().id)
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_NORMAL)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("rejects unknown modes", function()
            assert.is_false(pcall(Sszorak.SetCalloutMode, Sszorak, "banana"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("requires Listen and OnMatchedWarning on registered modes", function()
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
            }))
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return function() end
                end,
            }))
        end)
    end)
end)
