-- CC:Tweaked teglatest-kitorelo program.
-- A turtle a terulet bal also elso sarka elott, a melyseg iranyaba nezzen.

local programArgs = { ... }
local jobRequest = require("job_request")
local stateStore = require("state_store")
local Navigation = require("navigation")
local BaseDock = require("base_dock")
local Coordinate = require("coordinate_navigation")
local UI = require("ui")
local Telemetry = require("telemetry")
local Situations = require("situation_manager")
local WorkEstimator = require("work_estimator")
local centralRequest, centralRequestError = jobRequest.consume("excavator", programArgs)

local config = {}
local position = { x = 0, y = 0, z = 0 }
local heading = 0
local returningHome = false
local visited = 0
local stopRequested = false
local serviceRequested = false
local miningFinished = false
local persistenceEnabled = false
local STATE_FILE = "excavator_state.txt"
local STATE_TEMP_FILE = ".excavator_state.tmp"
local torchModuleOk, torchManager = pcall(require, "torch_manager")
if not torchModuleOk then torchManager = nil end
local actionLogOk, actionLogger = pcall(require, "action_log")
if not actionLogOk then actionLogger = nil end
local inventoryModuleOk, inventoryManager = pcall(require, "inventory_manager")
if not inventoryModuleOk then inventoryManager = nil end
local runtime = {
    active = false,
    activity = "menu",
    baseCompleted = 0,
    torchSteps = 0,
}
local sharedNav = nil
local navigationState = nil
local sharedTelemetry = nil
local telemetryState = nil
local sharedSituations = nil
local remoteNav = nil

