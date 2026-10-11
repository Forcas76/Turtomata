-- CC:Tweaked teglatest-kitorelo program.
-- A turtle a terulet bal also elso sarka elott, a melyseg iranyaba nezzen.

local config = {}
local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false
local visited = 0
local stopRequested = false
local miningFinished = false
local persistenceEnabled = false
local STATE_FILE = "excavator_state.txt"
local STATE_TEMP_FILE = ".excavator_state.tmp"
local torchModuleOk, torchManager = pcall(require, "torch_manager")
if not torchModuleOk then torchManager = nil end
local runtime = {
    active = false,
    activity = "menu",
    baseCompleted = 0,
    torchSteps = 0,
}

local headings = {
    [0] = { x = 0, z = 1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 },
    [3] = { x = -1, z = 0 },
}

local function saveState()
    if not persistenceEnabled then return end
    local payload = {
        version = 1,
        active = runtime.active,
        activity = runtime.activity,
        baseCompleted = runtime.baseCompleted,
        torchSteps = runtime.torchSteps,
        visited = visited,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        config = config,
    }
    local file = fs.open(STATE_TEMP_FILE, "w")
    if not file then error("Nem irhato az allapotfajl.", 0) end
    file.write(textutils.serializeJSON(payload))
    file.close()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(STATE_TEMP_FILE, STATE_FILE)
end

local function setActivity(activity)
    runtime.activity = activity
    saveState()
end

local function loadState()
    if not fs.exists(STATE_FILE) then return nil end
    local file = fs.open(STATE_FILE, "r")
    if not file then return nil end
    local content = file.readAll()
    file.close()
    local ok, saved = pcall(textutils.unserializeJSON, content)
    if not ok or type(saved) ~= "table" or saved.version ~= 1 then return nil end
    if not saved.active or type(saved.config) ~= "table"
        or type(saved.position) ~= "table" then return nil end
    return saved
end

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function banner()
    print("============================")
    print("      TERULET ASAS")
    print("============================")
end

local function promptInteger(label, defaultValue, minimum)
    while true do
        write(label .. " [" .. defaultValue .. "]: ")
        local value = read()
        if value == "" then return defaultValue end
        local number = tonumber(value)
        if number and number == math.floor(number) and number >= minimum then
            return number
        end
        print("Hibas. Minimum: " .. minimum)
    end
end

local function promptChoice(title, choices, defaultChoice)
    while true do
        print(title)
        for index, text in ipairs(choices) do print("  " .. index .. ") " .. text) end
        write("Valasztas [" .. defaultChoice .. "]: ")
        local value = read()
        if value == "" then return defaultChoice end
        local choice = tonumber(value)
        if choice and choice == math.floor(choice) and choices[choice] then
            return choice
        end
        print("Hibas valasztas.\n")
    end
end

local function configure()
    local saved = loadState()
    clearScreen()
    banner()
    print("")
    local mode = promptChoice("Feladat:", {
        "Uj terulet",
        saved and "Auto folytatas" or "Auto (nincs mentes)",
    }, saved and 2 or 1)

    clearScreen()
    banner()
    print("")
    if mode == 2 then
        if not saved then error("Nincs hasznalhato mentes.", 0) end
        config = saved.config
        config.autoResume = true
        position.x = saved.position.x or 0
        position.y = saved.position.y or 0
        position.z = saved.position.z or 0
        heading = saved.heading or 0
        visited = saved.visited or 0
        runtime.active = true
        runtime.activity = saved.activity or "ismeretlen"
        runtime.baseCompleted = saved.baseCompleted or 0
        runtime.torchSteps = saved.torchSteps or 0
    else
        config.autoResume = false
        print("Terulet: szeles=jobbra, mely=elore, magas=felfele")
        print("")
        config.width = promptInteger("Szelesseg", 8, 1)
        config.depth = promptInteger("Melyseg", 16, 1)
        config.height = promptInteger("Magassag", 4, 1)
        config.fuelReserve = promptInteger("Fuel tartalek", 5, 2)
        print("")
        config.torchEnabled = promptChoice("KISERLETI faklyazas:", {
            "Kikapcsolva",
            "Bekapcsolva",
        }, 1) == 2
        if config.torchEnabled then
            config.torchInterval = promptInteger("Faklya tavolsag", 12, 1)
        else
            config.torchInterval = 0
        end
    end

    if config.torchEnabled and not torchManager then
        error("Hianyzik a torch_manager.lua modul.", 0)
    end

    clearScreen()
    banner()
    print("")
    print("Meret: " .. config.width .. "x" .. config.depth .. "x" .. config.height)
    print("Blokkok: " .. (config.width * config.depth * config.height))
    print("Fuel+: " .. config.fuelReserve)
    print(config.autoResume and "Mod: auto folytatas" or "Mod: uj terulet")
    if config.torchEnabled then
        print("Faklya: " .. config.torchInterval .. " cellankent (KISERLETI)")
    else
        print("Faklya: ki")
    end
    print("")
    print("Start: bal-also-elso sarok elott")
    print("Lada: hatul, fuel: folotte")
    if config.torchEnabled then print("Faklya lada: a fuel lada folott") end
    print("")
    write("ENTER = inditas")
    read()
    clearScreen()
    banner()
