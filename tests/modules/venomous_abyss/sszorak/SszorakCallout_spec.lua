local Loader = require("helpers.loader")

describe("SszorakCallout", function()
    local ns, Sszorak

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Sszorak = ns.Modules.Get("Sszorak")
    end)

    describe("callout mode", function()
        local function RegisterTestJailbreak(resolveFn)
            Sszorak.RegisterCalloutMode({
                id = Sszorak.CALLOUT_MODE_JAILBREAK,
                Resolve = resolveFn or function(_self, savedMessage, _context)
                    return { hudMessage = savedMessage }
                end,
                GetEdgeMacroBody = function(_self, _edge, _assignment)
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return Sszorak.SubscribeSharedCalloutListeners()
                end,
                OnMatchedWarning = function() end,
            })
        end

        it("defaults to normal", function()
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetActiveCalloutMode().id)
        end)

        it("leaves jailbreak unavailable under the public stub", function()
            assert.is_false(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_NORMAL))
            assert.is_false(pcall(Sszorak.SetCalloutMode, Sszorak, Sszorak.CALLOUT_MODE_JAILBREAK))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("resets a saved jailbreak mode when jailbreak is not registered", function()
            ns = Loader.Load()
            local saved = ns.Database.Load({
                modules = { Sszorak = { calloutMode = "jailbreak" } },
            })
            ns.Modules.Start(saved)
            Sszorak = ns.Modules.Get("Sszorak")
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak.db.calloutMode)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("switches between normal and jailbreak when jailbreak is registered", function()
            RegisterTestJailbreak()
            assert.is_true(Sszorak.IsCalloutModeAvailable(Sszorak.CALLOUT_MODE_JAILBREAK))
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetCalloutMode())
            assert.equals(Sszorak.CALLOUT_MODE_JAILBREAK, Sszorak:GetActiveCalloutMode().id)
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_NORMAL)
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("normal mode expands icon tags the same as live display", function()
            local resolve = Sszorak:GetActiveCalloutMode():Resolve("{rt1}", nil)
            assert.equals(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t",
                resolve.hudMessage
            )
            assert.equals(nil, resolve.targetEdge)
        end)

        it("rejects unknown modes", function()
            assert.is_false(pcall(Sszorak.SetCalloutMode, Sszorak, "banana"))
            assert.equals(Sszorak.CALLOUT_MODE_NORMAL, Sszorak:GetCalloutMode())
        end)

        it("requires Listen and OnMatchedWarning on registered modes", function()
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                Resolve = function()
                    return { hudMessage = "x" }
                end,
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
            }))
            assert.is_false(pcall(Sszorak.RegisterCalloutMode, {
                id = "broken",
                Resolve = function()
                    return { hudMessage = "x" }
                end,
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

        it("skips the HUD when Resolve returns nil", function()
            Sszorak.RegisterCalloutMode({
                id = Sszorak.CALLOUT_MODE_JAILBREAK,
                Resolve = function()
                    return nil
                end,
                GetEdgeMacroBody = function()
                    return "/raid {rt1}"
                end,
                Listen = function()
                    return Sszorak.SubscribeSharedCalloutListeners()
                end,
                OnMatchedWarning = function(self)
                    Sszorak.ShowResolvedCallout(self:Resolve("{rt1}", nil), Sszorak.CALLOUT_DURATION_ENCOUNTER, true)
                end,
            })
            Sszorak:SetCalloutMode(Sszorak.CALLOUT_MODE_JAILBREAK)
            Encounter.FireStart(Sszorak.ENCOUNTER_ID, "Sszorak", 16, 20)
            Timer.Advance(Sszorak.ACTIVE_SCHEDULE.warningAnchors[1])
            Encounter.FireWarning({
                severity = Sszorak.WARNING_SEVERITY,
                duration = Sszorak.WARNING_DURATION,
            })
            assert.equals(nil, Sszorak:GetDisplayedCallout())
            assert.equals(nil, Sszorak:GetDisplayedCalloutResolve())
        end)
    end)
end)
