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

        it("does not show test callouts during a real encounter", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Chat.FireRaidLeader("second")
            Chat.FireRaidLeader("third")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
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

        it("ignores warnings outside the boss fight", function()
            FireValidWarning()
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)

        it("ignores warnings that fail severity or duration checks", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("one")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1])
            Encounter.FireWarning({ severity = 1, duration = Sszorak.WARNING_DURATION })
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            Encounter.FireWarning({
                severity = Sszorak.WARNING_SEVERITY,
                duration = Sszorak.WARNING_DURATION + Sszorak.WARNING_DURATION_TOLERANCE + 0.01,
            })
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)

        it("ignores warnings outside every anchor window", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("one")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1] + Sszorak.WARNING_TIME_WINDOW + 0.01)
            FireValidWarning()
            assert.equals(nil, Sszorak:GetDisplayedCallout())
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

        it("matches the closest of two nearby anchors", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Chat.FireRaidLeader("second")
            Timer.Advance(33)
            FireValidWarning()
            assert.equals("first", Sszorak:GetDisplayedCallout())
        end)

        it("accepts duration within tolerance and clears after the encounter callout duration", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1])
            Encounter.FireWarning({
                severity = Sszorak.WARNING_SEVERITY,
                duration = Sszorak.WARNING_DURATION - 0.05,
            })
            assert.equals("first", Sszorak:GetDisplayedCallout())
            Timer.Advance(Sszorak.CALLOUT_DURATION_ENCOUNTER - 0.001)
            assert.equals("first", Sszorak:GetDisplayedCallout())
            Timer.Advance(0.001)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)

        it("clears the displayed callout when the fight ends", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("first")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1])
            FireValidWarning()
            assert.equals("first", Sszorak:GetDisplayedCallout())
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)

        it("skips the HUD when ShowResolvedCallout gets nil", function()
            Sszorak.ShowResolvedCallout(nil, Sszorak.CALLOUT_DURATION_ENCOUNTER, true)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            assert.equals(nil, Sszorak:GetDisplayedCalloutResolve())
        end)
    end)

    describe("center edge resolves", function()
        local Chat
        local Encounter
        local Timer
        local printed

        local function PairLine(firstIndex, first, second)
            return string.format(ns.L.SSZORAK_HUD_PAIR, firstIndex, first, firstIndex + 1, second)
        end

        local function AdvanceTo(time)
            Timer.Advance(time / Sszorak.ANIM_PREVIEW_RATE)
        end

        before_each(function()
            Chat = ns.Api.Chat
            Encounter = ns.Api.Encounter
            Timer = ns.Api.Timer
            printed = {}
            ns.Util.Print = function(message)
                table.insert(printed, message)
            end
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForEncounter()
        end)

        it("saves and prints anchors 1 and 2 when test dots move home to center", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("{rt1}")
            Chat.FireRaidLeader("{rt2}")
            Chat.FireRaidLeader("third")
            local icon1 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
            local icon2 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t"
            AdvanceTo(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            assert.same({ PairLine(1, icon1, icon2) }, printed)
            assert.equals(icon1, Sszorak:GetDisplayedCallout())
            assert.equals(icon1, Sszorak:GetSavedEdgeResolve(1).hudMessage)
            assert.equals(icon2, Sszorak:GetSavedEdgeResolve(2).hudMessage)
            assert.is_nil(Sszorak:GetSavedEdgeResolve(3))
        end)

        it("saves and prints anchors 3 and 4 when test dots move far to center", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("{rt1}")
            Chat.FireRaidLeader("{rt2}")
            Chat.FireRaidLeader("third")
            local timeline = Sszorak.ACTIVE_SCHEDULE.positionTimeline
            local icon1 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
            local icon2 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t"
            AdvanceTo(timeline[2].time)
            assert.same({ PairLine(1, icon1, icon2) }, printed)
            AdvanceTo(timeline[3].time - timeline[2].time)
            assert.same({
                PairLine(1, icon1, icon2),
                PairLine(3, "third", ns.L.SSZORAK_EXIT),
            }, printed)
            assert.equals("third", Sszorak:GetDisplayedCallout())
            assert.equals("third", Sszorak:GetSavedEdgeResolve(3).hudMessage)
            assert.equals(ns.L.SSZORAK_EXIT, Sszorak:GetSavedEdgeResolve(4).hudMessage)
            assert.equals(Sszorak.EXIT_EDGE, Sszorak:GetSavedEdgeResolve(4).targetEdge)
            AdvanceTo(timeline[4].time - timeline[3].time)
            assert.equals(2, #printed)
        end)

        it("queries anchors 1 and 2 again on the next home-to-center move", function()
            local seen = {}
            Sszorak.RegisterCalloutMode({
                id = "edgeresolve",
                capturing = false,
                GetEdgeMacroBody = function()
                    return "/x"
                end,
                Listen = function()
                    return function() end
                end,
                BeginCapture = function(self)
                    self.capturing = true
                end,
                IsCapturing = function(self)
                    return self.capturing
                end,
                OnViscousCystWarning = function(_, anchorIndex)
                    table.insert(seen, anchorIndex)
                    return { hudMessage = "m" .. anchorIndex, targetEdge = anchorIndex }
                end,
            })
            Sszorak:SetCalloutMode("edgeresolve")
            Sszorak:StartMapTest()
            local timeline = Sszorak.ACTIVE_SCHEDULE.positionTimeline
            AdvanceTo(timeline[1].time)
            assert.same({ 1, 2 }, seen)
            assert.same({ PairLine(1, "m1", "m2") }, printed)
            assert.equals(1, Sszorak:GetSavedEdgeResolve(1).targetEdge)
            AdvanceTo(timeline[3].time - timeline[1].time)
            assert.same({ 1, 2, 3, 4 }, seen)
            seen = {}
            printed = {}
            AdvanceTo(timeline[5].time - timeline[3].time)
            assert.same({ 1, 2 }, seen)
            assert.same({ PairLine(1, "m1", "m2") }, printed)
        end)

        it("saves and prints the same pairs during a pull without the test HUD", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("{rt1}")
            Chat.FireRaidLeader("second")
            local timeline = Sszorak.ACTIVE_SCHEDULE.positionTimeline
            local icon1 = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
            Timer.Advance(timeline[1].time)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            assert.same({ PairLine(1, icon1, "second") }, printed)
            assert.equals(icon1, Sszorak:GetSavedEdgeResolve(1).hudMessage)
            assert.equals("second", Sszorak:GetSavedEdgeResolve(2).hudMessage)
            Timer.Advance(timeline[3].time - timeline[1].time)
            assert.same({
                PairLine(1, icon1, "second"),
                PairLine(3, ns.L.SSZORAK_HUD_EMPTY, ns.L.SSZORAK_EXIT),
            }, printed)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            assert.equals(Sszorak.EXIT_EDGE, Sszorak:GetSavedEdgeResolve(4).targetEdge)
        end)

        it("does not print when the timeline is not capturing", function()
            Sszorak:StartMapAnimation()
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            assert.same({}, printed)
            assert.is_nil(Sszorak:GetSavedEdgeResolve(1))
        end)

        it("drops saved resolves when the test ends and does not print the snap home", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("one")
            Chat.FireRaidLeader("two")
            AdvanceTo(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            assert.equals(1, #printed)
            assert.equals("one", Sszorak:GetSavedEdgeResolve(1).hudMessage)
            Sszorak:EndMapTest()
            assert.equals(1, #printed)
            assert.is_nil(Sszorak:GetSavedEdgeResolve(1))
        end)
    end)
end)
