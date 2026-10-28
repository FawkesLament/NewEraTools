local Loader = require("helpers.loader")

describe("TheLostExplorers", function()
    local ns, Module, Encounter, EncounterTimeline, Spell, Timer, Combat

    local function StartFight()
        Module:SetEnabled(true)
        Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
    end

    local function EndFight()
        Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
    end

    -- Final Ascension channel ending is the in-fight path that clears the active warning.
    local function FinishChannel()
        Spell.FireChannelStop(Module.BOSS_UNIT, nil, nil)
    end

    local function MatchingTimelineEvent(overrides)
        local eventInfo = {
            id = 1001,
            source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER,
            duration = 60,
        }
        if overrides then
            for key, value in pairs(overrides) do
                eventInfo[key] = value
            end
        end
        EncounterTimeline.SetEventStateForTests(eventInfo.id, EncounterTimeline.EVENT_STATE_ACTIVE)
        return eventInfo
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TheLostExplorers")
        Encounter = ns.Api.Encounter
        EncounterTimeline = ns.Api.EncounterTimeline
        Spell = ns.Api.Spell
        Timer = ns.Api.Timer
        Combat = ns.Api.Combat
        Module:ListenForFeedFish()
    end)

    it("is registered with saved settings", function()
        assert.is_false(Module == nil)
        assert.equals("table", type(Module.db))
        assert.is_false(Module:IsEnabled())
        assert.equals("table", type(Module:GetCalloutPosition()))
        assert.equals("table", type(Module:GetFeedOrder()))
        assert.is_false(Module:HasCompleteFeedOrder())
    end)

    describe("enabled", function()
        it("toggles and persists on the module db", function()
            Module:SetEnabled(true)
            assert.is_true(Module:IsEnabled())
            assert.is_true(Module.db.enabled)

            Module:SetEnabled(false)
            assert.is_false(Module:IsEnabled())
            assert.is_false(Module.db.enabled)
        end)
    end)

    describe("encounter", function()
        local function TimelineListenerCount()
            local list = ns.Api.GameEvents.handlers["ENCOUNTER_TIMELINE_EVENT_ADDED"]
            return list and #list or 0
        end

        it("tracks only encounter 3497", function()
            Module:SetEnabled(true)
            Encounter.FireStart(1, "Other", 16, 20)
            assert.is_false(Module:IsInEncounter())
            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            assert.is_true(Module:IsInEncounter())
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
            assert.is_false(Module:IsInEncounter())
        end)

        it("starts fight listeners only while enabled inside the encounter", function()
            assert.is_false(Module:IsListeningForFight())
            assert.equals(0, TimelineListenerCount())
            assert.is_false(Spell.HasChannelStopListener(Module.BOSS_UNIT))

            Module:SetEnabled(true)
            assert.is_false(Module:IsListeningForFight())

            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            assert.is_true(Module:IsListeningForFight())
            assert.equals(1, TimelineListenerCount())
            assert.is_true(Spell.HasChannelStopListener(Module.BOSS_UNIT))

            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
            assert.is_false(Module:IsListeningForFight())
            assert.equals(0, TimelineListenerCount())
            assert.is_false(Spell.HasChannelStopListener(Module.BOSS_UNIT))
        end)

        it("stops fight listeners when the feature is turned off mid-fight", function()
            StartFight()
            assert.is_true(Module:IsListeningForFight())
            Module:SetEnabled(false)
            assert.is_false(Module:IsListeningForFight())
            assert.equals(0, TimelineListenerCount())
        end)

        it("restarts fight listeners when the feature is turned back on mid-fight", function()
            StartFight()
            Module:SetEnabled(false)
            Module:SetEnabled(true)
            assert.is_true(Module:IsInEncounter())
            assert.is_true(Module:IsListeningForFight())
            assert.equals(1, TimelineListenerCount())
            assert.is_true(Spell.HasChannelStopListener(Module.BOSS_UNIT))
        end)

        it("does not accumulate timeline listeners across pulls", function()
            StartFight()
            assert.equals(1, TimelineListenerCount())
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
            assert.equals(0, TimelineListenerCount())
            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            assert.equals(1, TimelineListenerCount())
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
            assert.equals(0, TimelineListenerCount())
        end)
    end)

    describe("feed fish callout", function()
        it("schedules the callout after the delay following a matching timeline event", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            assert.equals(nil, Module:GetDisplayedCallout())

            Timer.Advance(Module.CALLOUT_DELAY - 0.01)
            assert.equals(nil, Module:GetDisplayedCallout())

            Timer.Advance(0.01)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            assert.equals(Timer.GetTime() + Module.CALLOUT_DURATION, Module:GetCalloutExpiresAt())
        end)

        it("clears the callout after its duration", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            Timer.Advance(Module.CALLOUT_DURATION)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("ignores timeline events that fail the filters", function()
            StartFight()

            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ source = 1 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())

            local inactive = MatchingTimelineEvent({ id = 1002 })
            EncounterTimeline.SetEventStateForTests(inactive.id, 2)
            EncounterTimeline.FireEventAdded(inactive)
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())

            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 1003, duration = 45 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("ignores timeline events when disabled or outside the fight", function()
            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())

            Module:SetEnabled(true)
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 1004 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        -- In encounters boss2's channel events carry a nil castGUID and a secret spellID.
        it("cancels a pending callout when boss2's channel stops", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Spell.FireChannelStop(Module.BOSS_UNIT, nil, nil)
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("clears an active callout when boss2's channel stops without a seen start", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            Spell.FireChannelStop(Module.BOSS_UNIT, nil, nil)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("does not let an earlier channel stop cancel a later warning", function()
            StartFight()
            Spell.FireChannelStop(Module.BOSS_UNIT, nil, nil)
            Spell.FireChannelStart(Module.BOSS_UNIT, nil, nil)
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("clears an active callout when the encounter ends", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            EndFight()
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("cancels a pending callout when the encounter ends", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY / 2)
            EndFight()
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("does not carry a pending callout into the next pull", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6001 }))
            Timer.Advance(Module.CALLOUT_DELAY / 3)
            EndFight()
            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())

            -- The new pull still schedules its own first warning normally.
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6002 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            EndFight()
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("keeps the callout when the player leaves combat mid-pull", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6101 }))
            Combat.FireLeave()
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            Combat.FireLeave()
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("leaves other sources' callouts alone when the encounter ends", function()
            StartFight()
            ns.CalloutManager.Show({ source = "OtherFeature", text = "other", duration = 60 })
            EndFight()
            assert.equals("other", ns.CalloutManager.GetCurrent().text)
        end)

        it("cancels pending work when the feature is turned off", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Module:SetEnabled(false)
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("does not revive a cancelled callout when re-enabled mid-fight", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Module:SetEnabled(false)
            Module:SetEnabled(true)
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("clears an active callout when the feature is turned off mid-fight", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
            Module:SetEnabled(false)
            assert.equals(nil, Module:GetDisplayedCallout())
        end)

        it("lets the latest schedule win within a pull", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_TRADER)
            Module:SetFeedOrderSlot(2, Module.BOSS_FIRST_MATE)
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6201 }))
            Timer.Advance(10)
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6202 }))
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 6203 }))

            Timer.Advance(Module.CALLOUT_DELAY - 10)
            assert.equals(nil, Module:GetDisplayedCallout())

            Timer.Advance(10)
            assert.equals(
                string.format(
                    ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_ORDERED,
                    ns.L.THE_LOST_EXPLORERS_BOSS_FIRST_MATE
                ),
                Module:GetDisplayedCallout()
            )
        end)

        it("accepts durations that round to 60", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ duration = 59.6 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("schedules only on the 1st, 3rd, and 5th matching timeline events", function()
            StartFight()
            local scheduled = 0
            for index = 1, 6 do
                EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 2000 + index }))
                Timer.Advance(Module.CALLOUT_DELAY)
                local shown = Module:GetDisplayedCallout() ~= nil
                if index == 1 or index == 3 or index == 5 then
                    assert.is_true(shown)
                    scheduled = scheduled + 1
                    FinishChannel()
                    assert.equals(nil, Module:GetDisplayedCallout())
                else
                    assert.is_false(shown)
                end
            end
            assert.equals(3, scheduled)
        end)

        it("resets the match count for a new encounter", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 3001 }))
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 3002 }))
            Encounter.FireEnd(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20, 1)

            Encounter.FireStart(Module.ENCOUNTER_ID, "The Lost Explorers", 16, 20)
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 3003 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("keeps the match count across a mid-fight toggle", function()
            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 4001 }))
            Module:SetEnabled(false)
            Module:SetEnabled(true)
            -- Next match is the 2nd overall this pull; should not schedule.
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 4002 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(nil, Module:GetDisplayedCallout())
            -- 3rd match should schedule.
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 4003 }))
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("keeps the default callout text when the feed order is incomplete", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_FIRST_MATE)
            assert.is_false(Module:HasCompleteFeedOrder())
            assert.equals(nil, Module:GetFeedOrderSlot(3))

            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("names the configured boss once the feed order is complete", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_TRADER)
            Module:SetFeedOrderSlot(2, Module.BOSS_FIRST_MATE)
            assert.is_true(Module:HasCompleteFeedOrder())
            assert.equals(Module.BOSS_SCROLLAGE, Module:GetFeedOrderSlot(3))

            StartFight()
            local expected = {
                string.format(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_ORDERED, ns.L.THE_LOST_EXPLORERS_BOSS_TRADER),
                string.format(
                    ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_ORDERED,
                    ns.L.THE_LOST_EXPLORERS_BOSS_FIRST_MATE
                ),
                string.format(
                    ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT_ORDERED,
                    ns.L.THE_LOST_EXPLORERS_BOSS_SCROLLAGE
                ),
            }
            local calloutIndex = 0
            for index = 1, 6 do
                EncounterTimeline.FireEventAdded(MatchingTimelineEvent({ id = 5000 + index }))
                Timer.Advance(Module.CALLOUT_DELAY)
                if index == 1 or index == 3 or index == 5 then
                    calloutIndex = calloutIndex + 1
                    assert.equals(expected[calloutIndex], Module:GetDisplayedCallout())
                    FinishChannel()
                    assert.equals(nil, Module:GetDisplayedCallout())
                else
                    assert.equals(nil, Module:GetDisplayedCallout())
                end
            end
        end)
    end)

    describe("feed order", function()
        it("resolves the third slot from the first two choices", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_FIRST_MATE)
            Module:SetFeedOrderSlot(2, Module.BOSS_SCROLLAGE)
            assert.equals(Module.BOSS_TRADER, Module:GetFeedOrderSlot(3))
            assert.is_true(Module:HasCompleteFeedOrder())

            Module:SetFeedOrderSlot(2, nil)
            assert.equals(nil, Module:GetFeedOrderSlot(3))
            assert.is_false(Module:HasCompleteFeedOrder())
        end)

        it("clears later slots when an earlier slot changes", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_FIRST_MATE)
            Module:SetFeedOrderSlot(2, Module.BOSS_SCROLLAGE)
            assert.equals(Module.BOSS_TRADER, Module:GetFeedOrderSlot(3))
            Module:SetFeedOrderSlot(1, Module.BOSS_TRADER)

            assert.equals(Module.BOSS_TRADER, Module:GetFeedOrderSlot(1))
            assert.equals(nil, Module:GetFeedOrderSlot(2))
            assert.equals(nil, Module:GetFeedOrderSlot(3))
            assert.is_false(Module:HasCompleteFeedOrder())
        end)

        it("ignores a later slot until earlier slots are filled", function()
            Module:SetFeedOrderSlot(2, Module.BOSS_SCROLLAGE)
            assert.equals(nil, Module:GetFeedOrderSlot(1))
            assert.equals(nil, Module:GetFeedOrderSlot(2))
            assert.equals(nil, Module:GetFeedOrderSlot(3))
        end)

        it("clears the sequence and restores the default callout text", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_FIRST_MATE)
            Module:SetFeedOrderSlot(2, Module.BOSS_SCROLLAGE)
            assert.is_true(Module:HasCompleteFeedOrder())
            Module:ClearFeedOrder()
            assert.is_false(Module:HasCompleteFeedOrder())

            StartFight()
            EncounterTimeline.FireEventAdded(MatchingTimelineEvent())
            Timer.Advance(Module.CALLOUT_DELAY)
            assert.equals(ns.L.THE_LOST_EXPLORERS_FEED_FISH_CALLOUT, Module:GetDisplayedCallout())
        end)

        it("persists the configured order on the module db", function()
            Module:SetFeedOrderSlot(1, Module.BOSS_SCROLLAGE)
            Module:SetFeedOrderSlot(2, Module.BOSS_TRADER)
            assert.same({
                Module.BOSS_SCROLLAGE,
                Module.BOSS_TRADER,
                Module.BOSS_FIRST_MATE,
            }, Module.db.feedOrder)
        end)
    end)
end)