local headings = {
    [0] = { x = 0, z = 1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 },
    [3] = { x = -1, z = 0 },
}

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
        baseCompleted = runtime.baseCompleted,
        torchSteps = runtime.torchSteps,
        visited = visited,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        navigation = sharedNav and sharedNav:snapshot() or navigationState,
        telemetry = sharedTelemetry and sharedTelemetry:snapshot() or telemetryState,
        remote = runtime.remote,
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
    if centralRequestError then error(centralRequestError, 0) end
    if centralRequest then
        if centralRequest.action == "resume" then
            if not saved then error("Nincs hasznalhato teruletaso mentes.", 0) end
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
            navigationState = saved.navigation
            telemetryState = saved.telemetry
            runtime.remote = saved.remote
        else
            config = centralRequest.config or {}
            config.autoResume = false
        end
        config.fuelReserve = config.fuelReserve or 5
        config.experimentalInventory = config.experimentalInventory == true
        config.torchEnabled = config.torchEnabled == true
        config.torchInterval = config.torchInterval or 0
        config.torchPlacementMode = config.torchPlacementMode or 1
        if not config.width or not config.depth or not config.height then error("Hianyos teruletaso konfiguracio.", 0) end
        if config.experimentalInventory and not inventoryManager then error("Hianyzik az inventory_manager.lua modul.", 0) end
        if config.torchEnabled and not torchManager then error("Hianyzik a torch_manager.lua modul.", 0) end
        clearScreen()
        banner()
        return
    end
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
        navigationState = saved.navigation
        telemetryState = saved.telemetry
        runtime.remote = saved.remote
    else
        config.autoResume = false
        print("Terulet: szeles=jobbra, mely=elore, magas=felfele")
        print("")
        config.width = promptInteger("Szelesseg", 8, 1)
        config.depth = promptInteger("Melyseg", 16, 1)
        config.height = promptInteger("Magassag", 4, 1)
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
            config.torchInterval = promptInteger("Faklya tavolsag", 12, 1)
            config.torchPlacementMode = promptChoice("Faklya helye (KISERLETI):", {
                "Oldalt: blokk ki, faklya be",
                "A turtle feje fole",
            }, 1)
        else
            config.torchInterval = 0
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
        config.torchPlacementMode = config.torchPlacementMode or 1
    end

    clearScreen()
    banner()
    print("")
    print("Meret: " .. config.width .. "x" .. config.depth .. "x" .. config.height)
    print("Blokkok: " .. (config.width * config.depth * config.height))
    print("Fuel+: " .. config.fuelReserve)
    print("Inv.: " .. (config.experimentalInventory and "KISERLETI" or "regi"))
    print(config.autoResume and "Mod: auto folytatas" or "Mod: uj terulet")
    if config.torchEnabled then
        print("Faklya: " .. config.torchInterval .. " cellankent (KISERLETI)")
        print("Faklya hely: " .. (config.torchPlacementMode == 2 and "fej folott" or "oldalt"))
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
    if config.experimentalInventory and inventoryManager then
        -- Kiserleti modban csak a mar detektalt blokk helyigenye dont.
        return false
    end
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
    local remaining = math.max(0, total - visited)
    local events = {}
    if config.experimentalInventory and inventoryManager then
        local inventoryStatus = inventoryManager.status(config)
        events[#events + 1] = string.format("KIS-INV %d/%d, ures %d",
            inventoryStatus.used, inventoryStatus.total, inventoryStatus.empty)
    end
    if sharedSituations then
        for _, warning in ipairs(sharedSituations:lastWarnings(2)) do
            events[#events + 1] = warning
        end
    end
    local remoteMoves = nil
    if config.remoteStart and config.remoteStart.enabled
        and config.remoteStart.base and config.remoteStart.work
        and runtime.remote then
        local base, work = config.remoteStart.base, config.remoteStart.work
        local remotePose = runtime.remote.navigation and runtime.remote.navigation.pose
        if runtime.remote.phase == "at_work" then
            remoteMoves = Coordinate.distance(work, base)
        elseif runtime.remote.phase == "to_work" and remotePose then
            remoteMoves = Coordinate.distance(remotePose, work) + Coordinate.distance(work, base)
        elseif runtime.remote.phase == "to_base" and remotePose then
            remoteMoves = Coordinate.distance(remotePose, base)
        elseif runtime.remote.phase == "at_base" then
            remoteMoves = 0
        end
    end
    local estimate = WorkEstimator.excavator(config, {
        baseCompleted = runtime.baseCompleted,
        visited = visited,
        remoteMoves = remoteMoves,
    })
    local remainingMs = sharedTelemetry and sharedTelemetry:estimateMs(estimate.plan)
        or WorkEstimator.durationMs(estimate, config.defaultActionSeconds or 0.8)
    local shownPosition = string.format("%d,%d,%d  irany=%d", position.x, position.y, position.z, heading)
    if runtime.remote and runtime.remote.phase ~= "at_work"
        and runtime.remote.navigation and runtime.remote.navigation.pose then
        local pose = runtime.remote.navigation.pose
        shownPosition = string.format("vilag %d,%d,%d irany=%d", pose.x, pose.y, pose.z, pose.heading)
    end
    UI.renderDashboard({
        task = "Terulet asas KISERLETI",
        status = prefix .. " / " .. tostring(runtime.activity),
        progress = string.format("%d/%d (%d%%)", visited, total, percent),
        position = shownPosition,
        fuel = fuelText() .. "  haza=" .. distanceHome(),
        inventory = inventoryUsage() .. "/16 slot",
        supplies = config.torchEnabled and ("faklya=" .. turtle.getItemCount(2)) or "faklya=ki",
        elapsed = sharedTelemetry and Telemetry.formatDuration(sharedTelemetry:elapsedMs()) or "00:00:00",
        remaining = string.format("%d muv. / kb. %s", estimate.totalActions,
            Telemetry.formatDuration(remainingMs)),
        events = events,
    })
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

local function face(target)
    if sharedNav then
        local turned = sharedNav:face(target)
        if not turned.ok then error(turned.reason, 0) end
        return
    end
    local difference = (target - heading) % 4
    if difference == 1 then turnRight()
    elseif difference == 2 then turnAround()
    elseif difference == 3 then turnLeft() end
end

local serviceAndResume

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

local function requiredForMove(nextX, nextY, nextZ)
    local homeAfterMove = math.abs(nextX) + math.abs(nextY) + math.abs(nextZ)
    if config.remoteStart and config.remoteStart.enabled
        and config.remoteStart.base and config.remoteStart.work then
        homeAfterMove = homeAfterMove
            + Coordinate.distance(config.remoteStart.base, config.remoteStart.work)
    end
    if not returningHome then homeAfterMove = homeAfterMove + config.fuelReserve end
    return 1 + homeAfterMove
end

local function digForward()
    local attempts = 0
    while turtle.detect() do
        local dug, reason = managedDig("forward")
        if not dug then return false, reason or "Az elottem levo blokk nem ashato." end
        sleep(0.1)
        attempts = attempts + 1
        if attempts > 20 then return false, "Tul sok blokk esik elem." end
    end
    return true
end

local function forward()
    if returningHome and heading == 2 and BaseDock.chestOnReturn(sharedNav) then
        return false, "A leado lada elott allok."
    end
    local direction = headings[heading]
    local nextX = position.x + direction.x
    local nextZ = position.z + direction.z
    if not refuelSlotOne(requiredForMove(nextX, position.y, nextZ)) then
        return false, "fuel"
    end
    local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
        { kind = "h", heading = heading }, {
            onBlocked = function(_, moveResult)
                local dug, reason = digForward()
                if dug then
                    if turtle.attack() then sleep(0.2) end
                    return { action = "retry" }
                end
                return { result = { ok = false, code = "blocked", reason = reason or moveResult.reason } }
            end,
        })
    if not moved.ok then return false, moved.reason or moved.code end
    return true
