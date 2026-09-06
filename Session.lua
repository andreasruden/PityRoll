local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

local function ExitTieResolutionMode()
	for _, squareData in ipairs(State.gridSquares) do
		squareData.clickFrame.leaderIndicator:Hide()
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
	addon.HidePriorityFrame()

	if addon.Frames.pityRollFrame then
		addon.Frames.pityRollFrame:Hide()
		addon.UpdateButtonFrameButtons()
		addon.Frames.eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
		State.playerRolls = {}
	end

	if State.currentRollIsNoPity then
		State.currentRollIsNoPity = false
		addon.BroadcastNoPityFlag(false)
	end

	if not State.currentBossSession.isActive then
		addon.HideButtonFrame()
	end
end

function addon.AbortRollSession()
	local itemLink = State.currentRollItemLink
	addon.EndSession()

	if itemLink then
		for i = #State.currentBossSession.lootItems, 1, -1 do
			if State.currentBossSession.lootItems[i] == itemLink then
				table.remove(State.currentBossSession.lootItems, i)
				table.remove(State.currentBossSession.itemNames, i)
				break
			end
		end
	end

	State.currentRollItemLink = nil
	State.currentRollItemName = nil
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
			squareData.clickFrame.leaderIndicator:Show()
		end
	end

	local tiedList = table.concat(State.tiedPlayers, ", ")
	print("|cFFFFFF00TIE DETECTED:|r " .. tiedList)
	print("|cFF00FF00PityRoll:|r Click on a tied player (highlit by a crown) to select winner, then click Award Item again")

	addon.UpdateButtonFrameButtons()
end

local function GiveLootToWinner(winner)
	if not IsMasterLooter() then return end

	if GetNumLootItems() == 0 then
		print("|cFF00FF00PityRoll:|r Loot window is closed. Open it to award the item automatically.")
		return
	end

	local targetSlot
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == LOOT_SLOT_ITEM and GetLootSlotLink(slot) == State.currentRollItemLink then
			targetSlot = slot
			break
		end
	end

	if not targetSlot then return end

	-- Scan master loot candidates for this slot to find the winner's player index
	for i = 1, GetNumGroupMembers() do
		local candidate = GetMasterLootCandidate(targetSlot, i)
		if candidate == winner.name then
			GiveMasterLoot(targetSlot, i)
			return
		end
	end
end

function addon.GiveItemToPlayer(winner, itemLink)
	State.currentRollItemLink = itemLink
	GiveLootToWinner(winner)
	State.currentRollItemLink = nil
end

function addon.FinishRollSession(specifiedWinner)
	if specifiedWinner then
		specifiedWinner = addon.NormalizeName(specifiedWinner)
	end

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
			print("|cFFFF0000Error:|r Please select a winner by clicking on a tied player (highlit by a crown)")
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

	local awardedItemLink = State.currentRollItemLink
	local awardedItemName = State.currentRollItemName

	if awardedItemLink then
		for i = #State.currentBossSession.lootItems, 1, -1 do
			if State.currentBossSession.lootItems[i] == awardedItemLink then
				table.remove(State.currentBossSession.lootItems, i)
				table.remove(State.currentBossSession.itemNames, i)
				break
			end
		end
		GiveLootToWinner(winner)
		print("|cFF00FF00PityRoll:|r " .. awardedItemName .. " awarded to " .. winner.name)

		-- Record history entry
		local historyBossName = State.currentBossSession.isActive
			and State.currentBossSession.bossName
			or Constants.TRASH_LOOT_NAME
		addon.RecordHistoryEntry(
			historyBossName,
			awardedItemLink,
			awardedItemName,
			winner,
			results
		)

		State.currentRollItemLink = nil
		State.currentRollItemName = nil
	end

	for playerName, rollData in pairs(State.playerRolls) do
		if not rollData.ignored then
			State.encounterRollers[playerName] = true
		end
	end

	for playerName, rollData in pairs(State.playerRolls) do
		if playerName ~= winner.name and not rollData.ignored and not rollData.nonStandardRoll and not State.currentRollIsNoPity then
			local oldPity = PityRollDB.players[playerName] or 0
			local newPity = oldPity + Constants.PITY_INCREMENT
			local cappedPity = math.min(newPity, Constants.MAX_PITY)
			PityRollDB.players[playerName] = cappedPity
			addon.RecordPityChange(playerName, oldPity, cappedPity)
		end
	end

	local winnerIsNonStandard = State.playerRolls[winner.name].nonStandardRoll or State.currentRollIsNoPity
	if not winnerIsNonStandard then
		local oldPity = PityRollDB.players[winner.name] or 0
		PityRollDB.players[winner.name] = 0
		addon.RecordPityChange(winner.name, oldPity, 0)
	end

	if awardedItemLink then
		local pityMsg
		if winnerIsNonStandard then
			local remainingPity = PityRollDB.players[winner.name] or 0
			pityMsg = winner.name .. " has been awarded " .. awardedItemLink .. ". Their pity remains at " .. remainingPity .. "."
		else
			pityMsg = winner.name .. " has been awarded " .. awardedItemLink .. ". Their pity is now 0."
		end
		addon.WriteToChat(pityMsg)
	end

	State.hasFinishedRollSession = true

	addon.EndSession()
