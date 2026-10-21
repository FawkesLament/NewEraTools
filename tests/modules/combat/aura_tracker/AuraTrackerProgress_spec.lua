local Harness = require("helpers.aura_tracker")

describe("progress mode", function()
    local AuraTracker, Schema

    before_each(function()
        local _
        _, AuraTracker, _, Schema = Harness.Start()
    end)

    it("defaults to duration with max stacks 10", function()
        local id = AuraTracker:AddTracker()
        assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(id))
        assert.is_false(AuraTracker:IsStacksMode(id))
        assert.equals(10, AuraTracker:GetMaxStacks(id))
    end)

    it("stores mode and max stacks independently per tracker", function()
        local a = AuraTracker:AddTracker()
        local b = AuraTracker:AddTracker()
        AuraTracker:SetProgressMode(a, Schema.PROGRESS_MODE_STACKS)
        AuraTracker:SetMaxStacks(a, 20)
        AuraTracker:SetMaxStacks(b, 5)
        assert.equals(Schema.PROGRESS_MODE_STACKS, AuraTracker:GetProgressMode(a))
        assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(b))
        assert.equals(20, AuraTracker:GetMaxStacks(a))
        assert.equals(5, AuraTracker:GetMaxStacks(b))
    end)

    it("notifies OnAppearanceChanged when mode or max stacks change", function()
        local id = AuraTracker:AddTracker()
        local appearanceCalls = 0
        local trackerCalls = 0
        function AuraTracker:OnAppearanceChanged(trackerId)
            assert.equals(id, trackerId)
            appearanceCalls = appearanceCalls + 1
        end
        function AuraTracker:OnTrackerChanged()
            trackerCalls = trackerCalls + 1
        end
        AuraTracker:SetProgressMode(id, Schema.PROGRESS_MODE_STACKS)
        AuraTracker:SetProgressMode(id, Schema.PROGRESS_MODE_STACKS)
        AuraTracker:SetMaxStacks(id, 15)
        AuraTracker:SetMaxStacks(id, 15)
        assert.equals(2, appearanceCalls)
        assert.equals(0, trackerCalls)
    end)

    it("rejects unknown modes and clamps max stacks", function()
        local id = AuraTracker:AddTracker()
        local tracker = AuraTracker.db.trackers[1]
        assert.is_false(pcall(AuraTracker.SetProgressMode, AuraTracker, id, "cooldown"))
        assert.equals(Schema.PROGRESS_MODE_DURATION, tracker.progressMode)
        assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(id))
        AuraTracker:SetMaxStacks(id, 0)
        assert.equals(Schema.MAX_STACKS_MIN, tracker.maxStacks)
        assert.equals(Schema.MAX_STACKS_MIN, AuraTracker:GetMaxStacks(id))
        AuraTracker:SetMaxStacks(id, 5000)
        assert.equals(Schema.MAX_STACKS_MAX, tracker.maxStacks)
        assert.equals(Schema.MAX_STACKS_MAX, AuraTracker:GetMaxStacks(id))
    end)

    it("keeps text displays independent of each other and of progress mode", function()
        local id = AuraTracker:AddTracker()
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
        assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        AuraTracker:SetProgressMode(id, Schema.PROGRESS_MODE_STACKS)
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_DURATION, true)
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_STACKS, true)
        AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 14)
        AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_STACKS, 20)
        AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, 12)
        AuraTracker:SetTextDisplayOffsetY(id, Schema.TEXT_STACKS, -24)
        assert.equals(Schema.PROGRESS_MODE_STACKS, AuraTracker:GetProgressMode(id))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        assert.equals(14, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
        assert.equals(20, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_STACKS))
        assert.equals(12, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_DURATION))
        assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
        assert.equals(-24, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_DURATION, false)
        assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        assert.equals(20, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_STACKS))
        assert.equals(Schema.PROGRESS_MODE_STACKS, AuraTracker:GetProgressMode(id))
    end)

    it("UpdateTracker applies progress mode and text display settings", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_DURATION, false)
        AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 16)
        AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, 9)
        AuraTracker:UpdateTracker(id, {
            progressMode = Schema.PROGRESS_MODE_STACKS,
            maxStacks = 8,
            textDisplays = {
                stacks = {
                    enabled = true,
                    offsetX = 15,
                    offsetY = -6,
                },
            },
        })
        local duration = AuraTracker.db.trackers[1].textDisplays[Schema.TEXT_DURATION]
        assert.is_true(AuraTracker:IsStacksMode(id))
        assert.equals(8, AuraTracker:GetMaxStacks(id))
        assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
        assert.equals(15, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
        assert.equals(-6, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
        assert.is_false(duration.enabled)
        assert.equals(16, duration.fontSize)
        assert.equals(9, duration.offsetX)
        assert.equals(0, duration.offsetY)
        assert.equals(9, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
    end)
end)
