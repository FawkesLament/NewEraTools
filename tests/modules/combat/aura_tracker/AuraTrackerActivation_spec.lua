local Harness = require("helpers.aura_tracker")

describe("ShouldTrack", function()
    local AuraTracker

    before_each(function()
        AuraTracker = select(2, Harness.Start())
    end)

    it("requires module enable, tracker enable, a positive spell ID, and an active scope", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        assert.is_false(AuraTracker:ShouldTrack(id))
        AuraTracker:SetSpellId(id, 12345)
        assert.is_true(AuraTracker:ShouldTrack(id))
        AuraTracker:SetTrackerEnabled(id, false)
        assert.is_false(AuraTracker:ShouldTrack(id))
        AuraTracker:SetTrackerEnabled(id, true)
        AuraTracker:SetEnabled(false)
        assert.is_false(AuraTracker:ShouldTrack(id))
        assert.is_true(AuraTracker:IsTrackerEnabled(id))
    end)
end)

describe("activation scope", function()
    local ns, AuraTracker, Activation
    local Player

    before_each(function()
        ns, AuraTracker, Activation = Harness.Start()
        Player = ns.Api.Player
    end)

    it("returns the first enabled tracker whose activation matches the current player", function()
        local otherSpec = AuraTracker:AddTracker()
        AuraTracker:SetActivationScope(otherSpec, Activation.SPECIALIZATION, 102)
        local disabled = AuraTracker:AddTracker()
        AuraTracker:SetTrackerEnabled(disabled, false)
        local match = AuraTracker:AddTracker()
        local later = AuraTracker:AddTracker()
        assert.equals(match, AuraTracker:GetFirstTrackerEnabledForCurrentPlayer())

        AuraTracker:SetTrackerEnabled(match, false)
        AuraTracker:SetTrackerEnabled(later, false)
        assert.is_nil(AuraTracker:GetFirstTrackerEnabledForCurrentPlayer())
    end)

    it("defaults new trackers to the current specialization ID", function()
        local id = AuraTracker:AddTracker()
        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.SPECIALIZATION, scope)
        assert.equals(105, target)

        Player.SetContextForTests({ specializationId = 64 })
        local other = AuraTracker:AddTracker()
        scope, target = AuraTracker:GetActivationScope(other)
        assert.equals(Activation.SPECIALIZATION, scope)
        assert.equals(64, target)
        assert.equals(64, AuraTracker.db.trackers[2].activationTarget)
        assert.equals(105, select(2, AuraTracker:GetActivationScope(id)))
        assert.equals(105, AuraTracker.db.trackers[1].activationTarget)
    end)

    it("AppliesToPlayer matches always, specialization, class, and role", function()
        local context = { classFile = "DRUID", specializationId = 105, role = "HEALER" }
        assert.is_true(Activation.AppliesToPlayer({
            activationScope = Activation.ALWAYS,
        }, context))
        assert.is_true(Activation.AppliesToPlayer({
            activationScope = Activation.SPECIALIZATION,
            activationTarget = 105,
        }, context))
        assert.is_false(Activation.AppliesToPlayer({
            activationScope = Activation.SPECIALIZATION,
            activationTarget = 102,
        }, context))
        assert.is_true(Activation.AppliesToPlayer({
            activationScope = Activation.CLASS,
            activationTarget = "DRUID",
        }, context))
        assert.is_false(Activation.AppliesToPlayer({
            activationScope = Activation.CLASS,
            activationTarget = "MAGE",
        }, context))
        assert.is_true(Activation.AppliesToPlayer({
            activationScope = Activation.ROLE,
            activationTarget = "HEALER",
        }, context))
        assert.is_false(Activation.AppliesToPlayer({
            activationScope = Activation.ROLE,
            activationTarget = "TANK",
        }, context))
    end)

    it("keeps inactive auras in the saved list when the scope does not match", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 102)
        assert.is_false(AuraTracker:ShouldTrack(id))
        assert.same({ id }, AuraTracker:GetTrackerIds())
        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.SPECIALIZATION, scope)
        assert.equals(102, target)
    end)

    it("does not rewrite saved scopes when the specialization changes", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 105)
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)

        local notifications = 0
        function AuraTracker:OnTrackerChanged(trackerId)
            assert.is_nil(trackerId)
            notifications = notifications + 1
        end
        AuraTracker:ListenForPlayerContext()

        Player.SetContextForTests({
            specializationId = 104,
            role = "TANK",
        })
        Player.FireChanged()

        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.SPECIALIZATION, scope)
        assert.equals(105, target)
        assert.is_false(AuraTracker:ShouldTrack(id))
        assert.equals(1, notifications)
    end)

    it("refreshes when entering the world so late specialization context activates trackers", function()
        local Instance = ns.Api.Instance
        local Timer = ns.Api.Timer
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 64)

        Player.ClearContextForTests({ "specializationId" })
        assert.is_nil(Player.GetSpecializationId())
        assert.is_false(AuraTracker:ShouldTrack(id))
        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.SPECIALIZATION, scope)
        assert.equals(64, target)

        local notifications = 0
        function AuraTracker:OnTrackerChanged(trackerId)
            assert.is_nil(trackerId)
            notifications = notifications + 1
        end
        AuraTracker:ListenForPlayerContext()

        Player.SetContextForTests({
            specializationId = 64,
            role = "DAMAGER",
        })
        Instance.FireEnteringWorld()
        assert.equals(1, notifications)
        assert.is_true(AuraTracker:ShouldTrack(id))
        assert.equals(1, #Timer.pending)
        assert.equals(0, Timer.pending[1].due)

        Timer.RunPending()
        assert.equals(2, notifications)
    end)

    it("reactivates when switching back to a matching specialization", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 102)

        Player.SetContextForTests({ specializationId = 102, role = "DAMAGER" })
        assert.is_true(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({ specializationId = 105, role = "HEALER" })
        assert.is_false(AuraTracker:ShouldTrack(id))
    end)

    it("filters by class when switching characters", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.CLASS, "DRUID")
        assert.is_true(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({
            classFile = "MAGE",
            specializationId = 64,
            role = "DAMAGER",
            specializations = {
                { id = 62, name = "Arcane", role = "DAMAGER" },
                { id = 63, name = "Fire", role = "DAMAGER" },
                { id = 64, name = "Frost", role = "DAMAGER" },
            },
        })
        assert.is_false(AuraTracker:ShouldTrack(id))
        assert.equals("DRUID", select(2, AuraTracker:GetActivationScope(id)))
    end)

    it("filters by role independently of specialization ID", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.ROLE, "HEALER")
        assert.is_true(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({ role = "TANK" })
        assert.equals(105, Player.GetSpecializationId())
        assert.is_false(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({ specializationId = 104 })
        assert.equals("TANK", Player.GetRole())
        assert.is_false(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({ role = "HEALER" })
        assert.equals(104, Player.GetSpecializationId())
        assert.is_true(AuraTracker:ShouldTrack(id))
        local scope, target = AuraTracker:GetActivationScope(id)
        assert.equals(Activation.ROLE, scope)
        assert.equals("HEALER", target)
    end)

    it("always-scoped auras stay active across specialization and class changes", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 774)
        AuraTracker:SetActivationScope(id, Activation.ALWAYS, nil)
        assert.is_true(AuraTracker:ShouldTrack(id))

        Player.SetContextForTests({
            classFile = "WARRIOR",
            specializationId = 71,
            role = "DAMAGER",
        })
        assert.is_true(AuraTracker:ShouldTrack(id))
        assert.equals(Activation.ALWAYS, AuraTracker:GetActivationScope(id))
        assert.is_nil(select(2, AuraTracker:GetActivationScope(id)))
    end)

    it("rejects invalid scope targets and unchanged sets do not notify", function()
        local id = AuraTracker:AddTracker()
        local calls = 0
        function AuraTracker:OnTrackerChanged()
            calls = calls + 1
        end
        local tracker = AuraTracker.db.trackers[1]
        assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, "nope", nil))
        assert.equals(Activation.SPECIALIZATION, tracker.activationScope)
        assert.equals(105, tracker.activationTarget)
        assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, Activation.SPECIALIZATION, 0))
        assert.equals(Activation.SPECIALIZATION, tracker.activationScope)
        assert.equals(105, tracker.activationTarget)
        assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, Activation.ROLE, "NONE"))
        assert.equals(Activation.SPECIALIZATION, tracker.activationScope)
        assert.equals(105, tracker.activationTarget)
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 105)
        assert.equals(0, calls)
        AuraTracker:SetActivationScope(id, Activation.CLASS, "DRUID")
        assert.equals(1, calls)
    end)

    it("exposes activation options for the current character", function()
        local options = AuraTracker.GetActivationOptions()
        assert.equals("DRUID", options.classFile)
        assert.equals(4, #options.specializations)
        assert.equals(102, options.specializations[1].id)
        assert.same({ "TANK", "HEALER", "DAMAGER" }, options.roles)
    end)

    it("formats activation scope labels for the list UI", function()
        local id = AuraTracker:AddTracker()
        assert.equals("Restoration", AuraTracker:GetActivationScopeLabel(id))
        AuraTracker:SetActivationScope(id, Activation.ALWAYS, nil)
        assert.equals(ns.L.AURA_TRACKER_SCOPE_ALWAYS, AuraTracker:GetActivationScopeLabel(id))
        AuraTracker:SetActivationScope(id, Activation.CLASS, "MAGE")
        assert.equals("Mage", AuraTracker:GetActivationScopeLabel(id))
        AuraTracker:SetActivationScope(id, Activation.ROLE, "HEALER")
        assert.equals(ns.L.AURA_TRACKER_ROLE_HEALER, AuraTracker:GetActivationScopeLabel(id))
        AuraTracker:SetActivationScope(id, Activation.SPECIALIZATION, 64)
        assert.equals("Frost", AuraTracker:GetActivationScopeLabel(id))
    end)
end)
