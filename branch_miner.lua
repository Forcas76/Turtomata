-- CC:Tweaked branch mining turtle
-- Interaktiv menurendszerrel, automatikus uritessel es tankolassal.

local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false
local torchModuleOk, torchManager = pcall(require, "torch_manager")
if not torchModuleOk then torchManager = nil end
local actionLogOk, actionLogger = pcall(require, "action_log")
if not actionLogOk then actionLogger = nil end
local inventoryModuleOk, inventoryManager = pcall(require, "inventory_manager")
if not inventoryModuleOk then inventoryManager = nil end

local headings = {
    [0] = { x = 0, z = 1, name = "elore (+Z)" },
    [1] = { x = 1, z = 0, name = "jobbra (+X)" },
    [2] = { x = 0, z = -1, name = "hatra (-Z)" },
    [3] = { x = -1, z = 0, name = "balra (-X)" },
}

local config = {}
local STATE_FILE = "branch_miner_state.txt"
local STATE_TEMP_FILE = ".branch_miner_state.tmp"
local persistenceEnabled = false
local stopRequested = false
local miningFinished = false
local runtime = {
    active = false,
    activity = "menu",
    mainCompleted = 0,
    branchesCompletedAt = 0,
}

local function saveState()
    if not persistenceEnabled then return end
    local payload = {
        version = 1,
        active = runtime.active,
        activity = runtime.activity,
        mainCompleted = runtime.mainCompleted,
        branchesCompletedAt = runtime.branchesCompletedAt,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        config = config,
    }
    local encoded = textutils.serializeJSON(payload)
    local file = fs.open(STATE_TEMP_FILE, "w")
    if not file then error("Nem irhato az allapotfajl.", 0) end
    file.write(encoded)
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

