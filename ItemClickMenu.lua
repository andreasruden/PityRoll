local addonName, addon = ...
local State = addon.State

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local itemClickMenuFrame = LibDD:Create_UIDropDownMenu("PityRollItemClickMenuFrame", UIParent)

local function RollItemAction(itemLink, itemName)
	if not State.currentBossSession.isActive then
		print("|cFFFF0000Error:|r No active boss session. Use /pr bossbegin first.")
		return
	end

	if #State.currentBossSession.lootItems == 0 then
		print("|cFFFF0000Error:|r No items available. All items have been awarded or use /pr bossend to finish.")
		return
	end

	addon.StartRollSessionWithItem(itemLink, itemName)
end

local function AwardDirectlyAction(itemLink, itemName)
	if not State.currentBossSession.isActive then
		print("|cFFFF0000Error:|r No active boss session. Use /pr bossbegin first.")
		return
	end

	if #State.currentBossSession.lootItems == 0 then
		print("|cFFFF0000Error:|r No items available. All items have been awarded or use /pr bossend to finish.")
		return
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
