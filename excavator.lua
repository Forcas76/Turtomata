-- KISERLETI CC:Tweaked teglatest-kitorelo program.
-- A turtle a terulet bal also elso sarka elott, a melyseg iranyaba nezzen.

local config = {}
local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false
local visited = 0

local headings = {
    [0] = { x = 0, z = 1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 },
    [3] = { x = -1, z = 0 },
}

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function banner()
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    print("!!  KISERLETI FUNKCIO!    !!")
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
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

local function configure()
    clearScreen()
    banner()
    print("")
    print("Terulet a turtle nezopontjabol:")
    print("szelesseg = jobbra")
    print("melyseg   = elore")
    print("magassag  = felfele")
    print("")
    config.width = promptInteger("Szelesseg", 8, 1)
    config.depth = promptInteger("Melyseg", 16, 1)
    config.height = promptInteger("Magassag", 4, 1)
    config.fuelReserve = promptInteger("Fuel tartalek", 5, 2)

    clearScreen()
    banner()
    print("")
    print("Meret: " .. config.width .. "x" .. config.depth .. "x" .. config.height)
    print("Blokkok: " .. (config.width * config.depth * config.height))
    print("Fuel+: " .. config.fuelReserve)
    print("")
    print("Start: bal-also-elso sarok elott")
    print("Lada: hatul, fuel: folotte")
    print("")
    write("ENTER = KISERLETI inditas")
    read()
    clearScreen()
    banner()
end

local function fuelLevel()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return math.huge end
    return level
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
    for slot = 2, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
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
        if turtle.getItemCount(slot) > 0 and not keepFuel then
            turtle.drop()
            if turtle.getItemCount(slot) > 0 then allDeposited = false end
        end
    end
    if not allDeposited then
        turnAround()
        turtle.select(2)
        return false, "A leado lada megtelt."
    end
    return true
end

local function fuelFromUpperChest(requiredAfterService)
    if fuelLevel() ~= math.huge and not refuelSlotOne(2) then
        turnAround()
        return false, "Legalabb 2 kezdo fuel kell."
    end
    if not turtle.up() then
        turnAround()
        return false, "A turtle feletti hely nem szabad."
    end
    position.y = position.y + 1
    local requiredAtTop = requiredAfterService + 1
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        else
            turtle.down()
            position.y = position.y - 1
            turnAround()
            return false, "Az 1-es slot nem egetheto."
        end
    end
    while fuelLevel() < requiredAtTop do
        if not turtle.suck(64) then
            turtle.down()
            position.y = position.y - 1
            turnAround()
            return false, "Az uzemanyaglada ures."
        end
        if not turtle.refuel(0) then
            turtle.drop()
            turtle.down()
            position.y = position.y - 1
            turnAround()
            return false, "Nem egetheto targy van a fuel ladaban."
        end
        turtle.refuel()
    end
    if not turtle.down() then return false, "Nem tudok leereszkedni." end
    position.y = position.y - 1
    turnAround()
    turtle.select(2)
    return true
end

local function serviceHome(requiredForTrip)
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "Nem vagyok a kezdohelyen."
    end
    refuelSlotOne(math.max(2, requiredForTrip))
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
    clearScreen()
    banner()
    print("Megszakitas: " .. reasonText)
    local homeOk, homeReason = returnHome()
    if not homeOk then return false, homeReason end
    local serviced, serviceReason = serviceHome(tripRequirement(savedX, savedY, savedZ))
    if not serviced then return false, serviceReason end
    print("Vissza a munkapontra...")
    return navigateFromHome(savedX, savedY, savedZ, savedHeading)
end

local function moveToTarget(targetX, targetY, targetZ)
    while position.x ~= targetX or position.y ~= targetY or position.z ~= targetZ do
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

    visited = visited + 1

    if clearAbove then
        if inventoryFull() then
            local resumed, resumeReason = serviceAndResume("Inventory tele.")
            if not resumed then return false, resumeReason end
        end
        local cleared, clearReason = clearUpperCell()
        if not cleared then return false, clearReason end
        visited = visited + 1
    end

    if visited <= 2 or visited % 16 == 0 or visited == total then
        print(string.format("Haladas: %d/%d | %d,%d,%d", visited, total,
            position.x, position.y, position.z))
    end
    return true
end

local function excavate()
    configure()
    local total = config.width * config.depth * config.height
    local serviced, serviceReason = serviceHome(config.fuelReserve + 4)
    if not serviced then
        printError("Inditasi hiba: " .. serviceReason)
        return
    end

    local currentX = 0
    local stopReason = nil
    local layerPass = 0
    for y = 0, config.height - 1, 2 do
        local clearAbove = y + 1 < config.height
        local forwardDepth = layerPass % 2 == 0
        local zStart = forwardDepth and 1 or config.depth
        local zEnd = forwardDepth and config.depth or 1
        local zStep = forwardDepth and 1 or -1
        local xDirection = currentX == 0 and 1 or -1
        local z = zStart

        while true do
            local rowOk, rowReason = visit(currentX, y, z, total, clearAbove)
            if not rowOk then stopReason = rowReason break end

            for _ = 2, config.width do
                currentX = currentX + xDirection
                local cellOk, cellReason = visit(currentX, y, z, total, clearAbove)
                if not cellOk then stopReason = cellReason break end
            end
            if stopReason or z == zEnd then break end
            xDirection = -xDirection
            z = z + zStep
        end
        if stopReason then break end
        layerPass = layerPass + 1
    end

    if stopReason then printError("Kitores leallt: " .. (stopReason or "hiba"))
    else print("A teljes terulet ki lett asva.") end

    if returnHome() then
        local finalOk, finalReason = serviceHome(config.fuelReserve)
        if finalOk then print("Kesz: otthon, inventory uritve.")
        else printError("Otthoni hiba: " .. finalReason) end
    end
end

local ok, errorMessage = pcall(excavate)
if not ok then
    printError("KISERLETI programhiba: " .. tostring(errorMessage))
    if distanceHome() > 0 then returnHome() end
end
