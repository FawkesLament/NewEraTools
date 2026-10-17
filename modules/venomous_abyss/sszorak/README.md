# Sszorak

Encounter helper for Sszorak. `Sszorak.lua` is the module entry point: saved defaults, raid-leader role, and `OnInit`. Other logic files add behavior to that same module. UI lives in `ui/` and starts from `OnEnable` in `ui/Panel.lua`.

`venomous_abyss.xml` loads logic before UI.

## Layout

```
Sszorak.lua            Module entry
Timeline.lua           Heroic and mythic pull schedules
Arena.lua              Octagon geometry and edge relationships
Markers.lua            Saved marker assignment and raid sync
Settings.lua           Map and callout settings, AddonCheck snapshot
Encounter.lua          Pull and test lifecycle, boss and group positions
communication/         How a commander callout becomes a destination
Macros.lua             Account macros and combat deferral
ui/Map.lua             Arena drawing and commander click visuals
ui/Window.lua          Floating map, preview, and edit position
ui/Callout.lua         Callout HUD
ui/Panel.lua           Settings page and module startup
```

## Flow

Commander macro → the active file in `communication/` → one shared guidance result → arena map and callout HUD.

The two modes collect signals differently. They do not draw frames. The map and the HUD only read the guidance result, so neither knows which mode produced it.

Saved settings and the marker assignment stay separate from the current pull. A test uses the same movement and guidance path as a pull, with its own start and stop.

## Combat

Secure marker buttons are created when the module enables, before a pull. Do not change their protected attributes from encounter callbacks. Macro creates and edits that happen in combat wait until combat ends.

## Where to add things

- Saved settings: `Sszorak.lua` defaults, then `Settings.lua`.
- Arena shape or edge relationships: `Arena.lua`.
- Marker assignment or its sync: `Markers.lua`.
- Pull timing: `Timeline.lua`. Who is in the fight, and where the boss and groups stand: `Encounter.lua`.
- A new callout mode: a file under `communication/` that registers with `Communication.lua`, loaded after it. Mode-specific macro text stays on that mode. Macro create and update stay in `Macros.lua`.
- Map drawing: `ui/Map.lua`. Window show, hide, and edit position: `ui/Window.lua`. HUD frame: `ui/Callout.lua`. Settings controls: `ui/Panel.lua`.
