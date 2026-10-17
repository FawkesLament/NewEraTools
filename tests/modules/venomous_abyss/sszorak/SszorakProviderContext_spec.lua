local Fs = require("helpers.fs")
local Harness = require("helpers.sszorak")

describe("Sszorak communication capabilities", function()
    local ns, Sszorak, capabilities

    before_each(function()
        ns, Sszorak = Harness.Start()
        capabilities = NewEraToolsAPI.GetCapabilities(Sszorak.COMMUNICATION_EXTENSION)
    end)

    it("publishes one read-only context grouped by responsibility", function()
        assert.equals(1, capabilities.version)
        assert.is_nil(capabilities.GetText)
        assert.is_nil(capabilities.ns)
        assert.is_nil(capabilities.player)
        assert.is_nil(capabilities.markers)
        assert.is_nil(capabilities.arena)
        assert.is_nil(capabilities.events.SubscribeRaidWarning)
        assert.is_nil(capabilities.events.IsExitAnchor)
        assert.is_nil(capabilities.events.AnchorSlot)
        assert.is_nil(capabilities.time)
        assert.is_nil(capabilities.presentation)
        assert.equals("function", type(capabilities.events.SubscribeViscousCystWarning))

        local rootOk = pcall(function()
            capabilities.version = 2
        end)
        local groupOk = pcall(function()
            capabilities.events.SubscribeViscousCystWarning = function() end
        end)
        assert.is_false(rootOk)
        assert.is_false(groupOk)
        assert.equals(1, capabilities.version)
    end)

    it("clears the displayed callout from the shared capture boundaries", function()
        for _, reset in ipairs({
            function()
                Sszorak:BeginCalloutCapture()
            end,
            function()
                Sszorak:EndCalloutCapture()
            end,
            function()
                Sszorak:ClearCalloutMessages()
            end,
        }) do
            Sszorak.ShowResolvedCallout({ hudMessage = "shown", targetEdge = 2 }, 10, false)
            reset()
            assert.is_nil(Sszorak:GetDisplayedCallout())
        end
    end)

    it("publishes capabilities without a jailbreak provider", function()
        assert.is_nil(ns.Extensions.Get(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK))
        assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
        assert.is_false(Fs.Exists("modules/venomous_abyss/sszorak/communication/Jailbreak.lua"))
    end)
end)
