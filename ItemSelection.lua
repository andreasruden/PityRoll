local addonName, addon = ...
local State = addon.State

local itemSelectionFrame = nil

local function CreateItemRow(parent, index, itemLink, itemName)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(360, 30)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(index - 1) * 32 - 10)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetPoint("LEFT", row, "LEFT", 5, 0)
	local itemIcon = GetItemIcon(itemLink)
	if itemIcon then
		icon:SetTexture(itemIcon)
	end

	local itemButton = CreateFrame("Button", nil, row)
	itemButton:SetSize(240, 24)
	itemButton:SetPoint("LEFT", icon, "RIGHT", 5, 0)

	local itemText = itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemText:SetPoint("LEFT")
	itemText:SetText(itemLink)
	itemText:SetJustifyH("LEFT")

	itemButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(itemLink)
		GameTooltip:Show()
	end)
	itemButton:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	local selectButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	selectButton:SetSize(70, 24)
	selectButton:SetPoint("RIGHT", row, "RIGHT", -5, 0)
	selectButton:SetText("Select")
	selectButton:SetScript("OnClick", function()
		itemSelectionFrame:Hide()
		addon.StartRollSessionWithItem(itemLink, itemName)
	end)

	return row
end

function addon.CreateItemSelectionFrame()
	if itemSelectionFrame then
		return
	end

	itemSelectionFrame = CreateFrame("Frame", "PityRollItemSelectionFrame", UIParent)
	itemSelectionFrame:SetSize(400, 450)
	itemSelectionFrame:SetPoint("CENTER")
	itemSelectionFrame:SetFrameStrata("DIALOG")

	local bg = itemSelectionFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)

	itemSelectionFrame:SetMovable(true)
	itemSelectionFrame:EnableMouse(true)
	itemSelectionFrame:RegisterForDrag("LeftButton")
	itemSelectionFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	itemSelectionFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	local title = itemSelectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", itemSelectionFrame, "TOP", 0, -10)
	title:SetText("Select Item to Award")

	itemSelectionFrame.bossNameText = itemSelectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	itemSelectionFrame.bossNameText:SetPoint("TOP", title, "BOTTOM", 0, -5)

	local scrollFrame = CreateFrame("ScrollFrame", nil, itemSelectionFrame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetSize(380, 330)
	scrollFrame:SetPoint("TOP", itemSelectionFrame.bossNameText, "BOTTOM", 0, -10)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(360, 330)
	scrollFrame:SetScrollChild(scrollChild)

	itemSelectionFrame.scrollChild = scrollChild
	itemSelectionFrame.itemRows = {}

	local cancelButton = CreateFrame("Button", nil, itemSelectionFrame, "UIPanelButtonTemplate")
	cancelButton:SetSize(100, 25)
	cancelButton:SetPoint("BOTTOM", itemSelectionFrame, "BOTTOM", 0, 10)
	cancelButton:SetText("Cancel")
	cancelButton:SetScript("OnClick", function()
		itemSelectionFrame:Hide()
	end)

	itemSelectionFrame:Hide()
end

function addon.ShowItemSelectionDialog()
	if not itemSelectionFrame then
		addon.CreateItemSelectionFrame()
	end

	for _, row in ipairs(itemSelectionFrame.itemRows) do
		row:Hide()
	end
	itemSelectionFrame.itemRows = {}

	local bossName = State.currentBossSession.bossName or "Unknown Boss"
	itemSelectionFrame.bossNameText:SetText("|cFFFFD700" .. bossName .. "|r")

	local lootItems = State.currentBossSession.lootItems
	local itemNames = State.currentBossSession.itemNames

	local totalHeight = #lootItems * 32 + 10
	itemSelectionFrame.scrollChild:SetHeight(math.max(totalHeight, 330))

	for i, itemLink in ipairs(lootItems) do
		local itemName = itemNames[i] or "Unknown Item"
		local row = CreateItemRow(itemSelectionFrame.scrollChild, i, itemLink, itemName)
		table.insert(itemSelectionFrame.itemRows, row)
	end

	itemSelectionFrame:Show()
end
