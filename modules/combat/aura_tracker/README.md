# Aura Tracker

Combat-group feature. `AuraTracker.lua` is the module entry point: saved defaults, the tracker list, and module enablement. Other logic files add behavior to that same module. UI lives in `ui/` and is built when the module enables or when the settings page opens.

## Layout

```
AuraTracker.lua     Module entry
Schema.lua          Saved-data shape and defaults
Activation.lua      When a tracker applies to the current player
Settings.lua        Reading and writing saved tracker fields
Runtime.lua         Whether a bar should be shown right now
Display.lua         Names, labels, and preview time text
Media.lua           Bar textures and fonts
Profile.lua         In-memory sample counters for /neatprof
ui/Panel.lua        Settings page and module startup
ui/List.lua         Tracker list
ui/ProfileReport.lua Selectable sample window
ui/editor/          Settings for the selected tracker
ui/bar/             On-screen bar, its look, and the layout-edit preview
```

`combat.xml` loads logic before UI. `ui/Panel.lua` starts the feature. The `/neatprof` command is registered from `ui/bar/Bar.lua`.

## Sampling

`/neatprof` measures the bar's own refresh work. Counters stay off until the first time you run it. That first run starts sampling and says so. Run it again to open the totals in a window you can select and copy. `/neatprof reset` clears the totals and keeps sampling. `/reload` stops sampling until you run `/neatprof` again.

Times include nested calls, so do not add rows together. A unit-context event updates the bars only. Changing a tracker's saved settings still refreshes the settings page, and that shows up as its own rows.

## Where to add things

- Saved tracker data: `Schema.lua` and `Settings.lua`, then the matching file in `ui/editor/`.
- Who the tracker applies to: `Activation.lua`.
- When the bar appears: `Runtime.lua`. If the frame itself must change, `ui/bar/`.
- How the bar is painted: `ui/bar/`, shared by the live bar and the layout-edit preview.
- Settings-page controls: `ui/editor/`.
- Widgets shared with other features: the top-level `ui/` folder.