end

local function fuelLevel()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return math.huge end
    return level
end

local function fuelText()
    local level = fuelLevel()
    return level == math.huge and "korlatlan" or tostring(level)
end

local function distanceHome()
    return math.abs(position.x) + math.abs(position.y) + math.abs(position.z)
end

local function refuelSlotOne(required)
    if fuelLevel() >= required then return true end
    local selected = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then
        while turtle.getItemCount(1) > 0 and fuelLevel() < required do
            turtle.refuel(1)
        end
    end
    if selected == 1 then selected = 2 end
    turtle.select(selected)
    return fuelLevel() >= required
end

local function inventoryFull()
    local firstMiningSlot = config.torchEnabled and 3 or 2
    for slot = firstMiningSlot, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
end

local function inventoryUsage()
    local used = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then used = used + 1 end
    end
    return used
end

local function status(prefix)
    local total = (config.width or 0) * (config.depth or 0) * (config.height or 0)
    local percent = total > 0 and math.floor((visited / total) * 100) or 0
    print(string.format(
        "%s | %s | %d/%d (%d%%)",
        prefix, runtime.activity, visited, total, percent
    ))
    print(string.format(
        "Poz:%d,%d,%d Fuel:%s Haza:%d Inv:%d/16",
        position.x, position.y, position.z, fuelText(), distanceHome(), inventoryUsage()
    ))
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

local function requiredForMove(nextX, nextY, nextZ)
    local homeAfterMove = math.abs(nextX) + math.abs(nextY) + math.abs(nextZ)
    if not returningHome then homeAfterMove = homeAfterMove + config.fuelReserve end
    return 1 + homeAfterMove
end

local function digForward()
    local attempts = 0
    while turtle.detect() do
        if not turtle.dig() then return false, "Az elottem levo blokk nem ashato." end
        sleep(0.1)
        attempts = attempts + 1
        if attempts > 20 then return false, "Tul sok blokk esik elem." end
    end
    return true
end

local function forward()
    local direction = headings[heading]
    local nextX = position.x + direction.x
    local nextZ = position.z + direction.z
    if not refuelSlotOne(requiredForMove(nextX, position.y, nextZ)) then
        return false, "fuel"
    end
    local attempts = 0
    while not turtle.forward() do
        local dug, reason = digForward()
        if not dug then
            if turtle.attack() then sleep(0.2) else return false, reason end
        end
        attempts = attempts + 1
        if attempts > 30 then return false, "Nem tudok elore menni." end
    end
    position.x, position.z = nextX, nextZ
    saveState()
    return true
end

