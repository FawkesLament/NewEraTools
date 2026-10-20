-- Production api/Nameplate.lua. Feature specs keep tests/helpers/fakes/Nameplate.lua.

local function Load()
    local listeners = {}
    local ns = {
        Api = {
            GameEvents = {
                Listen = function(event, handler)
                    listeners[event] = listeners[event] or {}
                    table.insert(listeners[event], handler)
                    return function()
                        local list = listeners[event]
                        if not list then
                            return
                        end
                        for index, candidate in ipairs(list) do
                            if candidate == handler then
                                table.remove(list, index)
                                return
                            end
                        end
                    end
                end,
            },
        },
    }
    assert(loadfile("api/Nameplate.lua"))("NewEraTools", ns)
    return ns.Api.Nameplate, listeners
end

local function Fire(listeners, event, ...)
    local list = listeners[event]
    if not list then
        return
    end
    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        snapshot[i](...)
    end
end

describe("Nameplate production", function()
    local Nameplate, listeners
    local framesByUnit
    local visiblePlates
    local savedCNamePlate

    before_each(function()
        savedCNamePlate = C_NamePlate
        framesByUnit = {}
        visiblePlates = {}
        C_NamePlate = {
            GetNamePlateForUnit = function(unit)
                return framesByUnit[unit]
            end,
            GetNamePlates = function()
                return visiblePlates
            end,
        }
        Nameplate, listeners = Load()
    end)

    after_each(function()
        C_NamePlate = savedCNamePlate
    end)

    it("returns the Blizzard nameplate frame for a unit token", function()
        local frame = { namePlateUnitToken = "nameplate1" }
        framesByUnit.nameplate1 = frame
        assert.equals(frame, Nameplate.GetFrame("nameplate1"))
        assert.is_nil(Nameplate.GetFrame("nameplate2"))
        assert.is_nil(Nameplate.GetFrame(""))
        assert.is_nil(Nameplate.GetFrame(nil))
    end)

    it("resolves OnAdded through GetNamePlateForUnit and skips missing frames", function()
        local seen = {}
        Nameplate.OnAdded(function(unit, frame)
            seen[#seen + 1] = { unit = unit, frame = frame }
        end)
        local plate = { namePlateUnitToken = "nameplate1" }
        Fire(listeners, "NAME_PLATE_UNIT_ADDED", "nameplate1")
        assert.same({}, seen)

        framesByUnit.nameplate1 = plate
        Fire(listeners, "NAME_PLATE_UNIT_ADDED", "nameplate1")
        assert.same({ { unit = "nameplate1", frame = plate } }, seen)
    end)

    it("forwards OnRemoved unit tokens and honors unsubscribe", function()
        local seen = {}
        local unsubscribe = Nameplate.OnRemoved(function(unit)
            seen[#seen + 1] = unit
        end)
        Fire(listeners, "NAME_PLATE_UNIT_REMOVED", "nameplate3")
        unsubscribe()
        Fire(listeners, "NAME_PLATE_UNIT_REMOVED", "nameplate4")
        assert.same({ "nameplate3" }, seen)
    end)

    it("walks currently visible Blizzard nameplates by namePlateUnitToken", function()
        local plateA = { namePlateUnitToken = "nameplate1" }
        local plateB = { namePlateUnitToken = "nameplate2" }
        visiblePlates[1] = plateA
        visiblePlates[2] = plateB
        visiblePlates[3] = { namePlateUnitToken = "" }
        local seen = {}
        Nameplate.ForEachVisible(function(unit, frame)
            seen[#seen + 1] = { unit = unit, frame = frame }
        end)
        assert.same({
            { unit = "nameplate1", frame = plateA },
            { unit = "nameplate2", frame = plateB },
        }, seen)
    end)
end)
