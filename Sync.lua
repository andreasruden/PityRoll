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
            database[addon.NormalizeName(name)] = tonumber(pity)
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

    playerName = addon.NormalizeName(playerName)

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
    sender = addon.NormalizeName(sender)

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

    sender = addon.NormalizeName(sender)

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
    sender = addon.NormalizeName(sender)

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

    if PityRollHistoryDB then
        PityRollHistoryDB.encounters = {}
        PityRollHistoryDB.pityChanges = {}
    end

    local newCount = 0
    for _ in pairs(PityRollDB.players) do
        newCount = newCount + 1
    end

    local newHash = addon.ComputePityTableHash()

    print("[PityRoll Sync] Force update received from " .. sender)
    print("[PityRoll Sync] Old database: " .. oldCount .. " players")
    print("[PityRoll Sync] New database: " .. newCount .. " players")
    print("[PityRoll Sync] New hash: " .. newHash)
    print("[PityRoll Sync] History cleared")
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

-- Helper to count table entries
function addon.TableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Serialize pity changes for export
function addon.SerializePityChanges()
    if not PityRollHistoryDB.pityChanges then
        return ""
    end

    local parts = {}
    for playerName, changes in pairs(PityRollHistoryDB.pityChanges) do
        table.insert(parts, string.format("%s:%d:%d", playerName, changes.old, changes.new))
    end

    table.sort(parts)

    return table.concat(parts, ",")
end

