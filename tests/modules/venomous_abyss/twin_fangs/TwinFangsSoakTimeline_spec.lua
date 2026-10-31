local Loader = require("helpers.loader")

describe("TwinFangs soak timeline", function()
    local ns, Module, SoakTimeline

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("TwinFangs")
        SoakTimeline = ns.Modules.Internals("TwinFangs").SoakTimeline
    end)

    it("places the three hits on the real 4.25 / 2.00 / 1.50 timing", function()
        assert.equals(4.25, Module.CAST_SECONDS)
        assert.equals(2, Module.HIT2_GAP)
        assert.equals(1.5, Module.HIT3_GAP)
        assert.equals(7.75, SoakTimeline.DURATION)
        assert.same({ 4.25, 6.25, 7.75 }, SoakTimeline.HIT_AT)
        assert.equals(4.25 / 7.75, SoakTimeline.HitFraction(1))
        assert.equals(6.25 / 7.75, SoakTimeline.HitFraction(2))
        assert.equals(1, SoakTimeline.HitFraction(3))
        local firstGap = SoakTimeline.HitFraction(2) - SoakTimeline.HitFraction(1)
        local secondGap = SoakTimeline.HitFraction(3) - SoakTimeline.HitFraction(2)
        assert.is_true(firstGap > secondGap)
    end)

    it("treats the fill as elapsed time and the numbered nodes as the next hit", function()
        local beforeFirst = SoakTimeline.StateAt(0)
        assert.equals(0, beforeFirst.progress)
        assert.equals(1, beforeFirst.activeHit)
        assert.equals("active", beforeFirst.nodes[1].status)
        assert.equals("pending", beforeFirst.nodes[2].status)
        assert.equals("pending", beforeFirst.nodes[3].status)
        assert.is_false(beforeFirst.nodes[1].flashing)

        local stillWindup = SoakTimeline.StateAt(4.24)
        assert.equals(1, stillWindup.activeHit)
        assert.equals("active", stillWindup.nodes[1].status)

        local afterFirst = SoakTimeline.StateAt(4.25)
        assert.equals(4.25 / 7.75, afterFirst.progress)
        assert.equals(2, afterFirst.activeHit)
        assert.equals("completed", afterFirst.nodes[1].status)
        assert.equals("active", afterFirst.nodes[2].status)
        assert.is_true(afterFirst.nodes[1].flashing)
        assert.is_false(afterFirst.nodes[2].flashing)

        local afterSecond = SoakTimeline.StateAt(6.25)
        assert.equals(3, afterSecond.activeHit)
        assert.equals("completed", afterSecond.nodes[1].status)
        assert.equals("completed", afterSecond.nodes[2].status)
        assert.equals("active", afterSecond.nodes[3].status)
        assert.is_true(afterSecond.nodes[2].flashing)

        local afterThird = SoakTimeline.StateAt(7.75)
        assert.equals(1, afterThird.progress)
        assert.is_nil(afterThird.activeHit)
        assert.equals("completed", afterThird.nodes[1].status)
        assert.equals("completed", afterThird.nodes[2].status)
        assert.equals("completed", afterThird.nodes[3].status)
        assert.is_true(afterThird.nodes[3].flashing)
    end)

    it("drops the hit flash and holds the completed bar before looping", function()
        local afterFlash = SoakTimeline.StateAt(4.25 + SoakTimeline.FLASH)
        assert.equals("completed", afterFlash.nodes[1].status)
        assert.is_false(afterFlash.nodes[1].flashing)

        local holding = SoakTimeline.StateAt(SoakTimeline.DURATION + 0.4)
        assert.equals(1, holding.progress)
        assert.is_nil(holding.activeHit)
        assert.is_false(holding.nodes[3].flashing)

        local restarted = SoakTimeline.StateAt(SoakTimeline.LOOP)
        assert.equals(0, restarted.progress)
        assert.equals(1, restarted.activeHit)
        assert.equals("active", restarted.nodes[1].status)
        assert.equals("pending", restarted.nodes[3].status)
    end)

    it("aligns Feast 1 callouts with the assigned hit on the looping preview clock", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        local hit1, hit2, hit3 = unpack(SoakTimeline.HIT_AT)

        local rightAtStart = SoakTimeline.PreviewCallout(0, 1)
        assert.equals("enter", rightAtStart.kind)
        assert.equals(hit1, rightAtStart.remaining)
        assert.equals("active", SoakTimeline.StateAt(0, 1).nodes[1].status)

        local rightAtHit = SoakTimeline.PreviewCallout(hit1, 1)
        assert.is_nil(rightAtHit)
        assert.equals("completed", SoakTimeline.StateAt(hit1, 1).nodes[1].status)

        local leftPrepare = SoakTimeline.PreviewCallout(0, SoakTimeline.AssignedHitForGroup(Schema.GROUP_LEFT))
        assert.equals("prepare", leftPrepare.kind)
        assert.equals(hit1, leftPrepare.remaining)
        local leftNow = SoakTimeline.PreviewCallout(hit1, 2)
        assert.equals("now", leftNow.kind)
        assert.equals(hit2 - hit1, leftNow.remaining)
        assert.equals("active", SoakTimeline.StateAt(hit1, 2).nodes[2].status)
        assert.is_nil(SoakTimeline.PreviewCallout(hit2, 2))

        local middlePrepare = SoakTimeline.PreviewCallout(0, 3)
        assert.equals("prepare", middlePrepare.kind)
        assert.equals(hit2, middlePrepare.remaining)
        local middleNow = SoakTimeline.PreviewCallout(hit2, 3)
        assert.equals("now", middleNow.kind)
        assert.equals(hit3 - hit2, middleNow.remaining)
        assert.is_nil(SoakTimeline.PreviewCallout(hit3, 3))
        assert.is_nil(SoakTimeline.PreviewCallout(SoakTimeline.DURATION + 0.4, 3))

        local restarted = SoakTimeline.PreviewCallout(SoakTimeline.LOOP, 1)
        assert.equals("enter", restarted.kind)
        assert.equals(hit1, restarted.remaining)
    end)

    it("maps the player's soak group onto a hit without changing the fill timeline", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        assert.equals(1, SoakTimeline.AssignedHitForGroup(Schema.GROUP_RIGHT, 1))
        assert.equals(2, SoakTimeline.AssignedHitForGroup(Schema.GROUP_LEFT, 1))
        assert.equals(3, SoakTimeline.AssignedHitForGroup(Schema.GROUP_MIDDLE, 1))
        assert.equals(1, SoakTimeline.AssignedHitForGroup(Schema.GROUP_LEFT, 3))
        assert.equals(2, SoakTimeline.AssignedHitForGroup(Schema.GROUP_RIGHT, 3))
        assert.equals(3, SoakTimeline.AssignedHitForGroup(Schema.GROUP_MIDDLE, 4))

        local assignedSecond = SoakTimeline.StateAt(0, 2)
        assert.equals(2, assignedSecond.assignedHit)
        assert.equals(1, assignedSecond.activeHit)
        assert.equals(0, assignedSecond.progress)
        assert.is_false(assignedSecond.nodes[1].assigned)
        assert.is_true(assignedSecond.nodes[2].assigned)
        assert.equals("active", assignedSecond.nodes[1].status)
        assert.equals("pending", assignedSecond.nodes[2].status)

        local duringOwnHit = SoakTimeline.StateAt(6.24, 2)
        assert.equals("completed", duringOwnHit.nodes[1].status)
        assert.equals("active", duringOwnHit.nodes[2].status)
        assert.is_true(duringOwnHit.nodes[2].assigned)

        local afterOwnHit = SoakTimeline.StateAt(6.25, 2)
        assert.equals("completed", afterOwnHit.nodes[2].status)
        assert.is_true(afterOwnHit.nodes[2].assigned)
        assert.equals(3, afterOwnHit.activeHit)
        assert.is_false(afterOwnHit.nodes[3].assigned)
    end)

    it("does not loop a live sequence after the third hit", function()
        local afterHit3 = SoakTimeline.SequenceState(SoakTimeline.DURATION + 1)
        assert.equals(1, afterHit3.progress)
        assert.is_nil(afterHit3.activeHit)
        assert.equals("completed", afterHit3.nodes[3].status)
    end)

    it("defaults below center and persists a moved timeline anchor", function()
        local Schema = ns.Modules.Internals("TwinFangs").Schema
        assert.same(Schema.DefaultSoakTimelinePosition(), Module:GetSoakTimelinePosition())
        local position = { point = "TOP", relativePoint = "TOP", x = 10, y = -24 }
        Module:SetSoakTimelinePosition(position)
        assert.same(position, Module.db.soakTimelinePosition)
        assert.equals(Module.db.soakTimelinePosition, Module:GetSoakTimelinePosition())

        local reloaded = Loader.Load()
        reloaded.Modules.Start(ns.Database.Load({
            modules = {
                TwinFangs = { soakTimelinePosition = position },
            },
        }))
        assert.same(position, reloaded.Modules.Get("TwinFangs"):GetSoakTimelinePosition())
    end)

    it("replaces an invalid saved timeline position with the factory anchor", function()
        local fresh = Loader.Load()
        fresh.Modules.Start(fresh.Database.Load({
            modules = {
                TwinFangs = {
                    soakTimelinePosition = {
                        point = "CENTER",
                        relativePoint = "CENTER",
                        x = "bad",
                        y = 0,
                    },
                },
            },
        }))
        assert.same(
            fresh.Modules.Internals("TwinFangs").Schema.DefaultSoakTimelinePosition(),
            fresh.Modules.Get("TwinFangs"):GetSoakTimelinePosition()
        )
    end)

    describe("during a Mythic feast", function()
        local Encounter, EncounterTimeline, Instance, Timer
        local starts
        local stops
        local nextEventId

        local function ActiveEvent(duration)
            local eventInfo = {
                id = nextEventId,
                source = EncounterTimeline.EVENT_SOURCE_ENCOUNTER,
                duration = duration,
            }
            nextEventId = nextEventId + 1
            EncounterTimeline.SetEventStateForTests(eventInfo.id, EncounterTimeline.EVENT_STATE_ACTIVE)
            return eventInfo
        end

        before_each(function()
            Encounter = ns.Api.Encounter
            EncounterTimeline = ns.Api.EncounterTimeline
            Instance = ns.Api.Instance
            Timer = ns.Api.Timer
            nextEventId = 1
            starts = {}
            stops = 0
            function Module:StartSoakTimeline(beginAt)
                starts[#starts + 1] = beginAt
            end
            function Module:StopSoakTimeline()
                stops = stops + 1
            end
            Module:ListenForEncounter()
            Module:SetSoakReminderEnabled(true)
        end)

        it("shows the bar when Ravenous Feast begins and hides it after hit 3", function()
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            local duration = Module.FEAST_DURATION
            local beginAt = Timer.GetTime() + duration
            EncounterTimeline.FireEventAdded(ActiveEvent(duration))

            Timer.Advance(duration - 0.01)
            assert.same({}, starts)
            Timer.Advance(0.01)
            assert.same({ beginAt }, starts)

            Timer.Advance(SoakTimeline.DURATION - 0.01)
            assert.equals(0, stops)
            Timer.Advance(0.01)
            assert.equals(1, stops)
        end)

        it("stays hidden when the timeline checkbox is off", function()
            Module:SetSoakTimelineEnabled(false)
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
            Timer.Advance(Module.FEAST_DURATION + SoakTimeline.DURATION)
            assert.same({}, starts)
        end)

        it("hides the bar when the pull ends", function()
            Encounter.FireStart(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            EncounterTimeline.FireEventAdded(ActiveEvent(Module.FEAST_DURATION))
            Timer.Advance(Module.FEAST_DURATION)
            assert.equals(1, #starts)
            Encounter.FireEnd(Module.ENCOUNTER_ID, "Twin Fangs", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)
            assert.is_true(stops >= 1)
        end)
    end)
end)
