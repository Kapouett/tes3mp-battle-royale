-- #TODO: Fix menu not working until you have run /help

BRgui = {}

-- Load config file
local brConfig = require("custom/testBRConfig")


function BRgui.ShowUserMenu(pid)
	TestBR.DebugLog(1, "Displaying menu to " .. Players[pid].name .. " (" .. pid .. ")")
	if TestBR.gameState == TestBR.GAME_STATE.NONE then
		menuHelper.DisplayMenu(pid, "testBR create lobby")
	elseif TestBR.gameState == TestBR.GAME_STATE.LOBBY then
		if TestBR.GetPlayerState(pid) == TestBR.PLAYER_STATE.SPECT then
			menuHelper.DisplayMenu(pid, "testBR join lobby")
		-- elseif TestBR.GetPlayerState(pid) == TestBR.PLAYER_STATE.JOINED then
		-- 	menuHelper.DisplayMenu(pid, "testBR ready lobby")
		end
	elseif TestBR.gameState == TestBR.GAME_STATE.INMATCH then

	end
end

function BRgui.OnButtonCreateLobby(pid)
	TestBR.CreateLobby(pid)
end

function BRgui.OnButtonJoinLobby(pid)
	TestBR.PlayerJoinLobby(pid)
end

function BRgui.OnButtonReady(pid)
	TestBR.PlayerSetReady(pid)
end

Menus["testBR create lobby"] = {
	text = color.Orange .. testBRConfig.menuTitle .. "\n" ..
			color.Yellow .. "No match running\n" ..
					color.White .. "You can create a new lobby!\n",
	buttons = {
			{ caption = "Create lobby",
				destinations =
				{
					menuHelper.destinations.setDefault(nil,
					{
						menuHelper.effects.runGlobalFunction("BRgui", "OnButtonCreateLobby", {menuHelper.variables.currentPid(), true})
					})
				}
			},
			{ caption = "Admin",
					displayConditions = {
						menuHelper.conditions.requireStaffRank(2)
					},
					destinations = {
						menuHelper.destinations.setDefault("help admin page 1")
					}
			},
			{ caption = "Exit", destinations = nil }
	}
}

Menus["testBR join lobby"] = {
	text = color.Orange .. testBRConfig.menuTitle .. "\n" ..
			color.Yellow .. "Available lobby!\n",
	buttons = {
			{ caption = "Join lobby",
				destinations =
				{
					menuHelper.destinations.setDefault(nil,
					{
						menuHelper.effects.runGlobalFunction("BRgui", "OnButtonJoinLobby", {menuHelper.variables.currentPid(), true})
					})
				}
			},
			{ caption = "Admin",
					displayConditions = {
						menuHelper.conditions.requireStaffRank(2)
					},
					destinations = {
						menuHelper.destinations.setDefault("help admin page 1")
					}
			},
			{ caption = "Exit", destinations = nil }
	}
}

return BRgui
