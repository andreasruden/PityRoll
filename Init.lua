local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

PityRollDB = PityRollDB or {}

-- LibUIDropDownMenu for context menu
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local minimapMenuFrame = LibDD:Create_UIDropDownMenu("PityRollMinimapMenuFrame", UIParent)

local function GetMinimapMenuTable()
	local menuTable = {
		{
			text = "Help",
			func = function()
				print("|cFF00FF00PityRoll:|r Left-click to start boss encounter")
				print("|cFF00FF00PityRoll:|r Use /pr report to show pity values")
				print("|cFF00FF00PityRoll:|r Use /pr info <name> for player details")
			end,
			notCheckable = true,
		},
		{
			text = "Pity Report",
			func = function()
				addon.ReportPityValues()
			end,
			notCheckable = true,
		},
		{
			text = "Query State of Followers",
			func = function()
				addon.QueryFollowerState()
			end,
			notCheckable = true,
		},
	}

	if addon.Frames.buttonFrame and addon.Frames.buttonFrame:IsShown() then
		table.insert(menuTable, {
			text = "End Boss (no boss pity)",
			func = function()
				addon.EndBossNoPity()
			end,
			notCheckable = true,
		})
	end

	table.insert(menuTable, {
		text = "Cancel",
		func = function() end,
		notCheckable = true,
	})

	return menuTable
end

-- LibDataBroker minimap button
local LDB = LibStub("LibDataBroker-1.1", true)
local icon = LDB and LDB:NewDataObject("PityRoll", {
	type = "launcher",
	text = "PityRoll",
	icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
	OnClick = function(self, button)
		if button == "LeftButton" then
			if addon.Frames.buttonFrame and addon.Frames.buttonFrame:IsShown() then
				print("|cFF00FF00PityRoll:|r Boss encounter already active")
				return
			end
			addon.BossBeginSession()
		elseif button == "RightButton" then
			local menuTable = GetMinimapMenuTable()
			LibDD:EasyMenu(menuTable, minimapMenuFrame, "cursor", 0, 0, "MENU", 2)
		end
	end,
	OnTooltipShow = function(tooltip)
		if not tooltip or not tooltip.AddLine then return end
		tooltip:AddLine("PityRoll")
		tooltip:AddLine("|cFFFFFFFFLeft-click:|r Start boss encounter")
		tooltip:AddLine("|cFFFFFFFFRight-click:|r Show menu")
		if addon.Frames.buttonFrame and addon.Frames.buttonFrame:IsShown() then
			tooltip:AddLine("|cFF00FF00Boss encounter active|r")
		end
	end,
})

local function HandleWhisperCommand(message, sender)
	sender = sender:match("([^-]+)")

	local lowerMsg = message:lower():trim()
	if lowerMsg ~= "!pity" then
		return
	end

	local currentTime = GetTime()
	local windowStart = currentTime - Constants.RATE_LIMIT_WINDOW

	local newTimestamps = {}
	for _, timestamp in ipairs(State.whisperTimestamps) do
		if timestamp > windowStart then
			table.insert(newTimestamps, timestamp)
		end
	end
	State.whisperTimestamps = newTimestamps

	if #State.whisperTimestamps >= Constants.MAX_WHISPERS_PER_WINDOW then
		return
	end

	table.insert(State.whisperTimestamps, currentTime)

	local normalizedName = sender:sub(1,1):upper() .. sender:sub(2):lower()

	local pityValue = PityRollDB.players[normalizedName]

	if pityValue then
		SendChatMessage(normalizedName .. "'s current pity: " .. pityValue .. "/" .. Constants.MAX_PITY, "WHISPER", nil, sender)
	else
		SendChatMessage(normalizedName .. " is not in the PityRoll database yet.", "WHISPER", nil, sender)
	end
end