local function promptInteger(label, defaultValue, minimum)
    while true do
        write(label .. " [" .. defaultValue .. "]: ")
        local value = read()
        if value == "" then
            return defaultValue
        end
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
        for index, text in ipairs(choices) do
            print("  " .. index .. ") " .. text)
        end
        write("Valasztas [" .. defaultChoice .. "]: ")
        local value = read()
        if value == "" then
            return defaultChoice
        end
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
    print("=== BRANCH MINER ===\n")

    local taskMode = promptChoice("Feladat:", {
        "Branch 1x2",
        "Branch 1x3",
        "Egyenes 3x3",
        "Terulet asas",
        saved and "Auto folytatas" or "Auto (nincs mentes)",
    }, saved and 5 or 1)

    clearScreen()

    if taskMode == 4 then
        config.launchExperimental = true
        return
    elseif taskMode == 5 then
        if not saved then
            printError("Nincs hasznalhato mentes.")
            sleep(2)
            return configure()
        end
        config = saved.config
        config.autoResume = true
        position.x = saved.position.x or 0
        position.y = saved.position.y or 0
        position.z = saved.position.z or 0
        heading = saved.heading or 0
        runtime.active = true
        runtime.activity = saved.activity or "ismeretlen"
        runtime.mainCompleted = saved.mainCompleted or 0
        runtime.branchesCompletedAt = saved.branchesCompletedAt or 0
    else
        config.tunnelMode = taskMode
        config.autoResume = false
        print("Mod: " .. ({ "Branch 1x2", "Branch 1x3", "Egyenes 3x3" })[taskMode])
        print("")
        config.startMode = promptChoice("Indulas:", {
            "Uj munka",
            "Kezi folytatas",
        }, 1)

        if config.startMode == 2 then
            config.startOffset = promptInteger("Kezdo tavolsag", 64, 1)
        else
            config.startOffset = 0
        end

        print("")
        if config.tunnelMode == 3 then
            config.mainLength = promptInteger("Alagut hossza", 128, 1)
            config.branchLength = 0
            config.branchSpacing = 0
        else
            config.mainLength = promptInteger("Fotengely", 128, 1)
            config.branchLength = promptInteger("Oldalagat", 16, 1)
            config.branchSpacing = promptInteger("Agak tavolsaga", 3, 1)
        end
        config.fuelReserve = promptInteger("Fuel tartalek", 5, 2)
        print("")
        config.experimentalInventory = promptChoice("KISERLETI inv.:", {
            "Kikapcsolva",
            "Bekapcsolva",
        }, 1) == 2
        print("")
        config.torchEnabled = promptChoice("KISERLETI faklyazas:", {
            "Kikapcsolva",
            "Bekapcsolva",
        }, 1) == 2
        if config.torchEnabled then
            config.mainTorchInterval = promptInteger("Fout: hany beasas", 12, 1)
            if config.tunnelMode == 3 then
                config.branchTorchInterval = 0
            else
                config.branchTorchInterval = promptInteger("Ag: hany blokkonkent", 8, 1)
            end
            config.torchPlacementMode = promptChoice("Faklya helye (KISERLETI):", {
                "Oldalt: blokk ki, faklya be",
                "A turtle feje fole",
            }, 1)
        else
            config.mainTorchInterval = 0
            config.branchTorchInterval = 0
            config.torchPlacementMode = 1
        end
    end

    config.experimentalInventory = config.experimentalInventory == true
    if config.experimentalInventory and not inventoryManager then
        error("Hianyzik az inventory_manager.lua modul.", 0)
    end
    if config.torchEnabled and not torchManager then
        error("Hianyzik a torch_manager.lua modul.", 0)
    end
    if config.torchEnabled then
        config.mainTorchInterval = config.mainTorchInterval or config.torchInterval or 12
        config.branchTorchInterval = config.branchTorchInterval
            or config.torchInterval or 8
        config.torchPlacementMode = config.torchPlacementMode or 1
    end

    clearScreen()
    print("=== OSSZEFOGLALO ===")
    if config.autoResume then
        print("Mod: auto folytatas")
        print("Mentve: " .. runtime.activity)
        print("Poz: " .. position.x .. "," .. position.y .. "," .. position.z)
    elseif config.startMode == 1 then
        print("Mod: uj munka")
    else
        print("Mod: kezi, kezdo=" .. config.startOffset)
    end
    if config.tunnelMode == 3 then
        print("Hossz: " .. config.mainLength)
    else
        print("Fo: " .. config.mainLength .. "  Ag: " .. config.branchLength)
        print("Agkoz: " .. config.branchSpacing)
    end
    print("Fuel+: " .. config.fuelReserve)
    print("Inv.: " .. (config.experimentalInventory and "KISERLETI" or "regi"))
    if config.torchEnabled then
        print("Fout faklya: " .. config.mainTorchInterval .. " beasas")
        if config.tunnelMode ~= 3 then
            print("Ag faklya: " .. config.branchTorchInterval .. " blokk")
        end
        print("Faklya hely: " .. (config.torchPlacementMode == 2 and "fej folott" or "oldalt"))
    else
        print("Faklya: ki")
    end
    local tunnelNames = {
        "2 blokk magas",
        "3 blokk magas",
        "3x3 blokk",
    }
    print("Meret: " .. tunnelNames[config.tunnelMode])
    print("Lada: hatul, fuel: folotte")
    if config.torchEnabled then print("Faklya lada: a fuel lada folott") end
    write("ENTER = inditas")
    read()
    clearScreen()
end

local function fuelLevel()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return math.huge end
    return level
end

local function fuelText(level)
    if level == math.huge then return "korlatlan" end
    return tostring(level)
end

local function distanceHomeAt(x, y, z)
    return math.abs(x) + math.abs(y) + math.abs(z)
end

local function distanceHome()
    return distanceHomeAt(position.x, position.y, position.z)
end

local function inventoryUsage()
    local usedSlots = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then usedSlots = usedSlots + 1 end
    end
    return usedSlots, math.floor((usedSlots / 16) * 100)
end

local function inventoryFull()
    if config.experimentalInventory and inventoryManager then
        return inventoryManager.isCompletelyFull(config)
    end
    -- Faklyazasnal az 1-es slot a fuel, a 2-es slot a faklya helye.
    local firstMiningSlot = config.torchEnabled and 3 or 2
    for slot = firstMiningSlot, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
end

