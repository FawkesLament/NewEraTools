# Coiled Altar Interrupt Replay Fixtures

Place Lua fixtures in this directory. The integration spec loads them through the generic replay harness and drives the production Coiled Altar interrupt tracker.

Do not regroup events by timestamp. Do not infer frame boundaries from floating-point time. Preserve the original event order and the frame boundaries you observed.

A recorded event does **not** change mock world state. A world-state query does **not** emit an event. If the game world changed, write an explicit `unit` or `remove` step at the point the production code would observe that change.

## Running tests

From the addon folder:

```text
luajit tests/run.lua tests/modules/venomous_abyss/coiled_altar/interrupt_replay_spec.lua
luajit tests/run.lua
```

The first command runs only this spec. The second runs the full suite. Nested `*_spec.lua` files are discovered automatically.

Every `*_pull.lua` file in this directory is discovered and replayed. `example_pull.lua` is the built-in synthetic smoke fixture. Additional recordings such as `real_pull.lua` run automatically once you add them. A present but invalid fixture fails the test. Files that do not match `*_pull.lua` are ignored.

## Root schema

Fixtures are ordinary Lua files that return a table:

```lua
local Replay = require("helpers.replay")

return {
    schemaVersion = 1,
    name = "Description",
    frames = {
        -- one or more frames
    },
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | yes | Integer, currently exactly `1`. |
| `name` | yes | Non-empty string used in failure diagnostics. |
| `frames` | yes | Non-empty array of frames, in playback order. |

Unknown root fields are rejected.

## Frame schema

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Numeric frame id. Must be strictly increasing. |
| `time` | yes | Simulated time in seconds. Must not move backwards. |
| `steps` | yes | Array of operations. May be empty. |
| `expect` | no | Checkpoint asserted **after** the frame flushes. |

Unknown frame fields are rejected. `expect = {}` is invalid.

Each replay frame:

1. Applies `steps` in order.
2. Runs deferred production work (`Tracker.Flush` when the production code requested it).
3. Snapshots production state.
4. Compares any `expect` fields.
5. Continues.

## Step operations

Use the Replay harness operations only. Partial unit updates are allowed. Events must pack arguments with `Replay.args`, including zero-argument events.

### Unit update

```lua
{
    op = "unit",
    token = "boss3",
    properties = {
        exists = true,
        level = 92,
        markerPresent = false,
    },
}
```

Accepted properties:

| Property | Type | Used by |
| --- | --- | --- |
| `exists` | boolean | `UnitExists` |
| `level` | number | `UnitLevel` (required before a living unit is queried) |
| `markerPresent` | boolean | `GetRaidTargetIndex` (`true` → `Replay.PRESENT`, `false` → `nil`) |

Unconfigured tokens fail the replay when queried. Configure every boss token the tracker enumerates, including the first nonexistent token that stops enumeration. If `boss3` and `boss4` exist, set `boss5` to `{ exists = false }`.

Configure every nameplate token before `UnitLevel` runs for it. That query happens during `UNIT_SPELLCAST_*` handling, not only at end-of-frame.

### Unit removal

```lua
{
    op = "remove",
    token = "nameplate7",
}
```

Marks the token as `exists = false`. It does **not** emit `NAME_PLATE_UNIT_REMOVED`.

### Event dispatch

```lua
{
    op = "event",
    name = "UNIT_SPELLCAST_START",
    args = Replay.args("boss3", Replay.PRESENT, Replay.PRESENT),
}
```

```lua
{
    op = "event",
    name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    args = Replay.args(),
}
```

`Replay.args(...)` preserves positional nils and the exact argument count. Unpack semantics match `unpack(args, 1, args.n)`.

Use `Replay.PRESENT` for non-nil payloads whose contents are secret or irrelevant (cast GUIDs, spell IDs). Use actual `nil` for nil payloads. Do not invent numeric spell IDs or GUIDs.

The tracker currently consumes:

- `INSTANCE_ENCOUNTER_ENGAGE_UNIT`
- `UNIT_SPELLCAST_START`
- `UNIT_SPELLCAST_INTERRUPTED`
- `UNIT_SPELLCAST_STOP`
- `UNIT_SPELLCAST_SUCCEEDED`
- `NAME_PLATE_UNIT_REMOVED`
- `RAID_TARGET_UPDATE`

The adapter starts encounter `3429` before the first frame, so fixtures may omit `ENCOUNTER_START`. A fixture `ENCOUNTER_END` for that encounter is forwarded to production teardown; the following snapshot is empty (`currentWave = false`, no live members).

## World-state contract

Unit updates apply immediately at the step where they appear. They do not emit events. Events do not change mock unit state.

If `boss4` becomes `boss3` after a death, the fixture must describe the mock world after that replacement:

```lua
{
    op = "unit",
    token = "boss3",
    properties = {
        exists = true,
        level = 92,
        markerPresent = false,
    },
},
{
    op = "remove",
    token = "boss4",
},
{
    op = "event",
    name = "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    args = Replay.args(),
},
```

Place those world updates relative to the events exactly as observed. End-of-frame reconciliation queries the world as it exists when the frame flushes, so include observations that matter at flush time.

`NAME_PLATE_UNIT_REMOVED` does not call `remove`. Write both when the plate token actually disappears **and** the event is delivered. Keep the token configured through any `UnitLevel` query that still happens in that frame (for example a nameplate `INTERRUPTED` that precedes `REMOVED`).

Nameplate tokens can be reused later. After `remove`, a later `unit` step may recreate `nameplate7` with a new existence/level/marker snapshot. The production tracker does not treat token reuse as the same shadow; identity lives in the tracker objects, not in the token string.

Do not guess unavailable observations. If the production code would query a token and you do not know the value, the replay will fail rather than invent an answer.

## Normalized snapshot

Checkpoints compare against this plain-Lua snapshot. Values are copied each frame; later production mutations do not change earlier snapshots. Object ids are test-only (`w1m1` = wave 1, member 1) and stay stable across token shifts, deaths, unbinds, and wave expiration.

```lua
{
    currentWave = "w2",          -- latest wave id, or false
    currentWaveMembers = {       -- original members in creation order, including dead
        "w2m1",
        "w2m2",
    },
    live = {                     -- production boss list: live[1] = boss3, live[2] = boss4, ...
        {
            id = "w1m2",
            kicks = 4,
            casting = false,
            marked = false,
            expired = true,
            plate = false,       -- bound nameplate token, or false
        },
        {
            id = "w2m1",
            kicks = 1,
            casting = true,
            marked = true,
            expired = false,
            plate = "nameplate7",
        },
    },
    plateOwners = {              -- currently bound nameplate token → object id
        nameplate7 = "w2m1",
    },
    possibleWorlds = {           -- current wave, production GetPossibleWorlds, W1 before W2
        "W1",
    },
}
```

`possibleWorlds` labels:

- `W1` — first member may be melee
- `W2` — second member may be melee

If no wave exists, `currentWave` is `false`, `currentWaveMembers` is `{}`, and `possibleWorlds` is `{}`.

## Checkpoints

All top-level `expect` fields are optional, but each present field is compared completely.

1. A missing top-level field is not asserted.
2. A present top-level field must match completely.
3. Arrays match in length, order, and values.
4. Maps match their complete key/value contents.
5. Nested live records must include every documented field: `id`, `kicks`, `casting`, `marked`, `expired`, `plate`.
6. `false` is a value, not an omitted field.
7. Unknown expected fields are rejected.
8. `expect = {}` is invalid.

Expected values come from the fixture author. The runner does not generate golden files.

## Complete example

See `example_pull.lua` for a passing synthetic fixture. A minimal valid shape:

```lua
local Replay = require("helpers.replay")

return {
    schemaVersion = 1,
    name = "Minimal Spawn",
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
            },
        },
    },
}
```

Every `*_pull.lua` file must include at least one frame and at least one non-empty `expect` checkpoint.

## What the harness does not simulate

- WoW secret-value enforcement. `Replay.PRESENT` is a non-nil stand-in; algorithms that only test nil vs non-nil are exercised, not Blizzard's secret API.
- Automatic world updates from events, or automatic events from world updates.
- Combat lockdown, protected frames, or real nameplate frame objects. `nameplateN` tokens are recognized by pattern; `UnitLevel` still requires a configured unit.
- Real spell IDs, GUIDs, or raid-marker indices `1`–`8`. Markers are only present vs absent.
- Queries of unconfigured tokens. Those fail the replay instead of returning WoW's default values.
- Addon messaging, UI, persistence, or recovery paths that the production tracker does not run during the encounter.
- Frame-boundary inference from timestamps.
