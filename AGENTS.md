# NewEraTools: Project Rules

A World of Warcraft (retail) addon written in Lua 5.1. These rules apply to both developers and AI agents.

## Project Layout

```
NewEraTools.toc       Loads layer manifests, then Main.lua.
<folder>.xml          Lists Lua files and sub-folder manifests in load order.
Main.lua              Initializes saved variables and starts modules.
core/                 Namespace, utilities, database, module registry, extensions, protocols.
api/                  Blizzard API adapters and game event subscriptions.
locales/              Translations; zhCN.lua defines all keys.
services/             Shared non-UI services.
ui/                   Shared UI components, layout, editor, main panel.
modules/<group>/      Feature groups matching PanelGroups keys.
modules/<group>/<name>/
                      Feature logic and feature-specific UI.
modules/PanelGroups.lua
                      Shared group metadata.
media/                Textures and assets.
tests/                Out-of-game Lua tests; never loaded by WoW.
```

## Architecture

1. **Layering:** Load order is `core → api → locales → services → ui → modules → Main.lua`. Files may depend only on earlier layers. `services/` must not depend on `ui/` or `modules/`; shared `ui/` must not depend on `modules/`. Extract shared components only when genuinely reusable.

2. **Manifests:** Each ordinary folder containing Lua files or sub-folders has a matching XML manifest (`raid_leader/raid_leader.xml`), using `<Script>` and `<Include>` with relative paths. Feature folders and their descendants are exceptions: they have no manifests; the group's manifest lists their Lua files directly. XML controls loading only; UI is built in Lua.

3. **Game APIs:** Only `api/` calls Blizzard game functions, accesses game state, or subscribes to game events. Expose thin adapters, plain data, and callbacks rather than raw events. Handle API version differences in `api/` at load time. Avoid unnecessary allocations in frequently called wrappers.

4. **UI boundaries:** Direct frame/widget APIs (`CreateFrame`, `GameTooltip`, etc.) belong only in shared or feature-local `ui/` directories or `*UI.lua` files. Logic files use plain Lua and `ns`; they may invoke UI components but must not manipulate frames directly. Shared visual constants belong in `ui/Assets.lua`. Prefer `ui/Layout.lua` over fixed positioning; let buttons size to their text.

5. **Modules:** Every feature uses `ns.Modules.New(name, { defaults = ... })`, with saved settings in `self.db`. `OnInit` runs for all modules before `OnEnable` runs for all modules. Shared UI requiring initialization, settings, or enable hooks may also be a module, but is not a feature. Feature modules must not reference one another; communicate through shared services or public UI interfaces. Shared content such as `PanelGroups` is data, not a module.

6. **Initialization:** Loading a file only defines functions, tables, and registrations. Runtime initialization—including frames, event subscriptions, and slash commands—happens in `OnEnable`. Register persistent resources once; avoid repeated initialization.

7. **State ownership:** Cross-component shared state is exposed through `ns`; private runtime state remains local to its owner. Feature files must not add keys directly to `ns`. Feature-private components use `local Internals = ns.Modules.Internals("<ModuleName>")`, accessible only within that feature's folder. Each key has a single defining file; premature access raises. Globals are restricted to `NewEraToolsDB`, the `NewEraToolsAPI` registration table, slash commands, and named frames, all using the `NewEraTools` prefix. Never expose `ns` or feature modules through `NewEraToolsAPI`. See [docs/extensions/](docs/extensions/).

8. **Resource lifecycle:** Every temporary subscription, timer, ticker, or other active resource must have a clear owner and cleanup path. Register low-frequency global listeners once for the addon lifetime; avoid unnecessary subscribe/unsubscribe cycles. Clean up encounter-specific and other temporary resources when their owner becomes inactive. Cancel pending timers or guard against stale callbacks. Reuse UI frames rather than repeatedly creating them; hiding a frame does not automatically unregister its events. Avoid unnecessary `OnUpdate` handlers and polling. Do not introduce complex lifecycle abstractions without a concrete need.

9. **Localization:** No user-visible string literals in code. Define strings in `locales/zhCN.lua` and reference them through `L.KEY`.

10. **Persistence:** When changing saved-data structure, increment `SCHEMA_VERSION` in `core/Database.lua` and add a migration. Renaming modules or saved variables requires migration to preserve settings.

## Extensions

External addons register optional feature extensions through `NewEraToolsAPI`. The host must work without extensions. Feature modules consume providers through `ns.Extensions` and own their specific provider contracts; do not invent a universal provider interface. See [docs/extensions/](docs/extensions/).

## Adding Features

1. Create feature logic in `modules/<group>/<snake_name>/<Name>.lua`. Put UI in `<Name>UI.lua` or a feature-local `ui/` folder. Larger features may organize related files into sub-folders.
2. List feature files in load order in `modules/<group>/<group>.xml` (logic before UI). New groups need a unique `order` in `modules/PanelGroups.lua`, a group manifest, and an include in `modules/modules.xml`.
3. Register UI sections through `ns.MainPanel:RegisterSection` from `OnEnable`, using the feature's `PanelGroups` group.
4. Add localization keys. New Blizzard APIs belong in `api/`, with corresponding test fakes, `.luacheckrc` entries, and manifest updates.
5. Add or update tests only when warranted by the Testing rules.

