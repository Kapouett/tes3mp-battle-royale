-- Config file
brConfig = require("custom/testBRConfig")

fileHelper = require("fileHelper")
tableHelper = require("tableHelper")

-- used for RNG seed
time = require("time")

-- used for generation of random numbers
math.randomseed(os.time())

testBRLootManager = {}

local defaultData = { tables = {  }, locations = {  } }

-- Initialize current data to valid default values
local data = {}

-- Sums of probabilities for each table
local sums = {}

local lootFile = ""

local hasEntry = false

testBRLootManager.init = function(fileName)
	lootFile = fileName .. ".json"

	-- Initialize current data to valid default values
	data = tableHelper.shallowCopy(defaultData)

	-- Create file if non-existant
	local f = io.open(tes3mp.GetDataPath() .. "/custom/" .. lootFile, "a")
	if f == nil then -- File doesn't
		io.close()
		hasEntry = false
	else -- File exists
		hasEntry = true
	end
end

testBRLootManager.CreateEntry = function()
    jsonInterface.save("custom/" .. lootFile, data)
    hasEntry = true
end

-- Save current data to the file
testBRLootManager.SaveToDrive = function()
    if hasEntry then
        jsonInterface.save("custom/" .. lootFile, data)
    end
end

-- Set current data to content of the file
testBRLootManager.LoadFromDisk = function()
	if (not hasEntry) then
		testBRLootManager.CreateEntry()
	end

    data = jsonInterface.load("custom/" .. lootFile)

	-- Empty JSON
	if data == nil then
		tes3mp.LogMessage(2, "BR loot tables file is empty")
		data = tableHelper.shallowCopy(defaultData)
	end

    -- JSON doesn't allow numerical keys, but we use them, so convert
    -- all string number keys into numerical keys
    tableHelper.fixNumericalKeys(data)
end

-- Add a new loot spawn location
testBRLootManager.AddLocation = function(table, cell, x, y, z)
	if data == nil then
		tes3mp.LogMessage(3, "Invalid loot table")
		data = tableHelper.shallowCopy(defaultData)
	end
	if data.locations == nil then
		tes3mp.LogMessage(3, "Invalid loot locations table")
		data.locations = tableHelper.shallowCopy(defaultData.locations)
	end
	
	if data.locations[cell] == nil then
		data.locations[cell] = {}
	end	

	data.locations[cell][#data.locations[cell] + 1] = { ["table"]=table, ["x"]=x, ["y"]=y, ["z"]=z }

	testBRLootManager.UpdateSums()
end

-- Spawn loot for a cell
testBRLootManager.SpawnCellLoot = function(cell)
	if data == nil then
		tes3mp.LogMessage(3, "Invalid loot table")
		return
	end
	if data.locations == nil then
		tes3mp.LogMessage(3, "Invalid loot locations table")
		return
	end
	
	local spawnPoints = data.locations[cell]
	if spawnPoints == nil then return end -- Nothing to spawn

	testBRLootManager.UpdateSums() -- Make sure sums are up to date

	for _, spawnPoint in pairs(spawnPoints) do
		local item = testBRLootManager.GetRandomItem( spawnPoint )
		if item ~= nil then
			--testBRLootManager.SpawnLootBox( cell, spawnPoint.x, spawnPoint.y, spawnPoint.z, {item} )
			testBRLootManager.SpawnItem( cell, spawnPoint.x, spawnPoint.y, spawnPoint.z, item.refId, item.count )
		end
	end
end

-- Get a random item for a spawnPoint, returns refId and count
testBRLootManager.GetRandomItem = function(spawnPoint)
	if sums[spawnPoint.table] == nil then
		tes3mp.LogMessage(3, "Tried to get a random item from an inexistant loot table (returned nil instead)")
		return nil
	end

	local target = math.random(1, sums[spawnPoint.table])

	for itemRefId, itemData in pairs(data.tables[spawnPoint.table]) do
		if target <= itemData.proba then
			return { refId=itemRefId, count=itemData.count }
		end
		target = target - itemData.proba
	end

	return nil
end

testBRLootManager.SpawnItem = function(cell, x, y, z, refId, count)
	local mpNum = WorldInstance:GetCurrentMpNum() + 1
	local location = {
		posX = x, posY = y, posZ = z,
		rotX = 0, rotY = 0, rotZ = 0
	}
	local refIndex =  0 .. "-" .. mpNum
	
	WorldInstance:SetCurrentMpNum(mpNum)
	tes3mp.SetCurrentMpNum(mpNum)

	LoadedCells[cell]:InitializeObjectData(refIndex, refId)		
	LoadedCells[cell].data.objectData[refIndex].location = location			
	table.insert(LoadedCells[cell].data.packets.place, refIndex)
	
	tes3mp.LogMessage(1, "Spawning " .. tostring(refId) .. " *" .. tostring(count) .. " in " .. cell)
	tes3mp.LogMessage(1, "Sending spawned item to players")
	for onlinePid, player in pairs(Players) do
		if player:IsLoggedIn() then
			tes3mp.InitializeEvent(onlinePid)
			tes3mp.SetEventCell(cell)
			tes3mp.SetObjectRefId(refId)
			tes3mp.SetObjectCount(count)
			tes3mp.SetObjectCharge(-1) -- Set the item condition at max
			tes3mp.SetObjectRefNumIndex(0)
			tes3mp.SetObjectMpNum(mpNum)
			tes3mp.SetObjectPosition(location.posX, location.posY, location.posZ)
			tes3mp.SetObjectRotation(location.rotX, location.rotY, location.rotZ)
			tes3mp.AddWorldObject()
			tes3mp.SendObjectPlace()
		end
	end
	LoadedCells[cell]:Save()
end

-- Spawn a corpse containing loot
testBRLootManager.SpawnLootBox = function(cell, x, y, z, loot)
	local data = {}

	local refId = corpseRefId

	local mpNum = WorldInstance:GetCurrentMpNum() + 1
	local location = {
		posX = x, posY = y, posZ = z,
		rotX = 0, rotY = 0, rotZ = 0
	}
	local uniqueId =  0 .. "-" .. mpNum
	local location = { posX=x, posY=y, posZ=z, rotX=0, rotY=0, rotZ=3.14 }

	LoadedCells[cell]:InitializeObjectData(uniqueId, refId)
    LoadedCells[cell].data.objectData[uniqueId].location = location

	table.insert(LoadedCells[cell].data.packets.actorList, uniqueId)

	local objectData = {}
	objectData.refId = refId
	objectData.location = location
	
	packetBuilder.AddObjectPlace(uniqueId, objectData)
	
	tes3mp.SendObjectPlace(true, false)
	
	-- Add loot
	for itemRefId, itemData in pairs(loot) do
		if item ~= nil then
			command = "additem \"" .. itemRefId .. "\" " .. tostring(itemData.count) --TODO: test this
			logicHandler.RunConsoleCommandOnObject(0, command, LoadedCells[cell], uniqueId, true)
		end
	end
end

testBRLootManager.UpdateSums = function()
	sums = {}
	for table, items in pairs(data.tables) do
		local sum = 0

		for refId, itemData in pairs(items) do
			sum = sum + itemData.proba
		end

		sums[table] = sum
	end
end