local function vertical(upward)
    local nextY = position.y + (upward and 1 or -1)
    if not refuelSlotOne(requiredForMove(position.x, nextY, position.z)) then
        return false, "fuel"
    end
    local move = upward and turtle.up or turtle.down
    local detect = upward and turtle.detectUp or turtle.detectDown
    local dig = upward and turtle.digUp or turtle.digDown
    local attack = upward and turtle.attackUp or turtle.attackDown
    local attempts = 0
    while not move() do
        if detect() then
            if not dig() then return false, "A fuggoleges blokk nem ashato." end
        elseif attack() then
            sleep(0.2)
        else
            return false, "Nem tudok fuggolegesen mozogni."
        end
        attempts = attempts + 1
        if attempts > 30 then return false, "Tul sok fuggoleges kiserlet." end
    end
    position.y = nextY
    saveState()
    return true
end

local function moveX(target)
    while position.x ~= target do
        face(position.x < target and 1 or 3)
        local ok, reason = forward()
        if not ok then return false, reason end
    end
    return true
end

local function moveZ(target)
    while position.z ~= target do
        face(position.z < target and 0 or 2)
        local ok, reason = forward()
        if not ok then return false, reason end
    end
    return true
end

local function moveY(target)
    while position.y ~= target do
        local ok, reason = vertical(position.y < target)
        if not ok then return false, reason end
    end
    return true
end

local function returnHome()
    returningHome = true
    setActivity("hazateres")
    print("Hazateres...")
    local ok, reason = moveY(0)
    if ok then ok, reason = moveX(0) end
    if ok then ok, reason = moveZ(0) end
    if ok then face(0) end
    returningHome = false
    return ok, reason
end

local function unloadBehind()
    turnAround()
    local hasBlock, block = turtle.inspect()
    if not hasBlock or not string.find(block.name or "", "chest", 1, true) then
        turnAround()
        return false, "Nincs leado lada a turtle mogott."
    end
    local allDeposited = true
    for slot = 1, 16 do
        turtle.select(slot)
        local keepFuel = slot == 1 and turtle.getItemCount(1) > 0 and turtle.refuel(0)
        local keepTorch = slot == 2 and config.torchEnabled
            and torchManager and torchManager.keepReservedSlot(config)
        if turtle.getItemCount(slot) > 0 and not keepFuel and not keepTorch then
            turtle.drop()
            if turtle.getItemCount(slot) > 0 then allDeposited = false end
        end
    end
    if not allDeposited then
        turnAround()
        turtle.select(config.torchEnabled and 3 or 2)
        return false, "A leado lada megtelt."
    end
    return true
end

local function fuelFromUpperChest(requiredAfterService)
    local accessFuel = config.torchEnabled and 4 or 2
    if fuelLevel() ~= math.huge and not refuelSlotOne(accessFuel) then
        turnAround()
        return false, "Nincs eleg kezdo fuel a kiszolgalasi ladakhoz."
    end
    if not turtle.up() then
        turnAround()
        return false, "A turtle feletti hely nem szabad."
    end
    position.y = position.y + 1
    saveState()
    local requiredAtTop = requiredAfterService + (config.torchEnabled and 3 or 1)
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        else
            turtle.down()
            position.y = position.y - 1
            saveState()
            turnAround()
            return false, "Az 1-es slot nem egetheto."
        end
    end
    while fuelLevel() < requiredAtTop do
        if not turtle.suck(64) then
            turtle.down()
            position.y = position.y - 1
            saveState()
            turnAround()
            return false, "Az uzemanyaglada ures."
        end
        if not turtle.refuel(0) then
            turtle.drop()
            turtle.down()
            position.y = position.y - 1
            saveState()
            turnAround()
            return false, "Nem egetheto targy van a fuel ladaban."
        end
        turtle.refuel()
    end

    if config.torchEnabled then
        if not turtle.up() then
            turtle.down()
            position.y = position.y - 1
            saveState()
            turnAround()
            return false, "Nem tudok felmenni a faklyas ladahoz."
        end
        position.y = position.y + 1
        saveState()
        local torchOk, torchReason = torchManager.refillFromChest()
        if not turtle.down() then return false, "Nem tudok lejonni a faklyas ladatol." end
        position.y = position.y - 1
        saveState()
        if not torchOk then
            turtle.down()
            position.y = position.y - 1
            saveState()
            turnAround()
            return false, torchReason
        end
    end
    if not turtle.down() then return false, "Nem tudok leereszkedni." end
    position.y = position.y - 1
    saveState()
    turnAround()
    turtle.select(config.torchEnabled and 3 or 2)
    return true
