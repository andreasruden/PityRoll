local addonName, addon = ...

local playerSelectionFrame = nil

local function CreatePlayerRow(parent, index, playerName)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(340, 24)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -(index - 1) * 26 - 5)
	row:EnableMouse(true)
	row.playerName = playerName

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
	row.bg = bg

	local indicator = row:CreateTexture(nil, "ARTWORK")
	indicator:SetSize(8, 8)
	indicator:SetPoint("LEFT", row, "LEFT", 4, 0)
	indicator:SetColorTexture(1.0, 0.84, 0.0, 1.0)
	indicator:Hide()
	row.indicator = indicator

	local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	nameText:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
	nameText:SetText(playerName)
	row.nameText = nameText

	row:SetScript("OnMouseDown", function()
		for _, r in ipairs(playerSelectionFrame.playerRows) do
			r.indicator:Hide()
			r.bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
		end
		row.indicator:Show()
		row.bg:SetColorTexture(0.25, 0.25, 0.15, 0.9)
		playerSelectionFrame.selectedPlayer = playerName
		playerSelectionFrame.confirmButton:Enable()
	end)

	row:SetScript("OnEnter", function()
		if playerSelectionFrame.selectedPlayer ~= playerName then
			row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
		end
	end)

	row:SetScript("OnLeave", function()
		if playerSelectionFrame.selectedPlayer ~= playerName then
			row.bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
		end
	end)

	return row
end

local function CreatePlayerSelectionFrame()
	playerSelectionFrame = CreateFrame("Frame", "PityRollPlayerSelectionFrame", UIParent)
	playerSelectionFrame:SetSize(400, 480)
	playerSelectionFrame:SetPoint("CENTER")
	playerSelectionFrame:SetFrameStrata("DIALOG")

	local bg = playerSelectionFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)

	playerSelectionFrame:SetMovable(true)
	playerSelectionFrame:EnableMouse(true)
	playerSelectionFrame:RegisterForDrag("LeftButton")
	playerSelectionFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	playerSelectionFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	playerSelectionFrame.titleText = playerSelectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	playerSelectionFrame.titleText:SetPoint("TOP", playerSelectionFrame, "TOP", 0, -15)

	local filterLabel = playerSelectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	filterLabel:SetPoint("TOPLEFT", playerSelectionFrame, "TOPLEFT", 15, -48)
	filterLabel:SetText("Filter:")

	local filterBox = CreateFrame("EditBox", nil, playerSelectionFrame, "InputBoxTemplate")
	filterBox:SetSize(160, 20)
	filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
	filterBox:SetAutoFocus(false)
	playerSelectionFrame.filterBox = filterBox

	filterBox:SetScript("OnTextChanged", function(self)
		local text = self:GetText():lower()
		for _, row in ipairs(playerSelectionFrame.playerRows) do
			if text == "" or row.playerName:lower():find(text, 1, true) then
				row:Show()
			else
				row:Hide()
				if playerSelectionFrame.selectedPlayer == row.playerName then
					playerSelectionFrame.selectedPlayer = nil
					playerSelectionFrame.confirmButton:Disable()
				end
			end
		end
	end)

	local scrollFrame = CreateFrame("ScrollFrame", nil, playerSelectionFrame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetSize(380, 310)
	scrollFrame:SetPoint("TOP", playerSelectionFrame, "TOP", 0, -80)
	playerSelectionFrame.scrollFrame = scrollFrame

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(360, 310)
	scrollFrame:SetScrollChild(scrollChild)
	playerSelectionFrame.scrollChild = scrollChild

	playerSelectionFrame.playerRows = {}
	playerSelectionFrame.selectedPlayer = nil

	local confirmButton = CreateFrame("Button", nil, playerSelectionFrame, "UIPanelButtonTemplate")
	confirmButton:SetSize(120, 25)
	confirmButton:SetPoint("BOTTOMRIGHT", playerSelectionFrame, "BOTTOM", -5, 10)
	confirmButton:Disable()
	confirmButton:SetScript("OnClick", function()
		local selected = playerSelectionFrame.selectedPlayer
		if not selected then return end
		local cb = playerSelectionFrame.onConfirm
		playerSelectionFrame:Hide()
		if cb then cb(selected) end
	end)
	playerSelectionFrame.confirmButton = confirmButton

	local cancelButton = CreateFrame("Button", nil, playerSelectionFrame, "UIPanelButtonTemplate")
	cancelButton:SetSize(80, 25)
	cancelButton:SetPoint("BOTTOMLEFT", playerSelectionFrame, "BOTTOM", 5, 10)
	cancelButton:SetText("Cancel")
	cancelButton:SetScript("OnClick", function()
		playerSelectionFrame:Hide()
	end)

	playerSelectionFrame:Hide()
end

-- config = {
--   title:       string
--   buttonLabel: string   (default: "Give Item")
--   onConfirm:   function(playerName)
--   playerList:  table of name strings, or nil → addon.GetAllGroupMembers()
-- }
function addon.ShowPlayerSelectionDialog(config)
	if not playerSelectionFrame then
		CreatePlayerSelectionFrame()
	end

	for _, row in ipairs(playerSelectionFrame.playerRows) do
		row:Hide()
	end
	playerSelectionFrame.playerRows = {}
	playerSelectionFrame.selectedPlayer = nil

	playerSelectionFrame.titleText:SetText(config.title or "Select Player")
	playerSelectionFrame.confirmButton:SetText(config.buttonLabel or "Give Item")
	playerSelectionFrame.confirmButton:Disable()
	playerSelectionFrame.onConfirm = config.onConfirm

	playerSelectionFrame.filterBox:SetText("")

	local players = config.playerList or addon.GetAllGroupMembers()
	table.sort(players)

	local totalHeight = #players * 26 + 10
	playerSelectionFrame.scrollChild:SetHeight(math.max(totalHeight, 310))

	for i, name in ipairs(players) do
		local row = CreatePlayerRow(playerSelectionFrame.scrollChild, i, name)
		table.insert(playerSelectionFrame.playerRows, row)
	end

	playerSelectionFrame:Show()
end
