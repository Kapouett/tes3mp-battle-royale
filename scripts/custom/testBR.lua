
-- Battle Royale game mode by testman, modified by Kapouett
-- v0.3

-- Don't forget to read the README.MD!

-- #TODO:
-- find a decent name for overall project
-- untangle all the spaghetti code
-- - A LOT OF IT
-- -- HOLY SHIT I CAN'T STRESS ENOUGH HOW MUCH FIXING AND IMPROVING THIS CODE NEEDS
-- - order functions in the order that makes sense
-- - figure out what / if there is a difference between methods and functions in LUA
-- -- figure out how to make timers execute functions with given arguments instead of relying on global variables
-- figure out how the zone-shrinking logic should actually work
-- implement said decent zone-shrinking logic
-- - make shrinking take some time instead of being an instant event
-- - make zone circle-shaped
-- make players unable to open vanilla containers
-- implement victory condition logic
-- implement custom containers that can be opened by players
-- think about possible revival mechanics
-- restore fatigue constant effect
-- implement hybrid playerzone shrinking system:
-- - use cell based system at the start
-- - switch to coordinates-math-distance-circle at the end
-- longer drop speed boost time
-- find a decent name



--#region =================== DESIGN DOCUMENT PART ===================

--[[
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
- Disable collision on spectators
- Disable item picking and dropping on spectators
- Add customization options (fix race/class/birthsign bonuses)
- Fix chameleon not showing on other players
- Fix slowfall not being disabled
]]

--#endregion

TestBR = {}

-- Load config file
local brConfig = require("custom/testBRConfig")

-- Load GUI
local brGUI = require("custom/testBR/gui")

local lootManager = require("custom/testBR/testBRLootManager")

local brRecords = require("custom/testBR/records")

--#region ====================== GLOBAL VARIABLES ======================

local PLAYER_STATE = { SPECT = 0, JOINED = 1, READY = 2, INMATCH = 3 }
TestBR.PLAYER_STATE = PLAYER_STATE -- Export enum

local GAME_STATE = { NONE = 0, LOBBY = 1, INMATCH = 2 }
TestBR.GAME_STATE = GAME_STATE -- Export enum

local gameState = GAME_STATE.NONE

-- unique identifier for the match
local matchId = 0

-- keep track of which players are in a match
local playerList = {}

-- cells visited during this match, used for loot spawning
local visitedCells = {}

-- used to track the fog progress
local currentFogStage = 1

-- used to store ony bottom left and top right corner of each level
local fogGridLimits = {}

-- Seconds left to display on the alert for fog shrinking
local fogAlertRemainingTime = 0

local fogTimer

local fogAlertTimer

local fogFilePaths = {brConfig.fogWarnFilePath, brConfig.fog1FilePath, brConfig.fog2FilePath, brConfig.fog3FilePath}
--#endregion


--#region ====================== MISC ======================

-- Used to easily regulate the level of information when debugging
function TestBR.DebugLog(debugLevel, message)
	if debugLevel >= brConfig.debugLevel then
		tes3mp.LogMessage(math.max(debugLevel, 2), "BR: " .. message)
	end
end

-- Used for match IDs and for RNG seed
local time = require("time")

-- Used for generation of random numbers
math.randomseed(os.time())

-- Get the number of non-nil entries in a table
function TestBR.TableLen(T)
	local count = 0
	for k, v in pairs(T) do
		if v ~= nil then
			count = count + 1
		end
	end
	return count
end

--#endregion


--#region =================== GAME STATE ===================

-- Create a new match and auto-join the lobby
function TestBR.CreateLobby(pid)
	if TestBR.gameState == GAME_STATE.INMATCH then
		tes3mp.SendMessage(pid, brConfig.strMatchAlreadyRunning .. "\n", false)
		return
	elseif TestBR.gameState == GAME_STATE.LOBBY then
		tes3mp.SendMessage(pid, brConfig.strProposalAlreadyRunning .. "\n", false)
		return
	end

	TestBR.DestroyLobby()

	-- Generate match id
	matchId = os.time()

	TestBR.DebugLog(2, "Handling new round proposal from PID " .. tostring(pid))
	TestBR.gameState = GAME_STATE.LOBBY
	tes3mp.SendMessage(pid, brConfig.strNewMatchProposal .. "\n", true)
	local matchProposalTimer = tes3mp.CreateTimerEx("BRLobbyExpired", time.seconds(brConfig.matchProposalTime), "i", 1)
	tes3mp.StartTimer(matchProposalTimer)

	-- Auto-join match proposer
	TestBR.PlayerJoinLobby(pid)
end

-- Proposal timer expired
function BRLobbyExpired()
	if TestBR.gameState == GAME_STATE.LOBBY then
		tes3mp.SendMessage(0, color.Red .. "Match proposal timer expired!" .. color.White .. " Use /".. brConfig.cmdNewMatch .." to try again.\n", true)

		TestBR.DestroyLobby()
	end
end

-- Remove all players form lobby
function TestBR.DestroyLobby()
	if TestBR.gameState ~= GAME_STATE.LOBBY then return end

	TestBR.DebugLog(2, "Ending current match proposal")

	-- Remove players from lobby
	for pid, player in pairs(Players) do
		TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)
	end

	TestBR.gameState = GAME_STATE.NONE
end

-- Begin match
function TestBR.StartRound()
	if TestBR.gameState == GAME_STATE.INMATCH then
		TestBR.DebugLog(3, "Attempted to start a match, but one in already running")
		return
	end

	-- Stop timers from previous match
	TestBR.StopFogTimers()

	TestBR.DebugLog(2, "Starting a battle royale round with ID " .. tostring(TestBR.roundID))

	playerList = {}

	visitedCells = {}

	TestBR.LoadLootTables()

	fogGridLimits = TestBR.GenerateFogGrid(brConfig.fogLevelSizes)

	currentFogStage = 1

	TestBR.ResetWorld()

	-- Make sure no one enters the game as a corpse (died in lobby)
	for pid, player in pairs(Players) do
		if Players[pid].resurrectTimer ~= nil then
			TestBR.ResurrectPlayer(pid)
		end
	end

	TestBR.gameState = GAME_STATE.INMATCH

	for pid, player in pairs(Players) do
		TestBR.PlayerStartRound(pid)
	end

	local message = string.gsub( brConfig.strMatchStart, "{x}", tostring(TestBR.CountPlayersInState(PLAYER_STATE.INMATCH)) )
	tes3mp.SendMessage(0, message .. "\n", true)

	TestBR.StartFogTimer(brConfig.fogStageDurations[currentFogStage])

	-- Clean map
	tes3mp.ClearMapChanges()
	TestBR.CleanMap()
	tes3mp.SendWorldMap(tes3mp.GetLastPlayerId(), true, false)
end