end

local function serviceHome(requiredForTrip)
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "Nem vagyok a kezdohelyen."
    end
    setActivity("urites_tankolas")
    refuelSlotOne(math.max(config.torchEnabled and 4 or 2, requiredForTrip))
    local unloaded, unloadReason = unloadBehind()
    if not unloaded then return false, unloadReason end
    return fuelFromUpperChest(requiredForTrip)
end

local function tripRequirement(x, y, z)
    local distance = math.abs(x) + math.abs(y) + math.abs(z)
    return (2 * distance) + config.fuelReserve + 2
end

local function navigateFromHome(x, y, z, targetHeading)
    local ok, reason = moveZ(z)
    if ok then ok, reason = moveX(x) end
    if ok then ok, reason = moveY(y) end
    if ok then face(targetHeading) end
    return ok, reason
end

local function serviceAndResume(reasonText)
    local savedX, savedY, savedZ = position.x, position.y, position.z
    local savedHeading = heading
    local savedActivity = runtime.activity
    clearScreen()
    banner()
    print("Megszakitas: " .. reasonText)
    local homeOk, homeReason = returnHome()
    if not homeOk then return false, homeReason end
    local serviced, serviceReason = serviceHome(tripRequirement(savedX, savedY, savedZ))
    if not serviced then return false, serviceReason end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    print("Vissza a munkapontra...")
    setActivity("vissza_munkapontra")
    local resumed, resumeReason = navigateFromHome(savedX, savedY, savedZ, savedHeading)
    if resumed then setActivity(savedActivity) end
    return resumed, resumeReason
end

local function moveToTarget(targetX, targetY, targetZ)
    while position.x ~= targetX or position.y ~= targetY or position.z ~= targetZ do
        if stopRequested and not returningHome then
            return false, "Felhasznaloi leallitas."
        end
        if inventoryFull() then
            local resumed, reason = serviceAndResume("Inventory tele.")
            if not resumed then return false, reason end
        end

        local ok, reason
        if position.y ~= targetY then
            ok, reason = vertical(position.y < targetY)
        elseif position.z ~= targetZ then
            face(position.z < targetZ and 0 or 2)
            ok, reason = forward()
        else
            face(position.x < targetX and 1 or 3)
            ok, reason = forward()
        end

        if not ok and reason == "fuel" then
            local resumed, resumeReason = serviceAndResume("Keves a fuel.")
            if not resumed then return false, resumeReason end
        elseif not ok then
            return false, reason
        end
    end
    return true
end

local function clearUpperCell()
    local attempts = 0
    while turtle.detectUp() do
        if not turtle.digUp() then
            return false, "A felso blokk nem ashato."
        end
        sleep(0.1)
        attempts = attempts + 1
        if attempts > 20 then
            return false, "Tul sok blokk esik felulrol."
        end
    end
    return true
end

local function visit(targetX, targetY, targetZ, total, clearAbove)
    local ok, reason = moveToTarget(targetX, targetY, targetZ)
    if not ok then return false, reason end

    local processed = 1

    if clearAbove then
        if inventoryFull() then
            local resumed, resumeReason = serviceAndResume("Inventory tele.")
            if not resumed then return false, resumeReason end
        end
        local cleared, clearReason = clearUpperCell()
        if not cleared then return false, clearReason end
        processed = processed + 1
    end

    local nextVisited = visited + processed
    if nextVisited <= 2 or nextVisited % 16 == 0 or nextVisited == total then
        print(string.format("Haladas: %d/%d | %d,%d,%d", nextVisited, total,
            position.x, position.y, position.z))
    end
    return true, nil, processed
end

