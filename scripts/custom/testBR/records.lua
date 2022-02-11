
local brRecords = {}

-- Load config file
local brConfig = require("custom/testBRConfig")

-- Create permanent records
function brRecords.Init()
	-- Spectator mode
	RecordStores.spell.data.permanentRecords["br_spectator"] = {
		subtype = 4,
		cost = 0,
		flags = 0,
		name = "Spectator's curse",
		effects = {
			{
				id = 10,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 400,
				magnitudeMin = 400
			},{
				id = 40,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 100,
				magnitudeMin = 100
			}
		},
	}

	-- Air drop slow fall
	RecordStores.spell.data.permanentRecords["br_slowfall_power"] = {
		name = "Slowfall",
		subtype = 4,
		cost = 0,
		flags = 0,
		effects = {
			{
				id = 11,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 5,
				magnitudeMin = 5
			}
		}
	}

	-- Fog damage, these stack the further you go in the fog
	RecordStores.spell.data.permanentRecords["br_fog_1"] = {
		name = "Fog damage",
		subtype = 4,
		cost = 0,
		flags = 0,
		effects = {
			{
				id = 23,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 1,
				magnitudeMin = 1
			}
		}
	}
	RecordStores.spell.data.permanentRecords["br_fog_2"] = {
		name = "Fog damage",
		subtype = 4,
		cost = 0,
		flags = 0,
		effects = {
			{
				id = 23,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 5,
				magnitudeMin = 5
			}
		}
	}
	RecordStores.spell.data.permanentRecords["br_fog_3"] = {
		name = "Fog damage",
		subtype = 4,
		cost = 0,
		flags = 0,
		effects = {
			{
				id = 23,
				attribute = -1,
				skill = -1,
				rangeType = 0,
				area = 0,
				magnitudeMax = 20,
				magnitudeMin = 20
			}
		}
	}

end

return brRecords