-- Check if the match should end (0 or 1 player left)
function TestBR.CheckVictoryConditions()
	if TestBR.gameState == GAME_STATE.INMATCH then
		local count = 0
		local playerName = ""
		local player = 0

		for name, val in pairs(playerList) do
			if val ~= nil then
				count = count + 1 -- #TODO: Only count a player if they are online (?)
				playerName = name
			end
		end

		-- If the winner is not online, deny their victory
		if count == 1 then
			for onlinePid, player in pairs(Players) do
				if player ~= nil and player.data.login.name == playerName and player:IsLoggedIn() then
					player = onlinePid
					break
				end
			end
			count = 0
		end

		if count == 0 then
			tes3mp.SendMessage(0, color.Green .. brConfig.strEndNoWinner .. "\n", true)
			TestBR.EndMatch()
		elseif count == 1 then
			tes3mp.SendMessage(0, color.Green .. string.gsub(brConfig.strEndWin, "{x}", playerName) .. "\n", true)
			-- Increment wins count for that player
			Players[player].data.BRinfo.wins = Players[player].data.BRinfo.wins + 1
			Players[player]:Save()
			TestBR.EndMatch()
		end
	end
end

-- End match
function TestBR.EndMatch()
	TestBR.gameState = GAME_STATE.NONE
	TestBR.StopFogTimers()
	for pid, player in pairs(Players) do
		-- Remove player from round participants
		TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)
	end
end

-- Force match end
function TestBR.AdminEndMatch(pid)
	if Players[pid]:IsAdmin() then
		if TestBR.gameState == GAME_STATE.INMATCH then
			TestBR.EndMatch()
			tes3mp.SendMessage(0, color.Green .. "Match ended by an admin\n", true)
		else
			tes3mp.SendMessage(pid, "There is no match to end\n", false)
		end
	else
		tes3mp.SendMessage(pid, "You don't have permission to do this\n", false)
	end
end

--#endregion


--#region =================== PLAYER STATE ===================

-- How many players are in a specific BR state
function TestBR.CountPlayersInState(state)
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

-- Join lobby (set state to JOINED)
function TestBR.PlayerJoinLobby(pid)
	if Players[pid] == nil or (not Players[pid]:IsLoggedIn()) then
		return
	end

	TestBR.DebugLog(2, "Setting state for " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if TestBR.gameState == GAME_STATE.INMATCH then
			tes3mp.SendMessage(0, brConfig.strMatchAlreadyRunning .. "\n", false)
			return
		elseif TestBR.gameState ~= GAME_STATE.LOBBY then
			tes3mp.SendMessage(0, brConfig.strNoCurrentMatch .. "\n", false)
			return
		elseif Players[pid].data.BRinfo.state == PLAYER_STATE.SPECT then
			Players[pid].data.BRinfo.matchId = matchId

			tes3mp.SendMessage(0, Players[pid].data.login.name .. " joined the lobby!\n", true)
			tes3mp.SendMessage(pid, "Use /" .. brConfig.cmdReady .. " when you're ready to start!\n", false)
			TestBR.SetPlayerState(pid, PLAYER_STATE.JOINED)
		elseif Players[pid].data.BRinfo.state == PLAYER_STATE.JOINED then
			tes3mp.SendMessage(pid, "You already joined, use /" .. brConfig.cmdReady .. "!\n")
		elseif Players[pid].data.BRinfo.state == PLAYER_STATE.READY then
			tes3mp.SendMessage(pid, "You already joined and marked as ready!\n")
		end
	end
end

-- Player Ready (set state to READY)
function TestBR.PlayerSetReady(pid)
	if Players[pid] == nil or (not Players[pid]:IsLoggedIn()) then
		return
	elseif TestBR.gameState == GAME_STATE.INMATCH then
		tes3mp.SendMessage(pid, brConfig.strMatchAlreadyRunning .. "\n", false)
		return
	end
	if TestBR.gameState == GAME_STATE.LOBBY then
		-- Force player to join
		if Players[pid].data.BRinfo.state == PLAYER_STATE.SPECT then
			TestBR.PlayerJoinLobby(pid)
		end
		if Players[pid].data.BRinfo.state == PLAYER_STATE.JOINED then
			TestBR.SetPlayerState(pid, PLAYER_STATE.READY)
			tes3mp.SendMessage(pid, color.Yellow .. string.gsub(brConfig.strPlayerReady, "{x}", Players[pid].data.login.name) .. "\n", true)

			-- Start match if everyone is ready
			if TestBR.CountPlayersInState(PLAYER_STATE.JOINED) <= 0 then
				TestBR.StartRound()
			end

		elseif Players[pid].data.BRinfo.state == PLAYER_STATE.READY then
			tes3mp.SendMessage(pid, "You are already ready.\n", false)
		end
	else
		tes3mp.SendMessage(pid, brConfig.strNoCurrentMatch .. "\n", false)
	end
end

-- Start the match for a player
function TestBR.PlayerStartRound(pid)
	TestBR.DebugLog(0, "Starting initial BR setup for PID " .. tostring(pid))
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() and Players[pid].data.BRinfo.state == PLAYER_STATE.READY then
		Players[pid].data.BRinfo.team = 0

		TestBR.PlayerSpells(pid)

		TestBR.ClearInventory(pid)

		TestBR.SetFogDamageLevel(pid, 0)

		TestBR.ResetCharacter(pid)

		TestBR.SpawnPlayer(pid, false)

		TestBR.StartAirdrop(pid)

		playerList[Players[pid].data.login.name] = true

		tes3mp.MessageBox(pid, -1, brConfig.strBeginMatch)

		TestBR.SetPlayerState(pid, PLAYER_STATE.INMATCH)
	end
end

-- Called from local PlayerStartRound to reset characters for each new match
function TestBR.ResetCharacter(pid)
	TestBR.DebugLog(0, "Resetting stats for " .. Players[pid].data.login.name .. ".")

	-- Reset player level
	Players[pid].data.stats.level = brConfig.defaultStats.playerLevel
	Players[pid].data.stats.levelProgress = 0

	-- Reset bounty
	Players[pid].data.fame.bounty = 0

	-- Reset player attributes
	for name in pairs(Players[pid].data.attributes) do
		Players[pid].data.attributes[name].base = brConfig.defaultStats.playerAttributes
		Players[pid].data.attributes[name].skillIncrease = 0
	end

	Players[pid].data.attributes.Speed.base = brConfig.defaultStats.playerSpeed
	Players[pid].data.attributes.Luck.base = brConfig.defaultStats.playerLuck

	-- Reset player skills
	for name in pairs(Players[pid].data.skills) do
		Players[pid].data.skills[name].base = brConfig.defaultStats.playerSkills
		Players[pid].data.skills[name].progress = 0
	end

	Players[pid].data.skills.Acrobatics.base = brConfig.defaultStats.playerAcrobatics
	Players[pid].data.skills.Marksman.base = brConfig.defaultStats.playerMarksman

	-- Reset player stats
	Players[pid].data.stats.healthBase = brConfig.defaultStats.playerHealth
	Players[pid].data.stats.healthCurrent = brConfig.defaultStats.playerHealth
	Players[pid].data.stats.magickaBase = brConfig.defaultStats.playerMagicka
	Players[pid].data.stats.magickaCurrent = brConfig.defaultStats.playerMagicka
	Players[pid].data.stats.fatigueBase = brConfig.defaultStats.playerFatigue
	Players[pid].data.stats.fatigueCurrent = brConfig.defaultStats.playerFatigue


	-- Reload player with reset information
	Players[pid]:Save()
	Players[pid]:LoadLevel()
	Players[pid]:LoadAttributes()
	Players[pid]:LoadSkills()
	Players[pid]:LoadStatsDynamic()
	Players[pid]:LoadBounty()
end

-- Spawns the player in the lobby or drops them from the sky
function TestBR.SpawnPlayer(pid, spawnInLobby)
	TestBR.DebugLog(1, "Spawning player " .. tostring(pid))
	local chosenSpawnPoint
	if spawnInLobby then
		chosenSpawnPoint = {brConfig.lobbyCell, brConfig.lobbySpawn.posX, brConfig.lobbySpawn.posY, brConfig.lobbySpawn.posZ, 0}
		tes3mp.MessageBox(pid, -1, brConfig.strWelcomeToLobby)
	else
		-- TEST: use random spawn point for now
		local random_x = math.random(-40000,80000)
		local random_y = math.random(-40000,120000)
		TestBR.DebugLog(0, "Spawning player " .. tostring(pid) .. " at " .. tostring(random_x) .. ", " .. tostring(random_y))
		chosenSpawnPoint = {"0, 0", random_x, random_y, 30000, 0}
		Players[pid].data.BRinfo.airmode = 2
	end
	tes3mp.SetCell(pid, chosenSpawnPoint[1])
	tes3mp.SendCell(pid)
	tes3mp.SetPos(pid, chosenSpawnPoint[2], chosenSpawnPoint[3], chosenSpawnPoint[4])
	tes3mp.SetRot(pid, 0, chosenSpawnPoint[5])
	tes3mp.SendPos(pid)
end

-- Either enables or disables spectator mode for player
function TestBR.SetSpectator(pid, boolean)
	TestBR.DebugLog(1, "Setting spectator mode for PID " .. tostring(pid))
	if boolean then
		TestBR.AddSpell(pid, "br_spectator")
	else
		TestBR.RemoveSpell(pid, "br_spectator")
	end
end

function TestBR.GetPlayerState(pid)
	-- #TODO: Check if logged in
	return Players[pid].data.BRinfo.state
end

-- Change player state. This will also refresh the player
function TestBR.SetPlayerState(pid, newState)
	Players[pid].data.BRinfo.state = newState
	TestBR.RefreshPlayerState(pid)
	Players[pid]:Save()
end

-- Apply RefreshPlayerState on all players
function TestBR.RefreshAllPlayersState()
	for pid, player in pairs(Players) do
		TestBR.RefreshPlayerState(pid)
	end
end

-- Apply effects to the corresponding player
-- #TODO: Spectator effects (disable combat but allow fun interactions)
function TestBR.RefreshPlayerState(pid)
	if Players[pid].data.BRinfo.state == PLAYER_STATE.SPECT then -- Set player as spectator
		TestBR.SetSpectator(pid, true)
		TestBR.SetAirMode(pid, 0)

	elseif Players[pid].data.BRinfo.matchId ~= matchId then -- Player's matchId is different from current matchId, force into spectator
		TestBR.DebugLog(1, "Player's matchID doesn't match")
		TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)

	elseif Players[pid].data.BRinfo.state == PLAYER_STATE.JOINED then
		if tes3mp.GetCell(pid) ~= brConfig.lobbyCell then -- Move player back to lobby
			TestBR.SpawnPlayer(pid, true)
		end
		TestBR.SetSpectator(pid, false)
		TestBR.SetAirMode(pid, 0)

	elseif Players[pid].data.BRinfo.state == PLAYER_STATE.READY then
		if tes3mp.GetCell(pid) ~= brConfig.lobbyCell then -- Move player back to lobby
			TestBR.SpawnPlayer(pid, true)
		end
		TestBR.SetSpectator(pid, false)
		TestBR.SetAirMode(pid, 0)

	else -- In match
		if (TestBR.gameState ~= GAME_STATE.INMATCH) or Players[pid].data.BRinfo.matchId ~= matchId then
			TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)
		else
			TestBR.SetSpectator(pid, false)
		end
	end
