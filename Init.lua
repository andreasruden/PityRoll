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

	local syncState = addon.GetSyncState()
	if syncState and syncState.outOfSyncFollowers and #syncState.outOfSyncFollowers > 0 then
		for _, followerName in ipairs(syncState.outOfSyncFollowers) do
			table.insert(menuTable, {
				text = "Force Update " .. followerName,
				func = function()
					addon.ShowForceUpdateConfirmation(followerName)
				end,
				notCheckable = true,
			})
		end
	end

	if State.currentBossSession.isActive then
		table.insert(menuTable, {
			text = "End Boss (no boss pity)",
			func = function()
				addon.EndBossNoPity()
			end,
			notCheckable = true,
		})
	end

	table.insert(menuTable, {
		text = "Export History",
		func = function()
			addon.ExportPityChanges()
		end,
		notCheckable = true,
	})

	table.insert(menuTable, {
		text = "Import History",
		func = function()
			addon.ShowImportDialog()
		end,
		notCheckable = true,
	})

	if PityRollHistoryDB and #PityRollHistoryDB.encounters > 0 then
		local numEncounters = #PityRollHistoryDB.encounters
		table.insert(menuTable, {
			text = string.format("Clear History (%d entries)", numEncounters),
			func = function()
				addon.ShowClearHistoryConfirmation()
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
			if State.currentBossSession.isActive then
				print("|cFF00FF00PityRoll:|r Boss encounter already active")
				return
			end
			addon.ShowBossBeginDialog()
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
		if State.currentBossSession.isActive then
			tooltip:AddLine("|cFF00FF00Boss encounter active|r")
		end
	end,
})

local function IsWhisperRateLimited()
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
		return true
	end

	table.insert(State.whisperTimestamps, currentTime)
	return false
end

local function HandleWhisperCommand(message, sender)
	sender = sender:match("([^-]+)")

	local lowerMsg = message:lower():trim()

	if lowerMsg == "!pity" then
		if IsWhisperRateLimited() then
			return
		end

		local normalizedName = addon.NormalizeName(sender)

		local pityValue = PityRollDB.players[normalizedName]

		if pityValue then
			SendChatMessage(normalizedName .. "'s current pity: " .. pityValue .. "/" .. Constants.MAX_PITY, "WHISPER", nil, sender)
		else
			SendChatMessage(normalizedName .. " is not in the PityRoll database yet.", "WHISPER", nil, sender)
		end
	elseif lowerMsg:match("^!prio%s") then
		local itemId = tonumber(message:match("item:(%d+)"))
		if not itemId then
			return
		end

		if IsWhisperRateLimited() then
			return
		end

		addon.GetPriorityMessageForItemId(itemId, function(response, err, comment)
			SendChatMessage(response or err, "WHISPER", nil, sender)
			if response and comment then
				SendChatMessage(comment, "WHISPER", nil, sender)
			end
		end)
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
	if minRoll ~= 1 or (maxRoll ~= 100 and maxRoll ~= 99) then
		print("|cFF00FF00PityRoll DEBUG:|r Not a 1-100 or 1-99 roll, ignoring")
		return
	end

	rollValue = tonumber(rollValue)

	playerName = addon.NormalizeName(playerName)
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
	local isNonStandard = maxRoll ~= 100
	rollBonus = (isNonStandard or State.currentRollIsNoPity) and 0 or (PityRollDB.players[playerName] or 0)

	-- Auto-ignore a /roll 99 if any active pity roll already exists
	local startIgnored = false
	if isNonStandard then
		for _, rollData in pairs(State.playerRolls) do
			if not rollData.nonStandardRoll and not rollData.ignored then
				startIgnored = true
				break
			end
		end
	end

	State.playerRolls[playerName] = {
		rollValue = rollValue,
		rollBonus = rollBonus,
		className = className,
		ignored = startIgnored,
		nonStandardRoll = isNonStandard
	}

	addon.AddSquareToGrid(className, playerName, rollValue, rollBonus, isNonStandard, startIgnored)

	-- When a pity roll arrives, auto-ignore all existing /roll 99 entries
	if not isNonStandard then
		local anyIgnored = false
		for _, rollData in pairs(State.playerRolls) do
			if rollData.nonStandardRoll and not rollData.ignored then
				rollData.ignored = true
				anyIgnored = true
			end
		end
		if anyIgnored then
			addon.RegenerateGrid()
		end
	end
end