local function status(prefix)
    local usedSlots, usedPercent = inventoryUsage()
    print(string.format(
        "%s | %s | %d/%d",
        prefix, runtime.activity, runtime.mainCompleted, config.mainLength or 0
    ))
    print(string.format(
        "Poz:%d,%d,%d Fuel:%s Haza:%d Inv:%d/16 %d%%",
        position.x, position.y, position.z, fuelText(fuelLevel()),
        distanceHome(), usedSlots, usedPercent
    ))
    if config.experimentalInventory and inventoryManager then
        local inventoryStatus = inventoryManager.status(config)
        print(string.format(
            "KIS-INV:%d/%d Ures:%d Puffer:%d",
            inventoryStatus.used, inventoryStatus.total,
            inventoryStatus.empty, inventoryStatus.buffer
        ))
    end
end

local function refuelFromInventory(required)
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

local function face(targetHeading)
    local difference = (targetHeading - heading) % 4
    if difference == 1 then turnRight()
    elseif difference == 2 then turnAround()
    elseif difference == 3 then turnLeft() end
end

local serviceAndResume

local function managedDig(direction)
    local inspect, dig
    if direction == "up" then
        inspect, dig = turtle.inspectUp, turtle.digUp
    elseif direction == "down" then
        inspect, dig = turtle.inspectDown, turtle.digDown
    else
        inspect, dig = turtle.inspect, turtle.dig
    end

    local hasBlock, blockData = inspect()
    if not hasBlock then return true end
    if not config.experimentalInventory or not inventoryManager or returningHome then
        if dig() then return true end
        return false, "A blokk nem ashato."
    end

    while hasBlock do
        local ready, beforeOrReason = inventoryManager.prepareForDig(config, blockData)
        if not ready then
            local resumed, resumeReason = serviceAndResume(
                "KISERLETI inventory: " .. tostring(beforeOrReason)
            )
            if not resumed then return false, resumeReason end
            hasBlock, blockData = inspect()
            if not hasBlock then return true end
        else
            if not dig() then return false, "A blokk nem ashato." end
            local recorded, recordReason = inventoryManager.afterDig(
                config, blockData, beforeOrReason
            )
            if not recorded then return false, recordReason end
            return true
        end
    end
    return true
end

local function digForwardUntilClear()
    local attempts = 0
    while turtle.detect() do
        local dug, reason = managedDig("forward")
        if not dug then return false, reason or "Nem tudom kiasni az elottem levo blokkot." end
        sleep(0.15)
        attempts = attempts + 1
        if attempts > 20 then return false, "Tul sok blokk esett az utamba." end
    end
    return true
end

local forward

local function clearVerticalColumn()
    if turtle.detectUp() then
        local dug, reason = managedDig("up")
        if not dug then return false, reason or "Nem tudom kiasni a felso blokkot." end
    end
    if config.tunnelMode >= 2 and turtle.detectDown() then
        local dug, reason = managedDig("down")
        if not dug then return false, reason or "Nem tudom kiasni az also blokkot." end
    end
    return true
end

local function clearTunnelCrossSection()
    local cleared, reason = clearVerticalColumn()
    if not cleared then return false, reason end
    if config.tunnelMode ~= 3 then return true end

    -- A turtle a 3x3-as szelet kozepen all. Kiter balra, atmegy jobbra,
    -- majd visszaall a kozepvonalra es az eredeti iranyba.
    local originalHeading = heading
    local centerX, centerY, centerZ = position.x, position.y, position.z
    turnLeft()
    local moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    cleared, reason = clearVerticalColumn()
    if not cleared then return false, reason end

    turnAround()
    moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    cleared, reason = clearVerticalColumn()
    if not cleared then return false, reason end

    turnAround()
    moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    if position.x ~= centerX or position.y ~= centerY or position.z ~= centerZ then
        return false, "A 3x3-as vagas utan nem a kozepvonalra ertem vissza."
    end
    -- Ekkor pontosan balra nez; egy jobbra fordulas allitja vissza az iranyt.
    turnRight()
    if heading ~= originalHeading then
        return false, "A 3x3-as vagas utan hibas az irany."
    end
    return true
end

local function nextPositionForward()
    local direction = headings[heading]
    return position.x + direction.x, position.y, position.z + direction.z
end

