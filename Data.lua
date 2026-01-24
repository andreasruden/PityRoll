local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

function addon.BroadcastPityData()
	local channel = addon.GetGroupChannel()
	if not channel then return end

	for playerName, pityValue in pairs(PityRollDB.players) do
		C_ChatInfo.SendAddonMessage(Constants.ADDON_PREFIX, "PITY:" .. playerName .. ":" .. pityValue, channel)
	end
end

function addon.BroadcastClear()
	local channel = addon.GetGroupChannel()
	if not channel then return end
	C_ChatInfo.SendAddonMessage(Constants.ADDON_PREFIX, "CLEAR", channel)
end

function addon.ReportPityValues()
	local allMembers = addon.GetAllGroupMembers()

	local pityList = {}
	for _, memberName in ipairs(allMembers) do
		local pityValue = PityRollDB.players[memberName] or 0
		table.insert(pityList, {name = memberName, pity = pityValue})
	end

	if #pityList == 0 then
		print("|cFF00FF00Pity Report:|r No group members found")
		return
	end

	table.sort(pityList, function(a, b) return a.name < b.name end)

	local message = "Pity Report: "
	local maxLength = 255

	for i, entry in ipairs(pityList) do
		local formatted = entry.name .. ": " .. entry.pity
		local separator = (i == 1) and "" or ", "

		if #message + #separator + #formatted > maxLength and message ~= "Pity Report: " then
			addon.WriteToChat(message)
			message = formatted
		else
			message = message .. separator .. formatted
		end
	end

	addon.WriteToChat(message)
end

function addon.ShowPityInfo(characterName)
	if not characterName or characterName == "" then
		print("|cFFFF0000Error:|r Please provide a character name. Usage: /pr info <name>")
		return
	end

	characterName = characterName:sub(1,1):upper() .. characterName:sub(2):lower()

	local pityValue = PityRollDB.players[characterName]

	if pityValue then
		print(string.format("|cFF00FF00Pity Info:|r %s has %d pity points", characterName, pityValue))
	else
		print(string.format("|cFFFFFF00Warning:|r No pity data found for character '%s'", characterName))
	end
end

function addon.AddPity(characterName, amount)
	if not characterName or characterName == "" then
		print("|cFFFF0000Error:|r Please provide a character name. Usage: /pr addpity <name> <amount>")
		return
	end

	if not amount or amount == "" then
		print("|cFFFF0000Error:|r Please provide an amount. Usage: /pr addpity <name> <amount>")
		return
	end

	local pityAmount = tonumber(amount)
	if not pityAmount or pityAmount == 0 then
		print("|cFFFF0000Error:|r Amount must be a non-zero number")
		return
	end

	characterName = characterName:sub(1,1):upper() .. characterName:sub(2):lower()

	if PityRollDB.players[characterName] == nil then
		print(string.format("|cFFFF0000Error:|r Character '%s' not found in pity database.", characterName))
		return
	end

	local oldPity = PityRollDB.players[characterName]
	local newPity = math.max(0, math.min(oldPity + pityAmount, Constants.MAX_PITY))
	local actualChange = newPity - oldPity

	PityRollDB.players[characterName] = newPity
	addon.RecordPityChange(characterName, oldPity, newPity)

	local verb = actualChange >= 0 and "Added" or "Removed"
	local sign = actualChange >= 0 and "+" or ""

	if actualChange ~= pityAmount then
		if newPity == Constants.MAX_PITY then
			print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity to %s (was: %d, now: %d - CAPPED AT MAXIMUM)", verb, sign, actualChange, characterName, oldPity, newPity))
		elseif newPity == 0 then
			print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity from %s (was: %d, now: %d - FLOORED AT ZERO)", verb, sign, actualChange, characterName, oldPity, newPity))
		end
	else
		print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity to %s (was: %d, now: %d)", verb, sign, actualChange, characterName, oldPity, newPity))
	end
end

function addon.SetRoll(characterName, newRollValue)
	if not characterName or characterName == "" then
		print("|cFFFF0000Error:|r Please provide a character name. Usage: /pr setroll <name> <value>")
		return
	end

	if not newRollValue or newRollValue == "" then
		print("|cFFFF0000Error:|r Please provide a roll value. Usage: /pr setroll <name> <value>")
		return
	end

	local rollValue = tonumber(newRollValue)
	if not rollValue then
		print("|cFFFF0000Error:|r Roll value must be a number")
		return
	end

	if rollValue ~= math.floor(rollValue) then
		print("|cFFFF0000Error:|r Roll value must be a whole number")
		return
	end

	if rollValue < 1 or rollValue > 100 then
		print("|cFFFF0000Error:|r Roll value must be between 1 and 100")
		return
	end

	characterName = characterName:sub(1,1):upper() .. characterName:sub(2):lower()

	if not addon.Frames.pityRollFrame or not addon.Frames.pityRollFrame:IsShown() then
		print("|cFFFF0000Error:|r Pity frame must be open to modify rolls. Use /pr new first.")
		return
	end

	if not State.playerRolls[characterName] then
		print(string.format("|cFFFF0000Error:|r Player '%s' has not rolled yet", characterName))
		return
	end

	local rollData = State.playerRolls[characterName]
	local oldRoll = rollData.rollValue
	local oldTotal = oldRoll + rollData.rollBonus

	rollData.rollValue = rollValue

	local newTotal = rollValue + rollData.rollBonus

	addon.RegenerateGrid()

	print(string.format("|cFF00FF00PityRoll:|r Updated %s's roll: %d -> %d (total: %d -> %d)",
		characterName, oldRoll, rollValue, oldTotal, newTotal))
end
