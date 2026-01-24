local addonName, addon = ...

-- Sync state tracking
local syncState = {
    queryResponses = {},
    queryInProgress = false,
    queryStartTime = nil,
    leaderHash = nil,
    outOfSyncFollowers = {}
}

-- Expose sync state for context menu
addon.GetSyncState = function()
    return syncState
end

-- CRC32 implementation using WoW bit library
local function ComputeCRC32(str)
    local crc = 0xFFFFFFFF
    local polynomial = 0xEDB88320

    for i = 1, #str do
        local byte = string.byte(str, i)
        crc = bit.bxor(crc, byte)

        for j = 1, 8 do
            if bit.band(crc, 1) == 1 then
                crc = bit.bxor(bit.rshift(crc, 1), polynomial)
            else
                crc = bit.rshift(crc, 1)
            end
        end
    end

    crc = bit.bxor(crc, 0xFFFFFFFF)
    return string.format("%08x", crc)
end

-- Compute hash of pity table with deterministic serialization
function addon.ComputePityTableHash()
    if not PityRollDB or not PityRollDB.players then
        return "00000000"
    end

    -- Extract and sort player names alphabetically
    local names = {}
    for name, _ in pairs(PityRollDB.players) do
        table.insert(names, name)
    end
    table.sort(names)

    -- Build deterministic serialization
    local parts = {}
    for _, name in ipairs(names) do
        table.insert(parts, name .. ":" .. PityRollDB.players[name])
    end

    local serialized = table.concat(parts, "|")
    return ComputeCRC32(serialized)
end

-- Serialize pity database for force update
function addon.SerializePityDatabase()
    if not PityRollDB or not PityRollDB.players then
        return ""
    end

    local names = {}
    for name, _ in pairs(PityRollDB.players) do
        table.insert(names, name)
    end
    table.sort(names)

    local parts = {}
    for _, name in ipairs(names) do
        table.insert(parts, name .. ":" .. PityRollDB.players[name])
    end

    return table.concat(parts, ",")
end

-- Deserialize pity database from force update
function addon.DeserializePityDatabase(serialized)
    local database = {}

    if not serialized or serialized == "" then
        return database
    end

    for entry in serialized:gmatch("[^,]+") do
        local name, pity = entry:match("^(.+):(%d+)$")
        if name and pity then
            database[name] = tonumber(pity)
        end
    end

    return database
end

-- Set sync source (leader to follow)
function addon.SetSyncSource(playerName)
    if not playerName or playerName == "" then
        print("[PityRoll Sync] Error: Must provide a player name")
        return
    end

    -- Normalize name (capitalize first letter)
    playerName = playerName:sub(1, 1):upper() .. playerName:sub(2):lower()

    -- Validate not setting self as source
    local selfName = UnitName("player")
    if playerName == selfName then
        print("[PityRoll Sync] Error: Cannot set yourself as sync source")
        return
    end

    PityRollDB.syncSource = playerName
    print("[PityRoll Sync] Now following " .. playerName)
end

-- Clear sync source
function addon.ClearSyncSource()
    local previousSource = PityRollDB.syncSource
    PityRollDB.syncSource = nil

    if previousSource then
        print("[PityRoll Sync] Stopped following " .. previousSource)
    else
        print("[PityRoll Sync] No sync source was set")
    end
end

-- Query follower state (called by leader from context menu)
function addon.QueryFollowerState()
    -- Validate in guild
    if not IsInGuild() then
        print("[PityRoll Sync] Error: You must be in a guild to query followers")
        return
    end

    -- Check if query already in progress
    if syncState.queryInProgress then
        print("[PityRoll Sync] Query already in progress, please wait")
        return
    end

    -- Compute current hash
    local hash = addon.ComputePityTableHash()

    -- Initialize query state
    syncState.queryResponses = {}
    syncState.outOfSyncFollowers = {}
    syncState.queryInProgress = true
    syncState.queryStartTime = GetTime()
    syncState.leaderHash = hash

    -- Broadcast query to guild
    local message = "SYNC_QUERY:" .. hash
    ChatThrottleLib:SendAddonMessage("NORMAL", "PityRoll", message, "GUILD")

    print("[PityRoll Sync] Querying followers... (hash: " .. hash .. ")")
    print("[PityRoll Sync] Waiting 5 seconds for responses...")

    -- Schedule results display after 5 seconds
    C_Timer.After(5, function()
        addon.DisplayQueryResults()
    end)
end

-- Handle sync query (follower receives from leader)
function addon.HandleSyncQuery(message, sender)
    -- Strip realm suffix from sender name
    sender = sender:match("([^-]+)") or sender

    -- Check if sender is our sync source
    if not PityRollDB.syncSource or PityRollDB.syncSource ~= sender then
        return  -- Ignore queries from non-leaders
    end

    -- Extract leader's hash
    local leaderHash = message:match("^SYNC_QUERY:(.+)$")
    if not leaderHash then
        return
    end

    -- Compute our hash
    local ourHash = addon.ComputePityTableHash()

    -- Compare hashes
    local status = (ourHash == leaderHash) and "MATCH" or "MISMATCH"

    -- Whisper response back to leader
    local response = "SYNC_RESPONSE:" .. status .. ":" .. ourHash
    ChatThrottleLib:SendAddonMessage("NORMAL", "PityRoll", response, "WHISPER", sender)
