local addonName, addon = ...
local Constants = addon.Constants
local State = addon.State

local function OnSquareClick(clickFrame)
	local playerName = clickFrame.playerName
	local rollData = State.playerRolls[playerName]

	if not rollData then
		return
	end

	if State.tieResolutionMode then
		local isTiedPlayer = false
		for _, tiedName in ipairs(State.tiedPlayers) do
			if tiedName == playerName then
				isTiedPlayer = true
				break
			end
		end

		if not isTiedPlayer then
			return
		end

		if State.selectedWinner then
			for _, squareData in ipairs(State.gridSquares) do
				if squareData.clickFrame.playerName == State.selectedWinner then
					squareData.clickFrame.selectionIndicator:Hide()
					squareData.clickFrame.leaderIndicator:Show()
					break
				end
			end
		end

		State.selectedWinner = playerName
		clickFrame.leaderIndicator:Hide()
		clickFrame.selectionIndicator:Show()

		print("|cFF00FF00PityRoll:|r Selected " .. playerName .. " as winner. Click Award Item again to confirm.")

		addon.UpdateButtonFrameButtons()
		return
	end

	rollData.ignored = not rollData.ignored

	local newAlpha = rollData.ignored and 0.3 or 1.0
	clickFrame.square:SetAlpha(newAlpha)

	if rollData.ignored then
		clickFrame.nameText:SetTextColor(0.5, 0.5, 0.5, 1)
	else
		clickFrame.nameText:SetTextColor(1, 1, 1, 1)
	end

	addon.UpdateLeaderIndicators()
end

function addon.UpdateLeaderIndicators()
	if State.tieResolutionMode then return end

	local highestTotal
	for _, rollData in pairs(State.playerRolls) do
		if not rollData.ignored then
			local total = rollData.rollValue + rollData.rollBonus
			if not highestTotal or total > highestTotal then
				highestTotal = total
			end
		end
	end

	for _, squareData in ipairs(State.gridSquares) do
		local rollData = State.playerRolls[squareData.clickFrame.playerName]
		local total = rollData and (rollData.rollValue + rollData.rollBonus)
		if highestTotal and rollData and not rollData.ignored and total == highestTotal then
			squareData.clickFrame.leaderIndicator:Show()
		else
			squareData.clickFrame.leaderIndicator:Hide()
		end
	end
end

local function CreateSquare(playerName, className, rollValue, rollBonus, isIgnored, isNonStandard)
	local pityRollFrame = addon.Frames.pityRollFrame
	local squareCount = #State.gridSquares
	local frameWidth = pityRollFrame:GetWidth()
	local frameHeight = pityRollFrame:GetHeight()

	local usableWidth = frameWidth - (Constants.GRID_MARGIN * 2)
	local usableHeight = frameHeight - (Constants.GRID_MARGIN * 2)

	local rowsPerColumn = math.floor((usableHeight + Constants.SQUARE_SPACING) / (Constants.SQUARE_HEIGHT + Constants.SQUARE_SPACING))

	local row = squareCount % rowsPerColumn
	local col = math.floor(squareCount / rowsPerColumn)

	local x = Constants.GRID_MARGIN + (col * (Constants.SQUARE_WIDTH + Constants.SQUARE_SPACING))
	local y = -(Constants.GRID_MARGIN + (row * (Constants.SQUARE_HEIGHT + Constants.SQUARE_SPACING)))

	local square = pityRollFrame:CreateTexture(nil, "ARTWORK")
	square:SetSize(Constants.SQUARE_WIDTH, Constants.SQUARE_HEIGHT)

	local classColor = Constants.CLASS_COLORS[className]
	square:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
	square:SetPoint("TOPLEFT", pityRollFrame, "TOPLEFT", x, y)

	if isIgnored then
		square:SetAlpha(0.3)
	end

	local leaderIndicator = pityRollFrame:CreateTexture(nil, "OVERLAY", nil, 7)
	leaderIndicator:SetSize(12, 12)
	leaderIndicator:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	leaderIndicator:SetTexCoord(0, 1, 0, 1)
	leaderIndicator:SetVertexColor(1, 1, 1, 1)
	leaderIndicator:SetPoint("TOPRIGHT", square, "TOPRIGHT", -2, -2)
	leaderIndicator:Hide()

	local selectionIndicator = pityRollFrame:CreateTexture(nil, "OVERLAY")
	selectionIndicator:SetSize(Constants.SQUARE_WIDTH + 6, Constants.SQUARE_HEIGHT + 6)
	selectionIndicator:SetColorTexture(0.0, 1.0, 0.0, 1.0)
	selectionIndicator:SetPoint("CENTER", square, "CENTER", 0, 0)
	selectionIndicator:Hide()

	local nameText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetPoint("TOP", square, "TOP", 0, -3)
	nameText:SetText(playerName)
	nameText:SetWidth(Constants.SQUARE_WIDTH - 4)
	nameText:SetJustifyH("CENTER")

	if isIgnored then
		nameText:SetTextColor(0.5, 0.5, 0.5, 1)
	else
		nameText:SetTextColor(1, 1, 1, 1)
	end

	local rollText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	rollText:SetPoint("BOTTOM", square, "BOTTOM", 0, 3)
	local bonusStr = isNonStandard and "(--)" or ("(+" .. rollBonus .. ")")
	rollText:SetText(rollValue .. " " .. bonusStr)
	rollText:SetTextColor(1, 1, 1, 1)
	rollText:SetWidth(Constants.SQUARE_WIDTH - 4)
	rollText:SetJustifyH("CENTER")

	local clickFrame = CreateFrame("Frame", nil, pityRollFrame)
	clickFrame:SetSize(Constants.SQUARE_WIDTH, Constants.SQUARE_HEIGHT)
	clickFrame:SetPoint("TOPLEFT", square, "TOPLEFT", 0, 0)
	clickFrame:EnableMouse(true)
	clickFrame.playerName = playerName
	clickFrame.square = square
	clickFrame.nameText = nameText
	clickFrame.leaderIndicator = leaderIndicator
	clickFrame.selectionIndicator = selectionIndicator
	clickFrame:SetScript("OnMouseDown", OnSquareClick)

	table.insert(State.gridSquares, {
		texture = square,
		nameText = nameText,
		rollText = rollText,
		clickFrame = clickFrame,
		leaderIndicator = leaderIndicator,
		selectionIndicator = selectionIndicator
	})