forward = function()
    local nextX, nextY, nextZ = nextPositionForward()
    local requiredAfterMove = distanceHomeAt(nextX, nextY, nextZ)
    if not returningHome then requiredAfterMove = requiredAfterMove + config.fuelReserve end

    if not refuelFromInventory(1 + requiredAfterMove) then
        return false, "fuel", string.format(
            "A kovetkezo lepeshez %d fuel kellene, de csak %s van.",
            1 + requiredAfterMove, fuelText(fuelLevel())
        )
    end

    local attempts = 0
    while not turtle.forward() do
        local dug, reason = digForwardUntilClear()
        if not dug then
            if turtle.attack() then sleep(0.2)
            else return false, "blocked", reason or "Nem tudok elore menni." end
        end
        attempts = attempts + 1
        if attempts > 30 then
            return false, "blocked", "Tul sok sikertelen elorelepesi kiserlet."
        end
    end
    position.x, position.y, position.z = nextX, nextY, nextZ
    saveState()
    return true
end

local function moveAxis(target, coordinateName, positiveHeading, negativeHeading)
    while position[coordinateName] ~= target do
        if position[coordinateName] < target then face(positiveHeading)
        else face(negativeHeading) end
        local moved, _, reason = forward()
        if not moved then return false, reason end
    end
    return true
end

local function navigateTo(targetX, targetZ, targetHeading)
    local ok, reason
    if targetX == 0 and targetZ == 0 then
        -- Oldalagatbol eloszor a fotengelyre, majd azon haza.
        ok, reason = moveAxis(targetX, "x", 1, 3)
        if ok then ok, reason = moveAxis(targetZ, "z", 0, 2) end
    else
        -- Otthonrol eloszor a fotengelyen, majd az oldalagatban halad.
        ok, reason = moveAxis(targetZ, "z", 0, 2)
        if ok then ok, reason = moveAxis(targetX, "x", 1, 3) end
    end
    if ok then face(targetHeading) end
    return ok, reason
end

local function moveVerticalTo(targetY)
    while position.y > targetY do
        if not refuelFromInventory(1) then return false, "Nincs fuel a leereszkedeshez." end
        if turtle.down() then
            position.y = position.y - 1
            saveState()
        elseif turtle.detectDown() then
            local dug, digReason = managedDig("down")
            if not dug then return false, digReason or "Nem tudok leereszkedni." end
        elseif not turtle.attackDown() then
            return false, "Nem tudok leereszkedni."
        end
    end
    while position.y < targetY do
        if not refuelFromInventory(1) then return false, "Nincs fuel a felemelkedeshez." end
        if turtle.up() then
            position.y = position.y + 1
            saveState()
        elseif turtle.detectUp() then
            local dug, digReason = managedDig("up")
            if not dug then return false, digReason or "Nem tudok felemelkedni." end
        elseif not turtle.attackUp() then
            return false, "Nem tudok felemelkedni."
        end
    end
    return true
end

local function returnHome()
    returningHome = true
    setActivity("hazateres")
    status("Hazateres")
    local travelY = config.tunnelMode == 3 and 1 or 0
    local ok, reason = moveVerticalTo(travelY)
    if ok then ok, reason = navigateTo(0, 0, 0) end
    if ok then ok, reason = moveVerticalTo(0) end
    returningHome = false
    if ok then status("Hazaertem")
    else printError("A hazateres elakadt: " .. (reason or "ismeretlen hiba")) end
    return ok, reason
end

local function unloadBehind()
    turnAround()
    local hasBlock, block = turtle.inspect()
    if not hasBlock or not string.find(block.name or "", "chest", 1, true) then
        return false, "Nincs leado lada kozvetlenul a turtle mogott."
    end
    local selected = turtle.getSelectedSlot()
    local allDeposited = true
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            local keepForFuel = slot == 1 and turtle.refuel(0)
            local keepForTorch = slot == 2 and config.torchEnabled
                and torchManager and torchManager.keepReservedSlot(config)
            if not keepForFuel and not keepForTorch then
                turtle.drop()
                if turtle.getItemCount(slot) > 0 then allDeposited = false end
            end
        end
    end
    turtle.select(selected)
    if not allDeposited then
        return false, "A leado lada megtelt, vagy nincs a turtle mogott."
    end
    return true
