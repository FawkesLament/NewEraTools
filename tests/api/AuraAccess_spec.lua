-- Production api/Aura.lua spell-filter and slot-access rules. Needs the Unit fake from Loader.
-- Does not start modules.

local Loader = require("helpers.loader")

describe("Aura filters", function()
    local ns
    local savedIsSecret
    local savedSecrets

    before_each(function()
        ns = Loader.Load()
        savedIsSecret = issecretvalue
        savedSecrets = C_Secrets
    end)

    after_each(function()
        issecretvalue = savedIsSecret
        C_Secrets = savedSecrets
    end)

    it("builds includeSpellIDs as a spell-ID set", function()
        local filters = ns.Api.Aura.BuildIncludeSpellFilters(774)
        assert.is_true(filters.includeSpellIDs[774])
        assert.is_nil(filters.includeSpellIDs[1])
    end)

    it("allows spell filtering for player buffs and for harmful auras on non-assistable units", function()
        local Aura = ns.Api.Aura
        assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_PLAYER, Aura.FILTER_HELPFUL))
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_PLAYER, Aura.FILTER_HARMFUL))
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HELPFUL))
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HELPFUL))
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

        ns.Api.Unit.SetForTests("target", {
            exists = true,
            guid = "Creature-1",
            canAssist = false,
        })
        assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

        ns.Api.Unit.SetForTests("focus", {
            exists = true,
            guid = "Creature-2",
            canAssist = false,
        })
        assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HARMFUL))
    end)

    it("denies method access on a slot button while aura secrecy blocks tainted code", function()
        local Aura = ns.Api.Aura
        local open = {
            CanBeAccessedInContext = function()
                return true
            end,
        }
        local denied = {
            CanBeAccessedInContext = function()
                return false
            end,
        }
        local throwing = {
            CanBeAccessedInContext = function()
                error("forbidden")
            end,
        }
        local forbidden = {
            IsForbidden = function()
                return true
            end,
        }
        assert.is_true(Aura.CanAccessObject(open))
        assert.is_false(Aura.CanAccessObject(denied))
        assert.is_false(Aura.CanAccessObject(throwing))
        assert.is_false(Aura.CanAccessObject(forbidden))
        assert.is_true(Aura.CanAccessObject({}))
        assert.is_false(Aura.CanAccessObject(nil))

        local sentinel = {}
        issecretvalue = function(value)
            return value == sentinel
        end
        local secretResult = {
            CanBeAccessedInContext = function()
                return sentinel
            end,
        }
        assert.is_false(Aura.CanAccessObject(secretResult))
        issecretvalue = savedIsSecret

        C_Secrets = {
            ShouldAurasBeSecret = function()
                return true
            end,
        }
        assert.is_false(Aura.CanAccessObject({}))
    end)

    it("refuses the spell filter for a missing, friendly, or secret-reaction unit", function()
        local Aura = ns.Api.Aura
        local Unit = ns.Api.Unit
        Unit.SetForTests("target", { exists = false, canAssist = false })
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

        Unit.SetForTests("target", {
            exists = true,
            guid = "Player-2",
            canAssist = true,
        })
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

        Unit.SetForTests("focus", { exists = true, guid = "Creature-3" })
        assert.is_nil(Unit.CanPlayerAssist("focus"))
        assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HARMFUL))
    end)
end)
