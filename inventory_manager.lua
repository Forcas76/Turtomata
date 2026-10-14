-- KISERLETI kapacitasalapu inventory-kezelo CC:Tweaked turtle programokhoz.

local manager = {}

local STATE_FILE = "inventory_state.txt"
local TEMP_FILE = ".inventory_state.tmp"
local firstMiningSlot = 2
local snapshot = nil
local seenBlocks = {}
local blockDrops = {}
local blockDropCounts = {}
local digCount = 0

local function now()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

local function miningSlotStart(config)
    return config and config.torchEnabled and 3 or 2
end

local function readSavedLearning()
    if not fs.exists(STATE_FILE) then return end
    local file = fs.open(STATE_FILE, "r")
    if not file then return end
    local content = file.readAll()
    file.close()
    local ok, saved = pcall(textutils.unserializeJSON, content)
    if not ok or type(saved) ~= "table" or saved.version ~= 1 then return end
    if type(saved.seenBlocks) == "table" then seenBlocks = saved.seenBlocks end
    if type(saved.blockDrops) == "table" then blockDrops = saved.blockDrops end
    if type(saved.blockDropCounts) == "table" then
        blockDropCounts = saved.blockDropCounts
    end
end

local function scanInternal(reason)
    local result = {
        updated = now(),
        reason = reason or "frissites",
        firstMiningSlot = firstMiningSlot,
        emptyMiningSlots = 0,
        usedMiningSlots = 0,
        miningSlots = 17 - firstMiningSlot,
        slots = {},
        itemTotals = {},
    }

    for slot = 1, 16 do
        local count = turtle.getItemCount(slot)
        local space = turtle.getItemSpace(slot)
        local detail = count > 0 and turtle.getItemDetail(slot) or nil
        local slotData = {
            count = count,
            space = space,
        }
        if detail then
            slotData.name = detail.name
            if detail.nbt then slotData.nbt = detail.nbt end
            local total = result.itemTotals[detail.name]
                or { count = 0, space = 0 }
            total.count = total.count + count
            total.space = total.space + space
            result.itemTotals[detail.name] = total
        end
        result.slots[tostring(slot)] = slotData

        if slot >= firstMiningSlot then
            if count == 0 then result.emptyMiningSlots = result.emptyMiningSlots + 1
            else result.usedMiningSlots = result.usedMiningSlots + 1 end
        end
    end
    snapshot = result
    return result
end

local function writeSnapshot(reason)
    if not snapshot then scanInternal(reason) end
    snapshot.reason = reason or snapshot.reason
    snapshot.updated = now()
    local payload = {
        version = 1,
        updated = snapshot.updated,
        reason = snapshot.reason,
        firstMiningSlot = firstMiningSlot,
        emptyMiningSlots = snapshot.emptyMiningSlots,
        usedMiningSlots = snapshot.usedMiningSlots,
        miningSlots = snapshot.miningSlots,
        slots = snapshot.slots,
        itemTotals = snapshot.itemTotals,
        seenBlocks = seenBlocks,
        blockDrops = blockDrops,
        blockDropCounts = blockDropCounts,
    }
    local file = fs.open(TEMP_FILE, "w")
    if not file then return false, "Nem irhato az inventory ideiglenes fajlja." end
    file.write(textutils.serializeJSON(payload))
    file.close()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(TEMP_FILE, STATE_FILE)
    return true
end

local function slotData(slot)
    return snapshot and snapshot.slots[tostring(slot)] or nil
end

local function findEmptySlot()
    for slot = firstMiningSlot, 16 do
        local data = slotData(slot)
        if data and data.count == 0 then return slot end
    end
    return nil
end

local function findMatchingSlot(itemName, requiredSpace)
    local bestSlot, bestSpace = nil, -1
    for slot = firstMiningSlot, 16 do
        local data = slotData(slot)
        if data and data.name == itemName and data.space >= requiredSpace
            and data.space > bestSpace then
            bestSlot, bestSpace = slot, data.space
        end
    end
    return bestSlot
end

local function compactInternal()
    local selected = turtle.getSelectedSlot()
    for target = firstMiningSlot, 16 do
        local targetDetail = turtle.getItemDetail(target)
        if targetDetail and turtle.getItemSpace(target) > 0 then
            for source = target + 1, 16 do
                local sourceDetail = turtle.getItemDetail(source)
                if sourceDetail and sourceDetail.name == targetDetail.name
                    and sourceDetail.nbt == targetDetail.nbt then
                    turtle.select(source)
                    turtle.transferTo(target)
                    if turtle.getItemSpace(target) == 0 then break end
                end
            end
        end
    end
    turtle.select(selected)
    scanInternal("stack_rendezes")
