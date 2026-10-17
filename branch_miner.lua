-- CC:Tweaked branch mining turtle
-- Interaktiv menurendszerrel, automatikus uritessel es tankolassal.

local programArgs = { ... }
local jobRequest = require("job_request")
local stateStore = require("state_store")
local Navigation = require("navigation")
local UI = require("ui")
local Telemetry = require("telemetry")
local Situations = require("situation_manager")
local WorkEstimator = require("work_estimator")
local centralRequest, centralRequestError = jobRequest.consume("branch_miner", programArgs)

local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false
local torchModuleOk, torchManager = pcall(require, "torch_manager")
if not torchModuleOk then torchManager = nil end
local actionLogOk, actionLogger = pcall(require, "action_log")
if not actionLogOk then actionLogger = nil end
local inventoryModuleOk, inventoryManager = pcall(require, "inventory_manager")
if not inventoryModuleOk then inventoryManager = nil end
local oreModuleOk, oreScanner = pcall(require, "ore_scanner")
if not oreModuleOk then oreScanner = nil end

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
    oreScan = nil,
    oreAheadVisited = nil,
}
local sharedNav = nil
local navigationState = nil
local sharedTelemetry = nil
local telemetryState = nil
local sharedSituations = nil
local activeBranchContext = nil

local function saveState()
    if not persistenceEnabled then return end
    if sharedNav then
        sharedNav.state.pose.x = position.x
        sharedNav.state.pose.y = position.y
        sharedNav.state.pose.z = position.z
        sharedNav.state.pose.heading = heading
    end
    local payload = {
        version = 1,
        active = runtime.active,
        activity = runtime.activity,
        mainCompleted = runtime.mainCompleted,
        branchesCompletedAt = runtime.branchesCompletedAt,
        oreScan = runtime.oreScan,
        oreAheadVisited = runtime.oreAheadVisited,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        navigation = sharedNav and sharedNav:snapshot() or navigationState,
        telemetry = sharedTelemetry and sharedTelemetry:snapshot() or telemetryState,
        config = config,
    }
    local ok, reason = stateStore.write(STATE_FILE, payload)
    if not ok then error(reason or "Nem irhato az allapotfajl.", 0) end
end

local function setActivity(activity)
    runtime.activity = activity
    saveState()
end

