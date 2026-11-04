local Fs = require("helpers.fs")
local Loader = require("helpers.loader")
local Replay = require("helpers.replay")

local FIXTURE_DIR = "tests/modules/venomous_abyss/coiled_altar/fixtures"
local EXAMPLE_PATH = FIXTURE_DIR .. "/example_pull.lua"
local PULL_PATH_PATTERN = "^" .. FIXTURE_DIR .. "/[^/]+_pull%.lua$"
local FIRST_SHADOW_BOSS = 3
local SCHEMA_VERSION = 1

local ROOT_FIELDS = {
    schemaVersion = true,
    name = true,
    frames = true,
}
local FRAME_FIELDS = {
    id = true,
    time = true,
    steps = true,
    expect = true,
}
local EXPECT_FIELDS = {
    currentWave = true,
    currentWaveMembers = true,
    live = true,
    plateOwners = true,
    possibleWorlds = true,
}
local LIVE_FIELDS = {
    id = true,
    kicks = true,
    casting = true,
    marked = true,
    expired = true,
    plate = true,
}
local LIVE_FIELD_ORDER = { "id", "kicks", "casting", "marked", "expired", "plate" }

local function FormatValue(value)
    if value == Replay.PRESENT then
        return "PRESENT"
    elseif value == nil then
        return "nil"
    elseif type(value) == "string" then
        return string.format("%q", value)
    elseif type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = "[" .. FormatValue(key) .. "] = " .. FormatValue(item)
    end
    table.sort(parts)
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function Fail(message)
    error(message, 0)
end

local function CountKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function IsArray(value)
    if type(value) ~= "table" then
        return false
    end
    local n = #value
    return CountKeys(value) == n
end

local function ValidateLiveRecord(record, path)
    if type(record) ~= "table" then
        Fail(path .. " must be a table")
    end
    for i = 1, #LIVE_FIELD_ORDER do
        local key = LIVE_FIELD_ORDER[i]
        if record[key] == nil then
            Fail(path .. " missing field " .. key)
        end
    end
    for key in pairs(record) do
        if not LIVE_FIELDS[key] then
            Fail(path .. " unknown field " .. tostring(key))
        end
    end
end

local function ValidateExpect(expect, path)
    if type(expect) ~= "table" then
        Fail(path .. " must be a table")
    end
    if CountKeys(expect) == 0 then
        Fail(path .. " is empty; omit expect or provide at least one field")
    end
    for key in pairs(expect) do
        if not EXPECT_FIELDS[key] then
            Fail(path .. " unknown field " .. tostring(key))
        end
    end
    if expect.currentWave ~= nil and expect.currentWave ~= false and type(expect.currentWave) ~= "string" then
        Fail(path .. ".currentWave must be a string or false")
    end
    if expect.currentWaveMembers ~= nil then
        if not IsArray(expect.currentWaveMembers) then
            Fail(path .. ".currentWaveMembers must be an array")
        end
        for i = 1, #expect.currentWaveMembers do
            if type(expect.currentWaveMembers[i]) ~= "string" then
                Fail(path .. ".currentWaveMembers[" .. i .. "] must be a string")
            end
        end
    end
    if expect.live ~= nil then
        if not IsArray(expect.live) then
            Fail(path .. ".live must be an array")
        end
        for i = 1, #expect.live do
            ValidateLiveRecord(expect.live[i], path .. ".live[" .. i .. "]")
        end
    end
    if expect.plateOwners ~= nil then
        if type(expect.plateOwners) ~= "table" then
            Fail(path .. ".plateOwners must be a table")
        end
        for token, id in pairs(expect.plateOwners) do
            if type(token) ~= "string" or token == "" then
                Fail(path .. ".plateOwners keys must be nameplate tokens")
            end
            if type(id) ~= "string" or id == "" then
                Fail(path .. ".plateOwners[" .. token .. "] must be a stable object id")
            end
        end
    end
    if expect.possibleWorlds ~= nil then
        if not IsArray(expect.possibleWorlds) then
            Fail(path .. ".possibleWorlds must be an array")
        end
        for i = 1, #expect.possibleWorlds do
            local label = expect.possibleWorlds[i]
            if label ~= "W1" and label ~= "W2" then
                Fail(path .. ".possibleWorlds[" .. i .. "] must be W1 or W2")
            end
        end
    end
