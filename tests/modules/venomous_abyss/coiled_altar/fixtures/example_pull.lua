local Replay = require("helpers.replay")

-- Synthetic smoke fixture: two shadows spawn, both start casting, then a same-frame
-- nameplate INTERRUPTED binds boss3 and increments that shadow's interrupt count once.
return {
    schemaVersion = 1,
    name = "Example Pull",

    frames = {
        {
            id = 100,
            time = 12.500,
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
            expect = {
                currentWave = "w1",
                currentWaveMembers = { "w1m1", "w1m2" },
                live = {
                    {
                        id = "w1m1",
                        kicks = 0,
                        casting = false,
                        marked = true,
                        expired = false,
                        plate = false,
                    },
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
                possibleWorlds = { "W1" },
            },
        },
        {
            id = 110,
            time = 13.000,
            steps = {
                {
                    op = "event",
                    name = "UNIT_SPELLCAST_START",
                    args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                },
                {
                    op = "event",
                    name = "UNIT_SPELLCAST_START",
                    args = Replay.args("boss4", Replay.PRESENT, Replay.PRESENT),
                },
            },
            expect = {
                live = {
                    {
                        id = "w1m1",
                        kicks = 0,
                        casting = true,
                        marked = true,
                        expired = false,
                        plate = false,
                    },
                    {
                        id = "w1m2",
                        kicks = 0,
                        casting = true,
                        marked = false,
                        expired = false,
                        plate = false,
                    },
                },
            },
        },
        {
            id = 120,
            time = 13.400,
            steps = {
                {
                    op = "unit",
                    token = "nameplate7",
                    properties = { exists = true, level = 92, markerPresent = false },
                },
                {
                    op = "event",
                    name = "UNIT_SPELLCAST_INTERRUPTED",
                    args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
                },
                {
                    op = "event",
                    name = "UNIT_SPELLCAST_INTERRUPTED",
                    args = Replay.args("nameplate7", Replay.PRESENT, Replay.PRESENT),
                },
            },
            expect = {
                currentWave = "w1",
                currentWaveMembers = { "w1m1", "w1m2" },
                live = {
                    {
                        id = "w1m1",
                        kicks = 1,
                        casting = false,
                        marked = true,
                        expired = false,
                        plate = "nameplate7",
                    },
                    {
                        id = "w1m2",
                        kicks = 0,
                        casting = true,
                        marked = false,
                        expired = false,
                        plate = false,
                    },
                },
                plateOwners = {
                    nameplate7 = "w1m1",
                },
                possibleWorlds = { "W1" },
            },
        },
    },
}
