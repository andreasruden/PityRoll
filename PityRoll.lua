local addonName, addon = ...

PityRollDB = PityRollDB or {}

local frame = CreateFrame("Frame")
local pityRollFrame = nil
local buttonFrame = nil

-- Pity configuration
local MAX_PITY = 50
local PITY_INCREMENT = 5

-- Rate limiting configuration
local MAX_WHISPERS_PER_WINDOW = 5
local RATE_LIMIT_WINDOW = 30

-- Track whisper timestamps
local whisperTimestamps = {}

-- Grid configuration
local SQUARE_WIDTH = 80
local SQUARE_HEIGHT = 35
local SQUARE_SPACING = 2
local GRID_MARGIN = 10

local CLASS_COLORS = {
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

local gridSquares = {}
local playerRolls = {}
local encounterRollers = {}

local function OnSquareClick(clickFrame)
	local playerName = clickFrame.playerName
	local rollData = playerRolls[playerName]

	if not rollData then
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
end

local function CreateSquare(playerName, className, rollValue, rollBonus, isIgnored)
	local squareCount = #gridSquares
	local frameWidth = pityRollFrame:GetWidth()
	local frameHeight = pityRollFrame:GetHeight()

	local usableWidth = frameWidth - (GRID_MARGIN * 2)
	local usableHeight = frameHeight - (GRID_MARGIN * 2)

	local rowsPerColumn = math.floor((usableHeight + SQUARE_SPACING) / (SQUARE_HEIGHT + SQUARE_SPACING))

	local row = squareCount % rowsPerColumn
	local col = math.floor(squareCount / rowsPerColumn)

	local x = GRID_MARGIN + (col * (SQUARE_WIDTH + SQUARE_SPACING))
	local y = -(GRID_MARGIN + (row * (SQUARE_HEIGHT + SQUARE_SPACING)))

	local square = pityRollFrame:CreateTexture(nil, "ARTWORK")
	square:SetSize(SQUARE_WIDTH, SQUARE_HEIGHT)

	local classColor = CLASS_COLORS[className]
	square:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
	square:SetPoint("TOPLEFT", pityRollFrame, "TOPLEFT", x, y)

	if isIgnored then
		square:SetAlpha(0.3)
	end

	local nameText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetPoint("TOP", square, "TOP", 0, -3)
	nameText:SetText(playerName)
	nameText:SetWidth(SQUARE_WIDTH - 4)
	nameText:SetJustifyH("CENTER")

	if isIgnored then
		nameText:SetTextColor(0.5, 0.5, 0.5, 1)
	else
		nameText:SetTextColor(1, 1, 1, 1)
	end

	local rollText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	rollText:SetPoint("BOTTOM", square, "BOTTOM", 0, 3)
	rollText:SetText(rollValue .. " (+" .. rollBonus .. ")")
	rollText:SetTextColor(1, 1, 1, 1)
	rollText:SetWidth(SQUARE_WIDTH - 4)
	rollText:SetJustifyH("CENTER")

	local clickFrame = CreateFrame("Frame", nil, pityRollFrame)
	clickFrame:SetSize(SQUARE_WIDTH, SQUARE_HEIGHT)
	clickFrame:SetPoint("TOPLEFT", square, "TOPLEFT", 0, 0)
	clickFrame:EnableMouse(true)
	clickFrame.playerName = playerName
	clickFrame.square = square
	clickFrame.nameText = nameText
	clickFrame:SetScript("OnMouseDown", OnSquareClick)

	table.insert(gridSquares, {
		texture = square,
		nameText = nameText,
		rollText = rollText,
		clickFrame = clickFrame
	})
end

local function AddSquareToGrid(className, playerName, rollValue, rollBonus)
    if not pityRollFrame or not pityRollFrame:IsShown() then
        print("|cFFFF0000Error:|r Pity frame must be open to add squares. Use /pr new first.")
        return
    end

    if not className or not playerName or not rollValue or not rollBonus then
        print("|cFFFF0000Error:|r Missing arguments. Usage: /pr add <class> <name> <roll> <bonus>")
        return
    end

    className = className:upper()

    if not CLASS_COLORS[className] then
        print("|cFFFF0000Error:|r Invalid class name '" .. className .. "'. Valid classes: WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID")
        return
    end

    rollValue = tonumber(rollValue)
    rollBonus = tonumber(rollBonus)

    if not rollValue or not rollBonus then
        print("|cFFFF0000Error:|r Roll value and bonus must be numbers")
        return
    end

    CreateSquare(playerName, className, rollValue, rollBonus, false)

    print("|cFF00FF00Added square " .. #gridSquares .. " to the grid.|r")
end

local function RegenerateGrid()
	if not pityRollFrame or not pityRollFrame:IsShown() then
		print("|cFFFF0000Error:|r Pity frame must be open to regenerate grid")
		return
	end

	for _, squareData in ipairs(gridSquares) do
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
	gridSquares = {}

	local sortedPlayers = {}
	for playerName, _ in pairs(playerRolls) do
		table.insert(sortedPlayers, playerName)
	end
	table.sort(sortedPlayers)

	for _, playerName in ipairs(sortedPlayers) do
		local rollData = playerRolls[playerName]
		CreateSquare(playerName, rollData.className, rollData.rollValue, rollData.rollBonus, rollData.ignored)
	end
end

local function WriteToChat(message)
	if IsInRaid() then
		SendChatMessage(message, "RAID")
	elseif IsInGroup() then
		SendChatMessage(message, "PARTY")
	else
		print(message)
	end
end

local function EndSession()
	if pityRollFrame then
		pityRollFrame:Hide()
		frame:UnregisterEvent("CHAT_MSG_SYSTEM")
		playerRolls = {}
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

local function FinishRollSession(specifiedWinner)
	if not next(playerRolls) then
		print("|cFF00FF00PityRoll:|r No rolls recorded. Closing window.")
		EndSession()
		return
	end

	local results = {}
	for playerName, rollData in pairs(playerRolls) do
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

	local tiedPlayers = DetectTie(results)

	if specifiedWinner then
		if not tiedPlayers then
			print("|cFFFF0000Error:|r Cannot specify a winner when there is no tie")
			return
		end

		local winnerIsValid = false
		for _, name in ipairs(tiedPlayers) do
			if name:lower() == specifiedWinner:lower() then
				winnerIsValid = true
				specifiedWinner = name
				break
			end
		end

		if not winnerIsValid then
			local tiedList = table.concat(tiedPlayers, ", ")
			print("|cFFFF0000Error:|r Specified winner '" .. specifiedWinner .. "' is not among tied players: " .. tiedList)
			return
		end
	elseif tiedPlayers then
		local tiedList = table.concat(tiedPlayers, ", ")
		print("|cFFFF0000Error:|r There is a tie between: " .. tiedList)
		print("|cFF00FF00PityRoll:|r Please use '/pr finish <PlayerName>' to specify the winner")
		return
	end

	local message = "PityRoll Results: "
	local maxLength = 255

	for i, result in ipairs(results) do
		local formatted = result.name .. " (" .. result.rollValue .. "+" .. result.rollBonus .. "=" .. result.total .. ")"
		local separator = (i == 1) and "" or ", "

		if #message + #separator + #formatted > maxLength and message ~= "PityRoll Results: " then
			WriteToChat(message)
			message = formatted
		else
			message = message .. separator .. formatted
		end
	end

	WriteToChat(message)

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
	WriteToChat("WINNER: " .. winner.name .. " (" .. winner.total .. ")")

	for playerName, rollData in pairs(playerRolls) do
		if not rollData.ignored then
			encounterRollers[playerName] = true
		end
	end

	for playerName, rollData in pairs(playerRolls) do
		if playerName ~= winner.name and not rollData.ignored then
			local newPity = (PityRollDB[playerName] or 0) + PITY_INCREMENT
			PityRollDB[playerName] = math.min(newPity, MAX_PITY)
		end
	end

	PityRollDB[winner.name] = 0

	EndSession()
end

local function GetAllGroupMembers()
	local members = {}
	local playerName = UnitName("player")
	if playerName then
		table.insert(members, playerName)
	end

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name = UnitName("raid" .. i)
			if name then
				name = name:match("([^-]+)") or name
				table.insert(members, name)
			end
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			local name = UnitName("party" .. i)
			if name then
				name = name:match("([^-]+)") or name
				table.insert(members, name)
			end
		end
	end

	return members
end

local function CreateButtonFrame()
	if buttonFrame then
		buttonFrame:Show()
		return
	end

	buttonFrame = CreateFrame("Frame", "PityRollButtonFrame", UIParent)
	buttonFrame:SetSize(100, 30)

	if PityRollDB.buttonFramePosition then
		local pos = PityRollDB.buttonFramePosition
		buttonFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
	else
		buttonFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end

	local bg = buttonFrame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(true)
	bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

	buttonFrame:SetMovable(true)
	buttonFrame:EnableMouse(true)
	buttonFrame:RegisterForDrag("LeftButton")
	buttonFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	buttonFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveButtonFramePosition()
	end)

	local finishButton = CreateFrame("Button", nil, buttonFrame, "UIPanelButtonTemplate")
	finishButton:SetSize(90, 25)
	finishButton:SetPoint("CENTER", buttonFrame, "CENTER", 0, 0)
	finishButton:SetText("Finish")
	finishButton:SetScript("OnClick", function()
		FinishRollSession(nil)
	end)

	buttonFrame.finishButton = finishButton

	buttonFrame:Show()
end

local function SaveButtonFramePosition()
	if not buttonFrame then
		return
	end

	local point, relativeTo, relativePoint, xOffset, yOffset = buttonFrame:GetPoint()

	PityRollDB.buttonFramePosition = {
		point = point,
		relativeTo = nil,
		relativePoint = relativePoint,
		xOffset = xOffset,
		yOffset = yOffset
	}
end

local function HideButtonFrame()
	if buttonFrame then
		buttonFrame:Hide()
	end
end

local function BossBeginSession()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to use /pr bossbegin")
		return
	end

	CreateButtonFrame()
	print("|cFF00FF00PityRoll:|r Boss encounter started. Button frame displayed.")
end

local function BossEndSession()
	if not IsInRaid() and not IsInGroup() then
		print("|cFFFF0000Error:|r You must be in a party or raid to use /pr bossend")
		return
	end

	local allMembers = GetAllGroupMembers()
	local nonRollers = {}

	for _, memberName in ipairs(allMembers) do
		if not encounterRollers[memberName] then
			table.insert(nonRollers, memberName)
		end
	end

	for _, playerName in ipairs(nonRollers) do
		local newPity = (PityRollDB[playerName] or 0) + 1
		PityRollDB[playerName] = math.min(newPity, MAX_PITY)
	end

	if #nonRollers > 0 then
		local names = table.concat(nonRollers, ", ")
		print("|cFF00FF00PityRoll:|r Awarded +1 pity to " .. #nonRollers .. " non-rollers: " .. names)
	else
		print("|cFF00FF00PityRoll:|r All group members rolled - no pity awarded")
	end

	encounterRollers = {}
	playerRolls = {}

	if pityRollFrame and pityRollFrame:IsShown() then
		EndSession()
	end

	HideButtonFrame()
end

local function ReportPityValues()
	local allMembers = GetAllGroupMembers()

	local pityList = {}
	for _, memberName in ipairs(allMembers) do
		local pityValue = PityRollDB[memberName] or 0
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
			WriteToChat(message)
			message = formatted
		else
			message = message .. separator .. formatted
		end
	end

	WriteToChat(message)
end

local function ShowPityInfo(characterName)
	if not characterName or characterName == "" then
		print("|cFFFF0000Error:|r Please provide a character name. Usage: /pr info <name>")
		return
	end

	characterName = characterName:sub(1,1):upper() .. characterName:sub(2):lower()

	local pityValue = PityRollDB[characterName]

	if pityValue then
		print(string.format("|cFF00FF00Pity Info:|r %s has %d pity points", characterName, pityValue))
	else
		print(string.format("|cFFFFFF00Warning:|r No pity data found for character '%s'", characterName))
	end
end

local function AddPity(characterName, amount)
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

	if PityRollDB[characterName] == nil then
		print(string.format("|cFFFF0000Error:|r Character '%s' not found in pity database.", characterName))
		return
	end

	local oldPity = PityRollDB[characterName]
	local newPity = math.max(0, math.min(oldPity + pityAmount, MAX_PITY))
	local actualChange = newPity - oldPity

	PityRollDB[characterName] = newPity

	local verb = actualChange >= 0 and "Added" or "Removed"
	local sign = actualChange >= 0 and "+" or ""

	if actualChange ~= pityAmount then
		if newPity == MAX_PITY then
			print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity to %s (was: %d, now: %d - CAPPED AT MAXIMUM)", verb, sign, actualChange, characterName, oldPity, newPity))
		elseif newPity == 0 then
			print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity from %s (was: %d, now: %d - FLOORED AT ZERO)", verb, sign, actualChange, characterName, oldPity, newPity))
		end
	else
		print(string.format("|cFF00FF00PityRoll:|r %s %s%d pity to %s (was: %d, now: %d)", verb, sign, actualChange, characterName, oldPity, newPity))
	end
end

local function SetRoll(characterName, newRollValue)
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

	if not pityRollFrame or not pityRollFrame:IsShown() then
		print("|cFFFF0000Error:|r Pity frame must be open to modify rolls. Use /pr new first.")
		return
	end

	if not playerRolls[characterName] then
		print(string.format("|cFFFF0000Error:|r Player '%s' has not rolled yet", characterName))
		return
	end

	local rollData = playerRolls[characterName]
	local oldRoll = rollData.rollValue
	local oldTotal = oldRoll + rollData.rollBonus

	rollData.rollValue = rollValue

	local newTotal = rollValue + rollData.rollBonus

	RegenerateGrid()

	print(string.format("|cFF00FF00PityRoll:|r Updated %s's roll: %d -> %d (total: %d -> %d)",
		characterName, oldRoll, rollValue, oldTotal, newTotal))
end

local function GetPlayerClass(playerName)
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

local function HandleWhisperCommand(message, sender)
	sender = sender:match("([^-]+)")

	local lowerMsg = message:lower():trim()
	if lowerMsg ~= "!pity" then
		return
	end

	local currentTime = GetTime()
	local windowStart = currentTime - RATE_LIMIT_WINDOW

	local newTimestamps = {}
	for _, timestamp in ipairs(whisperTimestamps) do
		if timestamp > windowStart then
			table.insert(newTimestamps, timestamp)
		end
	end
	whisperTimestamps = newTimestamps

	if #whisperTimestamps >= MAX_WHISPERS_PER_WINDOW then
		return
	end

	table.insert(whisperTimestamps, currentTime)

	local normalizedName = sender:sub(1,1):upper() .. sender:sub(2):lower()

	local pityValue = PityRollDB[normalizedName]

	if pityValue then
		SendChatMessage(normalizedName .. "'s current pity: " .. pityValue .. "/" .. MAX_PITY, "WHISPER", nil, sender)
	else
		SendChatMessage(normalizedName .. " is not in the PityRoll database yet.", "WHISPER", nil, sender)
	end
end

local function HandleSystemMessage(message)
	if not pityRollFrame or not pityRollFrame:IsShown() then
		print("|cFF00FF00PityRoll DEBUG:|r Frame not shown, ignoring")
		return
	end

	-- Pattern matches: "PlayerName rolls 42 (1-100)"
	local playerName, rollValue, minRoll, maxRoll = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")

	if not playerName then
		return
	end

	print("|cFF00FF00PityRoll DEBUG:|r Matched roll - Name: " .. playerName .. ", Roll: " .. rollValue .. ", Range: " .. minRoll .. "-" .. maxRoll)

	minRoll = tonumber(minRoll)
	maxRoll = tonumber(maxRoll)
	if minRoll ~= 1 or maxRoll ~= 100 then
		print("|cFF00FF00PityRoll DEBUG:|r Not a 1-100 roll, ignoring")
		return
	end

	rollValue = tonumber(rollValue)

	playerName = playerName:match("([^-]+)") or playerName
	print("|cFF00FF00PityRoll DEBUG:|r Clean name: " .. playerName)

	if playerRolls[playerName] then
		print("|cFF00FF00PityRoll DEBUG:|r Ignoring duplicate roll from " .. playerName)
		return
	end

	local className = GetPlayerClass(playerName)

	if not className then
		print("|cFFFF0000PityRoll:|r Could not determine class for " .. playerName .. " - player may not be in your raid/party")
		return
	end

	print("|cFF00FF00PityRoll DEBUG:|r Found class: " .. className .. " for " .. playerName)
	rollBonus = PityRollDB[playerName] or 0
	AddSquareToGrid(className, playerName, rollValue, rollBonus)

	playerRolls[playerName] = {
		rollValue = rollValue,
		rollBonus = rollBonus,
		className = className,
		ignored = false
	}
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            print("|cFF00FF00PityRoll|r addon loaded!")

            if not PityRollDB.initialized then
                PityRollDB.initialized = true
                PityRollDB.version = "1.0.0"
                PityRollDB.buttonFramePosition = {
                    point = "CENTER",
                    relativeTo = nil,
                    relativePoint = "CENTER",
                    xOffset = 0,
                    yOffset = -200
                }
                print("|cFF00FF00PityRoll|r: First time setup complete")
            end
        end
    elseif event == "PLAYER_LOGIN" then
        print("|cFF00FF00PityRoll|r: Welcome, " .. UnitName("player") .. "!")
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        HandleSystemMessage(message)
    elseif event == "CHAT_MSG_WHISPER" then
        local message, sender = ...
        HandleWhisperCommand(message, sender)
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:SetScript("OnEvent", OnEvent)

local function CreatePityRollFrame()
    if pityRollFrame then
        for _, squareData in ipairs(gridSquares) do
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
        gridSquares = {}
        playerRolls = {}
        pityRollFrame:Show()
        frame:RegisterEvent("CHAT_MSG_SYSTEM")
        return
    end

    pityRollFrame = CreateFrame("Frame", "PityRollFrame", UIParent)
    pityRollFrame:SetSize(300, 200)
    pityRollFrame:SetPoint("CENTER")

    local bg = pityRollFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    pityRollFrame:SetMovable(true)
    pityRollFrame:EnableMouse(true)
    pityRollFrame:RegisterForDrag("LeftButton")
    pityRollFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    pityRollFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    pityRollFrame:SetScript("OnHide", function(self)
        frame:UnregisterEvent("CHAT_MSG_SYSTEM")
    end)

    pityRollFrame:Show()
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
end

SLASH_PITYROLL1 = "/pityroll"
SLASH_PITYROLL2 = "/pr"
SlashCmdList["PITYROLL"] = function(msg)
    msg = msg:trim()
    local lowerMsg = msg:lower()

    if lowerMsg == "" or lowerMsg == "help" then
        print("|cFF00FF00PityRoll|r Commands:")
        print("/pityroll help - Show this help message")
        print("/pityroll version - Show addon version")
        print("/pityroll new - Open PityRoll frame")
        print("/pityroll add <class> <name> <roll> <bonus> - Add a player's roll to the grid")
        print("/pityroll finish [PlayerName] - Finish roll session and show sorted results (specify winner if tied)")
        print("/pityroll bossbegin - Show button frame for boss encounter")
        print("/pityroll bossend - Award +1 pity to non-rollers and reset tracking")
        print("/pityroll report - Show pity values for all party/raid members")
        print("/pityroll info <name> - Show pity value for a specific character")
        print("/pityroll addpity <name> <amount> - Manually add pity points to a character")
        print("/pityroll setroll <name> <value> - Manually set a player's roll (1-100)")
        print("/pityroll abort - Close the PityRoll frame")
    elseif lowerMsg == "version" then
        print("|cFF00FF00PityRoll|r version: " .. (PityRollDB.version or "1.0.0"))
    elseif lowerMsg == "new" then
        CreatePityRollFrame()
    elseif lowerMsg:match("^add%s+") then
        local args = {}
        for arg in msg:gmatch("%S+") do
            table.insert(args, arg)
        end

        if #args < 5 then
            print("|cFFFF0000Error:|r Usage: /pr add <class> <name> <roll> <bonus>")
            print("|cFF00FF00Example:|r /pr add warrior Thrall 95 10")
        else
            AddSquareToGrid(args[2], args[3], args[4], args[5])
        end
    elseif lowerMsg == "abort" then
        if pityRollFrame then
            EndSession()
            print("|cFF00FF00PityRoll|r: Frame closed")
        else
            print("|cFF00FF00PityRoll|r: No frame is currently open")
        end
    elseif lowerMsg:match("^finish") then
        local winnerName = msg:match("^finish%s+(.+)")
        FinishRollSession(winnerName)
    elseif lowerMsg == "bossbegin" then
        BossBeginSession()
    elseif lowerMsg == "bossend" then
        BossEndSession()
    elseif lowerMsg == "report" then
        ReportPityValues()
    elseif lowerMsg:match("^info%s+") then
        local characterName = msg:match("^info%s+(.+)")
        ShowPityInfo(characterName)
    elseif lowerMsg:match("^addpity%s+") then
        local args = {}
        for arg in msg:gmatch("%S+") do
            table.insert(args, arg)
        end
        if #args < 3 then
            print("|cFFFF0000Error:|r Usage: /pr addpity <name> <amount>")
        else
            AddPity(args[2], args[3])
        end
    elseif lowerMsg:match("^setroll%s+") then
        local args = {}
        for arg in msg:gmatch("%S+") do
            table.insert(args, arg)
        end
        if #args < 3 then
            print("|cFFFF0000Error:|r Usage: /pr setroll <name> <value>")
        else
            SetRoll(args[2], args[3])
        end
    else
        print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
    end
end
