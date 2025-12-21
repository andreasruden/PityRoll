local addonName, addon = ...

PityRollDB = PityRollDB or {}

local frame = CreateFrame("Frame")

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
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", OnEvent)

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
        pityRollFrame:Show()
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

    pityRollFrame:Show()
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
            print("|cFF00FF00PityRoll|r: Frame closed")
        else
            print("|cFF00FF00PityRoll|r: No frame is currently open")
        end
    else
        print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
    end
end