-- Base64 encoding function
function addon.Base64Encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- Base64 decoding function
function addon.Base64Decode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- Parse imported data and extract pity changes
function addon.ParseImportedData(text)
    if not text or text:trim() == "" then
        return {success = false, error = "Import text is empty"}
    end

    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        if line:trim() ~= "" then
            table.insert(lines, line)
        end
    end

    if #lines == 0 then
        return {success = false, error = "Import text is empty"}
    end

    local encodedLine = lines[#lines]

    local decoded = addon.Base64Decode(encodedLine)
    if not decoded or decoded == "" then
        return {success = false, error = "Invalid Base64 encoding"}
    end

    if not decoded:match("^#PrS#") then
        return {success = false, error = "Missing start marker (incomplete copy)"}
    end

    if not decoded:match("#PrE#$") then
        return {success = false, error = "Missing end marker (incomplete copy)"}
    end

    local data = decoded:match("^#PrS#(.*)#PrE#$")
    if not data then
        return {success = false, error = "Failed to extract data between markers"}
    end

    local pityChanges = {}
    for entry in data:gmatch("[^,]+") do
        local playerName, oldPity, newPity = entry:match("^(.+):(%d+):(%d+)$")
        if not playerName or not oldPity or not newPity then
            return {success = false, error = "Invalid pity change format: " .. entry}
        end
        playerName = addon.NormalizeName(playerName)

        pityChanges[playerName] = {
            old = tonumber(oldPity),
            new = tonumber(newPity)
        }
    end

    return {success = true, pityChanges = pityChanges}
end

-- Detect conflicts between imported pity changes and current database
function addon.DetectImportConflicts(pityChanges)
    local conflicts = {}
    local missingPlayers = {}
    local validChanges = {}

    for playerName, changes in pairs(pityChanges) do
        local currentPity = PityRollDB.players[playerName]

        if not currentPity then
            table.insert(missingPlayers, playerName)
        elseif currentPity ~= changes.old then
            table.insert(conflicts, {
                playerName = playerName,
                expectedOld = changes.old,
                actualCurrent = currentPity
            })
        else
            table.insert(validChanges, {
                playerName = playerName,
                oldPity = changes.old,
                newPity = changes.new
            })
        end
    end

    local hasConflicts = (#conflicts > 0 or #missingPlayers > 0)

    return {
        hasConflicts = hasConflicts,
        conflicts = conflicts,
        missingPlayers = missingPlayers,
        validChanges = validChanges
    }
end

-- Apply validated import changes to database and history
function addon.ApplyImportChanges(pityChanges)
    local updateCount = 0

    for playerName, changes in pairs(pityChanges) do
        PityRollDB.players[playerName] = changes.new

        if not PityRollHistoryDB.pityChanges[playerName] then
            PityRollHistoryDB.pityChanges[playerName] = {
                old = changes.old,
                new = changes.new
            }
        else
            PityRollHistoryDB.pityChanges[playerName].new = changes.new
        end

        updateCount = updateCount + 1
        local delta = changes.new - changes.old
        local sign = delta >= 0 and "+" or ""
        print(string.format("  %s: %d -> %d (%s%d pity)", playerName, changes.old, changes.new, sign, delta))
    end

    print(string.format("[PityRoll] Applied import: %d players updated", updateCount))
end

-- Show conflict error dialog
function addon.ShowImportConflictDialog(conflictResult)
    local errorText = "Import failed: Conflicts detected\n\n"

    if #conflictResult.conflicts > 0 then
        errorText = errorText .. "Pity mismatches:\n"
        for _, conflict in ipairs(conflictResult.conflicts) do
            errorText = errorText .. string.format("  %s: Import expects %d, but current pity is %d\n",
                conflict.playerName, conflict.expectedOld, conflict.actualCurrent)
        end
    end

    if #conflictResult.missingPlayers > 0 then
        if #conflictResult.conflicts > 0 then
            errorText = errorText .. "\n"
        end
        errorText = errorText .. "Players not in database:\n"
        for _, playerName in ipairs(conflictResult.missingPlayers) do
            errorText = errorText .. "  " .. playerName .. "\n"
        end
    end

    StaticPopupDialogs["PITYROLL_IMPORT_CONFLICT"] = {
        text = errorText,
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("PITYROLL_IMPORT_CONFLICT")
end

-- Show confirmation dialog with preview of changes
function addon.ShowImportConfirmationDialog(pityChanges)
    local frame = CreateFrame("Frame", "PityRollImportConfirmFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, 0, -5)
    frame.title:SetText("Confirm Import")

    local previewText = "The following pity changes will be applied:\n\n"
    local changeCount = 0
    local sortedNames = {}
    for playerName in pairs(pityChanges) do
        table.insert(sortedNames, playerName)
    end
    table.sort(sortedNames)

    for _, playerName in ipairs(sortedNames) do
        local changes = pityChanges[playerName]
        local delta = changes.new - changes.old
        local sign = delta >= 0 and "+" or ""
        previewText = previewText .. string.format("%s: %d -> %d (%s%d pity)\n",
            playerName, changes.old, changes.new, sign, delta)
        changeCount = changeCount + 1
    end

    previewText = previewText .. string.format("\nTotal: %d players affected", changeCount)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 50)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetSize(460, 340)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(false)
    editBox:SetText(previewText)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    scrollFrame:SetScrollChild(editBox)

    local applyButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    applyButton:SetSize(100, 30)
    applyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    applyButton:SetText("Apply")
    applyButton:SetNormalFontObject("GameFontNormal")
    applyButton:SetHighlightFontObject("GameFontHighlight")
    applyButton:SetScript("OnClick", function()
        addon.ApplyImportChanges(pityChanges)
        frame:Hide()
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    cancelButton:SetSize(100, 30)
    cancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    cancelButton:SetText("Cancel")
    cancelButton:SetNormalFontObject("GameFontNormal")
    cancelButton:SetHighlightFontObject("GameFontHighlight")
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:Show()
end

-- Main import dialog (entry point from context menu)
function addon.ShowImportDialog()
    local frame = CreateFrame("Frame", "PityRollImportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 250)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, 0, -5)
    frame.title:SetText("Import History")

    local instructions = frame:CreateFontString(nil, "OVERLAY")
    instructions:SetFontObject("GameFontNormal")
    instructions:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -30)
    instructions:SetText("Paste exported history below:")

    local errorLabel = frame:CreateFontString(nil, "OVERLAY")
    errorLabel:SetFontObject("GameFontNormal")
    errorLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 45)
    errorLabel:SetTextColor(1, 0, 0)
    errorLabel:SetText("")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 80)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetSize(460, 140)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(true)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    scrollFrame:SetScrollChild(editBox)

    local importButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    importButton:SetSize(100, 30)
    importButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    importButton:SetText("Import")
    importButton:SetNormalFontObject("GameFontNormal")
    importButton:SetHighlightFontObject("GameFontHighlight")
    importButton:SetScript("OnClick", function()
        errorLabel:SetText("")

        local text = editBox:GetText()
        local parseResult = addon.ParseImportedData(text)

        if not parseResult.success then
            errorLabel:SetText(parseResult.error)
            return
        end

        local conflictResult = addon.DetectImportConflicts(parseResult.pityChanges)

        if conflictResult.hasConflicts then
            frame:Hide()
            addon.ShowImportConflictDialog(conflictResult)
            return
        end

        frame:Hide()
        addon.ShowImportConfirmationDialog(parseResult.pityChanges)
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    cancelButton:SetSize(100, 30)
    cancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    cancelButton:SetText("Cancel")
    cancelButton:SetNormalFontObject("GameFontNormal")
    cancelButton:SetHighlightFontObject("GameFontHighlight")
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:Show()
end

-- Show copy dialog with text pre-selected
local function ShowCopyDialog(text, title)
    local frame = CreateFrame("Frame", "PityRollCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 150)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, 0, -5)
    frame.title:SetText(title or "Copy Text")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetSize(460, 100)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(true)
    editBox:SetText(text)
    editBox:HighlightText()
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    scrollFrame:SetScrollChild(editBox)

    frame:Show()
end

-- Export pity changes with base64 encoding
function addon.ExportPityChanges()
    local historyText = addon.SerializeHistory()
    local serialized = addon.SerializePityChanges()

    local exportText = historyText

    if serialized ~= "" then
        local markedData = "#PrS#" .. serialized .. "#PrE#"
        local encoded = addon.Base64Encode(markedData)
        exportText = exportText .. "\n" .. encoded
    end

    local playerCount = addon.TableSize(PityRollHistoryDB.pityChanges)
    local encounterCount = PityRollHistoryDB and #PityRollHistoryDB.encounters or 0

    local title = string.format("Export History (%d encounters, %d players)", encounterCount, playerCount)
    ShowCopyDialog(exportText, title)
    print("[PityRoll] Exported " .. encounterCount .. " encounters and " .. playerCount .. " pity changes")

    return exportText
end