end

local function ValidateStep(step, path)
    if type(step) ~= "table" or type(step.op) ~= "string" then
        Fail(path .. " must be a table with an op")
    end
    if step.op == "unit" then
        if type(step.token) ~= "string" or step.token == "" then
            Fail(path .. " unit step requires a token")
        end
        if step.properties ~= nil and type(step.properties) ~= "table" then
            Fail(path .. " properties must be a table")
        end
    elseif step.op == "remove" then
        if type(step.token) ~= "string" or step.token == "" then
            Fail(path .. " remove step requires a token")
        end
    elseif step.op == "event" then
        if type(step.name) ~= "string" or step.name == "" then
            Fail(path .. " event step requires a name")
        end
        if step.args ~= nil and (type(step.args) ~= "table" or type(step.args.n) ~= "number") then
            Fail(path .. " event args must be created with Replay.args()")
        end
    else
        Fail(path .. ' unknown operation "' .. step.op .. '"')
    end
end

---@param fixture any
local function ValidateFixture(fixture)
    if type(fixture) ~= "table" then
        Fail("fixture must be a table")
    end
    for key in pairs(fixture) do
        if not ROOT_FIELDS[key] then
            Fail("fixture has unknown field " .. tostring(key))
        end
    end
    if fixture.schemaVersion ~= SCHEMA_VERSION then
        Fail("fixture schemaVersion must be " .. SCHEMA_VERSION)
    end
    if type(fixture.name) ~= "string" or fixture.name == "" then
        Fail("fixture name must be a non-empty string")
    end
    if type(fixture.frames) ~= "table" or not IsArray(fixture.frames) or #fixture.frames == 0 then
        Fail("fixture frames must be a non-empty array")
    end
    local lastId
    for i = 1, #fixture.frames do
        local frame = fixture.frames[i]
        local path = "frames[" .. i .. "]"
        if type(frame) ~= "table" then
            Fail(path .. " must be a table")
        end
        for key in pairs(frame) do
            if not FRAME_FIELDS[key] then
                Fail(path .. " unknown field " .. tostring(key))
            end
        end
        if type(frame.id) ~= "number" then
            Fail(path .. ".id must be a number")
        end
        if lastId ~= nil and not (frame.id > lastId) then
            Fail(path .. ".id must be strictly increasing")
        end
        lastId = frame.id
        if type(frame.time) ~= "number" then
            Fail(path .. ".time must be a number")
        end
        if type(frame.steps) ~= "table" or not IsArray(frame.steps) then
            Fail(path .. ".steps must be an array")
        end
        for stepIndex = 1, #frame.steps do
            ValidateStep(frame.steps[stepIndex], path .. ".steps[" .. stepIndex .. "]")
        end
        if frame.expect ~= nil then
            ValidateExpect(frame.expect, path .. ".expect")
        end
    end
end

local function HasCheckpoint(fixture)
    for i = 1, #fixture.frames do
        if fixture.frames[i].expect ~= nil then
            return true
        end
    end
    return false
end

local function LoadFixtureFile(path)
    local chunk, err = loadfile(path)
    if not chunk then
        Fail("failed to load fixture " .. path .. ": " .. tostring(err))
    end
    local fixture = chunk()
    ValidateFixture(fixture)
    return fixture
end

