local Loader = require("helpers.loader")

describe("ResourceScope", function()
    local ns
    local ResourceScope
    local Timer
    local printed

    before_each(function()
        ns = Loader.Load()
        ResourceScope = ns.ResourceScope
        Timer = ns.Api.Timer
        printed = {}
        ns.Util.Print = function(message)
            printed[#printed + 1] = message
        end
    end)

    it("runs cleanups in reverse registration order", function()
        local order = {}
        local scope = ResourceScope.New()
        scope:Add(function()
            order[#order + 1] = "a"
        end)
        scope:Add(function()
            order[#order + 1] = "b"
        end)
        scope:Add(function()
            order[#order + 1] = "c"
        end)
        scope:Dispose()
        assert.same({ "c", "b", "a" }, order)
    end)

    it("does not run cleanups again after Dispose", function()
        local runs = 0
        local scope = ResourceScope.New()
        scope:Add(function()
            runs = runs + 1
        end)
        scope:Dispose()
        scope:Dispose()
        assert.equals(1, runs)
    end)

    it("continues remaining cleanups when one fails", function()
        local order = {}
        local scope = ResourceScope.New()
        scope:Add(function()
            order[#order + 1] = "a"
        end)
        scope:Add(function()
            error("cleanup failed")
        end)
        scope:Add(function()
            order[#order + 1] = "c"
        end)
        scope:Dispose()
        assert.same({ "c", "a" }, order)
        assert.equals(1, #printed)
        assert(printed[1]:find("ResourceScope cleanup error:", 1, true), printed[1])
        assert(printed[1]:find("cleanup failed", 1, true), printed[1])
    end)

    it("runs an added cleanup immediately after disposal instead of leaking it", function()
        local ran = false
        local scope = ResourceScope.New()
        scope:Dispose()
        scope:Add(function()
            ran = true
        end)
        assert.is_true(ran)
        scope:Dispose()
        assert.is_true(ran)
    end)

    it("unsubscribes through Subscribe", function()
        local unsubscribed = 0
        local received = 0
        local listener
        local function subscribe(callback)
            listener = callback
            return function()
                unsubscribed = unsubscribed + 1
                listener = nil
            end
        end

        local scope = ResourceScope.New()
        scope:Subscribe(subscribe, function()
            received = received + 1
        end)
        listener()
        scope:Dispose()
        assert.equals(1, received)
        assert.equals(1, unsubscribed)
        assert.is_nil(listener)
        scope:Dispose()
        assert.equals(1, unsubscribed)
    end)

    it("cancels a ticker on Dispose", function()
        local fires = 0
        local scope = ResourceScope.New()
        scope:Ticker(1, function()
            fires = fires + 1
        end)
        Timer.Advance(1)
        assert.equals(1, fires)
        scope:Dispose()
        Timer.Advance(5)
        assert.equals(1, fires)
    end)

    it("does not fire a one-shot timer after Dispose", function()
        local fires = 0
        local scope = ResourceScope.New()
        scope:After(5, function()
            fires = fires + 1
        end)
        scope:Dispose()
        Timer.Advance(5)
        assert.equals(0, fires)
    end)

    it("fires a one-shot timer before disposal", function()
        local fires = 0
        local scope = ResourceScope.New()
        scope:After(5, function()
            fires = fires + 1
        end)
        Timer.Advance(4.99)
        assert.equals(0, fires)
        Timer.Advance(0.01)
        assert.equals(1, fires)
        scope:Dispose()
    end)

    it("does not create a ticker after disposal", function()
        local fires = 0
        local created = 0
        local original = Timer.NewTicker
        Timer.NewTicker = function(...)
            created = created + 1
            return original(...)
        end
        local scope = ResourceScope.New()
        scope:Dispose()
        scope:Ticker(1, function()
            fires = fires + 1
        end)
        Timer.NewTicker = original
        assert.equals(0, created)
        Timer.Advance(5)
        assert.equals(0, fires)
    end)

    it("does not create a one-shot timer after disposal", function()
        local fires = 0
        local created = 0
        local original = Timer.NewTimer
        Timer.NewTimer = function(...)
            created = created + 1
            return original(...)
        end
        local scope = ResourceScope.New()
        scope:Dispose()
        scope:After(5, function()
            fires = fires + 1
        end)
        Timer.NewTimer = original
        assert.equals(0, created)
        Timer.Advance(5)
        assert.equals(0, fires)
    end)

    it("does not invoke Subscribe after disposal", function()
        local subscribed = 0
        local unsubscribed = 0
        local scope = ResourceScope.New()
        scope:Dispose()
        scope:Subscribe(function()
            subscribed = subscribed + 1
            return function()
                unsubscribed = unsubscribed + 1
            end
        end, function() end)
        assert.equals(0, subscribed)
        assert.equals(0, unsubscribed)
    end)

    it("does not leave a ticker when creation fails", function()
        local original = Timer.NewTicker
        Timer.NewTicker = function()
            error("create failed")
        end
        local scope = ResourceScope.New()
        local ok = pcall(function()
            scope:Ticker(1, function() end)
        end)
        Timer.NewTicker = original
        assert.is_false(ok)
        scope:Dispose()
        Timer.Advance(5)
    end)
end)
