
-- Battle Royale game mode by testman, continued by Kapouett
-- v0.3

--[[
Add the permanentRecords in data/recordstores/spell.json

Add fog1.png, fog2.png, fog3.png and fogwarn.png in data/map

To make respawning work, replace BasePlayer:Resurrect() in scripts/player/base.lua with:
function BasePlayer:Resurrect() -- Modified respawning behavior for Battle Royale
	-- Ensure that dying as a werewolf turns you back into your normal form
    if self.data.shapeshift.isWerewolf == true then
        self:SetWerewolfState(false)
    end

    -- Ensure that we unequip deadly items when applicable, to prevent an
    -- infinite death loop
    contentFixer.UnequipDeadlyItems(self.pid)

	tes3mp.Resurrect(self.pid, enumerations.resurrect.REGULAR)
end

--]]

-- TODO:
-- find a decent name for overall project
-- untangle all the spaghetti code
-- - A LOT OF IT
-- -- HOLY SHIT I CAN'T STRESS ENOUGH HOW MUCH FIXING AND IMPROVING THIS CODE NEEDS
-- - order functions in the order that makes sense
-- - figure out what / if there is a a difference between methods and functions in LUA
-- -- figure out how to make timers execute functions with given arguments instead of relying on global variables
-- figure out how the zone-shrinking logic should actually work
-- implement said decent zone-shrinking logic
-- - make shrinking take some time instead of being an instant event
-- - make zone circle-shaped
-- make players unable to open vanilla containers
-- implement victory condition logic
-- implement custom containers that can be opened by players
-- make players start taking damage if they are in a cell that turned into a non-safe cell
-- implement drop-on death
-- think about possible revival mechanics
-- restore fatigue constant effect
-- resend map to rejoining player
-- make sure to clear spells
-- implement hybrid playerzone shrinking system:
-- - use cell based system at the start
-- - switch to coordinates-math-distance-circle at the end
-- longer drop speed boost time


