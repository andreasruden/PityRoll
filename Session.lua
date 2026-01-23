local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

local function ExitTieResolutionMode()
	for _, squareData in ipairs(State.gridSquares) do
		squareData.clickFrame.tieIndicator:Hide()
		squareData.clickFrame.selectionIndicator:Hide()
	end

	State.tieResolutionMode = false
	State.tiedPlayers = nil
	State.selectedWinner = nil

	addon.UpdateButtonFrameButtons()
end

function addon.EndSession()
	if State.tieResolutionMode then
		ExitTieResolutionMode()
	end

	addon.BroadcastClear()

	if addon.Frames.pityRollFrame then
		addon.Frames.pityRollFrame:Hide()
		addon.UpdateButtonFrameButtons()
		addon.Frames.eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
		State.playerRolls = {}
	end
end

local function DetectTie(results)
	if #results < 2 then return nil end

	local highestTotal = results[1].total
	local tiedPlayers = {}

	for _, result in ipairs(results) do
		if result.total == highestTotal then
			table.insert(tiedPlayers, result.name)
		else
			break
		end
	end

	if #tiedPlayers > 1 then
		return tiedPlayers
	end

	return nil
end

local function EnterTieResolutionMode(tiedPlayersList)
	State.tieResolutionMode = true
	State.tiedPlayers = tiedPlayersList
	State.selectedWinner = nil

	for _, squareData in ipairs(State.gridSquares) do
		local playerName = squareData.clickFrame.playerName
		local isTiedPlayer = false

		for _, tiedName in ipairs(State.tiedPlayers) do
			if tiedName == playerName then
				isTiedPlayer = true
				break
			end
		end

		if isTiedPlayer then
			squareData.clickFrame.tieIndicator:Show()
		end
	end

	local tiedList = table.concat(State.tiedPlayers, ", ")
	print("|cFFFFFF00TIE DETECTED:|r " .. tiedList)
	print("|cFF00FF00PityRoll:|r Click on a tied player (highlighted in gold) to select winner, then click Award Item again")

	addon.UpdateButtonFrameButtons()
end

function addon.FinishRollSession(specifiedWinner)
	if not next(State.playerRolls) then
		print("|cFF00FF00PityRoll:|r No rolls recorded. Closing window.")
		addon.EndSession()
		return
	end

	local results = {}
	for playerName, rollData in pairs(State.playerRolls) do
		if not rollData.ignored then
			table.insert(results, {
				name = playerName,
				rollValue = rollData.rollValue,
				rollBonus = rollData.rollBonus,
				total = rollData.rollValue + rollData.rollBonus
			})
		end
	end

	if #results == 0 then
		print("|cFFFF0000Error:|r No valid rolls to process. All rolls are ignored.")
		return
	end

	table.sort(results, function(a, b) return a.total > b.total end)

	local tiedPlayersList = DetectTie(results)

	if tiedPlayersList then
		if specifiedWinner then
			local winnerIsValid = false
			for _, name in ipairs(tiedPlayersList) do
				if name:lower() == specifiedWinner:lower() then
					winnerIsValid = true
					specifiedWinner = name
					break
				end
			end

			if not winnerIsValid then
				local tiedList = table.concat(tiedPlayersList, ", ")
				print("|cFFFF0000Error:|r Specified winner '" .. specifiedWinner .. "' is not among tied players: " .. tiedList)
				return
			end

			if State.tieResolutionMode then
				ExitTieResolutionMode()
			end
		elseif not State.tieResolutionMode then
			EnterTieResolutionMode(tiedPlayersList)
			return
		elseif not State.selectedWinner then
			print("|cFFFF0000Error:|r Please select a winner by clicking on a tied player (highlighted in gold)")
			return
		else
			specifiedWinner = State.selectedWinner
			ExitTieResolutionMode()
		end
	else
		if State.tieResolutionMode then
			ExitTieResolutionMode()
		end
	end

	local message = "PityRoll Results: "
	local maxLength = 255

	for i, result in ipairs(results) do
		local formatted = result.name .. " (" .. result.rollValue .. "+" .. result.rollBonus .. "=" .. result.total .. ")"
		local separator = (i == 1) and "" or ", "

		if #message + #separator + #formatted > maxLength and message ~= "PityRoll Results: " then
			addon.WriteToChat(message)
			message = formatted
		else
			message = message .. separator .. formatted
		end
	end

	addon.WriteToChat(message)

	local winner
	if specifiedWinner then
		for _, result in ipairs(results) do
			if result.name == specifiedWinner then
				winner = result
				break
			end
		end
	else
		winner = results[1]
	end
	addon.WriteToChat("WINNER: " .. winner.name .. " (" .. winner.total .. ")")

	for playerName, rollData in pairs(State.playerRolls) do
		if not rollData.ignored then
			State.encounterRollers[playerName] = true
		end
	end

	for playerName, rollData in pairs(State.playerRolls) do
		if playerName ~= winner.name and not rollData.ignored then
			local newPity = (PityRollDB.players[playerName] or 0) + Constants.PITY_INCREMENT
			PityRollDB.players[playerName] = math.min(newPity, Constants.MAX_PITY)
		end
	end

	PityRollDB.players[winner.name] = 0

	State.hasFinishedRollSession = true

	addon.EndSession()
