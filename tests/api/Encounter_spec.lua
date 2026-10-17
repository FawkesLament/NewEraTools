local Loader = require("helpers.loader")

describe("Encounter.WhileIn", function()
    local ns, Encounter

    local savedInstanceEncounter

    before_each(function()
        ns = Loader.Load()
        Encounter = ns.Api.Encounter
        savedInstanceEncounter = C_InstanceEncounter
    end)

    after_each(function()
        C_InstanceEncounter = savedInstanceEncounter
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
        local difficulties = {}
        local handle = Encounter.WhileIn(10, function(difficultyID)
            setups = setups + 1
            table.insert(difficulties, difficultyID)
            return function()
                cleanups = cleanups + 1
            end
        end)

        Encounter.FireStart(10, "Boss", 15, 20)
        assert.equals(1, setups)
        assert.same({ 15 }, difficulties)

        handle:SetEnabled(false)
        assert.equals(1, cleanups)
        assert.is_true(handle:IsInside())
        assert.is_false(handle:IsActive())

        handle:SetEnabled(true)
        assert.equals(2, setups)
        assert.same({ 15, 15 }, difficulties)
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

    it("passes ENCOUNTER_START difficultyID to setup", function()
        local seen
        Encounter.WhileIn(10, function(difficultyID)
            seen = difficultyID
            return function() end
        end)
        Encounter.FireStart(10, "Boss", 15, 20)
        assert.equals(15, seen)
    end)

    it("ignores ENCOUNTER_END for a different encounter", function()
        local cleanups = 0
        local handle = Encounter.WhileIn(10, function()
            return function()
                cleanups = cleanups + 1
            end
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        Encounter.FireEnd(9, "Other", 16, 20, 1)
        assert.equals(0, cleanups)
        assert.is_true(handle:IsInside())
        assert.is_true(handle:IsActive())

        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        assert.equals(1, cleanups)
        assert.is_false(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)

    it("reads IsInProgress from C_InstanceEncounter without following FireStart", function()
        assert.is_false(Encounter.IsInProgress())

        local handle = Encounter.WhileIn(10, function()
            return function() end
        end)
        Encounter.FireStart(10, "Boss", 16, 20)
        assert.is_true(handle:IsInside())
        assert.is_false(Encounter.IsInProgress())

        C_InstanceEncounter = {
            IsEncounterInProgress = function()
                return true
            end,
        }
        assert.is_true(Encounter.IsInProgress())
        assert.is_true(handle:IsInside())

        C_InstanceEncounter.IsEncounterInProgress = function()
            return 1
        end
        assert.is_false(Encounter.IsInProgress())

        C_InstanceEncounter.IsEncounterInProgress = function()
            return false
        end
        assert.is_false(Encounter.IsInProgress())
        assert.is_true(handle:IsInside())

        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        C_InstanceEncounter.IsEncounterInProgress = function()
            return true
        end
        assert.is_true(Encounter.IsInProgress())
        assert.is_false(handle:IsInside())
    end)
end)
