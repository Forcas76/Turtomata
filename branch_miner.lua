-- CC:Tweaked branch mining turtle
-- Interaktiv menurendszerrel, automatikus uritessel es tankolassal.

local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false

local headings = {
    [0] = { x = 0, z = 1, name = "elore (+Z)" },
    [1] = { x = 1, z = 0, name = "jobbra (+X)" },
    [2] = { x = 0, z = -1, name = "hatra (-Z)" },
    [3] = { x = -1, z = 0, name = "balra (-X)" },
}

local config = {}

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
        print("Hibas ertek. Legalabb " .. minimum .. " erteku egesz szam kell.")
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
    clearScreen()
    print("================================")
    print("      BRANCH MINER TURTLE")
    print("================================\n")

    config.startMode = promptChoice("Inditasi mod:", {
        "Uj banyat kezdek a turtle helyetol",
        "Meglevo alagutban eloremegyek, majd onnan folytatom",
    }, 1)

    if config.startMode == 2 then
        config.startOffset = promptInteger("Meglevo alagut hossza (blokk)", 64, 1)
    else
        config.startOffset = 0
    end

    print("")
    config.mainLength = promptInteger("Innen asando uj fotengely hossza", 128, 1)
    config.branchLength = promptInteger("Egy oldalagat hossza", 16, 1)
    config.branchSpacing = promptInteger("Oldalagatok tavolsaga", 4, 1)
    config.fuelReserve = promptInteger("Biztonsagi uzemanyag-tartalek", 5, 2)

    print("")
    config.tunnelMode = promptChoice("Alagutmagassag:", {
        "2 blokk magas: elore + folotte",
        "3 blokk magas: alatta + elore + folotte",
        "3x3-as alagut: 3 blokk szeles es 3 blokk magas",
    }, 1)

    clearScreen()
    print("BEALLITASOK OSSZEFOGLALASA")
    print("---------------------------")
    if config.startMode == 1 then
        print("Indulas: uj banya")
    else
        print("Indulas: " .. config.startOffset .. " blokk elore, majd folytatas")
    end
    print("Uj fotengely: " .. config.mainLength .. " blokk")
    print("Oldalagat: " .. config.branchLength .. " blokk")
    print("Agak kozotti tavolsag: " .. config.branchSpacing .. " blokk")
    local tunnelNames = {
        "2 blokk magas",
        "3 blokk magas",
        "3x3 blokk",
    }
    print("Alagut merete: " .. tunnelNames[config.tunnelMode])
    print("Uzemanyag-tartalek: " .. config.fuelReserve)
    print("")
    print("Ladak a kezdohely mogott:")
    print("- leado lada: kozvetlenul a turtle mogott")
    print("- uzemanyaglada: a leado lada folott")
    print("- a turtle folott maradjon szabad hely")
    print("")
    print("A turtle eleje a banyaszat iranyaba nezzen.")
    write("Nyomj ENTER-t az inditashoz...")
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
    -- Az 1-es slot a tankolashoz van fenntartva.
    for slot = 2, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
end

local function status(prefix)
    local usedSlots, usedPercent = inventoryUsage()
    print(string.format(
        "%s | x=%d z=%d | fuel=%s | haza=%d | inv=%d/16 (%d%%)",
        prefix, position.x, position.z, fuelText(fuelLevel()), distanceHome(),
        usedSlots, usedPercent
    ))
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
end

local function turnRight()
    turtle.turnRight()
    heading = (heading + 1) % 4
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

local function digForwardUntilClear()
    local attempts = 0
    while turtle.detect() do
        if not turtle.dig() then
            return false, "Nem tudom kiasni az elottem levo blokkot."
        end
        sleep(0.15)
        attempts = attempts + 1
        if attempts > 20 then return false, "Tul sok blokk esett az utamba." end
    end
    return true
end

local forward

local function clearVerticalColumn()
    if turtle.detectUp() and not turtle.digUp() then
        return false, "Nem tudom kiasni a felso blokkot."
    end
    if config.tunnelMode >= 2 and turtle.detectDown() and not turtle.digDown() then
        return false, "Nem tudom kiasni az also blokkot."
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
    face(originalHeading)
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