end

function addon.AddSquareToGrid(className, playerName, rollValue, rollBonus, isNonStandard, isIgnored)
	if not addon.Frames.pityRollFrame or not addon.Frames.pityRollFrame:IsShown() then
		print("|cFFFF0000Error:|r Pity frame must be open to add squares. Roll an item first.")
		return
	end

	if not className or not playerName or not rollValue or not rollBonus then
		print("|cFFFF0000Error:|r Missing arguments. Usage: /pr add <class> <name> <roll> <bonus>")
		return
	end

	className = className:upper()

	if not Constants.CLASS_COLORS[className] then
		print("|cFFFF0000Error:|r Invalid class name '" .. className .. "'. Valid classes: WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID")
		return
	end

	rollValue = tonumber(rollValue)
	rollBonus = tonumber(rollBonus)

	if not rollValue or not rollBonus then
		print("|cFFFF0000Error:|r Roll value and bonus must be numbers")
		return
	end

	CreateSquare(playerName, className, rollValue, rollBonus, isIgnored or false, isNonStandard)
	addon.UpdateLeaderIndicators()

	print("|cFF00FF00Added square " .. #State.gridSquares .. " to the grid.|r")
end

function addon.RegenerateGrid()
	if not addon.Frames.pityRollFrame or not addon.Frames.pityRollFrame:IsShown() then
		print("|cFFFF0000Error:|r Pity frame must be open to regenerate grid")
		return
	end

	for _, squareData in ipairs(State.gridSquares) do
		squareData.texture:Hide()
		if squareData.nameText then
			squareData.nameText:Hide()
		end
		if squareData.rollText then
			squareData.rollText:Hide()
		end
		if squareData.clickFrame then
			squareData.clickFrame:Hide()
		end
	end
	State.gridSquares = {}

	local sortedPlayers = {}
	for playerName, _ in pairs(State.playerRolls) do
		table.insert(sortedPlayers, playerName)
	end
	table.sort(sortedPlayers)

	for _, playerName in ipairs(sortedPlayers) do
		local rollData = State.playerRolls[playerName]
		CreateSquare(playerName, rollData.className, rollData.rollValue, rollData.rollBonus, rollData.ignored, rollData.nonStandardRoll)
	end

	if State.tieResolutionMode and State.tiedPlayers then
		for _, squareData in ipairs(State.gridSquares) do
			local playerName = squareData.clickFrame.playerName

			for _, tiedName in ipairs(State.tiedPlayers) do
				if tiedName == playerName then
					if State.selectedWinner == playerName then
						squareData.clickFrame.selectionIndicator:Show()
					else
						squareData.clickFrame.leaderIndicator:Show()
					end
					break
				end
			end
		end
	end

	addon.UpdateLeaderIndicators()
end