local function ListPullFixtures()
    local found = {}
    for _, path in ipairs(Fs.ListFiles()) do
        if path:find(PULL_PATH_PATTERN) then
            found[#found + 1] = path
        end
    end
    return found
end

local function PossibleWorlds(Tracker, wave)
    if not wave then
        return {}
    end
    local w1, w2 = Tracker.GetPossibleWorlds(wave)
    local labels = {}
    if w1 then
        labels[#labels + 1] = "W1"
    end
    if w2 then
        labels[#labels + 1] = "W2"
    end
    return labels
end

local function CopyArray(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function NormalizeProductionState(Tracker, state, ids)
    if state.curWave then
        ids:observe(state.curWave)
    end
    for i = 1, #state.list do
        ids:observe(state.list[i].wave)
    end

    local live = {}
    for i = 1, #state.list do
        local shadow = state.list[i]
        live[i] = {
            id = ids:shadowId(shadow),
            kicks = shadow.kicks,
            casting = shadow.casting == true,
            marked = shadow.marked == true,
            expired = shadow.expired == true,
            plate = shadow.plate or false,
        }
    end

    local plateOwners = {}
    for plate, owner in pairs(state.plateOwner) do
        plateOwners[plate] = ids:shadowId(owner)
    end

    local currentWave = false
    local currentWaveMembers = {}
    if state.curWave then
        currentWave = ids:waveId(state.curWave)
        local members = state.curWave.members
        for i = 1, #members do
            currentWaveMembers[i] = ids:shadowId(members[i])
        end
    end

    return {
        currentWave = currentWave,
        currentWaveMembers = currentWaveMembers,
        live = live,
        plateOwners = plateOwners,
        possibleWorlds = PossibleWorlds(Tracker, state.curWave),
    }
end

local function EmptySnapshot()
    return {
        currentWave = false,
        currentWaveMembers = {},
        live = {},
        plateOwners = {},
        possibleWorlds = {},
    }
end

local function NewIdentityMap()
    local waveSeq = 0
    local waveIds = {}
    local memberIds = {}
    local ids = {}

    function ids:observe(wave)
        if type(wave) ~= "table" or waveIds[wave] then
            return
        end
        waveSeq = waveSeq + 1
        local waveId = "w" .. waveSeq
        waveIds[wave] = waveId
        local members = wave.members
        if type(members) == "table" then
            for i = 1, #members do
                memberIds[members[i]] = waveId .. "m" .. i
            end
        end
    end

    function ids:waveId(wave)
        self:observe(wave)
        return waveIds[wave]
    end

    function ids:shadowId(shadow)
        self:observe(shadow and shadow.wave)
        local id = memberIds[shadow]
        if not id then
            Fail("snapshot encountered an untracked shadow object")
        end
        return id
    end

    return ids
end

local function CheckpointFail(context, path, expected, actual)
    local lines = {
        "Coiled Altar Replay FAILED",
        "",
        "Fixture: " .. context.fixtureName,
        "Frame: " .. tostring(context.frameId),
        "Time: " .. string.format("%.3f", context.frameTime),
        "",
        "Path: " .. path,
        "",
        "Expected: " .. FormatValue(expected),
        "Actual:   " .. FormatValue(actual),
    }
    local liveIndex = path:match("^live%[(%d+)%]")
    if liveIndex then
        local index = tonumber(liveIndex)
        local record = context.snapshot.live[index]
        if record then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Object: " .. tostring(record.id)
            lines[#lines + 1] = "Current boss token: boss" .. (index + FIRST_SHADOW_BOSS - 1)
        end
    end
    Fail(table.concat(lines, "\n"))
end

local function AssertSameValue(context, path, expected, actual)
    if expected ~= actual then
        CheckpointFail(context, path, expected, actual)
    end
end

local function AssertSameArray(context, path, expected, actual, compareItem)
    if type(actual) ~= "table" then
        CheckpointFail(context, path, expected, actual)
    end
    if #expected ~= #actual then
        CheckpointFail(context, path, expected, actual)
    end
    for i = 1, #expected do
        compareItem(path .. "[" .. i .. "]", expected[i], actual[i])
    end
end

local function AssertSameMap(context, path, expected, actual)
    if type(actual) ~= "table" then
        CheckpointFail(context, path, expected, actual)
    end
    for key, value in pairs(expected) do
        AssertSameValue(context, path .. "[" .. tostring(key) .. "]", value, actual[key])
    end
    for key, value in pairs(actual) do
        if expected[key] == nil then
            CheckpointFail(context, path .. "[" .. tostring(key) .. "]", nil, value)
        end
    end
end

local function AssertCheckpoint(expect, snapshot, context)
    ValidateExpect(expect, "expect")
    context.snapshot = snapshot
    if expect.currentWave ~= nil then
        AssertSameValue(context, "currentWave", expect.currentWave, snapshot.currentWave)
    end
    if expect.currentWaveMembers ~= nil then
        AssertSameArray(
            context,
            "currentWaveMembers",
            expect.currentWaveMembers,
            snapshot.currentWaveMembers,
            function(path, expected, actual)
                AssertSameValue(context, path, expected, actual)
            end
        )
    end
    if expect.live ~= nil then
        AssertSameArray(context, "live", expect.live, snapshot.live, function(path, expected, actual)
            if type(actual) ~= "table" then
                CheckpointFail(context, path, expected, actual)
            end
            for i = 1, #LIVE_FIELD_ORDER do
                local key = LIVE_FIELD_ORDER[i]
                AssertSameValue(context, path .. "." .. key, expected[key], actual[key])
            end
        end)
    end
    if expect.plateOwners ~= nil then
        AssertSameMap(context, "plateOwners", expect.plateOwners, snapshot.plateOwners)
    end
    if expect.possibleWorlds ~= nil then
        AssertSameArray(
            context,
            "possibleWorlds",
            expect.possibleWorlds,
            snapshot.possibleWorlds,
            function(path, expected, actual)
                AssertSameValue(context, path, expected, actual)
            end
        )
    end
end

-- Production mount:
-- 1. Fresh namespace via Loader.Load / Modules.Start.
-- 2. Assign a MELEE interrupt so HasInterruptAssignments() is true.
-- 3. CoiledAltar:ListenForEncounter() + ENCOUNTER_START 3429, which calls Tracker.Start.
--    Fixtures may omit ENCOUNTER_START. A fixture ENCOUNTER_END is forwarded to the
--    production WhileIn teardown; the snapshot then reports empty tracker state.
-- 4. Replace requestFlush's Timer.After(0, ...) with env:defer. EnsureBatch still decides
--    when a flush is requested and whether events share one pending batch.
-- 5. Replay events are forwarded to the same production subscriptions (Spell / Encounter /
--    Nameplate / RaidTarget). The adapter does not apply interrupt-state transitions itself.
local CoiledAltarReplay = {}

function CoiledAltarReplay.mount(env)
    local ns = Loader.Load()
    ns.Modules.Start(ns.Database.Load(nil))
    local Module = ns.Modules.Get("CoiledAltar")
    local Tracker = ns.Modules.Internals("CoiledAltar").InterruptTracker
    local Encounter = ns.Api.Encounter
    local Nameplate = ns.Api.Nameplate
    local RaidTarget = ns.Api.RaidTarget
    local Spell = ns.Api.Spell
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

    if not Module:AssignInterruptPlayer("MELEE", 1, "PlayerA") then
        Fail("failed to configure a non-empty interrupt chain")
    end
    Module:ListenForEncounter()
    Encounter.FireStart(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20)
    local state = Tracker.Get()
    if type(state) ~= "table" then
        Fail("Coiled Altar tracker did not start for encounter 3429")
    end

    state.requestFlush = function()
        if state.flushScheduled or state.disposed then
            return
        end
        state.flushScheduled = true
        env:defer(function()
            state.flushScheduled = false
            if state.disposed then
                return
            end
            Tracker.Flush(state)
        end)
    end

    env.events:on("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
        Encounter.FireEnd(encounterID, encounterName, difficultyID, groupSize, success)
    end)
    env.events:on("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
        Encounter.FireEngageUnit()
    end)
    env.events:on("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
        Spell.FireCastStart(unit, castGUID, spellID)
    end)
    env.events:on("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID, spellID)
        Spell.FireCastInterrupted(unit, castGUID, spellID)
    end)
    env.events:on("UNIT_SPELLCAST_STOP", function(_, unit, castGUID, spellID)
        Spell.FireCastStop(unit, castGUID, spellID)
    end)
    env.events:on("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
        Spell.FireCastSucceeded(unit, castGUID, spellID)
    end)
    env.events:on("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        Nameplate.FireRemoved(unit)
    end)
    env.events:on("RAID_TARGET_UPDATE", function()
        RaidTarget.FireChanged()
    end)

    local ids = NewIdentityMap()
    return {
        snapshot = function()
            if Tracker.Get() ~= state then
                return EmptySnapshot()
            end
            return NormalizeProductionState(Tracker, state, ids)
        end,
        stop = function()
            if Tracker.Get() == state then
                Encounter.FireEnd(Module.ENCOUNTER_ID, "The Coiled Altar", 16, 20, 1)
            end
        end,
    }
end

local function AssertAcyclic(value, seen)
    if type(value) ~= "table" then
        return
    end
    if seen[value] then
        Fail("snapshot contains a cyclic reference")
    end
    seen[value] = true
    for key, item in pairs(value) do
        AssertAcyclic(key, seen)
        AssertAcyclic(item, seen)
    end
end

describe("Coiled Altar interrupt replay", function()
    local runners

    local function NewRunner()
        local runner = Replay.new({ mount = CoiledAltarReplay.mount })
        runners[#runners + 1] = runner
        return runner
    end

    local function RunReplay(fixture, extraOnFrame)
        ValidateFixture(fixture)
        local runner = NewRunner()
        runner:run(fixture, {
            onFrame = function(current, frame, snapshot)
                if extraOnFrame then
                    extraOnFrame(current, frame, snapshot)
                end
                if frame.expect ~= nil then
                    AssertCheckpoint(frame.expect, snapshot, {
                        fixtureName = fixture.name,
                        frameId = frame.id,
                        frameTime = frame.time,
                    })
                end
            end,
        })
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

    describe("synthetic fixture", function()
        it("replays example_pull through the production tracker", function()
            local fixture = LoadFixtureFile(EXAMPLE_PATH)
            local snapshots = {}
            local runner = RunReplay(fixture, function(_, frame, snapshot)
                snapshots[frame.id] = snapshot
            end)

            assert.equals("w1", snapshots[100].currentWave)
            assert.same({ "w1m1", "w1m2" }, snapshots[100].currentWaveMembers)
            assert.equals("w1m1", snapshots[120].live[1].id)
            assert.equals(1, snapshots[120].live[1].kicks)
            assert.equals("nameplate7", snapshots[120].live[1].plate)
            assert.equals(0, snapshots[120].live[2].kicks)
            assert.is_true(snapshots[120].live[2].casting)
            assert.same({ nameplate7 = "w1m1" }, snapshots[120].plateOwners)
            assert.same({ "W1" }, snapshots[120].possibleWorlds)
            assert.equals("w1m1", runner:snapshot().live[1].id)
        end)

        it("keeps stable object ids after a boss-token shift", function()
            local fixture = {
                schemaVersion = 1,
                name = "Identity After Death",
                frames = {
                    {
                        id = 1,
                        time = 1,
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
                        id = 2,
                        time = 2,
                        steps = {
                            {
                                op = "unit",
                                token = "nameplate7",
                                properties = { exists = true, level = 92, markerPresent = false },
                            },
                            {
                                op = "event",
                                name = "UNIT_SPELLCAST_START",
                                args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                            },
                            {
                                op = "event",
                                name = "UNIT_SPELLCAST_START",
                                args = Replay.args("nameplate7", Replay.PRESENT, Replay.PRESENT),
                            },
                        },
                    },
                    {
                        id = 3,
                        time = 3,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { exists = true, level = 92, markerPresent = false },
                            },
                            { op = "remove", token = "boss4" },
                            {
                                op = "event",
                                name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                                args = Replay.args(),
                            },
                            {
                                op = "event",
                                name = "UNIT_SPELLCAST_INTERRUPTED",
                                args = Replay.args("nameplate7", Replay.PRESENT, nil),
                            },
                            {
                                op = "event",
                                name = "NAME_PLATE_UNIT_REMOVED",
                                args = Replay.args("nameplate7"),
                            },
                            { op = "remove", token = "nameplate7" },
                        },
                        expect = {
                            currentWave = "w1",
                            currentWaveMembers = { "w1m1", "w1m2" },
                            live = {
                                {
                                    id = "w1m2",
                                    kicks = 0,
                                    casting = false,
                                    marked = false,
                                    expired = false,
                                    plate = false,
                                },
                            },
                            plateOwners = {},
                        },
                    },
                },
            }

            local firstLive
            RunReplay(fixture, function(_, frame, snapshot)
                if frame.id == 1 then
                    firstLive = CopyArray(snapshot.live)
                    assert.equals("w1m1", snapshot.live[1].id)
                    assert.equals("w1m2", snapshot.live[2].id)
                elseif frame.id == 2 then
                    assert.equals(firstLive[1].id, snapshot.live[1].id)
                    assert.equals(firstLive[2].id, snapshot.live[2].id)
                    assert.equals("nameplate7", snapshot.live[1].plate)
                end
            end)
        end)

        it("reports empty state after ENCOUNTER_END", function()
            RunReplay({
                schemaVersion = 1,
                name = "Encounter End",
                frames = {
                    {
                        id = 1,
                        time = 1,
                        steps = {
                            {
                                op = "unit",
                                token = "boss3",
                                properties = { exists = true, level = 92, markerPresent = false },
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
                        expect = {
                            currentWave = "w1",
                        },
                    },
                    {
                        id = 2,
                        time = 2,
                        steps = {
                            {
                                op = "event",
                                name = "ENCOUNTER_END",
                                args = Replay.args(3429, "The Coiled Altar", 16, 20, 0),
                            },
                        },
                        expect = {
                            currentWave = false,
                            currentWaveMembers = {},
                            live = {},
                            plateOwners = {},
                            possibleWorlds = {},
                        },
                    },
                },
            })
        end)

        it("returns acyclic plain snapshots", function()
            local runner = RunReplay(LoadFixtureFile(EXAMPLE_PATH))
            local snapshot = runner:snapshot()
            AssertAcyclic(snapshot, {})
            local plate = snapshot.live[1].plate
            assert.equals("string", type(snapshot.live[1].id))
            assert.equals("number", type(snapshot.live[1].kicks))
            assert.equals("boolean", type(snapshot.live[1].casting))
            assert(plate == false or type(plate) == "string", "plate must be false or a unit token")
        end)
    end)

    describe("checkpoint assertions", function()
        it("fails when an expected interrupt count does not match", function()
            local fixture = LoadFixtureFile(EXAMPLE_PATH)
            fixture.frames[3].expect.live[1].kicks = 4
            local ok, err = pcall(RunReplay, fixture)
            assert.is_false(ok)
            err = tostring(err)
            assert(err:find("Coiled Altar Replay FAILED", 1, true), err)
            assert(err:find("Fixture: Example Pull", 1, true), err)
            assert(err:find("Frame: 120", 1, true), err)
            assert(err:find("Path: live[1].kicks", 1, true), err)
            assert(err:find("Expected: 4", 1, true), err)
            assert(err:find("Actual:   1", 1, true), err)
            assert(err:find("Object: w1m1", 1, true), err)
            assert(err:find("Current boss token: boss3", 1, true), err)
        end)

        it("fails when an expected object id does not match", function()
            local fixture = LoadFixtureFile(EXAMPLE_PATH)
            fixture.frames[3].expect.live[1].id = "w1m2"
            local ok, err = pcall(RunReplay, fixture)
            assert.is_false(ok)
            err = tostring(err)
            assert(err:find("Path: live[1].id", 1, true), err)
            assert(err:find('Expected: "w1m2"', 1, true), err)
            assert(err:find('Actual:   "w1m1"', 1, true), err)
        end)

        it("rejects unknown expect fields", function()
            local ok, err = pcall(ValidateExpect, { kicks = 1 }, "expect")
            assert.is_false(ok)
            assert(tostring(err):find("unknown field kicks", 1, true), tostring(err))
        end)

        it("rejects an empty expect table", function()
            local ok, err = pcall(ValidateExpect, {}, "expect")
            assert.is_false(ok)
            assert(tostring(err):find("is empty", 1, true), tostring(err))
        end)
    end)

    describe("fixture schema", function()
        it("rejects malformed fixtures", function()
            local ok, err = pcall(ValidateFixture, {
                schemaVersion = 2,
                name = "Bad",
                frames = { { id = 1, time = 1, steps = {} } },
            })
            assert.is_false(ok)
            assert(tostring(err):find("schemaVersion must be 1", 1, true), tostring(err))

            ok, err = pcall(ValidateFixture, {
                schemaVersion = 1,
                name = "",
                frames = { { id = 1, time = 1, steps = {} } },
            })
            assert.is_false(ok)
            assert(tostring(err):find("name must be a non-empty string", 1, true), tostring(err))

            ok, err = pcall(ValidateFixture, {
                schemaVersion = 1,
                name = "Empty",
                frames = {},
            })
            assert.is_false(ok)
            assert(tostring(err):find("non-empty array", 1, true), tostring(err))

            ok, err = pcall(ValidateFixture, {
                schemaVersion = 1,
                name = "Ids",
                frames = {
                    { id = 2, time = 1, steps = {} },
                    { id = 2, time = 2, steps = {} },
                },
            })
            assert.is_false(ok)
            assert(tostring(err):find("strictly increasing", 1, true), tostring(err))
        end)

        it("rejects a pull fixture that has frames but no checkpoints", function()
            local fixture = {
                schemaVersion = 1,
                name = "No Checkpoints",
                frames = {
                    { id = 1, time = 1, steps = {} },
                },
            }
            ValidateFixture(fixture)
            assert.is_false(HasCheckpoint(fixture))
        end)

        it("discovers *_pull.lua files in the fixtures directory", function()
            local pulls = ListPullFixtures()
            local foundExample = false
            for i = 1, #pulls do
                assert(pulls[i]:find(PULL_PATH_PATTERN), pulls[i])
                if pulls[i] == EXAMPLE_PATH then
                    foundExample = true
                end
            end
            assert.is_true(foundExample)
        end)
    end)

    describe("isolation", function()
        it("does not share production state between runners", function()
            local fixture = LoadFixtureFile(EXAMPLE_PATH)
            local first = RunReplay(fixture)
            local snapshotA = first:snapshot()
            first:close()

            local second = RunReplay(fixture)
            local snapshotB = second:snapshot()
            assert.same(snapshotA, snapshotB)
            assert.equals("w1m1", snapshotB.live[1].id)
            assert.equals(1, snapshotB.live[1].kicks)
        end)
    end)

    describe("pull fixtures", function()
        local pulls = ListPullFixtures()
        if #pulls == 0 then
            it("finds *_pull.lua files", function()
                Fail("no *_pull.lua fixtures found in " .. FIXTURE_DIR)
            end)
        else
            local function ReplayPull(path)
                it("replays " .. path:match("[^/]+$"), function()
                    local fixture = LoadFixtureFile(path)
                    if not HasCheckpoint(fixture) then
                        Fail(path .. " must contain at least one non-empty expect checkpoint")
                    end
                    RunReplay(fixture)
                end)
            end
            for i = 1, #pulls do
                ReplayPull(pulls[i])
            end
        end
    end)
end)
