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

SLASH_PITYROLL1 = "/pityroll"
SLASH_PITYROLL2 = "/pr"
SlashCmdList["PITYROLL"] = function(msg)
    msg = msg:lower():trim()

    if msg == "" or msg == "help" then
        print("|cFF00FF00PityRoll|r Commands:")
        print("/pityroll help - Show this help message")
        print("/pityroll version - Show addon version")
    elseif msg == "version" then
        print("|cFF00FF00PityRoll|r version: " .. (PityRollDB.version or "1.0.0"))
    else
        print("|cFF00FF00PityRoll|r: Unknown command. Type /pityroll help for commands")
    end
end
