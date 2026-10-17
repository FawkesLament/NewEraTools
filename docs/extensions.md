# Sszorak communication modes

A communication mode turns Sszorak signals into macro text and a HUD callout. Register one from your addon. NewEraTools loads and runs with none registered.

Depend on the host so it loads first:

```
## Dependencies: NewEraTools
```

Call `RegisterExtension` from your addon's files or its load callback.

```lua
local capabilities = NewEraToolsAPI.GetCapabilities("sszorak.communication")

NewEraToolsAPI.RegisterExtension("sszorak.communication", "relay", {
    id = "relay",
    GetEdgeMacroBody = function(self, edge, assignment)
        return "/raid {rt1}"
    end,
    Listen = function(self)
        local stopWarning = capabilities.events.SubscribeViscousCystWarning()
        return function()
            stopWarning()
        end
    end,
    OnViscousCystWarning = function(self, anchorIndex)
        return nil
    end,
})
```

`extensionType` is `sszorak.communication`. `providerId` is your mode id. Both are 1–64 characters and match `[A-Za-z][A-Za-z0-9_.-]*`. `provider.id` is the same string as `providerId`.

Registration fails if an argument is invalid or that id is already registered. The host registers `normal`. It does not register `jailbreak`; another addon may use that id. A failed registration does not replace the existing mode. A registration lasts until reload or logout.

## Provider

| Field | When the host calls it |
| --- | --- |
| `GetEdgeMacroBody(self, edge, assignment)` | While building the macro for one markable edge. Return the macro body. |
| `Listen(self)` | When this mode becomes active. Subscribe, and return a function that removes those subscriptions. |
| `OnViscousCystWarning(self, anchorIndex)` | After `SubscribeViscousCystWarning`, when a viscous-cyst warning matches an anchor. Return a resolve, or `nil` to show nothing. |
| `BeginCapture(self)` | A pull or map test started. The HUD is already clear. Start collecting signals. |
| `EndCapture(self)` | That pull or map test ended. The HUD is already clear. Drop what you collected. |
| `ClearMessages(self)` | The dots returned home during a timeline. The HUD is already clear. Drop the buffer for the next cycle. |
| `IsCapturing(self)` | Return true after `BeginCapture` until `EndCapture`. The host waits for false before switching to a mode that registered during that session. |

`GetEdgeMacroBody`, `Listen`, and `OnViscousCystWarning` are required. The other four are optional; the host calls each one only when it is present.

`edge` in `GetEdgeMacroBody` is one of 2, 3, 4, 6, 7, or 8. `assignment` maps each of those edges to the world marker on it: `STAR`, `CIRCLE`, `DIAMOND`, `TRIANGLE`, `MOON`, `SQUARE`, `CROSS`, or `SKULL`. Return the macro text only. The host creates and edits the macro, and waits until combat ends if the edit is not allowed yet.

From `Listen`, call `capabilities.events.SubscribeViscousCystWarning()`. That subscribes the host's warning filter, which then calls `OnViscousCystWarning`. Stop that subscription from the function `Listen` returns. The host calls that function when this mode stops being active.

`anchorIndex` is 1-based. Anchors repeat in groups of 4. Index 4, 8, 12, … is the exit callout. Slots 1 and 2 of each group are the entrance side of the room; slot 3 is the exit side.

A resolve is a table with `hudMessage` and, when the map should draw a path, `targetEdge`. Return `nil` when there is nothing to show. The host displays `hudMessage` and clears it when a capture starts, a capture ends, or the dots return home.

`targetEdge` uses the same octagon. Edge 1 is the entrance and edge 5 is the exit. Markable edges are 2, 3, 4, 6, 7, and 8. The opposite edge is four steps around: 2↔6, 3↔7, 4↔8. Group B stands on 2–4 and group A on 6–8. Depth from the entrance is near on 2 and 8, mid on 3 and 7, and far on 4 and 6.

## Capabilities

`NewEraToolsAPI.GetCapabilities("sszorak.communication")` returns a read-only context, `version` 1. Read it after NewEraTools has loaded. Assigning to the context or to a group is an error.

| Operation | Result |
| --- | --- |
| `events.SubscribeViscousCystWarning()` | Subscribes the warning filter. Returns an unsubscribe function. |
| `presentation.Resolve(edge, fromEntranceSide)` | The jailbreak HUD resolve for `edge`, or `nil`. |

`Resolve` uses the exit phrase for edge 5. For any other edge it uses the raid-target icon of the marker on that edge, then the position relative to the player's group. Pass `fromEntranceSide` as true when the player is on the entrance side of the room; near and far are swapped otherwise. An edge with no marker returns `nil`.

For anything else, call the game API yourself. `GetTime` orders signals. `CHAT_MSG_RAID_WARNING`, `CHAT_MSG_RAID_LEADER`, and `RAID_TARGET_UPDATE` are the raid signals.

## Activation

Registering stores the mode and adds it to the mode list. The host calls `Listen` when the mode is the one in use.

If the saved mode id is yours, the host keeps that choice even when your addon has not registered yet, and uses `normal` until you do. After you register, it switches to your mode when no pull is in progress and the active mode is not capturing. During a pull or capture it switches when that session ends. If the player selects your mode in the panel, the host switches to it then.
