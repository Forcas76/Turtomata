-- CCTurtle kozponti belepesi pont.

local ui = require("ui")
local Settings = require("settings")
local stateStore = require("state_store")
local jobRequest = require("job_request")
local WorkEstimator = require("work_estimator")

local currentSettings = Settings.load()
local remoteOk, Remote = pcall(require, "remote")

local function boolText(value) return value and "BE" or "KI" end

local function appendEstimate(lines, estimate)
    for _, formula in ipairs(estimate.formula or {}) do
        lines[#lines + 1] = "Keplet: " .. formula
    end
    local seconds = currentSettings.navigation.defaultActionSeconds or 0.8
    lines[#lines + 1] = "Vart muvelet: " .. estimate.totalActions
    lines[#lines + 1] = string.format("Becsles (%.2f mp/muv): %s", seconds,
        require("telemetry").formatDuration(WorkEstimator.durationMs(estimate, seconds)))
    return lines
end

local function programExists(name)
    return fs.exists(name) or fs.exists(name .. ".lua")
end

local function activeState(path)
    local value = stateStore.read(path)
    return type(value) == "table" and value.active == true
end

local function saveSettings()
    local ok, reason = Settings.save(currentSettings)
    if not ok then
        ui.message("Beallitasi hiba", reason, "error")
        ui.waitForEnter()
    end
    return ok
end

local function toggle(path)
    Settings.set(currentSettings, path, not Settings.get(currentSettings, path, false))
    saveSettings()
end

local function editInteger(title, path, minimum, maximum)
    local old = Settings.get(currentSettings, path, minimum)
    local value = ui.integer(title, title, old, minimum, maximum)
    Settings.set(currentSettings, path, value)
    saveSettings()
end

local function oreSettings()
    while true do
        local choice = ui.menu("BEALLITASOK > ERCKERESES", {
            { label = "Alapbol engedelyezve", suffix = boolText(currentSettings.ores.enabledByDefault), value = "toggle" },
            { label = "Keresett ercek", value = "targets" },
            { label = "Max. kovetesi melyseg", suffix = currentSettings.ores.maxDepth, value = "depth" },
            { label = "Max. blokk / erctelep", suffix = currentSettings.ores.maxBlocks, value = "blocks" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "toggle" then toggle("ores.enabledByDefault")
        elseif choice == "depth" then editInteger("Max. kovetesi melyseg", "ores.maxDepth", 1, 64)
        elseif choice == "blocks" then editInteger("Max. blokk / erctelep", "ores.maxBlocks", 1, 512)
        elseif choice == "targets" then
            local ok, scanner = pcall(require, "ore_scanner")
            if not ok then
                ui.message("Hianyzo modul", "Nem toltheto be az ore_scanner.lua.", "error")
                ui.waitForEnter()
            else
                local edited, reason = scanner.editTargets()
                if not edited then
                    ui.message("Erclista hiba", reason or "Nem mentheto az erclista.", "error")
                    ui.waitForEnter()
                end
            end
        end
    end
end

local function torchSettings()
    while true do
        local choice = ui.menu("BEALLITASOK > FAKLYAZAS", {
            { label = "Alapbol engedelyezve", suffix = boolText(currentSettings.torches.enabledByDefault), value = "toggle" },
            { label = "Alap tavolsag", suffix = currentSettings.torches.interval, value = "interval" },
            { label = "Alap elhelyezes", suffix = currentSettings.torches.placement == "above" and "fej folott" or "oldalt", value = "placement" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "toggle" then toggle("torches.enabledByDefault")
        elseif choice == "interval" then editInteger("Faklya tavolsag", "torches.interval", 1, 128)
        elseif choice == "placement" then
            local selected = ui.choice("Faklya elhelyezese", { "Oldalt", "Fej folott" }, currentSettings.torches.placement == "above" and 2 or 1)
            if selected then
                currentSettings.torches.placement = selected == 2 and "above" or "side"
                saveSettings()
            end
        end
    end
end

local function safetySettings()
    while true do
        local choice = ui.menu("BEALLITASOK > BIZTONSAG", {
            { label = "Viz lezarasa", suffix = boolText(currentSettings.safety.sealWater), value = "water" },
            { label = "Lava lezarasa", suffix = boolText(currentSettings.safety.sealLava), value = "lava" },
            { label = "Faklyahiba vegzetes", suffix = boolText(currentSettings.safety.torchFailureFatal), value = "torch" },
            { label = "Ujraprobalasi limit", suffix = currentSettings.safety.retryLimit, value = "retry" },
            { label = "Tomitoblokk", suffix = currentSettings.safety.sealBlock, value = "block" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "water" then toggle("safety.sealWater")
        elseif choice == "lava" then toggle("safety.sealLava")
        elseif choice == "torch" then toggle("safety.torchFailureFatal")
        elseif choice == "retry" then editInteger("Ujraprobalasi limit", "safety.retryLimit", 1, 100)
        elseif choice == "block" then
            local value = ui.input("Tomitoblokk", "Blokk", currentSettings.safety.sealBlock, function(raw)
                raw = string.lower(tostring(raw or "")):gsub("^%s+", ""):gsub("%s+$", "")
                if not string.find(raw, ":", 1, true) then raw = "minecraft:" .. raw end
                if not string.match(raw, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") then
                    return false, nil, "Formatum: <mod_neve>:<blokk_neve>"
                end
                return true, raw
            end, "Formatum: <mod_neve>:<blokk_neve>")
            currentSettings.safety.sealBlock = value
            saveSettings()
        end
    end
end

local function navigationSettings()
    while true do
        local choice = ui.menu("BEALLITASOK > NAVIGACIO", {
            { label = "Kezdo mp / muvelet", suffix = currentSettings.navigation.defaultActionSeconds, value = "time" },
            { label = "Koordinata mod", suffix = currentSettings.navigation.coordinateMode, value = "mode" },
            { label = "Fuel tartalek", suffix = currentSettings.general.fuelReserve, value = "fuel" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "fuel" then editInteger("Fuel tartalek", "general.fuelReserve", 2, 1000)
        elseif choice == "time" then
            local value = ui.input("Kezdo muveleti ido", "Masodperc", currentSettings.navigation.defaultActionSeconds, function(raw)
                local number = tonumber(raw)
                if not number or number <= 0 or number > 60 then return false, nil, "0 es 60 kozotti szam kell." end
                return true, number
            end)
            currentSettings.navigation.defaultActionSeconds = value
            saveSettings()
        elseif choice == "mode" then
            local selected = ui.choice("Koordinatas navigacio modja", {
                "Csak szabad ut", "Alagut a celig (KISERLETI)"
            }, currentSettings.navigation.coordinateMode == "dig" and 2 or 1)
            if selected then
                currentSettings.navigation.coordinateMode = selected == 2 and "dig" or "open"
                saveSettings()
            end
        end
    end
end

local function settingsMenu()
    while true do
        local choice = ui.menu("BEALLITASOK", {
            { label = "Navigacio es altalanos", value = "navigation" },
            { label = "Biztonsag es helyzetkezeles", value = "safety" },
            { label = "Inventory KISERLETI", suffix = boolText(currentSettings.inventory.experimental), value = "inventory" },
            { label = "Faklyazas", value = "torches" },
            { label = "Erckereses", value = "ores" },
            { label = "Alapertekek visszaallitasa", value = "reset" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "navigation" then navigationSettings()
        elseif choice == "safety" then safetySettings()
        elseif choice == "inventory" then toggle("inventory.experimental")
        elseif choice == "torches" then torchSettings()
        elseif choice == "ores" then oreSettings()
        elseif choice == "reset" then
            ui.confirm("ALAPERTEKEK", { "Az osszes kozponti beallitas visszaall.", "A folytatasi mentesek nem torlodnek." }, "ENTER = visszaallitas")
            local ok, reason, value = Settings.reset()
            if ok then currentSettings = value
            else ui.message("Hiba", reason, "error") ui.waitForEnter() end
        end
    end
end

local function yesNo(title, defaultValue)
    local selected = ui.choice(title, { "Kikapcsolva", "Bekapcsolva" }, defaultValue and 2 or 1)
    return selected == 2
end

local function torchConfig(config, mainAndBranch)
    config.torchEnabled = yesNo("KISERLETI faklyazas", currentSettings.torches.enabledByDefault)
    if config.torchEnabled then
        config.mainTorchInterval = ui.integer("Faklyazas", mainAndBranch and "Fout: hany beasas" or "Faklya tavolsag", currentSettings.torches.interval, 1)
        if mainAndBranch then
            config.branchTorchInterval = ui.integer("Faklyazas", "Ag: hany blokkonkent", currentSettings.torches.interval, 1)
        end
        local placement = ui.choice("Faklya helye (KISERLETI)", { "Oldalt", "Fej folott" }, currentSettings.torches.placement == "above" and 2 or 1)
        config.torchPlacementMode = placement == 2 and 2 or 1
    else
        config.mainTorchInterval, config.branchTorchInterval = 0, 0
        config.torchPlacementMode = 1
    end
end

local function launch(task, program, action, config, summary)
    if not programExists(program) then
        ui.message("Hianyzo program", program .. ".lua nem talalhato.", "error")
        ui.waitForEnter()
        return
    end
    ui.confirm("INDITASI OSSZEFOGLALO", summary, "ENTER = turtle inditasa")
    local token, reason = jobRequest.create(task, action, config)
    if not token then
        ui.message("Inditasi hiba", reason, "error")
        ui.waitForEnter()
        return
    end
    ui.clear()
    shell.run(program, "--request", token)
    ui.waitForEnter("ENTER = vissza a fomenube")
end

local function configureBranch()
    local mode = ui.choice("BRANCH MINING MOD", { "Branch 1x2", "Branch 1x3", "Egyenes 3x3" }, 1)
    if not mode then return end
    local config = { tunnelMode = mode, autoResume = false }
    config.startMode = ui.choice("INDULAS", { "Uj munka", "Kezi folytatas" }, 1)
    config.startOffset = config.startMode == 2 and ui.integer("Kezi folytatas", "Kezdo tavolsag", 64, 1) or 0
    config.mainLength = ui.integer("MERETEK", mode == 3 and "Alagut hossza" or "Fotengely", 128, 1)
    if mode == 3 then config.branchLength, config.branchSpacing = 0, 0
    else
        config.branchLength = ui.integer("MERETEK", "Oldalagat", 16, 1)
        config.branchSpacing = ui.integer("MERETEK", "Agak tavolsaga", 3, 1)
    end
    config.fuelReserve = ui.integer("UZEMANYAG", "Fuel tartalek", currentSettings.general.fuelReserve, 2)
    config.experimentalInventory = yesNo("KISERLETI inventory", currentSettings.inventory.experimental)
    torchConfig(config, mode ~= 3)
    config.oreScanEnabled = mode ~= 3 and yesNo("KISERLETI erckereses", currentSettings.ores.enabledByDefault) or false
    config.oreScanMaxDepth = currentSettings.ores.maxDepth
    config.oreScanMaxBlocks = currentSettings.ores.maxBlocks
    config.safety = currentSettings.safety
    config.defaultActionSeconds = currentSettings.navigation.defaultActionSeconds
    local name = ({ "Branch 1x2", "Branch 1x3", "Egyenes 3x3" })[mode]
    local summary = {
        "Mod: " .. name,
        "Hossz: " .. config.mainLength,
        mode == 3 and "Oldalag: nincs" or ("Oldalag: " .. config.branchLength .. ", koz: " .. config.branchSpacing),
        "Fuel tartalek: " .. config.fuelReserve,
        "Faklya: " .. boolText(config.torchEnabled),
        "Erckereses: " .. boolText(config.oreScanEnabled),
    }
    local estimate = WorkEstimator.branch(config, { mainCompleted = 0, initial = true })
    launch("branch_miner", "branch_miner", "new", config, appendEstimate(summary, estimate))
end

local function configureExcavator()
    local config = {
        autoResume = false,
        width = ui.integer("TERULET", "Szelesseg", 8, 1),
        depth = ui.integer("TERULET", "Melyseg", 16, 1),
        height = ui.integer("TERULET", "Magassag", 4, 1),
        fuelReserve = ui.integer("UZEMANYAG", "Fuel tartalek", currentSettings.general.fuelReserve, 2),
        experimentalInventory = yesNo("KISERLETI inventory", currentSettings.inventory.experimental),
    }
    config.remoteStart = { enabled = yesNo("KISERLETI koordinatas indulas", false) }
    if config.remoteStart.enabled then
        local facing = ui.choice("LADABAZIS IRANYA", {
            "Eszak (-Z)", "Kelet (+X)", "Del (+Z)", "Nyugat (-X)"
        }, 1) - 1
        local base = {
            x = ui.integer("LADABAZIS", "Vilag X", 0),
            y = ui.integer("LADABAZIS", "Vilag Y", 64),
            z = ui.integer("LADABAZIS", "Vilag Z", 0),
            heading = facing,
        }
        local work = {
            x = ui.integer("MUNKAPONT", "Vilag X", base.x),
            y = ui.integer("MUNKAPONT", "Vilag Y", base.y),
            z = ui.integer("MUNKAPONT", "Vilag Z", base.z),
        }
        local turn = ui.choice("ASAS IRANYA A KEZDO IRANYHOZ", {
            "Egyenesen", "Jobbra", "Hatra", "Balra"
        }, 1) - 1
        work.heading = (base.heading + turn) % 4
        config.remoteStart.base = base
        config.remoteStart.work = work
        config.remoteStart.relativeTurn = turn
        config.remoteStart.mode = currentSettings.navigation.coordinateMode
        config.remoteStart.axisOrder = { "y", "x", "z" }
    end
    torchConfig(config, false)
    config.torchInterval = config.mainTorchInterval
    config.safety = currentSettings.safety
    config.defaultActionSeconds = currentSettings.navigation.defaultActionSeconds
    local summary = {
        string.format("Meret: %dx%dx%d", config.width, config.depth, config.height),
        "Fuel tartalek: " .. config.fuelReserve,
        "Faklya: " .. boolText(config.torchEnabled),
    }
    if config.remoteStart.enabled then
        local base, work = config.remoteStart.base, config.remoteStart.work
        local turnNames = { "egyenesen", "jobbra", "hatra", "balra" }
        summary[#summary + 1] = string.format("Bazis: %d,%d,%d", base.x, base.y, base.z)
        summary[#summary + 1] = string.format("Munkapont: %d,%d,%d", work.x, work.y, work.z)
        summary[#summary + 1] = "Asas iranya: " .. turnNames[(config.remoteStart.relativeTurn or 0) + 1]
        summary[#summary + 1] = "Koordinata mod: " .. config.remoteStart.mode
    end
    local estimate = WorkEstimator.excavator(config, { baseCompleted = 0, visited = 0 })
    launch("excavator", "excavator", "new", config, appendEstimate(summary, estimate))
end

local function configureNether()
    local mode = ui.choice("NETHER UTEPITO", { "Lepcso fel/le", "Vedett 1x2 alagut" }, 1)
    if not mode then return end
    local config = { autoResume = false, mode = mode }
    if mode == 1 then
        config.stairDirection = ui.choice("LEPCSO IRANYA", { "Felfele", "Lefele" }, 1) == 1 and "up" or "down"
    end
    config.length = ui.integer("NETHER UTEPITO", "Hossz", 64, 1)
    config.builderBlock = ui.input("EPITOANYAG", "Blokk", "minecraft:cobblestone", function(raw)
        raw = string.lower(tostring(raw or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if not string.find(raw, ":", 1, true) then raw = "minecraft:" .. raw end
        if not string.match(raw, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") then return false, nil, "Hibas blokkformatum." end
        return true, raw
    end, "Formatum: <mod_neve>:<blokk_neve>")
    config.fuelReserve = ui.integer("UZEMANYAG", "Fuel tartalek", math.max(4, currentSettings.general.fuelReserve), 4)
    config.torchEnabled = yesNo("KISERLETI faklyazas", currentSettings.torches.enabledByDefault)
    config.torchInterval = config.torchEnabled and ui.integer("FAKLYAZAS", "Faklya tavolsag", currentSettings.torches.interval, 1) or 0
    config.safety = currentSettings.safety
    config.defaultActionSeconds = currentSettings.navigation.defaultActionSeconds
    local summary = {
        "Mod: " .. (mode == 1 and ("lepcso " .. config.stairDirection) or "vedett 1x2"),
        "Hossz: " .. config.length,
        "Epitoanyag: " .. config.builderBlock,
        "Faklya: " .. boolText(config.torchEnabled),
    }
    local estimate = WorkEstimator.nether(config, { completed = 0, pathLength = 0 })
    launch("nether_builder", "nether_builder", "new", config, appendEstimate(summary, estimate))
end

local function coordinateTask()
    local facing = ui.choice("JELENLEGI FACING", { "Eszak (-Z)", "Kelet (+X)", "Del (+Z)", "Nyugat (-X)" }, 1)
    if not facing then return end
    local start = {
        x = ui.integer("JELENLEGI HELY", "Vilag X", 0),
        y = ui.integer("JELENLEGI HELY", "Vilag Y", 64),
        z = ui.integer("JELENLEGI HELY", "Vilag Z", 0),
        heading = facing - 1,
    }
    local target = {
        x = ui.integer("CEL", "Cel X", start.x),
        y = ui.integer("CEL", "Cel Y", start.y),
        z = ui.integer("CEL", "Cel Z", start.z),
    }
    local finalFacing = ui.choice("VEGSO FACING", { "Mindegy", "Eszak", "Kelet", "Del", "Nyugat" }, 1)
    if finalFacing and finalFacing > 1 then target.heading = finalFacing - 2 end
    local estimate = WorkEstimator.coordinate(start, target)
    local config = {
        start = start,
        target = target,
        axisOrder = currentSettings.navigation.coordinateAxisOrder,
        mode = currentSettings.navigation.coordinateMode,
        fuelReserve = currentSettings.general.fuelReserve,
        defaultActionSeconds = currentSettings.navigation.defaultActionSeconds,
        safety = currentSettings.safety,
    }
    local summary = {
        string.format("Start: %d, %d, %d", start.x, start.y, start.z),
        string.format("Cel:   %d, %d, %d", target.x, target.y, target.z),
        "Mod: " .. config.mode .. " (KISERLETI)",
    }
    launch("coordinate", "coordinate_task", "new", config, appendEstimate(summary, estimate))
end

local function resumeMenu()
    local jobs = {
        { label = "Branch mining", task = "branch_miner", program = "branch_miner", state = "branch_miner_state.txt" },
        { label = "Terulet asas", task = "excavator", program = "excavator", state = "excavator_state.txt" },
        { label = "Nether utepito", task = "nether_builder", program = "nether_builder", state = "nether_builder_state.txt" },
        { label = "Koordinatas navigacio", task = "coordinate", program = "coordinate_task", state = "coordinate_state.txt" },
    }
    local items = {}
    for _, job in ipairs(jobs) do
        if activeState(job.state) then items[#items + 1] = { label = job.label, value = job } end
    end
    items[#items + 1] = { label = "Vissza", value = "back" }
    local selected = ui.menu("FOLYTATHATO MUNKAK", items)
    if not selected or selected == "back" then return end
    launch(selected.task, selected.program, "resume", {}, { selected.label, "A mentett allapot folytatasa." })
end

local function diagnostics()
    local modules = { "ui", "settings", "state_store", "navigation", "coordinate_navigation", "situation_manager", "telemetry", "work_estimator", "inventory_manager", "torch_manager", "ore_scanner" }
    local lines = {}
    for _, name in ipairs(modules) do
        local ok = pcall(require, name)
        lines[#lines + 1] = (ok and "[OK] " or "[HIBA] ") .. name
    end
    lines[#lines + 1] = "Fuel: " .. tostring(turtle.getFuelLevel())
    ui.message("DIAGNOSZTIKA", lines)
    ui.waitForEnter()
end

local function menuLoop()
    while true do
        local hasResume = activeState("branch_miner_state.txt")
            or activeState("excavator_state.txt")
            or activeState("nether_builder_state.txt")
            or activeState("coordinate_state.txt")
        local choice = ui.menu("CCTURTLE", {
            { label = "Branch mining", value = "branch" },
            { label = "Terulet kiasasa", suffix = "KISERLETI", value = "excavator" },
            { label = "Nether utepito", value = "nether" },
            { label = "Koordinatara navigalas", suffix = "KISERLETI", value = "coordinate" },
            { label = "Felbehagyott munka", enabled = hasResume, value = "resume" },
            { label = "Beallitasok", value = "settings" },
            { label = "Diagnosztika", value = "diagnostics" },
            { label = "Kilepes", value = "exit" },
        }, { allowBack = false })
        if choice == "branch" then configureBranch()
        elseif choice == "excavator" then configureExcavator()
        elseif choice == "nether" then configureNether()
        elseif choice == "coordinate" then coordinateTask()
        elseif choice == "resume" then resumeMenu()
        elseif choice == "settings" then settingsMenu()
        elseif choice == "diagnostics" then diagnostics()
        elseif choice == "exit" then ui.clear() return end
    end
end

if remoteOk and Remote and parallel then
    parallel.waitForAny(menuLoop, Remote.run)
else
    menuLoop()
end