local function OnEvent(self, event, ...)
	if event == "LOOT_OPENED" then
		addon.AnnounceRareDrops()
	elseif event == "TRADE_SHOW" then
		addon.State.tradePartner = UnitName("NPC")
		addon.State.tradeItems = nil
	elseif event == "TRADE_ACCEPT_UPDATE" then
		local playerAccepted = ...
		if playerAccepted == 1 then
			addon.SnapshotTradeItems()
		end
	elseif event == "UI_INFO_MESSAGE" then
		local _, message = ...
		if message == ERR_TRADE_COMPLETE then
			addon.AnnounceTrade()
		end
	elseif event == "ADDON_LOADED" then
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
				PityRollDB.priorityFramePosition = {
					point = "CENTER",
					relativeTo = nil,
					relativePoint = "CENTER",
					xOffset = 200,
					yOffset = 100
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
					encounters = {},
					pityChanges = {}
				}
				print("|cFF00FF00PityRoll History:|r First time setup complete")
			end

			-- Migration for existing users
			if PityRollHistoryDB and not PityRollHistoryDB.version then
				PityRollHistoryDB.version = "1.0.0"
				PityRollHistoryDB.encounters = PityRollHistoryDB.encounters or {}
			end

			-- Migration for pityChanges
			if PityRollHistoryDB and not PityRollHistoryDB.pityChanges then
				PityRollHistoryDB.pityChanges = {}
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
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		local itemId = ...
		addon.OnItemInfoReceived(itemId)
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, channel, sender = ...
		if prefix == Constants.ADDON_PREFIX then
			if message == "CLEAR" then
				State.observedPity = {}
			elseif message == "NOPITY_ON" then
				State.currentRollIsNoPity = true
			elseif message == "NOPITY_OFF" then
				State.currentRollIsNoPity = false
			elseif message:sub(1, 10) == "PITYBATCH:" then
				local rest = message:sub(11)
				local flag, entriesStr = rest:match("^(%d):(.*)$")
				if flag then
					State.currentRollIsNoPity = (flag == "1")
					if flag == "0" then
						for entry in entriesStr:gmatch("[^,]+") do
							local name, value = entry:match("^(.+):(%d+)$")
							if name and value then
								State.observedPity[addon.NormalizeName(name)] = tonumber(value)
							end
						end
					end
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
addon.Frames.eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
addon.Frames.eventFrame:RegisterEvent("LOOT_OPENED")
addon.Frames.eventFrame:RegisterEvent("TRADE_SHOW")
addon.Frames.eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
addon.Frames.eventFrame:RegisterEvent("UI_INFO_MESSAGE")
addon.Frames.eventFrame:SetScript("OnEvent", OnEvent)

-- Chat filter to modify roll messages with pity bonus
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, message, ...)
	-- Only process if pity frame visible or using follower mode
	if not (addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown()) and next(State.observedPity) == nil then
		return false
	end

	if State.currentRollIsNoPity then
		return false
	end

	local playerName, rollValue, minRoll, maxRoll = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
	if not playerName then
		return false
	end

	if minRoll ~= "1" or maxRoll ~= "100" then
		return false
	end

	local cleanName = addon.NormalizeName(playerName)

	-- Prefer our own authoritative data when we're running the session;
	-- only fall back to broadcast data when we're a follower.
	local pity
	if addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown() then
		pity = (PityRollDB.players and PityRollDB.players[cleanName]) or 0
	else
		pity = State.observedPity[cleanName] or 0
	end
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
		print("/pityroll add <class> <name> <roll> <bonus> - Add a player's roll to the grid")
		print("/pityroll finish [PlayerName] - Finish roll session and show sorted results (specify winner if tied)")
		print("/pityroll bossbegin - Show button frame for boss encounter")
		print("/pityroll bossend - Award +" .. Constants.BOSS_PITY .. " pity to non-rollers and reset tracking")
		print("/pityroll report - Show pity values for all party/raid members")
		print("/pityroll info <name> - Show pity value for a specific character")
		print("/pityroll addpity <name> <amount> - Manually add pity points to a character")
		print("/pityroll setroll <name> <value> - Manually set a player's roll (1-100)")
		print("/pityroll priorities <item id> - Show loot priority for an item")
		print("/pityroll setsource <name> - Set sync leader to follow")
		print("/pityroll clearsource - Stop following sync leader")
		print("/pityroll abort - Close the PityRoll frame")
	elseif lowerMsg == "version" then
		print("|cFF00FF00PityRoll|r version: " .. (PityRollDB.version or "1.0.0"))
	elseif lowerMsg:match("^add%s+") then
		local args = {}
		for arg in msg:gmatch("%S+") do
			table.insert(args, arg)
		end

		if #args < 5 then
			print("|cFFFF0000Error:|r Usage: /pr add <class> <name> <roll> <bonus>")
			print("|cFF00FF00Example:|r /pr add warrior Thrall 95 10")
		else
			addon.AddSquareToGrid(args[2], addon.NormalizeName(args[3]), args[4], args[5])
		end
	elseif lowerMsg == "abort" then
		if addon.Frames.pityRollFrame then
			addon.AbortRollSession()
			print("|cFF00FF00PityRoll|r: Frame closed")
		else
			print("|cFF00FF00PityRoll|r: No frame is currently open")
		end
	elseif lowerMsg:match("^finish") then
		local winnerName = msg:match("^finish%s+(.+)")
		addon.FinishRollSession(winnerName)
	elseif lowerMsg == "bossbegin" or lowerMsg:match("^bossbegin%s+") then
		local name = msg:match("^bossbegin%s+(.+)")
		if not name and UnitExists("target") then
			local targetName = UnitName("target")
			name = targetName and (targetName:match("([^-]+)") or targetName) or nil
		end
		addon.BossBeginSession(name)
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
	elseif lowerMsg:match("^priorities%s+") then
		local itemId = tonumber(msg:match("^priorities%s+(%d+)"))
		if not itemId then
			print("|cFFFF0000Error:|r Usage: /pr priorities <item id>")
		else
			addon.PrintPriorityForItemId(itemId)
		end
	elseif lowerMsg:match("^setsource%s+") then
		local sourceName = msg:match("^setsource%s+(.+)")
		addon.SetSyncSource(sourceName)
	elseif lowerMsg == "clearsource" then
		addon.ClearSyncSource()
	elseif lowerMsg:match("^export") then
		addon.ExportPityChanges()
	else
		print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
	end
end