end

local function refuelFromUpperChest(requiredAfterService)
    -- Ekkor a turtle a ladak fele nez. A fuel lada a leado lada folott van.
    local accessFuel = config.torchEnabled and 4 or 2
    if fuelLevel() ~= math.huge and not refuelFromInventory(accessFuel) then
        return false, "Nincs eleg fuel a kiszolgalasi ladak eleresehez."
    end
    if not turtle.up() then
        return false, "Nem tudok felmenni az uzemanyagladahoz. Szabad a hely folottem?"
    end
    position.y = position.y + 1
    saveState()

    local requiredAtTop = requiredAfterService + (config.torchEnabled and 3 or 1)
    local selected = turtle.getSelectedSlot()
    local reason = nil
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        else reason = "Az 1-es slotban nem egetheto targy maradt." end
    end
    local refuelOk = reason == nil and fuelLevel() >= requiredAtTop
    while not refuelOk and not reason do
        turtle.select(1)
        if not turtle.suck(64) then
            reason = "Az uzemanyaglada ures, vagy nincs a leado lada folott."
            break
        elseif not turtle.refuel(0) then
            turtle.drop()
            reason = "Az uzemanyagladaban nem egetheto targy van."
            break
        else
            -- A felvett teljes stacket betankolja (peldaul mind a 64 szenet).
            turtle.refuel()
            refuelOk = fuelLevel() >= requiredAtTop
        end
    end
    if selected == 1 then selected = 2 end
    turtle.select(selected)

    if refuelOk and config.torchEnabled then
        if not turtle.up() then
            reason = "Nem tudok felmenni a faklyas ladahoz."
        else
            position.y = position.y + 1
            saveState()
            local torchOk, torchReason = torchManager.refillFromChest()
            if not torchOk then reason = torchReason end
            if not turtle.down() then
                return false, "Nem tudok lejonni a faklyas ladatol."
            end
            position.y = position.y - 1
            saveState()
        end
    end

    if fuelLevel() < 1 then
        printError("Nincs fuel a leereszkedeshez; a turtle a felso szinten maradt.")
        return false, reason or "Elfogyott az uzemanyag."
    end
    if not turtle.down() then return false, "Nem tudok visszaereszkedni a kezdohelyre." end
    position.y = position.y - 1
    saveState()
    turnAround()
    if not refuelOk or reason then
        return false, reason or "Nem sikerult eleg uzemanyagot felvenni."
    end
    return true
end

local function serviceHome(requiredForTrip)
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "A lada-kiszolgalas csak a kezdohelyen vegezheto."
    end
    setActivity("urites_tankolas")
    refuelFromInventory(math.max(config.torchEnabled and 4 or 2, requiredForTrip))
    local unloaded, unloadReason = unloadBehind()
    if not unloaded then
        turnAround()
        return false, unloadReason
    end
    local fueled, fuelReason = refuelFromUpperChest(requiredForTrip)
    if not fueled then return false, fuelReason end
    turtle.select(config.torchEnabled and 3 or 2)
    if config.experimentalInventory and inventoryManager then
        local refreshed, inventoryReason = inventoryManager.refresh(
            config, "indulas_ladaktol", true
        )
        if not refreshed then return false, inventoryReason end
    end
    print("Inventory kiuritve, tankolas kesz.")
    return true
end

local function tripFuelRequirement(targetX, targetZ)
    local distance = math.abs(targetX) + math.abs(targetZ)
    local nextWorkCost = 2
    if config.tunnelMode == 3 then nextWorkCost = 6 end
    local verticalRoundTrip = config.tunnelMode == 3 and 2 or 0
    return (2 * distance) + verticalRoundTrip + config.fuelReserve + nextWorkCost
end

