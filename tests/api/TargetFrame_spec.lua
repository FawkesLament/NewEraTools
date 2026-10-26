local function Load()
    local ns = {
        Api = {
            GameEvents = dofile("tests/helpers/fakes/GameEvents.lua")(),
            Timer = dofile("tests/helpers/fakes/Timer.lua")(),
        },
    }
    _G.TargetFrame = nil
    _G.EllesmereUIUnitFrames_Target = nil
    assert(loadfile("api/TargetFrame.lua"))("NewEraTools", ns)
    return ns.Api.TargetFrame, ns
end

local function NamedFrame(name, unit)
    return {
        name = name,
        unit = unit,
        GetName = function(self)
            return self.name
        end,
        GetAttribute = function(self, key)
            if key == "unit" then
                return self.unit
            end
            return nil
        end,
        IsForbidden = function()
            return false
        end,
    }
end

describe("TargetFrame production", function()
    local savedTarget
    local savedEllesmere
    local savedAddOns

    before_each(function()
        savedTarget = _G.TargetFrame
        savedEllesmere = _G.EllesmereUIUnitFrames_Target
        savedAddOns = C_AddOns
        C_AddOns = {
            IsAddOnLoaded = function()
                return false
            end,
        }
    end)

    after_each(function()
        _G.TargetFrame = savedTarget
        _G.EllesmereUIUnitFrames_Target = savedEllesmere
        C_AddOns = savedAddOns
    end)

    it("returns the default TargetFrame and rejects FocusFrame or forbidden frames", function()
        local TargetFrame = Load()
        assert.is_nil(TargetFrame.GetFrame())

        local target = NamedFrame("TargetFrame")
        _G.TargetFrame = target
        assert.equals(target, TargetFrame.GetFrame())

        target.name = "FocusFrame"
        assert.is_nil(TargetFrame.GetFrame())

        target.name = "TargetFrame"
        target.IsForbidden = function()
            return true
        end
        assert.is_nil(TargetFrame.GetFrame())
    end)

    it("prefers the EllesmereUI Target Frame when that addon has spawned it", function()
        local TargetFrame = Load()
        local blizzard = NamedFrame("TargetFrame")
        local eui = NamedFrame("EllesmereUIUnitFrames_Target", "target")
        _G.TargetFrame = blizzard
        _G.EllesmereUIUnitFrames_Target = eui
        C_AddOns.IsAddOnLoaded = function(name)
            return name == "EllesmereUIUnitFrames"
        end
        assert.equals(eui, TargetFrame.GetFrame())
    end)

    it("ignores EllesmereUI Player, Focus, and ToT frames", function()
        local TargetFrame = Load()
        local blizzard = NamedFrame("TargetFrame")
        _G.TargetFrame = blizzard
        C_AddOns.IsAddOnLoaded = function(name)
            return name == "EllesmereUIUnitFrames"
        end

        _G.EllesmereUIUnitFrames_Target = NamedFrame("EllesmereUIUnitFrames_Focus", "focus")
        assert.equals(blizzard, TargetFrame.GetFrame())

        _G.EllesmereUIUnitFrames_Target = NamedFrame("EllesmereUIUnitFrames_Target", "focus")
        assert.equals(blizzard, TargetFrame.GetFrame())

        _G.EllesmereUIUnitFrames_Target = NamedFrame("EllesmereUIUnitFrames_TargetTarget", "targettarget")
        assert.equals(blizzard, TargetFrame.GetFrame())
    end)

    it("falls back to Blizzard while EllesmereUI is missing or has not spawned the Target Frame", function()
        local TargetFrame = Load()
        local blizzard = NamedFrame("TargetFrame")
        _G.TargetFrame = blizzard
        _G.EllesmereUIUnitFrames_Target = NamedFrame("EllesmereUIUnitFrames_Target", "target")
        assert.equals(blizzard, TargetFrame.GetFrame())

        C_AddOns.IsAddOnLoaded = function(name)
            return name == "EllesmereUIUnitFrames"
        end
        _G.EllesmereUIUnitFrames_Target = nil
        assert.equals(blizzard, TargetFrame.GetFrame())
    end)

    it("notifies once EllesmereUI loads and again after the deferred spawn", function()
        local TargetFrame, ns = Load()
        local fires = 0
        TargetFrame.OnReady(function()
            fires = fires + 1
        end)
        ns.Api.GameEvents.Fire("ADDON_LOADED", "SomeOtherAddon")
        assert.equals(0, fires)
        ns.Api.GameEvents.Fire("ADDON_LOADED", "EllesmereUIUnitFrames")
        assert.equals(1, fires)
        ns.Api.Timer.Advance(0)
        assert.equals(2, fires)
        ns.Api.GameEvents.Fire("PLAYER_LOGIN")
        assert.equals(3, fires)
    end)
end)
