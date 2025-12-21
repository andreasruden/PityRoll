local addonName, addon = ...

PityRollDB = PityRollDB or {}

local frame = CreateFrame("Frame")
local pityRollFrame = nil

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

    local nameText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOP", square, "TOP", 0, -3)
    nameText:SetText(playerName)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetWidth(SQUARE_WIDTH - 4)
    nameText:SetJustifyH("CENTER")

    local rollText = pityRollFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollText:SetPoint("BOTTOM", square, "BOTTOM", 0, 3)
    rollText:SetText(rollValue .. " (+" .. rollBonus .. ")")
    rollText:SetTextColor(1, 1, 1, 1)
    rollText:SetWidth(SQUARE_WIDTH - 4)
    rollText:SetJustifyH("CENTER")

    table.insert(gridSquares, {
        texture = square,
        nameText = nameText,
        rollText = rollText
    })

    print("|cFF00FF00Added square " .. #gridSquares .. " to the grid.|r")
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
	AddSquareToGrid(className, playerName, rollValue, 0)

	playerRolls[playerName] = {
		rollValue = rollValue,
		className = className
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
                print("|cFF00FF00PityRoll|r: First time setup complete")
            end
        end
    elseif event == "PLAYER_LOGIN" then
        print("|cFF00FF00PityRoll|r: Welcome, " .. UnitName("player") .. "!")
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        HandleSystemMessage(message)
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
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
            pityRollFrame:Hide()
            frame:UnregisterEvent("CHAT_MSG_SYSTEM")
            playerRolls = {}
            print("|cFF00FF00PityRoll|r: Frame closed")
        else
            print("|cFF00FF00PityRoll|r: No frame is currently open")
        end
    else
        print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
    end
end
