local addonName, addon = ...
local State = addon.State

local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local itemClickMenuFrame = LibDD:Create_UIDropDownMenu("PityRollItemClickMenuFrame", UIParent)

-- LibUIDropDownMenu only closes its menu when the mouse leaves it and its
-- autoHideDelay expires; it never reacts to clicks elsewhere. Since capturing
-- clicks with an overlay frame is unreliable across other addons' UI layers,
-- poll for a mouse-down edge instead and close the menu if it landed outside.
--
-- LibStub shares a single instance of this library across all installed
-- addons, keyed by the highest version registered; different revisions name
-- their internal list frames differently ("L_DropDownListQuestie<n>" in some,
-- plain "L_DropDownList<n>" in others), and it's whichever addon's copy wins
-- that actually creates them, not necessarily PityRoll's own. So check every
-- known naming scheme rather than hardcoding the one PityRoll ships with.
local dropDownListNamePrefixes = { "L_DropDownListQuestie", "L_DropDownList", "DropDownList" }
local dropDownListNames = {}
for _, prefix in ipairs(dropDownListNamePrefixes) do
	for level = 1, 3 do
		table.insert(dropDownListNames, prefix .. level)
	end
end

local function IsMouseOverAnyDropDownList()
	for _, name in ipairs(dropDownListNames) do
		local listFrame = _G[name]
		if listFrame and listFrame:IsShown() and listFrame:IsMouseOver() then
			return true
		end
	end
	return false
end

local wasMouseDown = false
local menuCloseWatcher = CreateFrame("Frame")
menuCloseWatcher:Hide()
menuCloseWatcher:SetScript("OnUpdate", function()
	local isMouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if isMouseDown and not wasMouseDown and not IsMouseOverAnyDropDownList() then
		LibDD:CloseDropDownMenus()
	end
	wasMouseDown = isMouseDown
end)

for _, name in ipairs(dropDownListNames) do
	local listFrame = _G[name]
	if listFrame then
		listFrame:HookScript("OnShow", function() menuCloseWatcher:Show() end)
		listFrame:HookScript("OnHide", function() menuCloseWatcher:Hide() end)
	end
end

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
