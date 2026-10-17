local Harness = require("helpers.sszorak")

describe("SszorakCallout", function()
    local ns, Sszorak

    before_each(function()
        ns, Sszorak = Harness.Start()
    end)

    describe("raid leader messages", function()
        local Chat
        local Encounter
        local Timer

        local function HomeReturnTime(index)
            local count = 0
            for _, entry in ipairs(Sszorak.ACTIVE_SCHEDULE.positionTimeline) do
                if entry.station == 1 then
                    count = count + 1
                    if count == index then
                        return entry.time
                    end
                end
            end
        end

        before_each(function()
            Chat = ns.Api.Chat
            Encounter = ns.Api.Encounter
            Timer = ns.Api.Timer
            -- Center moves print the edge-resolve pair; these examples don't assert it.
            ns.Util.Print = function() end
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForEncounter()
        end)

        it("ignores messages when capture is off", function()
            Chat.FireRaidLeader("alpha")
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
            assert.is_false(Sszorak:IsCapturingRaidLeaderMessages())
        end)

        it("stores the first three messages during the fight as opaque values", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            local secretA, secretB, secretC = { id = "a" }, { id = "b" }, { id = "c" }
            Chat.FireRaidLeader(secretA)
            Chat.FireRaidLeader(secretB)
            Chat.FireRaidLeader(secretC)
            Chat.FireRaidLeader({ id = "d" })
            local saved = Sszorak:GetRaidLeaderMessages()
            assert.equals(3, #saved)
            assert.is_true(saved[1] == secretA and saved[2] == secretB and saved[3] == secretC)
        end)

        it("clears saved messages when dots return home and accepts a new batch", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("one")
            Chat.FireRaidLeader("two")
            Timer.Advance(HomeReturnTime(1))
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
            Chat.FireRaidLeader("fresh")
            assert.equals(1, #Sszorak:GetRaidLeaderMessages())
            assert.equals("fresh", Sszorak:GetRaidLeaderMessages()[1])
        end)

        it("clears saved messages when the fight ends and stops capture", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(Sszorak:IsCapturingRaidLeaderMessages())
            Chat.FireRaidLeader("one")
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
            assert.is_false(Sszorak:IsCapturingRaidLeaderMessages())
            Chat.FireRaidLeader("late")
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
        end)

        it("captures during map test and clears on home using the fast timeline", function()
            Sszorak:StartMapTest()
            assert.is_true(Sszorak:IsCapturingRaidLeaderMessages())
            Chat.FireRaidLeader("one")
            assert.equals(1, #Sszorak:GetRaidLeaderMessages())
            Timer.Advance(HomeReturnTime(1) / Sszorak.ANIM_PREVIEW_RATE)
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
            Chat.FireRaidLeader("two")
            assert.equals(1, #Sszorak:GetRaidLeaderMessages())
        end)

        it("stops capture when map test ends", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("one")
            Sszorak:EndMapTest()
            assert.is_false(Sszorak:IsCapturingRaidLeaderMessages())
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
            Chat.FireRaidLeader("late")
            assert.equals(0, #Sszorak:GetRaidLeaderMessages())
        end)

        it("shows the 1st message on left-to-center and the 3rd on right-to-center during map test", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("first")
            Chat.FireRaidLeader("second")
            Chat.FireRaidLeader("third")
            local rate = Sszorak.ANIM_PREVIEW_RATE
            local timeline = Sszorak.ACTIVE_SCHEDULE.positionTimeline

            Timer.Advance(timeline[1].time / rate)
            assert.equals("first", Sszorak:GetDisplayedCallout())
            Timer.Advance((timeline[2].time - timeline[1].time) / rate)
            assert.equals("first", Sszorak:GetDisplayedCallout())
            Timer.Advance((timeline[3].time - timeline[2].time) / rate)
            assert.equals("third", Sszorak:GetDisplayedCallout())
            Timer.Advance(Sszorak.CALLOUT_DURATION_TEST)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)
    end)

    describe("encounter warnings", function()
        local Chat
        local Encounter
        local Timer

        local function FireValidWarning()
            Encounter.FireWarning({
                severity = Sszorak.WARNING_SEVERITY,
                duration = Sszorak.WARNING_DURATION,
            })
        end

        before_each(function()
            Chat = ns.Api.Chat
            Encounter = ns.Api.Encounter
            Timer = ns.Api.Timer
            -- Center moves print the edge-resolve pair; these examples assert the warning HUD only.
            ns.Util.Print = function() end
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForEncounter()
        end)

        it("shows the group-index message for the closest matching anchor", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Chat.FireRaidLeader("second")
            Chat.FireRaidLeader("third")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[2])
            FireValidWarning()
            assert.equals("second", Sszorak:GetDisplayedCallout())
        end)

        it("shows the exit callout for the 4th warning in each anchor group", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[4])
            FireValidWarning()
            assert.equals(ns.L.SSZORAK_EXIT, Sszorak:GetDisplayedCallout())
            assert.equals(Sszorak.EXIT_EDGE, Sszorak:GetDisplayedCalloutResolve().targetEdge)

            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[8] - Sszorak.ACTIVE_SCHEDULE.warningAnchors[4])
            FireValidWarning()
            assert.equals(ns.L.SSZORAK_EXIT, Sszorak:GetDisplayedCallout())
        end)

        it("expands raid-target chat tags to texture escapes for display", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("{rt1}")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1])
            FireValidWarning()
            assert.equals("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t", Sszorak:GetDisplayedCallout())
        end)

        it("shows nothing when that group slot has no saved message", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[3])
            FireValidWarning()
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)
    end)
end)
