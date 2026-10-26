# NewEraTools

A World of Warcraft (retail) toolbox addon.

## Features

General helpers:
- **Aura Tracker**: Tracks player buff with a status bar.
- **Combat timer**: Floating timer for the current fight.
- **Auto combat log**: Automatically enables combat logging in current-expansion raids or mythic dungeons.
- **Interrupt Claim**: Modifier-click a nameplate to set focus, and optionally mark and announce the interrupt.

RL helpers:
- **RL Toolbar**: A toolbar for ready-check & countdowns.
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
