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

    it("Wipe empties a table in place", function()
        local t = { a = 1, b = 2 }
        Util.Wipe(t)
        assert.same({}, t)
    end)
end)
