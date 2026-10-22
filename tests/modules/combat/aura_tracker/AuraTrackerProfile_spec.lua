local Loader = require("helpers.loader")

describe("AuraTracker profile report", function()
    local ns, profile
    local clock
    local previousClock

    before_each(function()
        previousClock = debugprofilestop
        clock = { now = 0 }
        debugprofilestop = function()
            return clock.now
        end
        ns = Loader.Load()
        profile = ns.Modules.Internals("AuraTracker").Profile
    end)

    after_each(function()
        debugprofilestop = previousClock
    end)

    local function Row(name, count, total, max)
        return string.format(ns.L.AURA_TRACKER_PROFILE_ROW, name, count, total, max)
    end

    it("returns the empty message before any samples", function()
        assert.is_false(profile.IsRecording())
        assert.equals(ns.L.AURA_TRACKER_PROFILE_EMPTY, profile.Report())
    end)

    it("ignores samples until recording starts", function()
        profile.Inc("event.PLAYER_TARGET_CHANGED")
        profile.Stop("bar.display", profile.Start())
        assert.equals(ns.L.AURA_TRACKER_PROFILE_EMPTY, profile.Report())
        profile.Record()
        profile.Inc("bar.display")
        assert.is_true(profile.Report():find("bar.display", 1, true) ~= nil)
    end)

    it("reports the latest mark without treating it as a duration", function()
        profile.Record()
        profile.Mark("ui.scrollDeltaPx", -36)
        profile.Mark("ui.scrollDeltaPx", -12)
        local text = profile.Report()
        assert.is_true(text:find("ui.scrollDeltaPx", 1, true) ~= nil)
        assert.is_true(text:find("-12", 1, true) ~= nil)
        assert.is_nil(text:find("-36", 1, true))
        profile.Reset()
        assert.equals(ns.L.AURA_TRACKER_PROFILE_EMPTY, profile.Report())
        assert.is_true(profile.IsRecording())
        profile.Inc("bar.display")
        assert.is_true(profile.Report():find(Row("bar.display", 1, 0, 0), 1, true) ~= nil)
    end)

    it("lists each counter once, sorted", function()
        profile.Record()
        local eventKey = profile.EventKey("PLAYER_TARGET_CHANGED")
        assert.equals("event.PLAYER_TARGET_CHANGED", eventKey)
        assert.equals("event.UNIT_FACTION.target", profile.EventKey("UNIT_FACTION", "target"))
        assert.equals("event.other", profile.EventKey("UNIT_FLAGS", "party1"))
        profile.Inc(eventKey)
        profile.Inc(eventKey)
        clock.now = 10
        local started = profile.Start()
        clock.now = 25.5
        profile.Stop("bar.display", started)
        local text = profile.Report()
        local displayAt = text:find("bar.display", 1, true)
        local eventAt = text:find(eventKey, 1, true)
        assert.is_true(displayAt ~= nil and eventAt ~= nil and displayAt < eventAt)
        local _, displayCount = text:gsub("bar%.display", "")
        assert.equals(1, displayCount)
        assert.is_true(text:find(Row(eventKey, 2, 0, 0), 1, true) ~= nil)
        assert.is_true(text:find(Row("bar.display", 1, 15.5, 15.5), 1, true) ~= nil)
    end)
end)
