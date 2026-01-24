local addonName, addon = ...
local State = addon.State

-- Helper Functions

local function BuildLosersArray(allResults, winner)
    local losers = {}
    for _, result in ipairs(allResults) do
        if result.name ~= winner.name and not result.ignored then
            table.insert(losers, result.name)
        end
    end
    table.sort(losers)
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
    elseif #losers <= 5 then
        return table.concat(losers, ", ")
    else
        local first5 = {}
        for i = 1, 5 do
            first5[i] = losers[i]
        end
        return table.concat(first5, ", ") .. " and " .. (#losers - 5) .. " others"
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
