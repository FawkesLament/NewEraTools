local Harness = require("helpers.aura_tracker")
local Loader = require("helpers.loader")

---@param module table
---@param trackerId integer
---@return table|nil
local function SavedTracker(module, trackerId)
    for _, tracker in ipairs(module.db.trackers) do
        if tracker.id == trackerId then
            return tracker
        end
    end
end

describe("AuraTracker", function()
    local AuraTracker, Activation, Schema

    before_each(function()
        local _
        _, AuraTracker, Activation, Schema = Harness.Start()
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

        it("assigns a new id when reloaded nextTrackerId collides with saved trackers", function()
            local ns = Loader.Load()
            local saved = {
                modules = {
                    AuraTracker = {
                        nextTrackerId = 1,
                        trackers = {
                            { id = 1, spellId = 774 },
                            { id = 2, spellId = 8936 },
                        },
                    },
                },
            }
            local loaded = ns.Database.Load(saved)
            ns.Modules.Start(loaded)
            local reloaded = ns.Modules.Get("AuraTracker")
            local raw = loaded.modules.AuraTracker
            assert.is_true(reloaded.db == raw)
            assert.equals(3, raw.nextTrackerId)
            assert.equals(1, raw.trackers[1].id)
            assert.equals(2, raw.trackers[2].id)
            assert.equals(774, raw.trackers[1].spellId)
            assert.equals(8936, raw.trackers[2].spellId)

            local third = reloaded:AddTracker()
            assert.equals(3, third)
            assert.equals(4, raw.nextTrackerId)
            assert.equals(1, raw.trackers[1].id)
            assert.equals(2, raw.trackers[2].id)
            assert.equals(3, raw.trackers[3].id)
            assert.equals(774, raw.trackers[1].spellId)
            assert.equals(8936, raw.trackers[2].spellId)
            assert.same({ 1, 2, 3 }, reloaded:GetTrackerIds())
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
            local sourceSaved = SavedTracker(AuraTracker, source)
            local duplicateSaved = SavedTracker(AuraTracker, duplicate)
            assert.is_true(sourceSaved.textDisplays ~= duplicateSaved.textDisplays)
            assert.is_true(sourceSaved.textDisplays.duration ~= duplicateSaved.textDisplays.duration)
            assert.is_true(sourceSaved.backgroundColor ~= duplicateSaved.backgroundColor)
            assert.is_true(sourceSaved.lineColor ~= duplicateSaved.lineColor)

            AuraTracker:SetFillColor(duplicate, { r = 0, g = 1, b = 0 })
            AuraTracker:SetBackgroundColor(duplicate, { r = 1, g = 1, b = 0 })
            AuraTracker:SetTextDisplayOffsetX(duplicate, Schema.TEXT_DURATION, 7)
            AuraTracker:SetWidth(duplicate, 100)
            AuraTracker:SetPosition(duplicate, {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            })
            assert.equals(1, AuraTracker:GetFillColor(source).r)
            assert.equals(0, AuraTracker:GetBackgroundColor(source).r)
            assert.equals(0, AuraTracker:GetBackgroundColor(source).g)
            assert.equals(1, AuraTracker:GetBackgroundColor(source).b)
            assert.equals(-40, AuraTracker:GetTextDisplayOffsetX(source, Schema.TEXT_DURATION))
            assert.equals(240, AuraTracker:GetWidth(source))
            assert.equals(12, AuraTracker:GetPosition(source).x)
            assert.equals(0, AuraTracker:GetFillColor(duplicate).r)
            assert.equals(1, AuraTracker:GetFillColor(duplicate).g)
            assert.equals(1, AuraTracker:GetBackgroundColor(duplicate).r)
            assert.equals(7, AuraTracker:GetTextDisplayOffsetX(duplicate, Schema.TEXT_DURATION))

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
            AuraTracker:SetSpellId(a, 774)
            AuraTracker:SetSpellId(b, 8936)
            AuraTracker:SetWidth(a, 240)
            AuraTracker:SetWidth(b, 120)
            AuraTracker:SetFillColor(a, { r = 1, g = 0, b = 0 })
            AuraTracker:SetFillColor(b, { r = 0, g = 1, b = 0 })
            AuraTracker:SetSpellId(a, 1126)
            assert.equals(240, AuraTracker:GetWidth(a))
            assert.equals(120, AuraTracker:GetWidth(b))
            assert.equals(1, AuraTracker:GetFillColor(a).r)
            assert.equals(1, AuraTracker:GetFillColor(b).g)
            assert.equals(1126, SavedTracker(AuraTracker, a).spellId)
            assert.equals(8936, SavedTracker(AuraTracker, b).spellId)
        end)

        it("UpdateTracker applies a partial settings table", function()
            local id = AuraTracker:AddTracker()
            AuraTracker:SetHeight(id, 32)
            AuraTracker:SetSource(id, Schema.UNIT_FOCUS, Schema.AURA_HARMFUL)
            AuraTracker:SetPosition(id, {
                point = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                x = 15,
                y = -40,
            })
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

            local tracker = SavedTracker(AuraTracker, id)
            assert.equals(false, tracker.enabled)
            assert.equals(123, tracker.spellId)
            assert.equals(180, tracker.width)
            assert.is_true(tracker.reverseFill)
            assert.equals(32, tracker.height)
            assert.equals(Schema.UNIT_FOCUS, tracker.unit)
            assert.equals(Schema.AURA_HARMFUL, tracker.auraType)
            assert.equals("TOPLEFT", tracker.position.point)
            assert.equals("BOTTOMLEFT", tracker.position.relativePoint)
            assert.equals(15, tracker.position.x)
            assert.equals(-40, tracker.position.y)
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
end)
