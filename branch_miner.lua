-- CC:Tweaked branch mining turtle
-- Interaktiv menurendszerrel, automatikus uritessel es tankolassal.

local programArgs = { ... }
local jobRequest = require("job_request")
local stateStore = require("state_store")
local Navigation = require("navigation")
local BaseDock = require("base_dock")
local UI = require("ui")
local Telemetry = require("telemetry")
local Situations = require("situation_manager")
local WorkEstimator = require("work_estimator")
local SwarmSafety = require("swarm_safety")
local SwarmSession = require("swarm_session")
local PickupLedger = require("pickup_ledger")
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
local serviceRequested = false
local miningFinished = false
local runtime = {
    active = false,
    activity = "menu",
    mainCompleted = 0,
    branchesCompletedAt = 0,
    branchProgress = nil,
    mainTorchHandledThrough = 0,
    torchOutcomes = {},
    oreScan = nil,
    oreAheadVisited = nil,
    skippedOreScans = {},
    skipOrePending = false,
    fluidRisk = false,
    needsSealSupply = false,
    collected = {},
}
local sharedNav = nil
local navigationState = nil
local sharedTelemetry = nil
local telemetryState = nil
local sharedSituations = nil
local activeBranchContext = nil

local function swarmLinkAlive()
    if not config.swarmTrunkOnly then return true end
    local session = SwarmSession.load()
    local now = os.epoch and os.epoch("utc") or 0
    return session and session.active and session.role == "leader"
        and not session.stationCheckPending
        and session.jobId == config.swarmJobId
        and session.status ~= "emergency_stop"
        and session.coordinatorId and session.lastHeartbeatAt
        and now - session.lastHeartbeatAt <= 6000
end

local function saveState()
    if not persistenceEnabled then return end
    local pose = sharedNav and sharedNav:getPose()
        or { x = position.x, y = position.y, z = position.z, heading = heading }
    local payload = {
        version = 2,
        active = runtime.active,
        activity = runtime.activity,
        mainCompleted = runtime.mainCompleted,
        branchesCompletedAt = runtime.branchesCompletedAt,
        branchProgress = runtime.branchProgress,
        mainTorchHandledThrough = runtime.mainTorchHandledThrough,
        torchOutcomes = runtime.torchOutcomes,
        oreScan = runtime.oreScan,
        oreAheadVisited = runtime.oreAheadVisited,
        skippedOreScans = runtime.active and runtime.skippedOreScans or nil,
        skipOrePending = runtime.active and runtime.skipOrePending or nil,
        fluidRisk = runtime.fluidRisk,
        needsSealSupply = runtime.needsSealSupply,
        collected = runtime.active and runtime.collected or nil,
        position = { x = pose.x, y = pose.y, z = pose.z },
        heading = pose.heading,
        navigation = sharedNav and sharedNav:snapshot() or navigationState,
        telemetry = sharedTelemetry and sharedTelemetry:snapshot() or telemetryState,
        config = config,
    }
    local ok, reason = stateStore.write(STATE_FILE, payload)
    if not ok then error(reason or "Nem irhato az allapotfajl.", 0) end
end

local function trackedDig(action)
    local before = PickupLedger.snapshot()
    local dug
    if sharedTelemetry then
        dug = sharedTelemetry:measure("dig", action)
    else
        dug = action()
    end
    if dug then
        runtime.collected = PickupLedger.record(runtime.collected, before,
            PickupLedger.snapshot())
        saveState()
    end
    return dug
end

local function setActivity(activity)
    runtime.activity = activity
    saveState()
end

local function loadState()
    local saved = stateStore.read(STATE_FILE)
    if type(saved) ~= "table" or saved.version ~= 2 then return nil end
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
            runtime.branchProgress = saved.branchProgress
            runtime.mainTorchHandledThrough = saved.mainTorchHandledThrough
                or saved.mainCompleted or 0
            runtime.torchOutcomes = saved.torchOutcomes or {}
            runtime.oreScan = saved.oreScan
            runtime.oreAheadVisited = saved.oreAheadVisited
            runtime.skippedOreScans = saved.skippedOreScans or {}
            runtime.skipOrePending = saved.skipOrePending == true
            runtime.fluidRisk = saved.fluidRisk == true
            runtime.needsSealSupply = saved.needsSealSupply == true
            runtime.collected = saved.collected or {}
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
        runtime.branchProgress = saved.branchProgress
        runtime.torchOutcomes = saved.torchOutcomes or {}
        runtime.oreScan = saved.oreScan
        runtime.oreAheadVisited = saved.oreAheadVisited
        runtime.skippedOreScans = saved.skippedOreScans or {}
        runtime.skipOrePending = saved.skipOrePending == true
        runtime.fluidRisk = saved.fluidRisk == true
        runtime.needsSealSupply = saved.needsSealSupply == true
        runtime.collected = saved.collected or {}
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