serviceAndResume = function(reasonText)
    local savedX, savedY, savedZ = position.x, position.y, position.z
    local savedHeading = heading
    local savedActivity = runtime.activity
    clearScreen()
    print("Megszakitas: " .. reasonText)
    if not returnHome() then return false, "Nem sikerult hazaterni." end
    local fueled, serviceReason = serviceHome(tripFuelRequirement(savedX, savedZ))
    if not fueled then return false, serviceReason end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    print(string.format("Visszateres a munkapontra: x=%d z=%d", savedX, savedZ))
    setActivity("vissza_munkapontra")
    local levelOk, levelReason = moveVerticalTo(savedY)
    if not levelOk then return false, levelReason end
    local resumed, resumeReason = navigateTo(savedX, savedZ, savedHeading)
    if not resumed then return false, resumeReason end
    setActivity(savedActivity)
    status("Munka folytatasa")
    return true
end

local function placeTorchNow()
    if inventoryFull() then
        local resumed, reason = serviceAndResume("Az inventory megtelt.")
        if not resumed then return false, reason end
    end

    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end

    local placed, placeReason
    if config.torchPlacementMode == 2 then
        placed, placeReason = torchManager.placeAbove(
            function() return heading end,
            face
        )
    else
        placed, placeReason = torchManager.placeInDirection(
            (heading + 1) % 4,
            function() return heading end,
            face,
            managedDig
        )
    end
    if not placed then return false, placeReason end

    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end
    return true
end

local function mineForward(steps, label, carveCrossSection)
    if carveCrossSection == nil then carveCrossSection = true end
    local step = 1
    while step <= steps do
        if stopRequested and not returningHome then
            return false, "Felhasznaloi leallitas."
        end
        if not returningHome and inventoryFull() then
            local resumed, reason = serviceAndResume("Az inventory megtelt.")
            if not resumed then return false, reason end
        end

        if carveCrossSection and config.tunnelMode == 3 and not returningHome then
            local requiredForSlice = distanceHome() + config.fuelReserve + 6
            if not refuelFromInventory(requiredForSlice) then
                local resumed, reason = serviceAndResume(
                    "Keves az uzemanyag a kovetkezo 3x3-as szelethez."
                )
                if not resumed then return false, reason end
            end
        end
        local dug, digReason = digForwardUntilClear()
        if not dug then return false, digReason end

        local moved, moveCode, moveReason = forward()
        if not moved and moveCode == "fuel" and not returningHome then
            local resumed, reason = serviceAndResume("Keves az uzemanyag. " .. moveReason)
            if not resumed then return false, reason end
        elseif not moved then
            return false, moveReason
        else
            if carveCrossSection then
                local cleared, clearReason = clearTunnelCrossSection()
                if not cleared then return false, clearReason end
            end
            if step == 1 or step % 8 == 0 or step == steps then
                status(label .. " " .. step .. "/" .. steps)
            end
            step = step + 1
        end
    end
    return true
end

local function mineBranch(turnFunction, sideName)
    turnFunction()
    local completed, reason = mineForward(
        config.branchLength,
        sideName .. " agat",
        true
    )
    if not completed then return false, reason end
    turnAround()
    local previousReturningState = returningHome
    returningHome = true

    local function placePlannedTorch(branchStep)
        if not config.torchEnabled
            or branchStep <= 0
            or branchStep % config.branchTorchInterval ~= 0 then
            return true
        end
        -- Az ag mar teljesen kesz. A lerakashoz ideiglenesen munkaallapotot
        -- hasznalunk, hogy ures slot eseten haza tudjon menni faklyaert.
        returningHome = false
        local placed, placeReason = placeTorchNow()
        returningHome = true
        return placed, placeReason
    end

    local torchOk, torchReason = placePlannedTorch(config.branchLength)
    if not torchOk then
        returningHome = previousReturningState
        return false, torchReason
    end

    local returned, returnReason = true, nil
    for returnStep = 1, config.branchLength do
        returned, returnReason = mineForward(1, sideName .. " vissza", false)
        if not returned then break end
        local outboundStep = config.branchLength - returnStep
        torchOk, torchReason = placePlannedTorch(outboundStep)
        if not torchOk then
            returned, returnReason = false, torchReason
            break
        end
    end
    returningHome = previousReturningState
    if not returned then return false, returnReason end
    if sideName == "Bal" then turnLeft() else turnRight() end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    return true
end

