local Harness = require("helpers.aura_tracker")

describe("spellId", function()
    local AuraTracker

    before_each(function()
        AuraTracker = select(2, Harness.Start())
    end)

    it("stores a positive integer on one tracker", function()
        local first = AuraTracker:AddTracker()
        local second = AuraTracker:AddTracker()
        AuraTracker:SetSpellId(first, 774)
        AuraTracker:SetSpellId(second, 8936)
        assert.equals(774, AuraTracker.db.trackers[1].spellId)
        assert.equals(8936, AuraTracker.db.trackers[2].spellId)
        assert.equals(774, AuraTracker:GetSpellId(first))
        assert.equals(8936, AuraTracker:GetSpellId(second))
    end)

    it("allows clearing to zero", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetSpellId(id, 0)
        assert.equals(0, AuraTracker:GetSpellId(id))
    end)

    it("does not notify when unchanged", function()
        local id = AuraTracker:AddTracker()
        local calls = 0
        function AuraTracker:OnTrackerChanged()
            calls = calls + 1
        end
        AuraTracker:SetSpellId(id, 0)
        assert.equals(0, calls)
        AuraTracker:SetSpellId(id, 100)
        AuraTracker:SetSpellId(id, 100)
        assert.equals(1, calls)
    end)

    it("rejects non-integers and negatives", function()
        local id = AuraTracker:AddTracker()
        local other = AuraTracker:AddTracker()
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetSpellId(other, 8936)
        local tracker = AuraTracker.db.trackers[1]
        assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, 1.5))
        assert.equals(774, tracker.spellId)
        assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, -1))
        assert.equals(774, tracker.spellId)
        assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, "12"))
        assert.equals(774, tracker.spellId)
        assert.equals(8936, AuraTracker.db.trackers[2].spellId)
        assert.equals(774, AuraTracker:GetSpellId(id))
    end)
end)

describe("display name", function()
    local ns, AuraTracker

    before_each(function()
        ns, AuraTracker = Harness.Start()
    end)

    it("falls back to Untitled, then spell ID, then resolved name", function()
        local id = AuraTracker:AddTracker()
        assert.equals(ns.L.AURA_TRACKER_UNTITLED, AuraTracker:GetDisplayName(id))
        AuraTracker:SetSpellId(id, 774)
        assert.equals("774", AuraTracker:GetDisplayName(id))
        ns.Api.Spell.SetNameForTests(774, "Rejuvenation")
        assert.equals("Rejuvenation", AuraTracker:GetDisplayName(id))
    end)
end)

describe("remaining time format", function()
    local AuraTracker

    before_each(function()
        AuraTracker = select(2, Harness.Start())
    end)

    it("uses one decimal below 10 seconds", function()
        assert.equals("0.0", AuraTracker:FormatRemainingTime(0))
        assert.equals("4.3", AuraTracker:FormatRemainingTime(4.39))
        assert.equals("9.9", AuraTracker:FormatRemainingTime(9.99))
    end)

    it("uses whole seconds from 10 up to under a minute", function()
        assert.equals("10", AuraTracker:FormatRemainingTime(10))
        assert.equals("10", AuraTracker:FormatRemainingTime(10.9))
        assert.equals("59", AuraTracker:FormatRemainingTime(59.9))
    end)

    it("uses m:ss from one minute upward", function()
        assert.equals("1:00", AuraTracker:FormatRemainingTime(60))
        assert.equals("1:23", AuraTracker:FormatRemainingTime(83))
        assert.equals("2:05", AuraTracker:FormatRemainingTime(125.9))
    end)

    it("treats a negative, non-number, or NaN as zero", function()
        assert.equals("0.0", AuraTracker:FormatRemainingTime(-0.1))
        assert.equals("0.0", AuraTracker:FormatRemainingTime("4"))
        assert.equals("0.0", AuraTracker:FormatRemainingTime(0 / 0))
    end)
end)
