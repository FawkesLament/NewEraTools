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

        it("returns default enabled, left side, and normal mode", function()
            assert.same({
                enabled = true,
                side = Sszorak.SIDE_LEFT,
                mode = Sszorak.CALLOUT_MODE_NORMAL,
            }, InspectConfig())
        end)

        it("represents every valid side and mode combination", function()
            local cases = {
                { rotated = false, mode = Sszorak.CALLOUT_MODE_NORMAL, side = Sszorak.SIDE_LEFT },
                { rotated = true, mode = Sszorak.CALLOUT_MODE_NORMAL, side = Sszorak.SIDE_RIGHT },
                { rotated = false, mode = Sszorak.CALLOUT_MODE_JAILBREAK, side = Sszorak.SIDE_LEFT },
                { rotated = true, mode = Sszorak.CALLOUT_MODE_JAILBREAK, side = Sszorak.SIDE_RIGHT },
            }
            for _, case in ipairs(cases) do
                Sszorak:SetMapRotated(case.rotated)
                Sszorak:SetCalloutMode(case.mode)
                assert.same({
                    enabled = true,
                    side = case.side,
                    mode = case.mode,
                }, InspectConfig())
            end
        end)

        it("reflects enablement and side changes on the next GetConfig call", function()
            assert.equals(true, InspectConfig().enabled)
            assert.equals(Sszorak.SIDE_LEFT, InspectConfig().side)
            Sszorak:SetMapEnabled(false)
            assert.equals(false, InspectConfig().enabled)
            Sszorak:SetMapEnabled(true)
            assert.equals(true, InspectConfig().enabled)
            Sszorak:SetMapRotated(true)
            assert.equals(Sszorak.SIDE_RIGHT, InspectConfig().side)
            Sszorak:SetMapRotated(false)
            assert.equals(Sszorak.SIDE_LEFT, InspectConfig().side)
        end)

        it("does not mutate saved configuration when inspected", function()
            Sszorak:SetMapRotated(true)
            local beforeEnabled = Sszorak.db.mapEnabled
            local beforeRotated = Sszorak.db.mapRotated
            local beforeMode = Sszorak.db.calloutMode
            local snapshot = InspectConfig()
            snapshot.enabled = false
            snapshot.side = "mutated"
            snapshot.mode = "mutated"
            assert.equals(beforeEnabled, Sszorak.db.mapEnabled)
            assert.equals(beforeRotated, Sszorak.db.mapRotated)
            assert.equals(beforeMode, Sszorak.db.calloutMode)
            assert.equals(true, InspectConfig().enabled)
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

        it("fails safely on invalid mapRotated", function()
            Sszorak.db.mapRotated = "yes"
            local config, err = InspectConfig()
            assert.equals(nil, config)
            assert.equals("provider_failed", err)
        end)

        it("fails safely on invalid calloutMode", function()
            Sszorak.db.calloutMode = "banana"
            local config, err = InspectConfig()
            assert.equals(nil, config)
            assert.equals("provider_failed", err)
        end)

        it("fails safely when calloutMode is unavailable", function()
            -- Simulate an unregistered mode id that still passes the known-mode string check.
            local realAvailable = Sszorak.IsCalloutModeAvailable
            Sszorak.IsCalloutModeAvailable = function(modeId)
                if modeId == Sszorak.CALLOUT_MODE_JAILBREAK then
                    return false
                end
                return realAvailable(modeId)
            end
            Sszorak.db.calloutMode = Sszorak.CALLOUT_MODE_JAILBREAK
            local config, err = InspectConfig()
            Sszorak.IsCalloutModeAvailable = realAvailable
            assert.equals(nil, config)
            assert.equals("provider_failed", err)
        end)
    end)
end)