local function travelToStartOffset()
    if config.startOffset == 0 then return true end
    print("Elorehaladas a folytatasi pontig...")
    local step = 1
    while step <= config.startOffset do
        if stopRequested then return false, "Felhasznaloi leallitas." end
        local moved, moveCode, reason = forward()
        if not moved and moveCode == "fuel" then
            local resumed, serviceReason = serviceAndResume("Keves az uzemanyag az odauton.")
            if not resumed then return false, serviceReason end
        elseif not moved then
            return false, reason
        else
            if step == 1 or step % 16 == 0 or step == config.startOffset then
                status("Odaut " .. step .. "/" .. config.startOffset)
            end
            step = step + 1
        end
    end
    return true
end

local function minePendingBranches(absoluteStep)
    if stopRequested then return false, "Felhasznaloi leallitas." end
    if config.tunnelMode == 3 then return true end
    if absoluteStep <= 0 or absoluteStep % config.branchSpacing ~= 0 then
        return true
    end
    if runtime.branchesCompletedAt >= absoluteStep then return true end

    setActivity("bal_oldalagat")
    local leftOk, leftReason = mineBranch(turnLeft, "Bal")
    if not leftOk then return false, leftReason end

    setActivity("jobb_oldalagat")
    local rightOk, rightReason = mineBranch(turnRight, "Jobb")
    if not rightOk then return false, rightReason end

    runtime.branchesCompletedAt = absoluteStep
    setActivity("agak_keszen")
    return true
end

local function plannedMainTorchPoints(completed)
    local points = {}
    if not config.torchEnabled then return points end

    local sinceLast = 0
    for localStep = 1, completed do
        sinceLast = sinceLast + 1
        local absoluteStep = config.startOffset + localStep
        local branchPoint = config.tunnelMode ~= 3
            and absoluteStep % config.branchSpacing == 0
        local stableWall = config.torchPlacementMode ~= 2 or not branchPoint
        if sinceLast >= config.mainTorchInterval and stableWall then
            points[localStep] = true
            sinceLast = 0
        end
    end
    return points
end

local function returnHomeWithMainTorches()
    local workY = config.tunnelMode == 3 and 1 or 0
    local expectedZ = config.startOffset + runtime.mainCompleted
    if not config.torchEnabled
        or position.x ~= 0
        or position.y ~= workY
        or position.z ~= expectedZ then
        return returnHome()
    end

    local points = plannedMainTorchPoints(runtime.mainCompleted)
    returningHome = true
    setActivity("fotengely_faklyazas_hazafele")
    face(2)

    for localStep = runtime.mainCompleted, 1, -1 do
        if points[localStep] then
            -- Az egesz foutvonal es minden eddigi oldalagat kesz. Ha faklyaert
            -- kell hazamenni, a kiszolgalas utan ugyanide navigal vissza.
            returningHome = false
            local placed, placeReason = placeTorchNow()
            returningHome = true
            if not placed then
                returningHome = false
                return false, placeReason
            end
        end

        local moved, _, moveReason = forward()
        if not moved then
            returningHome = false
            return false, moveReason
        end
    end

    local ok, reason = moveAxis(0, "z", 0, 2)
    if ok then ok, reason = moveVerticalTo(0) end
    if ok then face(0) end
    returningHome = false
    if ok then status("Hazaertem") end
    return ok, reason
end

local function returnAndService()
    if returnHome() then
        local serviced, reason = serviceHome(config.fuelReserve)
        if not serviced then printError("Otthoni hiba: " .. (reason or "ismeretlen")) end
    end
end

