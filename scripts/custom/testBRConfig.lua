testBRConfig = {}

-- This file contains configuration and localization data, feel free to edit it to fit your needs

-- ====================== CONFIG ======================

-- print out a lot more messages about what script is doing
testBRConfig.debugLevel = 1

-- how fast time passes
-- you will most likely want this to be very low in order to have skybox remain the same
--testBRConfig.timeScale = 0.1

-- determines defaulttime of day for maps that do not have it specified
--testBRConfig.timeOfDay = 9

-- determines default weather
--testBRConfig.weather = 0

-- Determines if the effects from player's chosen race get applied
--testBRConfig.allowRacePowers = false

-- Determines if the effects from player's chosen celestial sign get applied
--testBRConfig.allowSignPowers = false

-- Determines if it is possible to use different presets of equipment / stats 
--testBRConfig.allowClasses = true

-- Determines if players are allowed to enter interiors
testBRConfig.allowInteriors = true

-- Define image files for map
testBRConfig.fogNoneFilePath = tes3mp.GetDataPath() .. "/map/fognone.png" -- This should point to a fully transparent image
testBRConfig.fogWarnFilePath = tes3mp.GetDataPath() .. "/map/fogwarn.png"
testBRConfig.fog1FilePath = tes3mp.GetDataPath() .. "/map/fog1.png"
testBRConfig.fog2FilePath = tes3mp.GetDataPath() .. "/map/fog2.png"
testBRConfig.fog3FilePath = tes3mp.GetDataPath() .. "/map/fog3.png"

-- default stats for players
testBRConfig.defaultStats = {
playerLevel = 1,
playerAttributes = 75,
playerSkills = 75,
playerHealth = 100,
playerMagicka = 100,
playerFatigue = 300,
playerLuck = 100,
playerSpeed = 75,
playerAcrobatics = 50,
playerMarksman = 150
}

-- turns out it's much easier if you don't try to combine arrays whose elements do not necesarily correspond
-- config that determines how the fog will behave 
testBRConfig.fogLevelSizes = {"all", 20, 15, 10, 5, 3, 1}
testBRConfig.fogStageDurations = {300, 240, 240, 120, 120, 60, 60, 120}
-- determines the order of how levels increase damage
testBRConfig.fogDamageValues = {"warn", 1, 2, 3}


-- used to determine the cell span on which to use the fog logic
-- {{min_X, min_Y},{max_X, max_Y}}
testBRConfig.mapBorders = {{-15,-15}, {25,25}}

-- How many seconds does match proposal last
testBRConfig.matchProposalTime = 120

-- Lobby cell
testBRConfig.lobbyCell = "Vivec, fosse de l'Arène"

testBRConfig.lobbySpawn = { posX=-13.7, posY=-76.2, posZ=-459.4 }

testBRConfig.lootTable = "testBR_loot"


-- ======================== COMMANDS ========================

-- Propose a new match
testBRConfig.cmdNewMatch = "newmatch"

-- Join the current match proposal
testBRConfig.cmdJoin = "join"

-- Mark yourself as ready
testBRConfig.cmdReady = "ready"


-- ====================== LOCALIZATION ======================

-- Displayed in chat when a new match is proposed
testBRConfig.strNewMatchProposal = color.Green .. "New match!" .. color.White .. " Use /" .. testBRConfig.cmdJoin .. " to participate! Players have " .. tostring(testBRConfig.matchProposalTime) .. " seconds to join"

-- Match started with {x} players
testBRConfig.strMatchStart = "Starting match with {x} players!"

-- Message box displayed on joining a match
testBRConfig.strWelcomeToLobby = "Welcome to the lobby!"

-- Message box displayed when a player tries to exit the lobby cell
testBRConfig.strCantLeaveLobby = "You cannot leave the lobby!"

-- Message box displayed on match start
testBRConfig.strBeginMatch = "Begin match!"

-- Displayed when a player tries to enter an interior cell while they are disabled in the br config
testBRConfig.strCantEnterInterior = "You cannot enter interiors!"

-- Message box displayed one minute before a blight shrink
testBRConfig.strBlightAlert1Minute = "Blight shrinking in a minute!"

-- Message box displayed {x} seconds before a blight shrink
testBRConfig.strBlightAlertSec = "Blight shrinking in {x} seconds"

-- Message box displayed when a player respawns as a spectator
testBRConfig.strGhost = "You're now a spooky ghost!"

-- Chat message displayed when {x} kills themselves
testBRConfig.strDied = "{x} died."

-- Chat message displayed when {y} was killed by {x}
testBRConfig.strKill = "{x} was killed by {y}."

-- {x} died, {y} players remaining.
testBRConfig.strXDiedYPlayersRemaining = "{x} died, {y} players remaining."

-- End of match, everyone died
testBRConfig.strEndNoWinner = "Everyone died."

-- End of match, {x} won
testBRConfig.strEndWin = "{x} won the match!"

-- A match is already running
testBRConfig.strMatchAlreadyRunning = "A match is already running"

-- A match proposal is already running, join it with /join
testBRConfig.strProposalAlreadyRunning = "A match proposal is already running, join it with /" .. testBRConfig.cmdJoin

-- Chat message displayed when {x} uses /ready
testBRConfig.strPlayerReady = "{x} is ready."

-- No current match, start one with /newmatch!
testBRConfig.strNoCurrentMatch = "No current match, start one with /" .. testBRConfig.cmdNewMatch .. "!"

return testBRConfig