end

-- Ensures a player has sane BR data
function TestBR.VerifyPlayerData(pid)
	TestBR.DebugLog(1, "Verifying player data for " .. tostring(Players[pid]))

	if Players[pid].data.BRinfo == nil then
		BRinfo = {}
		BRinfo.matchId = 0
		BRinfo.state = PLAYER_STATE.SPECT
		BRinfo.team = 0
		BRinfo.airMode = 0
		BRinfo.lastExteriorCell = "0, 0" -- Used to apply fog effects even in interiors
		BRinfo.totalKills = 0
		BRinfo.totalDeaths = 0
		BRinfo.wins = 0
		BRinfo.BROutfit = {} -- Used to hold data about player's chosen outfit
		BRinfo.secretNumber = math.random(100000,999999) -- Used for verification #TODO: What is this?
		Players[pid].data.BRinfo = BRinfo
		Players[pid]:Save()
	end
end

--#endregion


--#region =================== PLAYER SPELLS ===================

-- Clear player's spellbook #TODO and add feather and restore fatigue powers
function TestBR.PlayerSpells(pid)
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		Players[pid]:CleanSpellbook()
		Players[pid].data.selectedSpell = ""
		Players[pid].data.spellbook = {}
		Players[pid]:LoadSpellbook()
		Players[pid]:LoadSelectedSpell()
		tes3mp.ClearSpellbookChanges(pid)
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
		tes3mp.AddSpell(pid, "feather_power")
		tes3mp.AddSpell(pid, "restore_fatigue_power")
		tes3mp.SendSpellbookChanges(pid, false)
	end
end

-- Shortcut to add a single spell to a player's spellbook (don't use it for multiple spells)
function TestBR.AddSpell(pid, spell)
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		tes3mp.ClearSpellbookChanges(pid)
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
		tes3mp.AddSpell(pid, spell)
		tes3mp.SendSpellbookChanges(pid, true)
	end
end

-- Shortcut to remove a single spell from a player's spellbook (don't use it for multiple spells)
function TestBR.RemoveSpell(pid, spell)
	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		tes3mp.ClearSpellbookChanges(pid)
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.REMOVE)
		tes3mp.AddSpell(pid, spell)
		tes3mp.SendSpellbookChanges(pid, true)
	end
end

--#endregion


--#region =================== PLAYER INVENTORY ===================

-- Empty a player's inventory
function TestBR.ClearInventory(pid)
	Players[pid]:CleanInventory()
	Players[pid].data.inventory = {}
	Players[pid].data.equipment = {}

	TestBR.ApplyPlayerItems(pid)
end

-- Save changes and make items appear on player
function TestBR.ApplyPlayerItems(pid)
	Players[pid]:Save()
	Players[pid]:LoadInventory()
	Players[pid]:LoadEquipment()
