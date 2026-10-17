local Harness = require("helpers.sszorak")

local EPSILON = 1e-9

local function AssertNear(expected, actual)
    if math.abs(expected - actual) >= EPSILON then
        error(string.format("expected %.12f, got %.12f", expected, actual), 2)
    end
end

describe("Sszorak", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    describe("encounter detection", function()
        local Encounter
        local changes

        before_each(function()
            Encounter = ns.Api.Encounter
            changes = 0
            Sszorak.OnEncounterChanged = function()
                changes = changes + 1
            end
            Sszorak:ListenForEncounter()
        end)

        it("starts outside the encounter", function()
            assert.is_false(Sszorak:IsInEncounter())
        end)

        it("enters and leaves this boss fight", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(Sszorak:IsInEncounter())
            assert.equals(1, changes)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(2, changes)
        end)

        it("ignores other encounters", function()
            Encounter.FireStart(1, "Other", 16, 20)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(0, changes)
            Encounter.FireEnd(1, "Other", 16, 20, 0)
            assert.is_false(Sszorak:IsInEncounter())
            assert.equals(0, changes)
        end)

        it("does not notify twice for the same state", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.equals(1, changes)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 0)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 0)
            assert.equals(2, changes)
        end)

        it("does not change the map enabled preference", function()
            Sszorak:SetMapEnabled(false)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_false(Sszorak:IsMapEnabled())
        end)
    end)

    describe("map animation", function()
        local Timer
        local moves

        local function BossX()
            return Sszorak:GetBossPosition().x
        end

        local function AdvanceTimeline(fromTime, toTime)
            Timer.Advance(toTime - fromTime)
        end

        local function ExpectedX(station, homeX)
            if station == 1 then
                return homeX
            end
            if station == 2 then
                return 0
            end
            return -homeX
        end

        before_each(function()
            Timer = ns.Api.Timer
            moves = 0
            Sszorak.OnPositionsChanged = function()
                moves = moves + 1
            end
        end)

        it("starts on the entrance side", function()
            assert.is_true(BossX() > 0.5)
            local a = Sszorak:GetGroupPosition("A")
            local b = Sszorak:GetGroupPosition("B")
            AssertNear(a.x, b.x)
            assert.is_true(a.x > 0 and a.x < BossX())
        end)

        it("follows the fixed position timeline and freezes on the last station", function()
            local homeX = BossX()
            Sszorak:StartMapAnimation()
            assert.equals(1, moves)
            AssertNear(homeX, BossX())

            local elapsed = 0
            for _, entry in ipairs(Sszorak.ACTIVE_SCHEDULE.positionTimeline) do
                AdvanceTimeline(elapsed, entry.time)
                elapsed = entry.time
                AssertNear(ExpectedX(entry.station, homeX), BossX())
            end

            local frozenX = BossX()
            AdvanceTimeline(elapsed, elapsed + 600)
            AssertNear(frozenX, BossX())
            assert.is_true(frozenX > 0.5)
        end)

        it("keeps group Y offsets while sharing the animated X", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            local a = Sszorak:GetGroupPosition("A")
            local b = Sszorak:GetGroupPosition("B")
            AssertNear(0, a.x)
            AssertNear(0, b.x)
            assert.is_true(a.y < 0 and b.y > 0)
        end)

        it("resets when started again, ignoring the previous timer", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            AssertNear(0, BossX())
            Sszorak:StartMapAnimation()
            local homeX = BossX()
            assert.is_true(homeX > 0.5)
            -- The old second jump from the first run must not fire.
            local firstJump = Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time
            local secondJump = Sszorak.ACTIVE_SCHEDULE.positionTimeline[2].time
            Timer.Advance(secondJump - firstJump)
            AssertNear(homeX, BossX())
            Timer.Advance(firstJump - (secondJump - firstJump))
            AssertNear(0, BossX())
        end)

        it("stops and snaps home", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[2].time)
            Sszorak:StopMapAnimation()
            assert.is_true(BossX() > 0.5)
            local x = BossX()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[#Sszorak.ACTIVE_SCHEDULE.positionTimeline].time)
            AssertNear(x, BossX())
        end)

        it("reports animating and home-station state for map click tracking", function()
            assert.is_false(Sszorak:IsMapAnimating())
            assert.is_true(Sszorak:IsAtHomeStation())

            local started, stopped = 0, 0
            Sszorak.OnMapAnimationStarted = function()
                started = started + 1
            end
            Sszorak.OnMapAnimationStopped = function()
                stopped = stopped + 1
            end

            Sszorak:StartMapAnimation()
            assert.is_true(Sszorak:IsMapAnimating())
            assert.is_true(Sszorak:IsAtHomeStation())
            assert.equals(1, started)

            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            assert.is_false(Sszorak:IsAtHomeStation())

            Timer.Advance(
                Sszorak.ACTIVE_SCHEDULE.positionTimeline[3].time - Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time
            )
            -- Timeline[3] is center again; home is timeline[4].
            assert.is_false(Sszorak:IsAtHomeStation())
            Timer.Advance(
                Sszorak.ACTIVE_SCHEDULE.positionTimeline[4].time - Sszorak.ACTIVE_SCHEDULE.positionTimeline[3].time
            )
            assert.is_true(Sszorak:IsAtHomeStation())
            assert.is_true(Sszorak:IsMapAnimating())

            Sszorak:StopMapAnimation()
            assert.is_false(Sszorak:IsMapAnimating())
            assert.is_true(Sszorak:IsAtHomeStation())
            assert.equals(1, stopped)
        end)

        it("starts on encounter pull and stops when the fight ends", function()
            local Encounter = ns.Api.Encounter
            -- The center move reports edge resolves; this example only checks the timeline.
            ns.Util.Print = function() end
            Sszorak:ListenForEncounter()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            AssertNear(0, BossX())

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time - 0.001)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(0.001)
            AssertNear(0, BossX())

            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.is_true(BossX() > 0.5)
            local x = BossX()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            AssertNear(x, BossX())
        end)

        it("loads the mythic schedule on mythic pulls and heroic otherwise", function()
            local Encounter = ns.Api.Encounter
            local Instance = ns.Api.Instance
            local Timeline = ns.SszorakTimeline
            local mythic = Timeline.GetSchedule(Instance.DIFFICULTY_MYTHIC_RAID)
            local heroic = Timeline.GetSchedule(Instance.DIFFICULTY_HEROIC_RAID)
            Sszorak:ListenForEncounter()

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", Instance.DIFFICULTY_MYTHIC_RAID, 20)
            assert.equals(mythic, Sszorak.ACTIVE_SCHEDULE)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", Instance.DIFFICULTY_MYTHIC_RAID, 20, 1)

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", Instance.DIFFICULTY_HEROIC_RAID, 20)
            assert.equals(heroic, Sszorak.ACTIVE_SCHEDULE)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", Instance.DIFFICULTY_HEROIC_RAID, 20, 1)

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 14, 20)
            assert.equals(heroic, Sszorak.ACTIVE_SCHEDULE)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 14, 20, 1)
        end)

        it("runs preview on a faster timeline", function()
            local firstJump = Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time
            Sszorak:StartMapAnimation({ rate = Sszorak.ANIM_PREVIEW_RATE })
            Timer.Advance(firstJump / Sszorak.ANIM_PREVIEW_RATE - 0.001)
            assert.is_true(BossX() > 0.5)
            Timer.Advance(0.001)
            AssertNear(0, BossX())
        end)
    end)

    describe("positions", function()
        it("puts the boss on the entrance-exit centerline, nearer the entrance", function()
            local boss = Sszorak:GetBossPosition()
            AssertNear(0, boss.y)
            assert.is_true(boss.x > 0.5 and boss.x < 1)
        end)

        it("puts group A below and B above, slightly closer to center than the boss", function()
            local boss = Sszorak:GetBossPosition()
            local a = Sszorak:GetGroupPosition("A")
            local b = Sszorak:GetGroupPosition("B")
            AssertNear(a.x, b.x)
            assert.is_true(a.x > 0 and a.x < boss.x)
            assert.is_true(a.y < boss.y and b.y > boss.y)
            AssertNear(boss.y - a.y, b.y - boss.y)
        end)

        it("keeps every group inside the arena", function()
            for _, group in ipairs(Sszorak.GROUPS) do
                local point = Sszorak:GetGroupPosition(group)
                assert.is_true(math.sqrt(point.x ^ 2 + point.y ^ 2) < 1)
            end
        end)

        it("rejects unknown groups", function()
            local ok = pcall(Sszorak.GetGroupPosition, Sszorak, "C")
            assert.is_false(ok)
        end)
    end)
end)
