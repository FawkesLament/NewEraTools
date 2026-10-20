local Harness = require("helpers.sszorak")

describe("Sszorak", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    it("is registered with saved settings", function()
        assert.is_false(Sszorak == nil)
        assert.equals("table", type(Sszorak.db))
    end)

    describe("raid role", function()
        it("is member unless the player is the raid leader", function()
            local Group = ns.Api.Group
            assert.equals(Sszorak.RAID_ROLE_MEMBER, Sszorak:GetRaidRole())
            assert.is_false(Sszorak:IsRaidCommander())
            Group.isRaidLeader = true
            assert.equals(Sszorak.RAID_ROLE_COMMANDER, Sszorak:GetRaidRole())
            assert.is_true(Sszorak:IsRaidCommander())
        end)
    end)

    describe("AddonCheck configuration provider", function()
        ---Dev/test inspection path: AddonCheck.GetConfig(Sszorak.ADDON_CHECK_MODULE_ID).
        local function InspectConfig()
            return ns.AddonCheck.GetConfig(Sszorak.ADDON_CHECK_MODULE_ID)
        end

        it("registers on module init without opening the settings UI", function()
            assert.is_true(ns.AddonCheck.IsRegistered(Sszorak.ADDON_CHECK_MODULE_ID))
            assert.equals("Sszorak", Sszorak.ADDON_CHECK_MODULE_ID)
        end)

        it("returns the map off, the left side, and normal mode", function()
            assert.same({
                enabled = false,
                side = Sszorak.SIDE_LEFT,
                mode = Sszorak.CALLOUT_MODE_NORMAL,
            }, InspectConfig())
        end)

        it("represents every valid side and mode combination", function()
            NewEraToolsAPI.RegisterExtension(Sszorak.COMMUNICATION_EXTENSION, Sszorak.CALLOUT_MODE_JAILBREAK, {
                id = Sszorak.CALLOUT_MODE_JAILBREAK,
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return function() end
                end,
                OnViscousCystWarning = function()
                    return nil
                end,
            })
            local cases = {
                { mode = Sszorak.CALLOUT_MODE_NORMAL, side = Sszorak.SIDE_LEFT },
                { mode = Sszorak.CALLOUT_MODE_NORMAL, side = Sszorak.SIDE_RIGHT },
                { mode = Sszorak.CALLOUT_MODE_JAILBREAK, side = Sszorak.SIDE_LEFT },
                { mode = Sszorak.CALLOUT_MODE_JAILBREAK, side = Sszorak.SIDE_RIGHT },
            }
            for _, case in ipairs(cases) do
                Sszorak:SetPlayerSide(case.side)
                Sszorak:SetCalloutMode(case.mode)
                assert.same({
                    enabled = false,
                    side = case.side,
                    mode = case.mode,
                }, InspectConfig())
            end
        end)

        it("reflects enablement and side changes on the next GetConfig call", function()
            assert.equals(false, InspectConfig().enabled)
            assert.equals(Sszorak.SIDE_LEFT, InspectConfig().side)
            Sszorak:SetMapEnabled(true)
            assert.equals(true, InspectConfig().enabled)
            Sszorak:SetMapEnabled(false)
            assert.equals(false, InspectConfig().enabled)
            Sszorak:SetPlayerSide(Sszorak.SIDE_RIGHT)
            assert.equals(Sszorak.SIDE_RIGHT, InspectConfig().side)
            Sszorak:SetPlayerSide(Sszorak.SIDE_LEFT)
            assert.equals(Sszorak.SIDE_LEFT, InspectConfig().side)
        end)

        it("does not mutate saved configuration when inspected", function()
            Sszorak:SetPlayerSide(Sszorak.SIDE_RIGHT)
            local beforeEnabled = Sszorak.db.mapEnabled
            local beforeSide = Sszorak.db.playerSide
            local beforeMode = Sszorak.db.calloutMode
            local snapshot = InspectConfig()
            snapshot.enabled = false
            snapshot.side = "mutated"
            snapshot.mode = "mutated"
            assert.equals(beforeEnabled, Sszorak.db.mapEnabled)
            assert.equals(beforeSide, Sszorak.db.playerSide)
            assert.equals(beforeMode, Sszorak.db.calloutMode)
            assert.equals(false, InspectConfig().enabled)
            assert.equals(Sszorak.SIDE_RIGHT, InspectConfig().side)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, InspectConfig().mode)
        end)

        it("fails safely on invalid mapEnabled", function()
            Sszorak.db.mapEnabled = "yes"
            local config, err = InspectConfig()
            assert.equals(nil, config)
            assert.equals("provider_failed", err)
        end)

        it("validates enabled and mode against the commander snapshot", function()
            local localConfig = {
                enabled = true,
                side = Sszorak.SIDE_LEFT,
                mode = Sszorak.CALLOUT_MODE_NORMAL,
            }
            assert.is_nil(Sszorak.ValidateAddonCheckConfig({
                enabled = true,
                side = Sszorak.SIDE_RIGHT,
                mode = Sszorak.CALLOUT_MODE_NORMAL,
            }, localConfig))
            assert.same(
                { "enabled" },
                Sszorak.ValidateAddonCheckConfig({
                    enabled = false,
                    side = Sszorak.SIDE_LEFT,
                    mode = Sszorak.CALLOUT_MODE_NORMAL,
                }, localConfig)
            )
            assert.same(
                { "mode" },
                Sszorak.ValidateAddonCheckConfig({
                    enabled = true,
                    side = Sszorak.SIDE_LEFT,
                    mode = Sszorak.CALLOUT_MODE_JAILBREAK,
                }, localConfig)
            )
            assert.same(
                { "enabled", "mode" },
                Sszorak.ValidateAddonCheckConfig({
                    enabled = false,
                    side = Sszorak.SIDE_LEFT,
                    mode = Sszorak.CALLOUT_MODE_JAILBREAK,
                }, localConfig)
            )
        end)

        it("fails safely on invalid playerSide", function()
            Sszorak.db.playerSide = "yes"
            local config, err = InspectConfig()
            assert.equals(nil, config)
            assert.equals("provider_failed", err)
        end)

        it("reports normal and announces when the saved mode is unavailable", function()
            local printed = {}
            ns.Util.Print = function(message)
                printed[#printed + 1] = message
            end
            Sszorak.db.calloutMode = "banana"
            local config, err = InspectConfig()
            assert.is_nil(err)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, config.mode)
            assert.equals("banana", Sszorak.db.calloutMode)
            assert.same({ string.format(ns.L.SSZORAK_CALLOUT_MODE_UNAVAILABLE, "banana") }, printed)

            Sszorak.db.calloutMode = Sszorak.CALLOUT_MODE_JAILBREAK
            config, err = InspectConfig()
            assert.is_nil(err)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, config.mode)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak.db.calloutMode)
            InspectConfig()
            assert.same({
                string.format(ns.L.SSZORAK_CALLOUT_MODE_UNAVAILABLE, "banana"),
                string.format(ns.L.SSZORAK_CALLOUT_MODE_UNAVAILABLE, Sszorak.CALLOUT_MODE_JAILBREAK),
            }, printed)
        end)
    end)
end)
