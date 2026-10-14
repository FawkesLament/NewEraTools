local Loader = require("helpers.loader")

describe("SszorakCallout", function()
    local ns, Sszorak

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Sszorak = ns.Modules.Get("Sszorak")
    end)

    describe("callout mode", function()
        it("defaults to normal", function()
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("registers jailbreak alongside normal", function()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
        end)

        it("preserves a saved jailbreak mode", function()
            ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak.db.calloutMode)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
        end)

        it("switches between normal and jailbreak", function()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetActiveCalloutMode().id)
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_NORMAL)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("subscribes jailbreak listeners for raid target, raid warning, raid leader, and encounter warning", function()
            local Chat = ns.Api.Chat
            local Encounter = ns.Api.Encounter
            local RaidTarget = ns.Api.RaidTarget
            Sszorak:ListenForCalloutMode()
            assert.equals(1, #Chat.raidLeaderCallbacks)
            assert.equals(0, #Chat.raidWarningCallbacks)
            assert.equals(0, #RaidTarget.changedCallbacks)
            assert.equals(1, #Encounter.warningCallbacks)

            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(1, #Chat.raidLeaderCallbacks)
            assert.equals(1, #Chat.raidWarningCallbacks)
            assert.equals(1, #RaidTarget.changedCallbacks)
            assert.equals(1, #Encounter.warningCallbacks)

            -- Stub handlers must accept fires without error.
            RaidTarget.FireChanged()
            Chat.FireRaidWarning("warn")
            Chat.FireRaidLeader("leader")

            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_NORMAL)
            assert.equals(1, #Chat.raidLeaderCallbacks)
            assert.equals(0, #Chat.raidWarningCallbacks)
            assert.equals(0, #RaidTarget.changedCallbacks)
            assert.equals(1, #Encounter.warningCallbacks)
        end)

        it("rejects unknown modes", function()
            assert.is_false(pcall(Sszorak.SetCalloutMode, Sszorak, "banana"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("requires Listen and OnMatchedWarning on registered modes", function()
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
            }))
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return function() end
                end,
            }))
        end)
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
            assert.equals(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t",
                Sszorak:GetDisplayedCallout()
            )
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

        it("saves and restores callout position", function()
            Sszorak:SetCalloutPosition({ point = "TOP", relativePoint = "CENTER", x = 12, y = -40 })
            assert.same(
                { point = "TOP", relativePoint = "CENTER", x = 12, y = -40 },
                Sszorak:GetCalloutPosition()
            )
        end)

        it("skips the HUD when ShowResolvedCallout gets nil", function()
            Sszorak.ShowResolvedCallout(nil, Sszorak.CALLOUT_DURATION_ENCOUNTER, true)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            assert.equals(nil, Sszorak:GetDisplayedCalloutResolve())
        end)
    end)

    describe("jailbreak events", function()
        local Chat
        local Encounter
        local RaidTarget
        local Timer

        before_each(function()
            Chat = ns.Api.Chat
            Encounter = ns.Api.Encounter
            RaidTarget = ns.Api.RaidTarget
            Timer = ns.Api.Timer
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            Sszorak:ListenForCalloutMode()
            Sszorak:ListenForEncounter()
        end)

        it("ignores events when capture is off", function()
            Chat.FireRaidLeader("a")
            Chat.FireRaidWarning("b")
            RaidTarget.FireChanged()
            assert.equals(0, #Sszorak:GetJailbreakEvents())
            assert.is_false(Sszorak:IsCapturingJailbreakEvents())
        end)

        it("records raid leader, raid warning, and raid target events during the fight", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            assert.is_true(Sszorak:IsCapturingJailbreakEvents())
            Chat.FireRaidLeader("leader")
            Chat.FireRaidWarning("warn")
            RaidTarget.FireChanged()
            local saved = Sszorak:GetJailbreakEvents()
            assert.equals(3, #saved)
            assert.equals(Sszorak.JAILBREAK_EVENT_RAID_LEADER, saved[1].type)
            assert.equals(Sszorak.JAILBREAK_EVENT_RAID_WARNING, saved[2].type)
            assert.equals(Sszorak.JAILBREAK_EVENT_RAID_TARGET, saved[3].type)
        end)

        it("clears events when the fight ends", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("one")
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            assert.equals(0, #Sszorak:GetJailbreakEvents())
            assert.is_false(Sszorak:IsCapturingJailbreakEvents())
            Chat.FireRaidLeader("late")
            assert.equals(0, #Sszorak:GetJailbreakEvents())
        end)

        local function HomeReturnTime(index)
            local count = 0
            for _, entry in ipairs(Sszorak.ACTIVE_SCHEDULE.positionTimeline) do
                if entry.station == Sszorak.STATION_HOME then
                    count = count + 1
                    if count == index then
                        return entry.time
                    end
                end
            end
        end

        local function Gap()
            Timer.Advance(Sszorak.JAILBREAK_EVENT_GROUP_WINDOW + 0.01)
        end

        local function FireRaidTargets(count)
            for _ = 1, count do
                RaidTarget.FireChanged()
            end
        end

        ---Warning anchor 1 selects event group 1 (both 1-based).
        local function ResolveFirstGroup()
            return Sszorak:GetActiveCalloutMode():OnMatchedWarning(1)
        end

        ---Expected jailbreak HUD: marker icon plus relative position vs group and station.
        ---@param edge integer
        ---@param anchorIndex integer|nil  Defaults to 1 (entrance side); near/far flip on slots 3–4.
        local function ExpectedHud(edge, anchorIndex)
            local marker = Sszorak:GetEdgeMarker(edge)
            local raidTarget = Sszorak.MARKER_RAID_TARGET[marker]
            local icon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. raidTarget .. ":0|t"
            local entranceDepth = {
                [2] = "near",
                [3] = "mid",
                [4] = "far",
                [6] = "far",
                [7] = "mid",
                [8] = "near",
            }
            local depthLocale = {
                near = ns.L.SSZORAK_DEPTH_NEAR,
                mid = ns.L.SSZORAK_DEPTH_MID,
                far = ns.L.SSZORAK_DEPTH_FAR,
            }
            local groupByEdge = {
                [2] = "B",
                [3] = "B",
                [4] = "B",
                [6] = "A",
                [7] = "A",
                [8] = "A",
            }
            local slot = (((anchorIndex or 1) - 1) % Sszorak.WARNING_ANCHOR_GROUP_SIZE) + 1
            local depthKey = entranceDepth[edge]
            if depthKey ~= "mid" and slot > 2 then
                depthKey = depthKey == "near" and "far" or "near"
            end
            local side = groupByEdge[edge] == Sszorak:GetPlayerGroup() and ns.L.SSZORAK_SIDE_SAME
                or ns.L.SSZORAK_SIDE_OPPOSITE
            local relative = string.format(ns.L.SSZORAK_RELATIVE_POSITION, side, depthLocale[depthKey])
            return icon .. " " .. relative
        end

        it("resets the event log when dots return home during a fight", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("one")
            assert.equals(1, #Sszorak:GetJailbreakEvents())
            Timer.Advance(HomeReturnTime(1))
            assert.equals(0, #Sszorak:GetJailbreakEvents())
            assert.is_true(Sszorak:IsCapturingJailbreakEvents())
            Chat.FireRaidWarning("fresh")
            assert.equals(1, #Sszorak:GetJailbreakEvents())
            assert.equals(Sszorak.JAILBREAK_EVENT_RAID_WARNING, Sszorak:GetJailbreakEvents()[1].type)
        end)

        it("resets the event log when dots return home during map test", function()
            Sszorak:StartMapTest()
            Chat.FireRaidLeader("one")
            assert.equals(1, #Sszorak:GetJailbreakEvents())
            Timer.Advance(HomeReturnTime(1) / Sszorak.ANIM_PREVIEW_RATE)
            assert.equals(0, #Sszorak:GetJailbreakEvents())
            assert.is_true(Sszorak:IsCapturingJailbreakEvents())
            Chat.FireRaidWarning("fresh")
            assert.equals(1, #Sszorak:GetJailbreakEvents())
            Sszorak:EndMapTest()
            assert.equals(0, #Sszorak:GetJailbreakEvents())
            assert.is_false(Sszorak:IsCapturingJailbreakEvents())
        end)

        it("shows the 1st and 3rd event groups on center moves during map test", function()
            Sszorak:StartMapTest()
            -- Group indices 1 and 3 (same slots as Normal's saved messages).
            Chat.FireRaidLeader("g1") -- edge 6
            Gap()
            Chat.FireRaidWarning("g2") -- edge 2
            Gap()
            Chat.FireRaidWarning("g3")
            FireRaidTargets(3) -- edge 3

            local rate = Sszorak.ANIM_PREVIEW_RATE
            local timeline = Sszorak.ACTIVE_SCHEDULE.positionTimeline
            Timer.Advance(timeline[1].time / rate)
            assert.equals(ExpectedHud(6, 1), Sszorak:GetDisplayedCallout())
            assert.equals(6, Sszorak:GetDisplayedCalloutResolve().targetEdge)
            Timer.Advance((timeline[2].time - timeline[1].time) / rate)
            assert.equals(ExpectedHud(6, 1), Sszorak:GetDisplayedCallout())
            Timer.Advance((timeline[3].time - timeline[2].time) / rate)
            assert.equals(ExpectedHud(3, 3), Sszorak:GetDisplayedCallout())
            assert.equals(3, Sszorak:GetDisplayedCalloutResolve().targetEdge)
        end)

        it("maps a single clicked edge's opposite on the first center move in map test", function()
            Sszorak:StartMapTest()
            -- Clicking edge 2's macro encodes opposite edge 6 (`/raid .`).
            Chat.FireRaidLeader("from-edge-2-macro")
            local rate = Sszorak.ANIM_PREVIEW_RATE
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time / rate)
            assert.equals(6, Sszorak:GetDisplayedCalloutResolve().targetEdge)
        end)

        it("does not show jailbreak test callouts during a real encounter", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidLeader("g1")
            Gap()
            Chat.FireRaidWarning("g2")
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.positionTimeline[1].time)
            assert.equals(nil, Sszorak:GetDisplayedCallout())
        end)

        it("partitions events within the group window into the same group", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            local step = Sszorak.JAILBREAK_EVENT_GROUP_WINDOW / 3
            Chat.FireRaidLeader("a")
            Timer.Advance(step)
            Chat.FireRaidWarning("b")
            Timer.Advance(step)
            RaidTarget.FireChanged()
            Gap()
            Chat.FireRaidLeader("c")
            local groups = Sszorak:GetJailbreakEventGroups()
            assert.equals(2, #groups)
            assert.equals(3, #groups[1])
            assert.equals(1, #groups[2])
            assert.equals(Sszorak.JAILBREAK_EVENT_RAID_LEADER, groups[2][1].type)
        end)

        it("maps event-count triples to markable edges", function()
            local cases = {
                { edge = 2, warning = 1, leader = 0, targets = 0 },
                { edge = 3, warning = 1, leader = 0, targets = 3 },
                { edge = 4, warning = 1, leader = 0, targets = 5 },
                { edge = 6, warning = 0, leader = 1, targets = 0 },
                { edge = 7, warning = 0, leader = 1, targets = 4 },
                { edge = 8, warning = 0, leader = 1, targets = 6 },
            }
            for _, case in ipairs(cases) do
                Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
                for _ = 1, case.warning do
                    Chat.FireRaidWarning("w")
                end
                for _ = 1, case.leader do
                    Chat.FireRaidLeader("l")
                end
                FireRaidTargets(case.targets)
                local resolve = ResolveFirstGroup()
                assert.equals(case.edge, resolve.targetEdge, "edge for case " .. case.edge)
                assert.equals(ExpectedHud(case.edge), resolve.hudMessage)
                Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)
            end
        end)

        it("labels markable edges relative to the player's group", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("w") -- edge 2: opposite near for group A (−Y)
            local resolveA = ResolveFirstGroup()
            assert.equals(2, resolveA.targetEdge)
            assert.equals(ExpectedHud(2, 1), resolveA.hudMessage)
            assert.is_true(resolveA.hudMessage:find(ns.L.SSZORAK_SIDE_OPPOSITE, 1, true) ~= nil)
            assert.is_true(resolveA.hudMessage:find(ns.L.SSZORAK_DEPTH_NEAR, 1, true) ~= nil)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)

            Sszorak:SetMapRotated(true) -- group B (+Y)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("w") -- edge 2: same-side near for group B
            local resolveB = ResolveFirstGroup()
            assert.equals(2, resolveB.targetEdge)
            assert.equals(ExpectedHud(2, 1), resolveB.hudMessage)
            assert.is_true(resolveB.hudMessage:find(ns.L.SSZORAK_SIDE_SAME, 1, true) ~= nil)
            assert.is_true(resolveB.hudMessage:find(ns.L.SSZORAK_DEPTH_NEAR, 1, true) ~= nil)
        end)

        it("flips near/far when the warning anchor is on the exit side", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("g1") -- edge 2
            Gap()
            Chat.FireRaidLeader("g2") -- edge 6
            Gap()
            Chat.FireRaidWarning("g3") -- edge 2 again
            local mode = Sszorak:GetActiveCalloutMode()
            local entrance = mode:OnMatchedWarning(1)
            local exitSide = mode:OnMatchedWarning(3)
            assert.equals(2, entrance.targetEdge)
            assert.equals(2, exitSide.targetEdge)
            assert.equals(ExpectedHud(2, 1), entrance.hudMessage)
            assert.equals(ExpectedHud(2, 3), exitSide.hudMessage)
            assert.is_true(entrance.hudMessage:find(ns.L.SSZORAK_DEPTH_NEAR, 1, true) ~= nil)
            assert.is_true(exitSide.hudMessage:find(ns.L.SSZORAK_DEPTH_FAR, 1, true) ~= nil)
        end)

        it("uses ceil(raid targets / 2) for the c count", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("w")
            FireRaidTargets(4) -- c = ceil(4/2) = 2 → edge 3
            assert.equals(3, ResolveFirstGroup().targetEdge)
            Encounter.FireEnd(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20, 1)

            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("w")
            FireRaidTargets(3) -- c = ceil(3/2) = 2 → edge 3
            assert.equals(3, ResolveFirstGroup().targetEdge)
        end)

        it("returns nil for unmapped count triples", function()
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Chat.FireRaidWarning("w")
            Chat.FireRaidLeader("l")
            assert.equals(nil, ResolveFirstGroup())
        end)

        it("resolves multiples of 4 to the exit edge", function()
            local mode = Sszorak:GetActiveCalloutMode()
            for _, anchorIndex in ipairs({ 4, 8, 12 }) do
                local resolve = mode:OnMatchedWarning(anchorIndex)
                assert.equals(ns.L.SSZORAK_EXIT, resolve.hudMessage)
                assert.equals(Sszorak.EXIT_EDGE, resolve.targetEdge)
            end
        end)
    end)
end)