end

function TestBR.DropAllItems(pid)
	TestBR.DebugLog(1, "Dropping all items for PID " .. tostring(pid))

	local z_offset = 5

	--for index, item in pairs(Players[pid].data.inventory) do
	local inventoryLength = #Players[pid].data.inventory
	if inventoryLength > 0 then
		for index=1,inventoryLength do
			TestBR.DropItem(pid, index, z_offset)
			z_offset = z_offset + 5
		end
	end
	TestBR.ClearInventory(pid)
end

-- inspired by code from from David-AW (https://github.com/David-AW/tes3mp-safezone-dropitems/blob/master/deathdrop.lua#L134)
-- and from rickoff (https://github.com/rickoff/Tes3mp-Ecarlate-Script/blob/0.7.0/DeathDrop/DeathDrop.lua
function TestBR.DropItem(pid, index, z_offset)

	local player = Players[pid]

	local item = player.data.inventory[index]

	if item == nil then return end

	local mpNum = WorldInstance:GetCurrentMpNum() + 1
	local cell = tes3mp.GetCell(pid)
	local location = {
		posX = tes3mp.GetPosX(pid), posY = tes3mp.GetPosY(pid), posZ = tes3mp.GetPosZ(pid) + z_offset,
		rotX = 0, rotY = 0, rotZ = math.random()*3.14
	}

	-- Randomize item position a little
	location.posX = location.posX + (math.random()*4.0)-2.0
	location.posY = location.posY + (math.random()*4.0)-2.0

	local refId = item.refId
	local refIndex =  0 .. "-" .. mpNum
	local itemref = {refId = item.refId, count = item.count, charge = item.charge }
	Players[pid]:Save()
	TestBR.DebugLog(0, "Removing item " .. tostring(item.refId))
	Players[pid]:LoadItemChanges({itemref}, enumerations.inventory.REMOVE)	

	WorldInstance:SetCurrentMpNum(mpNum)
	tes3mp.SetCurrentMpNum(mpNum)

	LoadedCells[cell]:InitializeObjectData(refIndex, refId)		
	LoadedCells[cell].data.objectData[refIndex].location = location			
	table.insert(LoadedCells[cell].data.packets.place, refIndex)
	TestBR.DebugLog(0, "Sending data to other players")

	tes3mp.InitializeEvent(pid)
	tes3mp.SetEventCell(cell)
	tes3mp.SetObjectRefId(refId)
	tes3mp.SetObjectCount(item.count)
	tes3mp.SetObjectCharge(item.charge)
	tes3mp.SetObjectRefNumIndex(0)
	tes3mp.SetObjectMpNum(mpNum)
	tes3mp.SetObjectPosition(location.posX, location.posY, location.posZ)
	tes3mp.SetObjectRotation(location.rotX, location.rotY, location.rotZ)
	tes3mp.AddWorldObject()
	tes3mp.SendObjectPlace(true, false)

	LoadedCells[cell]:Save()
end

--#endregion


--#region =================== AIR DROP ===================

function TestBR.StartAirdrop(pid)
	Players[pid].data.BRinfo.airMode = 2
	TestBR.HandleAirMode(pid)
end

-- Apply a player's air-mode to its value and start timers to lower it if needed
function TestBR.HandleAirMode(pid)
	if Players[pid] == nil then return end
	local airmode = Players[pid].data.BRinfo.airMode
	TestBR.SetAirMode(pid, airmode)
	Players[pid].data.BRinfo.airMode = airmode - 1
	if airmode > 1 then
		--Players[pid].airTimer = tes3mp.CreateTimerEx("OnPlayerTopic", time.seconds((15*airmode)+3), "i", pid)
		Players[pid].airTimer = tes3mp.CreateTimerEx("BRHandleTimerAirModeTimeout", time.seconds((15*airmode)+3), "i", pid)
		tes3mp.StartTimer(Players[pid].airTimer)
	end
end

function BRHandleTimerAirModeTimeout(pid)
	TestBR.HandleAirMode(pid)
end

-- set airborne-related effects
-- 0 = disabled
-- 1 = just slowfall
-- 2 = slowfall and speed
function TestBR.SetAirMode(pid, mode)
	TestBR.DebugLog(2, "Setting air mode for " .. tostring(pid))

	if Players[pid] ~= nil and Players[pid]:IsLoggedIn() then
		if Players[pid].airTimer ~= nil then -- Stop timer
			tes3mp.StopTimer(Players[pid].airTimer)
		end

		Players[pid].data.BRinfo.airMode = mode -- Ensure that the player's data is up to date

		if mode == 2 then
			TestBR.SetSlowFall(pid, true)
			Players[pid].data.attributes["Speed"].base = 3000
		elseif mode == 1 then
			TestBR.SetSlowFall(pid, true)
			-- #TODO: make this restore the proper value
			Players[pid].data.attributes["Speed"].base = brConfig.defaultStats.playerSpeed
		else 
			TestBR.SetSlowFall(pid, false)
			-- #TODO: make this restore the proper value
			Players[pid].data.attributes["Speed"].base = brConfig.defaultStats.playerSpeed
		end

		Players[pid]:Save()
		Players[pid]:LoadAttributes()
	end
end

-- either enables or disables slowfall for player
-- this part assumes that there is a proper entry for br_slowfall_power in recordstore
function TestBR.SetSlowFall(pid, boolean)
	TestBR.DebugLog(1, "Setting slowfall mode for PID " .. tostring(pid))
	if boolean then
		TestBR.AddSpell(pid, "br_slowfall_power")
	else
		TestBR.RemoveSpell(pid, "br_slowfall_power")
	end
end

--#endregion


--#region =================== FOG ===================

-- Check and applies the damage level for a player at cell transition
-- #TODO: Apply effects when we are out of the map
-- #TODO: make it so that damage level doesn't get cleared and re-applied on every cell transition
function TestBR.CheckCellDamageLevel(pid)
	TestBR.DebugLog(1, "Checking new cell for PID " .. tostring(pid))
	local playerCell = Players[pid].data.BRinfo.lastExteriorCell -- Handle interiors	

	-- danke StackOverflow
	local x, y = playerCell:match("([^,]+),([^,]+)")

	local foundLevel = false

	for level=1,#fogGridLimits do
		TestBR.DebugLog(0, "GetCurrentDamageLevel: " .. tostring(TestBR.GetCurrentDamageLevel(level)))
		TestBR.DebugLog(0, "x == number: " .. tostring(type(tonumber(x)) == "number"))
		TestBR.DebugLog(0, "y == number: " .. tostring(type(tonumber(y)) == "number"))
		TestBR.DebugLog(0, "cell only in level: " .. tostring(TestBR.IsCellOnlyInLevel({tonumber(x), tonumber(y)}, level)))
		if type(TestBR.GetCurrentDamageLevel(level)) == "number" and type(tonumber(x)) == "number" 
		and type(tonumber(y)) == "number" and TestBR.IsCellOnlyInLevel({tonumber(x), tonumber(y)}, level) then
			TestBR.SetFogDamageLevel(pid, TestBR.GetCurrentDamageLevel(level))
			foundLevel = true
			TestBR.DebugLog(1, "Damage level for PID " .. tostring(pid) .. " is set to " .. tostring(currentFogStage - level))
			break
		end
	end

	if not foundLevel then
		TestBR.SetFogDamageLevel(pid, 0)
	end
end

function TestBR.SetFogDamageLevel(pid, level)
	if Players[pid] == nil then
		return
	end
	TestBR.DebugLog(1, "Setting damage level for PID " .. tostring(pid))

	tes3mp.ClearSpellbookChanges(pid)
	if level == 0 then
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.REMOVE)
		tes3mp.AddSpell(pid, "br_fog_1")
		tes3mp.AddSpell(pid, "br_fog_2")
		tes3mp.AddSpell(pid, "br_fog_3")
	elseif level == 1 then
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
		tes3mp.AddSpell(pid, "br_fog_1")
	elseif level == 2 then
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
		tes3mp.AddSpell(pid, "br_fog_2")
	elseif level == 3 then
		tes3mp.SetSpellbookChangesAction(pid, enumerations.spellbook.ADD)
		tes3mp.AddSpell(pid, "br_fog_3")
	end
	tes3mp.SendSpellbookChanges(pid, true)
end

-- Start timer for AdvanceFog and alerts
function TestBR.StartFogTimer(delay)
	TestBR.DebugLog(1, "Setting shrink timer for " .. tostring(delay) .. " seconds")
	tes3mp.SendMessage(0, string.gsub(brConfig.strBlightAlertSec, "{x}", tostring(delay) ) .."\n", true)
	fogTimer = tes3mp.CreateTimerEx("BRAdvanceFog", time.seconds(delay), "i", 1)
	tes3mp.StartTimer(fogTimer)

	if delay >= 90 then -- Set alert for last minute
		fogAlertRemainingTime = 60
		TestBR.StartShrinkAlertTimer(delay - 60)
	else -- Only set warning for last seconds
		fogAlertRemainingTime = 10
		TestBR.StartShrinkAlertTimer(delay - 10)
	end
end

-- Start timer for alert message boxes
function TestBR.StartShrinkAlertTimer(delay)
	TestBR.DebugLog(1, "Setting shrink timer alert for " .. tostring(delay) .. " seconds")
	fogAlertTimer = tes3mp.CreateTimerEx("BRHandleShrinkTimerAlertTimeout", time.seconds(delay), "i", 1)
	tes3mp.StartTimer(fogAlertTimer)
end

-- Last minute and last 10 seconds warnings
function BRHandleShrinkTimerAlertTimeout()
	local message = ""
	if fogAlertRemainingTime >= 60 then
		message = brConfig.strBlightAlert1Minute
	else
		message = string.gsub(brConfig.strBlightAlertSec, "{x}", tostring(fogAlertRemainingTime))
	end
	for pid, player in pairs(Players) do
		tes3mp.MessageBox(pid, -1, message)
	end

	local nextTimer = 1

	if fogAlertRemainingTime >= 60 then
		fogAlertRemainingTime = 10
		nextTimer = 50
	else
		fogAlertRemainingTime = fogAlertRemainingTime - 1
	end

	if fogAlertRemainingTime >= 1 then -- Start next timer
		TestBR.StartShrinkAlertTimer(nextTimer)
	end
end

function TestBR.StopFogTimers()
	if fogTimer ~= nil then
		tes3mp.StopTimer(fogTimer)
	end
	if fogAlertTimer ~= nil then
		tes3mp.StopTimer(fogAlertTimer)
	end
end

-- Force fog to advance #TODO: Restrict this to admins
function TestBR.ForceNextFog(pid)
	if Players[pid]:IsAdmin() then

		if #brConfig.fogStageDurations >= currentFogStage + 1 then
			-- Stop current timers
			TestBR.StopFogTimers()
			BRAdvanceFog()
		else
			tes3mp.SendMessage(pid, color.Red .. "Blight cannot shrink anymore\n", false)
		end

	else
		tes3mp.SendMessage(pid, "You don't have permission to do this\n", false)
	end
end

-- Advance fog and start timers for next stage and reminders
function BRAdvanceFog()
	if (TestBR.gameState ~= GAME_STATE.INMATCH) then
		return
	end

	TestBR.DebugLog(1, "Advancing fog...")

	tes3mp.SendMessage(0, "Blight is shrinking.\n", true)
	currentFogStage = currentFogStage + 1
	if currentFogStage <= #brConfig.fogStageDurations then
		TestBR.StartFogTimer(brConfig.fogStageDurations[currentFogStage]) -- Start timer for next stage
	end

	TestBR.UpdateMap()
	tes3mp.SendWorldMap(tes3mp.GetLastPlayerId(), true, false)

	for pid, player in pairs(Players) do
		if player ~= nil and player:IsLoggedIn() then
			-- Update fog damage for players
			if Players[pid].data.BRinfo.state == PLAYER_STATE.INMATCH then
				TestBR.CheckCellDamageLevel(pid)
			end
		end
	end
end


-- returns a list of squares that are to be used for fog levels
-- for example: { {{10, 0}, {0, 10}}, {{5, 5}, {5, 5}}, {} }
function TestBR.GenerateFogGrid(fogLevelSizes)
	TestBR.DebugLog(1, "Generating fog grid")
	local generatedFogGrid = {}

	for level=1,#fogLevelSizes do
		TestBR.DebugLog(0, "Generating level " .. tostring(level))
		generatedFogGrid[level] = {}

		-- handle the first item in the array (double check just to be sure)
		--if type(fogLevelSizes[level]) ~= "number" and fogLevelSizes[level] = "all" then
		-- or lol, we can just check if this is first time going through the loop
		-- this does assume that config is not messed up, that first entry is meant to be whole area
		if level == 1 then
			table.insert(generatedFogGrid[level], {brConfig.mapBorders[1][1], brConfig.mapBorders[1][2]})
			table.insert(generatedFogGrid[level], {brConfig.mapBorders[2][1], brConfig.mapBorders[2][2]})
		else
			-- check out some stuff about previous level
			local xIncludesZero = 0
			local yIncludesZero = 0
			-- check if min X and max X are both positive or both negative
			-- because if they are not, it means that one of cells in X range is also {0, y}, which must be counted in the length as well
			if TestBR.DoNumbersHaveSameSign(generatedFogGrid[level-1][1][1], generatedFogGrid[level-1][2][1]) then
				xIncludesZero = 1
			end
			-- same for Y
			if TestBR.DoNumbersHaveSameSign(generatedFogGrid[level-1][1][2], generatedFogGrid[level-1][2][2]) then
				yIncludesZero = 1
			end

			local previousXLength = math.abs(generatedFogGrid[level-1][1][1]) + math.abs(generatedFogGrid[level-1][2][1]) + xIncludesZero
			local previousYLength = math.abs(generatedFogGrid[level-1][1][2]) + math.abs(generatedFogGrid[level-1][2][2]) + yIncludesZero

			-- figure out if there is space for next level
			-- -1 because we are checking if new size fits into a square that is one cell smaller from both sides
			if fogLevelSizes[level] < previousXLength - 1 and fogLevelSizes[level] < previousYLength - 1 then
				-- all right, looks like it will fit
				-- now we can even try to add "border" that is one cell wide, so that edges of previous level and new level don't touch
				local cellBorder = 0
				if fogLevelSizes[level] < previousXLength - 2 and fogLevelSizes[level] < previousYLength - 2 then
					TestBR.DebugLog(1, "Level " .. tostring(level) .. " can get a cell-wide border")
					cellBorder = 1
				end

			-- this gives available area for the whole level
			-- {minX, maxX}
			local availableVerticalArea = {generatedFogGrid[level-1][1][1] + 1 + cellBorder, generatedFogGrid[level-1][2][1] - 1 - cellBorder}
			-- {minY, maxY}
			local availableHorisontalArea = {generatedFogGrid[level-1][1][2] + 1 + cellBorder, generatedFogGrid[level-1][2][2] - 1 - cellBorder}

			-- but now we need to determine what is the available area for the bottom left cell from which the whole level will be extrapolated from
			-- we leave minX as it is, but we subtract level size from the maxX
			local availableCornerAreaX = {availableVerticalArea[1], availableVerticalArea[2] - fogLevelSizes[level]}
			-- same for Y
			local availableCornerAreaY = {availableHorisontalArea[1], availableHorisontalArea[2] - fogLevelSizes[level]}

			-- choose random cell in the available area
			local newX = math.random(availableCornerAreaX[1],availableCornerAreaX[2])
			local newY = math.random(availableCornerAreaY[1],availableCornerAreaY[2])

			-- save bottom left corner
			table.insert(generatedFogGrid[level], {newX, newY})
			-- save top right corner
			table.insert(generatedFogGrid[level], {newX + fogLevelSizes[level], newY + fogLevelSizes[level]})
			TestBR.DebugLog(0, "" .. tostring(level) .. " goes from " .. tostring(newX) .. ", " .. tostring(newY) .. " to " ..
				tostring(newX + fogLevelSizes[level]) .. ", " .. tostring(newY + fogLevelSizes[level]))
			-- lol no place to add the level. Who made this config?
			else
				TestBR.DebugLog(2, "Given level size does not fit into previous level, skipping this one")
				-- #TODO: lol this will actually break, since this for loop does not account for missing data
				-- so just don't make bad configs until this gets implemented :^^^^)
			end
		end
	end

	return generatedFogGrid
end

-- returns true if cell is part of level
function TestBR.IsCellInLevel(cell, level)
	TestBR.DebugLog(0, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is in level " .. tostring(level))
	-- check if cell is in level range
	if fogGridLimits[level] and TestBR.IsCellInRange(cell, fogGridLimits[level][1], fogGridLimits[level][2]) then
		return true
	end
	return false
end

-- basically same function as above, only with added exclusivity check
-- returns true if cell is part of level
-- #TODO: make this by implementing an "isExclusive" argument instead of having two seperate functions
function TestBR.IsCellOnlyInLevel(cell, level)
	TestBR.DebugLog(0, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is only in level " .. tostring(level))
	-- check if cell is in level range
	if fogGridLimits[level] and TestBR.IsCellInRange(cell, fogGridLimits[level][1], fogGridLimits[level][2]) then
		-- now watch this: check if further levels exist and that cell does not actually belong to that further level
		if fogGridLimits[level+1] and TestBR.IsCellInRange(cell, fogGridLimits[level+1][1], fogGridLimits[level+1][2]) then
			return false
		end
		return true
	end
	return false
end

-- returns true if cell is inside the rectangle defined by given coordinates
function TestBR.IsCellInRange(cell, topRight, bottomLeft)
	if cell == nil then
		return
	end
	TestBR.DebugLog(0, "Checking if " .. tostring(cell[1]) .. ", " .. tostring(cell[2]) .. " is inside the "
		 .. tostring(topRight[1]) .. ", " .. tostring(topRight[2]) .. " - " .. tostring(bottomLeft[1]) .. ", " .. tostring(bottomLeft[2]) .. " rectangle")
	if cell[1] >= topRight[1] and cell[1] <= bottomLeft[1] and cell[2] >= topRight[2] and cell[2] <= bottomLeft[2] then
		return true
	end
	return false
end

function TestBR.DoNumbersHaveSameSign(number1, number2)
	if string.sub(tostring(number1), 1, 1) == string.sub(tostring(number2), 1, 1) then
		return true
	end
	return false
end

function TestBR.GetCurrentDamageLevel(level)
	TestBR.DebugLog(1, "Looking up damage level for level " .. tostring(level))
	if currentFogStage - level > #brConfig.fogDamageValues then
		return brConfig.fogDamageValues[#brConfig.fogDamageValues]
	else
		return brConfig.fogDamageValues[currentFogStage - level]
	end
end

function TestBR.UpdateMap()
	TestBR.DebugLog(1, "Updating map to fog level " .. tostring(currentFogStage))
	tes3mp.ClearMapChanges()

	for levelIndex=1,#fogGridLimits do
		-- at this point I am just banging code together until it works
		-- got lucky with the first condition, added second condition in order to limit logic only to relevant levels
		if levelIndex - currentFogStage < #brConfig.fogDamageValues and brConfig.fogDamageValues[currentFogStage - levelIndex] ~= nil then
			TestBR.DebugLog(1, "Level " .. tostring(levelIndex) .. " gets fog level " .. tostring(brConfig.fogDamageValues[currentFogStage - levelIndex]))

			-- iterate through all cells in this level
			for x=fogGridLimits[levelIndex][1][1],fogGridLimits[levelIndex][2][1] do
				for y=fogGridLimits[levelIndex][1][2],fogGridLimits[levelIndex][2][2] do
					-- actually, instead of using IsCell**Only**InLevel() we can avoid checking cells which obviously are in the level
					-- instead, we just check if cells are not in the next level. Same thing that above mentioned function would do,
					-- but we do it on smaller set of cells
					-- so it's "is this the last level OR (is there next level AND cell is not part of next level)"		
					if not fogGridLimits[levelIndex+1] or (fogGridLimits[levelIndex+1] and not TestBR.IsCellInLevel({x, y}, levelIndex+1)) then
						--tes3mp.LoadMapTileImageFile(x, y, fogFilePaths[currentFogStage - levelIndex])
						TestBR.PaintMapTile(x, y, currentFogStage - levelIndex)
					end
				end
			end
		end
	end
end

-- Paint a map tile to a fog level. You will need to call tes3mp.SendWorldMap() to send the changes to players.
function TestBR.PaintMapTile(x, y, level)
	local path = ""
	if level >= #fogFilePaths then
		path = fogFilePaths[ #fogFilePaths ]
	elseif level > 0 then
		path = fogFilePaths[ level ]
	else
		path = brConfig.fogNoneFilePath
	end
	tes3mp.LoadMapTileImageFile(x, y, path)
end

function TestBR.CleanMap()
	for x=fogGridLimits[1][1][1], fogGridLimits[1][2][1] do
		for y=fogGridLimits[1][1][2], fogGridLimits[1][2][2] do
			TestBR.PaintMapTile(x, y, 0)
		end
	end
end

function TestBR.SendMapToPlayer(pid)
	TestBR.DebugLog(1, "Sending map to PID " .. tostring(pid))
	tes3mp.SendWorldMap(pid, false, false)
end

--#endregion


-- #TODO: Implement this
function TestBR.ResetWorld()

end


function BROnDeathTimeExpiration(pid)
	TestBR.ResurrectPlayer(pid)
end

-- Modified respawning behavior for Battle Royale that doesn't teleport the player
function TestBR.ResurrectPlayer(pid)
	if Players[pid] == nil then return end

	if Players[pid].resurrectTimer ~= nil then
		tes3mp.StopTimer( Players[pid].resurrectTimer )
		Players[pid].resurrectTimer = nil
	end

	-- Ensure that dying as a werewolf turns you back into your normal form
	if Players[pid].data.shapeshift.isWerewolf == true then
		Players[pid]:SetWerewolfState(false)
	end

	-- Ensure that we unequip deadly items when applicable, to prevent an
	-- infinite death loop
	contentFixer.UnequipDeadlyItems(pid)

	tes3mp.Resurrect(pid, enumerations.resurrect.REGULAR)

	if TestBR.gameState ~= GAME_STATE.LOBBY then
		TestBR.SetPlayerState(PLAYER_STATE.SPECT)
		tes3mp.MessageBox(pid, -1, brConfig.strGhost)
	end
end


--#region ======================== EVENT HANDLERS ========================

--[[
-- This is basically hijacking OnPlayerTopic event signal for our own purposes
-- OnPlayerTopic because it doesn't play any role in purely PvP gamemode where no NPCs are present
-- #TODO: figure out how to add new event without messing up with server core, so that all the code is only in this file
customEventHooks.registerValidator("OnPlayerTopic", function(eventStatus, pid)
	return customEventHooks.makeEventStatus(false, true)
end)

customEventHooks.registerHandler("OnPlayerTopic", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		testBR.HandleAirMode(pid)
	end
end)
]]-- #TODO: Test new implementation

customEventHooks.registerHandler("OnServerPostInit", function(eventStatus)
	-- Create necessary permanent records
	brRecords.Init()
end)

customEventHooks.registerHandler("OnPlayerFinishLogin", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		TestBR.VerifyPlayerData(pid)
		TestBR.RefreshPlayerState(pid)

		if TestBR.gameState == GAME_STATE.INMATCH then
			TestBR.SendMapToPlayer(pid)
		end
	end
end)

-- Replace default death and respawning behavior
customEventHooks.registerValidator("OnPlayerDeath", function(eventStatus, pid)
	eventStatus.validDefaultHandler = false
	eventStatus.validCustomHandlers = true
	return eventStatus
end)

-- Override death and respawning behaviour
customEventHooks.registerHandler("OnPlayerDeath", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then

		-- Remove dead player from match, broadcast death notification and check for victory
		local respawnDelay = 2

		if TestBR.gameState == GAME_STATE.INMATCH and Players[pid].data.BRinfo.state == PLAYER_STATE.INMATCH then -- Player was in match
			respawnDelay = config.deathTime

			-- Send kill message
			local deathReason = brConfig.strDied

			if tes3mp.DoesPlayerHavePlayerKiller(pid) then
				local killerPid = tes3mp.GetPlayerKillerPid(pid)

				if pid ~= killerPid then
					deathReason = string.gsub(brConfig.strKill, "{y}", Players[killerPid].data.login.name)
					if Players[killerPid] ~= nil then -- Increment killer's kill count
						Players[killerPid].data.BRinfo.totalKills = Players[killerPid].data.BRinfo.totalKills + 1
					end
				end
			else
				local killerName = tes3mp.GetPlayerKillerName(pid)

				if killerName ~= "" then				
					deathReason = string.gsub(brConfig.strKill, "{y}", killerName)
				end
			end

			local message = string.gsub(deathReason, "{x}", Players[pid].data.login.name)

			tes3mp.SendMessage(pid, message .. "\n", true)

			-- Increment player's death count
			Players[pid].data.BRinfo.totalDeaths = Players[pid].data.BRinfo.totalDeaths + 1


			-- Broadcast death message box to everyone
			local messageBoxStr = string.gsub( brConfig.strXDiedYPlayersRemaining, "{x}", Players[pid].data.login.name )
			messageBoxStr = string.gsub( messageBoxStr, "{y}", tostring(TestBR.TableLen(playerList)-1) )

			for i, player in pairs(Players) do
				tes3mp.MessageBox(i, -1, messageBoxStr)
			end

			TestBR.DropAllItems(pid)

			TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)

			playerList[Players[pid].data.login.name] = nil

			TestBR.CheckVictoryConditions()
		end
		TestBR.SetFogDamageLevel(pid, 0)
		Players[pid]:Save()

		Players[pid].resurrectTimer = tes3mp.CreateTimerEx("BROnDeathTimeExpiration", time.seconds(respawnDelay), "i", pid)
		tes3mp.StartTimer( Players[pid].resurrectTimer )

	end
end)

--[[
customEventHooks.registerHandler("OnPlayerResurrect", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then
		if Players[pid] == nil then
			testBR.DebugLog(2, "Nil player respawned?!")
			return
		end

		if testBR.gameState == GAME_STATE.LOBBY then
			-- Just respawn players in lobby
		else
			-- #TODO: Spectator effects (disable combat but allow fun interactions)
			testBR.SetPlayerState(playerState.SPECT)
			tes3mp.MessageBox(pid, -1, brConfig.strGhost)
		end

		testBR.CheckVictoryConditions() -- Just in case
	end
end)--]]

customEventHooks.registerHandler("OnCellLoad", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete

		-- Spawn random loot if this cell is loaded for the first time
		if visitedCells[ tes3mp.GetCell(pid) ] == nil then
			testBRLootManager.SpawnCellLoot( tes3mp.GetCell(pid) )
			visitedCells[ tes3mp.GetCell(pid) ] = true
		end

	end
end)

customEventHooks.registerHandler("OnPlayerEndCharGen", function(eventstatus, pid)
	if Players[pid] ~= nil then

		TestBR.DebugLog(1, "Ending character generation for " .. tostring(pid))
		Players[pid]:SaveLogin()
		Players[pid]:SaveCharacter()
		Players[pid]:SaveClass()
		Players[pid]:SaveStatsDynamic()
		Players[pid]:SaveEquipment()
		Players[pid]:SaveIpAddress()
		Players[pid]:CreateAccount()
		TestBR.VerifyPlayerData(pid)

		TestBR.SetPlayerState(pid, PLAYER_STATE.SPECT)
	end
end)

-- custom validator for cell change #TODO: Deny door interaction
customEventHooks.registerValidator("OnPlayerCellChange", function(eventStatus, pid)
	-- Prevent players in lobby from leaving it
	if TestBR.gameState == GAME_STATE.LOBBY and tes3mp.GetCell(pid) ~= brConfig.lobbyCell and Players[pid].data.BRinfo.state >= 1 then
		tes3mp.MessageBox(pid, -1, brConfig.strCantLeaveLobby)
		TestBR.SpawnPlayer(pid, true)
        return customEventHooks.makeEventStatus(false, true)
	end

	--[[-- Allow player to spawn in lobby
	if tes3mp.GetCell(pid) == brConfig.lobbyCell and (testBR.gameState ~= GAME_STATE.INMATCH) then
		return customEventHooks.makeEventStatus(true,true)
	end--]]

	if (not brConfig.allowInteriors) and TestBR.gameState == GAME_STATE.INMATCH and Players[pid].data.BRinfo.state == PLAYER_STATE.INMATCH then
		local _, _, cellX, cellY = string.find(tes3mp.GetCell(pid), patterns.exteriorCell)
		if cellX == nil or cellY == nil then
			TestBR.DebugLog(1, tostring(pid).." tried to enter an interior")
			tes3mp.MessageBox(pid, -1, brConfig.strCantEnterInterior)
			Players[pid].data.location.posX = tes3mp.GetPreviousCellPosX(pid)
			Players[pid].data.location.posY = tes3mp.GetPreviousCellPosY(pid)
			Players[pid].data.location.posZ = tes3mp.GetPreviousCellPosZ(pid)
			Players[pid]:LoadCell()
			return customEventHooks.makeEventStatus(false, true)
		end
	end

	return customEventHooks.makeEventStatus(true, true)
end)

customEventHooks.registerHandler("OnPlayerCellChange", function(eventStatus, pid)
	if eventStatus.validCustomHandlers then --check if some other script made this event obsolete
		
		TestBR.DebugLog(0, "Processing cell change for PID " .. tostring(pid))
		if Players[pid] ~= nil and Players[pid]:IsLoggedIn() and Players[pid].data.BRinfo.state == PLAYER_STATE.INMATCH then

			-- Spawn random loot if this cell is visited for the first time
			if visitedCells[ tes3mp.GetCell(pid) ] == nil then
				testBRLootManager.SpawnCellLoot( tes3mp.GetCell(pid) )
				visitedCells[ tes3mp.GetCell(pid) ] = true
			end

			-- Check if we are in an exterior to keep track of the last visited exterior cell
			_, _, cellX, cellY = string.find(tes3mp.GetCell(pid), patterns.exteriorCell)
			if cellX ~= nil and cellY ~= nil then
				Players[pid].data.BRinfo.lastExteriorCell = tes3mp.GetCell(pid)

				-- #TODO: lol I have no idea how to properly re-paint a tile after player "discovered it"
				--tes3mp.ClearMapChanges()
				--testBR.PaintMapTile(cellX, cellY, )
				--tes3mp.SendWorldMap(pid, false, false)
			end

			TestBR.CheckCellDamageLevel(pid)

			Players[pid]:SaveStatsDynamic()
			Players[pid]:Save()
		end

	end
end)

--#endregion


--#region ======================== LOOT TABLES ========================

-- Init loot table
TestBR.DebugLog(1, "Initializing loot table manager")
testBRLootManager.init(brConfig.lootTable)

-- Reload loot tables from disk
function TestBR.LoadLootTables()
	TestBR.DebugLog(1, "Loading loot table from disk")
	testBRLootManager.LoadFromDisk()
end

-- Add a loot spawn location for a given loot table at the player's position
function TestBR.AddLootSpawn(pid, lootTable)
	if TestBR.gameState == GAME_STATE.INMATCH then
		tes3mp.SendMessage(pid, color.Red .. "Cannot edit loot spawn points during a match!\n", false)
	else
		if lootTable == nil then
			tes3mp.SendMessage(pid, color.Red .. "Missing loot table argument\n", false)
			return
		end
		testBRLootManager.AddLocation(lootTable, tes3mp.GetCell(pid), tes3mp.GetPosX(pid), tes3mp.GetPosY(pid), tes3mp.GetPosZ(pid))
		testBRLootManager.SaveToDrive()
		tes3mp.SendMessage(pid, color.Green .. "Added a spawn point for " .. lootTable .. "!\n", false)
	end
end

function TestBR.AddLootSpawnCmd(pid, args) -- #TODO: Restrict this to a certain permission level & check if the table exists
	if lootTable == nil then
		tes3mp.SendMessage(pid, color.Red .. "Missing loot table argument\n", false)
	else
		TestBR.AddLootSpawn(pid, args[2])
	end
end

-- Temporary utility command to add common loot
function TestBR.AddLootSpawnCommon(pid)
	TestBR.AddLootSpawn(pid, "common")
end
-- Temporary utility command to add rare loot
function TestBR.AddLootSpawnRare(pid)
	TestBR.AddLootSpawn(pid, "rare")
end
-- Temporary utility command to add legendary loot
function TestBR.AddLootSpawnLegendary(pid)
	TestBR.AddLootSpawn(pid, "legendary")
end

--#endregion


--#region ======================== REGISTER COMMANDS ========================

customCommandHooks.registerCommand(brConfig.cmdMenu, brGUI.ShowUserMenu)
customCommandHooks.registerCommand(brConfig.cmdNewMatch, TestBR.CreateLobby)
customCommandHooks.registerCommand("forcestartmatch", TestBR.StartRound)
customCommandHooks.registerCommand(brConfig.cmdJoin, TestBR.PlayerJoinLobby)
customCommandHooks.registerCommand(brConfig.cmdReady, TestBR.PlayerSetReady)
customCommandHooks.registerCommand("forcenextfog", TestBR.ForceNextFog)
customCommandHooks.registerCommand("forceend", TestBR.AdminEndMatch)


-- Temporary utility command
function TestBR.PrintPlayerCoordsCmd(pid)
	tes3mp.SendMessage(pid, Players[pid].data.login.name .. " is at " .. tostring(tes3mp.GetPosX(pid)) .. ", "
	.. tostring(tes3mp.GetPosY(pid)) .. ", " .. tostring(tes3mp.GetPosZ(pid)) .. " in cell \"" .. tes3mp.GetCell(pid) .. "\"\n")
end

customCommandHooks.registerCommand("here", TestBR.PrintPlayerCoordsCmd)
customCommandHooks.registerCommand("loot", TestBR.AddLootSpawnCmd)
customCommandHooks.registerCommand("xc", TestBR.AddLootSpawnCommon)
customCommandHooks.registerCommand("xr", TestBR.AddLootSpawnRare)
customCommandHooks.registerCommand("xl", TestBR.AddLootSpawnLegendary)

--#endregion

return TestBR