local function HandleSystemMessage(message)
	if not addon.Frames.pityRollFrame or not addon.Frames.pityRollFrame:IsShown() then
		print("|cFF00FF00PityRoll DEBUG:|r Frame not shown, ignoring")
		return
	end

	-- Pattern matches: "PlayerName rolls 42 (1-100)"
	local playerName, rollValue, minRoll, maxRoll = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")

	if not playerName then
		return
	end

	print("|cFF00FF00PityRoll DEBUG:|r Matched roll - Name: " .. playerName .. ", Roll: " .. rollValue .. ", Range: " .. minRoll .. "-" .. maxRoll)

	minRoll = tonumber(minRoll)
	maxRoll = tonumber(maxRoll)
	if minRoll ~= 1 or maxRoll ~= 100 then
		print("|cFF00FF00PityRoll DEBUG:|r Not a 1-100 roll, ignoring")
		return
	end

	rollValue = tonumber(rollValue)

	playerName = playerName:match("([^-]+)") or playerName
	print("|cFF00FF00PityRoll DEBUG:|r Clean name: " .. playerName)

	if State.playerRolls[playerName] then
		print("|cFF00FF00PityRoll DEBUG:|r Ignoring duplicate roll from " .. playerName)
		return
	end

	local className = addon.GetPlayerClass(playerName)

	if not className then
		print("|cFFFF0000PityRoll:|r Could not determine class for " .. playerName .. " - player may not be in your raid/party")
		return
	end

	print("|cFF00FF00PityRoll DEBUG:|r Found class: " .. className .. " for " .. playerName)
	rollBonus = PityRollDB.players[playerName] or 0
	addon.AddSquareToGrid(className, playerName, rollValue, rollBonus)

	State.playerRolls[playerName] = {
		rollValue = rollValue,
		rollBonus = rollBonus,
		className = className,
		ignored = false
	}
end

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then
			print("|cFF00FF00PityRoll|r addon loaded!")

			if not PityRollDB.initialized then
				PityRollDB.initialized = true
				PityRollDB.players = {}
				PityRollDB.version = "1.0.0"
				PityRollDB.buttonFramePosition = {
					point = "CENTER",
					relativeTo = nil,
					relativePoint = "CENTER",
					xOffset = 0,
					yOffset = -200
				}
				PityRollDB.pityFramePosition = {
					point = "CENTER",
					relativeTo = nil,
					relativePoint = "CENTER",
					xOffset = 0,
					yOffset = 0
				}
				PityRollDB.minimap = {
					hide = false,
				}
				PityRollDB.syncSource = nil
		print("|cFF00FF00PityRoll|r: First time setup complete")
			end

			-- Initialize History DB
			if not PityRollHistoryDB then
				PityRollHistoryDB = {
					initialized = true,
					version = "1.0.0",
					encounters = {}
				}
				print("|cFF00FF00PityRoll History:|r First time setup complete")
			end

			-- Migration for existing users
			if PityRollHistoryDB and not PityRollHistoryDB.version then
				PityRollHistoryDB.version = "1.0.0"
				PityRollHistoryDB.encounters = PityRollHistoryDB.encounters or {}
			end

			C_ChatInfo.RegisterAddonMessagePrefix(Constants.ADDON_PREFIX)

			-- Register minimap button with saved position
			local LibDBIcon = LibStub("LibDBIcon-1.0", true)
			if LibDBIcon and icon then
				if not PityRollDB.minimap then
					PityRollDB.minimap = { hide = false }
				end
				LibDBIcon:Register("PityRoll", icon, PityRollDB.minimap)
				if not PityRollDB.minimap.hide then
					LibDBIcon:Show("PityRoll")
				end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		print("|cFF00FF00PityRoll|r: Welcome, " .. UnitName("player") .. "!")
	elseif event == "CHAT_MSG_SYSTEM" then
		local message = ...
		HandleSystemMessage(message)
	elseif event == "CHAT_MSG_WHISPER" then
		local message, sender = ...
		HandleWhisperCommand(message, sender)
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, channel, sender = ...
		if prefix == Constants.ADDON_PREFIX then
			if message == "CLEAR" then
				State.observedPity = {}
			elseif message:sub(1, 5) == "PITY:" then
				local name, value = message:match("^PITY:(.+):(%d+)$")
				if name and value then
					State.observedPity[name] = tonumber(value)
				end
			elseif message:sub(1, 5) == "SYNC_" then
				addon.HandleSyncMessage(message, channel, sender)
			end
		end
	end
end

addon.Frames.eventFrame = CreateFrame("Frame")
addon.Frames.eventFrame:RegisterEvent("ADDON_LOADED")
addon.Frames.eventFrame:RegisterEvent("PLAYER_LOGIN")
addon.Frames.eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
addon.Frames.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
addon.Frames.eventFrame:SetScript("OnEvent", OnEvent)

-- Chat filter to modify roll messages with pity bonus
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, message, ...)
	-- Only process if pity frame visible or using follower mode
	if not (addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown()) and next(State.observedPity) == nil then
		return false
	end

	local playerName, rollValue, minRoll, maxRoll = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
	if not playerName then
		return false
	end

	if minRoll ~= "1" or maxRoll ~= "100" then
		return false
	end

	-- Strip realm name for lookup
	local cleanName = playerName:match("([^-]+)") or playerName

	local pity = State.observedPity[cleanName] or (PityRollDB.players and PityRollDB.players[cleanName]) or 0
	if pity == 0 then
		return false
	end

	local total = tonumber(rollValue) + pity
	local newMessage = string.format("%s rolls %d (%s+%d) (1-100)", playerName, total, rollValue, pity)
	return false, newMessage, ...
