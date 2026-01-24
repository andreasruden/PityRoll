local addonName, addon = ...

-- Sync state tracking
local syncState = {
    queryResponses = {},
    queryInProgress = false,
    queryStartTime = nil,
    leaderHash = nil
}

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

-- Handle all sync messages (router function)
function addon.HandleSyncMessage(message, channel, sender)
    if message:sub(1, 11) == "SYNC_QUERY:" then
        addon.HandleSyncQuery(message, sender)
    elseif message:sub(1, 14) == "SYNC_RESPONSE:" then
        addon.HandleSyncResponse(message, sender)
    end
end