local function returnHome()
    returningHome = true
    status("Hazateres")
    local ok, reason = navigateTo(0, 0, 0)
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
            if not keepForFuel then
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
    if fuelLevel() ~= math.huge and not refuelFromInventory(2) then
        return false, "Legalabb 2 fuel kell a felso uzemanyaglada eleresehez."
    end
    if not turtle.up() then
        return false, "Nem tudok felmenni az uzemanyagladahoz. Szabad a hely folottem?"
    end

    local requiredAtTop = requiredAfterService + 1
    local selected = turtle.getSelectedSlot()
    local refuelOk = fuelLevel() >= requiredAtTop
    local reason = nil
    while not refuelOk do
        turtle.select(1)
        if turtle.getItemCount(1) > 0 then
            if turtle.refuel(0) then
                while turtle.getItemCount(1) > 0 and fuelLevel() < requiredAtTop do
                    turtle.refuel(1)
                end
                if turtle.getItemCount(1) > 0 then turtle.drop() end
                refuelOk = fuelLevel() >= requiredAtTop
            else
                reason = "Az 1-es slotban nem egetheto targy maradt."
                break
            end
        elseif not turtle.suck(64) then
            reason = "Az uzemanyaglada ures, vagy nincs a leado lada folott."
            break
        elseif not turtle.refuel(0) then
            turtle.drop()
            reason = "Az uzemanyagladaban nem egetheto targy van."
            break
        else
            while turtle.getItemCount(1) > 0 and fuelLevel() < requiredAtTop do
                turtle.refuel(1)
            end
            if turtle.getItemCount(1) > 0 then turtle.drop() end
            refuelOk = fuelLevel() >= requiredAtTop
        end
    end
    -- Az 1-es slotban maradt egetheto targyat visszateszi a fuel ladaba.
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then turtle.drop() end
    if selected == 1 then selected = 2 end
    turtle.select(selected)

    if fuelLevel() < 1 then
        printError("Nincs fuel a leereszkedeshez; a turtle a felso szinten maradt.")
        return false, reason or "Elfogyott az uzemanyag."
    end
    if not turtle.down() then return false, "Nem tudok visszaereszkedni a kezdohelyre." end
    turnAround()
    if not refuelOk then return false, reason or "Nem sikerult eleg uzemanyagot felvenni." end
    return true
end

local function serviceHome(requiredForTrip)
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "A lada-kiszolgalas csak a kezdohelyen vegezheto."
    end
    refuelFromInventory(math.max(2, requiredForTrip))
    local unloaded, unloadReason = unloadBehind()
    if not unloaded then
        turnAround()
        return false, unloadReason
    end
    local fueled, fuelReason = refuelFromUpperChest(requiredForTrip)
    if not fueled then return false, fuelReason end
    turtle.select(2)
    print("Inventory kiuritve, tankolas kesz.")
    return true
end

local function tripFuelRequirement(targetX, targetZ)
    local distance = math.abs(targetX) + math.abs(targetZ)
    local nextWorkCost = 2
    if config.tunnelMode == 3 then nextWorkCost = 6 end
    return (2 * distance) + config.fuelReserve + nextWorkCost
end

local function serviceAndResume(reasonText)
    local savedX, savedZ, savedHeading = position.x, position.z, heading
    print("Megszakitas: " .. reasonText)
    if not returnHome() then return false, "Nem sikerult hazaterni." end
    local fueled, serviceReason = serviceHome(tripFuelRequirement(savedX, savedZ))
    if not fueled then return false, serviceReason end
    print(string.format("Visszateres a munkapontra: x=%d z=%d", savedX, savedZ))
    local resumed, resumeReason = navigateTo(savedX, savedZ, savedHeading)
    if not resumed then return false, resumeReason end
    status("Munka folytatasa")
    return true
end

local function mineForward(steps, label, carveCrossSection)
    if carveCrossSection == nil then carveCrossSection = true end
    local step = 1
    while step <= steps do
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
    local completed, reason = mineForward(config.branchLength, sideName .. " agat")
    if not completed then return false, reason end
    turnAround()
    local previousReturningState = returningHome
    returningHome = true
    local returned, returnReason = mineForward(
        config.branchLength, sideName .. " vissza", false
    )
    returningHome = previousReturningState
    if not returned then return false, returnReason end
    if sideName == "Bal" then turnLeft() else turnRight() end
    return true
end

local function travelToStartOffset()
    if config.startOffset == 0 then return true end
    print("Elorehaladas a folytatasi pontig...")
    local step = 1
    while step <= config.startOffset do
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

local function runMining()
    configure()
    print("Branch miner indul.")
    local serviced, serviceReason = serviceHome(tripFuelRequirement(0, config.startOffset))
    if not serviced then
        printError("Nem tudok elindulni: " .. serviceReason)
        return
    end

    local reached, reachReason = travelToStartOffset()
    if not reached then
        printError("Nem ertem el a folytatasi pontot: " .. (reachReason or "ismeretlen hiba"))
        returnHome()
        return
    end

    local stopReason = nil
    for localStep = 1, config.mainLength do
        local absoluteStep = config.startOffset + localStep
        local moved, reason = mineForward(1, "Fotengely " .. localStep .. "/" .. config.mainLength)
        if not moved then stopReason = reason break end

        if absoluteStep % config.branchSpacing == 0 then
            local leftOk, leftReason = mineBranch(turnLeft, "Bal")
            if not leftOk then stopReason = leftReason break end
            local rightOk, rightReason = mineBranch(turnRight, "Jobb")
            if not rightOk then stopReason = rightReason break end
        end
    end

    if stopReason then printError("A banyaszat leallt: " .. stopReason)
    else print("A beallitott banyaszati szakasz elkeszult.") end

    if returnHome() then
        local finalOk, finalReason = serviceHome(config.fuelReserve)
        if finalOk then print("Kesz: a turtle otthon van, az inventory ures.")
        else printError("Hazaertem, de a lada-kiszolgalas sikertelen: " .. finalReason) end
    end
end

local ok, errorMessage = pcall(runMining)
if not ok then
    printError("Programhiba: " .. tostring(errorMessage))
    if distanceHome() > 0 then returnHome() end
end