## Floating UI

- **Positioning:** Prefer `ui/FloatingWindow.lua`, or a plain layout host for protected/secret-sensitive content such as `AuraContainer`. Use `MEDIUM` strata so Blizzard menus remain on top. Persist `{ point, relativePoint, x, y }` in module defaults and reuse the existing drag/save infrastructure.
- **Layout editing:** Register elements through `ns.LayoutEditor.Register` with stable IDs (`Feature:instance`). Use `global = true` for common UI. Boss-specific elements use `global = false` and a dedicated `LayoutEditor.RegisterScope` (`id`, `label`, `elementIds`, optional `prepare`), entered through `LayoutEditor.BeginScope(id)`. Do not create separate editing systems.
- **Preview:** Implement `onEditBegin` / `onEditEnd` to show preview content independently of normal activation, then restore visibility and mouse behavior. Stop any preview animation or timer when editing ends. The editor controls position only; appearance and dimensions remain feature-owned.
- **Interaction and combat:** Floating chrome must not intercept normal clicks outside edit mode. Keep intentional interactive controls functional. Never reanchor or otherwise perform prohibited changes to protected frames during combat. Layout editing is out-of-combat only and exits when combat begins.
- **Lifetime:** Create persistent UI elements once and reuse them. Separate frame existence from feature activation and visibility; clean up temporary handlers, timers, and interaction state when appropriate.

## Code Style

- Follow existing naming and file organization conventions. Format with `stylua .` and respect `.stylua.toml`.
- Library tables (`Util`, `Api.*`) use dot functions; modules use colon methods.
- Add LuaLS annotations for public APIs and non-obvious data shapes.
- Comments explain intent, constraints, and surprising behavior, not what the code already states.
- Prefer simple, local solutions over speculative abstractions. Avoid duplicating existing infrastructure.

## Testing

- **Execution:** Run `luajit tests/run.lua` from the addon folder (Lua 5.1; in-repo busted-compatible subset). Run the full suite after changes; all tests must pass.
- **Coverage:** Test observable contracts, meaningful logic, state transitions, edge cases, and regressions—not implementation details or test counts. Default to not adding tests for constants, mappings, defaults, labels, styling, layout, or straightforward refactoring.
- **Quality:** Assert actual outcomes and failure behavior. Never weaken assertions merely to make tests pass. Prefer a regression test that fails before significant bug fixes. For high-risk logic, consider reversible mutation testing. Do not derive expected results solely from production implementation.
- **Lifecycle:** For lifecycle-sensitive code, test repeated activation/deactivation, cleanup, and prevention of stale callbacks where applicable. Verify that subscriptions and timers do not accumulate across repeated sessions.
- **Organization:** Group specs by observable behavior, not production files. Keep them focused, prefer extending existing specs, and avoid excessive fixtures or fragmentation. Remove redundant tests without losing meaningful coverage.
- **Isolation:** Reset state between tests and reliably restore mocked globals. Avoid test-order dependencies and hidden defaults. Mocks must reflect documented API contracts without being overly permissive.
- **WoW limitations:** Most `api/` adapters are replaced with fakes; `Aura`, `Encounter`, and `MessageProtocolComm` use production implementations. Adapter contract specs may stub WoW globals. The loader skips `ui/`, `*UI.lua`, and `Main.lua`; UI specs may load selected files with frame stubs. Meta tests check manifests, locale keys, and architectural boundaries. Fakes cannot establish real WoW API behavior.
- **In-game validation:** Secret values, combat lockdown, protected UI, and visual changes require in-game testing (`/reload`, `/netools`, and relevant encounter scenarios).
- **Reporting:** Summarize tests run, behaviors verified, and remaining in-game validation. If no tests were added, briefly explain why without treating that as a deficiency.

## WoW Constraints

- Lua 5.1 only; no `require`, `io`, or `os`. Files share cross-component state through `ns`.
- Respect secret values, combat restrictions, and protected UI boundaries. Do not assume data readable outside combat remains readable during encounters.
- Never hardcode `Interface\AddOns\...` paths; use `ns.Assets`.

## Inter-Addon Messaging

- `api/AddonMessage` is the only Blizzard addon-message transport wrapper (prefixes, send/receive, throttle results).
- `core/MessageProtocol` owns the v1 envelope and topic routing. `api/MessageProtocolComm` bridges the protocol to `NET_RT` / `NET_CTL`. See [docs/message_protocol.md](docs/message_protocol.md).
- Features own payload formats, topics, authorization, request lifecycles, and traffic class (`REALTIME` / `CONTROL`). Keep business schemas out of the generic protocol.
- Prefer `MessageProtocol` + `MessageProtocolComm` for new cross-client features. Do not create new per-feature addon-message prefixes.