end

local function vertical(upward)
    local nextY = position.y + (upward and 1 or -1)
    if not refuelSlotOne(requiredForMove(position.x, nextY, position.z)) then
        return false, "fuel"
    end
    local direction = upward and "up" or "down"
    local moved = assert(sharedNav, "A navigacios modul nincs inicializalva."):step(
        { kind = upward and "u" or "d" }, {
            onBlocked = function(_, moveResult)
                local detect = upward and turtle.detectUp or turtle.detectDown
                local attack = upward and turtle.attackUp or turtle.attackDown
                if detect() then
                    local dug, reason = managedDig(direction)
                    if dug then return { action = "retry" } end
                    return { result = { ok = false, code = "blocked", reason = reason } }
                end
                if attack() then return { action = "retry" } end
                return { result = moveResult }
            end,
        })
    if not moved.ok then return false, moved.reason or moved.code end
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
    if ok or reason == "A leado lada elott allok." then
        ok, reason = BaseDock.seek(sharedNav, 2)
    end
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
    local moved = sharedNav:step({ kind = "u" })
    if not moved.ok then
        turnAround()
        return false, "A turtle feletti hely nem szabad."
    end
    local requiredAtTop = requiredAfterService + (config.torchEnabled and 3 or 1)
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        else
            sharedNav:step({ kind = "d" })
            turnAround()
            return false, "Az 1-es slot nem egetheto."
        end
    end
    while fuelLevel() < requiredAtTop do
        if not turtle.suck(64) then
            sharedNav:step({ kind = "d" })
            turnAround()
            return false, "Az uzemanyaglada ures."
        end
        if not turtle.refuel(0) then
            turtle.drop()
            sharedNav:step({ kind = "d" })
            turnAround()
            return false, "Nem egetheto targy van a fuel ladaban."
        end
        turtle.refuel()
    end

    if config.torchEnabled then
        moved = sharedNav:step({ kind = "u" })
        if not moved.ok then
            sharedNav:step({ kind = "d" })
            turnAround()
            return false, "Nem tudok felmenni a faklyas ladahoz."
        end
        local torchOk, torchReason = torchManager.refillFromChest()
        moved = sharedNav:step({ kind = "d" })
        if not moved.ok then return false, "Nem tudok lejonni a faklyas ladatol." end
        if not torchOk then
            sharedNav:step({ kind = "d" })
            turnAround()
            return false, torchReason
        end
    end
    moved = sharedNav:step({ kind = "d" })
    if not moved.ok then return false, "Nem tudok leereszkedni." end
    turnAround()
    turtle.select(config.torchEnabled and 3 or 2)
    return true
end

local function serviceAtBase(requiredForTrip)
    if position.x ~= 0 or position.y ~= 0 or position.z ~= 0 then
        return false, "Nem vagyok a kezdohelyen."
    end
    setActivity("urites_tankolas")
    refuelSlotOne(math.max(config.torchEnabled and 4 or 2, requiredForTrip))
    local unloaded, unloadReason = unloadBehind()
    if not unloaded then return false, unloadReason end
    local fueled, fuelReason = fuelFromUpperChest(requiredForTrip)
    if not fueled then return false, fuelReason end
    if config.experimentalInventory and inventoryManager then
        local refreshed, inventoryReason = inventoryManager.refresh(
            config, "indulas_ladaktol", true
        )
        if not refreshed then return false, inventoryReason end
    end
    return true
end

