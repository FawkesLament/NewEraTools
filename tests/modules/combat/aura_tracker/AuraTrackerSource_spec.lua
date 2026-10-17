local Harness = require("helpers.aura_tracker")

describe("aura source", function()
    local ns, AuraTracker, Activation, Schema

    before_each(function()
        ns, AuraTracker, Activation, Schema = Harness.Start()
    end)

    local function Enable(id)
        AuraTracker:SetEnabled(true)
        AuraTracker:SetSpellId(id, 980)
        AuraTracker:SetActivationScope(id, Activation.ALWAYS, nil)
    end

    local function Saved(id)
        for _, tracker in ipairs(AuraTracker.db.trackers) do
            if tracker.id == id then
                return tracker
            end
        end
    end

    it("defaults each bar to a player buff and stores unit and aura type independently", function()
        local id = AuraTracker:AddTracker()
        assert.equals(Schema.UNIT_PLAYER, AuraTracker:GetUnit(id))
        assert.equals(Schema.AURA_HELPFUL, AuraTracker:GetAuraType(id))
        assert.is_true(AuraTracker:IsSourceSupported(id))

        AuraTracker:SetUnit(id, Schema.UNIT_TARGET)
        assert.equals(Schema.AURA_HELPFUL, AuraTracker:GetAuraType(id))
        assert.is_false(AuraTracker:IsSourceSupported(id))

        AuraTracker:SetAuraType(id, Schema.AURA_HARMFUL)
        assert.is_true(AuraTracker:IsSourceSupported(id))
        AuraTracker:SetUnit(id, Schema.UNIT_FOCUS)
        assert.equals(Schema.UNIT_FOCUS, AuraTracker:GetUnit(id))
        assert.equals(Schema.AURA_HARMFUL, AuraTracker:GetAuraType(id))
    end)

    it("rejects unknown units and aura types", function()
        local id = AuraTracker:AddTracker()
        local tracker = Saved(id)
        assert.is_false(pcall(AuraTracker.SetUnit, AuraTracker, id, "party1"))
        assert.equals(Schema.UNIT_PLAYER, tracker.unit)
        assert.equals(Schema.AURA_HELPFUL, tracker.auraType)
        assert.is_false(pcall(AuraTracker.SetAuraType, AuraTracker, id, "MAGIC"))
        assert.equals(Schema.UNIT_PLAYER, tracker.unit)
        assert.equals(Schema.AURA_HELPFUL, tracker.auraType)
        assert.equals(Schema.UNIT_PLAYER, AuraTracker:GetUnit(id))
        assert.equals(Schema.AURA_HELPFUL, AuraTracker:GetAuraType(id))
    end)

    it("normalizes an unsupported saved pair back to the supported tokens", function()
        local id = AuraTracker:AddTracker()
        local tracker = Saved(id)
        tracker.unit = "raid1"
        tracker.auraType = "MAGIC"
        AuraTracker:OnInit()
        tracker = Saved(id)
        assert.equals(Schema.UNIT_PLAYER, tracker.unit)
        assert.equals(Schema.AURA_HELPFUL, tracker.auraType)
        assert.equals(Schema.UNIT_PLAYER, AuraTracker:GetUnit(id))
        assert.equals(Schema.AURA_HELPFUL, AuraTracker:GetAuraType(id))
    end)

    it("shows a player buff, and a target or focus debuff only while that unit cannot be assisted", function()
        local playerBar = AuraTracker:AddTracker()
        local targetBar = AuraTracker:AddTracker()
        local focusBar = AuraTracker:AddTracker()
        Enable(playerBar)
        Enable(targetBar)
        Enable(focusBar)
        AuraTracker:SetUnit(targetBar, Schema.UNIT_TARGET)
        AuraTracker:SetAuraType(targetBar, Schema.AURA_HARMFUL)
        AuraTracker:SetUnit(focusBar, Schema.UNIT_FOCUS)
        AuraTracker:SetAuraType(focusBar, Schema.AURA_HARMFUL)

        assert.is_true(AuraTracker:CanDisplayAura(playerBar))
        assert.is_false(AuraTracker:CanDisplayAura(targetBar))
        assert.is_nil(AuraTracker:GetDisplayedUnitGUID(targetBar))

        ns.Api.Unit.SetForTests("target", {
            exists = true,
            guid = "Creature-A",
            canAssist = false,
        })
        assert.is_true(AuraTracker:CanDisplayAura(targetBar))
        assert.equals("Creature-A", AuraTracker:GetDisplayedUnitGUID(targetBar))

        ns.Api.Unit.SetForTests("target", {
            exists = true,
            guid = "Player-friend",
            canAssist = true,
        })
        assert.is_true(AuraTracker:ShouldTrack(targetBar))
        assert.is_false(AuraTracker:CanDisplayAura(targetBar))
        assert.is_nil(AuraTracker:GetDisplayedUnitGUID(targetBar))
        local savedTarget = Saved(targetBar)
        assert.equals(Schema.UNIT_TARGET, savedTarget.unit)
        assert.equals(Schema.AURA_HARMFUL, savedTarget.auraType)

        ns.Api.Unit.SetForTests("target", { exists = false })
        assert.is_false(AuraTracker:CanDisplayAura(targetBar))

        ns.Api.Unit.SetForTests("focus", {
            exists = true,
            guid = "Creature-B",
            canAssist = false,
        })
        assert.is_true(AuraTracker:CanDisplayAura(focusBar))
        assert.equals("Creature-B", AuraTracker:GetDisplayedUnitGUID(focusBar))

        ns.Api.Unit.SetForTests("focus", {
            exists = true,
            guid = "Creature-C",
            canAssist = false,
        })
        assert.equals("Creature-C", AuraTracker:GetDisplayedUnitGUID(focusBar))
        assert.equals("Player-1-00000001", AuraTracker:GetDisplayedUnitGUID(playerBar))
    end)

    it("does not display an unsupported pair or a secret assist result", function()
        local id = AuraTracker:AddTracker()
        Enable(id)
        AuraTracker:SetUnit(id, Schema.UNIT_TARGET)
        assert.is_false(AuraTracker:ShouldTrack(id))
        assert.is_false(AuraTracker:CanDisplayAura(id))

        AuraTracker:SetAuraType(id, Schema.AURA_HARMFUL)
        ns.Api.Unit.SetForTests("target", { exists = true, guid = "Creature-secret" })
        assert.is_true(AuraTracker:ShouldTrack(id))
        assert.is_false(AuraTracker:CanDisplayAura(id))
    end)

    it("refreshes bars when target or focus changes, and ignores those events for player buffs", function()
        local playerBar = AuraTracker:AddTracker()
        local targetBar = AuraTracker:AddTracker()
        Enable(playerBar)
        Enable(targetBar)
        local settings = 0
        local refreshes = 0
        function AuraTracker:OnTrackerChanged()
            settings = settings + 1
        end
        function AuraTracker:OnTrackingRefresh()
            refreshes = refreshes + 1
        end

        AuraTracker:ListenForUnitContext()
        ns.Api.GameEvents.Fire("PLAYER_TARGET_CHANGED")
        ns.Api.GameEvents.Fire("PLAYER_FOCUS_CHANGED")
        ns.Api.GameEvents.Fire("UNIT_FACTION", "target")
        assert.equals(0, refreshes)
        assert.equals(0, settings)
        assert.is_nil(AuraTracker.targetRescanSerial)
        assert.is_nil(AuraTracker.focusRescanSerial)

        AuraTracker:SetUnit(targetBar, Schema.UNIT_TARGET)
        AuraTracker:SetAuraType(targetBar, Schema.AURA_HARMFUL)
        settings = 0
        refreshes = 0
        ns.Api.GameEvents.Fire("PLAYER_TARGET_CHANGED")
        ns.Api.GameEvents.Fire("PLAYER_FOCUS_CHANGED")
        ns.Api.GameEvents.Fire("UNIT_FLAGS", "focus")
        ns.Api.GameEvents.Fire("UNIT_FACTION", "party1")
        -- Same-frame events share one bar refresh and do not rebuild settings.
        assert.equals(1, refreshes)
        assert.equals(0, settings)
        assert.equals(1, AuraTracker.targetRescanSerial)
        assert.equals(1, AuraTracker.focusRescanSerial)
        -- Target info can be stale in the event frame; one coalesced pass runs next frame.
        ns.Api.Timer.RunPending()
        assert.equals(2, refreshes)
        assert.equals(0, settings)
        assert.equals(2, AuraTracker.targetRescanSerial)
        assert.equals(2, AuraTracker.focusRescanSerial)

        ns.Api.GameEvents.Fire("UNIT_FLAGS", "target")
        ns.Api.GameEvents.Fire("UNIT_FACTION", "target")
        ns.Api.GameEvents.Fire("UNIT_FACTION", "party1")
        ns.Api.Timer.RunPending()
        assert.equals(2, AuraTracker.targetRescanSerial)
        assert.equals(2, AuraTracker.focusRescanSerial)
    end)

    it("stores a target debuff in one change so the bar never sees an unsupported pair", function()
        local id = AuraTracker:AddTracker()
        local steps = {}
        function AuraTracker:OnTrackerChanged()
            steps[#steps + 1] = {
                AuraTracker:GetUnit(id),
                AuraTracker:GetAuraType(id),
                AuraTracker:IsSourceSupported(id),
            }
        end
        AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
        AuraTracker:SetSource(id, Schema.UNIT_TARGET, Schema.AURA_HARMFUL)
        assert.same({ { Schema.UNIT_TARGET, Schema.AURA_HARMFUL, true } }, steps)
        local tracker = Saved(id)
        assert.is_false(pcall(AuraTracker.SetSource, AuraTracker, id, "party1", Schema.AURA_HARMFUL))
        assert.equals(Schema.UNIT_TARGET, tracker.unit)
        assert.equals(Schema.AURA_HARMFUL, tracker.auraType)
        assert.equals(Schema.UNIT_TARGET, AuraTracker:GetUnit(id))
    end)

    it("copies unit and aura type through UpdateTracker", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:UpdateTracker(id, {
            unit = Schema.UNIT_FOCUS,
            auraType = Schema.AURA_HARMFUL,
            spellId = 172,
        })
        local tracker = Saved(id)
        assert.equals(Schema.UNIT_FOCUS, tracker.unit)
        assert.equals(Schema.AURA_HARMFUL, tracker.auraType)
        assert.equals(172, tracker.spellId)
        assert.equals(Schema.UNIT_FOCUS, AuraTracker:GetUnit(id))
        assert.equals(Schema.AURA_HARMFUL, AuraTracker:GetAuraType(id))
        assert.equals(172, AuraTracker:GetSpellId(id))

        AuraTracker:UpdateTracker(id, { unit = Schema.UNIT_TARGET })
        assert.equals(Schema.UNIT_TARGET, tracker.unit)
        assert.equals(Schema.AURA_HARMFUL, tracker.auraType)
        assert.equals(172, tracker.spellId)
    end)
end)
