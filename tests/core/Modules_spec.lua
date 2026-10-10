local Loader = require("helpers.loader")

describe("Modules", function()
    local ns

    before_each(function()
        ns = Loader.Load()
    end)

    it("rejects duplicate names", function()
        ns.Modules.New("Test")
        assert.is_false(pcall(ns.Modules.New, "Test"))
    end)

    it("assigns settings, then runs every OnInit before any OnEnable", function()
        local calls = {}
        local first = ns.Modules.New("First", { defaults = { value = 1 } })
        local second = ns.Modules.New("Second")
        function first:OnInit()
            table.insert(calls, "first:init " .. self.db.value)
        end
        function first:OnEnable()
            table.insert(calls, "first:enable")
        end
        function second:OnInit()
            table.insert(calls, "second:init")
        end
        function second:OnEnable()
            table.insert(calls, "second:enable")
        end

        ns.Modules.Start(ns.Database.Load(nil))

        assert.same({ "first:init 1", "second:init", "first:enable", "second:enable" }, calls)
    end)
end)
