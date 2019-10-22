# TES3MP Battle Royale Prototype

[![Generic badge](https://img.shields.io/badge/code%20style-spaghetti-orange.svg)](https://img.devrant.com/devrant/rant/r_172856_HvF2J.jpg)

Battle Royale game mode for TES3MP 0.7.0-alpha.

This is far from finished, so I won't write anything useful here for now.

scripts/custom/testBR.lua is the file with most of the code.
scripts/custom/testBRLootManager.lua manages loot tables and loot spawning logic.
data contains images to draw fog on the map and custom records needed for the script to work.

## Usage
Drop the script and data folders in your server folder and add `require("custom/testBR")` to scripts/customScripts.lua.

## Recommended changes to config.lua
- allowWildernessRest = false
- config.allowWait = false
- shareMapExploration = false
- respawnAtImperialShrine = false
- respawnAtTribunalTemple = false
- playersRespawn = true
- bountyResetOnDeath = true
- bountyDeathPenalty = false
