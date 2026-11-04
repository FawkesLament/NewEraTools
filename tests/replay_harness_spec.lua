local Loader = require("helpers.loader")
local Replay = require("helpers.replay")

local function CopyList(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function Packed(...)
    return { n = select("#", ...), ... }
end

local function AssertPacked(expected, actual)
    assert.equals(expected.n, actual.n)
    for i = 1, expected.n do
        assert.equals(expected[i], actual[i])
    end
end

describe("Replay harness", function()
    local runners

    local function New(mount)
        local runner = Replay.new({ mount = mount })
        runners[#runners + 1] = runner
        return runner
    end

    before_each(function()
        runners = {}
    end)

    after_each(function()
        for i = 1, #runners do
            pcall(function()
                runners[i]:close()
            end)
        end
    end)

    describe("event order", function()
        it("delivers multiple events in one frame in arrival order", function()
            local received = {}
            local runner = New(function(env)
                env.events:on("ALPHA", function(eventName, value)
                    received[#received + 1] = { eventName, value }
                end)
                env.events:on("BETA", function(eventName, value)
                    received[#received + 1] = { eventName, value }
                end)
                env.events:on("ALPHA", function(eventName, value)
                    received[#received + 1] = { "second", eventName, value }
                end)
                return {
                    snapshot = function()
                        return CopyList(received)
                    end,
                }
            end)

            runner:beginFrame(1, 10)
            runner:emit("ALPHA", 1)
            runner:emit("BETA", 2)
            runner:emit("ALPHA", 3)
            runner:endFrame()

            assert.same({
                { "ALPHA", 1 },
                { "second", "ALPHA", 1 },
                { "BETA", 2 },
                { "ALPHA", 3 },
                { "second", "ALPHA", 3 },
            }, runner:snapshot())
        end)
    end)

    describe("nil payload preservation", function()
        it("preserves leading, middle, and trailing nils and PRESENT placeholders", function()
            local received = {}
            local runner = New(function(env)
                env.events:on("PAYLOAD", function(eventName, ...)
                    received[#received + 1] = Packed(eventName, ...)
                end)
                return {
                    snapshot = function()
                        return received
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:emit("PAYLOAD", nil, "mid", nil)
            runner:emit("PAYLOAD", Replay.PRESENT)
            runner:emit("PAYLOAD", "tail", nil)
            runner:endFrame()

            AssertPacked(Packed("PAYLOAD", nil, "mid", nil), received[1])
            AssertPacked(Packed("PAYLOAD", Replay.PRESENT), received[2])
            AssertPacked(Packed("PAYLOAD", "tail", nil), received[3])
            assert.equals(Replay.PRESENT, received[2][2])

            local fixtureRunner = New(function(env)
                local captured = {}
                env.events:on("PAYLOAD", function(eventName, ...)
                    captured[#captured + 1] = Packed(eventName, ...)
                end)
                return {
                    snapshot = function()
                        return captured
                    end,
                }
            end)

            fixtureRunner:stepFrame({
                id = 2,
                time = 2,
                steps = {
                    {
                        op = "event",
                        name = "PAYLOAD",
                        args = Replay.args(nil, Replay.PRESENT, nil),
                    },
                },
            })
            AssertPacked(Packed("PAYLOAD", nil, Replay.PRESENT, nil), fixtureRunner:snapshot()[1])
        end)
    end)

    describe("frame boundary", function()
        it("runs deferred work only when the frame ends", function()
            local log = {}
            local runner = New(function(env)
                env.events:on("HIT", function()
                    log[#log + 1] = "event"
                    env:defer(function()
                        log[#log + 1] = "deferred"
                        log[#log + 1] = env.api.GetTime()
                    end)
                end)
                return {
                    snapshot = function()
                        return CopyList(log)
                    end,
                }
            end)

            runner:beginFrame(40, 12.5)
            runner:emit("HIT")
            runner:emit("HIT")
            assert.same({ "event", "event" }, runner:snapshot())
            runner:endFrame()
            assert.same({ "event", "event", "deferred", 12.5, "deferred", 12.5 }, runner:snapshot())
        end)
    end)

    describe("nested deferral", function()
        it("runs callbacks scheduled during a flush on the next frame boundary", function()
            local log = {}
            local runner = New(function(env)
                env.events:on("GO", function()
                    env:defer(function()
                        log[#log + 1] = "first"
                        env:defer(function()
                            log[#log + 1] = "second"
                        end)
                    end)
                end)
                return {
                    snapshot = function()
                        return CopyList(log)
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:emit("GO")
            runner:endFrame()
            assert.same({ "first" }, runner:snapshot())

            runner:beginFrame(2, 2)
            runner:endFrame()
            assert.same({ "first", "second" }, runner:snapshot())
        end)
    end)

    describe("world updates between events", function()
        it("exposes the mock world at the moment each handler queries it", function()
            local observed = { n = 0 }
            local runner = New(function(env)
                env.events:on("CHECK", function()
                    observed.n = observed.n + 1
                    observed[observed.n] = env.api.GetRaidTargetIndex("boss3")
                end)
                return {
                    snapshot = function()
                        local copy = { n = observed.n }
                        for i = 1, observed.n do
                            copy[i] = observed[i]
                        end
                        return copy
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:setUnit("boss3", { exists = true, markerPresent = false })
            runner:emit("CHECK")
            runner:setUnit("boss3", { markerPresent = true })
            runner:emit("CHECK")
            runner:endFrame()

            local snapshot = runner:snapshot()
            assert.equals(2, snapshot.n)
            assert.is_nil(snapshot[1])
            assert.equals(Replay.PRESENT, snapshot[2])
        end)
    end)

    describe("world state at flush", function()
        it("lets end-of-frame callbacks see world updates made after the event", function()
            local observed
            local runner = New(function(env)
                env.events:on("PROBE", function()
                    env:defer(function()
                        observed = env.api.UnitExists("boss3")
                    end)
                end)
                return {
                    snapshot = function()
                        return { exists = observed }
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:setUnit("boss3", { exists = true, level = 92 })
            runner:emit("PROBE")
            runner:setUnit("boss3", { exists = false })
            runner:endFrame()

            assert.is_false(runner:snapshot().exists)
        end)
    end)

    describe("event unregistration", function()
        it("does not invoke an unsubscribed callback", function()
            local hits = 0
            local unsubscribe
            local runner = New(function(env)
                unsubscribe = env.events:on("TICK", function()
                    hits = hits + 1
                end)
                return {
                    snapshot = function()
                        return { hits = hits }
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:emit("TICK")
            unsubscribe()
            runner:emit("TICK")
            runner:endFrame()

            assert.equals(1, runner:snapshot().hits)
        end)
    end)

    describe("deterministic replay", function()
        it("produces identical snapshots from two fresh runners of the same fixture", function()
            local function Mount(env)
                local log = {}
                env.events:on("PING", function(_, unit)
                    log[#log + 1] = {
                        unit = unit,
                        exists = env.api.UnitExists(unit),
                        marker = env.api.GetRaidTargetIndex(unit) ~= nil,
                        time = env.api.GetTime(),
                    }
                end)
                return {
                    snapshot = function()
                        local copy = {}
                        for i = 1, #log do
                            local entry = log[i]
                            copy[i] = {
                                unit = entry.unit,
                                exists = entry.exists,
                                marker = entry.marker,
                                time = entry.time,
                            }
                        end
                        return { log = copy }
                    end,
                }
            end

            local fixture = {
                frames = {
                    {
                        id = 10,
                        time = 5,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { exists = true, level = 92, markerPresent = true },
                            },
                            { op = "event", name = "PING", args = Replay.args("boss3") },
                        },
                    },
                    {
                        id = 11,
                        time = 5.25,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { markerPresent = false },
                            },
                            { op = "event", name = "PING", args = Replay.args("boss3") },
                        },
                    },
                },
            }

            local first = New(Mount)
            first:run(fixture)
            local snapshotA = first:snapshot()
            first:close()

            local second = New(Mount)
            second:run(fixture)
            local snapshotB = second:snapshot()

            assert.same(snapshotA, snapshotB)
            assert.equals(5, snapshotA.log[1].time)
            assert.is_true(snapshotA.log[1].marker)
            assert.is_false(snapshotA.log[2].marker)
        end)
    end)

    describe("isolation", function()
        it("does not share units, callbacks, or queued work between runners", function()
            local logA = {}
            local logB = {}
            local envA
            local runnerA = New(function(env)
                envA = env
                env.events:on("PING", function()
                    logA[#logA + 1] = "a"
                    env:defer(function()
                        logA[#logA + 1] = "deferred-a"
                    end)
                end)
                return {
                    snapshot = function()
                        return CopyList(logA)
                    end,
                }
            end)
            local runnerB = New(function(env)
                env.events:on("PING", function()
                    logB[#logB + 1] = "b"
                end)
                return {
                    snapshot = function()
                        return CopyList(logB)
                    end,
                }
            end)

            runnerA:beginFrame(1, 1)
            runnerA:setUnit("boss3", { exists = true, level = 1 })
            runnerA:emit("PING")

            runnerB:beginFrame(1, 1)
            runnerB:setUnit("boss4", { exists = true, level = 2 })
            runnerB:emit("PING")
            runnerB:endFrame()

            assert.same({ "a" }, runnerA:snapshot())
            assert.same({ "b" }, runnerB:snapshot())

            local ok, err = pcall(function()
                envA.api.UnitExists("boss4")
            end)
            assert.is_false(ok)
            assert(tostring(err):find('unconfigured unit "boss4"', 1, true), tostring(err))
            assert.is_true(envA.api.UnitExists("boss3"))

            runnerA:endFrame()
            assert.same({ "a", "deferred-a" }, runnerA:snapshot())
            assert.same({ "b" }, runnerB:snapshot())
        end)
    end)

    describe("cleanup", function()
        it("discards callbacks and deferred work and rejects further use", function()
            local hits = 0
            local deferred = 0
            local stopped = false
            local runner = New(function(env)
                env.events:on("TICK", function()
                    hits = hits + 1
                    env:defer(function()
                        deferred = deferred + 1
                    end)
                end)
                return {
                    snapshot = function()
                        return { hits = hits, deferred = deferred }
                    end,
                    stop = function()
                        stopped = true
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:emit("TICK")
            runner:close()

            assert.is_true(stopped)
            assert.equals(1, hits)
            assert.equals(0, deferred)
            assert.is_false(pcall(function()
                runner:beginFrame(2, 2)
            end))
            assert.is_false(pcall(function()
                runner:emit("TICK")
            end))
            assert.is_false(pcall(function()
                runner:endFrame()
            end))
            assert.is_false(pcall(function()
                runner:snapshot()
            end))
            assert.is_false(pcall(function()
                runner:setUnit("boss3", { exists = true })
            end))
        end)
    end)

    describe("strict API queries", function()
        it("fails clearly when a handler queries an unconfigured unit", function()
            local runner = New(function(env)
                env.events:on("PROBE", function()
                    env.api.UnitExists("boss3")
                end)
                return {
                    snapshot = function()
                        return {}
                    end,
                }
            end)

            runner:beginFrame(2058, 48.217)
            local ok, err = pcall(function()
                runner:emit("PROBE")
            end)
            assert.is_false(ok)
            err = tostring(err)
            assert(err:find("Replay failed at frame 2058 (t=48.217)", 1, true), err)
            assert(err:find("PROBE", 1, true), err)
            assert(err:find('unconfigured unit "boss3"', 1, true), err)
        end)

        it("fails clearly when a living unit has no configured level", function()
            local runner = New(function(env)
                env.events:on("PROBE", function()
                    env.api.UnitLevel("boss3")
                end)
                return {
                    snapshot = function()
                        return {}
                    end,
                }
            end)

            runner:beginFrame(1, 1)
            runner:setUnit("boss3", { exists = true, markerPresent = false })
            local ok, err = pcall(function()
                runner:emit("PROBE")
            end)
            assert.is_false(ok)
            assert(tostring(err):find("no configured level", 1, true), tostring(err))
        end)
    end)

    describe("fixture execution", function()
        it("runs frames in order and invokes onFrame after each flush", function()
            local seen = {}
            local runner = New(function(env)
                local log = {}
                env.events:on("PING", function(_, token)
                    log[#log + 1] = token
                end)
                env.events:on("GONE", function()
                    env:defer(function()
                        log[#log + 1] = env.api.UnitExists("boss3") and "alive" or "gone"
                    end)
                end)
                return {
                    snapshot = function()
                        return CopyList(log)
                    end,
                }
            end)

            local returned = runner:run({
                frames = {
                    {
                        id = 100,
                        time = 12.5,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { exists = true, level = 92, markerPresent = false },
                            },
                            { op = "event", name = "PING", args = Replay.args("boss3") },
                        },
                    },
                    {
                        id = 150,
                        time = 13,
                        steps = {
                            { op = "remove", token = "boss3" },
                            { op = "event", name = "GONE", args = Replay.args() },
                        },
                    },
                },
            }, {
                onFrame = function(current, frame, snapshot)
                    seen[#seen + 1] = { id = frame.id, snapshot = snapshot }
                    assert.equals(runner, current)
                end,
            })

            assert.equals(runner, returned)
            assert.same({ "boss3" }, seen[1].snapshot)
            assert.same({ "boss3", "gone" }, seen[2].snapshot)
            assert.same({ "boss3", "gone" }, runner:snapshot())
        end)

        it("rejects unknown fixture operations", function()
            local runner = New(function()
                return {
                    snapshot = function()
                        return {}
                    end,
                }
            end)
            local ok, err = pcall(function()
                runner:stepFrame({
                    id = 1,
                    time = 1,
                    steps = {
                        { op = "cast", name = "nope" },
                    },
                })
            end)
            assert.is_false(ok)
            assert(tostring(err):find('unknown operation "cast"', 1, true), tostring(err))
        end)

        it("rejects a second beginFrame while a frame is open", function()
            local runner = New(function()
                return {
                    snapshot = function()
                        return {}
                    end,
                }
            end)
            runner:beginFrame(1, 1)
            local ok, err = pcall(function()
                runner:beginFrame(2, 2)
            end)
            assert.is_false(ok)
            assert(tostring(err):find("a frame is already open", 1, true), tostring(err))
        end)
    end)

    describe("example production mount", function()
        it("drives Coiled Altar interrupt tracking through a thin adapter", function()
            local function Mount(env)
                local ns = Loader.Load()
                ns.Modules.Start(ns.Database.Load(nil))
                local Tracker = ns.Modules.Internals("CoiledAltar").InterruptTracker
                local RaidTarget = ns.Api.RaidTarget
                local Unit = ns.Api.Unit

                function Unit.Exists(unit)
                    return env.api.UnitExists(unit)
                end

                function Unit.GetLevel(unit)
                    return env.api.UnitLevel(unit)
                end

                function RaidTarget.GetIndex(unit)
                    return env.api.GetRaidTargetIndex(unit)
                end

                local state = Tracker.New()
                local flushScheduled = false
                state.requestFlush = function()
                    if flushScheduled then
                        return
                    end
                    flushScheduled = true
                    env:defer(function()
                        flushScheduled = false
                        Tracker.Flush(state)
                    end)
                end

                env.events:on("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
                    Tracker.OnEngage(state)
                end)
                env.events:on("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
                    Tracker.OnCast(state, "START", unit, castGUID ~= nil, spellID ~= nil)
                end)
                env.events:on("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID, spellID)
                    Tracker.OnCast(state, "INTERRUPTED", unit, castGUID ~= nil, spellID ~= nil)
                end)

                return {
                    snapshot = function()
                        local shadows = {}
                        for i = 1, #state.list do
                            local shadow = state.list[i]
                            shadows[i] = {
                                expired = shadow.expired == true,
                                marked = shadow.marked == true,
                                kicks = shadow.kicks,
                                casting = shadow.casting == true,
                            }
                        end
                        return { count = #state.list, shadows = shadows }
                    end,
                    stop = function()
                        state.disposed = true
                        state.batch = nil
                    end,
                }
            end

            local fixture = {
                frames = {
                    {
                        id = 100,
                        time = 12.5,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { exists = true, level = 92, markerPresent = true },
                            },
                            {
                                op = "unit",
                                token = "boss4",
                                properties = { exists = true, level = 92, markerPresent = false },
                            },
                            {
                                op = "unit",
                                token = "boss5",
                                properties = { exists = false },
                            },
                            {
                                op = "event",
                                name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                                args = Replay.args(),
                            },
                        },
                    },
                    {
                        id = 110,
                        time = 13.0,
                        steps = {
                            {
                                op = "event",
                                name = "UNIT_SPELLCAST_START",
                                args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                            },
                            {
                                op = "event",
                                name = "UNIT_SPELLCAST_INTERRUPTED",
                                args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                            },
                        },
                    },
                },
            }

            local runner = New(Mount)
            runner:run(fixture, {
                onFrame = function(_, frame, state)
                    if frame.id == 100 then
                        assert.equals(2, state.count)
                        assert.is_true(state.shadows[1].marked)
                        assert.is_false(state.shadows[2].marked)
                        assert.equals(0, state.shadows[1].kicks)
                    elseif frame.id == 110 then
                        assert.equals(1, state.shadows[1].kicks)
                        assert.is_false(state.shadows[1].casting)
                    end
                end,
            })

            local finalState = runner:snapshot()
            assert.equals(2, finalState.count)
            assert.equals(1, finalState.shadows[1].kicks)
            assert.equals(0, finalState.shadows[2].kicks)
        end)
    end)
end)
