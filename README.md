# NewEraTools

A World of Warcraft (retail) toolbox addon.

## Features

- **Aura Tracker**: Tracks player buff with a status bar.
- **Auto combat log**: Automatically enables combat logging in current-expansion raids or mythic dungeons.
- **Combat timer**: Floating timer for the current fight.
- **Raid lottery**: Randomly picks raid members and announces them in raid chat.
- **The Lost Explorers helper**: A reminder to feed fish.
- **Sszorak helper**: Displays an arena map with markers and move timeline, and helps assign cysts to markers.

## Usage

Type `/nets` or click the minimap button to open the panel.

## Development

See [AGENTS.md](AGENTS.md) for the project structure and coding rules. Run the tests with `luajit tests/run.lua`.

Other addons can register optional feature extensions through `NewEraToolsAPI`. See [docs/extensions.md](docs/extensions.md).
