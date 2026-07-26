local addonName, addon = ...
PityRoll = addon

-- Constants
addon.Constants = {
	MAX_PITY = 50,
	PITY_INCREMENT = 5,
	BOSS_PITY = 2,
	ADDON_PREFIX = "PityRoll",

	-- Rate limiting configuration
	MAX_WHISPERS_PER_WINDOW = 5,
	RATE_LIMIT_WINDOW = 30,

	-- Grid configuration
	SQUARE_WIDTH = 80,
	SQUARE_HEIGHT = 35,
	SQUARE_SPACING = 2,
	GRID_MARGIN = 10,

	-- Class colors
	CLASS_COLORS = {
		WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
		PALADIN = {r = 0.96, g = 0.55, b = 0.73},
		HUNTER = {r = 0.67, g = 0.83, b = 0.45},
		ROGUE = {r = 1.00, g = 0.96, b = 0.41},
		PRIEST = {r = 1.00, g = 1.00, b = 1.00},
		SHAMAN = {r = 0.00, g = 0.44, b = 0.87},
		MAGE = {r = 0.41, g = 0.80, b = 0.94},
		WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
		DRUID = {r = 1.00, g = 0.49, b = 0.04}
	}
}

-- Shared state
addon.State = {
	gridSquares = {},
	playerRolls = {},
	encounterRollers = {},
	hasFinishedRollSession = false,
	tieResolutionMode = false,
	tiedPlayers = nil,
	selectedWinner = nil,
	observedPity = {},
	whisperTimestamps = {},
	currentBossSession = {
		bossName = nil,
		bossGuid = nil,
		lootItems = {},
		itemNames = {},
		startTime = nil,
		isActive = false
	},
	currentRollItemLink = nil,
	currentRollItemName = nil
}

-- Frames
addon.Frames = {
	eventFrame = nil,
	pityRollFrame = nil,
	buttonFrame = nil
}

-- Stubs for cross-module functions (will be implemented by other modules)
addon.UpdateButtonFrameButtons = function() end
addon.RegenerateGrid = function() end
addon.EndSession = function() end

-- Utility functions
function addon.GetGroupChannel()
	if IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

function addon.GetPlayerClass(playerName)
	local name = playerName:match("([^-]+)") or playerName

	if name == UnitName("player") then
		local _, englishClass = UnitClass("player")
		return englishClass
	end

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			if UnitName("raid" .. i) == name then
				local _, englishClass = UnitClass("raid" .. i)
				return englishClass
			end
		end
	end

	if IsInGroup() and not IsInRaid() then
		for i = 1, GetNumSubgroupMembers() do
			if UnitName("party" .. i) == name then
				local _, englishClass = UnitClass("party" .. i)
				return englishClass
			end
		end
	end

	return nil
end

function addon.GetAllGroupMembers()
	local members = {}

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name = UnitName("raid" .. i)
			if name then
				name = name:match("([^-]+)") or name
				table.insert(members, name)
			end
		end
	elseif IsInGroup() then
		local playerName = UnitName("player")
		if playerName then
			table.insert(members, playerName)
		end

		for i = 1, GetNumSubgroupMembers() do
			local name = UnitName("party" .. i)
			if name then
				name = name:match("([^-]+)") or name
				table.insert(members, name)
			end
		end
	else
		local playerName = UnitName("player")
		if playerName then
			table.insert(members, playerName)
		end
	end

	return members
end

function addon.WriteToChat(message)
	if IsInRaid() then
		SendChatMessage(message, "RAID")
	elseif IsInGroup() then
		SendChatMessage(message, "PARTY")
	else
		print(message)
	end
end

function addon.AnnounceRollItem(itemLink)
	local message = "Rolling for " .. itemLink .. ". If this matches your Main Spec, type /roll to use your pity or /roll 99 to ignore pity."
	if IsInRaid() then
		if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
			SendChatMessage(message, "RAID_WARNING")
		else
			SendChatMessage(message, "RAID")
		end
	elseif IsInGroup() then
		SendChatMessage(message, "PARTY")
	else
		print(message)
	end

	addon.AnnouncePriority(itemLink)
end

function addon.AnnouncePriority(itemLink)
	local itemId = tonumber(itemLink:match("item:(%d+)"))
	local tiers = itemId and addon.Priorities[itemId]
	if not tiers then return end

	local parts = {}
	for _, tier in ipairs(tiers) do
		table.insert(parts, table.concat(tier, ", "))
	end

	addon.WriteToChat("Priority:")
	addon.WriteToChat(table.concat(parts, "  >  "))
end
