local Loader = require("helpers.loader")

describe("AuraTracker", function()
    local ns, AuraTracker, Activation, Schema

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        AuraTracker = ns.Modules.Get("AuraTracker")
        Activation = ns.AuraTrackerActivation
        Schema = ns.AuraTrackerSchema
    end)

    it("is registered with module-level settings and no trackers", function()
        assert.is_false(AuraTracker == nil)
        assert.equals("table", type(AuraTracker.db))
        assert.is_false(AuraTracker:IsEnabled())
        assert.is_true(AuraTracker:GetHideDuringSkyriding())
        assert.is_true(AuraTracker:GetHideDuringPetBattles())
        assert.is_true(AuraTracker:GetHideDuringCinematics())
        assert.same({}, AuraTracker:GetTrackerIds())
    end)

    describe("enabled", function()
        it("toggles the module without changing per-tracker enabled flags", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetTrackerEnabled(id, true)
            local seen = {}
            function AuraTracker:OnTrackerChanged(trackerId)
                table.insert(seen, { trackerId, self:IsEnabled() })
            end
            AuraTracker:SetEnabled(true)
            AuraTracker:SetEnabled(true)
            AuraTracker:SetEnabled(false)
            assert.same({ { nil, true }, { nil, false } }, seen)
            assert.is_false(AuraTracker:IsEnabled())
            assert.is_true(AuraTracker:IsTrackerEnabled(id))
        end)
    end)

    describe("tracker lifecycle", function()
        it("adds trackers with stable unique ids that are not reused", function()
            local first = AuraTracker:AddTracker()
            local second = AuraTracker:AddTracker()
            assert.is_true(first ~= second)
            AuraTracker:RemoveTracker(first)
            local third = AuraTracker:AddTracker()
            assert.is_true(third ~= first)
            assert.is_true(third ~= second)
            assert.same({ second, third }, AuraTracker:GetTrackerIds())
        end)

        it("allows multiple trackers to share a spell ID", function()
            local a = AuraTracker:AddTracker()
            local b = AuraTracker:AddTracker()
            AuraTracker:SetSpellId(a, 774)
            AuraTracker:SetSpellId(b, 774)
            assert.equals(774, AuraTracker:GetSpellId(a))
            assert.equals(774, AuraTracker:GetSpellId(b))
        end)

        it("duplicates a tracker after the source with a new id and independent nested settings", function()
            local before = AuraTracker:AddTracker()
            local source = AuraTracker:AddTracker()
            local after = AuraTracker:AddTracker()
            AuraTracker:UpdateTracker(source, {
                spellId = 774,
                enabled = false,
                width = 240,
                height = 28,
                reverseFill = true,
                vertical = true,
                showBorder = true,
                progressMode = Schema.PROGRESS_MODE_STACKS,
                maxStacks = 5,
                fillColor = { r = 1, g = 0, b = 0 },
                backgroundColor = { r = 0, g = 0, b = 1 },
                lineColor = { r = 0, g = 1, b = 0 },
                backgroundOpacity = 0.5,
                lineThickness = 3,
                textDisplays = {
                    duration = {
                        enabled = true,
                        fontSize = 16,
                        offsetX = -40,
                        offsetY = 8,
                    },
                    stacks = {
                        enabled = true,
                        fontSize = 18,
                        offsetX = 40,
                        offsetY = -8,
                    },
                },
            })
            AuraTracker:SetActivationScope(source, Activation.ROLE, "HEALER")
            AuraTracker:SetPosition(source, {
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                x = 12,
                y = -34,
            })

            local listChanged = 0
            local changedId
            function AuraTracker:OnTrackerListChanged()
                listChanged = listChanged + 1
            end
            function AuraTracker:OnTrackerChanged(trackerId)
                changedId = trackerId
            end

            local duplicate = AuraTracker:DuplicateTracker(source)
            assert.is_true(duplicate ~= source)
            assert.is_true(duplicate ~= before)
            assert.is_true(duplicate ~= after)
            assert.same({ before, source, duplicate, after }, AuraTracker:GetTrackerIds())
            assert.equals(1, listChanged)
            assert.equals(duplicate, changedId)

            assert.equals(774, AuraTracker:GetSpellId(duplicate))
            assert.is_false(AuraTracker:IsTrackerEnabled(duplicate))
            assert.equals(240, AuraTracker:GetWidth(duplicate))
            assert.equals(28, AuraTracker:GetHeight(duplicate))
            assert.is_true(AuraTracker:GetReverseFill(duplicate))
            assert.is_true(AuraTracker:GetVertical(duplicate))
            assert.is_true(AuraTracker:GetShowBorder(duplicate))
            assert.is_true(AuraTracker:IsTextDisplayEnabled(duplicate, Schema.TEXT_DURATION))
            assert.is_true(AuraTracker:IsTextDisplayEnabled(duplicate, Schema.TEXT_STACKS))
            assert.equals(Schema.PROGRESS_MODE_STACKS, AuraTracker:GetProgressMode(duplicate))
            assert.equals(5, AuraTracker:GetMaxStacks(duplicate))
            assert.equals(0.5, AuraTracker:GetBackgroundOpacity(duplicate))
            assert.equals(3, AuraTracker:GetLineThickness(duplicate))
            assert.equals(16, AuraTracker:GetTextDisplayFontSize(duplicate, Schema.TEXT_DURATION))
            assert.equals(18, AuraTracker:GetTextDisplayFontSize(duplicate, Schema.TEXT_STACKS))
            assert.equals(-40, AuraTracker:GetTextDisplayOffsetX(duplicate, Schema.TEXT_DURATION))
            assert.equals(8, AuraTracker:GetTextDisplayOffsetY(duplicate, Schema.TEXT_DURATION))
            assert.equals(40, AuraTracker:GetTextDisplayOffsetX(duplicate, Schema.TEXT_STACKS))
            assert.equals(-8, AuraTracker:GetTextDisplayOffsetY(duplicate, Schema.TEXT_STACKS))
            local scope, target = AuraTracker:GetActivationScope(duplicate)
            assert.equals(Activation.ROLE, scope)
            assert.equals("HEALER", target)
            local position = AuraTracker:GetPosition(duplicate)
            assert.equals("TOPLEFT", position.point)
            assert.equals(12, position.x)
            assert.equals(-34, position.y)
            assert.is_true(position ~= AuraTracker:GetPosition(source))

            AuraTracker:SetFillColor(duplicate, { r = 0, g = 1, b = 0 })
            AuraTracker:SetWidth(duplicate, 100)
            AuraTracker:SetPosition(duplicate, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            })
            assert.equals(1, AuraTracker:GetFillColor(source).r)
            assert.equals(240, AuraTracker:GetWidth(source))
            assert.equals(12, AuraTracker:GetPosition(source).x)
            assert.equals(0, AuraTracker:GetFillColor(duplicate).r)
            assert.equals(1, AuraTracker:GetFillColor(duplicate).g)

            local nested = AuraTracker:DuplicateTracker(duplicate)
            assert.same({ before, source, duplicate, nested, after }, AuraTracker:GetTrackerIds())
            assert.equals(774, AuraTracker:GetSpellId(nested))
            assert.equals(100, AuraTracker:GetWidth(nested))

            AuraTracker:RemoveTracker(duplicate)
            assert.same({ before, source, nested, after }, AuraTracker:GetTrackerIds())
            assert.equals(774, AuraTracker:GetSpellId(source))
            assert.equals(100, AuraTracker:GetWidth(nested))
        end)

        it("keeps appearance settings independent per tracker", function()
            local a = AuraTracker:AddTracker()
            local b = AuraTracker:AddTracker()
            AuraTracker:SetWidth(a, 240)
            AuraTracker:SetWidth(b, 120)
            AuraTracker:SetFillColor(a, { r = 1, g = 0, b = 0 })
            AuraTracker:SetFillColor(b, { r = 0, g = 1, b = 0 })
            assert.equals(240, AuraTracker:GetWidth(a))
            assert.equals(120, AuraTracker:GetWidth(b))
            assert.equals(1, AuraTracker:GetFillColor(a).r)
            assert.equals(1, AuraTracker:GetFillColor(b).g)
        end)

        it("UpdateTracker applies a partial settings table", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:UpdateTracker(id, {
                enabled = false,
                spellId = 123,
                width = 180,
                reverseFill = true,
            })
            assert.is_false(AuraTracker:IsTrackerEnabled(id))
            assert.equals(123, AuraTracker:GetSpellId(id))
            assert.equals(180, AuraTracker:GetWidth(id))
            assert.is_true(AuraTracker:GetReverseFill(id))
        end)

        it("SetTrackerEnabled notifies only that tracker", function()
            local a = AuraTracker:AddTracker()
            local b = AuraTracker:AddTracker()
            local seen = {}
            function AuraTracker:OnTrackerChanged(trackerId)
                table.insert(seen, trackerId)
            end
            AuraTracker:SetTrackerEnabled(a, false)
            AuraTracker:SetTrackerEnabled(a, false)
            AuraTracker:SetTrackerEnabled(b, false)
            assert.same({ a, b }, seen)
        end)
    end)

    describe("spellId", function()
        it("stores a positive integer on one tracker", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetSpellId(id, 774)
            assert.equals(774, AuraTracker:GetSpellId(id))
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
            assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, 1.5))
            assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, -1))
            assert.is_false(pcall(AuraTracker.SetSpellId, AuraTracker, id, "12"))
            assert.equals(0, AuraTracker:GetSpellId(id))
        end)
    end)

    describe("display name", function()
        it("falls back to Untitled, then spell ID, then resolved name", function()
            local id = AuraTracker:AddTracker()
            assert.equals(ns.L.AURA_TRACKER_UNTITLED, AuraTracker:GetDisplayName(id))
            AuraTracker:SetSpellId(id, 774)
            assert.equals("774", AuraTracker:GetDisplayName(id))
            ns.Api.Spell.SetNameForTests(774, "Rejuvenation")
            assert.equals("Rejuvenation", AuraTracker:GetDisplayName(id))
        end)
    end)

    describe("ShouldTrack", function()
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

    describe("global visibility", function()
        local Activity

        before_each(function()
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

    describe("activation scope", function()
        local Player

        before_each(function()
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

            Player.SetContextForTests({
                specializationId = nil,
                role = nil,
            })
            assert.is_false(AuraTracker:ShouldTrack(id))

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

            Player.SetContextForTests({ specializationId = 104, role = "TANK" })
            assert.is_false(AuraTracker:ShouldTrack(id))

            Player.SetContextForTests({ specializationId = 105, role = "HEALER" })
            assert.is_true(AuraTracker:ShouldTrack(id))
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
            assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, "nope", nil))
            assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, Activation.SPECIALIZATION, 0))
            assert.is_false(pcall(AuraTracker.SetActivationScope, AuraTracker, id, Activation.ROLE, "NONE"))
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

    describe("Aura filters", function()
        it("builds includeSpellIDs as a spell-ID set", function()
            local filters = ns.Api.Aura.BuildIncludeSpellFilters(774)
            assert.is_true(filters.includeSpellIDs[774])
            assert.is_nil(filters.includeSpellIDs[1])
        end)

        it("allows spell filtering for player buffs and for harmful auras on non-assistable units", function()
            local Aura = ns.Api.Aura
            assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_PLAYER, Aura.FILTER_HELPFUL))
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_PLAYER, Aura.FILTER_HARMFUL))
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HELPFUL))
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HELPFUL))
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

            ns.Api.Unit.SetForTests("target", {
                exists = true,
                guid = "Creature-1",
                canAssist = false,
            })
            assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

            ns.Api.Unit.SetForTests("focus", {
                exists = true,
                guid = "Creature-2",
                canAssist = false,
            })
            assert.is_true(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HARMFUL))
        end)

        it("denies method access on a slot button while aura secrecy blocks tainted code", function()
            local Aura = ns.Api.Aura
            local open = {
                CanBeAccessedInContext = function()
                    return true
                end,
            }
            local denied = {
                CanBeAccessedInContext = function()
                    return false
                end,
            }
            local throwing = {
                CanBeAccessedInContext = function()
                    error("forbidden")
                end,
            }
            local forbidden = {
                IsForbidden = function()
                    return true
                end,
            }
            assert.is_true(Aura.CanAccessObject(open))
            assert.is_false(Aura.CanAccessObject(denied))
            assert.is_false(Aura.CanAccessObject(throwing))
            assert.is_false(Aura.CanAccessObject(forbidden))
            assert.is_true(Aura.CanAccessObject({}))
            assert.is_false(Aura.CanAccessObject(nil))

            local sentinel = {}
            local previousIsSecret = issecretvalue
            issecretvalue = function(value)
                return value == sentinel
            end
            local secretResult = {
                CanBeAccessedInContext = function()
                    return sentinel
                end,
            }
            assert.is_false(Aura.CanAccessObject(secretResult))
            issecretvalue = previousIsSecret

            local previousSecrets = C_Secrets
            C_Secrets = {
                ShouldAurasBeSecret = function()
                    return true
                end,
            }
            assert.is_false(Aura.CanAccessObject({}))
            C_Secrets = previousSecrets
        end)

        it("refuses the spell filter for a missing, friendly, or secret-reaction unit", function()
            local Aura = ns.Api.Aura
            local Unit = ns.Api.Unit
            Unit.SetForTests("target", { exists = false, canAssist = false })
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

            Unit.SetForTests("target", {
                exists = true,
                guid = "Player-2",
                canAssist = true,
            })
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_TARGET, Aura.FILTER_HARMFUL))

            Unit.SetForTests("focus", { exists = true, guid = "Creature-3" })
            assert.is_nil(Unit.CanPlayerAssist("focus"))
            assert.is_false(Aura.CanApplyIncludeSpellFilter(Aura.UNIT_FOCUS, Aura.FILTER_HARMFUL))
        end)
    end)

    describe("aura source", function()
        local function Enable(id)
            AuraTracker:SetEnabled(true)
            AuraTracker:SetSpellId(id, 980)
            AuraTracker:SetActivationScope(id, Activation.ALWAYS, nil)
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
            assert.is_false(pcall(AuraTracker.SetUnit, AuraTracker, id, "party1"))
            assert.is_false(pcall(AuraTracker.SetAuraType, AuraTracker, id, "MAGIC"))
            assert.equals(Schema.UNIT_PLAYER, AuraTracker:GetUnit(id))
            assert.equals(Schema.AURA_HELPFUL, AuraTracker:GetAuraType(id))
        end)

        it("normalizes an unsupported saved pair back to the supported tokens", function()
            local id = AuraTracker:AddTracker()
            for _, tracker in ipairs(AuraTracker.db.trackers) do
                if tracker.id == id then
                    tracker.unit = "raid1"
                    tracker.auraType = "MAGIC"
                end
            end
            AuraTracker:OnInit()
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
            ns.Api.GameEvents.Fire("UNIT_FACTION", "target")
            assert.equals(0, refreshes)
            assert.equals(0, settings)

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
            -- Target info can be stale in the event frame; one coalesced pass runs next frame.
            ns.Api.Timer.RunPending()
            assert.equals(2, refreshes)
            assert.equals(0, settings)
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
            assert.is_false(pcall(AuraTracker.SetSource, AuraTracker, id, "party1", Schema.AURA_HARMFUL))
            assert.equals(Schema.UNIT_TARGET, AuraTracker:GetUnit(id))
        end)

        it("copies unit and aura type through UpdateTracker", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:UpdateTracker(id, {
                unit = Schema.UNIT_FOCUS,
                auraType = Schema.AURA_HARMFUL,
                spellId = 172,
            })
            assert.equals(Schema.UNIT_FOCUS, AuraTracker:GetUnit(id))
            assert.equals(Schema.AURA_HARMFUL, AuraTracker:GetAuraType(id))
            assert.equals(172, AuraTracker:GetSpellId(id))
        end)
    end)

    describe("progress mode", function()
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
            assert.is_false(pcall(AuraTracker.SetProgressMode, AuraTracker, id, "cooldown"))
            assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(id))
            AuraTracker:SetMaxStacks(id, 0)
            assert.equals(Schema.MAX_STACKS_MIN, AuraTracker:GetMaxStacks(id))
            AuraTracker:SetMaxStacks(id, 5000)
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

        it("builds application bar options with maxApplications", function()
            local options = ns.Api.Aura.GetApplicationBarOptions(12)
            assert.equals(12, options.maxApplications)
        end)

        it("UpdateTracker applies progress mode and text display settings", function()
            local id = AuraTracker:AddTracker()
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
            assert.is_true(AuraTracker:IsStacksMode(id))
            assert.equals(8, AuraTracker:GetMaxStacks(id))
            assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
            assert.equals(15, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
            assert.equals(-6, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        end)
    end)

    describe("remaining time format", function()
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
    end)

    describe("position", function()
        it("defaults to the original center offset", function()
            local id = AuraTracker:AddTracker()
            local position = AuraTracker:GetPosition(id)
            assert.equals("CENTER", position.point)
            assert.equals("CENTER", position.relativePoint)
            assert.equals(0, position.x)
            assert.equals(-80, position.y)
        end)

        it("stores a valid anchor per tracker", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetPosition(id, { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -20 })
            local position = AuraTracker:GetPosition(id)
            assert.equals("TOPLEFT", position.point)
            assert.equals("TOPLEFT", position.relativePoint)
            assert.equals(10, position.x)
            assert.equals(-20, position.y)
        end)

        it("rejects incomplete positions", function()
            local id = AuraTracker:AddTracker()
            assert.is_false(pcall(AuraTracker.SetPosition, AuraTracker, id, { point = "TOPLEFT", x = 1, y = 2 }))
            assert.equals("CENTER", AuraTracker:GetPosition(id).point)
        end)

        it("stacks new tracker defaults so they do not fully overlap", function()
            local first = AuraTracker:AddTracker()
            local second = AuraTracker:AddTracker()
            assert.equals(-80, AuraTracker:GetPosition(first).y)
            assert.equals(-104, AuraTracker:GetPosition(second).y)
        end)
    end)

    describe("appearance", function()
        it("uses the original bar defaults", function()
            local id = AuraTracker:AddTracker()
            assert.equals(200, AuraTracker:GetWidth(id))
            assert.equals(18, AuraTracker:GetHeight(id))
            assert.equals(1, AuraTracker:GetBackgroundOpacity(id))
            assert.is_false(AuraTracker:GetReverseFill(id))
            assert.is_false(AuraTracker:GetVertical(id))
            assert.is_false(AuraTracker:GetShowBorder(id))
            assert.is_true(AuraTracker:GetShowStackDividers(id))
            assert.equals(1, AuraTracker:GetLineThickness(id))
            assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
            assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
            assert.equals(Schema.PROGRESS_MODE_DURATION, AuraTracker:GetProgressMode(id))
            assert.equals(10, AuraTracker:GetMaxStacks(id))
            assert.equals("default", AuraTracker:GetTextDisplayFont(id, Schema.TEXT_DURATION))
            assert.equals(12, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_DURATION))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
            assert.equals("flat", AuraTracker:GetTexture(id))
            assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))
            local fill = AuraTracker:GetFillColor(id)
            assert.equals(0.310, fill.r)
            assert.equals(0.765, fill.g)
            assert.equals(0.710, fill.b)
            local line = AuraTracker:GetLineColor(id)
            assert.equals(0.180, line.r)
            assert.equals(0.196, line.g)
            assert.equals(0.231, line.b)
        end)

        it("notifies OnAppearanceChanged without OnTrackerChanged", function()
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
            AuraTracker:SetWidth(id, 240)
            AuraTracker:SetHeight(id, 24)
            AuraTracker:SetFillColor(id, { r = 1, g = 0, b = 0 })
            AuraTracker:SetTexture(id, "default")
            AuraTracker:SetBackgroundColor(id, { r = 0, g = 0, b = 0 })
            AuraTracker:SetBackgroundOpacity(id, 0.5)
            AuraTracker:SetReverseFill(id, true)
            AuraTracker:SetVertical(id, true)
            AuraTracker:SetShowBorder(id, true)
            AuraTracker:SetLineColor(id, { r = 1, g = 1, b = 1 })
            AuraTracker:SetLineThickness(id, 3)
            AuraTracker:SetShowStackDividers(id, false)
            AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_DURATION, false)
            AuraTracker:SetTextDisplayEnabled(id, Schema.TEXT_STACKS, true)
            AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 16)
            AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_STACKS, 30)
            assert.equals(16, appearanceCalls)
            assert.equals(0, trackerCalls)
            assert.equals(240, AuraTracker:GetWidth(id))
            assert.equals(24, AuraTracker:GetHeight(id))
            assert.equals("default", AuraTracker:GetTexture(id))
            assert.equals(ns.Assets.Textures.STATUS_BAR, AuraTracker:GetTexturePath(id))
            assert.is_true(AuraTracker:GetReverseFill(id))
            assert.is_true(AuraTracker:GetVertical(id))
            assert.is_true(AuraTracker:GetShowBorder(id))
            assert.equals(1, AuraTracker:GetLineColor(id).r)
            assert.equals(3, AuraTracker:GetLineThickness(id))
            assert.is_false(AuraTracker:GetShowStackDividers(id))
            assert.is_false(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_DURATION))
            assert.is_true(AuraTracker:IsTextDisplayEnabled(id, Schema.TEXT_STACKS))
            assert.equals(16, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
            assert.equals(30, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
        end)

        it("keeps line style and stack-divider settings independent per tracker", function()
            local a = AuraTracker:AddTracker()
            local b = AuraTracker:AddTracker()
            AuraTracker:SetLineColor(a, { r = 1, g = 0, b = 0 })
            AuraTracker:SetLineThickness(a, 4)
            AuraTracker:SetShowStackDividers(a, false)
            assert.equals(1, AuraTracker:GetLineColor(a).r)
            assert.equals(0.180, AuraTracker:GetLineColor(b).r)
            assert.equals(4, AuraTracker:GetLineThickness(a))
            assert.equals(1, AuraTracker:GetLineThickness(b))
            assert.is_false(AuraTracker:GetShowStackDividers(a))
            assert.is_true(AuraTracker:GetShowStackDividers(b))
        end)

        it("clamps line thickness", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetLineThickness(id, 0)
            assert.equals(Schema.LINE_THICKNESS_MIN, AuraTracker:GetLineThickness(id))
            AuraTracker:SetLineThickness(id, 99)
            assert.equals(Schema.LINE_THICKNESS_MAX, AuraTracker:GetLineThickness(id))
        end)

        it("clamps size, opacity, and font size", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetWidth(id, 1)
            assert.equals(Schema.WIDTH_MIN, AuraTracker:GetWidth(id))
            AuraTracker:SetHeight(id, 999)
            assert.equals(Schema.HEIGHT_MAX, AuraTracker:GetHeight(id))
            AuraTracker:SetBackgroundOpacity(id, 2)
            assert.equals(1, AuraTracker:GetBackgroundOpacity(id))
            AuraTracker:SetTextDisplayFontSize(id, Schema.TEXT_DURATION, 1)
            assert.equals(Schema.FONT_SIZE_MIN, AuraTracker:GetTextDisplayFontSize(id, Schema.TEXT_DURATION))
        end)

        it("keeps text offsets when orientation, fill direction, or progress mode change", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, -20)
            AuraTracker:SetTextDisplayOffsetY(id, Schema.TEXT_STACKS, 12)
            AuraTracker:SetVertical(id, true)
            AuraTracker:SetReverseFill(id, true)
            AuraTracker:SetProgressMode(id, Schema.PROGRESS_MODE_STACKS)
            assert.equals(-20, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_DURATION))
            assert.equals(0, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_STACKS))
            assert.equals(12, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
        end)

        it("clamps text offsets", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetTextDisplayOffsetX(id, Schema.TEXT_DURATION, -999)
            AuraTracker:SetTextDisplayOffsetY(id, Schema.TEXT_STACKS, 999)
            assert.equals(Schema.TEXT_OFFSET_MIN, AuraTracker:GetTextDisplayOffsetX(id, Schema.TEXT_DURATION))
            assert.equals(Schema.TEXT_OFFSET_MAX, AuraTracker:GetTextDisplayOffsetY(id, Schema.TEXT_STACKS))
        end)

        it("does not notify when appearance is unchanged", function()
            local id = AuraTracker:AddTracker()
            local calls = 0
            function AuraTracker:OnAppearanceChanged()
                calls = calls + 1
            end
            AuraTracker:SetWidth(id, 200)
            AuraTracker:SetTexture(id, "flat")
            AuraTracker:SetReverseFill(id, false)
            assert.equals(0, calls)
        end)

        it("rejects unknown textures and falls back when saved value is invalid", function()
            local id = AuraTracker:AddTracker()
            assert.is_false(pcall(AuraTracker.SetTexture, AuraTracker, id, "missing"))
            local tracker = AuraTracker.db.trackers[1]
            tracker.texture = "missing"
            assert.equals("flat", AuraTracker:GetTexture(id))
            assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))
            -- Keep the raw id so a late LibSharedMedia register can restore it.
            assert.equals("missing", tracker.texture)
        end)

        it("lists only built-in textures when LibSharedMedia is absent", function()
            local ids = ns.AuraTrackerMedia.ListTextureIds()
            assert.same({ "flat", "default", "raid" }, ids)
        end)
    end)

    describe("LibSharedMedia textures", function()
        local previousLibStub
        local fakeLSM
        local registeredCallbacks

        before_each(function()
            previousLibStub = rawget(_G, "LibStub")
            registeredCallbacks = {}
            fakeLSM = {
                MediaType = { STATUSBAR = "statusbar" },
                media = {
                    statusbar = {
                        Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
                        Smooth = "Interface\\Buttons\\YELLOWORANGE64",
                        FlatLSM = "Interface\\Buttons\\WHITE8x8",
                    },
                },
            }
            function fakeLSM:List(mediaType)
                local names = {}
                for name in pairs(self.media[mediaType] or {}) do
                    names[#names + 1] = name
                end
                table.sort(names)
                return names
            end
            function fakeLSM:Fetch(mediaType, key, noDefault)
                local path = self.media[mediaType] and self.media[mediaType][key]
                if path then
                    return path
                end
                if not noDefault then
                    return self.media[mediaType] and self.media[mediaType].Blizzard
                end
                return nil
            end
            function fakeLSM.RegisterCallback(_, event, handler)
                registeredCallbacks[#registeredCallbacks + 1] = { event = event, handler = handler }
            end
            _G.LibStub = function(name, silent)
                if name == "LibSharedMedia-3.0" then
                    return fakeLSM
                end
                if silent then
                    return nil
                end
                error("library not found: " .. tostring(name))
            end
        end)

        after_each(function()
            _G.LibStub = previousLibStub
        end)

        it("resolves and stores LSM statusbar handles without storing paths", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetTexture(id, "Smooth")
            assert.equals("Smooth", AuraTracker:GetTexture(id))
            assert.equals("Smooth", AuraTracker.db.trackers[1].texture)
            assert.equals("Interface\\Buttons\\YELLOWORANGE64", AuraTracker:GetTexturePath(id))
        end)

        it("skips LSM entries that duplicate built-in ids or paths", function()
            local ids = ns.AuraTrackerMedia.ListTextureIds()
            assert.same({ "flat", "default", "raid", "Smooth" }, ids)
        end)

        it("falls back while an LSM handle is missing, then resolves after registration", function()
            local id = AuraTracker:AddTracker()
            AuraTracker.db.trackers[1].texture = "Later"
            assert.equals("flat", AuraTracker:GetTexture(id))
            assert.equals(ns.Assets.Textures.WHITE, AuraTracker:GetTexturePath(id))

            fakeLSM.media.statusbar.Later = "Interface\\Buttons\\BLUE64"
            assert.equals("Later", AuraTracker:GetTexture(id))
            assert.equals("Interface\\Buttons\\BLUE64", AuraTracker:GetTexturePath(id))
        end)
    end)
end)

describe("AuraTracker database migration", function()
    local ns

    before_each(function()
        ns = Loader.Load()
    end)

    it("renames BuffTracker module settings to AuraTracker", function()
        local saved = {
            schemaVersion = 1,
            modules = {
                BuffTracker = { enabled = true, spellId = 774, width = 240 },
            },
        }
        local loaded = ns.Database.Load(saved)
        assert.equals(6, loaded.schemaVersion)
        assert.is_nil(loaded.modules.BuffTracker)
        assert.equals(true, loaded.modules.AuraTracker.enabled)
        assert.equals(1, #loaded.modules.AuraTracker.trackers)
        assert.equals(774, loaded.modules.AuraTracker.trackers[1].spellId)
        assert.equals(240, loaded.modules.AuraTracker.trackers[1].width)
        assert.equals(2, loaded.modules.AuraTracker.nextTrackerId)
        assert.is_nil(loaded.modules.AuraTracker.spellId)
    end)

    it("converts flat AuraTracker settings into a trackers collection", function()
        local saved = {
            schemaVersion = 2,
            modules = {
                AuraTracker = {
                    enabled = true,
                    spellId = 774,
                    width = 240,
                    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -80 },
                },
            },
        }
        local loaded = ns.Database.Load(saved)
        assert.equals(6, loaded.schemaVersion)
        local tracker = loaded.modules.AuraTracker.trackers[1]
        assert.equals(1, tracker.id)
        assert.is_true(tracker.enabled)
        assert.equals(774, tracker.spellId)
        assert.equals(240, tracker.width)
        assert.equals(-80, tracker.position.y)
        assert.is_true(loaded.modules.AuraTracker.enabled)
    end)
end)

describe("AuraTracker deferred appearance", function()
    local ns, AuraTracker

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        AuraTracker = ns.Modules.Get("AuraTracker")
    end)

    it("reports only the saved fields that differ from the last painted look", function()
        local id = AuraTracker:AddTracker()
        local painted = AuraTracker:CaptureDeferredAppearance(id)
        assert.same({}, AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id)))

        AuraTracker:SetWidth(id, 240)
        AuraTracker:SetFillColor(id, { r = 1, g = 0, b = 0 })
        AuraTracker:SetProgressMode(id, ns.AuraTrackerSchema.PROGRESS_MODE_STACKS)
        AuraTracker:SetTextDisplayEnabled(id, ns.AuraTrackerSchema.TEXT_STACKS, true)
        AuraTracker:SetSpellId(id, 774)
        local pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_true(pending.width)
        assert.is_true(pending.fillColor)
        assert.is_true(pending.progressMode)
        assert.is_true(pending["text.stacks.enabled"])
        assert.is_nil(pending.spellId)
        assert.is_nil(pending.height)

        AuraTracker:SetWidth(id, painted.width)
        pending = AuraTracker.DiffDeferredAppearance(painted, AuraTracker:CaptureDeferredAppearance(id))
        assert.is_nil(pending.width)
        assert.is_true(pending.fillColor)
    end)
end)

describe("AuraTracker profile report", function()
    local ns, profile

    before_each(function()
        ns = Loader.Load()
        profile = ns.AuraTrackerProfile
    end)

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
    end)

    it("lists each counter once, sorted", function()
        profile.Record()
        profile.Inc("event.PLAYER_TARGET_CHANGED")
        profile.Inc("event.PLAYER_TARGET_CHANGED")
        profile.Stop("bar.display", profile.Start())
        local text = profile.Report()
        local displayAt = text:find("bar.display", 1, true)
        local eventAt = text:find("event.PLAYER_TARGET_CHANGED", 1, true)
        assert.is_true(displayAt ~= nil and eventAt ~= nil and displayAt < eventAt)
        local _, displayCount = text:gsub("bar%.display", "")
        assert.equals(1, displayCount)
    end)
end)