local function sealBlockNames()
    local targets = config.safety and config.safety.sealBlocks
    if type(targets) ~= "table" or #targets == 0 then
        targets = { config.safety and config.safety.sealBlock
            or "minecraft:cobblestone" }
    end
    return targets
end

local function isSealBlock(name)
    for _, target in ipairs(sealBlockNames()) do
        if target == name then return true end
    end
    return false
end

local function selectSealBlock()
    local firstMiningSlot = config.torchEnabled and 3 or 2
    for _, target in ipairs(sealBlockNames()) do
        for slot = firstMiningSlot, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name == target and turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                return true
            end
        end
    end
    runtime.needsSealSupply = true
    saveState()
    return false, "Nincs engedelyezett tomitoblokk az inventory-ban."
end

local function managedDig(direction)
    if not swarmLinkAlive() then
        return false, "Kezeloi kapcsolat megszakadt; helyben megallas."
    end
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
    local safe, unsafeReason = SwarmSafety.mayDig(direction)
    if not safe then return false, unsafeReason end
    if direction == "forward" and config.oreScanEnabled and activeBranchContext
        and oreScanner and (oreScanner.matches(blockData)
            or oreScanner.discoveryId(blockData)) then
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
        runtime.fluidRisk = true
        saveState()
        local cleared = sharedSituations:clearFluidSource(direction, selectSealBlock, function()
            return trackedDig(dig)
        end)
        if cleared.kind == "handled" then return true end
        return false, cleared.reason or "A folyadek nem zarhato le."
    end
    if not config.experimentalInventory or not inventoryManager or returningHome then
        local dug = trackedDig(dig)
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
            local dug = trackedDig(dig)
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
    while turtle.detect() or sharedSituations
        and sharedSituations:fluidKind("forward") do
        local dug, reason = managedDig("forward")
        if not dug then return false, reason or "Nem tudom kiasni az elottem levo blokkot." end
        sleep(0.15)
        attempts = attempts + 1
        if attempts > 20 then return false, "Tul sok blokk esett az utamba." end
    end
    return true
end

local forward
local moveVerticalTo

local function sealOuterFluid()
    if not sharedSituations then return true end
    local first = sharedSituations:fluidKind("forward")
    if first then
        runtime.fluidRisk = true
        saveState()
    end
    if not runtime.fluidRisk then return true end
    local startY, startHeading = position.y, heading
    local ok, reason = true, nil
    for _, level in ipairs({ -1, 0, 1 }) do
        ok, reason = moveVerticalTo(startY + level)
        if not ok then break end
        if sharedSituations:fluidKind("forward") then
            local sealed = sharedSituations:sealFluid("forward", selectSealBlock)
            if sealed.kind ~= "handled" and sealed.kind ~= "skipped" then
                ok, reason = false, sealed.reason
                break
            end
            if runtime.needsSealSupply then
                ok, reason = false, "Nincs tomitoblokk a kulso falhoz."
                break
            end
        end
    end
    local restored, restoreReason = moveVerticalTo(startY)
    if not restored then return false, restoreReason end
    face(startHeading)
    return ok, reason
end

