-- CC:Tweaked Nether ut- es alagutepito turtle.
-- 1-es slot: fuel. Faklya nelkul 2-5., faklyaval 3-5. slot: epitoanyag.
-- KISERLETI faklyazasnal a 2-es slot a faklyake. A 6-16. slot banyaszslot.

local config = {}
local position = { x = 0, y = 0, z = 0 }
local heading = 0
local stopRequested = false
local taskFinished = false
local persistenceEnabled = false
local returningHome = false

local STATE_FILE = "nether_builder_state.txt"
local STATE_TEMP_FILE = ".nether_builder_state.tmp"
local BUILD_LAST, MINE_FIRST = 5, 6
local buildFirstSlot = 2

local actionLogOk, actionLogger = pcall(require, "action_log")
if not actionLogOk then actionLogger = nil end
local torchModuleOk, torchManager = pcall(require, "torch_manager")
if not torchModuleOk then torchManager = nil end

local headings = {
    [0] = { x = 0, z = 1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 },
    [3] = { x = -1, z = 0 },
}

local runtime = {
    active = false,
    activity = "menu",
    completed = 0,
    path = {},
    pending = nil,
    serviceLevel = 0,
    blockDrops = {},
}

local function saveState()
    if not persistenceEnabled then return end
    local payload = {
        version = 1,
        active = runtime.active,
        activity = runtime.activity,
        completed = runtime.completed,
        path = runtime.path,
        pending = runtime.pending,
        serviceLevel = runtime.serviceLevel,
        blockDrops = runtime.blockDrops,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        config = config,
    }
    local file = fs.open(STATE_TEMP_FILE, "w")
    if not file then error("Nem irhato a Nether allapotfajl.", 0) end
    file.write(textutils.serializeJSON(payload))
    file.close()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(STATE_TEMP_FILE, STATE_FILE)
end

local function setActivity(value)
    runtime.activity = value
    saveState()
end

local function loadState()
    if not fs.exists(STATE_FILE) then return nil end
    local file = fs.open(STATE_FILE, "r")
    if not file then return nil end
    local content = file.readAll()
    file.close()
    local ok, saved = pcall(textutils.unserializeJSON, content)
    if not ok or type(saved) ~= "table" or saved.version ~= 1
        or not saved.active or type(saved.config) ~= "table"
        or type(saved.position) ~= "table" then return nil end
    return saved
end

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function promptChoice(title, choices, defaultChoice)
    while true do
        print(title)
        for index, value in ipairs(choices) do print("  " .. index .. ") " .. value) end
        write("Valasztas [" .. defaultChoice .. "]: ")
        local value = read()
        if value == "" then return defaultChoice end
        local number = tonumber(value)
        if number and number == math.floor(number) and choices[number] then return number end
        print("Hibas valasztas.\n")
    end
end

local function promptInteger(label, defaultValue, minimum)
    while true do
        write(label .. " [" .. defaultValue .. "]: ")
        local value = read()
        if value == "" then return defaultValue end
        local number = tonumber(value)
        if number and number == math.floor(number) and number >= minimum then return number end
        print("Hibas. Minimum: " .. minimum)
    end
end

