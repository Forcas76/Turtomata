-- Turtomata kozponti belepesi pont.

local ui = require("ui")
local Settings = require("settings")
local stateStore = require("state_store")
local jobRequest = require("job_request")
local WorkEstimator = require("work_estimator")
local Version = require("version")
local Localization = require("localization")
local WorkRegistry = require("work_registry")
local JobPreview = require("job_preview")
local JobSetup = require("job_setup")
local ChainEditor = require("chain_editor")

local currentSettings = Settings.load()
Localization.setLanguage(currentSettings.general.language)
local remoteOk, Remote = pcall(require, "remote")
local REMOTE_ACTIVE_FILE = ".remote_active_job"
if fs.exists(REMOTE_ACTIVE_FILE) then fs.delete(REMOTE_ACTIVE_FILE) end

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
    if value == nil then return end
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
            if value then currentSettings.safety.sealBlock = value saveSettings() end
        end
    end
end

local function navigationSettings()
    while true do
        local choice = ui.menu("BEALLITASOK > NAVIGACIO", {
            { label = "Kezdo mp / muvelet", suffix = currentSettings.navigation.defaultActionSeconds, value = "time" },
            { label = "Koordinata mod", suffix = currentSettings.navigation.coordinateMode, value = "mode" },
            { label = "Fuel tartalek", suffix = currentSettings.general.fuelReserve, value = "fuel" },
            { label = "Auto folytatas alap", suffix = boolText(currentSettings.general.autoResumeDefault), value = "auto" },
            { label = "Kozos bazis", suffix = string.format("%d,%d,%d",
                currentSettings.navigation.base.x,
                currentSettings.navigation.base.y,
                currentSettings.navigation.base.z), value = "base" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "fuel" then editInteger("Fuel tartalek", "general.fuelReserve", 2, 1000)
        elseif choice == "auto" then toggle("general.autoResumeDefault")
        elseif choice == "base" then
            local base = currentSettings.navigation.base
            while true do
                local field = ui.menu("KOZOS BAZIS", {
                    { label = "X", suffix = base.x, value = "x" },
                    { label = "Y", suffix = base.y, value = "y" },
                    { label = "Z", suffix = base.z, value = "z" },
                    { label = "Irany", suffix = base.heading, value = "heading" },
                    { label = "Vissza", value = "back" },
                })
                if not field or field == "back" then break end
                if field == "heading" then
                    local selected = ui.choice("BAZIS IRANY",
                        { "Eszak", "Kelet", "Del", "Nyugat" },
                        base.heading + 1)
                    if selected then base.heading = selected - 1 saveSettings() end
                else
                    local value = ui.integer("BAZIS " .. field:upper(),
                        field:upper(), base[field])
                    if value ~= nil then base[field] = value saveSettings() end
                end
            end
        elseif choice == "time" then
            local value = ui.input("Kezdo muveleti ido", "Masodperc", currentSettings.navigation.defaultActionSeconds, function(raw)
                local number = tonumber(raw)
                if not number or number <= 0 or number > 60 then return false, nil, "0 es 60 kozotti szam kell." end
                return true, number
            end)
            if value then currentSettings.navigation.defaultActionSeconds = value saveSettings() end
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
            { label = "Nyelv / Language", suffix = currentSettings.general.language == "en" and "English" or "Magyar", value = "language" },
            { label = "Navigacio es altalanos", value = "navigation" },
            { label = "Biztonsag es helyzetkezeles", value = "safety" },
            { label = "Inventory KISERLETI", suffix = boolText(currentSettings.inventory.experimental), value = "inventory" },
            { label = "Faklyazas", value = "torches" },
            { label = "Erckereses", value = "ores" },
            { label = "Alapertekek visszaallitasa", value = "reset" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "language" then
            local selected = ui.choice("Nyelv / Language", { "Magyar", "Angol" },
                currentSettings.general.language == "en" and 2 or 1)
            if selected then
                currentSettings.general.language = selected == 2 and "en" or "hu"
                saveSettings()
                Localization.setLanguage(currentSettings.general.language)
            end
        elseif choice == "navigation" then navigationSettings()
        elseif choice == "safety" then safetySettings()
        elseif choice == "inventory" then toggle("inventory.experimental")
        elseif choice == "torches" then torchSettings()
        elseif choice == "ores" then oreSettings()
        elseif choice == "reset" then
            if ui.confirm("ALAPERTEKEK", { "Az osszes kozponti beallitas visszaall.", "A folytatasi mentesek nem torlodnek." }, "ENTER = visszaallitas") then
                local ok, reason, value = Settings.reset()
                if ok then
                    currentSettings = value
                    Localization.setLanguage(currentSettings.general.language)
                else ui.message("Hiba", reason, "error") ui.waitForEnter() end
            end
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

local function launch(task, program, action, config, summary, options)
    options = options or {}
    if not programExists(program) then
        ui.message("Hianyzo program", program .. ".lua nem talalhato.", "error")
        ui.waitForEnter()
        return
    end
    if not options.auto and not options.confirmed
        and not ui.confirm("INDITASI OSSZEFOGLALO", summary,
        "ENTER = turtle inditasa") then return end
    if action == "new" then
        local registered, registerReason = WorkRegistry.start(task,
            config and config.resumeOnStartup)
        if not registered then
            ui.message("Munka utkozes", registerReason, "error")
            ui.waitForEnter()
            return
        end
    elseif not options.auto then
        local allowed, resumeReason = WorkRegistry.resume(task)
        if not allowed then
            ui.message("Munka utkozes", resumeReason, "error")
            ui.waitForEnter()
            return
        end
    end
    local token, reason = jobRequest.create(task, action, config)
    if not token then
        WorkRegistry.update("needs_attention", reason)
        ui.message("Inditasi hiba", reason, "error")
        ui.waitForEnter()
        return
    end
    ui.clear()
    stateStore.write(REMOTE_ACTIVE_FILE, {
        task = task, program = program, action = action, config = config,
    })
    local success = shell.run(program, "--request", token)
    if fs.exists(REMOTE_ACTIVE_FILE) then fs.delete(REMOTE_ACTIVE_FILE) end
    local saved = stateStore.read(WorkRegistry.stateFile(task) or "")
    if type(saved) == "table" and saved.active == false then
        WorkRegistry.update("completed")
    elseif type(saved) == "table" and
        (saved.activity == "megallitva_otthon"
            or saved.phase == "megallitva_otthon"
            or saved.phase == "megallitva") then
        WorkRegistry.update("paused")
    elseif type(saved) == "table" and saved.phase == "needs_supplies" then
        WorkRegistry.update("needs_supplies", saved.lastError)
    else
        WorkRegistry.update("needs_attention",
            success and "A feladat aktiv mentesben maradt." or "A program hibaval tert vissza.")
    end
    if not options.auto then ui.waitForEnter("ENTER = vissza a fomenube") end
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
    config.resumeOnStartup = yesNo("Automatikus folytatas indulasnal", currentSettings.general.autoResumeDefault)
    local name = ({ "Branch 1x2", "Branch 1x3", "Egyenes 3x3" })[mode]
    local summary = {
        "Mod: " .. name,
        "Hossz: " .. config.mainLength,
        mode == 3 and "Oldalag: nincs" or ("Oldalag: " .. config.branchLength .. ", koz: " .. config.branchSpacing),
        "Fuel tartalek: " .. config.fuelReserve,
        "Faklya: " .. boolText(config.torchEnabled),
        "Erckereses: " .. boolText(config.oreScanEnabled),
        "Auto folytatas: " .. boolText(config.resumeOnStartup),
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
    config.resumeOnStartup = yesNo("Automatikus folytatas indulasnal", currentSettings.general.autoResumeDefault)
    local summary = {
        string.format("Meret: %dx%dx%d", config.width, config.depth, config.height),
        "Fuel tartalek: " .. config.fuelReserve,
        "Faklya: " .. boolText(config.torchEnabled),
        "Auto folytatas: " .. boolText(config.resumeOnStartup),
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
    local mode = ui.choice("UTVONAL KESZITES", { "Lepcso fel/le", "Vedett 1x2 alagut", "Sima 1x2 alagut" }, 1)
    if not mode then return end
    local config = { autoResume = false, mode = mode }
    if mode == 1 then
        config.stairDirection = ui.choice("LEPCSO IRANYA", { "Felfele", "Lefele" }, 1) == 1 and "up" or "down"
    end
    config.length = ui.integer("UTVONAL KESZITES", "Hossz", 64, 1)
    if mode == 3 then
        config.builderBlock = "minecraft:cobblestone"
    else
        config.builderBlock = ui.input("EPITOANYAG", "Blokk", "minecraft:cobblestone", function(raw)
            raw = string.lower(tostring(raw or "")):gsub("^%s+", ""):gsub("%s+$", "")
            if not string.find(raw, ":", 1, true) then raw = "minecraft:" .. raw end
            if not string.match(raw, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") then return false, nil, "Hibas blokkformatum." end
            return true, raw
        end, "Formatum: <mod_neve>:<blokk_neve>")
    end
    config.fuelReserve = ui.integer("UZEMANYAG", "Fuel tartalek", math.max(4, currentSettings.general.fuelReserve), 4)
    config.torchEnabled = yesNo("KISERLETI faklyazas", currentSettings.torches.enabledByDefault)
    config.torchInterval = config.torchEnabled and ui.integer("FAKLYAZAS", "Faklya tavolsag", currentSettings.torches.interval, 1) or 0
    config.safety = currentSettings.safety
    config.defaultActionSeconds = currentSettings.navigation.defaultActionSeconds
    config.resumeOnStartup = yesNo("Automatikus folytatas indulasnal", currentSettings.general.autoResumeDefault)
    local summary = {
        "Mod: " .. (mode == 1 and ("lepcso " .. config.stairDirection)
            or mode == 2 and "vedett 1x2" or "sima 1x2"),
        "Hossz: " .. config.length,
        "Epitoanyag: " .. config.builderBlock,
        "Faklya: " .. boolText(config.torchEnabled),
        "Auto folytatas: " .. boolText(config.resumeOnStartup),
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
    config.resumeOnStartup = yesNo("Automatikus folytatas indulasnal", currentSettings.general.autoResumeDefault)
    local summary = {
        string.format("Start: %d, %d, %d", start.x, start.y, start.z),
        string.format("Cel:   %d, %d, %d", target.x, target.y, target.z),
        "Mod: " .. config.mode .. " (KISERLETI)",
        "Auto folytatas: " .. boolText(config.resumeOnStartup),
    }
    launch("coordinate", "coordinate_task", "new", config, appendEstimate(summary, estimate))
end

local function resumeMenu()
    local jobs = JobPreview.list()
    local items = {}
    for _, job in ipairs(jobs) do
        items[#items + 1] = {
            label = job.label, suffix = job.progress, value = job,
        }
    end
    items[#items + 1] = { label = "Vissza", value = "back" }
    local selected = ui.menu("FOLYTATHATO MUNKAK", items)
    if not selected or selected == "back" then return end
    local lines = JobPreview.describe(selected, selected.saved)
    if not ui.confirm("MENTETT MUNKA", lines, "ENTER = folytatas") then return end
    launch(selected.task, selected.program, "resume", {}, lines, { confirmed = true })
end

local function workControl()
    while true do
        local owner = WorkRegistry.load()
        local savedJobs = JobPreview.list()
        local items = {}
        if owner then
            items[#items + 1] = { label = "Tulajdonos", suffix = owner.task,
                enabled = false, value = "owner" }
            items[#items + 1] = { label = "Allapot", suffix = owner.status,
                enabled = false, value = "status" }
            items[#items + 1] = { label = "Auto folytatas",
                suffix = boolText(owner.autoResume), value = "auto" }
            items[#items + 1] = { label = "Munka felszabaditasa",
                value = "release" }
        end
        if owner or #savedJobs > 0 then
            items[#items + 1] = { label = "Mentett munka torlese", value = "delete" }
        else
            items[#items + 1] = { label = "Nincs mentett munka",
                enabled = false, value = "empty" }
        end
        items[#items + 1] = { label = "Vissza", value = "back" }
        local selected = ui.menu("MUNKA KEZELES", items)
        if not selected or selected == "back" then return end
        if selected == "auto" then
            WorkRegistry.setAutoResume(not owner.autoResume)
        elseif selected == "release" then
            if ui.confirm("FELSZABADITAS", {
                "A mentes megmarad, de nem indul automatikusan.",
                "Csak akkor tedd, ha a turtle a bazison all.",
                "Uj munka inditasa utan a regit nem folytathatod",
                "a masik aktiv munka lezarasa nelkul.",
            }, "ENTER = felszabaditas") then
                WorkRegistry.release()
                return
            end
        elseif selected == "delete" then
            local choices, listed = {}, {}
            for _, job in ipairs(savedJobs) do
                choices[#choices + 1] = { label = job.label,
                    suffix = job.progress, value = job }
                listed[job.task] = true
            end
            if owner and not listed[owner.task] then
                choices[#choices + 1] = { label = owner.task,
                    suffix = owner.status,
                    value = { task = owner.task, label = owner.task } }
            end
            choices[#choices + 1] = { label = "Vissza", value = "back" }
            local job = ui.menu("MENTES TORLESE", choices)
            if job and job ~= "back" then
                local lines = {
                    Localization.text("Feladat: ") .. job.label,
                    Localization.text("Haladas: ")
                        .. tostring(job.progress or "ismeretlen"),
                    "A folytatasi mentes vegleg torlodik.",
                    "Csak bazison allo turtle-n hasznald!",
                }
                if job.task == "chain" then
                    lines[#lines + 1] = "Az aktiv reszfeladat mentese is torlodik."
                end
                if ui.confirm("MENTES VEGLEGES TORLESE", lines,
                    "ENTER = torles") then
                    local ok, reason = WorkRegistry.deleteSaved(job.task)
                    ui.message(ok and "MENTES TOROLVE" or "TORLESI HIBA",
                        ok and "A mentes torolve." or tostring(reason),
                        ok and nil or "error")
                    ui.waitForEnter()
                end
            end
        end
    end
end

local function diagnostics()
    local modules = { "ui", "settings", "state_store", "navigation",
        "coordinate_navigation", "situation_manager", "telemetry",
        "work_estimator", "inventory_manager", "torch_manager",
        "ore_scanner", "work_registry", "job_preview", "job_setup",
        "base_dock", "chain_editor" }
    local lines = {}
    for _, name in ipairs(modules) do
        local ok = pcall(require, name)
        lines[#lines + 1] = (ok and "[OK] " or "[HIBA] ") .. name
    end
    lines[#lines + 1] = "Fuel: " .. tostring(turtle.getFuelLevel())
    ui.message("DIAGNOSZTIKA", lines)
    ui.waitForEnter()
end

local function updateTurtleProgram()
    if not programExists("downloader") then
        ui.message("Hianyzo program", "downloader nem talalhato.", "error")
        ui.waitForEnter()
        return
    end
    if not ui.confirm("Program frissitese", {
        "A teljes turtle program frissul.",
        "Siker utan az eszkoz ujraindul.",
    }, "ENTER = frissites") then return end
    ui.message("Program frissitese...", "Kerlek varj.")
    local ok = shell.run("downloader", "turtle")
    if ok then
        ui.message("Frissites kesz. Ujrainditas...", "")
        sleep(1)
        os.reboot()
    else
        ui.message("A frissites sikertelen.", "Ellenorizd a downloader uzeneteit.", "error")
        ui.waitForEnter()
    end
end

local function menuLoop()
    local auto = WorkRegistry.autoCandidate()
    if auto then
        local programs = {
            branch_miner = "branch_miner", excavator = "excavator",
            nether_builder = "nether_builder", coordinate = "coordinate_task",
            farm = "farm_task",
            chain = "task_chain",
        }
        local program = programs[auto.task]
        if program then
            ui.message("AUTO FOLYTATAS", { auto.task, "Mentett feladat helyreallitasa..." })
            launch(auto.task, program, "resume", {}, {}, { auto = true })
        end
    end
    while true do
        local hasResume = #JobPreview.list() > 0
        local choice = ui.menu("TURTOMATA " .. Version.label, {
            { label = "Branch mining", value = "branch" },
            { label = "Terulet kiasasa", suffix = "KISERLETI", value = "excavator" },
            { label = "Utvonal keszites", value = "nether" },
            { label = "Koordinatara navigalas", suffix = "KISERLETI", value = "coordinate" },
            { label = "Farm karbantartas", suffix = "KISERLETI", value = "farm" },
            { label = "Feladatlanc", suffix = "KISERLETI", value = "chain" },
            { label = "Felbehagyott munka", enabled = hasResume, value = "resume" },
            { label = "Munka kezelese", value = "work" },
            { label = "Beallitasok", value = "settings" },
            { label = "Diagnosztika", value = "diagnostics" },
            { label = "Program frissitese", value = "update" },
            { label = "Kilepes", value = "exit" },
        }, { allowBack = false })
        if choice == "branch" then
            local config, summary = JobSetup.branch(currentSettings)
            if config then launch("branch_miner", "branch_miner", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "excavator" then
            local config, summary = JobSetup.excavator(currentSettings)
            if config then launch("excavator", "excavator", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "nether" then
            local config, summary = JobSetup.nether(currentSettings)
            if config then launch("nether_builder", "nether_builder", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "coordinate" then
            local config, summary = JobSetup.coordinate(currentSettings)
            if config then launch("coordinate", "coordinate_task", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "farm" then
            local config, summary = JobSetup.farm(currentSettings)
            if config then launch("farm", "farm_task", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "chain" then
            local config, summary = ChainEditor.open(currentSettings)
            if config then launch("chain", "task_chain", "new",
                config, summary, { confirmed = true }) end
        elseif choice == "resume" then resumeMenu()
        elseif choice == "work" then workControl()
        elseif choice == "settings" then settingsMenu()
        elseif choice == "diagnostics" then diagnostics()
        elseif choice == "update" then updateTurtleProgram()
        elseif choice == "exit" then ui.clear() return end
    end
end

if remoteOk and Remote and parallel then
    parallel.waitForAny(menuLoop, Remote.run)
else
    menuLoop()
end