local function remoteEnabled()
    return config.remoteStart and config.remoteStart.enabled
        and config.remoteStart.base and config.remoteStart.work
end

local function remoteDistance()
    if not remoteEnabled() then return 0 end
    return Coordinate.distance(config.remoteStart.base, config.remoteStart.work)
end

local function remoteMoveOptions()
    local function directionApi(move)
        if move.kind == "u" then return turtle.inspectUp, turtle.digUp, turtle.attackUp end
        if move.kind == "d" then return turtle.inspectDown, turtle.digDown, turtle.attackDown end
        return turtle.inspect, turtle.dig, turtle.attack
    end
    return {
        shouldStop = function() return stopRequested end,
        onBlocked = function(move, moveResult)
            if config.remoteStart.mode ~= "dig" then
                return { result = {
                    ok = false, code = "blocked",
                    reason = "Akadaly a koordinatas utvonalon (csak szabad ut mod).",
                } }
            end
            local inspect, dig, attack = directionApi(move)
            local exists, data = inspect()
            if exists then
                local name = data and data.name or ""
                if string.find(name, "water", 1, true)
                    or string.find(name, "lava", 1, true) then
                    return { result = { ok = false, code = "blocked",
                        reason = "Folyadek van a koordinatas utvonalon." } }
                end
                if dig() then return { action = "retry" } end
            elseif attack() then
                return { action = "retry" }
            end
            return { result = { ok = false, code = "blocked", reason = moveResult.reason } }
        end,
    }
end

local function travelRemote(targetName)
    if not remoteEnabled() then return true end
    local target = config.remoteStart[targetName]
    runtime.remote.phase = targetName == "base" and "to_base" or "to_work"
    setActivity(targetName == "base" and "koordinatas_hazateres" or "koordinatas_munkapont")
    local plan, reason = Coordinate.plan(remoteNav:getPose(), target, config.remoteStart.axisOrder)
    if not plan then return false, reason end
    local result = Coordinate.execute(remoteNav, plan, remoteMoveOptions())
    if not result.ok then return false, result.reason or result.code end
    runtime.remote.phase = targetName == "base" and "at_base" or "at_work"
    runtime.remote.navigation = remoteNav:snapshot()
    saveState()
    return true
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

serviceAndResume = function(reasonText)
    local savedX, savedY, savedZ = position.x, position.y, position.z
    local savedHeading = heading
    local savedActivity = runtime.activity
    clearScreen()
    banner()
    print("Megszakitas: " .. reasonText)
    local homeOk, homeReason = returnHome()
    if not homeOk then return false, homeReason end
    local atBase, baseReason = travelRemote("base")
    if not atBase then return false, baseReason end
    local remoteTrip = remoteDistance() * 2
    local serviced, serviceReason = serviceAtBase(
        tripRequirement(savedX, savedY, savedZ) + remoteTrip
    )
    if not serviced then return false, serviceReason end
    if stopRequested then return false, "Felhasznaloi leallitas." end
    local atWork, workReason = travelRemote("work")
    if not atWork then return false, workReason end
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
        if serviceRequested and not returningHome then
            serviceRequested = false
            local resumed, serviceReason = serviceAndResume("Tavoli lepakolas es feltoltes.")
            if not resumed then return false, serviceReason end
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
        local dug, reason = managedDig("up")
        if not dug then return false, reason or "A felso blokk nem ashato." end
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
    local placementAvailable = config.torchPlacementMode == 2 or direction ~= nil
    if nextTorchSteps < config.torchInterval or not placementAvailable then
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
    local originalHeading = heading
    local function side(target)
        if target == nil then return nil end
        return function()
            return torchManager.placeInDirection(target, function() return heading end, face, managedDig)
        end
    end
    local function above()
        return torchManager.placeAbove(function() return heading end, face)
    end
    local outcome = sharedSituations:placeTorchWithFallback({
        preferred = config.torchPlacementMode == 2 and above or side(direction),
        otherSide = side(direction and ((direction + 2) % 4) or nil),
        above = config.torchPlacementMode == 2 and nil or above,
    })
    if outcome.kind == "fatal" then return false, outcome.reason end
    if not torchManager.hasTorch() then
        local resumed, reason = serviceAndResume("Elfogyott a faklya.")
        if not resumed then return false, reason end
    end
    return true, nil, 0
end

