-- Production api/Player.lua. Feature specs keep tests/helpers/fakes/Player.lua.

describe("Player production", function()
    local saved = {}

    local function SaveGlobals()
        saved.C_SpecializationInfo = C_SpecializationInfo
        saved.GetSpecializationInfoByID = GetSpecializationInfoByID
    end

    local function Load()
        local ns = { Api = {} }
        assert(loadfile("api/Player.lua"))("NewEraTools", ns)
        return ns.Api.Player
    end

    before_each(function()
        SaveGlobals()
        C_SpecializationInfo = nil
        GetSpecializationInfoByID = nil
    end)

    after_each(function()
        C_SpecializationInfo = saved.C_SpecializationInfo
        GetSpecializationInfoByID = saved.GetSpecializationInfoByID
    end)

    it("returns the specialization icon from the client", function()
        GetSpecializationInfoByID = function(specId)
            if specId == 105 then
                return specId, "Restoration", "desc", 136041, "HEALER"
            end
        end
        local Player = Load()

        assert.equals(136041, Player.GetSpecializationIcon(105))
    end)

    it("returns nil when the specialization or its icon is missing", function()
        GetSpecializationInfoByID = function()
            return 105, "Restoration", "desc", "", "HEALER"
        end
        local Player = Load()

        assert.is_nil(Player.GetSpecializationIcon(nil))
        assert.is_nil(Player.GetSpecializationIcon(0))
        assert.is_nil(Player.GetSpecializationIcon(105))

        GetSpecializationInfoByID = nil
        Player = Load()
        assert.is_nil(Player.GetSpecializationIcon(105))
    end)
end)
