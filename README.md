# NewEraTools

A World of Warcraft (retail) toolbox addon.

## Features

General helpers:
- **Aura tracker**: Tracks player buff with a status bar.
- **Auto combat log**: Automatically enables combat logging in current-expansion raids or mythic dungeons.
- **Combat timer**: Floating timer for the current fight.
- **Interrupt claim**: Modifier-click to focus and mark an enemy, and announce to the party.

RL helpers:
- **RL toolbar**: Ready-check, countdown and cancel.
- **Raid lottery**: Randomly picks raid members and announces them in raid chat.

Encounter-specific:
- **The Lost Explorers**: Reminds feeding fish.
- **Sszorak**: Displays an arena map with markers and move timeline, and helps assign cysts to markers.
- **Twin Fangs**: Reminds interrupt based on custom, pre-defined rotations & soak.

## Usage

Type `/nets` or click the minimap button to open the panel.

## Development

See [AGENTS.md](AGENTS.md) for the project structure and coding rules. Run the tests with `luajit tests/run.lua`.

Other addons can register optional feature extensions through `NewEraToolsAPI`. See [docs/extensions/](docs/extensions/).
