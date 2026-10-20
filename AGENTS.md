# NewEraTools: project rules

A World of Warcraft (retail) addon written in Lua 5.1. These rules apply to people and AI agents alike.

## Layout

```
NewEraTools.toc   Loads one XML manifest per layer, then Main.lua.
<folder>.xml      Each folder's manifest: lists its .lua files and sub-folder manifests, in load order.
Main.lua          Entry point: loads saved variables and starts modules.
core/             Basic utilities and pure logic: namespace, util, locale table, database, module registry, extension registry, MessageProtocol.
api/              The only code that calls Blizzard game functions or listens to game events.
locales/          Translations. zhCN.lua is the base locale and defines every key.
services/         Shared non-UI services used by modules (and optionally ui/), e.g. AddonCheck.
ui/               Shared, module-independent UI: assets, widgets, layout, floating windows, layout editor, main panel.
modules/<group>/  One folder per sidebar group, named after its PanelGroups key (raid_leader/).
modules/<group>/<name>/  One folder per feature: <Name>.lua (logic). UI is <Name>UI.lua, or a local ui/ folder for a larger feature.
modules/*.lua     The only files directly in modules/: content shared by features (PanelGroups.lua).
media/            Textures.
tests/            Unit tests run outside the game. WoW never loads them.
```

## Architecture

1. Layers load in this order: `core` → `api` → `locales` → `services` → `ui` → `modules` → `Main.lua`. A file may use only layers loaded before it. `services` may use `core`/`api`/`locales` but never `ui` or `modules`. `ui` may use `services` (and earlier layers) but never `modules`. Every folder with Lua files or sub-folders has a manifest named after the folder (`raid_leader/raid_leader.xml`) using `<Script file="..."/>` for its files and `<Include file="..."/>` for sub-folders; paths are relative to the manifest. The exception is feature folders, including a local `ui/` inside them: they have no manifest, and their group's manifest lists their files directly (`<Script file="raid_lottery\RaidLottery.lua"/>`). Manifests only list files; UI is built in Lua, not XML.
2. Only `api/` touches game state: Blizzard functions, constants and events. It returns plain tables and offers callbacks (e.g. `Group.OnChanged`) instead of raw events. API version differences are handled inside `api/`, once, at load time. Keep wrappers thin: if a game function's signature already fits, assign it directly (`Timer.After = C_Timer.After`), and don't allocate tables per call in anything that may run often.
3. Direct frame and widget calls (`CreateFrame`, `GameTooltip`, ...) belong only in a `ui/` directory (shared or inside a feature) or in a `*UI.lua` file. Other files may build UI only through those components. Template, texture, atlas and font names, plus shared spacing, sizes and colors, live in `ui/Assets.lua`. Place widgets with `ui/Layout.lua` (stacks, rows, grids) instead of fixed offsets from the container's top, and let buttons size to their text.
4. Logic files (`core/`, `services/`, module `<Name>.lua`, shared files in `modules/`) use only plain Lua and `ns`. They do not call `CreateFrame`; they may ask a UI component to build frames, and they stay independent of a concrete UI. `services/` holds cross-feature non-UI behavior that may call `api/`; keep `core/` limited to basics and pure helpers.
5. Every feature is a module: `ns.Modules.New(name, { defaults = ... })`. `self.db` holds its saved settings. `OnInit` runs for all modules, then `OnEnable` for all modules. Feature modules never reference each other; they may use UI services such as `ns.MainPanel`, shared services such as `ns.AddonCheck`, and shared content such as `ns.PanelGroups`. Shared content in `modules/` is data, not a module, and is loaded by `modules/modules.xml` before any feature. Feature UI may use shared `ui/` and its own module's public interface. Shared `ui/` never names a feature or a group. Extract a shared component only when the abstraction is genuinely reusable.
6. Loading a file only defines things. Frames, events and slash commands are set up in `OnEnable`.
7. All shared state lives in the `ns` table. Globals are limited to `NewEraToolsDB`, the `NewEraToolsAPI` registration table, slash commands and named frames, all prefixed `NewEraTools`. Do not put `ns` or feature modules on `NewEraToolsAPI`. See [docs/extensions.md](docs/extensions.md).
8. No user-visible string literals in code: use `L.KEY`, defined in `locales/zhCN.lua`.
9. To change the shape of saved data, bump `SCHEMA_VERSION` in `core/Database.lua` and add a migration.

## Extensions

External addons register optional feature extensions on `NewEraToolsAPI`. The host runs fully with none installed. Feature modules read them through `ns.Extensions` and define the provider contract for their own extension type. Contracts are not a shared provider interface. See [docs/extensions.md](docs/extensions.md).

## Adding a feature

1. Logic in `modules/<group>/<snake_name>/<Name>.lua`, where `<group>` is the lowercased `ns.PanelGroups` key of the feature's sidebar group. UI goes in `<Name>UI.lua`, or in that feature's `ui/` folder when one file is not enough, and calls `ns.MainPanel:RegisterSection` from `OnEnable` with that `group`. A new group goes into `modules/PanelGroups.lua` with a unique `order`, gets a `modules/<group>/<group>.xml` manifest, and is included from `modules/modules.xml`.
2. List the logic file, then its UI files, in `modules/<group>/<group>.xml` (`<snake_name>\<Name>.lua`, then `<Name>UI.lua` or `<snake_name>\ui\...`).
3. Add strings to `locales/zhCN.lua` (and other locales).
4. A new game API call goes into an `api/` function, gets a fake in `tests/helpers/fakes/`, and is listed in `.luacheckrc`. New `api/` files are added to `api/api.xml`.
5. Add tests under tests/modules/<group>/<snake_name>/, grouped by behavior rather than production filename. Small features may use a single <Name>_spec.lua; split complex features into focused specs. Follow the testing rules below.

