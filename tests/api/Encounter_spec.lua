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

    it("disposes scoped resources when the encounter ends", function()
        local cleaned = 0
        local handle = Encounter.WhileIn(10, function(_, scope)
            scope:Add(function()
                cleaned = cleaned + 1
            end)
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.equals(0, cleaned)
        assert.is_true(handle:IsActive())

        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        assert.equals(1, cleaned)
        assert.is_false(handle:IsActive())
    end)

    it("disposes scoped resources when disabled mid-fight", function()
        local cleaned = 0
        local handle = Encounter.WhileIn(10, function(_, scope)
            scope:Add(function()
                cleaned = cleaned + 1
            end)
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        handle:SetEnabled(false)
        assert.equals(1, cleaned)
        assert.is_true(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)

    it("creates a fresh scope when re-enabled mid-fight", function()
        local scopes = {}
        local handle = Encounter.WhileIn(10, function(_, scope)
            scopes[#scopes + 1] = scope
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        handle:SetEnabled(false)
        handle:SetEnabled(true)
        assert.equals(2, #scopes)
        assert(scopes[1] ~= scopes[2], "expected a new ResourceScope after re-enable")
        assert.is_true(handle:IsActive())
    end)

    it("does not accumulate warning listeners across pulls", function()
        local warnings = 0
        Encounter.WhileIn(10, function(_, scope)
            scope:Subscribe(Encounter.OnWarning, function()
                warnings = warnings + 1
            end)
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        Encounter.FireWarning({})
        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        Encounter.FireWarning({})
        Encounter.FireStart(10, "Boss", 16, 20)
        Encounter.FireWarning({})

        assert.equals(2, warnings)
    end)

    it("does not accumulate tickers across pulls", function()
        local Timer = ns.Api.Timer
        local fires = 0
        Encounter.WhileIn(10, function(_, scope)
            scope:Ticker(1, function()
                fires = fires + 1
            end)
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        Timer.Advance(1)
        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        Timer.Advance(5)
        Encounter.FireStart(10, "Boss", 16, 20)
        Timer.Advance(1)

        assert.equals(2, fires)
    end)

    it("disposes resources registered before a setup failure", function()
        local cleaned = 0
        local handle = Encounter.WhileIn(10, function(_, scope)
            scope:Add(function()
                cleaned = cleaned + 1
            end)
            error("setup failed")
        end)

        local ok, err = pcall(Encounter.FireStart, 10, "Boss", 16, 20)
        assert.is_false(ok)
        -- Re-raised without a WhileIn location prefix, with the trace from the failing setup.
        local firstLine = err:match("^[^\n]*")
        assert.is_true(firstLine:find("^[^:]*Encounter_spec%.lua:%d+: setup failed$") ~= nil)
        local trace = err:sub(#firstLine + 2)
        assert.is_true(trace:find("Encounter_spec.lua", 1, true) ~= nil)
        assert.equals(1, cleaned)
        assert.is_true(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)

    it("disposes both scoped resources and a returned cleanup", function()
        local order = {}
        Encounter.WhileIn(10, function(_, scope)
            scope:Add(function()
                order[#order + 1] = "scope"
            end)
            return function()
                order[#order + 1] = "return"
            end
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        Encounter.FireEnd(10, "Boss", 16, 20, 1)
        assert.same({ "return", "scope" }, order)
    end)

    it("does not let a superseded setup overwrite a newer activation", function()
        local handle
        local scopes = {}
        local firstCleanupImmediate = false
        handle = Encounter.WhileIn(10, function(_, scope)
            scopes[#scopes + 1] = scope
            if #scopes == 1 then
                handle:SetEnabled(false)
                handle:SetEnabled(true)
                local ran = false
                scope:Add(function()
                    ran = true
                end)
                firstCleanupImmediate = ran
            end
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.is_true(firstCleanupImmediate)
        assert.equals(2, #scopes)
        assert(scopes[1] ~= scopes[2], "expected the re-enable to own a different scope")
        assert.is_true(handle:IsEnabled())
        assert.is_true(handle:IsActive())
    end)

    it("is active during setup once the scope is installed", function()
        local handle
        local duringSetup
        handle = Encounter.WhileIn(10, function()
            duringSetup = handle:IsActive()
        end)

        assert.is_false(handle:IsActive())
        Encounter.FireStart(10, "Boss", 16, 20)
        assert.is_true(duringSetup)
        assert.is_true(handle:IsActive())
    end)

    it("disposes an in-progress setup if the encounter ends during setup", function()
        local cleaned = 0
        local handle = Encounter.WhileIn(10, function(_, scope)
            scope:Add(function()
                cleaned = cleaned + 1
            end)
            Encounter.FireEnd(10, "Boss", 16, 20, 1)
        end)

        Encounter.FireStart(10, "Boss", 16, 20)
        assert.equals(1, cleaned)
        assert.is_false(handle:IsInside())
        assert.is_false(handle:IsActive())
    end)
end)