end

function addon.NewRollSession()
	addon.CreatePityRollFrame()
	addon.UpdateButtonFrameButtons()
	addon.BroadcastPityData()
end

function addon.CaptureBossLootData()
	if not UnitExists("target") then
		return false, "You must target a mob to start a boss session"
	end

	local numLootItems = GetNumLootItems()
	if numLootItems == 0 then
		return false, "You must open the loot window first (right-click the boss corpse)"
	end

	local bossName = UnitName("target")
	if not bossName then
		return false, "Unable to read target name"
	end

	bossName = bossName:match("([^-]+)") or bossName
	local bossGuid = UnitGUID("target")

	State.currentBossSession.bossName = bossName
	State.currentBossSession.bossGuid = bossGuid
	State.currentBossSession.lootItems = {}
	State.currentBossSession.itemNames = {}
	State.currentBossSession.startTime = time()
	State.currentBossSession.isActive = true

	for slot = 1, numLootItems do
		local itemLink = GetLootSlotLink(slot)
		local slotType = GetLootSlotType(slot)

		if itemLink and slotType == LOOT_SLOT_ITEM then
			table.insert(State.currentBossSession.lootItems, itemLink)
			local itemName = GetItemInfo(itemLink)
			if itemName then
				table.insert(State.currentBossSession.itemNames, itemName)
			end
		end
	end

	return true, nil
end

function addon.BossBeginSession()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to use /pr bossbegin")
		return
	end

	local success, errorMsg = addon.CaptureBossLootData()
	if not success then
		print("|cFFFF0000Error:|r " .. errorMsg)
		return
	end

	State.hasFinishedRollSession = false
	addon.CreateButtonFrame()
	addon.UpdateButtonFrameButtons()

	local itemCount = #State.currentBossSession.lootItems
	local bossName = State.currentBossSession.bossName
	print("|cFF00FF00PityRoll:|r Boss encounter started for " .. bossName .. " (" .. itemCount .. " items)")

	if itemCount > 0 then
		print("|cFF00FF00PityRoll:|r Dropped items:")
		for i, itemName in ipairs(State.currentBossSession.itemNames) do
			print("  " .. i .. ". " .. itemName)
		end
	end
end

function addon.BossEndSession()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to use /pr bossend")
		return
	end

	local allMembers = addon.GetAllGroupMembers()
	local nonRollers = {}

	for _, memberName in ipairs(allMembers) do
		if not State.encounterRollers[memberName] then
			table.insert(nonRollers, memberName)
		end
	end

	for _, playerName in ipairs(nonRollers) do
		local newPity = (PityRollDB.players[playerName] or 0) + 1
		PityRollDB.players[playerName] = math.min(newPity, Constants.MAX_PITY)
	end

	if #nonRollers > 0 then
		local names = table.concat(nonRollers, ", ")
		print("|cFF00FF00PityRoll:|r Awarded +1 pity to " .. #nonRollers .. " non-rollers: " .. names)
	else
		print("|cFF00FF00PityRoll:|r All group members rolled - no pity awarded")
	end

	State.encounterRollers = {}
	State.playerRolls = {}
	State.currentBossSession = {
		bossName = nil,
		bossGuid = nil,
		lootItems = {},
		itemNames = {},
		startTime = nil,
		isActive = false
	}

	if addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown() then
		addon.EndSession()
	end

	addon.HideButtonFrame()
end

function addon.EndBossNoPity()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to end boss")
		return
	end

	print("|cFF00FF00PityRoll:|r Ending boss without awarding pity")

	State.encounterRollers = {}
	State.playerRolls = {}
	State.currentBossSession = {
		bossName = nil,
		bossGuid = nil,
		lootItems = {},
		itemNames = {},
		startTime = nil,
		isActive = false
	}

	if addon.Frames.pityRollFrame and addon.Frames.pityRollFrame:IsShown() then
		addon.EndSession()
	end

	addon.HideButtonFrame()
end