end

local function candidateFor(blockData)
    local blockName = type(blockData) == "table" and blockData.name or nil
    local dropName = blockName and blockDrops[blockName] or nil
    local requiredSpace = blockName and blockDropCounts[blockName] or 1

    if dropName then
        local matching = findMatchingSlot(dropName, requiredSpace)
        if matching then return matching, dropName, false end
        local empty = findEmptySlot()
        if empty then return empty, dropName, false end
        return nil, dropName, false
    end

    -- Nincs allando puffer: egyetlen ures slot mar eleg az uj dropnak.
    local empty = findEmptySlot()
    if empty then return empty, nil, true end
    return nil, nil, true
end

function manager.initialize(config)
    firstMiningSlot = miningSlotStart(config)
    readSavedLearning()
    scanInternal("programinditas")
    return writeSnapshot("programinditas")
end

function manager.refresh(config, reason, persist)
    firstMiningSlot = miningSlotStart(config)
    local result = scanInternal(reason)
    if persist then
        local ok, errorMessage = writeSnapshot(reason)
        if not ok then return nil, errorMessage end
    end
    return result
end

function manager.compact(config)
    firstMiningSlot = miningSlotStart(config)
    compactInternal()
    return writeSnapshot("stack_rendezes")
end

function manager.prepareForDig(config, blockData)
    firstMiningSlot = miningSlotStart(config)
    scanInternal("banyaszat_elott")
    local blockName = type(blockData) == "table" and blockData.name or nil
    if blockName and not seenBlocks[blockName] then
        local saved, saveReason = writeSnapshot("uj_blokk_elott")
        if not saved then return false, saveReason end
    end
    local slot, dropName, unknown = candidateFor(blockData)
    if not slot then
        compactInternal()
        slot, dropName, unknown = candidateFor(blockData)
    end
    if not slot then
        writeSnapshot(unknown and "nincs_hely_uj_dropnak" or "nincs_hely_dropnak")
        return false, string.format(
            "Nincs biztonsagos hely a dropnak: %s", blockName or "ismeretlen"
        )
    end

    local before = snapshot
    turtle.select(slot)
    return true, before, dropName
end

function manager.afterDig(config, blockData, before)
    firstMiningSlot = miningSlotStart(config)
    local after = scanInternal("banyaszat_utan")
    local blockName = type(blockData) == "table" and blockData.name or nil
    local learned = false

    if blockName and not seenBlocks[blockName] then
        seenBlocks[blockName] = true
        local candidates = {}
        for itemName, totals in pairs(after.itemTotals) do
            local old = before and before.itemTotals[itemName]
            local oldCount = old and old.count or 0
            if totals.count > oldCount then candidates[#candidates + 1] = itemName end
        end
        if #candidates == 1 then
            local dropName = candidates[1]
            blockDrops[blockName] = dropName
            local old = before and before.itemTotals[dropName]
            local oldCount = old and old.count or 0
            blockDropCounts[blockName] = math.max(
                1, after.itemTotals[dropName].count - oldCount
            )
        end
        learned = true
    elseif blockName and blockDrops[blockName] then
        local dropName = blockDrops[blockName]
        local old = before and before.itemTotals[dropName]
        local oldCount = old and old.count or 0
        local current = after.itemTotals[dropName]
        local gained = current and current.count - oldCount or 0
        if gained > (blockDropCounts[blockName] or 1) then
            blockDropCounts[blockName] = gained
            learned = true
        end
    end

    digCount = digCount + 1
    if learned or digCount % 16 == 0 then
        return writeSnapshot(learned and "uj_blokk_megtanulva" or "idoszakos_frissites")
    end
    return true
end

function manager.isCompletelyFull(config)
    firstMiningSlot = miningSlotStart(config)
    scanInternal("telitettseg")
    for slot = firstMiningSlot, 16 do
        local data = slotData(slot)
        if data and data.space > 0 then return false end
    end
    return true
end

function manager.status(config)
    firstMiningSlot = miningSlotStart(config)
    scanInternal("allapot")
    return {
        used = snapshot.usedMiningSlots,
        total = snapshot.miningSlots,
        empty = snapshot.emptyMiningSlots,
    }
end

return manager