end)

SLASH_PITYROLL1 = "/pityroll"
SLASH_PITYROLL2 = "/pr"
SlashCmdList["PITYROLL"] = function(msg)
	msg = msg:trim()
	local lowerMsg = msg:lower()

	if lowerMsg == "" or lowerMsg == "help" then
		print("|cFF00FF00PityRoll|r Commands:")
		print("/pityroll help - Show this help message")
		print("/pityroll version - Show addon version")
		print("/pityroll new - Open PityRoll frame")
		print("/pityroll add <class> <name> <roll> <bonus> - Add a player's roll to the grid")
		print("/pityroll finish [PlayerName] - Finish roll session and show sorted results (specify winner if tied)")
		print("/pityroll bossbegin - Show button frame for boss encounter")
		print("/pityroll bossend - Award +1 pity to non-rollers and reset tracking")
		print("/pityroll report - Show pity values for all party/raid members")
		print("/pityroll info <name> - Show pity value for a specific character")
		print("/pityroll addpity <name> <amount> - Manually add pity points to a character")
		print("/pityroll setroll <name> <value> - Manually set a player's roll (1-100)")
		print("/pityroll setsource <name> - Set sync leader to follow")
		print("/pityroll clearsource - Stop following sync leader")
		print("/pityroll abort - Close the PityRoll frame")
	elseif lowerMsg == "version" then
		print("|cFF00FF00PityRoll|r version: " .. (PityRollDB.version or "1.0.0"))
	elseif lowerMsg == "new" then
		addon.NewRollSession()
	elseif lowerMsg:match("^add%s+") then
		local args = {}
		for arg in msg:gmatch("%S+") do
			table.insert(args, arg)
		end

		if #args < 5 then
			print("|cFFFF0000Error:|r Usage: /pr add <class> <name> <roll> <bonus>")
			print("|cFF00FF00Example:|r /pr add warrior Thrall 95 10")
		else
			addon.AddSquareToGrid(args[2], args[3], args[4], args[5])
		end
	elseif lowerMsg == "abort" then
		if addon.Frames.pityRollFrame then
			addon.EndSession()
			print("|cFF00FF00PityRoll|r: Frame closed")
		else
			print("|cFF00FF00PityRoll|r: No frame is currently open")
		end
	elseif lowerMsg:match("^finish") then
		local winnerName = msg:match("^finish%s+(.+)")
		addon.FinishRollSession(winnerName)
	elseif lowerMsg == "bossbegin" then
		addon.BossBeginSession()
	elseif lowerMsg == "bossend" then
		addon.BossEndSession()
	elseif lowerMsg == "report" then
		addon.ReportPityValues()
	elseif lowerMsg:match("^info%s+") then
		local characterName = msg:match("^info%s+(.+)")
		addon.ShowPityInfo(characterName)
	elseif lowerMsg:match("^addpity%s+") then
		local args = {}
		for arg in msg:gmatch("%S+") do
			table.insert(args, arg)
		end
		if #args < 3 then
			print("|cFFFF0000Error:|r Usage: /pr addpity <name> <amount>")
		else
			addon.AddPity(args[2], args[3])
		end
	elseif lowerMsg:match("^setroll%s+") then
		local args = {}
		for arg in msg:gmatch("%S+") do
			table.insert(args, arg)
		end
		if #args < 3 then
			print("|cFFFF0000Error:|r Usage: /pr setroll <name> <value>")
		else
			addon.SetRoll(args[2], args[3])
		end
	elseif lowerMsg:match("^history") then
		local subCommand = msg:match("^history%s+(.+)")

		if not subCommand or subCommand == "" then
			addon.DumpHistory(10)
		elseif subCommand:match("^%d+$") then
			addon.DumpHistory(tonumber(subCommand))
		elseif subCommand == "all" then
			addon.DumpHistory(nil)
		elseif subCommand == "clear confirm" then
			PityRollHistoryDB.encounters = {}
			print("|cFF00FF00PityRoll:|r History cleared")
		elseif subCommand == "clear" then
			addon.ClearHistory()
		elseif subCommand == "stats" then
			local encounters, items = addon.GetHistoryStats()
			print(string.format("|cFF00FF00PityRoll History:|r %d encounters, %d items awarded", encounters, items))
		else
			print("|cFFFF0000Error:|r Unknown history command")
		end
	elseif lowerMsg:match("^setsource%s+") then
		local sourceName = msg:match("^setsource%s+(.+)")
		addon.SetSyncSource(sourceName)
	elseif lowerMsg == "clearsource" then
		addon.ClearSyncSource()
	else
		print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
	end
end