local function targetForBaseIndex(baseIndex)
    local cellsPerPass = config.width * config.depth
    local layerPass = math.floor((baseIndex - 1) / cellsPerPass)
    local withinPass = (baseIndex - 1) % cellsPerPass
    local row = math.floor(withinPass / config.width)
    local column = withinPass % config.width
    local globalRow = layerPass * config.depth + row
    local x = globalRow % 2 == 0 and column or (config.width - 1 - column)
    local z = layerPass % 2 == 0 and (row + 1) or (config.depth - row)
    local y = layerPass * 2
    return x, y, z, y + 1 < config.height
end

local function torchDirection(x, z)
    if x == 0 then return 3 end
    if x == config.width - 1 then return 1 end
    if z == 1 then return 2 end
    if z == config.depth then return 0 end
    return nil
end

local function processTorchStep(x, z)
    if not config.torchEnabled then return true, nil, runtime.torchSteps end
    local nextTorchSteps = (runtime.torchSteps or 0) + 1
    local direction = torchDirection(x, z)
    if nextTorchSteps < config.torchInterval or direction == nil then
        return true, nil, nextTorchSteps
    end

    if inventoryFull() then
        local resumed, reason = serviceAndResume("Inventory tele.")
        if not resumed then return false, reason end
    end

    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end
    local placed, placeReason = torchManager.placeInDirection(
        direction,
        function() return heading end,
        face
    )
    if not placed then return false, placeReason end
    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end
    return true, nil, 0
end

local function runExcavation()
    persistenceEnabled = true
    local total = config.width * config.depth * config.height
    local baseTotal = config.width * config.depth * math.ceil(config.height / 2)

    if config.autoResume then
        runtime.active = true
        setActivity("auto_ujrainditas")
        if not returnHome() then return end
    else
        runtime.active = true
        runtime.baseCompleted = 0
        runtime.torchSteps = 0
        visited = 0
        setActivity("indulas")
    end

    local serviced, serviceReason = serviceHome(config.fuelReserve + 4)
    if not serviced then
        printError("Inditasi hiba: " .. serviceReason)
        return
    end

    local stopReason = nil
    setActivity("kitores")
    for baseIndex = runtime.baseCompleted + 1, baseTotal do
        if stopRequested then stopReason = "Felhasznaloi leallitas." break end
        local x, y, z, clearAbove = targetForBaseIndex(baseIndex)
        local cellOk, cellReason, processed = visit(x, y, z, total, clearAbove)
        if not cellOk then stopReason = cellReason break end
        local torchOk, torchReason, nextTorchSteps = processTorchStep(x, z)
        if not torchOk then stopReason = torchReason break end
        visited = visited + processed
        runtime.torchSteps = nextTorchSteps
        runtime.baseCompleted = baseIndex
        saveState()
    end

    if stopReason then printError("Kitores leallt: " .. (stopReason or "hiba"))
    else print("A teljes terulet ki lett asva.") end

    if returnHome() then
        local finalOk, finalReason = serviceHome(config.fuelReserve)
        if finalOk then
            if not stopReason then
                runtime.active = false
                setActivity("kesz")
            end
            print("Kesz: otthon, inventory uritve.")
        else printError("Otthoni hiba: " .. finalReason) end
    end
end

local function miningTask()
    local ok, errorMessage = pcall(runExcavation)
    if not ok then
        printError("Programhiba: " .. tostring(errorMessage))
        if distanceHome() > 0 then returnHome() end
    end
    miningFinished = true
    os.queueEvent("excavator_finished")
end

local function stopListener()
    print("Q/Ctrl+T: leallitas | S: allapot")
    while not miningFinished do
        local event, key = os.pullEventRaw()
        if event == "excavator_finished" then return end
        if event == "terminate" or (event == "key" and key == keys.q) then
            if not stopRequested then
                stopRequested = true
                print("Leallitas kerese fogadva. Biztonsagos hazateres indul...")
            end
        elseif event == "key" and key == keys.s then
            status("Allapot")
        end
    end
end

local configured, configureError = pcall(configure)
if not configured then
    printError("Beallitasi hiba: " .. tostring(configureError))
else
    parallel.waitForAll(miningTask, stopListener)
end