--[[

=================== DESIGN DOCUMENT PART ===================

Usually I like to plan out project development, but this time I went directly into the code and I got lost very quickly in a mess of concepts.
So with this we are taking a step back and defining some things that can help make sense of this mess of a code below.

Overall logic:

players spawn in lobby by default, where they can sign up for next round and wait until it starts
once round starts, players get teleported to exterior, timers for parachuting logic and also timer for fog shrinking starts.
From that point on we differentiate between players in lobby and players in game. Well, players who are in lobby stay like they were and
players who are in round get to do battle royale stuff until they get killed or round ends. After that they get flagged as out of round and 
spawn in lobby with rest of players.

fog - the thing that battle royale games have. It shrinks over time and damages players who stand in it

fogGridLimits - an array that contains the bottom left (min X and min Y) and top right (max X and max Y) for each level

fog grid - Currently used logic is square-based, but same principle could easily work for other shapes, preferably circle (https://en.wikipedia.org/wiki/Midpoint_circle_algorithm)
Whole area gets segmented when the match starts, so that it doesn't have to determine each new zone when fog starts shrinking
Below example is for grid with 4 levels. Each time fog shrinks, it moves one level in. and all cells in that area start dealing damage to player

+------------------------------#
| 1                            |
|  +------------------#        |
|  | 2    +---------# |        |
|  |      | 3       | |        |
|  |      | +--#    | |        |
|  |      | | 4|    | |        |
|  |      | #--+    | |        |
|  |      #---------+ |        |
|  |                  |        |
|  |                  |        |
|  #------------------+        |
|                              |
|                              |
#------------------------------+
(# represents the coordinates that are saved in array, + and the lines are extrapolated from the given two cells)

fogLevel - one set of cells. It is used to easily determine if cell that player entered should cause damage to player or not.

fogStage - basically index of fog progress

---- Kapouett's stuff ----
Players are in spectator mode (state 0) and can start a match proposal.
Players can join a proposed match (switching to state 1), moving them to the lobby.
Players can mark themselves as ready (switching to state 2). When everyone in the lobby is ready, the match begins (switching participants to state 3)
When a match participant (state 3) enters a cell, random loot is spawned according to the data defined in the json file (stored in data/custom).
When a player dies during a match, they drop their inventory and respawn as a spectator (state 0) where they died.
The match ends when only one player is left (or 0)

TODO:
- Spawn loot in containers
- Reset world when a match starts
- Let spectators teleport to players
- Add customization options (fix race/class/birthsign bonuses)
- Cancel fog timers when a match ends

]]

-- find a decent name
testBR = {}

-- ====================== CONFIG ======================

-- print out a lot more messages about what script is doing
debugLevel = 1

-- how fast time passes
-- you will most likely want this to be very low in order to have skybox remain the same
--timeScale = 0.1

-- determines defaulttime of day for maps that do not have it specified
--timeOfDay = 9

-- determines default weather
--weather = 0

-- Determines if the effects from player's chosen race get applied
--allowRacePowers = false

-- Determines if the effects from player's chosen celestial sign get applied
--allowSignPowers = false

-- Determines if it is possible to use different presets of equipment / stats 
--allowClasses = true

-- Determines if players are allowed to enter interiors
allowInteriors = true

-- define image files for map
fogWarnFilePath = tes3mp.GetDataPath() .. "/map/fogwarn.png"
fog1FilePath = tes3mp.GetDataPath() .. "/map/fog1.png"
fog2FilePath = tes3mp.GetDataPath() .. "/map/fog2.png"
fog3FilePath = tes3mp.GetDataPath() .. "/map/fog3.png"
fogFilePaths = {fogWarnFilePath, fog1FilePath, fog2FilePath, fog3FilePath}

-- default stats for players
defaultStats = {
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
fogLevelSizes = {"all", 20, 15, 10, 5, 3, 1}
fogStageDurations = {300, 240, 240, 120, 120, 60, 60, 10}
-- determines the order of how levels increase damage
fogDamageValues = {"warn", 1, 2, 3}


-- used to determine the cell span on which to use the fog logic
-- {{min_X, min_Y},{max_X, max_Y}}
mapBorders = {{-15,-15}, {25,25}}

-- how many seconds does match proposal last
matchProposalTime = 60

-- Lobby cell
lobbyCell = "Vivec, fosse de l'Arène"

-- ====================== GLOBAL VARIABLES ======================

-- unique identifier for the match
matchId = 0

-- indicates if there is currently an active match going on
roundInProgress = false

-- indicates if match proposal is currently in progress
matchProposalInProgress = false

-- keep track of which players are in a match
playerList = {}

-- cells visited during this match, used for loot spawning
visitedCells = {}

-- used to track the fog progress
currentFogStage = 1

-- used to store ony bottom left and top right corner of each level
fogGridLimits = {}

-- for warnings about time remaining until fog shrinks
fogShrinkRemainingTime = 0

-- ====================== FUN STARTS HERE ======================

-- used for match IDs and for RNG seed
time = require("time")

-- used for generation of random numbers
math.randomseed(os.time())

lootManager = require("custom/testBRLootManager")

-- used to easily regulate the level of information when debugging
testBR.DebugLog = function(requiredDebugLevel, message)
	if debugLevel >= requiredDebugLevel then
		tes3mp.LogMessage(2, message)
	end
end

-- Init loot table
testBR.DebugLog(1, "Initializing loot table manager")
testBRLootManager.init("testBR_loot")

-- Reload loot tables from disk
testBR.LoadLootTables = function()
	testBR.DebugLog(1, "Loading loot table from disk")
	testBRLootManager.LoadFromDisk()
end

testBR.TableLen = function(T)
	local count = 0
	for k, v in pairs(T) do
		if v ~= nil then
			count = count + 1
		end
	end
	return count
end

-- How many players are in a specific BR state
testBR.CountState = function(state)
	local res = 0
	for onlinePid, player in pairs(Players) do
		if player:IsLoggedIn() then
			if player.data.BRinfo.state == state then
				res = res + 1
			end
		end
	end
	return res
end

-- Remove all players form lobby
testBR.ClearLobby = function()
	if matchInProgress then
		testBR.DebugLog(3, "Attempted to clear the lobby while the match is running")
		return
	end
	for pid, player in pairs(Players) do
		testBR.SetPlayerState(pid, 0)
	end
end

-- Begin match TODO: Kill timers from previous games
testBR.StartRound = function()
	if roundInProgress then
		testBR.DebugLog(3, "Attempted to start a match, but one in already running")
		return
	end

	matchId = os.time()

	testBR.DebugLog(2, "Starting a battle royale round with ID " .. tostring(roundID))

	playerList = {}

	visitedCells = {}

	testBR.LoadLootTables()

	fogGridLimits = testBR.GenerateFogGrid(fogLevelSizes)

	currentFogStage = 1

	matchProposalInProgress = false

	roundInProgress = true

	testBR.ResetWorld()

	for pid, player in pairs(Players) do
		testBR.PlayerInit(pid)
	end

	tes3mp.SendMessage(0, "Starting match with " .. tostring(testBR.CountState(3)) .. " players!\n", true)

	testBR.StartFogTimer(fogStageDurations[currentFogStage])
end

-- TODO: implement this after implementing chests / drop-on-death
testBR.ResetWorld = function()

end

-- Start the match for a player
testBR.PlayerInit = function(pid)
	testBR.DebugLog(2, "Starting initial BR setup for PID " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() and Players[pid].data.BRinfo.state == 2 then
		-- Make sure no one enters the game as a corpse (died in lobby)
		--Players[pid]:Resurrect() -- TODO: Change resurrect to do nothing if the character is not dead

		Players[pid].data.BRinfo.matchId = matchId

		testBR.ResetCharacter(pid)

		testBR.SpawnPlayer(pid)

		testBR.PlayerSpells(pid)

		testBR.ClearInventory(pid)

		testBR.SetFogDamageLevel(pid, 0)

		testBR.StartAirdrop(pid)
		
		table.insert(playerList, pid)

		tes3mp.MessageBox(pid, -1, "Begin match!")

		testBR.SetPlayerState(pid, 3)
	end
end

-- Clear player's spellbook TODO and add feather and restore fatigue powers
testBR.PlayerSpells = function(pid)
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		Players[pid]:CleanSpellbook()
		Players[pid].data.selectedSpell = ""
		Players[pid].data.spellbook = {}
		Players[pid]:LoadSpellbook()
		Players[pid]:LoadSelectedSpell()
		command = "player->addspell feather_power"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
		command = "player->addspell restore_fatigue_power"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	end
end

testBR.ClearInventory = function(pid)
	Players[pid]:CleanInventory()
	Players[pid].data.inventory = {}
	Players[pid].data.equipment = {}
	
	testBR.ApplyPlayerItems(pid)
end

-- save changes and make items appear on player
testBR.ApplyPlayerItems = function(pid)
	Players[pid]:Save()
	Players[pid]:LoadInventory()
	Players[pid]:LoadEquipment()
end

-- Create a new match and auto-join the lobby
testBR.ProposeMatch = function(pid)
	if roundInProgress then
		tes3mp.SendMessage(pid, "A match is already running\n", false)
		return
	end
	if matchProposalInProgress then
		tes3mp.SendMessage(pid, "A match proposal is already running, join it with /join\n", false)
		return
	end

	testBR.ClearLobby()

	testBR.DebugLog(2, "Handling new round proposal from PID " .. tostring(pid))
	matchProposalInProgress = true
	tes3mp.SendMessage(0, color.Green .. "New match!" .. color.White .. " Use /join to participate! Players have " .. tostring(matchProposalTime) .. " seconds to join\n", true)
	matchProposalTimer = tes3mp.CreateTimerEx("BRMatchProposalExpired", time.seconds(matchProposalTime), "i", 1)
	tes3mp.StartTimer(matchProposalTimer)

	-- Auto-join match proposer
	testBR.PlayerJoin(pid)
end

-- Proposal timer expired
BRMatchProposalExpired = function()
	if matchProposalInProgress then
		testBR.DebugLog(2, "Ending current match proposal")
		tes3mp.SendMessage(0, color.Red .. "Match proposal timer expired!" .. color.White .. " Use /newmatch to try again.\n", true)
		matchProposalInProgress = false

		testBR.ClearLobby()
	end
end

-- Join lobby (set state to 1)
testBR.PlayerJoin = function(pid)
	testBR.DebugLog(2, "Setting state for " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if roundInProgress then
			tes3mp.SendMessage(0, "Match in progress, you'll have to wait for the next match\n", false)
			return
		elseif (not matchProposalInProgress) then
			tes3mp.SendMessage(0, "No current match, start one with /newmatch!\n", false)
			return
		elseif Players[pid].data.BRinfo.state == 0 then
			tes3mp.SendMessage(0, Players[pid].data.login.name .. " joined the lobby!\n", true)
			tes3mp.SendMessage(pid, "Use /ready when you're ready to start!\n", false)
			testBR.SetPlayerState(pid, 1)
		elseif Players[pid].data.BRinfo.state == 1 then
			tes3mp.SendMessage(pid, "You already joined, use /ready!\n")
		elseif Players[pid].data.BRinfo.state == 2 then
			tes3mp.SendMessage(pid, "You already joined and marked as ready!\n")
		end
	end
end

-- Player Ready (set state to 2)
testBR.PlayerReady = function(pid)
	if roundInProgress then
		tes3mp.SendMessage(pid, "The match is already running!\n", false)
		return
	end
	if Players[pid] == nil or (not Players[pid]:IsLoggedIn()) then
		return
	end
	if matchProposalInProgress then
		-- Force player to join
		if Players[pid].data.BRinfo.state == 0 then
			testBR.PlayerJoin(pid)
		end
		if Players[pid].data.BRinfo.state == 1 then
			testBR.SetPlayerState(pid, 2)
			tes3mp.SendMessage(pid, color.Yellow .. Players[pid].data.login.name .. " is ready.\n", true)

			-- Start match if everyone is ready
			if testBR.CountState(0) <= 0 then
				testBR.StartRound()
			end

		elseif Players[pid].data.BRinfo.state == 2 then
			tes3mp.SendMessage(pid, "You are already ready.\n", false)
		end
	else
		tes3mp.SendMessage(pid, "There's no match! You can start one with /newmatch\n", false)
	end
end

testBR.StartAirdrop = function(pid)
	Players[pid].data.BRinfo.airMode = 2
	testBR.HandleAirMode(pid)
end

testBR.HandleAirMode = function(pid)
	airmode = Players[pid].data.BRinfo.airMode
	testBR.SetAirMode(pid, airmode)
	Players[pid].data.BRinfo.airMode = airmode - 1
	if airmode > 1 then
		Players[pid].airTimer = tes3mp.CreateTimerEx("OnPlayerTopic", time.seconds((15*airmode)+3), "i", pid)
		tes3mp.StartTimer(Players[pid].airTimer)
	end
end

-- set airborne-related effects
-- 0 = disabled
-- 1 = just slowfall
-- 2 = slowfall and speed
testBR.SetAirMode = function(pid, mode)
	testBR.DebugLog(2, "Setting air mode for " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if mode == 2 then
			testBR.SetSlowFall(pid, true)
			Players[pid].data.attributes["Speed"].base = 3000
		elseif mode == 1 then
			testBR.SetSlowFall(pid, true)
			-- TODO: make this restore the proper value
			Players[pid].data.attributes["Speed"].base = defaultStats.playerSpeed
		else 
			testBR.SetSlowFall(pid, false)
		end

		Players[pid]:Save()
		Players[pid]:LoadAttributes()
	end
end

-- either enables or disables slowfall for player
-- this part assumes that there is a proper entry for slowfall_power in recordstore
testBR.SetSlowFall = function(pid, boolean)
	testBR.DebugLog(2, "Setting slowfall mode for PID " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if boolean then
			command = "player->addspell slowfall_power"
		else
			command = "player->removespell slowfall_power"
		end
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	end
end

-- either enables or disables ghost for player
-- this part assumes that there is a proper entry for br_ghost in recordstore
testBR.SetGhost = function(pid, boolean)
	testBR.DebugLog(2, "Setting slowfall mode for PID " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if boolean then
			command = "player->addspell br_ghost"
		else
			command = "player->removespell br_ghost"
		end
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	end
end

testBR.ProcessCellChange = function(pid)
	testBR.DebugLog(2, "Processing cell change for PID " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() and Players[pid].data.BRinfo.state == 3 then

		-- Spawn random loot if this cell is visited for the first time
		if visitedCells[ tes3mp.GetCell(pid) ] == nil then
			testBRLootManager.SpawnCellLoot( tes3mp.GetCell(pid) )
			visitedCells[ tes3mp.GetCell(pid) ] = true
		end

		-- Check if we are in an exterior to keep track of the last visited exterior cell
		_, _, cellX, cellY = string.find(tes3mp.GetCell(pid), patterns.exteriorCell)
		if cellX ~= nil or cellY ~= nil then
			Players[pid].data.BRinfo.lastExteriorCell = tes3mp.GetCell(pid)
		end

		testBR.CheckCellDamageLevel(pid)
		-- TODO: lol I have no idea how to properly re-paint a tile after player "discovered it"
		--tes3mp.SendWorldMap(pid)
		Players[pid]:SaveStatsDynamic()
		Players[pid]:Save()
	end
end

testBR.SpawnPlayer = function(pid, spawnInLobby)
	testBR.DebugLog(2, "Spawning player " .. tostring(pid))
	if spawnInLobby then
		chosenSpawnPoint = {lobbyCell, -13.7, -76.2, -459.4, 0}
		tes3mp.MessageBox(pid, -1, "Welcome to the lobby!")
	else
		-- TEST: use random spawn point for now
		random_x = math.random(-40000,80000)
		random_y = math.random(-40000,120000)
		testBR.DebugLog(2, "Spawning player " .. tostring(pid) .. " at " .. tostring(random_x) .. ", " .. tostring(random_y))
		--chosenSpawnPoint = {"-2, 7", -13092, 57668, 2593, 2.39}
		chosenSpawnPoint = {"0, 0", random_x, random_y, 30000, 0}
		--chosenSpawnPoint = Players[pid].data.BRinfo.chosenSpawnPoint
		Players[pid].data.BRinfo.airmode = 2
	end
	tes3mp.SetCell(pid, chosenSpawnPoint[1])
	tes3mp.SendCell(pid)
	tes3mp.SetPos(pid, chosenSpawnPoint[2], chosenSpawnPoint[3], chosenSpawnPoint[4])
	tes3mp.SetRot(pid, 0, chosenSpawnPoint[5])
	tes3mp.SendPos(pid)
end

testBR.DropAllItems = function(pid)
	testBR.DebugLog(1, "Dropping all items for PID " .. tostring(pid))

	--mpNum = WorldInstance:GetCurrentMpNum() + 1
	z_offset = 5

	--for index, item in pairs(Players[pid].data.inventory) do
	inventoryLength = #Players[pid].data.inventory
	if inventoryLength > 0 then
		for index=1,inventoryLength do
			testBR.DropItem(pid, index, z_offset)
			z_offset = z_offset + 5
		end
	end
	Players[pid].data.inventory = {}
	Players[pid]:Save()
end

-- inspired by code from from David-AW (https://github.com/David-AW/tes3mp-safezone-dropitems/blob/master/deathdrop.lua#L134)
-- and from rickoff (https://github.com/rickoff/Tes3mp-Ecarlate-Script/blob/0.7.0/DeathDrop/DeathDrop.lua
testBR.DropItem = function(pid, index, z_offset)
		
	local player = Players[pid]
	
	local item = player.data.inventory[index]
	
	if item == nil then return end

	local mpNum = WorldInstance:GetCurrentMpNum() + 1
	local cell = tes3mp.GetCell(pid)
	local location = {
		posX = tes3mp.GetPosX(pid), posY = tes3mp.GetPosY(pid), posZ = tes3mp.GetPosZ(pid) + z_offset,
		rotX = tes3mp.GetRotX(pid), rotY = 0, rotZ = tes3mp.GetRotZ(pid)
	}
	local refId = item.refId
	local refIndex =  0 .. "-" .. mpNum
	local itemref = {refId = item.refId, count = item.count, charge = item.charge } --item.charge}
	Players[pid]:Save()
	testBR.DebugLog(2, "Removing item " .. tostring(item.refId))
	Players[pid]:LoadItemChanges({itemref}, enumerations.inventory.REMOVE)	
	
	WorldInstance:SetCurrentMpNum(mpNum)
	tes3mp.SetCurrentMpNum(mpNum)

	LoadedCells[cell]:InitializeObjectData(refIndex, refId)		
	LoadedCells[cell].data.objectData[refIndex].location = location			
	table.insert(LoadedCells[cell].data.packets.place, refIndex)
	testBR.DebugLog(2, "Sending data to other players")
	for onlinePid, player in pairs(Players) do
		if player:IsLoggedIn() then
			tes3mp.InitializeEvent(onlinePid)
			tes3mp.SetEventCell(cell)
			tes3mp.SetObjectRefId(refId)
			tes3mp.SetObjectCount(item.count)
			tes3mp.SetObjectCharge(item.charge)
			tes3mp.SetObjectRefNumIndex(0)
			tes3mp.SetObjectMpNum(mpNum)
			tes3mp.SetObjectPosition(location.posX, location.posY, location.posZ)
			tes3mp.SetObjectRotation(location.rotX, location.rotY, location.rotZ)
			tes3mp.AddWorldObject()
			tes3mp.SendObjectPlace()
		end
	end
	LoadedCells[cell]:Save()
	--]]
end

-- set the damage level for player at cell transition
-- TODO: make it so that damage level doesn't get cleared and re-applied on every cell transition
testBR.CheckCellDamageLevel = function(pid)
	testBR.DebugLog(1, "Checking new cell for PID " .. tostring(pid))
	playerCell = Players[pid].data.BRinfo.lastExteriorCell -- Handle interiors	

	-- danke StackOverflow
	x, y = playerCell:match("([^,]+),([^,]+)")

	foundLevel = false

	for level=1,#fogGridLimits do
		testBR.DebugLog(3, "GetCurrentDamageLevel: " .. tostring(testBR.GetCurrentDamageLevel(level)))
		testBR.DebugLog(3, "x == number: " .. tostring(type(tonumber(x)) == "number"))
		testBR.DebugLog(3, "y == number: " .. tostring(type(tonumber(y)) == "number"))
		testBR.DebugLog(3, "cell only in level: " .. tostring(testBR.IsCellOnlyInLevel({tonumber(x), tonumber(y)}, level)))
		if type(testBR.GetCurrentDamageLevel(level)) == "number" and type(tonumber(x)) == "number" 
		and type(tonumber(y)) == "number" and testBR.IsCellOnlyInLevel({tonumber(x), tonumber(y)}, level) then
			testBR.SetFogDamageLevel(pid, testBR.GetCurrentDamageLevel(level))
			foundLevel = true
			testBR.DebugLog(3, "Damage level for PID " .. tostring(pid) .. " is set to " .. tostring(currentFogStage - level))
			break
		end
	end
	
	if not foundLevel then
		testBR.SetFogDamageLevel(pid, 0)
	end
end

testBR.SetFogDamageLevel = function(pid, level)
	testBR.DebugLog(1, "Setting damage level for PID " .. tostring(pid))
	
	if Players[pid] == nil then
		return
	end

	if level == 0 then
		command = "player->removespell fogdamage1"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
		command = "player->removespell fogdamage2"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
		command = "player->removespell fogdamage3"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	elseif level == 1 then
		command = "player->addspell fogdamage1"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	elseif level == 2 then
		command = "player->addspell fogdamage2"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	elseif level == 3 then
		command = "player->addspell fogdamage3"
		logicHandler.RunConsoleCommandOnPlayer(pid, command)
	end
end


testBR.StartFogTimer = function(delay)
	testBR.DebugLog(1, "Setting shrink timer for " .. tostring(delay) .. " seconds")
	tes3mp.SendMessage(0,"Blight shrinking in " .. tostring(delay) .. " seconds.\n", true)
	fogTimer = tes3mp.CreateTimerEx("BRAdvanceFog", time.seconds(delay), "i", 1)
	tes3mp.StartTimer(fogTimer)
end

-- delay is for how long timer will last
-- init is to tell the function if it is being called for the first time. If not, then assume recursion
testBR.StartShrinkAlertTimer = function(delay)
	testBR.DebugLog(1, "Setting shrink timer alert for " .. tostring(delay) .. " seconds")
	shrinkAlertTimer = tes3mp.CreateTimerEx("HandleShrinkTimerAlertTimeout", time.seconds(delay), "i", 1)
	tes3mp.StartTimer(shrinkAlertTimer)
end


function HandleShrinkTimerAlertTimeout()
	for pid, player in pairs(Players) do
		if fogShrinkRemainingTime > 60 then
			tes3mp.MessageBox(pid, -1, "Blight shrinking in a minute!")
		else
			tes3mp.MessageBox(pid, -1, "Blight shrinking in " .. tostring(fogShrinkRemainingTime))
		end
	end

	-- now that minute warning is done, set timer for 10 second warning
	if fogShrinkRemainingTime > 60 then
		fogShrinkRemainingTime = 50 
	end
	
	-- stop making new timers if time is up
	if fogShrinkRemainingTime > 1 then
		-- for warning each second for last 10 seconds
		if fogShrinkRemainingTime <= 10 then
			fogShrinkRemainingTime = fogShrinkRemainingTime - 1
		end
		testBR.StartShrinkAlertTimer(fogShrinkRemainingTime)
	end
end

testBR.TEMP_StartShrinkAlertTimer = function(delay)
	testBR.DebugLog(1, "Setting shrink timer alert for " .. tostring(delay) .. " seconds")
	TEMP_shrinkAlertTimer = tes3mp.CreateTimerEx("TEMP_HandleShrinkTimerAlertTimeout", time.seconds(delay), "i", 1)
	tes3mp.StartTimer(TEMP_shrinkAlertTimer)
end

function TEMP_HandleShrinkTimerAlertTimeout()
	if (not roundInProgress) then
		return
	end

	for pid, player in pairs(Players) do
		if player ~= nil then
			tes3mp.MessageBox(pid, -1, "Blight will be shrinking soon!")
		end
	end
end


BRAdvanceFog = function()
	if (not roundInProgress) then
		return
	end

	testBR.DebugLog(1, "Advancing fog...")

	tes3mp.SendMessage(0,"Blight is shrinking.\n", true)
	currentFogStage = currentFogStage + 1
	if currentFogStage <= #fogStageDurations then
		testBR.StartFogTimer(fogStageDurations[currentFogStage])
		if fogStageDurations[currentFogStage] > 60 then
			fogShrinkRemainingTime = fogStageDurations[currentFogStage] - 60
		else
			fogShrinkRemainingTime = fogStageDurations[currentFogStage]
		end
		-- TODO: make this actually work before enabling it
		--testBR.StartShrinkAlertTimer(fogShrinkRemainingTime)
		testBR.TEMP_StartShrinkAlertTimer(fogShrinkRemainingTime)
	end

	testBR.UpdateMap()

	for pid, player in pairs(Players) do
		if player ~= nil and player:IsLoggedIn() then
			-- Send new map state to player
			testBR.SendMapToPlayer(pid)
			if Players[pid].data.BRinfo.state == 3 then
				-- Apply fog effects to players in cells that are now in fog
				testBR.CheckCellDamageLevel(pid)
			end
		end
	end
end


-- returns a list of squares that are to be used for fog levels
-- for example: { {{10, 0}, {0, 10}}, {{5, 5}, {5, 5}}, {} }
testBR.GenerateFogGrid = function(fogLevelSizes)	
	testBR.DebugLog(1, "Generating fog grid")
	generatedFogGrid = {}

	for level=1,#fogLevelSizes do
		testBR.DebugLog(0, "Generating level " .. tostring(level))
		generatedFogGrid[level] = {}
		
		-- handle the first item in the array (double check just to be sure)
		--if type(fogLevelSizes[level]) ~= "number" and fogLevelSizes[level] = "all" then
		-- or lol, we can just check if this is first time going through the loop
		-- this does assume that config is not messed up, that first entry is meant to be whole area
		if level == 1 then
			table.insert(generatedFogGrid[level], {mapBorders[1][1], mapBorders[1][2]})
			table.insert(generatedFogGrid[level], {mapBorders[2][1], mapBorders[2][2]})
		else
			-- check out some stuff about previous level
			xIncludesZero = 0
			yIncludesZero = 0
			-- check if min X and max X are both positive or both negative
			-- because if they are not, it means that one of cells in X range is also {0, y}, which must be counted in the length as well
			if testBR.DoNumbersHaveSameSign(generatedFogGrid[level-1][1][1], generatedFogGrid[level-1][2][1]) then
				xIncludesZero = 1
			end
			-- same for Y
			if testBR.DoNumbersHaveSameSign(generatedFogGrid[level-1][1][2], generatedFogGrid[level-1][2][2]) then
				yIncludesZero = 1
			end

			previousXLength = math.abs(generatedFogGrid[level-1][1][1]) + math.abs(generatedFogGrid[level-1][2][1]) + xIncludesZero
			previousYLength = math.abs(generatedFogGrid[level-1][1][2]) + math.abs(generatedFogGrid[level-1][2][2]) + yIncludesZero

			-- figure out if there is space for next level
			-- -1 because we are checking if new size fits into a square that is one cell smaller from both sides
			if fogLevelSizes[level] < previousXLength - 1 and fogLevelSizes[level] < previousYLength - 1 then
				-- all right, looks like it will fit
				-- now we can even try to add "border" that is one cell wide, so that edges of previous level and new level don't touch
				cellBorder = 0
				if fogLevelSizes[level] < previousXLength - 2 and fogLevelSizes[level] < previousYLength - 2 then
					testBR.DebugLog(2, "Level " .. tostring(level) .. " can get a cell-wide border")
					cellBorder = 1
				end
			
			-- this gives available area for the whole level
			-- {minX, maxX}
			availableVerticalArea = {generatedFogGrid[level-1][1][1] + 1 + cellBorder, generatedFogGrid[level-1][2][1] - 1 - cellBorder}
			-- {minY, maxY}
			availableHorisontalArea = {generatedFogGrid[level-1][1][2] + 1 + cellBorder, generatedFogGrid[level-1][2][2] - 1 - cellBorder}

			-- but now we need to determine what is the available area for the bottom left cell from which the whole level will be extrapolated from
			-- we leave minX as it is, but we subtract level size from the maxX
			availableCornerAreaX = {availableVerticalArea[1], availableVerticalArea[2] - fogLevelSizes[level]}
			-- same for Y
			availableCornerAreaY = {availableHorisontalArea[1], availableHorisontalArea[2] - fogLevelSizes[level]}
			
			-- choose random cell in the available area
			newX = math.random(availableCornerAreaX[1],availableCornerAreaX[2])
			newY = math.random(availableCornerAreaY[1],availableCornerAreaY[2])
			
			-- save bottom left corner
			table.insert(generatedFogGrid[level], {newX, newY})
			-- save top right corner
			table.insert(generatedFogGrid[level], {newX + fogLevelSizes[level], newY + fogLevelSizes[level]})
			testBR.DebugLog(2, "" .. tostring(level) .. " goes from " .. tostring(newX) .. ", " .. tostring(newY) .. " to " ..
				tostring(newX + fogLevelSizes[level]) .. ", " .. tostring(newY + fogLevelSizes[level]))
			-- lol no place to add the level. Who made this config?
			else
				testBR.DebugLog(2, "Given level size does not fit into previous level, skipping this one")
				-- TODO: lol this will actually break, since this for loop does not account for missing data
				-- so just don't make bad configs until this gets implemented :^^^^)
			end
		end
	end

	return generatedFogGrid
end

-- returns true if cell is part of level
testBR.IsCellInLevel = function(cell, level)
	testBR.DebugLog(2, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is in level " .. tostring(level))
	-- check if cell is in level range
	if fogGridLimits[level] and testBR.IsCellInRange(cell, fogGridLimits[level][1], fogGridLimits[level][2]) then
		return true
	end
	return false
end

-- basically same function as above, only with added exclusivity check
-- returns true if cell is part of level
-- TODO: make this by implementing an "isExclusive" argument instead of having two seperate functions
testBR.IsCellOnlyInLevel = function(cell, level)
	testBR.DebugLog(2, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is only in level " .. tostring(level))
	-- check if cell is in level range
	if fogGridLimits[level] and testBR.IsCellInRange(cell, fogGridLimits[level][1], fogGridLimits[level][2]) then
		-- now watch this: check if further levels exist and that cell does not actually belong to that further level
		if fogGridLimits[level+1] and testBR.IsCellInRange(cell, fogGridLimits[level+1][1], fogGridLimits[level+1][2]) then
			return false
		end		
		return true
	end
	return false
end

-- returns true if cell is inside the rectangle defined by given coordinates
testBR.IsCellInRange = function(cell, topRight, bottomLeft)
	if cell == nil then
		return
	end
	testBR.DebugLog(2, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is inside the "
		 .. tostring(topRight[1]) .. ", " .. tostring(topRight[2]) .. " - " .. tostring(bottomLeft[1]) .. ", " .. tostring(bottomLeft[2]) .. " rectangle")
	if cell[1] >= topRight[1] and cell[1] <= bottomLeft[1] and cell[2] >= topRight[2] and cell[2] <= bottomLeft[2] then
		return true
	end
	return false
end

testBR.DoNumbersHaveSameSign = function(number1, number2)
	if string.sub(tostring(number1), 1, 1) == string.sub(tostring(number2), 1, 1) then
		return true
	end
	return false
end

testBR.GetCurrentDamageLevel = function(level)
	testBR.DebugLog(1, "Looking up damage level for level " .. tostring(level))
	if currentFogStage - level > #fogDamageValues then
		return fogDamageValues[#fogDamageValues]
	else
		return fogDamageValues[currentFogStage - level]
	end
end

testBR.UpdateMap = function()
	testBR.DebugLog(1, "Updating map to fog level " .. tostring(currentFogStage))
	tes3mp.ClearMapChanges()

	for levelIndex=1,#fogGridLimits do
		-- at this point I am just banging code together until it works
		-- got lucky with the first condition, added second condition in order to limit logic only to relevant levels
		if levelIndex - currentFogStage < #fogDamageValues and fogDamageValues[currentFogStage - levelIndex] ~= nil then
			testBR.DebugLog(2, "Level " .. tostring(levelIndex) .. " gets fog level " .. tostring(fogDamageValues[currentFogStage - levelIndex]))
			
			-- iterate through all cells in this level
			for x=fogGridLimits[levelIndex][1][1],fogGridLimits[levelIndex][2][1] do
				for y=fogGridLimits[levelIndex][1][2],fogGridLimits[levelIndex][2][2] do
					-- actually, instead of using IsCell**Only**InLevel() we can avoid checking cells which obviously are in the level
					-- instead, we just check if cells are not in the next level. Same thing that above mentioned function would do,
					-- but we do it on smaller set of cells
					-- so it's "is this the last level OR (is there next level AND cell is not part of next level)"		
					if not fogGridLimits[levelIndex+1] or (fogGridLimits[levelIndex+1] and not testBR.IsCellInLevel({x, y}, levelIndex+1)) then
						tes3mp.LoadMapTileImageFile(x, y, fogFilePaths[currentFogStage - levelIndex])
					end
				end
			end
		end 
	end
end

testBR.SendMapToPlayer = function(pid)
	testBR.DebugLog(1, "Sending map to PID " .. tostring(pid))
	tes3mp.SendWorldMap(pid)
end

testBR.OnCellLoad = function(pid)

end

-- Remove dead player from match, broadcast death notification and check for victory
testBR.ProcessDeath = function(pid)
	if roundInProgress and Players[pid].data.BRinfo.state == 3 then -- Player was in match
		-- Display death to everyone
		for i, player in pairs(Players) do
			tes3mp.MessageBox(i, -1, Players[pid].data.login.name .. " died. " .. tostring(testBR.TableLen(playerList)-1) .. " player(s) remaining")
		end

		testBR.DropAllItems(pid)
		table.remove(playerList, pid)
		testBR.CheckVictoryConditions()

		testBR.SetPlayerState(pid, 0)
	end
	testBR.SetFogDamageLevel(pid, 0)
	Players[pid]:Save()
end

testBR.VerifyPlayerData = function(pid)
	testBR.DebugLog(1, "Verifying player data for " .. tostring(Players[pid]))
	
	if Players[pid].data.BRinfo == nil then
		BRinfo = {}
		BRinfo.matchId = 0
		BRinfo.state = 0 -- 0 = not in BR, 1 = in lobby, 2 = ready, 3 = in match
		BRinfo.chosenSpawnPoint = nil
		BRinfo.team = 0
		BRinfo.airMode = 0
		BRinfo.lastExteriorCell = "0, 0" -- Used to apply fog effects even in interiors
		BRinfo.totalKills = 0
		BRinfo.totalDeaths = 0		
		BRinfo.wins = 0
		BRinfo.BROutfit = {} -- used to hold data about player's chosen outfit
		BRinfo.secretNumber = math.random(100000,999999) -- used for verification
		Players[pid].data.BRinfo = BRinfo
		Players[pid]:Save()
	end
end

-- Called from local PlayerInit to reset characters for each new match
testBR.ResetCharacter = function(pid)
	testBR.DebugLog(1, "Resetting stats for " .. Players[pid].data.login.name .. ".")

	-- Reset battle royale
	Players[pid].data.BRinfo.team = 0
	testBR.SetPlayerState(pid, 2)
	
	-- Reset player level
	Players[pid].data.stats.level = defaultStats.playerLevel
	Players[pid].data.stats.levelProgress = 0

	-- Reset bounty
	Players[pid].data.stats.bounty = 0
	
	-- Reset player attributes
	for name in pairs(Players[pid].data.attributes) do
		Players[pid].data.attributes[name].base = defaultStats.playerAttributes
		Players[pid].data.attributes[name].skillIncrease = 0
	end

	Players[pid].data.attributes.Speed.base = defaultStats.playerSpeed
	Players[pid].data.attributes.Luck.base = defaultStats.playerLuck
	
	-- Reset player skills
	for name in pairs(Players[pid].data.skills) do
		Players[pid].data.skills[name].base = defaultStats.playerSkills
		Players[pid].data.skills[name].progress = 0
	end

	Players[pid].data.skills.Acrobatics.base = defaultStats.playerAcrobatics
	Players[pid].data.skills.Marksman.base = defaultStats.playerMarksman

	-- Reset player stats
	Players[pid].data.stats.healthBase = defaultStats.playerHealth
	Players[pid].data.stats.healthCurrent = defaultStats.playerHealth
	Players[pid].data.stats.magickaBase = defaultStats.playerMagicka
	Players[pid].data.stats.magickaCurrent = defaultStats.playerMagicka
	Players[pid].data.stats.fatigueBase = defaultStats.playerFatigue
	Players[pid].data.stats.fatigueCurrent = defaultStats.playerFatigue

	
	--testBR.DebugLog(2, "Stats all reset")
	
	-- Reload player with reset information
	Players[pid]:Save()
	Players[pid]:LoadLevel()
	--testBR.DebugLog(2, "Player level loaded")
	Players[pid]:LoadAttributes()
	--testBR.DebugLog(2, "Player attributes loaded")
	Players[pid]:LoadSkills()
	--testBR.DebugLog(2, "Player skills loaded")
	Players[pid]:LoadStatsDynamic()
	--testBR.DebugLog(2, "Dynamic stats loaded")
end

testBR.EndCharGen = function(pid)
	testBR.DebugLog(1, "Ending character generation for " .. tostring(pid))
	Players[pid]:SaveLogin()
	Players[pid]:SaveCharacter()
	Players[pid]:SaveClass()
	Players[pid]:SaveStatsDynamic()
	Players[pid]:SaveEquipment()
	Players[pid]:SaveIpAddress()
	Players[pid]:CreateAccount()
	testBR.VerifyPlayerData(pid)

	testBR.SetPlayerState(pid, 0)
end

-- check if player is last one
testBR.CheckVictoryConditions = function()
	if roundInProgress then
		if testBR.TableLen(playerList) == 0 then
			tes3mp.SendMessage(0, color.Green .. "Everyone died!\n", true)
			testBR.EndMatch()
		elseif testBR.TableLen(playerList) == 1 then
			tes3mp.SendMessage(0, color.Green .. Players[playerList[1]].data.login.name .. " won the match!\n", true)
			Players[playerList[1]].data.BRinfo.wins = Players[playerList[1]].data.BRinfo.wins + 1
			Players[playerList[1]]:Save()
			testBR.EndMatch()
		end
	end
end

-- End match
testBR.EndMatch = function()
	roundInProgress = false
	for pid, player in pairs(Players) do
		-- Remove player from round participants
		testBR.SetPlayerState(pid, 0)
	end
end

-- Force match end
testBR.AdminEndMatch = function(pid)
	if Players[pid]:IsAdmin() then
		testBR.EndMatch()
		if roundInProgress then
			tes3mp.SendMessage(0, color.Green .. "Match ended by an admin\n", true)
		else
			tes3mp.SendMessage(pid, "There is no match to end\n", false)
		end
	else
		tes3mp.SendMessage(pid, "You don't have permission to do this\n", false)
	end
end

-- Force fog to advance TODO: Restrict this to admins and fix timers
testBR.ForceNextFog = function(pid)
	if #fogStageDurations >= currentFogStage + 1 then
		BRAdvanceFog()
	end
end

-- Change player state (0 = spectator, 1 = in lobby, 2 = ready, 3 = in match)
testBR.SetPlayerState = function(pid, newState)
	Players[pid].data.BRinfo.state = newState
	testBR.RefreshPlayerState(pid)
	Players[playerList[1]]:Save()
end

-- Apply effects to the corresponding player
testBR.RefreshPlayerState = function(pid)
	if Players[pid].data.BRinfo.state == 0 then -- Spectator
		testBR.SetSlowFall(pid, false)
		Players[pid].data.attributes["Speed"].base = defaultStats.playerSpeed
		testBR.SetGhost(pid, true)

	elseif Players[pid].data.BRinfo.state == 1 then -- In lobby
		if tes3mp.GetCell(pid) ~= lobbyCell then -- Move player back to lobby
			testBR.SpawnPlayer(pid, true)
			testBR.SetSlowFall(false)
			Players[pid].data.attributes["Speed"].base = defaultStats.playerSpeed
			testBR.SetGhost(pid, false)
		end

	elseif Players[pid].data.BRinfo.state == 2 then -- Ready
		testBR.SetGhost(pid, false)

		if tes3mp.GetCell(pid) ~= lobbyCell then -- Move player back to lobby
			testBR.SpawnPlayer(pid, true)
		end
		testBR.SetSlowFall(false)
		Players[pid].data.attributes["Speed"].base = defaultStats.playerSpeed

	else -- In match
		if (not roundInProgress) or Players[pid].data.BRinfo.matchId ~= matchId then
			testBR.SetPlayerState(pid, 0)
		else
			testBR.SetGhost(pid, false)
		end
	end
end

-- Apply RefreshPlayerState on all players
testBR.RefreshAllPlayersState = function()
	for pid, player in pairs(Players) do
		testBR.RefreshPlayerState(pid)
	end
end

-- This is basically hijacking OnPlayerTopic event signal for our own purposes
-- OnPlayerTopic because it doesn't play any role in purely PvP gamemode where no NPCs are present
-- TODO: figure out how to add new event without messing up with server core, so that all the code is only in this file
customEventHooks.registerValidator("OnPlayerTopic", function(eventStatus, pid)
	return customEventHooks.makeEventStatus(false,true)
end)

customEventHooks.registerHandler("OnPlayerTopic", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.HandleAirMode(pid)
	end
end)

customEventHooks.registerHandler("OnPlayerFinishLogin", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.VerifyPlayerData(pid)
		testBR.RefreshPlayerState(pid)
	end
end)

customEventHooks.registerHandler("OnPlayerDeath", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.ProcessDeath(pid)
	end
end)

customEventHooks.registerHandler("OnCellLoad", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.OnCellLoad(pid)
	end
end)

customEventHooks.registerHandler("OnPlayerCellChange", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.ProcessCellChange(pid)
	end
end)

customEventHooks.registerHandler("OnPlayerBounty", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.ProcessCellChange(pid)
	end
end)

customEventHooks.registerHandler("OnPlayerEndCharGen", function(eventstatus, pid)
	if Players[pid] ~= nil then
		testBR.DebugLog(1, "++++ Newly created: " .. tostring(pid))
		testBR.EndCharGen(pid)
	end
end)


customEventHooks.registerHandler("OnPlayerResurrect", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		if Players[pid] == nil then
			testBR.DebugLog(3, "Nil player respawned?!")
			return
		end

		if matchProposalInProgress then
			-- Just respawn players in lobby
		else
			-- TODO: Spectator effects (disable combat but allow fun interactions)
			testBR.SetPlayerState(0)
			tes3mp.MessageBox(pid, -1, "You're now a spooky ghost!")
		end

		testBR.CheckVictoryConditions() -- Just in case
	end
end)

-- custom validator for cell change
customEventHooks.registerValidator("OnPlayerCellChange", function(eventStatus, pid)
	-- Prevent players in lobby from leaving it
	if matchProposalInProgress and tes3mp.GetCell(pid) ~= lobbyCell and Players[pid].data.BRinfo.state >= 1 then
		tes3mp.MessageBox(pid, -1, "You cannot leave the lobby!")
		testBR.SpawnPlayer(pid, true)
        return customEventHooks.makeEventStatus(false, true)
	end

	--[[-- Allow player to spawn in lobby
	if tes3mp.GetCell(pid) == lobbyCell and (not roundInProgress) then
		return customEventHooks.makeEventStatus(true,true)
	end--]]

	if (not allowInteriors) and roundInProgress and Players[pid].data.BRinfo.state == 2 then
		_, _, cellX, cellY = string.find(tes3mp.GetCell(pid), patterns.exteriorCell)
    	if cellX == nil or cellY == nil then
			testBR.DebugLog(1, "Cell is not external and can not be entered")
			tes3mp.MessageBox(pid, -1, "You cannot enter interiors!")
			Players[pid].data.location.posX = tes3mp.GetPreviousCellPosX(pid)
			Players[pid].data.location.posY = tes3mp.GetPreviousCellPosY(pid)
			Players[pid].data.location.posZ = tes3mp.GetPreviousCellPosZ(pid)
			Players[pid]:LoadCell()
			return customEventHooks.makeEventStatus(false,true)
		end
	end

	return customEventHooks.makeEventStatus(true,true)
end)

testBR.PrintPlayerCoords = function(pid)
	tes3mp.SendMessage(pid, Players[pid].data.login.name .. " is at " .. tostring(tes3mp.GetPosX(pid)) .. ", "
	.. tostring(tes3mp.GetPosY(pid)) .. ", " .. tostring(tes3mp.GetPosZ(pid)) .. " in cell \"" .. tes3mp.GetCell(pid) .. "\"\n")
end

testBR.AddLootSpawn = function(pid, args) -- TODO: Restrict this to a certain permission level & check if the table exists
	if roundInProgress then
		tes3mp.SendMessage(pid, color.Red .. "Cannot edit loot spawn points during a match!\n", false)
	else
		local lootTable = args[2]
		if lootTable == nil then
			tes3mp.SendMessage(pid, color.Red .. "Missing loot table argument\n", false)
			return
		end
		testBRLootManager.AddLocation(lootTable, tes3mp.GetCell(pid), tes3mp.GetPosX(pid), tes3mp.GetPosY(pid), tes3mp.GetPosZ(pid))
		testBRLootManager.SaveToDrive()
		tes3mp.SendMessage(pid, color.Green .. "Added a spawn point for " .. lootTable .. "!\n", false)
	end
end

testBR.AddLootSpawnCommon = function(pid)
	testBR.AddLootSpawn(pid, "common")
end
testBR.AddLootSpawnRare = function(pid)
	testBR.AddLootSpawn(pid, "rare")
end
testBR.AddLootSpawnLegendary = function(pid)
	testBR.AddLootSpawn(pid, "legendary")
end

testBR.AdminTest = function(pid, a)
	for machin, truc in pairs(a) do
		tes3mp.SendMessage(pid, tostring(machin) .. ": " .. tostring(truc) .. "\n", false)
	end
	if Players[pid]:IsAdmin() then
		testBRLootManager.AddLocation("common", tes3mp.GetCell(pid), tes3mp.GetPosX(pid), tes3mp.GetPosY(pid), tes3mp.GetPosZ(pid))
		testBRLootManager.SaveToDrive()
	end
end

customCommandHooks.registerCommand("newmatch", testBR.ProposeMatch)
customCommandHooks.registerCommand("forcestartmatch", testBR.StartRound)
customCommandHooks.registerCommand("join", testBR.PlayerJoin)
customCommandHooks.registerCommand("ready", testBR.PlayerReady)
customCommandHooks.registerCommand("forcenextfog", BRAdvanceFog)
customCommandHooks.registerCommand("forceend", testBR.AdminEndMatch)
customCommandHooks.registerCommand("here", testBR.PrintPlayerCoords)

customCommandHooks.registerCommand("loot", testBR.AddLootSpawn)
customCommandHooks.registerCommand("xc", testBR.AddLootSpawnCommon)
customCommandHooks.registerCommand("xr", testBR.AddLootSpawnRare)
customCommandHooks.registerCommand("xl", testBR.AddLootSpawnLegendary)
customCommandHooks.registerCommand("x", testBR.AdminTest)

-- Clear match data on server start
testBR.ClearLobby()

return testBR
