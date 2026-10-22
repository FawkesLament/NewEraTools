local Loader = require("helpers.loader")

describe("AuraTracker list plan", function()
    local ListPlan

    before_each(function()
        local ns = Loader.Load()
        ListPlan = ns.Modules.Internals("AuraTracker").ListPlan
    end)

    it("treats the same id order as unchanged", function()
        assert.is_true(ListPlan.SameIds({ 1, 2 }, { 1, 2 }))
        assert.is_true(ListPlan.SameIds({}, {}))
    end)

    it("notices an added, removed, or reordered id", function()
        assert.is_false(ListPlan.SameIds({ 1 }, { 1, 2 }))
        assert.is_false(ListPlan.SameIds({ 1, 2 }, { 1 }))
        assert.is_false(ListPlan.SameIds({ 1, 2 }, { 2, 1 }))
        assert.is_false(ListPlan.SameIds(nil, { 1 }))
    end)

    it("keeps the scroll offset when the list change is at the viewport", function()
        assert.equals(40, ListPlan.AdjustScroll(40, 40, 100, 140, 500))
        assert.equals(0, ListPlan.AdjustScroll(0, 20, 36, 0, 500))
    end)

    it("moves the scroll offset when the list change is entirely above the viewport", function()
        assert.equals(240, ListPlan.AdjustScroll(200, 40, 100, 140, 500))
        assert.equals(160, ListPlan.AdjustScroll(200, 40, 100, 60, 500))
    end)

    it("clamps the adjusted scroll offset to the new range", function()
        assert.equals(0, ListPlan.AdjustScroll(20, 0, 20, 0, 200))
        assert.equals(50, ListPlan.AdjustScroll(200, 0, 100, 180, 50))
    end)
end)