local function loadState()
    local saved = stateStore.read(STATE_FILE)
    if type(saved) ~= "table" or saved.version ~= 1 then return nil end
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
    if centralRequestError then error(centralRequestError, 0) end
    if centralRequest then
        if centralRequest.action == "resume" then
            if not saved then error("Nincs hasznalhato branch mining mentes.", 0) end
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
            runtime.oreScan = saved.oreScan
            runtime.oreAheadVisited = saved.oreAheadVisited
            navigationState = saved.navigation
            telemetryState = saved.telemetry
        else
            config = centralRequest.config or {}
            config.autoResume = false
        end
        config.startMode = config.startMode or 1
        config.startOffset = config.startOffset or 0
        config.fuelReserve = config.fuelReserve or 5
        config.experimentalInventory = config.experimentalInventory == true
        config.torchEnabled = config.torchEnabled == true
        config.mainTorchInterval = config.mainTorchInterval or 0
        config.branchTorchInterval = config.branchTorchInterval or 0
        config.torchPlacementMode = config.torchPlacementMode or 1
        config.oreScanEnabled = config.oreScanEnabled == true
        config.oreScanMaxDepth = config.oreScanMaxDepth or 4
        config.oreScanMaxBlocks = config.oreScanMaxBlocks or 16
        if not config.tunnelMode or not config.mainLength then error("Hianyos branch konfiguracio.", 0) end
        if config.experimentalInventory and not inventoryManager then error("Hianyzik az inventory_manager.lua modul.", 0) end
        if config.torchEnabled and not torchManager then error("Hianyzik a torch_manager.lua modul.", 0) end
        if config.oreScanEnabled and not oreScanner then error("Hianyzik az ore_scanner.lua modul.", 0) end
        clearScreen()
        return
    end
    clearScreen()
    print("=== BRANCH MINER ===\n")

    local taskMode = promptChoice("Feladat:", {
        "Branch 1x2",
        "Branch 1x3",
        "Egyenes 3x3",
        "Terulet asas",
        "Nether utak",
        saved and "Auto folytatas" or "Auto (nincs mentes)",
    }, saved and 6 or 1)

    clearScreen()

    if taskMode == 4 then
        config.launchExperimental = true
        return
    elseif taskMode == 5 then
        config.launchNetherBuilder = true
        return
    elseif taskMode == 6 then
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
        runtime.oreScan = saved.oreScan
        runtime.oreAheadVisited = saved.oreAheadVisited
        navigationState = saved.navigation
        telemetryState = saved.telemetry
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

        if config.tunnelMode ~= 3 then
            print("")
            config.oreScanEnabled = promptChoice("KISERLETI erckereses:", {
                "Kikapcsolva",
                "Bekapcsolva",
            }, 1) == 2
            if config.oreScanEnabled then
                if not oreScanner then error("Hianyzik az ore_scanner.lua modul.", 0) end
                local edited, editReason = oreScanner.editTargets()
                if not edited then error(editReason or "Az erclista nem mentheto.", 0) end
                clearScreen()
                print("KISERLETI erckereses")
                config.oreScanMaxDepth = promptInteger("Max melyseg", 4, 1)
                config.oreScanMaxBlocks = promptInteger("Max erc/telep", 16, 1)
            end
        else
            config.oreScanEnabled = false
        end
    end

    config.experimentalInventory = config.experimentalInventory == true
    if config.experimentalInventory and not inventoryManager then
        error("Hianyzik az inventory_manager.lua modul.", 0)
    end
    if config.torchEnabled and not torchManager then
        error("Hianyzik a torch_manager.lua modul.", 0)
    end
    config.oreScanEnabled = config.oreScanEnabled == true
    config.oreScanMaxDepth = config.oreScanMaxDepth or 4
    config.oreScanMaxBlocks = config.oreScanMaxBlocks or 16
    if config.oreScanEnabled and not oreScanner then
        error("Hianyzik az ore_scanner.lua modul.", 0)
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
    if config.oreScanEnabled then
        print("Erckereses: KISERLETI (" .. oreScanner.selectedCount() .. " blokk)")
        print("Erc limit: " .. config.oreScanMaxDepth .. " mely / "
            .. config.oreScanMaxBlocks .. " blokk")
    else
        print("Erckereses: ki")
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
        -- Kiserleti modban csak a mar detektalt blokk helyigenye dont.
        return false
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
    local estimate = WorkEstimator.branch(config, {
        mainCompleted = runtime.mainCompleted,
        homeDistance = distanceHome(),
    })
    local remainingMs = sharedTelemetry and sharedTelemetry:estimateMs(estimate.plan)
        or WorkEstimator.durationMs(estimate, config.defaultActionSeconds or 0.8)
    local events = {}
    if config.experimentalInventory and inventoryManager then
        local inventoryStatus = inventoryManager.status(config)
        events[#events + 1] = string.format("KIS-INV %d/%d, ures %d",
            inventoryStatus.used, inventoryStatus.total, inventoryStatus.empty)
    end
    if runtime.oreScan and runtime.oreScan.active then
        events[#events + 1] = string.format("ERC %s %s ag=%d mely=%d db=%d",
            runtime.oreScan.phase or "vizsgalat",
            runtime.oreScan.side or "?",
            runtime.oreScan.branchStep or 0,
            runtime.oreScan.scanLevel or 0,
            runtime.oreScan.veinMined or 0)
    end
    if sharedSituations then
        for _, warning in ipairs(sharedSituations:lastWarnings(2)) do events[#events + 1] = warning end
    end
    UI.renderDashboard({
        task = ({ "Branch 1x2", "Branch 1x3", "Egyenes 3x3" })[config.tunnelMode] or "Branch mining",
        status = prefix .. " / " .. tostring(runtime.activity),
        progress = string.format("%d/%d", runtime.mainCompleted, config.mainLength or 0),
        position = string.format("%d,%d,%d  irany=%d", position.x, position.y, position.z, heading),
        fuel = fuelText(fuelLevel()) .. "  haza=" .. distanceHome(),
        inventory = string.format("%d/16 (%d%%)", usedSlots, usedPercent),
        supplies = config.torchEnabled and ("faklya=" .. turtle.getItemCount(2)) or "faklya=ki",
        elapsed = sharedTelemetry and Telemetry.formatDuration(sharedTelemetry:elapsedMs()) or "00:00:00",
        remaining = string.format("%d muv. / kb. %s", estimate.totalActions,
            Telemetry.formatDuration(remainingMs)),
        events = events,
    })
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
    local turned = assert(sharedNav, "A navigacios modul nincs inicializalva."):turnLeft()
    if not turned.ok then error(turned.reason, 0) end
end

local function turnRight()
    local turned = assert(sharedNav, "A navigacios modul nincs inicializalva."):turnRight()
    if not turned.ok then error(turned.reason, 0) end
end

local function turnAround()
    turnRight()
    turnRight()
end

local function face(targetHeading)
    if sharedNav then
        local turned = sharedNav:face(targetHeading)
        if not turned.ok then error(turned.reason, 0) end
        return
    end
    local difference = (targetHeading - heading) % 4
    if difference == 1 then turnRight()
    elseif difference == 2 then turnAround()
    elseif difference == 3 then turnLeft() end
end

local serviceAndResume
local buildOreApi

local function selectSealBlock()
    local target = config.safety and config.safety.sealBlock or "minecraft:cobblestone"
    local firstMiningSlot = config.torchEnabled and 3 or 2
    for slot = firstMiningSlot, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == target and turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            return true
        end
    end
    return false, "Nincs " .. target .. " tomitoblokk az inventory-ban."
end

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
    if direction == "forward" and config.oreScanEnabled and activeBranchContext
        and oreScanner and oreScanner.matches(blockData) then
        setActivity("ag_elore_erc")
        local mined, reason, minedCount, minedPositions = oreScanner.mineAhead(
            activeBranchContext.side,
            activeBranchContext.step,
            buildOreApi(),
            blockData
        )
        if not mined then return false, reason or "Az elottem talalt ercteler elakadt." end
        runtime.oreAheadVisited = runtime.oreAheadVisited or {
            at = activeBranchContext.absoluteStep,
            left = {}, right = {},
        }
        local sideVisited = runtime.oreAheadVisited[activeBranchContext.side]
        for positionKey in pairs(minedPositions or {}) do
            sideVisited[positionKey] = true
        end
        -- Regi/ures eredmenynel is maradjon egy lepesszintu tartalekjeloles.
        if not next(minedPositions or {}) then
            sideVisited[tostring(activeBranchContext.step)] = minedCount or true
        end
        setActivity(activeBranchContext.side == "left" and "bal_oldalagat" or "jobb_oldalagat")
        saveState()
        return true
    end
    if sharedSituations and sharedSituations:fluidKind(direction) then
        local cleared = sharedSituations:clearFluidSource(direction, selectSealBlock, function()
            return sharedTelemetry and sharedTelemetry:measure("dig", dig) or dig()
        end)
        if cleared.kind == "handled" then return true end
        return false, cleared.reason or "A folyadek nem zarhato le."
    end
    if not config.experimentalInventory or not inventoryManager or returningHome then
        local dug = sharedTelemetry and sharedTelemetry:measure("dig", dig) or dig()
        if dug then return true end
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
            local dug = sharedTelemetry and sharedTelemetry:measure("dig", dig) or dig()
            if not dug then return false, "A blokk nem ashato." end
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

    local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
        { kind = "h", heading = heading }, {
        onBlocked = function(_, moveResult)
            local dug, reason = digForwardUntilClear()
            if dug then
                if turtle.attack() then sleep(0.2) end
                return { action = "retry" }
            end
            return { result = {
                ok = false,
                code = "blocked",
                reason = reason or moveResult.reason,
            } }
        end,
    })
    if not moved.ok then return false, moved.code, moved.reason end
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
        local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
            { kind = "d" }, {
                onBlocked = function(_, moveResult)
                    if turtle.detectDown() then
                        local dug, reason = managedDig("down")
                        if dug then return { action = "retry" } end
                        return { result = { ok = false, code = "blocked", reason = reason } }
                    end
                    if turtle.attackDown() then return { action = "retry" } end
                    return { result = moveResult }
                end,
            })
        if not moved.ok then return false, moved.reason end
    end
    while position.y < targetY do
        if not refuelFromInventory(1) then return false, "Nincs fuel a felemelkedeshez." end
        local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
            { kind = "u" }, {
                onBlocked = function(_, moveResult)
                    if turtle.detectUp() then
                        local dug, reason = managedDig("up")
                        if dug then return { action = "retry" } end
                        return { result = { ok = false, code = "blocked", reason = reason } }
                    end
                    if turtle.attackUp() then return { action = "retry" } end
                    return { result = moveResult }
                end,
            })
        if not moved.ok then return false, moved.reason end
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
    local serviceMove = sharedNav:step({ kind = "u" })
    if not serviceMove.ok then
        return false, "Nem tudok felmenni az uzemanyagladahoz. Szabad a hely folottem?"
    end

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
        serviceMove = sharedNav:step({ kind = "u" })
        if not serviceMove.ok then
            reason = "Nem tudok felmenni a faklyas ladahoz."
        else
            local torchOk, torchReason = torchManager.refillFromChest()
            if not torchOk then reason = torchReason end
            serviceMove = sharedNav:step({ kind = "d" })
            if not serviceMove.ok then
                return false, "Nem tudok lejonni a faklyas ladatol."
            end
        end
    end

    if fuelLevel() < 1 then
        printError("Nincs fuel a leereszkedeshez; a turtle a felso szinten maradt.")
        return false, reason or "Elfogyott az uzemanyag."
    end
    serviceMove = sharedNav:step({ kind = "d" })
    if not serviceMove.ok then return false, "Nem tudok visszaereszkedni a kezdohelyre." end
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

