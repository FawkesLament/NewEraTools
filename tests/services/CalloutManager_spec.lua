local Loader = require("helpers.loader")

describe("CalloutManager", function()
    local ns, CalloutManager, Timer

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        CalloutManager = ns.CalloutManager
        Timer = ns.Api.Timer
    end)

    local function Show(overrides)
        local options = {
            source = "alpha",
            text = "First",
            duration = 5,
        }
        for key, value in pairs(overrides or {}) do
            options[key] = value
        end
        return CalloutManager.Show(options)
    end

    it("hides a message when its duration elapses", function()
        Show({ duration = 3 })
        assert.equals("First", CalloutManager.GetDisplayed())
        assert.equals(Timer.GetTime() + 3, CalloutManager.GetExpiresAt())
        Timer.Advance(2.99)
        assert.equals("First", CalloutManager.GetDisplayed())
        Timer.Advance(0.01)
        assert.is_nil(CalloutManager.GetDisplayed())
        assert.is_nil(CalloutManager.GetExpiresAt())
    end)

    it("replaces an older message with a newer one", function()
        Show({ text = "First", duration = 5 })
        Show({ text = "Second", duration = 5 })
        assert.equals("Second", CalloutManager.GetDisplayed())
        assert.equals("alpha", CalloutManager.GetCurrent().source)
    end)

    it("ignores an old expire timer after a newer message replaced it", function()
        Show({ text = "First", duration = 5 })
        Timer.Advance(3)
        Show({ text = "Second", duration = 5 })
        Timer.Advance(2)
        assert.equals("Second", CalloutManager.GetDisplayed())
        Timer.Advance(3)
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("ignores dismissing an older handle after replacement", function()
        local first = Show({ text = "First", duration = 8 })
        local second = Show({ text = "Second", duration = 8 })
        first:Dismiss()
        assert.equals("Second", CalloutManager.GetDisplayed())
        second:Dismiss()
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("dismisses the current message early", function()
        local handle = Show({ duration = 10 })
        handle:Dismiss()
        assert.is_nil(CalloutManager.GetDisplayed())
        Timer.Advance(10)
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("gives consecutive messages distinct handles even when the text matches", function()
        local first = Show({ text = "Same", duration = 5 })
        local second = Show({ text = "Same", duration = 5 })
        assert.is_true(first ~= second)
        first:Dismiss()
        assert.equals("Same", CalloutManager.GetDisplayed())
        second:Dismiss()
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("clears only the current source and leaves another source's message", function()
        Show({ source = "alpha", text = "A", duration = 5 })
        Show({ source = "beta", text = "B", duration = 5 })
        CalloutManager.ClearSource("alpha")
        assert.equals("B", CalloutManager.GetDisplayed())
        CalloutManager.ClearSource("beta")
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("does not show an already-expired message and drops whatever was visible", function()
        Show({ text = "First", duration = 5 })
        Show({ text = "Late", expiresAt = Timer.GetTime() })
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("notifies listeners on show, replace, dismiss, and expire", function()
        local changes = 0
        local stop = CalloutManager.OnChanged(function()
            changes = changes + 1
        end)
        local handle = Show({ duration = 2 })
        assert.equals(1, changes)
        Show({ text = "Second", duration = 2 })
        assert.equals(2, changes)
        handle:Dismiss()
        assert.equals(2, changes)
        local current = Show({ text = "Third", duration = 2 })
        assert.equals(3, changes)
        current:Dismiss()
        assert.equals(4, changes)
        Show({ text = "Fourth", duration = 1 })
        assert.equals(5, changes)
        Timer.Advance(1)
        assert.equals(6, changes)
        stop()
        Show({ text = "Quiet", duration = 1 })
        assert.equals(6, changes)
    end)

    it("stores wrap and appendTimer on the current message", function()
        Show({
            text = "X",
            duration = 4,
            appendTimer = true,
            wrap = "Go %s drop",
        })
        local current = CalloutManager.GetCurrent()
        assert.equals("X", current.text)
        assert.is_true(current.appendTimer)
        assert.equals("Go %s drop", current.wrap)
        assert.is_true(CalloutManager.GetAppendTimer())
    end)
end)
