local addonName, addon = ...
local State = addon.State

-- Helper Functions

local function BuildLosersArray(allResults, winner)
    local losers = {}
    for _, result in ipairs(allResults) do
        if result.name ~= winner.name and not result.ignored then
            local playerName = result.name
            local oldPity = PityRollDB.players[playerName] or 0
            local newPity = math.min(oldPity + addon.Constants.PITY_INCREMENT, addon.Constants.MAX_PITY)
            table.insert(losers, {playerName, newPity})
        end
    end
    table.sort(losers, function(a, b) return a[1] < b[1] end)
    return losers
end

local function FindCurrentEncounter()
    if not State.currentBossSession or not State.currentBossSession.startTime then
        return nil
    end

    local timestamp = State.currentBossSession.startTime
    for i = #PityRollHistoryDB.encounters, 1, -1 do
        local encounter = PityRollHistoryDB.encounters[i]
        if encounter.timestamp == timestamp then
            return encounter
        end
    end

    return nil
end

local function CreateNewEncounter(bossName, timestamp)
    local encounter = {
        bossName = bossName,
        timestamp = timestamp,
        items = {}
    }
    table.insert(PityRollHistoryDB.encounters, encounter)
    return encounter
end

local function FormatTimestamp(timestamp)
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function FormatLosersList(losers)
    if #losers == 0 then
        return "no other rollers"
    end

    local formattedLosers = {}
    for i, loser in ipairs(losers) do
        if type(loser) == "table" then
            table.insert(formattedLosers, loser[1] .. " " .. loser[2])
        else
            table.insert(formattedLosers, loser)
        end
    end

    if #formattedLosers <= 5 then
        return table.concat(formattedLosers, ", ")
    else
        local first5 = {}
        for i = 1, 5 do
            first5[i] = formattedLosers[i]
        end
        return table.concat(first5, ", ") .. " and " .. (#formattedLosers - 5) .. " others"
    end
end

-- Public Functions

function addon.RecordHistoryEntry(bossName, itemLink, itemName, winner, allResults)
    if not PityRollHistoryDB then
        return
    end

    -- Find or create encounter
    local encounter = FindCurrentEncounter()
    if not encounter then
        if not State.currentBossSession or not State.currentBossSession.startTime then
            print("|cFFFF0000PityRoll History:|r Cannot record entry - no active boss session")
            return
        end
        encounter = CreateNewEncounter(bossName, State.currentBossSession.startTime)
    end

    -- Build losers array
    local losers = BuildLosersArray(allResults, winner)

    -- Add item to encounter
    local itemEntry = {
        itemLink = itemLink,
        itemName = itemName,
        winner = winner.name,
        losers = losers
    }
    table.insert(encounter.items, itemEntry)
end

function addon.DumpHistory(limit)
    if not PityRollHistoryDB or #PityRollHistoryDB.encounters == 0 then
        print("|cFF00FF00PityRoll History:|r No history recorded")
        return
    end

    local count = 0
    local maxCount = limit or #PityRollHistoryDB.encounters

    print("|cFF00FF00PityRoll History:|r")

    -- Iterate in reverse chronological order
    for i = #PityRollHistoryDB.encounters, 1, -1 do
        if count >= maxCount then
            break
        end

        local encounter = PityRollHistoryDB.encounters[i]
        local dateStr = FormatTimestamp(encounter.timestamp)
        print(string.format("%s (%s):", encounter.bossName, dateStr))

        for _, item in ipairs(encounter.items) do
            local losersList = FormatLosersList(item.losers)
            print(string.format("  - %s: %s (%s)", item.itemName, item.winner, losersList))
        end

        print("")  -- Empty line between encounters
        count = count + 1
    end
end

function addon.ClearHistory()
    print("|cFFFF0000WARNING:|r Type '/pr history clear confirm' to proceed")
end

function addon.ShowClearHistoryConfirmation()
    local numEncounters = PityRollHistoryDB and #PityRollHistoryDB.encounters or 0

    StaticPopupDialogs["PITYROLL_CLEAR_HISTORY"] = {
        text = string.format("Are you sure you want to clear all history?\n\nThis will delete %d encounter(s) and cannot be undone.", numEncounters),
        button1 = "Yes, Clear All",
        button2 = "Cancel",
        OnAccept = function()
            PityRollHistoryDB.encounters = {}
            PityRollHistoryDB.pityChanges = {}
            print("|cFF00FF00PityRoll:|r History cleared")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("PITYROLL_CLEAR_HISTORY")
end

function addon.GetHistoryStats()
    if not PityRollHistoryDB then
        return 0, 0
    end

    local encounterCount = #PityRollHistoryDB.encounters
    local itemCount = 0

    for _, encounter in ipairs(PityRollHistoryDB.encounters) do
        itemCount = itemCount + #encounter.items
    end

    return encounterCount, itemCount
end

function addon.RecordPityChange(playerName, oldPity, newPity)
    if not PityRollHistoryDB.pityChanges then
        PityRollHistoryDB.pityChanges = {}
    end

    if oldPity == newPity then
        return
    end

    if not PityRollHistoryDB.pityChanges[playerName] then
        PityRollHistoryDB.pityChanges[playerName] = {
            old = oldPity,
            new = newPity
        }
    else
        PityRollHistoryDB.pityChanges[playerName].new = newPity
    end
end

function addon.SerializeHistory(limit)
    if not PityRollHistoryDB or #PityRollHistoryDB.encounters == 0 then
        return "No history recorded\n"
    end

    local lines = {}
    local count = 0
    local maxCount = limit or #PityRollHistoryDB.encounters

    for i = #PityRollHistoryDB.encounters, 1, -1 do
        if count >= maxCount then
            break
        end

        local encounter = PityRollHistoryDB.encounters[i]
        local dateStr = FormatTimestamp(encounter.timestamp)
        table.insert(lines, string.format("**%s (%s):**", encounter.bossName, dateStr))

        for _, item in ipairs(encounter.items) do
            local losersList = FormatLosersList(item.losers)
            table.insert(lines, string.format("- %s: %s (%s)", item.itemName, item.winner, losersList))
        end

        table.insert(lines, "")
        count = count + 1
    end

    return table.concat(lines, "\n")
end