end

function addon.StartRollSessionWithItem(itemLink, itemName, noPity)
	State.currentRollItemLink = itemLink
	State.currentRollItemName = itemName
	State.currentRollIsNoPity = noPity or false
	addon.AnnounceRollItem(itemLink, noPity)
	addon.CreateButtonFrame()
	addon.CreatePityRollFrame()
	addon.UpdateButtonFrameButtons()
	addon.BroadcastPityData(noPity or false)
end

function addon.ExecuteDirectAward(itemLink, itemName, playerName)
	local oldPity = PityRollDB.players[playerName] or 0
	PityRollDB.players[playerName] = 0
	addon.RecordPityChange(playerName, oldPity, 0)

	for i = #State.currentBossSession.lootItems, 1, -1 do
		if State.currentBossSession.lootItems[i] == itemLink then
			table.remove(State.currentBossSession.lootItems, i)
			table.remove(State.currentBossSession.itemNames, i)
			break
		end
	end

	local winner = { name = playerName, rollValue = 0, rollBonus = 0, total = 0 }
	local historyBossName = State.currentBossSession.isActive
		and State.currentBossSession.bossName
		or Constants.TRASH_LOOT_NAME
	addon.RecordHistoryEntry(
		historyBossName,
		itemLink,
		itemName,
		winner,
		{}
	)

	State.encounterRollers[playerName] = true

	addon.GiveItemToPlayer(winner, itemLink)

	addon.WriteToChat(playerName .. " has been awarded " .. itemLink .. ". Their pity is now 0.")

	print("|cFF00FF00PityRoll:|r " .. itemName .. " directly awarded to " .. playerName)
	addon.UpdateButtonFrameButtons()
end

local pendingBossBeginName = ""

StaticPopupDialogs["PITYROLL_START_BOSS_SESSION"] = {
	text = "Start boss session for:",
	button1 = "Accept",
	button2 = "Cancel",
	hasEditBox = true,
	maxLetters = 50,
	OnShow = function(self)
		local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
		editBox:SetText(pendingBossBeginName)
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = function(self)
		local editBox = self.editBox or _G[self:GetName() .. "EditBox"]
		local name = editBox:GetText():trim()
		if name == "" then
			print("|cFFFF0000Error:|r Boss name cannot be empty")
			return
		end
		addon.BossBeginSession(name)
	end,
	EditBoxOnEnterPressed = function(self)
		local name = self:GetText():trim()
		if name == "" then
			print("|cFFFF0000Error:|r Boss name cannot be empty")
			return
		end
		addon.BossBeginSession(name)
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function addon.ShowBossBeginDialog()
	pendingBossBeginName = ""
	if UnitExists("target") then
		local targetName = UnitName("target")
		pendingBossBeginName = targetName and (targetName:match("([^-]+)") or targetName) or ""
	end
	StaticPopup_Show("PITYROLL_START_BOSS_SESSION")
end

function addon.BossBeginSession(bossName)
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to use /pr bossbegin")
		return
	end

	if not UnitIsGroupLeader("player") and not IsMasterLooter() then
		print("|cFFFF0000Error:|r You must be group leader or master looter to start a boss encounter")
		return
	end

	if not bossName or bossName:trim() == "" then
		print("|cFFFF0000Error:|r Boss name cannot be empty")
		return
	end

	State.currentBossSession.bossName = bossName
	State.currentBossSession.bossGuid = nil
	State.currentBossSession.lootItems = {}
	State.currentBossSession.itemNames = {}
	State.currentBossSession.startTime = time()
	State.currentBossSession.isActive = true

	State.hasFinishedRollSession = false
	addon.CreateButtonFrame()
	addon.UpdateButtonFrameButtons()

	print("|cFF00FF00PityRoll:|r Boss encounter started for " .. bossName)
end

local function BossEndSessionInternal()
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
		local oldPity = PityRollDB.players[playerName] or 0
		local newPity = oldPity + Constants.BOSS_PITY
		local cappedPity = math.min(newPity, Constants.MAX_PITY)
		PityRollDB.players[playerName] = cappedPity
		addon.RecordPityChange(playerName, oldPity, cappedPity)
	end

	if #nonRollers > 0 then
		local names = table.concat(nonRollers, ", ")
		print("|cFF00FF00PityRoll:|r Awarded +" .. Constants.BOSS_PITY .. " pity to " .. #nonRollers .. " non-rollers: " .. names)
	else
		print("|cFF00FF00PityRoll:|r All group members rolled - no pity awarded")
	end

	State.currentRollItemLink = nil
	State.currentRollItemName = nil
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

function addon.BossEndSession()
	BossEndSessionInternal()
end

local function EndBossNoPityInternal()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to end boss")
		return
	end

	print("|cFF00FF00PityRoll:|r Ending boss without awarding pity")

	State.currentRollItemLink = nil
	State.currentRollItemName = nil
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
	EndBossNoPityInternal()
end
