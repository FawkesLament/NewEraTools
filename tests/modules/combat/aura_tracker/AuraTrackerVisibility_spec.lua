local Harness = require("helpers.aura_tracker")

describe("global visibility", function()
    local ns, AuraTracker, Activation
    local Activity

    before_each(function()
        ns, AuraTracker, Activation = Harness.Start()
        Activity = ns.Api.Activity
        Activity.SetStateForTests({
            skyriding = false,
            inPetBattle = false,
            inCinematic = false,
        })
    end)

    it("defaults all auto-hide options to enabled", function()
        assert.is_true(AuraTracker:GetHideDuringSkyriding())
        assert.is_true(AuraTracker:GetHideDuringPetBattles())
        assert.is_true(AuraTracker:GetHideDuringCinematics())
        assert.is_false(AuraTracker:ShouldHideAuraBars())
    end)

    it("hides for each activity only when that option is enabled", function()
        Activity.SetStateForTests({ skyriding = true })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        AuraTracker:SetHideDuringSkyriding(false)
        assert.is_false(AuraTracker:ShouldHideAuraBars())

        Activity.SetStateForTests({ skyriding = false, inPetBattle = true })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        AuraTracker:SetHideDuringPetBattles(false)
        assert.is_false(AuraTracker:ShouldHideAuraBars())

        Activity.SetStateForTests({ inPetBattle = false, inCinematic = true })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        AuraTracker:SetHideDuringCinematics(false)
        assert.is_false(AuraTracker:ShouldHideAuraBars())
    end)

    it("stays hidden while any overlapping hide condition remains active", function()
        Activity.SetStateForTests({
            skyriding = true,
            inPetBattle = true,
            inCinematic = true,
        })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        AuraTracker:SetHideDuringSkyriding(false)
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        Activity.SetStateForTests({ inPetBattle = false })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        Activity.SetStateForTests({ inCinematic = false })
        assert.is_false(AuraTracker:ShouldHideAuraBars())
    end)

    it("does not change ShouldTrack, enablement, or activation scope", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.ROLE, "HEALER")
        assert.is_true(AuraTracker:ShouldTrack(id))

        Activity.SetStateForTests({ skyriding = true, inPetBattle = true })
        assert.is_true(AuraTracker:ShouldHideAuraBars())
        assert.is_true(AuraTracker:ShouldTrack(id))
        assert.is_true(AuraTracker:IsEnabled())
        assert.is_true(AuraTracker:IsTrackerEnabled(id))
        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.ROLE, scope)
        assert.equals("HEALER", target)
    end)

    it("notifies trackers when a visibility option changes", function()
        local seen = {}
        function AuraTracker:OnTrackerChanged(trackerId)
            table.insert(seen, trackerId)
        end
        AuraTracker:SetHideDuringSkyriding(false)
        AuraTracker:SetHideDuringSkyriding(false)
        AuraTracker:SetHideDuringPetBattles(false)
        assert.same({ nil, nil }, seen)
    end)

    it("refreshes when activity context changes", function()
        local notifications = 0
        function AuraTracker:OnTrackerChanged(trackerId)
            assert.is_nil(trackerId)
            notifications = notifications + 1
        end
        AuraTracker:ListenForVisibilityContext()
        Activity.FireContextChanged()
        assert.equals(1, notifications)
    end)
end)
