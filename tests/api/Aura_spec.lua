-- Production api/Aura.lua for the engine option helpers.
-- Feature specs load the same file through Loader and do not call these helpers.

local function Load()
    local ns = { Api = {} }
    assert(loadfile("api/Aura.lua"))("NewEraTools", ns)
    return ns.Api.Aura
end

describe("Aura production options", function()
    local saved = {}

    before_each(function()
        saved.Enum = Enum
        saved.C_AddOns = C_AddOns
        saved.C_StringUtil = C_StringUtil
        saved.AuraContainerSortMethod = AuraContainerSortMethod
        saved.AuraContainerSortDirection = AuraContainerSortDirection
    end)

    after_each(function()
        Enum = saved.Enum
        C_AddOns = saved.C_AddOns
        C_StringUtil = saved.C_StringUtil
        AuraContainerSortMethod = saved.AuraContainerSortMethod
        AuraContainerSortDirection = saved.AuraContainerSortDirection
    end)

    it("returns remaining-time duration bar options from Enum", function()
        Enum = {
            StatusBarTimerDirection = { RemainingTime = "remaining" },
        }
        local Aura = Load()
        local bare = Aura.GetDurationBarOptions()
        assert.equals("remaining", bare.direction)
        assert.is_nil(bare.interpolation)

        Enum.StatusBarInterpolation = { ExponentialEaseOut = "ease" }
        local eased = Aura.GetDurationBarOptions()
        assert.equals("remaining", eased.direction)
        assert.equals("ease", eased.interpolation)
    end)

    it("returns the expiration sort constants", function()
        AuraContainerSortMethod = { Expiration = "expiration" }
        AuraContainerSortDirection = { Normal = "normal" }
        local method, direction = Load().GetExpirationSort()
        assert.equals("expiration", method)
        assert.equals("normal", direction)
    end)

    it("returns false from EnsureLoaded when C_AddOns is unavailable", function()
        C_AddOns = nil
        assert.is_false(Load().EnsureLoaded())
    end)

    it("builds application bar options with maxApplications", function()
        local options = Load().GetApplicationBarOptions(12)
        assert.equals(12, options.maxApplications)
    end)

    it("clamps application count display so a single stack is 1, not 0", function()
        local breakpoints
        C_StringUtil = {
            CreateNumericRuleFormatter = function()
                return {
                    SetBreakpoints = function(_, points)
                        breakpoints = points
                    end,
                }
            end,
        }
        local options = Load().GetApplicationCountOptions()
        assert(options.formatter)
        assert.equals(0, breakpoints[1].threshold)
        assert.equals("%d", breakpoints[1].format)
        -- auraData.applications is 0 at one stack; min raises that to 1.
        assert.equals(1, breakpoints[1].min)
    end)
end)