## Adding a floating UI element

Positioning is shared; appearance and visibility stay in the module.

1. Prefer `ui/FloatingWindow.lua` for overlays, or a plain outer layout host when the real content is protected/secret-sensitive (e.g. AuraContainer). Use `MEDIUM` frame strata (not `DIALOG`/`HIGH`) so Blizzard menus stay on top; layout edit mode raises frames temporarily. Persist `{ point, relativePoint, x, y }` in the module's `defaults` and expose get/set helpers. Do not invent a second drag/save path.
2. Register with `ns.LayoutEditor.Register` from the module UI (`OnEnable` / first frame create). Use a stable id `Feature:instance` (e.g. `AuraTracker:1`) so multiple instances can be added later. Set `global = true` for general-purpose UI (the common UI scope). Set `global = false` for boss- or encounter-specific UI, register one scope with `LayoutEditor.RegisterScope` (`id`, `label`, `elementIds`, optional `prepare`), and call `LayoutEditor.BeginScope(id)` from that module's layout button. The main panel's **编辑布局** button enters the same editor in the common scope. There is one editing session; the toolbar switches scopes.
3. Implement `onEditBegin` / `onEditEnd` to show a preview without requiring the feature's normal activation conditions, then restore normal show/hide and mouse behavior. A module may optionally run a lightweight preview animation while editing (start in `onEditBegin`, stop in `onEditEnd`); keep it local to the module. The editor only moves position; width, height, scale, and look stay on the module's own settings.
4. Outside edit mode, floating chrome must not steal clicks for dragging. Keep intentional clicks (e.g. "enable combat logging") if the feature needs them. Never reanchor protected frames during combat; editing is out-of-combat only and exits automatically when combat starts.

## Code style

- Follow existing naming and file organization conventions. Use `stylua .` for formatting and respect `.stylua.toml`.
- Library tables (`Util`, `Api.*`) use dot functions; modules use colon methods.
- Add LuaLS annotations (`---@param`, `---@return`, `---@class`) for public APIs and non-obvious data shapes.
- Comments explain intent, constraints, or non-obvious behavior rather than narrating the code.

## Testing

- **Run tests:** Use `luajit tests/run.lua` from the addon folder (Lua 5.1; in-repo busted-compatible subset). Run the full suite after changes; all tests must pass.
- **Test selectively:** Tests protect observable behavioral contracts, not implementation details, static data, or test counts. **Default to NOT adding tests.** Add or update tests only for meaningful logic, state transitions, edge cases, or regression risks. Do not add tests solely for changes to constants, configuration defaults, mappings, labels, styling, layout, or straightforward refactoring. Run existing tests as appropriate even when no new tests are needed.
- **Test quality:** Verify actual outcomes and meaningful failure paths. Never weaken assertions just to pass tests. For significant bug fixes, prefer a regression test that fails before the fix. For high-risk logic, consider reversible mutation testing. Do not duplicate coverage or assert hardcoded implementation values.
- **Organization:** Group specs by behavior, not production file. Keep them focused without excessive fragmentation or shared fixtures. Prefer extending existing specs over creating new files. Remove obsolete or redundant tests when appropriate, but preserve meaningful assertions during test-only refactoring.
- **Isolation and mocks:** Each test must have isolated state; use `before_each`/`after_each` and restore overridden globals reliably. Avoid test-order dependencies and hidden defaults. Mocks must reflect documented API contracts without being overly permissive. Do not derive expected results solely from the implementation. Avoid caching globals such as `math.random` at production load time when tests need to stub them.
- **WoW limitations:** The test loader fakes most `api/` adapters; `Aura`, `Encounter`, and `MessageProtocolComm` use production implementations. Fake-based tests cannot validate actual Blizzard API behavior. Complex adapters may use contract specs with stubbed WoW globals. The loader skips `ui/`, `*UI.lua`, and `Main.lua`; UI specs may load selected files with frame stubs. Meta tests cover TOC/manifest completeness and locale keys. Secret values, combat restrictions, protected UI, and UI changes require in-game validation (`/reload`, `/netools`, and relevant raid scenarios).
- **Reporting:** Summarize test results, relevant behavior verified, and remaining in-game validation needs. Explicitly state when no tests were added and why, without treating that as a deficiency.

## WoW constraints

- Addon code runs in Lua 5.1 with no `require`, `io` or `os`. Files share state only through `ns`.
- Update `## Interface` in the TOC after major game patches.
- Never hardcode `Interface\AddOns\...` paths; use `ns.Assets`.
- Renaming the saved variable or a module discards its saved settings unless a migration carries them over.

## Inter-addon messaging

- `api/AddonMessage` is the only transport wrapper for Blizzard addon messages (prefixes, send/receive, throttle results).
- `core/MessageProtocol` owns the v1 envelope and topic routing; `api/MessageProtocolComm` is the one-way adapter that listens/sends on `NET_RT` / `NET_CTL`. See [docs/message_protocol.md](docs/message_protocol.md).
- Feature modules own payload bytes, topics, authorization, request lifecycles, and traffic class (`REALTIME` vs `CONTROL`). Do not put business schemas in the generic protocol layer.
- Prefer MessageProtocol + MessageProtocolComm for new cross-client features; do not add new per-feature addon-message prefixes.
