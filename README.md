# TES3MP Battle Royale Prototype

[![Generic badge](https://img.shields.io/badge/code%20style-spaghetti-orange.svg)](https://img.devrant.com/devrant/rant/r_172856_HvF2J.jpg)

Battle Royale game mode for [TES3MP](https://github.com/TES3MP/TES3MP) 0.8.0.

- `scripts/custom/testBR.lua` is the file with most of the code.
- `scripts/custom/testBRLootManager.lua` manages loot tables and loot spawning logic.
- `scripts/custom/testBRConfig.lua` contains settings for the Battle Royale scripts.
- `data` contains images to draw fog on the map and custom records needed for the script to work, as well as a sample loot table.

## Installation
Drop the script and data folders in your server folder and add `require("custom/testBR")` to `scripts/customScripts.lua`.

Adjust configuration in `scripts/custom/testBRConfig.lua`, **especially the lobby cell** because I use the french version of the game, so I set the lobby as "Vivec, fosse de l'Arène".

## Recommended changes to config.lua
- config.allowWildernessRest = false
- config.allowWait = false
- config.shareMapExploration = false

## Usage
### Users
- `/newmatch` to propose a new match
- `/join` to join a match proposition. This will put them in the lobby
- `/ready` when you are in a lobby (the match will start when everyone is ready)
### Admins
- `/forcestartmatch` forces the current proposition to start
- `/forceend` terminates the current match
- `/forcenextfog` makes the fog progress instantly