local function normalizeBlockName(value)
    value = string.lower(value or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if not string.find(value, ":", 1, true)
        and string.match(value, "^[a-z0-9_./-]+$") then
        value = "minecraft:" .. value
    end
    if not string.match(value, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") then return nil end
    return value
end

local function promptBlockName(defaultValue)
    while true do
        print("Epitoanyag formatuma:")
        print("<mod_neve>:<blokk_neve>")
        print("Pelda: minecraft:cobblestone")
        print("Rovid vanilla: cobblestone")
        write("Epito blokk [" .. defaultValue .. "]: ")
        local value = read()
        if value == "" then value = defaultValue end
        value = normalizeBlockName(value)
        if value then return value end
        printError("Hibas blokkazonosito.")
    end
end

local function configure()
    local saved = loadState()
    clearScreen()
    print("=== NETHER UTEPITO ===\n")
    local mode = promptChoice("Feladat:", {
        "Lepcso fel/le",
        "Vedett 1x2 alagut",
        saved and "Auto folytatas" or "Auto (nincs mentes)",
    }, saved and 3 or 1)

    clearScreen()
    if mode == 3 then
        if not saved then error("Nincs hasznalhato Nether mentes.", 0) end
        config = saved.config
        config.autoResume = true
        position.x = saved.position.x or 0
        position.y = saved.position.y or 0
        position.z = saved.position.z or 0
        heading = saved.heading or 0
        runtime.active = true
        runtime.activity = saved.activity or "ismeretlen"
        runtime.completed = saved.completed or 0
        runtime.path = type(saved.path) == "table" and saved.path or {}
        runtime.pending = saved.pending
        runtime.serviceLevel = saved.serviceLevel or 0
        runtime.blockDrops = type(saved.blockDrops) == "table" and saved.blockDrops or {}
    else
        config.autoResume = false
        config.mode = mode
        if mode == 1 then
            config.stairDirection = promptChoice("Lepcso iranya:", {
                "Felfele",
                "Lefele",
            }, 1) == 1 and "up" or "down"
        end
        config.length = promptInteger("Hossz", 64, 1)
        config.builderBlock = promptBlockName("minecraft:cobblestone")
        config.fuelReserve = promptInteger("Fuel tartalek", 8, 4)
        print("")
        config.torchEnabled = promptChoice("KISERLETI faklyazas:", {
            "Kikapcsolva",
            "Bekapcsolva",
        }, 1) == 2
        config.torchInterval = config.torchEnabled
            and promptInteger("Faklya tavolsag", 8, 1) or 0
    end

    config.fuelReserve = config.fuelReserve or 8
    config.torchEnabled = config.torchEnabled == true
    config.torchInterval = config.torchEnabled and (config.torchInterval or 8) or 0
    if config.torchEnabled and not torchManager then
        error("Hianyzik a torch_manager.lua.", 0)
    end
    buildFirstSlot = config.torchEnabled and 3 or 2
    config.builderBlock = normalizeBlockName(config.builderBlock)
    if not config.builderBlock then error("Hibas mentett epitoanyag.", 0) end

    clearScreen()
    print("=== OSSZEFOGLALO ===")
    if config.mode == 1 then
        print("Mod: lepcso " .. (config.stairDirection == "up" and "felfele" or "lefele"))
    else
        print("Mod: vedett 1x2 alagut")
    end
    print("Hossz: " .. config.length)
    print("Epito: " .. config.builderBlock)
    print("Faklya: " .. (config.torchEnabled
        and ("be, " .. config.torchInterval .. " lepesenkent") or "ki"))
    print("Epito slot: " .. buildFirstSlot .. "-5")
    print("Banyasz slot: 6-16")
    print("Lada: hatul, fuel: folotte")
    if config.torchEnabled then print("Faklyas lada: a fuel lada folott") end
    print("Epitoanyag a leado lada elejere!")
    if config.autoResume then print("Folytatas: " .. runtime.completed .. " lepestol") end
    print("")
    write("ENTER = inditas")
    read()
    clearScreen()
end

local function fuelLevel()
    local value = turtle.getFuelLevel()
    return value == "unlimited" and math.huge or value
end

local function fuelText()
    local value = fuelLevel()
    return value == math.huge and "korlatlan" or tostring(value)
end

local function refuelFromSlotOne(required)
    if fuelLevel() >= required then return true end
    local selectedSlot = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then
        while turtle.getItemCount(1) > 0 and fuelLevel() < required do turtle.refuel(1) end
    end
    if selectedSlot == 1 then selectedSlot = MINE_FIRST end
    turtle.select(selectedSlot)
    return fuelLevel() >= required
end

local function turnLeft()
    turtle.turnLeft()
    heading = (heading + 3) % 4
    saveState()
end

local function turnRight()
    turtle.turnRight()
    heading = (heading + 1) % 4
    saveState()
end

local function turnAround()
    turnRight()
    turnRight()
end

local function face(target)
    local difference = (target - heading) % 4
    if difference == 1 then turnRight()
    elseif difference == 2 then turnAround()
    elseif difference == 3 then turnLeft() end
end

local function copyMove(move)
    return move.kind == "h" and { kind = "h", heading = move.heading }
        or { kind = move.kind }
end

local function inverseMove(move)
    if move.kind == "u" then return { kind = "d" } end
    if move.kind == "d" then return { kind = "u" } end
    return { kind = "h", heading = (move.heading + 2) % 4 }
end

local function positionAfter(source, move)
    local result = { x = source.x, y = source.y, z = source.z }
    if move.kind == "u" then result.y = result.y + 1
    elseif move.kind == "d" then result.y = result.y - 1
    elseif move.heading == 0 then result.z = result.z + 1
    elseif move.heading == 1 then result.x = result.x + 1
    elseif move.heading == 2 then result.z = result.z - 1
    elseif move.heading == 3 then result.x = result.x - 1 end
    return result
end

local function samePosition(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

local function pathEndpoint(path)
    local result = { x = 0, y = 0, z = 0 }
    for _, move in ipairs(path) do result = positionAfter(result, move) end
    return result
end

local function normalizePending()
    if type(runtime.pending) ~= "table" then return true end
    local before = pathEndpoint(runtime.path)
    local move = runtime.pending.move
    if runtime.pending.operation == "push" then
        local after = positionAfter(before, move)
        if samePosition(position, after) then runtime.path[#runtime.path + 1] = copyMove(move)
        elseif not samePosition(position, before) then return false end
    elseif runtime.pending.operation == "pop" then
        local parent = {}
        for index = 1, math.max(0, #runtime.path - 1) do parent[index] = copyMove(runtime.path[index]) end
        if samePosition(position, pathEndpoint(parent)) then table.remove(runtime.path)
        elseif not samePosition(position, before) then return false end
    end
    runtime.pending = nil
    saveState()
    return true
end

local function rawMove(move)
    if not refuelFromSlotOne(1) then return false, "Nincs fuel a mozgasra." end
    if move.kind == "h" then
        face(move.heading)
        if not turtle.forward() then return false, "Akadaly van az elmentett utvonalon." end
        local direction = headings[heading]
        position.x = position.x + direction.x
        position.z = position.z + direction.z
    elseif move.kind == "u" then
        if not turtle.up() then return false, "Nem tudok felfele lepni." end
        position.y = position.y + 1
    elseif move.kind == "d" then
        if not turtle.down() then return false, "Nem tudok lefele lepni." end
        position.y = position.y - 1
    else
        return false, "Ismeretlen utvonallepes."
    end
    saveState()
    return true
end

local function pushMove(move)
    runtime.pending = { operation = "push", move = copyMove(move) }
    saveState()
    local ok, reason = rawMove(move)
    if not ok then runtime.pending = nil saveState() return false, reason end
    runtime.path[#runtime.path + 1] = copyMove(move)
    runtime.pending = nil
    saveState()
    return true
end

local function popMove()
    local move = runtime.path[#runtime.path]
    if not move then return true end
    runtime.pending = { operation = "pop", move = copyMove(move) }
    saveState()
    local ok, reason = rawMove(inverseMove(move))
    if not ok then runtime.pending = nil saveState() return false, reason end
    table.remove(runtime.path)
    runtime.pending = nil
    saveState()
    return true
end

local function clonePath(path)
    local result = {}
    for index, move in ipairs(path) do result[index] = copyMove(move) end
    return result
end

local function retreatHome()
    returningHome = true
    setActivity("hazateres")
    while #runtime.path > 0 do
        local ok, reason = popMove()
        if not ok then returningHome = false return false, reason end
    end
    face(0)
    returningHome = false
    return true
end

local function replayPath(path)
    setActivity("vissza_munkapontra")
    for _, move in ipairs(path) do
        local ok, reason = pushMove(move)
        if not ok then return false, reason end
    end
    return true
end

local function builderCount()
    local total = 0
    for slot = buildFirstSlot, BUILD_LAST do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == config.builderBlock then
            total = total + turtle.getItemCount(slot)
        end
    end
    return total
end

local function selectBuilder()
    for slot = buildFirstSlot, BUILD_LAST do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == config.builderBlock and turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            return true
        end
    end
    return false
end

local function miningFull()
    for slot = MINE_FIRST, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
end

local function selectMatchingSlot(itemName, firstSlot, lastSlot)
    if not itemName then return false end
    for slot = firstSlot, lastSlot do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == itemName and turtle.getItemSpace(slot) > 0 then
            turtle.select(slot)
            return true
        end
    end
    return false
end

local function selectDropSlot(blockData)
    local blockName = type(blockData) == "table" and blockData.name or nil
    local expectedDrop = blockName and runtime.blockDrops[blockName] or blockName

    -- A kibanyaszott epitoanyag rogton visszakerulhet a fenntartott stackekbe.
    if expectedDrop == config.builderBlock
        and selectMatchingSlot(expectedDrop, buildFirstSlot, BUILD_LAST) then
        return true
    end
    if selectMatchingSlot(expectedDrop, MINE_FIRST, 16) then return true end

    -- Ismeretlen dropnal a blokk sajat targyvaltozatat is megprobaljuk.
    if blockName ~= expectedDrop
        and selectMatchingSlot(blockName, MINE_FIRST, 16) then return true end

    -- Uj targyfajta csak tenylegesen ures banyaszslotot kapjon.
    for slot = MINE_FIRST, 16 do
        if turtle.getItemCount(slot) == 0 then
            turtle.select(slot)
            return true
        end
    end
    return false
end

local function inventoryTotals()
    local totals = {}
    for slot = buildFirstSlot, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            totals[detail.name] = (totals[detail.name] or 0) + turtle.getItemCount(slot)
        end
    end
    return totals
end

local function learnDrop(blockData, before)
    local blockName = type(blockData) == "table" and blockData.name or nil
    if not blockName then return end
    local after = inventoryTotals()
    local learnedName = nil
    for itemName, count in pairs(after) do
        if count > (before[itemName] or 0) then
            if learnedName then return end
            learnedName = itemName
        end
    end
    if learnedName and runtime.blockDrops[blockName] ~= learnedName then
        runtime.blockDrops[blockName] = learnedName
        saveState()
    end
end

local function inspectDepositChest()
    local exists, data = turtle.inspect()
    return exists and type(data) == "table"
        and string.find(data.name or "", "chest", 1, true) ~= nil
end

local function unloadAndLoadBuilders(requiredBlocks)
    turnAround()
    if not inspectDepositChest() then
        turnAround()
        return false, "Nincs leado/epitoanyag lada a turtle mogott."
    end

    local selectedSlot = turtle.getSelectedSlot()
    for slot = 1, 16 do
        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        if count > 0 then
            local detail = turtle.getItemDetail(slot)
            local keepFuel = slot == 1 and turtle.refuel(0)
            local keepTorch = slot == 2 and config.torchEnabled
                and torchManager.keepReservedSlot(config)
            local keepBuilder = slot >= buildFirstSlot and slot <= BUILD_LAST
                and detail and detail.name == config.builderBlock
            if not keepFuel and not keepTorch and not keepBuilder then
                turtle.drop()
                if turtle.getItemCount(slot) > 0 then
                    turtle.select(selectedSlot)
                    turnAround()
                    return false, "A leado lada megtelt."
                end
            end
        end
    end

    if requiredBlocks > 0 then
        for slot = buildFirstSlot, BUILD_LAST do
            turtle.select(slot)
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name ~= config.builderBlock then
                turtle.drop()
                detail = nil
            end
            local space = turtle.getItemSpace(slot)
            if space > 0 then
                turtle.suck(space)
                detail = turtle.getItemDetail(slot)
                if detail and detail.name ~= config.builderBlock then
                    local wrongName = detail.name
                    turtle.drop()
                    turtle.select(selectedSlot)
                    turnAround()
                    return false, "A lada elso targya nem az epitoanyag: " .. wrongName
                end
            end
        end
    end
    turtle.select(selectedSlot)
    if builderCount() < requiredBlocks then
        turnAround()
        return false, "Nincs eleg " .. config.builderBlock .. " a leado ladaban."
    end
    return true
end

local function refuelFromUpperChest(requiredFuel, refillTorch)
    local accessFuel = config.torchEnabled and 4 or 2
    if not refuelFromSlotOne(accessFuel) then
        turnAround()
        return false, "Nincs eleg kezdo fuel a kiszolgalo ladak eleresehez."
    end
    if not turtle.up() then
        turnAround()
        return false, "A turtle feletti hely nem szabad."
    end
    position.y = position.y + 1
    runtime.serviceLevel = 1
    saveState()

    local reason = nil
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        else
            turtle.drop()
            reason = "Az 1-es slotban nem egetheto targy volt."
        end
    end
    while not reason and fuelLevel() < requiredFuel do
        if not turtle.suck(64) then
            reason = "Az uzemanyaglada ures."
        elseif not turtle.refuel(0) then
            local detail = turtle.getItemDetail(1)
            local name = detail and detail.name or "ismeretlen"
            turtle.drop()
            reason = "Nem egetheto targy a fuel ladaban: " .. name
        else
            -- Mindig a teljes felvett stacket tankolja be.
            turtle.refuel()
        end
    end

    if not reason and config.torchEnabled and refillTorch ~= false then
        if not turtle.up() then
            reason = "Nem tudok felmenni a faklyas ladahoz."
        else
            position.y = position.y + 1
            runtime.serviceLevel = 2
            saveState()
            local torchOk, torchReason = torchManager.refillFromChest()
            if not torchOk then reason = torchReason end
            if not turtle.down() then
                return false, "Nem tudok lejonni a faklyas ladatol."
            end
            position.y = position.y - 1
            runtime.serviceLevel = 1
            saveState()
        end
    end

    if fuelLevel() < 1 then return false, reason or "Nincs fuel a leereszkedeshez." end
    if not turtle.down() then return false, "Nem tudok lejonni a fuel ladatol." end
    position.y = position.y - 1
    runtime.serviceLevel = 0
    saveState()
    turnAround()
    turtle.select(MINE_FIRST)
    if reason then return false, reason end
    return true
end

local function serviceHome(requiredFuel, requiredBlocks, refillTorch)
    if #runtime.path ~= 0 or position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "A lada-kiszolgalas nem a kezdoponton indult."
    end
    setActivity("urites_anyag_tankolas")
    local loaded, loadReason = unloadAndLoadBuilders(requiredBlocks)
    if not loaded then return false, loadReason end
    return refuelFromUpperChest(requiredFuel, refillTorch)
end

local function serviceAndResume(reasonText, requiredBlocks)
    local resumePath = clonePath(runtime.path)
    local previousActivity = runtime.activity
    clearScreen()
    print("Kiszolgalas: " .. reasonText)
    local home, homeReason = retreatHome()
    if not home then return false, homeReason end
    local requiredFuel = (2 * #resumePath) + config.fuelReserve + 12
    local serviced, serviceReason = serviceHome(requiredFuel, requiredBlocks or 1)
    if not serviced then return false, serviceReason end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    local replayed, replayReason = replayPath(resumePath)
    if not replayed then return false, replayReason end
    setActivity(previousActivity)
    return true
end

local function ensureBuilder(required)
    if builderCount() >= required then return true end
    local ok, reason = serviceAndResume("Elfogyott az epitoanyag.", required)
    if not ok then return false, reason end
    if builderCount() < required then return false, "A feltoltes utan sincs eleg epitoanyag." end
    return true
end

local function ensureWorkFuel(extraMoves)
    local required = #runtime.path + extraMoves + config.fuelReserve + 2
    if refuelFromSlotOne(required) then return true end
    return serviceAndResume("Keves az uzemanyag.", config.mode == 2 and 6 or 1)
end

local function status(prefix)
    print(string.format(
        "%s | %s | %d/%d",
        prefix, runtime.activity, runtime.completed, config.length or 0
    ))
    print(string.format(
        "Poz:%d,%d,%d Fuel:%s Ut:%d Epit:%d",
        position.x, position.y, position.z, fuelText(), #runtime.path, builderCount()
    ))
    if config.torchEnabled then
        print("Faklya: " .. turtle.getItemCount(2))
    end
end

local function managedDig(direction)
    local inspect, dig
    if direction == "up" then inspect, dig = turtle.inspectUp, turtle.digUp
    elseif direction == "down" then inspect, dig = turtle.inspectDown, turtle.digDown
    else inspect, dig = turtle.inspect, turtle.dig end

    local attempts = 0
    while true do
        local hasBlock, blockData = inspect()
        if not hasBlock then return true end
        if stopRequested then return false, "Felhasznaloi leallitas." end
        if not selectDropSlot(blockData) then
            local serviced, reason = serviceAndResume(
                "A kovetkezo drop mar nem fer el.", config.mode == 2 and 6 or 1
            )
            if not serviced then return false, reason end
        else
            local before = inventoryTotals()
            if not dig() then return false, "A blokk nem banyaszhato." end
            learnDrop(blockData, before)
            sleep(0.15)
            attempts = attempts + 1
            if attempts > 20 then return false, "Tul sok blokk esik vissza az utba." end
        end
    end
end

local function placeIfAir(direction, targetHeading)
    local originalHeading = heading
    local detect, place
    if direction == "up" then detect, place = turtle.detectUp, turtle.placeUp
    elseif direction == "down" then detect, place = turtle.detectDown, turtle.placeDown
    else
        face(targetHeading)
        detect, place = turtle.detect, turtle.place
    end
    if detect() then
        if direction == "forward" then face(originalHeading) end
        return true
    end
    local ready, reason = ensureBuilder(1)
    if not ready then
        if direction == "forward" then face(originalHeading) end
        return false, reason
    end
    if direction == "forward" then face(targetHeading) end
    if not selectBuilder() then
        if direction == "forward" then face(originalHeading) end
        return false, "Nem talalom az epitoanyagot a "
            .. buildFirstSlot .. "-5. slotban."
    end
    local placed = place()
    if direction == "forward" then face(originalHeading) end
    turtle.select(MINE_FIRST)
    if not placed then return false, "Nem sikerult epitoanyagot lerakni." end
    saveState()
    return true
end

local function placeTorchAboveWithSupport()
    if not torchManager.hasTorch() then
        local serviced, reason = serviceAndResume(
            "Elfogyott a faklya.", config.mode == 2 and 6 or 1
        )
        if not serviced then return false, reason end
    end

    local placed, reason = torchManager.placeAbove(function() return heading end, face)
    if placed then return true end

    -- Nyilt terepen a fali faklyanak nem feltetlenul van mihez tapadnia.
    -- Belepes a faklya cellajaba, oldalso tamasz epites, majd ujraprobalas.
    if turtle.detectUp() then return false, reason end
    local moved, moveReason = pushMove({ kind = "u" })
    if not moved then return false, moveReason end
    local supported, supportReason = placeIfAir("forward", (heading + 1) % 4)
    local returned, returnReason = popMove()
    if not returned then return false, returnReason end
    if not supported then return false, supportReason end

    placed, reason = torchManager.placeAbove(function() return heading end, face)
    if not placed then return false, reason end
    return true
end

local function placeScheduledTorch()
    setActivity("faklyazas")

    -- Felfele lepcsozesnel a jelenlegi fej feletti cella lesz a kovetkezo
    -- lepes utja. Ezert egy cellaval visszabb, az elozo foknal faklyazunk.
    if config.mode == 1 and config.stairDirection == "up" then
        local lastMove = runtime.path[#runtime.path]
        if not lastMove or lastMove.kind ~= "h" then
            return false, "Nem talalom a felfele lepcso elozo fokat."
        end
        local restoredMove = copyMove(lastMove)
        local backed, backReason = popMove()
        if not backed then return false, backReason end
        local placed, placeReason = placeTorchAboveWithSupport()
        local restored, restoreReason = pushMove(restoredMove)
        if not restored then return false, restoreReason end
        face(0)
        return placed, placeReason
    end

    local placed, reason = placeTorchAboveWithSupport()
    face(0)
    return placed, reason
end

local function buildTunnelShell(travelHeading)
    local ok, reason = placeIfAir("down")
    if not ok then return false, reason end
    ok, reason = placeIfAir("forward", (travelHeading + 3) % 4)
    if not ok then return false, reason end
    ok, reason = placeIfAir("forward", (travelHeading + 1) % 4)
    if not ok then return false, reason end

    ok, reason = pushMove({ kind = "u" })
    if not ok then return false, reason end
    ok, reason = placeIfAir("forward", (travelHeading + 3) % 4)
    if ok then ok, reason = placeIfAir("forward", (travelHeading + 1) % 4) end
    if ok then ok, reason = placeIfAir("up") end
    local downOk, downReason = popMove()
    if not downOk then return false, downReason end
    face(travelHeading)
    return ok, reason
end

local function buildStairStep()
    local ok, reason = ensureBuilder(1)
    if not ok then return false, reason end

    if config.stairDirection == "up" then
        ok, reason = managedDig("up")
        if ok then ok, reason = pushMove({ kind = "u" }) end
        if ok then ok, reason = managedDig("forward") end
        if ok then ok, reason = pushMove({ kind = "h", heading = 0 }) end
    else
        ok, reason = managedDig("forward")
        if ok then ok, reason = pushMove({ kind = "h", heading = 0 }) end
        if ok then ok, reason = managedDig("down") end
        if ok then ok, reason = pushMove({ kind = "d" }) end
    end
    if not ok then return false, reason end
    ok, reason = managedDig("up")
    if not ok then return false, reason end
    ok, reason = placeIfAir("down")
    if not ok then return false, reason end
    face(0)
    return true
end

local function buildTunnelStep()
    local ok, reason = ensureBuilder(6)
    if not ok then return false, reason end
    ok, reason = managedDig("forward")
    if not ok then return false, reason end
    ok, reason = pushMove({ kind = "h", heading = 0 })
    if not ok then return false, reason end
    ok, reason = managedDig("up")
    if not ok then return false, reason end
    return buildTunnelShell(0)
end

local function replayCompletedPath()
    runtime.path = {}
    runtime.pending = nil
    saveState()
    for _ = 1, runtime.completed do
        local ok, reason
        if config.mode == 1 and config.stairDirection == "up" then
            ok, reason = pushMove({ kind = "u" })
            if ok then ok, reason = pushMove({ kind = "h", heading = 0 }) end
        else
            ok, reason = pushMove({ kind = "h", heading = 0 })
            if ok and config.mode == 1 then ok, reason = pushMove({ kind = "d" }) end
        end
        if not ok then return false, reason end
    end
    face(0)
    return true
end

local function recoverServicePosition()
    if runtime.serviceLevel <= 0 then return true end
    if position.x ~= 0 or position.z ~= 0 or position.y ~= runtime.serviceLevel then
        return false, "A fuel-lada pozicioja nem egyezik a mentessel."
    end
    while runtime.serviceLevel > 0 do
        if not refuelFromSlotOne(1) or not turtle.down() then
            return false, "Nem tudok lejonni a fuel ladatol."
        end
        position.y = position.y - 1
        runtime.serviceLevel = runtime.serviceLevel - 1
        saveState()
    end
    face(0)
    return true
end

local function runBuilder()
    persistenceEnabled = true
    if actionLogger then
        local modeName = config.mode == 1
            and (config.stairDirection == "up" and "Nether lepcso fel" or "Nether lepcso le")
            or "Nether vedett 1x2"
        actionLogger.log(modeName
            .. (config.autoResume and " - auto folytatas" or " - uj munka")
            .. (config.torchEnabled and " - faklyazas=be" or " - faklyazas=ki"))
    end

    if config.autoResume then
        setActivity("auto_helyreallitas")
        local serviceRecovered, serviceReason = recoverServicePosition()
        if not serviceRecovered then error(serviceReason, 0) end
        if not normalizePending() then error("A mentett utvonal nem egyezik a pozicioval.", 0) end
        local home, homeReason = retreatHome()
        if not home then error(homeReason, 0) end
        local serviced, serviceReason2 = serviceHome(
            (4 * runtime.completed) + config.fuelReserve + 12,
            config.mode == 2 and 6 or 1
        )
        if not serviced then error(serviceReason2, 0) end
        local replayed, replayReason = replayCompletedPath()
        if not replayed then error(replayReason, 0) end
    else
        runtime.active = true
        runtime.activity = "indulas"
        runtime.completed = 0
        runtime.path = {}
        runtime.pending = nil
        runtime.serviceLevel = 0
        runtime.blockDrops = {}
        saveState()
        local serviced, reason = serviceHome(
            config.fuelReserve + 12,
            config.mode == 2 and 6 or 1
        )
        if not serviced then error(reason, 0) end
    end

    local stopReason = nil
    for step = runtime.completed + 1, config.length do
        if stopRequested then stopReason = "Felhasznaloi leallitas." break end
        setActivity(config.mode == 1 and "lepcso_epites" or "alagut_epites")
        local fueled, fuelReason = ensureWorkFuel(config.mode == 1 and 4 or 5)
        if not fueled then stopReason = fuelReason break end
        if miningFull() then
            local serviced, serviceReason = serviceAndResume(
                "Az inventory megtelt.", config.mode == 2 and 6 or 1
            )
            if not serviced then stopReason = serviceReason break end
        end
        local ok, reason
        if config.mode == 1 then ok, reason = buildStairStep()
        else ok, reason = buildTunnelStep() end
        if not ok then stopReason = reason break end
        if config.torchEnabled and step % config.torchInterval == 0 then
            ok, reason = placeScheduledTorch()
            if not ok then stopReason = reason break end
        end
        runtime.completed = step
        saveState()
        if step == 1 or step % 8 == 0 or step == config.length then
            status("Haladas")
        end
    end

    if stopReason then printError("A Nether epites leallt: " .. tostring(stopReason))
    else print("A beallitott Nether utvonal elkeszult.") end

    local home, homeReason = retreatHome()
    if not home then
        printError("Nem sikerult hazaterni: " .. tostring(homeReason))
        return
    end
    local serviced, serviceReason = serviceHome(config.fuelReserve + 4, 0, false)
    if not serviced then
        printError("Otthoni kiszolgalasi hiba: " .. tostring(serviceReason))
        return
    end
    if not stopReason then
        runtime.active = false
        setActivity("kesz")
    else
        setActivity("megallitva_otthon")
    end
    print("A turtle a kezdoponton van.")
end

local function builderTask()
    local ok, reason = pcall(runBuilder)
    if not ok then
        printError("Programhiba: " .. tostring(reason))
        if persistenceEnabled and #runtime.path > 0 then
            local home, homeReason = retreatHome()
            if not home then printError("A hazateres is elakadt: " .. tostring(homeReason)) end
        end
    end
    taskFinished = true
    os.queueEvent("nether_builder_finished")
end

local function stopListener()
    print("Q/Ctrl+T: leallitas | S: allapot")
    while not taskFinished do
        local event, key = os.pullEventRaw()
        if event == "nether_builder_finished" then return end
        if event == "terminate" or (event == "key" and key == keys.q) then
            stopRequested = true
            print("Leallitas kerese fogadva.")
        elseif event == "key" and key == keys.s then
            status("Allapot")
        end
    end
end

local configured, configureReason = pcall(configure)
if not configured then
    printError("Beallitasi hiba: " .. tostring(configureReason))
else
    parallel.waitForAll(builderTask, stopListener)
end
