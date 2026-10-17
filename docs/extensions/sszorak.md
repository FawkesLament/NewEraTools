# Sszorak communication modes

A communication mode turns Sszorak signals into macro text and a HUD callout. Register one from your addon. NewEraTools loads and runs with none registered.

## Edges

The arena is a regular octagon. Edges are numbered 1 through 8, counterclockwise. Edge 1 is the entrance on the right. Edge 5 is the exit on the left.

Markable edges are 2, 3, 4, 6, 7, and 8. The entrance and the exit are not markable. Every later `edge` argument, and `CystGuidance.targetEdge`, uses these numbers. The opposite edge is four steps around: 1↔5, 2↔6, 3↔7, and 4↔8.

Group B stands on 2–4. Group A stands on 6–8. Depth from the entrance is near on 2 and 8, mid on 3 and 7, and far on 4 and 6.

## Registration

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

Registration fails if an argument is invalid or that id is already registered. The host registers `normal`. A failed registration does not replace the existing mode. A registration lasts until reload or logout.

## Provider

`GetEdgeMacroBody`, `Listen`, and `OnViscousCystWarning` are required. The other four are optional; the host calls each one only when it is present. The host clears the callout when a capture starts, a capture ends, or the dots return home.

```lua
---While building the macro for one markable edge.
---Return the macro text only. The host creates and edits the macro, and waits until combat ends if the edit is not allowed yet.
---`assignment` maps each markable edge to its world marker (`"STAR"`, `"CIRCLE"`, `"DIAMOND"`, `"TRIANGLE"`, `"MOON"`, `"SQUARE"`, `"CROSS"`, `"SKULL"`). The entrance and the exit are absent.
---@param edge integer Markable edge from the Edges section.
---@param assignment table<integer, string>
---@return string
function Provider:GetEdgeMacroBody(edge, assignment) end
```

```lua
---When this mode becomes active.
---Call `capabilities.events.SubscribeViscousCystWarning()`. That subscribes the host's warning filter, which then calls `OnViscousCystWarning`.
---Return a function that removes every subscription this call added. The host calls that function when this mode stops being active.
---@return fun()
function Provider:Listen() end
```

```lua
---After `SubscribeViscousCystWarning`, when a viscous-cyst warning matches an anchor.
---Return a `CystGuidance`, or `nil` to show nothing.
---`anchorIndex` is 1-based. Anchors repeat in groups of 4. Index 4, 8, 12, … is the exit callout.
---Slots 1 and 2 of each group are the entrance side of the room; slot 3 is the exit side.
---@param anchorIndex integer
---@return CystGuidance|nil
function Provider:OnViscousCystWarning(anchorIndex) end
```

```lua
---Map edge to highlight, and the HUD text to show.
---`targetEdge` is an edge number from the Edges section. Nil draws no arrow.
---Omit `hudMessage` when `targetEdge` is set to let the host build it: the exit phrase for edge 5, otherwise the marker icon on that edge plus the position relative to the player's group. Near and far swap on an exit-side anchor. An edge with no marker shows nothing.
---A returned `hudMessage` is shown as is, including when `targetEdge` is also set.
---@class CystGuidance
---@field targetEdge? number
---@field hudMessage? string
```

```lua
---Optional. A pull or map test started. The HUD is already clear. Start collecting signals.
function Provider:BeginCapture() end
```

```lua
---Optional. That pull or map test ended. The HUD is already clear. Drop what you collected.
function Provider:EndCapture() end
```

```lua
---Optional. The dots returned home during a timeline. The HUD is already clear. Drop the buffer for the next cycle.
function Provider:ClearMessages() end
```

```lua
---Optional. Return true after `BeginCapture` until `EndCapture`.
---The host waits for false before switching to a mode that registered during that session.
---@return boolean
function Provider:IsCapturing() end
```

## Capabilities

`NewEraToolsAPI.GetCapabilities("sszorak.communication")` returns a read-only context, `version` 1. Read it after NewEraTools has loaded. Assigning to the context or to a group is an error.

```lua
---Subscribes the host's warning filter. The host then calls the active mode's `OnViscousCystWarning`.
---@return fun() unsubscribe
function events:SubscribeViscousCystWarning() end
```

For anything else, call the game API yourself.

## Activation

Registering stores the mode and adds it to the mode list. The host calls `Listen` when the mode is the one in use.

If the saved mode id is yours, the host keeps that choice even when your addon has not registered yet, and uses `normal` until you do. After you register, it switches to your mode when no pull is in progress and the active mode is not capturing. During a pull or capture it switches when that session ends. If the player selects your mode in the panel, the host switches to it then.
