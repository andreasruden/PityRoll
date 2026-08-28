local addonName, addon = ...
local State = addon.State

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local itemClickMenuFrame = LibDD:Create_UIDropDownMenu("PityRollItemClickMenuFrame", UIParent)

local function AddItemToBossSession(itemLink, itemName)
	for _, existingLink in ipairs(State.currentBossSession.lootItems) do
		if existingLink == itemLink then
			return
		end
	end

	table.insert(State.currentBossSession.lootItems, itemLink)
	table.insert(State.currentBossSession.itemNames, itemName)
end

local function RollItemAction(itemLink, itemName)
	if State.currentBossSession.isActive then
		AddItemToBossSession(itemLink, itemName)
	end
	addon.StartRollSessionWithItem(itemLink, itemName)
end

local function RollItemNoPityAction(itemLink, itemName)
	if State.currentBossSession.isActive then
		AddItemToBossSession(itemLink, itemName)
	end
	addon.StartRollSessionWithItem(itemLink, itemName, true)
end

local function AwardDirectlyAction(itemLink, itemName)
	if State.currentBossSession.isActive then
		AddItemToBossSession(itemLink, itemName)
	end
	addon.ShowPlayerSelectionDialog({
		title = "Award " .. itemLink,
		buttonLabel = "Give Item",
		onConfirm = function(playerName)
			addon.ExecuteDirectAward(itemLink, itemName, playerName)
		end,
	})
end

local function ShowItemClickMenu(itemLink, itemName)
	local menuTable = {
		{
			text = "Roll Item",
			func = function() RollItemAction(itemLink, itemName) end,
			notCheckable = true,
		},
		{
			text = "Award Directly",
			func = function() AwardDirectlyAction(itemLink, itemName) end,
			notCheckable = true,
		},
		{
			text = "Roll Without Pity",
			func = function() RollItemNoPityAction(itemLink, itemName) end,
			notCheckable = true,
		},
	}

	LibDD:EasyMenu(menuTable, itemClickMenuFrame, "cursor", 0, 0, "MENU", 2)
end

hooksecurefunc("HandleModifiedItemClick", function(itemLink)
	if not itemLink then
		return
	end

	local button = GetMouseButtonClicked and GetMouseButtonClicked() or nil
	local isPlainAltLeftClick = IsAltKeyDown()
		and not IsShiftKeyDown()
		and not IsControlKeyDown()
		and (button == nil or button == "LeftButton")

	if not isPlainAltLeftClick then
		return
	end

	local itemName = GetItemInfo(itemLink)
	ShowItemClickMenu(itemLink, itemName or itemLink)
end)