local function runMining()
    persistenceEnabled = true
    if config.experimentalInventory and inventoryManager then
        local initialized, inventoryReason = inventoryManager.initialize(config)
        if not initialized then
            printError("Inventory modul hiba: " .. tostring(inventoryReason))
            return
        end
    end
    if actionLogger then
        local modeNames = { "Branch 1x2", "Branch 1x3", "Egyenes 3x3" }
        local startType = config.autoResume and "auto folytatas"
            or (config.startMode == 2 and "kezi folytatas" or "uj munka")
        actionLogger.log(modeNames[config.tunnelMode] .. " - " .. startType)
    end
    print("Branch miner indul.")
    local checkpoint

    if config.autoResume then
        runtime.active = true
        setActivity("auto_ujrainditas")
        if not returnHome() then return end
        checkpoint = config.startOffset + runtime.mainCompleted
        local serviced, serviceReason = serviceHome(tripFuelRequirement(0, checkpoint))
        if not serviced then
            printError("Kiszolgalasi hiba: " .. serviceReason)
            return
        end
        local workY = config.tunnelMode == 3 and 1 or 0
        local levelOk, levelReason = moveVerticalTo(workY)
        if not levelOk then
            printError("Nem ertem el a munkaszintet: " .. levelReason)
            return
        end
        setActivity("vissza_ellenorzopontra")
        local reached, reachReason = navigateTo(0, checkpoint, 0)
        if not reached then
            printError("Nem ertem el a mentett pontot: " .. (reachReason or "hiba"))
            returnAndService()
            return
        end
        local branchesOk, branchesReason = minePendingBranches(checkpoint)
        if not branchesOk then
            printError("Ag-folytatasi hiba: " .. (branchesReason or "hiba"))
            returnAndService()
            return
        end
    else
        runtime.active = true
        runtime.activity = "indulas"
        runtime.mainCompleted = 0
        runtime.branchesCompletedAt = 0
        saveState()

        local serviced, serviceReason = serviceHome(tripFuelRequirement(0, config.startOffset))
        if not serviced then
            printError("Nem tudok elindulni: " .. serviceReason)
            return
        end
        local workY = config.tunnelMode == 3 and 1 or 0
        local levelOk, levelReason = moveVerticalTo(workY)
        if not levelOk then
            printError("Nem ertem el a munkaszintet: " .. levelReason)
            return
        end
        setActivity("kezdo_uthaladas")
        local reached, reachReason = travelToStartOffset()
        if not reached then
            printError("Nem ertem el a kezdo pontot: " .. (reachReason or "hiba"))
            returnAndService()
            return
        end
    end

    local stopReason = nil
    for localStep = runtime.mainCompleted + 1, config.mainLength do
        if stopRequested then stopReason = "Felhasznaloi leallitas." break end
        local absoluteStep = config.startOffset + localStep
        setActivity("fotengely")
        local moved, reason = mineForward(
            1,
            "Fotengely " .. localStep .. "/" .. config.mainLength,
            true
        )
        if not moved then stopReason = reason break end
        runtime.mainCompleted = localStep
        saveState()

        local branchesOk, branchesReason = minePendingBranches(absoluteStep)
        if not branchesOk then stopReason = branchesReason break end
    end

    if stopReason then printError("A banyaszat leallt: " .. stopReason)
    else print("A beallitott banyaszati szakasz elkeszult.") end

    if returnHomeWithMainTorches() then
        local finalOk, finalReason = serviceHome(config.fuelReserve)
        if finalOk then
            if not stopReason then
                runtime.active = false
                setActivity("kesz")
            end
            print("Kesz: a turtle otthon van, az inventory ures.")
        else printError("Hazaertem, de a lada-kiszolgalas sikertelen: " .. finalReason) end
    end
end

local function miningTask()
    local ok, errorMessage = pcall(runMining)
    if not ok then
        printError("Programhiba: " .. tostring(errorMessage))
        if distanceHome() > 0 then returnAndService() end
    end
    miningFinished = true
    os.queueEvent("miner_finished")
end

local function stopListener()
    print("Q/Ctrl+T: leallitas | S: allapot")
    while not miningFinished do
        local event, key = os.pullEventRaw()
        if event == "miner_finished" then return end
        if event == "terminate" or (event == "key" and key == keys.q) then
            if not stopRequested then
                stopRequested = true
                print("Leallitas kerese fogadva.")
                print("Biztonsagos hazateres indul...")
            end
        elseif event == "key" and key == keys.s then
            status("Allapot")
        end
    end
end

local configured, configureError = pcall(configure)
if not configured then
    printError("Beallitasi hiba: " .. tostring(configureError))
elseif config.launchExperimental then
    clearScreen()
    print("Terulet asas inditasa...")
    if not fs.exists("excavator") and not fs.exists("excavator.lua") then
        printError("Hianyzik az excavator program.")
    else
        shell.run("excavator")
    end
else
    parallel.waitForAll(miningTask, stopListener)
end