serviceAndResume = function(reasonText, extraFuel)
    local savedX, savedY, savedZ = position.x, position.y, position.z
    local savedHeading = heading
    local savedActivity = runtime.activity
    clearScreen()
    print("Megszakitas: " .. reasonText)
    if not returnHome() then return false, "Nem sikerult hazaterni." end
    local fueled, serviceReason = serviceHome(
        tripFuelRequirement(savedX, savedZ) + (extraFuel or 0)
    )
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

    local originalHeading = heading
    local function side(target)
        return function()
            return torchManager.placeInDirection(target, function() return heading end, face, managedDig)
        end
    end
    local function above()
        return torchManager.placeAbove(function() return heading end, face)
    end
    local outcome = sharedSituations:placeTorchWithFallback({
        preferred = config.torchPlacementMode == 2 and above or side((originalHeading + 1) % 4),
        otherSide = side((originalHeading + 3) % 4),
        above = config.torchPlacementMode == 2 and nil or above,
    })
    if outcome.kind == "fatal" then return false, outcome.reason end

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

local function oreMoveOpen(move)
    if not refuelFromInventory(1) then
        return false, "Nincs fuel az erc-utvonal mozgasahoz."
    end
    local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(move)
    if not moved.ok then return false, moved.reason end
    return true
end