end

-- Handle sync response (leader receives from follower)
function addon.HandleSyncResponse(message, sender)
    if not syncState.queryInProgress then
        return  -- Ignore responses when not querying
    end

    -- Strip realm suffix from sender name
    sender = sender:match("([^-]+)") or sender

    -- Parse response
    local status, hash = message:match("^SYNC_RESPONSE:(%w+):(.+)$")
    if not status or not hash then
        return
    end

    -- Store response
    syncState.queryResponses[sender] = {
        status = status,
        hash = hash
    }
end

-- Display query results after timeout
function addon.DisplayQueryResults()
    if not syncState.queryInProgress then
        return
    end

    syncState.queryInProgress = false

    -- Check if any responses received
    local responseCount = 0
    for _ in pairs(syncState.queryResponses) do
        responseCount = responseCount + 1
    end

    if responseCount == 0 then
        print("[PityRoll Sync] No followers responded")
        return
    end

    -- Categorize responses
    local synced = {}
    local outOfSync = {}

    for sender, response in pairs(syncState.queryResponses) do
        if response.status == "MATCH" then
            table.insert(synced, sender)
        else
            table.insert(outOfSync, {name = sender, hash = response.hash})
        end
    end

    -- Store out-of-sync followers for context menu
    syncState.outOfSyncFollowers = {}
    for _, follower in ipairs(outOfSync) do
        table.insert(syncState.outOfSyncFollowers, follower.name)
    end
    table.sort(syncState.outOfSyncFollowers)

    -- Display results
    print("[PityRoll Sync] Follower Status Report:")

    if #synced > 0 then
        table.sort(synced)
        print("  |cff00ff00[SYNCED]|r " .. table.concat(synced, ", "))
    end

    if #outOfSync > 0 then
        for _, follower in ipairs(outOfSync) do
            print("  |cffff0000[OUT OF SYNC]|r " .. follower.name .. " (hash: " .. follower.hash .. ")")
        end
    end

    print("[PityRoll Sync] " .. #synced .. " in sync, " .. #outOfSync .. " out of sync")
end

-- Show force update confirmation dialog
function addon.ShowForceUpdateConfirmation(followerName)
    StaticPopupDialogs["PITYROLL_FORCE_UPDATE"] = {
        text = "Are you sure you want to force update " .. followerName .. "?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            addon.SendForceUpdate(followerName)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("PITYROLL_FORCE_UPDATE")
end

-- Send force update to follower
function addon.SendForceUpdate(followerName)
    local serialized = addon.SerializePityDatabase()
    local message = "SYNC_FORCE_UPDATE:" .. serialized

    if #message > 255 then
        print("[PityRoll Sync] Error: Database too large to send (size: " .. #message .. " bytes, limit: 255)")
        print("[PityRoll Sync] Consider reducing the number of players in your database")
        return
    end

    ChatThrottleLib:SendAddonMessage("NORMAL", "PityRoll", message, "WHISPER", followerName)
    print("[PityRoll Sync] Force update sent to " .. followerName)
end

-- Handle force update from leader
function addon.HandleForceUpdate(message, sender)
    sender = sender:match("([^-]+)") or sender

    if not PityRollDB.syncSource or PityRollDB.syncSource ~= sender then
        print("[PityRoll Sync] Rejected force update from " .. sender .. " (not your sync source)")
        return
    end

    local serialized = message:match("^SYNC_FORCE_UPDATE:(.*)$")
    if not serialized then
        print("[PityRoll Sync] Error: Invalid force update message")
        return
    end

    local oldCount = 0
    if PityRollDB.players then
        for _ in pairs(PityRollDB.players) do
            oldCount = oldCount + 1
        end
    end

    local newDatabase = addon.DeserializePityDatabase(serialized)

    PityRollDB.players = {}
    PityRollDB.players = newDatabase

    local newCount = 0
    for _ in pairs(PityRollDB.players) do
        newCount = newCount + 1
    end

    local newHash = addon.ComputePityTableHash()

    print("[PityRoll Sync] Force update received from " .. sender)
    print("[PityRoll Sync] Old database: " .. oldCount .. " players")
    print("[PityRoll Sync] New database: " .. newCount .. " players")
    print("[PityRoll Sync] New hash: " .. newHash)
end

-- Handle all sync messages (router function)
function addon.HandleSyncMessage(message, channel, sender)
    if message:sub(1, 11) == "SYNC_QUERY:" then
        addon.HandleSyncQuery(message, sender)
    elseif message:sub(1, 14) == "SYNC_RESPONSE:" then
        addon.HandleSyncResponse(message, sender)
    elseif message:sub(1, 18) == "SYNC_FORCE_UPDATE:" then
        addon.HandleForceUpdate(message, sender)
    end
end
