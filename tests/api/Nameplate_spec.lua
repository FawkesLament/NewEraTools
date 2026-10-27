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

    it("accepts plain nameplate tokens and rejects secret or other units", function()
        local savedIsSecret = issecretvalue
        local SECRET = {}
        issecretvalue = function(value)
            return value == SECRET
        end
        assert.is_true(Nameplate.IsUnitToken("nameplate1"))
        assert.is_true(Nameplate.IsUnitToken("nameplate40"))
        assert.is_false(Nameplate.IsUnitToken("namePlate1"))
        assert.is_false(Nameplate.IsUnitToken("player"))
        assert.is_false(Nameplate.IsUnitToken("nameplate"))
        assert.is_false(Nameplate.IsUnitToken("nameplate1x"))
        assert.is_false(Nameplate.IsUnitToken(""))
        assert.is_false(Nameplate.IsUnitToken(nil))
        assert.is_false(Nameplate.IsUnitToken(SECRET))
        assert.is_nil(Nameplate.GetFrame(SECRET))

        local seen = {}
        visiblePlates[1] = { namePlateUnitToken = SECRET }
        visiblePlates[2] = { namePlateUnitToken = "nameplate1" }
        Nameplate.ForEachVisible(function(unit)
            seen[#seen + 1] = unit
        end)
        assert.same({ "nameplate1" }, seen)
        issecretvalue = savedIsSecret
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

    it("resolves GetFrame for secret nameplate tokens without comparing them", function()
        local savedIsSecret = issecretvalue
        local SECRET = {}
        local plate = { namePlateUnitToken = SECRET }
        issecretvalue = function(value)
            return value == SECRET
        end
        framesByUnit[SECRET] = plate
        assert.equals(plate, Nameplate.GetFrame(SECRET))
        assert.equals(SECRET, Nameplate.GetUnit(plate))
        issecretvalue = savedIsSecret
    end)

    it("walks every visible plate even when the unit token is secret or missing", function()
        local savedIsSecret = issecretvalue
        local SECRET = {}
        issecretvalue = function(value)
            return value == SECRET
        end
        local plateA = { namePlateUnitToken = SECRET }
        local plateB = { namePlateUnitToken = "nameplate2" }
        visiblePlates[1] = plateA
        visiblePlates[2] = plateB
        visiblePlates[3] = { namePlateUnitToken = "" }
        local seen = {}
        Nameplate.ForEachPlate(function(frame)
            seen[#seen + 1] = frame
        end)
        assert.equals(3, #seen)
        assert.equals(plateA, seen[1])
        issecretvalue = savedIsSecret
    end)

    it("uses Blizzard UnitFrame as the click host when Plater is not present", function()
        local unitFrame = {}
        local plate = { UnitFrame = unitFrame }
        local bare = { namePlateUnitToken = "nameplate1" }
        assert.equals(unitFrame, Nameplate.GetHost(plate))
        assert.equals(bare, Nameplate.GetHost(bare))
        assert.is_nil(Nameplate.GetHost(nil))
    end)

    it("uses Plater's hit-test frame as the click host instead of the hidden Blizzard UnitFrame", function()
        local blizzardUnitFrame = {}
        local hitTest = {}
        local platerUnitFrame = { Plater = true, hitTestFrame = hitTest }
        local plate = {
            Plater = true,
            UnitFrame = blizzardUnitFrame,
            unitFrame = platerUnitFrame,
        }
        assert.equals(hitTest, Nameplate.GetHost(plate))
        platerUnitFrame.hitTestFrame = nil
        assert.equals(platerUnitFrame, Nameplate.GetHost(plate))
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