local function oreInspectAndDig(move)
    local inspect, dig
    if move.kind == "u" then
        inspect, dig = turtle.inspectUp, turtle.digUp
    elseif move.kind == "d" then
        inspect, dig = turtle.inspectDown, turtle.digDown
    else
        face(move.heading)
        inspect, dig = turtle.inspect, turtle.dig
    end

    local hasBlock, blockData = inspect()
    if not hasBlock or not oreScanner.matches(blockData) then
        return false, "changed", "A kijelolt erc mar nincs a helyen."
    end
    if not config.experimentalInventory or not inventoryManager then
        if inventoryFull() then
            return false, "service", "Az inventory megtelt az erc elott."
        end
        if not dig() then return false, "blocked", "A kijelolt erc nem banyaszhato." end
        return true
    end

    local ready, beforeOrReason = inventoryManager.prepareForDig(config, blockData)
    if not ready then
        return false, "service", "KISERLETI inventory: " .. tostring(beforeOrReason)
    end
    if not dig() then return false, "blocked", "A kijelolt erc nem banyaszhato." end
    local recorded, recordReason = inventoryManager.afterDig(
        config, blockData, beforeOrReason
    )
    if not recorded then return false, "blocked", recordReason end
    return true
end

buildOreApi = function()
    return {
        maxDepth = config.oreScanMaxDepth,
        maxBlocks = config.oreScanMaxBlocks,
        fuelReserve = config.fuelReserve,
        getPose = function()
            return { x = position.x, y = position.y, z = position.z, heading = heading }
        end,
        face = face,
        moveOpen = oreMoveOpen,
        digOre = oreInspectAndDig,
        ensureFuel = refuelFromInventory,
        shouldStop = function() return stopRequested end,
        checkpoint = function(oreState)
            runtime.oreScan = oreState
            saveState()
            if oreState then status("Erckereses") end
        end,
        placeBranchTorch = function(side, branchStep)
            if not config.torchEnabled or branchStep <= 0
                or branchStep % config.branchTorchInterval ~= 0 then
                return true
            end
            runtime.oreAheadVisited.torches = runtime.oreAheadVisited.torches
                or { left = {}, right = {} }
            local placedBySide = runtime.oreAheadVisited.torches[side]
            if placedBySide[branchStep] then return true end
            local previousReturning = returningHome
            returningHome = false
            local placed, reason = placeTorchNow()
            returningHome = previousReturning
            if placed then
                placedBySide[branchStep] = true
                saveState()
            end
            return placed, reason
        end,
        service = function(reason, extraFuel)
            return serviceAndResume(reason, extraFuel)
        end,
    }
end

