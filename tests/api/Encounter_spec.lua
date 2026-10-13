local Loader = require("helpers.loader")

describe("Encounter.WhileIn", function()
    local ns, Encounter

    before_each(function()
        ns = Loader.Load()
        Encounter = ns.Api.Encounter
    end)

    it("runs setup on matching start and cleanup on matching end", function()
        local setups, cleanups = 0, 0
        local handle = Encounter.WhileIn(10, function()
            setups = setups + 1
            return function()
                cleanups = cleanups + 1
            end
        end)

        Encounter.FireStart(9, "Other", 16, 20)
        assert.equals(0, setups)
        assert.is_false(handle:IsInside())
        assert.is_false(handle:IsActive())

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.equals(1, setups)
        assert.is_true(handle:IsInside())
        assert.is_true(handle:IsActive())

        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        assert.equals(1, cleanups)
        assert.is_false(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)

    it("tears down and re-runs setup when disabled then re-enabled mid-fight", function()
        local setups, cleanups = 0, 0
        local handle = Encounter.WhileIn(10, function()
            setups = setups + 1
            return function()
                cleanups = cleanups + 1
            end
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.equals(1, setups)

        handle:SetEnabled(false)
        assert.equals(1, cleanups)
        assert.is_true(handle:IsInside())
        assert.is_false(handle:IsActive())

        handle:SetEnabled(true)
        assert.equals(2, setups)
        assert.is_true(handle:IsActive())
    end)

    it("does not run setup while disabled even if the encounter is active", function()
        local setups = 0
        local handle = Encounter.WhileIn(10, function()
            setups = setups + 1
            return function() end
        end)
        handle:SetEnabled(false)

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.equals(0, setups)
        assert.is_true(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)

    it("ignores a nil cleanup from setup", function()
        local handle = Encounter.WhileIn(10, function()
            return nil
        end)
        Encounter.FireStart(10, "Boss", 16, 20)
        assert.is_true(handle:IsActive())
        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        assert.is_false(handle:IsActive())
    end)
end)