local function runExcavation()
    persistenceEnabled = true
    sharedTelemetry = Telemetry.new(telemetryState, { defaultSeconds = config.defaultActionSeconds or 0.8 })
    sharedSituations = Situations.new(config.safety or {}, { telemetry = sharedTelemetry })
    sharedNav = Navigation.new({
        state = navigationState or {
            pose = { x = position.x, y = position.y, z = position.z, heading = heading },
            path = {}, pending = nil, anchors = {},
        },
        ensureFuel = function(required)
            if refuelSlotOne(required) then return true end
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
    if remoteEnabled() then
        runtime.remote = runtime.remote or {
            phase = "at_base",
            navigation = {
                pose = {
                    x = config.remoteStart.base.x,
                    y = config.remoteStart.base.y,
                    z = config.remoteStart.base.z,
                    heading = config.remoteStart.base.heading,
                },
                path = {}, pending = nil, anchors = {},
            },
        }
        remoteNav = Coordinate.createNavigator({
            state = runtime.remote.navigation,
            telemetry = sharedTelemetry,
            retryLimit = config.safety and config.safety.retryLimit,
            ensureFuel = function(required, distanceToBase)
                return refuelSlotOne(required + distanceToBase + config.fuelReserve)
            end,
            checkpoint = function(navState)
                runtime.remote.navigation = navState
                saveState()
                status("Koordinatas navigacio")
            end,
        })
        local remoteRecovered = remoteNav:recoverPending()
        if not remoteRecovered.ok then
            printError("Koordinatas menteshiba: " .. tostring(remoteRecovered.reason))
            return
        end
    end
    if config.experimentalInventory and inventoryManager then
        local initialized, inventoryReason = inventoryManager.initialize(config)
        if not initialized then
            printError("Inventory modul hiba: " .. tostring(inventoryReason))
            return
        end
    end
    if actionLogger then
        actionLogger.log(config.autoResume
            and "Terulet asas - auto folytatas"
            or "Terulet asas - uj munka")
    end
    local total = config.width * config.depth * config.height
    local baseTotal = config.width * config.depth * math.ceil(config.height / 2)

    if config.autoResume then
        runtime.active = true
        setActivity("auto_ujrainditas")
        if remoteEnabled() and runtime.remote.phase ~= "at_work" then
            if runtime.remote.phase == "to_base" or runtime.remote.phase == "at_base" then
                local atBase, baseReason = travelRemote("base")
                if not atBase then printError(baseReason) return end
                local serviced, reason = serviceAtBase(config.fuelReserve + remoteDistance() * 2 + 4)
                if not serviced then printError(reason) return end
            end
            local atWork, workReason = travelRemote("work")
            if not atWork then printError(workReason) return end
        end
        if not returnHome() then return end
    else
        runtime.active = true
        runtime.baseCompleted = 0
        runtime.torchSteps = 0
        visited = 0
        setActivity("indulas")
    end

    local atBase, baseReason = travelRemote("base")
    if not atBase then
        printError("Inditasi hiba: " .. tostring(baseReason))
        return
    end
    local serviced, serviceReason = serviceAtBase(
        config.fuelReserve + (remoteDistance() * 2) + 4
    )
    if not serviced then
        printError("Inditasi hiba: " .. serviceReason)
        return
    end
    local atWork, workReason = travelRemote("work")
    if not atWork then
        printError("Munkapont hiba: " .. tostring(workReason))
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
        local baseOk, finalReason = travelRemote("base")
        local finalOk = false
        if baseOk then finalOk, finalReason = serviceAtBase(config.fuelReserve) end
        if finalOk then
            if not stopReason then
                runtime.active = false
                setActivity("kesz")
            else
                setActivity("megallitva_otthon")
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
        if event == "terminate" or (event == "key" and key == keys.q)
            or (event == "turtomata_remote_command" and key == "return_home") then
            if not stopRequested then
                stopRequested = true
                print("Leallitas kerese fogadva. Biztonsagos hazateres indul...")
            end
        elseif event == "key" and key == keys.s then
            status("Allapot")
        elseif event == "turtomata_remote_command" and key == "service" then
            serviceRequested = true
            print("Tavoli lepakolasi keres fogadva.")
        end
    end
end

local configured, configureError = pcall(configure)
if not configured then
    printError("Beallitasi hiba: " .. tostring(configureError))
else
    parallel.waitForAll(miningTask, stopListener)
end