local function mineBranch(turnFunction, sideName, placeTorches, carveCrossSection)
    if placeTorches == nil then placeTorches = true end
    if carveCrossSection == nil then carveCrossSection = true end
    turnFunction()
    local sideKey = sideName == "Bal" and "left" or "right"
    local completed, reason = true, nil
    for branchStep = 1, config.branchLength do
        if carveCrossSection and config.oreScanEnabled then
            activeBranchContext = {
                side = sideKey,
                step = branchStep,
                absoluteStep = config.startOffset + runtime.mainCompleted,
            }
        end
        completed, reason = mineForward(1, sideName .. " agat", carveCrossSection)
        activeBranchContext = nil
        if not completed then return false, reason end
    end
    turnAround()
    local previousReturningState = returningHome
    returningHome = true

    local function placePlannedTorch(branchStep)
        if not placeTorches or not config.torchEnabled
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

    local delayTorches = config.oreScanEnabled and config.torchEnabled
    if not runtime.oreAheadVisited or runtime.oreAheadVisited.at ~= absoluteStep then
        runtime.oreAheadVisited = {
            at = absoluteStep, left = {}, right = {},
            torches = { left = {}, right = {} },
        }
        saveState()
    end

    setActivity("bal_oldalagat")
    local leftOk, leftReason = mineBranch(
        turnLeft, "Bal", not delayTorches, true
    )
    if not leftOk then return false, leftReason end

    setActivity("jobb_oldalagat")
    local rightOk, rightReason = mineBranch(
        turnRight, "Jobb", not delayTorches, true
    )
    if not rightOk then return false, rightReason end

    if config.oreScanEnabled then
        local oreApi = buildOreApi()
        setActivity("bal_ag_erckereses")
        local scanned, scanReason = oreScanner.scanBranch(
            "left", config.branchLength, config.tunnelMode, oreApi,
            runtime.oreAheadVisited.left
        )
        if not scanned then return false, scanReason end

        setActivity("jobb_ag_erckereses")
        scanned, scanReason = oreScanner.scanBranch(
            "right", config.branchLength, config.tunnelMode, oreApi,
            runtime.oreAheadVisited.right
        )
        if not scanned then return false, scanReason end
    end

    runtime.branchesCompletedAt = absoluteStep
    runtime.oreAheadVisited = nil
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
    sharedTelemetry = Telemetry.new(telemetryState, { defaultSeconds = config.defaultActionSeconds or 0.8 })
    sharedSituations = Situations.new(config.safety or {}, { telemetry = sharedTelemetry })
    sharedNav = Navigation.new({
        state = navigationState or {
            pose = { x = position.x, y = position.y, z = position.z, heading = heading },
            path = {}, pending = nil, anchors = {},
        },
        ensureFuel = function(required)
            if refuelFromInventory(required) then return true end
            return false, "Nincs fuel a navigacios lepeshez."
        end,
        telemetry = sharedTelemetry,
        retryLimit = config.safety and config.safety.retryLimit,
        checkpoint = function(navState)
            position.x, position.y, position.z = navState.pose.x, navState.pose.y, navState.pose.z
            heading = navState.pose.heading
            navigationState = navState
            saveState()
        end,
    })
    local navRecovered = sharedNav:recoverPending()
    if not navRecovered.ok then
        printError("Navigacios menteshiba: " .. tostring(navRecovered.reason))
        return
    end
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
        local oreText = config.oreScanEnabled and " - erckereses=be" or " - erckereses=ki"
        actionLogger.log(modeNames[config.tunnelMode] .. " - " .. startType .. oreText)
    end
    print("Branch miner indul.")
    local checkpoint

    if config.autoResume then
        runtime.active = true
        setActivity("auto_ujrainditas")
        if runtime.oreScan and runtime.oreScan.active then
            print("Erc-utvonal biztonsagos visszafejtese...")
            local recovered, recoverReason = oreScanner.recover(
                runtime.oreScan, buildOreApi()
            )
            if not recovered then
                printError("Nem tudtam visszafejteni az erc-utvonalat: "
                    .. tostring(recoverReason))
                return
            end
        end
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
        runtime.oreScan = nil
        runtime.oreAheadVisited = nil
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
        if event == "terminate" or (event == "key" and key == keys.q)
            or (event == "ccturtle_remote_command" and key == "return_home") then
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
elseif config.launchNetherBuilder then
    clearScreen()
    print("Nether utepito inditasa...")
    if not fs.exists("nether_builder") and not fs.exists("nether_builder.lua") then
        printError("Hianyzik a nether_builder program.")
    else
        shell.run("nether_builder")
    end
else
    parallel.waitForAll(miningTask, stopListener)
end