local function clearVerticalColumn()
    if turtle.detectUp() or sharedSituations
        and sharedSituations:fluidKind("up") then
        local dug, reason = managedDig("up")
        if not dug then return false, reason or "Nem tudom kiasni a felso blokkot." end
    end
    if config.tunnelMode >= 2 and (turtle.detectDown()
        or sharedSituations and sharedSituations:fluidKind("down")) then
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
    local outerOk, outerReason = sealOuterFluid()
    if not outerOk then return false, outerReason end

    turnAround()
    moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    cleared, reason = clearVerticalColumn()
    if not cleared then return false, reason end
    outerOk, outerReason = sealOuterFluid()
    if not outerOk then return false, outerReason end

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
    if not swarmLinkAlive() then
        return false, "link_lost", "Kezeloi kapcsolat megszakadt; helyben megallas."
    end
    if returningHome and heading == 2 and BaseDock.chestOnReturn(sharedNav) then
        return false, "dock_reached", "A leado lada elott allok."
    end
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
            local safe, unsafeReason = SwarmSafety.mayDig("forward")
            if not safe then
                return { result = { ok = false, code = "protected",
                    reason = unsafeReason } }
            end
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

moveVerticalTo = function(targetY)
    while position.y > targetY do
        if not swarmLinkAlive() then return false, "Kezeloi kapcsolat megszakadt." end
        if not refuelFromInventory(1) then return false, "Nincs fuel a leereszkedeshez." end
        local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
            { kind = "d" }, {
                onBlocked = function(_, moveResult)
                    local safe, unsafeReason = SwarmSafety.mayDig("down")
                    if not safe then
                        return { result = { ok = false, code = "protected",
                            reason = unsafeReason } }
                    end
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
        if not swarmLinkAlive() then return false, "Kezeloi kapcsolat megszakadt." end
        if not refuelFromInventory(1) then return false, "Nincs fuel a felemelkedeshez." end
        local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
            { kind = "u" }, {
                onBlocked = function(_, moveResult)
                    local safe, unsafeReason = SwarmSafety.mayDig("up")
                    if not safe then
                        return { result = { ok = false, code = "protected",
                            reason = unsafeReason } }
                    end
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

local function sealNearbyFluid()
    if not runtime.fluidRisk or returningHome then return true end
    local startY, startHeading = position.y, heading
    local levels = config.tunnelMode == 1 and { 0, 1 } or { -1, 0, 1 }
    local function seal(direction)
        if not sharedSituations:fluidKind(direction) then return true end
        local outcome = sharedSituations:sealFluid(direction, selectSealBlock)
        if outcome.kind == "handled" then return true end
        if runtime.needsSealSupply then
            return false, "Tömitoblokk kell a folyadek melletti reshez."
        end
        if outcome.kind == "skipped" then return true end
        return false, outcome.reason or "Nem zarhato le a folyadek."
    end
    local ok, reason = true, nil
    for _, level in ipairs(levels) do
        ok, reason = moveVerticalTo(startY + level)
        if not ok then break end
        for _, side in ipairs({ 1, 3 }) do
            face((startHeading + side) % 4)
            ok, reason = seal("forward")
            if not ok then break end
        end
        if not ok then break end
        if level == levels[1] then
            ok, reason = seal("down")
            if not ok then break end
        end
        if level == levels[#levels] then
            ok, reason = seal("up")
            if not ok then break end
        end
    end
    local restored, restoreReason = moveVerticalTo(startY)
    if not restored then return false, restoreReason end
    face(startHeading)
    if not ok then return false, reason end
    runtime.fluidRisk = false
    saveState()
    return true
end

local function returnHome()
    if not swarmLinkAlive() then
        return false, "Kezeloi kapcsolat megszakadt; nincs vak hazateres."
    end
    returningHome = true
    setActivity("hazateres")
    status("Hazateres")
    local travelY = config.tunnelMode == 3 and 1 or 0
    local ok, reason = moveVerticalTo(travelY)
    if ok then ok, reason = navigateTo(0, 0, 0) end
    if ok then ok, reason = moveVerticalTo(0) end
    if ok or reason == "A leado lada elott allok." then
        if swarmLinkAlive() then ok, reason = BaseDock.seek(sharedNav, 2)
        else ok, reason = false, "Kezeloi kapcsolat megszakadt." end
        if ok then face(0) end
    end
    returningHome = false
    if ok then status("Hazaertem")
    else printError("A hazateres elakadt: " .. (reason or "ismeretlen hiba")) end
    return ok, reason
end

local function unloadBehind()
    turnAround()
    local learned, learnReason = BaseDock.learnAtBase(sharedNav)
    if not learned then return false, learnReason end
    local selected = turtle.getSelectedSlot()
    local allDeposited = true
    local keptSeal = false
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            local keepForFuel = slot == 1 and turtle.refuel(0)
            local keepForTorch = slot == 2 and config.torchEnabled
                and torchManager and torchManager.keepReservedSlot(config)
            local keepForSeal = not keptSeal and detail
                and isSealBlock(detail.name) and slot >= (config.torchEnabled and 3 or 2)
            if keepForSeal then keptSeal = true end
            if not keepForFuel and not keepForTorch and not keepForSeal then
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
    if not swarmLinkAlive() then
        return false, "Kezeloi kapcsolat megszakadt; nincs lada-kiszolgalas."
    end
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
    if runtime.needsSealSupply then
        local selected = turtle.getSelectedSlot()
        local ready = selectSealBlock()
        if not ready then
            local first = config.torchEnabled and 3 or 2
            local empty = nil
            for slot = first, 16 do
                if turtle.getItemCount(slot) == 0 then empty = slot break end
            end
            if not empty then return false, "Nincs szabad hely tomitoblokknak." end
            turtle.select(empty)
            if not turtle.suck(64) then
                turtle.select(selected)
                return false, "Nincs tomitoblokk a leado ladaban."
            end
            local item = turtle.getItemDetail(empty)
            if not item or not isSealBlock(item.name) then
                turtle.drop()
                turtle.select(selected)
                return false, "A leado lada elso targya nem engedelyezett tomitoblokk."
            end
        end
        turtle.select(selected)
        runtime.needsSealSupply = false
        saveState()
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
    if not swarmLinkAlive() then
        return false, "Kezeloi kapcsolat megszakadt; helyben megallas."
    end
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
    local function supportedAbove()
        if turtle.detectUp() then return false, "A fej feletti hely foglalt." end
        local raised = sharedNav:step({ kind = "u" })
        if not raised.ok then return false, raised.reason end
        local supported = turtle.detectUp()
        local reason = nil
        if not supported and sharedSituations:fluidKind("up") then
            reason = "Folyadek van a faklya tamasza helyen."
        elseif not supported then
            local selected = turtle.getSelectedSlot()
            local ready, missing = selectSealBlock()
            if ready then supported = turtle.placeUp()
            else reason = missing end
            turtle.select(selected)
        end
        local lowered = sharedNav:step({ kind = "d" })
        if not lowered.ok then
            error("Nem tudok visszaereszkedni a faklyatamasz utan: "
                .. tostring(lowered.reason), 0)
        end
        if not supported then return false, reason or "Nem teheto le tamasza a faklyanak." end
        return above()
    end
    local outcome = sharedSituations:placeTorchWithFallback({
        preferred = config.torchPlacementMode == 2 and above or side((originalHeading + 1) % 4),
        otherSide = side((originalHeading + 3) % 4),
        above = config.torchPlacementMode == 2 and nil or above,
        supportPreferred = supportedAbove,
    })
    -- A sikertelen fizikai faklyalerakas nem allithatja le a banyaszatot.
    -- A helyzetkezelo figyelmeztetese tovabbra is megmarad.

    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end
    return true, nil, outcome.kind == "handled"
end

local function noteTorch(key, physicallyPlaced)
    runtime.torchOutcomes[key] = physicallyPlaced and "placed" or "skipped"
    saveState()
end

local function mineForward(steps, label, carveCrossSection)
    if carveCrossSection == nil then carveCrossSection = true end
    local step = 1
    while step <= steps do
        if not swarmLinkAlive() then
            return false, "Kezeloi kapcsolat megszakadt; helyben megallas."
        end
        if stopRequested and not returningHome then
            return false, "Felhasznaloi leallitas."
        end
        if serviceRequested and not returningHome then
            serviceRequested = false
            local resumed, serviceReason = serviceAndResume("Tavoli lepakolas es feltoltes.")
            if not resumed then return false, serviceReason end
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
        if not dug then
            if runtime.needsSealSupply and not returningHome then
                local resumed, serviceReason = serviceAndResume(
                    "Tomitoblokk kell a folyadekhoz.")
                if not resumed then return false, serviceReason end
            else return false, digReason end
        else

        local moved, moveCode, moveReason = forward()
        if not moved and moveCode == "fuel" and not returningHome then
            local resumed, reason = serviceAndResume("Keves az uzemanyag. " .. moveReason)
            if not resumed then return false, reason end
        elseif not moved then
            if runtime.needsSealSupply and not returningHome then
                local resumed, serviceReason = serviceAndResume(
                    "Tomitoblokk kell a folyadekhoz.")
                if not resumed then return false, serviceReason end
            else return false, moveReason end
        else
            if not swarmLinkAlive() then
                return false, "Kezeloi kapcsolat megszakadt; helyben megallas."
            end
            if carveCrossSection then
                local cleared, clearReason = clearTunnelCrossSection()
                if not cleared then return false, clearReason end
                local sealed, sealReason = sealNearbyFluid()
                if not sealed then
                    if runtime.needsSealSupply then
                        local resumed, serviceReason = serviceAndResume(
                            "Tomitoblokk kell a folyadekhoz.")
                        if not resumed then return false, serviceReason end
                        sealed, sealReason = sealNearbyFluid()
                        if not sealed then return false, sealReason end
                    else return false, sealReason end
                end
            end
            if step == 1 or step % 8 == 0 or step == steps then
                status(label .. " " .. step .. "/" .. steps)
            end
            step = step + 1
        end
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

local function oreInspectAndDig(move, _, discoveryId)
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
    local safe, unsafeReason = SwarmSafety.mayDig(
        move.kind == "u" and "up" or move.kind == "d" and "down"
            or "forward")
    if not safe then return false, "protected", unsafeReason end
    if not hasBlock or not (oreScanner.matches(blockData)
        or discoveryId and blockData.name == discoveryId) then
        return false, "changed", "A kijelolt erc mar nincs a helyen."
    end
    if not config.experimentalInventory or not inventoryManager then
        if inventoryFull() then
            return false, "service", "Az inventory megtelt az erc elott."
        end
        if not trackedDig(dig) then return false, "blocked", "A kijelolt erc nem banyaszhato." end
        return true
    end

    local ready, beforeOrReason = inventoryManager.prepareForDig(config, blockData)
    if not ready then
        return false, "service", "KISERLETI inventory: " .. tostring(beforeOrReason)
    end
    if not trackedDig(dig) then return false, "blocked", "A kijelolt erc nem banyaszhato." end
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
        shouldSkipScan = function() return runtime.skipOrePending end,
        markSkipped = function(side, step)
            local key = tostring(config.startOffset + runtime.mainCompleted)
                .. ":" .. side
            if not runtime.skippedOreScans[key] then
                runtime.skippedOreScans[key] = { fromStep = step }
            end
            runtime.skipOrePending = false
            saveState()
        end,
        checkpoint = function(oreState)
            runtime.oreScan = oreState
            saveState()
            if oreState then status("Erckereses") end
        end,
        placeBranchTorch = function(side, branchStep)
            if not config.torchEnabled or branchStep <= 0
                or config.branchTorchInterval <= 0
                or branchStep % config.branchTorchInterval ~= 0 then
                return true
            end
            runtime.oreAheadVisited.torches = runtime.oreAheadVisited.torches
                or { left = {}, right = {} }
            local placedBySide = runtime.oreAheadVisited.torches[side]
            if placedBySide[branchStep] then return true end
            local previousReturning = returningHome
            returningHome = false
            local placed, reason, physicallyPlaced = placeTorchNow()
            returningHome = previousReturning
            if placed then
                placedBySide[branchStep] = true
                noteTorch(string.format("branch:%d:%s:%d",
                    config.startOffset + runtime.mainCompleted,
                    side, branchStep), physicallyPlaced)
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
    local function placePlannedTorch(branchStep)
        if not placeTorches or not config.torchEnabled
            or config.branchTorchInterval <= 0
            or branchStep <= 0
            or branchStep % config.branchTorchInterval ~= 0 then
            return true
        end
        -- Ercellenorzes nelkul a kesz agat mar az asas kozben faklyazzuk.
        -- A sikertelen helyezest a kozos helyzetkezelo nem vegzetesnek veszi.
        local ok, reason, physicallyPlaced = placeTorchNow()
        if ok then
            noteTorch(string.format("branch:%d:%s:%d",
                config.startOffset + runtime.mainCompleted,
                sideKey, branchStep), physicallyPlaced)
        end
        return ok, reason
    end
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
        completed, reason = placePlannedTorch(branchStep)
        if not completed then return false, reason end
    end
    if carveCrossSection and config.oreScanEnabled then
        setActivity(sideKey == "left" and "bal_ag_vissza_erc"
            or "jobb_ag_vissza_erc")
        local scanned, scanReason = oreScanner.scanReturnBranch(
            sideKey, config.branchLength, config.tunnelMode, buildOreApi()
        )
        if not scanned then return false, scanReason end
        return true
    end
    turnAround()
    local previousReturningState = returningHome
    returningHome = true

    local returned, returnReason = true, nil
    for returnStep = 1, config.branchLength do
        returned, returnReason = mineForward(1, sideName .. " vissza", false)
        if not returned then break end
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
    if config.swarmTrunkOnly then return true end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    if config.tunnelMode == 3 then return true end
    if absoluteStep <= 0 or absoluteStep % config.branchSpacing ~= 0 then
        return true
    end
    if runtime.branchesCompletedAt >= absoluteStep then return true end

    if not runtime.branchProgress or runtime.branchProgress.at ~= absoluteStep then
        runtime.branchProgress = { at = absoluteStep, leftDone = false,
            rightDone = false }
        saveState()
    end

    local delayTorches = config.oreScanEnabled and config.torchEnabled
    if not runtime.oreAheadVisited or runtime.oreAheadVisited.at ~= absoluteStep then
        runtime.oreAheadVisited = {
            at = absoluteStep, left = {}, right = {},
            torches = { left = {}, right = {} },
        }
        saveState()
    end

    if not runtime.branchProgress.leftDone then
        setActivity("bal_oldalagat")
        local leftOk, leftReason = mineBranch(
            turnLeft, "Bal", not delayTorches, true
        )
        if not leftOk then return false, leftReason end
        runtime.branchProgress.leftDone = true
        saveState()
    end

    if not runtime.branchProgress.rightDone then
        setActivity("jobb_oldalagat")
        local rightOk, rightReason = mineBranch(
            turnRight, "Jobb", not delayTorches, true
        )
        if not rightOk then return false, rightReason end
        runtime.branchProgress.rightDone = true
        saveState()
    end

    runtime.branchesCompletedAt = absoluteStep
    runtime.branchProgress = nil
    runtime.oreAheadVisited = nil
    setActivity("agak_keszen")
    return true
end

local function plannedMainTorchPoints(completed)
    local points = {}
    if not config.torchEnabled or config.mainTorchInterval <= 0 then
        return points
    end

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

local mainTorchPointsCache
local function placeCurrentMainTorch(localStep)
    if localStep <= 0 or localStep <= runtime.mainTorchHandledThrough then
        return true
    end
    if not mainTorchPointsCache then
        mainTorchPointsCache = plannedMainTorchPoints(config.mainLength)
    end
    if mainTorchPointsCache[localStep] then
        -- A kijelolt fotengely-ponton mar elkeszult a keresztmetszet es
        -- az esetleges ket oldalagat is. Most probaljuk lerakni a faklyat.
        local placed, reason, physicallyPlaced = placeTorchNow()
        if not placed then return false, reason end
        noteTorch("main:" .. localStep, physicallyPlaced)
    end
    runtime.mainTorchHandledThrough = localStep
    saveState()
    return true
end

local function returnAndService()
    if returnHome() then
        local serviced, reason = serviceHome(config.fuelReserve)
        if not serviced then printError("Otthoni hiba: " .. (reason or "ismeretlen")) end
    end
end

local function parkSwarmLeader()
    if not config.swarmTrunkOnly then return true end
    if not swarmLinkAlive() then return false, "Kezeloi kapcsolat megszakadt." end
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "A vezetot csak a bazisrol lehet felreallitani."
    end
    face(3) -- A segedek jobbra sorakoznak; a vezeto balra all felre.
    local cleared, clearReason = digForwardUntilClear()
    if not cleared then return false, clearReason end
    local moved, _, moveReason = forward()
    if not moved then return false, moveReason end
    local clearTop, topReason = managedDig("up")
    if not clearTop then return false, topReason end
    face(0)
    return true
end

local function runMining()
    if config.swarmTrunkOnly and not swarmLinkAlive() then
        printError("Nincs aktiv kezelojel; nem indulok el.")
        return
    end
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
            local returnScan = runtime.oreScan.returnScan
            print(returnScan and "Oldalag visszauti vizsgalatanak folytatasa..."
                or "Erc-utvonal biztonsagos visszafejtese...")
            local side = runtime.oreScan.side
            local recovered, recoverReason
            if returnScan then
                recovered, recoverReason = oreScanner.resumeReturnBranch(
                    runtime.oreScan, config.branchLength, config.tunnelMode,
                    buildOreApi())
            else
                recovered, recoverReason = oreScanner.recover(
                    runtime.oreScan, buildOreApi())
            end
            if not recovered then
                printError("Nem tudtam visszafejteni az erc-utvonalat: "
                    .. tostring(recoverReason))
                return
            end
            if returnScan and runtime.branchProgress
                and runtime.branchProgress.at == config.startOffset
                    + runtime.mainCompleted then
                runtime.branchProgress[side .. "Done"] = true
                saveState()
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
        local torchOk, torchReason = placeCurrentMainTorch(runtime.mainCompleted)
        if not torchOk then
            printError("Fout-faklyazasi hiba: " .. tostring(torchReason))
            returnAndService()
            return
        end
    else
        runtime.active = true
        runtime.activity = "indulas"
        runtime.mainCompleted = 0
        runtime.branchesCompletedAt = 0
        runtime.branchProgress = nil
        runtime.mainTorchHandledThrough = 0
        runtime.oreScan = nil
        runtime.oreAheadVisited = nil
        runtime.skippedOreScans = {}
        runtime.skipOrePending = false
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
        local torchOk, torchReason = placeCurrentMainTorch(localStep)
        if not torchOk then stopReason = torchReason break end
    end

    if stopReason then printError("A banyaszat leallt: " .. stopReason)
    else print("A beallitott banyaszati szakasz elkeszult.") end

    if config.swarmTrunkOnly and not swarmLinkAlive() then
        setActivity("needs_attention")
        printError("Kapcsolatvesztes: a turtle helyben marad. Ne indits vak hazaterest.")
        return
    end

    -- Aktiv erc-kitero/visszauti vizsgalat mellett a sima koordinatas
    -- hazateres elmozditana a turtle-t a scanner mentett utvonala alol.
    if runtime.oreScan and runtime.oreScan.active then
        local recovered, recoverReason = oreScanner.recover(
            runtime.oreScan, buildOreApi())
        if not recovered then
            printError("Erc-utvonal miatt nem indulok vakon haza: "
                .. tostring(recoverReason))
            return
        end
    end

    if returnHome() then
        local finalOk, finalReason = serviceHome(config.fuelReserve)
        if finalOk then
            if not stopReason and config.swarmTrunkOnly then
                finalOk, finalReason = parkSwarmLeader()
            end
        end
        if finalOk then
            if not stopReason then
                runtime.active = false
                setActivity("kesz")
            else
                setActivity("megallitva_otthon")
            end
            print(config.swarmTrunkOnly and
                "Kesz: a vezeto a bazistol balra, biztonsagos varakozohelyen all."
                or "Kesz: a turtle otthon van, az inventory ures.")
        else printError("Hazaertem, de a lada-kiszolgalas sikertelen: " .. finalReason) end
    end
end

local function miningTask()
    local ok, errorMessage = pcall(runMining)
    if not ok then
        printError("Programhiba: " .. tostring(errorMessage))
        if distanceHome() > 0 and swarmLinkAlive() then returnAndService() end
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
            or (event == "turtomata_remote_command" and key == "return_home") then
            if not stopRequested then
                stopRequested = true
                print("Leallitas kerese fogadva.")
                print("Biztonsagos hazateres indul...")
            end
        elseif event == "key" and key == keys.s then
            status("Allapot")
        elseif event == "turtomata_remote_command" and key == "service" then
            serviceRequested = true
            print("Tavoli lepakolasi keres fogadva.")
        elseif event == "turtomata_remote_command"
            and key == "skip_ore_scan" then
            runtime.skipOrePending = true
            saveState()
            print("Erckereses kihagyasa a kovetkezo biztonsagos ponttol.")
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
