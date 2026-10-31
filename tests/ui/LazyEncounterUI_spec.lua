local Loader = require("helpers.loader")

describe("LazyEncounterUI", function()
    local LazyEncounterUI

    local function NewHelper(hooks)
        return LazyEncounterUI.Create({
            create = function()
                hooks.creates = hooks.creates + 1
                local instance = {}
                hooks.instances[#hooks.instances + 1] = instance
                return instance
            end,
            activate = function(instance)
                hooks.activates = hooks.activates + 1
                hooks.activated[#hooks.activated + 1] = instance
            end,
            deactivate = function(instance)
                hooks.deactivates = hooks.deactivates + 1
                hooks.deactivated[#hooks.deactivated + 1] = instance
            end,
        })
    end

    local function NewHooks()
        return {
            creates = 0,
            activates = 0,
            deactivates = 0,
            instances = {},
            activated = {},
            deactivated = {},
        }
    end

    before_each(function()
        LazyEncounterUI = Loader.Load().LazyEncounterUI
    end)

    it("creates exactly one instance on first Prepare", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:Prepare()
        assert.equals(1, hooks.creates)
        assert.equals(1, #hooks.instances)
        assert.equals(0, hooks.activates)
        assert.equals(0, hooks.deactivates)
    end)

    it("does not recreate on later Prepare calls", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:Prepare()
        local instance = hooks.instances[1]
        ui:Prepare()
        ui:Prepare()
        assert.equals(1, hooks.creates)
        assert.equals(instance, hooks.instances[1])
        assert.equals(1, #hooks.instances)
    end)

    it("creates and activates on SetActive(true) before Prepare", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:SetActive(true)
        assert.equals(1, hooks.creates)
        assert.equals(1, hooks.activates)
        assert.equals(hooks.instances[1], hooks.activated[1])
        assert.equals(0, hooks.deactivates)
    end)

    it("does not invoke activate again while already active", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:Prepare()
        ui:SetActive(true)
        ui:SetActive(true)
        ui:SetActive(true)
        assert.equals(1, hooks.creates)
        assert.equals(1, hooks.activates)
    end)

    it("invokes deactivate once per active-to-inactive transition", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:SetActive(true)
        ui:SetActive(false)
        ui:SetActive(false)
        assert.equals(1, hooks.deactivates)
        assert.equals(hooks.instances[1], hooks.deactivated[1])
        ui:SetActive(true)
        ui:SetActive(false)
        assert.equals(2, hooks.activates)
        assert.equals(2, hooks.deactivates)
    end)

    it("does nothing when deactivated before initialization", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:SetActive(false)
        ui:SetActive(false)
        assert.equals(0, hooks.creates)
        assert.equals(0, hooks.activates)
        assert.equals(0, hooks.deactivates)
        assert.equals(0, #hooks.instances)
    end)

    it("reactivates the original instance without recreating it", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        ui:Prepare()
        local instance = hooks.instances[1]
        ui:SetActive(true)
        ui:SetActive(false)
        ui:SetActive(true)
        assert.equals(1, hooks.creates)
        assert.equals(1, #hooks.instances)
        assert.equals(instance, hooks.activated[1])
        assert.equals(instance, hooks.activated[2])
        assert.equals(instance, hooks.deactivated[1])
        assert.is_true(ui:IsPrepared())
        assert.is_true(ui:IsActive())
    end)

    it("reports prepared and active independently", function()
        local hooks = NewHooks()
        local ui = NewHelper(hooks)
        assert.is_false(ui:IsPrepared())
        assert.is_false(ui:IsActive())
        ui:Prepare()
        assert.is_true(ui:IsPrepared())
        assert.is_false(ui:IsActive())
        ui:SetActive(true)
        assert.is_true(ui:IsActive())
        ui:SetActive(false)
        assert.is_true(ui:IsPrepared())
        assert.is_false(ui:IsActive())
    end)
end)
