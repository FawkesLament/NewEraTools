local Loader = require("helpers.loader")

describe("Util", function()
    local Util

    before_each(function()
        Util = Loader.Load().Util
    end)

    describe("ApplyDefaults", function()
        it("fills missing keys, including nested tables", function()
            local target = {}
            Util.ApplyDefaults(target, { count = 1, nested = { flag = true } })
            assert.same({ count = 1, nested = { flag = true } }, target)
        end)

        it("keeps existing values", function()
            local target = { count = 5, nested = { flag = false } }
            Util.ApplyDefaults(target, { count = 1, nested = { flag = true, extra = 2 } })
            assert.same({ count = 5, nested = { flag = false, extra = 2 } }, target)
        end)

        it("does not share default tables with the target", function()
            local defaults = { list = {} }
            local target = {}
            Util.ApplyDefaults(target, defaults)
            target.list.item = true
            assert.is_nil(defaults.list.item)
        end)
    end)

    it("Clamp limits a value to a range", function()
        assert.equals(1, Util.Clamp(-3, 1, 40))
        assert.equals(40, Util.Clamp(99, 1, 40))
        assert.equals(7, Util.Clamp(7, 1, 40))
    end)

    it("Snap rounds to step then clamps", function()
        assert.equals(1.0, Util.Snap(0.98, 0.8, 1.5, 0.05))
        assert.equals(0.8, Util.Snap(0.5, 0.8, 1.5, 0.05))
        assert.equals(1.5, Util.Snap(2.0, 0.8, 1.5, 0.05))
        assert.equals(12, Util.Snap(12.4, 8, 32, 1))
    end)

    it("Wipe empties a table in place", function()
        local t = { a = 1, b = 2 }
        Util.Wipe(t)
        assert.same({}, t)
    end)

    describe("DeepCopy", function()
        it("returns non-tables unchanged", function()
            assert.equals(3, Util.DeepCopy(3))
            assert.equals("x", Util.DeepCopy("x"))
            assert.is_nil(Util.DeepCopy(nil))
        end)

        it("copies nested tables independently", function()
            local source = { count = 1, nested = { flag = true, color = { r = 1, g = 0, b = 0 } } }
            local copy = Util.DeepCopy(source)
            assert.same(source, copy)
            assert.is_true(copy ~= source)
            assert.is_true(copy.nested ~= source.nested)
            assert.is_true(copy.nested.color ~= source.nested.color)
            copy.nested.color.r = 0
            assert.equals(1, source.nested.color.r)
        end)
    end)
end)
