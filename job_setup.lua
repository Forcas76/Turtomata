-- V2: szerkesztheto, visszalepheto feladatlapok a kozponti menuhöz.
local ui = require("ui")
local Estimator = require("work_estimator")
local Telemetry = require("telemetry")
local Store = require("state_store")
local setup = {}
local function defaultBase(settings)
    return Store.clone(settings.navigation.base
        or { x = 0, y = 64, z = 0, heading = 0 })
end

local function yn(value) return value and "BE" or "KI" end
local function bool(title, value)
    local choice = ui.choice(title, { "KI", "BE" }, value and 2 or 1)
    if choice == nil then return nil end
    return choice == 2
end
local function number(title, value, minimum)
    return ui.integer(title, title, value, minimum)
end
local function namedBlock(title, value)
    return ui.input(title, "Blokk", value, function(raw)
        raw = tostring(raw or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if not raw:find(":", 1, true) then raw = "minecraft:" .. raw end
        if not raw:match("^[a-z0-9_.-]+:[a-z0-9_./-]+$") then
            return false, nil, "Formatum: mod:blokk"
        end
        return true, raw
    end, "Formatum: mod:blokk")
end
local function field(label, get, edit, enabled)
    return { label = label, get = get, edit = edit, enabled = enabled }
end
local function appendEstimate(lines, estimate, seconds)
    for _, formula in ipairs(estimate.formula or {}) do
        lines[#lines + 1] = "Keplet: " .. formula
    end
    lines[#lines + 1] = "Muveletek: " .. tostring(estimate.totalActions)
    lines[#lines + 1] = "Kb. ido: " .. Telemetry.formatDuration(
        Estimator.durationMs(estimate, seconds or 0.8))
    return lines
end
local function editCard(title, config, fields, summary)
    while true do
        local items, visible = {}, {}
        for _, option in ipairs(fields) do
            if not option.enabled or option.enabled(config) then
                visible[#visible + 1] = option
                items[#items + 1] = {
                    label = option.label, suffix = tostring(option.get(config)),
                    value = #visible,
                }
            end
        end
        items[#items + 1] = { label = "Attekintes / inditas", value = "start" }
        items[#items + 1] = { label = "Vissza", value = "back" }
        local choice = ui.menu(title, items)
        if not choice or choice == "back" then return nil end
        if choice == "start" then
            local lines, problem = summary(config)
            if not lines then
                ui.message("BEALLITASI HIBA", tostring(problem), "error")
                ui.waitForEnter()
            elseif ui.confirm("FELADAT ATTEKINTES", lines, "ENTER = inditas") then
                return config, lines
            end
        else
            visible[choice].edit(config)
        end
    end
end
local function integerField(label, key, minimum, enabled)
    return field(label, function(c) return c[key] end, function(c)
        local value = number(label, c[key], minimum)
        if value ~= nil then c[key] = value end
    end, enabled)
end
local function boolField(label, key, enabled)
    return field(label, function(c) return yn(c[key]) end, function(c)
        local value = bool(label, c[key])
        if value ~= nil then c[key] = value end
    end, enabled)
end
local function common(c, settings)
    c.fuelReserve = settings.general.fuelReserve
    c.resumeOnStartup = settings.general.autoResumeDefault
    c.safety = settings.safety
    c.defaultActionSeconds = settings.navigation.defaultActionSeconds
    return c
end
local function baseFields()
    return {
        integerField("Fuel tartalek", "fuelReserve", 2),
        boolField("Auto folytatas", "resumeOnStartup"),
    }
end
local function addFields(target, others)
    for _, item in ipairs(others) do target[#target + 1] = item end
    return target
end
local function facingField(label, key, container)
    return field(label, function(c)
        return ({ "Eszak", "Kelet", "Del", "Nyugat" })
            [(container and c[container][key] or c[key]) + 1]
    end, function(c)
        local holder = container and c[container] or c
        local choice = ui.choice(label, { "Eszak", "Kelet", "Del", "Nyugat" },
            holder[key] + 1)
        if choice then holder[key] = choice - 1 end
    end)
end

function setup.branch(settings, existing)
    while true do
        local mode = ui.choice("BRANCH MOD", { "Branch 1x2", "Branch 1x3", "Egyenes 3x3" },
            existing and existing.tunnelMode or 1)
        if not mode then return nil end
        local shared = false
        if mode ~= 3 then
            local workMode = ui.choice("MUNKA MODJA", { "Egyeduli", "Kozos" },
                existing and existing.sharedMode and 2 or 1)
            if not workMode then return nil end
            shared = workMode == 2
            if shared then
                local role = ui.choice("KOZOS BRANCH", {
                    "Uj munka (vezeto)", "Csatlakozas (seged)",
                    "Allapot / folytatas",
                }, 1)
                if not role then return nil end
                if role == 2 then return "shared_join" end
                if role == 3 then return "shared_manage" end
            end
        end
        local c = common({
            tunnelMode = mode, sharedMode = shared,
            autoResume = false, startMode = 1,
            startOffset = 0, mainLength = 128, branchLength = 16,
            branchSpacing = 3, experimentalInventory = settings.inventory.experimental,
            unloadMode = "auto",
            torchEnabled = settings.torches.enabledByDefault,
            mainTorchInterval = settings.torches.interval,
            branchTorchInterval = settings.torches.interval,
            torchPlacementMode = settings.torches.placement == "above" and 2 or 1,
            oreScanEnabled = mode ~= 3 and settings.ores.enabledByDefault or false,
            oreScanMaxDepth = settings.ores.maxDepth,
            oreScanMaxBlocks = settings.ores.maxBlocks,
        }, settings)
        if existing and existing.tunnelMode == mode then
            c = Store.clone(existing)
            c.sharedMode = shared
        end
        local fields = {
            boolField("Kezi kezdoeltolas", "manualStart",
                function() return not shared end),
            integerField("Kezdo tavolsag", "startOffset", 1,
                function(v) return not shared and v.manualStart end),
            integerField("Fout hossza", "mainLength", 1),
            integerField("Oldalag hossza", "branchLength", 1,
                function() return mode ~= 3 end),
            integerField("Agkoz", "branchSpacing", 1,
                function() return mode ~= 3 end),
            boolField("Kiserleti inventory", "experimentalInventory"),
            field("Lepakolas", function(v)
                return v.unloadMode == "primary" and "csak kozos" or "auto"
            end, function(v)
                local selected = ui.choice("LEPAKOLAS", {
                    "Automatikus lada", "Csak kozos lada",
                }, v.unloadMode == "primary" and 2 or 1)
                if selected then
                    v.unloadMode = selected == 2 and "primary" or "auto"
                end
            end, function() return shared end),
            boolField("Faklyazas", "torchEnabled"),
            integerField("Fout faklya", "mainTorchInterval", 1,
                function(v) return v.torchEnabled end),
            integerField("Ag faklya", "branchTorchInterval", 1,
                function(v) return mode ~= 3 and v.torchEnabled end),
            field("Faklya helye", function(v)
                return v.torchPlacementMode == 2 and "fej folott" or "oldalt"
            end, function(v)
                local choice = ui.choice("FAKLYA HELYE", { "Oldalt", "Fej folott" },
                    v.torchPlacementMode)
                if choice then v.torchPlacementMode = choice end
            end, function(v) return v.torchEnabled end),
            boolField("Erckereses", "oreScanEnabled",
                function() return mode ~= 3 end),
            integerField("Erc max melyseg", "oreScanMaxDepth", 1,
                function(v) return v.oreScanEnabled end),
            integerField("Erc max blokk", "oreScanMaxBlocks", 1,
                function(v) return v.oreScanEnabled end),
        }
        addFields(fields, baseFields())
        local config, lines = editCard("BRANCH ADATLAP", c, fields, function(v)
            if shared and v.oreScanEnabled and v.torchEnabled
                and (v.branchTorchInterval or 0) > 0
                and math.floor(v.branchLength / v.branchTorchInterval) > 64 then
                return nil, "Kozos erc-visszauton legfeljebb 64 faklyapont lehet. Noveldd a tavolsagot."
            end
            if shared then v.manualStart = false end
            v.startMode = v.manualStart and 2 or 1
            if not v.manualStart then v.startOffset = 0 end
            if mode == 3 then v.branchLength, v.branchSpacing = 0, 0 end
            if v.oreScanEnabled then
                local profile = Store.read("ore_targets.txt")
                v.oreTargets = type(profile) == "table"
                    and Store.clone(profile.selected or {}) or {}
            else
                v.oreTargets = nil
            end
            local lines = {
                "Mod: " .. ({ "1x2", "1x3", "3x3" })[mode],
                "Munka: " .. (v.sharedMode and "kozos" or "egyeduli"),
                "Fout: " .. v.mainLength,
                "Oldalag/koz: " .. v.branchLength .. "/" .. v.branchSpacing,
                "Kezdoeltolas: " .. v.startOffset,
                "Fuel: " .. v.fuelReserve,
                "Faklya/erc/inv: " .. yn(v.torchEnabled) .. "/"
                    .. yn(v.oreScanEnabled) .. "/" .. yn(v.experimentalInventory),
                "Lepakolas: " .. (v.unloadMode == "primary"
                    and "kozos" or "automatikus"),
                "Auto folytatas: " .. yn(v.resumeOnStartup),
            }
            return appendEstimate(lines, Estimator.branch(v,
                { mainCompleted = 0, initial = true }), v.defaultActionSeconds)
        end)
        if config then return config, lines end
    end
end

function setup.excavator(settings, existing)
    local c = common({
        autoResume = false, width = 8, depth = 16, height = 4,
        experimentalInventory = settings.inventory.experimental,
        torchEnabled = settings.torches.enabledByDefault,
        mainTorchInterval = settings.torches.interval,
        torchPlacementMode = settings.torches.placement == "above" and 2 or 1,
        remoteStart = { enabled = false,
            base = defaultBase(settings),
            work = defaultBase(settings),
            relativeTurn = 0,
        },
    }, settings)
    if existing then c = Store.clone(existing) end
    local fields = {
        integerField("Szelesseg", "width", 1),
        integerField("Melyseg", "depth", 1),
        integerField("Magassag", "height", 1),
        boolField("Kiserleti inventory", "experimentalInventory"),
        boolField("Faklyazas", "torchEnabled"),
        integerField("Faklya tavolsag", "mainTorchInterval", 1,
            function(v) return v.torchEnabled end),
        field("Tavoli munkapont", function(v) return yn(v.remoteStart.enabled) end,
            function(v)
                local value = bool("TAVOLI MUNKAPONT", v.remoteStart.enabled)
                if value ~= nil then v.remoteStart.enabled = value end
            end),
    }
    for _, place in ipairs({ "base", "work" }) do
        for _, axis in ipairs({ "x", "y", "z" }) do
            local label = (place == "base" and "Bazis " or "Munka ") .. axis:upper()
            fields[#fields + 1] = field(label,
                function(v) return v.remoteStart[place][axis] end,
                function(v)
                    local holder = v.remoteStart[place]
                    local value = number(label, holder[axis])
                    if value ~= nil then holder[axis] = value end
                end, function(v) return v.remoteStart.enabled end)
        end
    end
    fields[#fields + 1] = field("Bazis facing",
        function(v) return v.remoteStart.base.heading end, function(v)
            local selected = ui.choice("BAZIS FACING",
                { "Eszak", "Kelet", "Del", "Nyugat" },
                v.remoteStart.base.heading + 1)
            if selected then v.remoteStart.base.heading = selected - 1 end
        end, function(v) return v.remoteStart.enabled end)
    fields[#fields + 1] = field("Asas iranya",
        function(v) return ({ "elore", "jobbra", "hatra", "balra" })
            [v.remoteStart.relativeTurn + 1] end, function(v)
            local selected = ui.choice("ASAS IRANYA",
                { "Elore", "Jobbra", "Hatra", "Balra" },
                v.remoteStart.relativeTurn + 1)
            if selected then v.remoteStart.relativeTurn = selected - 1 end
        end, function(v) return v.remoteStart.enabled end)
    addFields(fields, baseFields())
    return editCard("TERULET ADATLAP", c, fields, function(v)
        v.torchInterval = v.torchEnabled and v.mainTorchInterval or 0
        if v.remoteStart.enabled then
            v.remoteStart.work.heading = (v.remoteStart.base.heading
                + v.remoteStart.relativeTurn) % 4
            v.remoteStart.mode = settings.navigation.coordinateMode
            v.remoteStart.axisOrder = { "y", "x", "z" }
        end
        local lines = {
            string.format("Meret: %dx%dx%d", v.width, v.depth, v.height),
            "Fuel: " .. v.fuelReserve,
            "Faklya/inv: " .. yn(v.torchEnabled) .. "/"
                .. yn(v.experimentalInventory),
            "Auto folytatas: " .. yn(v.resumeOnStartup),
        }
        if v.remoteStart.enabled then
            lines[#lines + 1] = string.format("Bazis: %d,%d,%d",
                v.remoteStart.base.x, v.remoteStart.base.y, v.remoteStart.base.z)
            lines[#lines + 1] = string.format("Munkapont: %d,%d,%d",
                v.remoteStart.work.x, v.remoteStart.work.y, v.remoteStart.work.z)
        end
        return appendEstimate(lines, Estimator.excavator(v,
            { baseCompleted = 0, visited = 0 }), v.defaultActionSeconds)
    end)
end

function setup.nether(settings, existing)
    while true do
        local mode = ui.choice("UTVONAL MOD",
            { "Lepcso fel/le", "Vedett 1x2", "Sima 1x2" },
            existing and existing.mode or 1)
        if not mode then return nil end
        local c = common({
            autoResume = false, mode = mode, stairDirection = "up",
            length = 64, builderBlock = "minecraft:cobblestone",
            torchEnabled = settings.torches.enabledByDefault,
            torchInterval = settings.torches.interval,
        }, settings)
        if existing and existing.mode == mode then c = Store.clone(existing) end
        local fields = {
            field("Lepcso iranya", function(v) return v.stairDirection end,
                function(v)
                    local choice = ui.choice("LEPCSO IRANY",
                        { "Felfele", "Lefele" },
                        v.stairDirection == "up" and 1 or 2)
                    if choice then v.stairDirection = choice == 1 and "up" or "down" end
                end, function() return mode == 1 end),
            integerField("Hossz", "length", 1),
            field("Epitoanyag", function(v) return v.builderBlock end,
                function(v)
                    local value = namedBlock("EPITOANYAG", v.builderBlock)
                    if value then v.builderBlock = value end
                end, function() return mode ~= 3 end),
            boolField("Faklyazas", "torchEnabled"),
            integerField("Faklya tavolsag", "torchInterval", 1,
                function(v) return v.torchEnabled end),
        }
        addFields(fields, baseFields())
        local config, lines = editCard("UTVONAL ADATLAP", c, fields, function(v)
            local lines = {
                "Mod: " .. (mode == 1 and ("lepcso " .. v.stairDirection)
                    or mode == 2 and "vedett 1x2" or "sima 1x2"),
                "Hossz: " .. v.length,
                "Epitoanyag: " .. v.builderBlock,
                "Faklya: " .. yn(v.torchEnabled),
                "Fuel: " .. v.fuelReserve,
                "Auto folytatas: " .. yn(v.resumeOnStartup),
            }
            return appendEstimate(lines, Estimator.nether(v,
                { completed = 0, pathLength = 0 }), v.defaultActionSeconds)
        end)
        if config then return config, lines end
    end
end

function setup.coordinate(settings)
    local c = common({
        start = defaultBase(settings),
        target = defaultBase(settings),
        mode = settings.navigation.coordinateMode,
        axisOrder = settings.navigation.coordinateAxisOrder,
    }, settings)
    local fields = {}
    for _, place in ipairs({ "start", "target" }) do
        for _, axis in ipairs({ "x", "y", "z" }) do
            local label = (place == "start" and "Start " or "Cel ") .. axis:upper()
            fields[#fields + 1] = field(label, function(v) return v[place][axis] end,
                function(v)
                    local value = number(label, v[place][axis])
                    if value ~= nil then v[place][axis] = value end
                end)
        end
    end
    fields[#fields + 1] = facingField("Start facing", "heading", "start")
    fields[#fields + 1] = field("Cel facing", function(v)
        return v.target.heading == nil and "mindegy"
            or tostring(v.target.heading)
    end, function(v)
        local choice = ui.choice("CEL FACING",
            { "Mindegy", "Eszak", "Kelet", "Del", "Nyugat" },
            v.target.heading and v.target.heading + 2 or 1)
        if choice then v.target.heading = choice == 1 and nil or choice - 2 end
    end)
    fields[#fields + 1] = field("Rombolasi mod", function(v) return v.mode end,
        function(v)
            local choice = ui.choice("KOZLEKEDES",
                { "Csak szabad ut", "Alagut a celig" },
                v.mode == "dig" and 2 or 1)
            if choice then v.mode = choice == 2 and "dig" or "open" end
        end)
    addFields(fields, baseFields())
    return editCard("KOORDINATA ADATLAP", c, fields, function(v)
        local lines = {
            string.format("Start: %d,%d,%d", v.start.x, v.start.y, v.start.z),
            string.format("Cel: %d,%d,%d", v.target.x, v.target.y, v.target.z),
            "Mod: " .. v.mode,
            "Fuel: " .. v.fuelReserve,
            "Auto folytatas: " .. yn(v.resumeOnStartup),
        }
        return appendEstimate(lines,
            Estimator.coordinate(v.start, v.target), v.defaultActionSeconds)
    end)
end

local function positionFields(fields, label, key, enabled)
    for _, axis in ipairs({ "x", "y", "z" }) do
        local name = label .. " " .. axis:upper()
        fields[#fields + 1] = field(name,
            function(v) return v[key][axis] end,
            function(v)
                local value = number(name, v[key][axis])
                if value ~= nil then v[key][axis] = value end
            end, enabled)
    end
    fields[#fields + 1] = field(label .. " irany",
        function(v) return ({ "Eszak", "Kelet", "Del", "Nyugat" })
            [v[key].heading + 1] end,
        function(v)
            local choice = ui.choice(label .. " IRANY",
                { "Eszak", "Kelet", "Del", "Nyugat" }, v[key].heading + 1)
            if choice then v[key].heading = choice - 1 end
        end, enabled)
end

local function editPens(pens)
    while true do
        local items = {}
        for index, pen in ipairs(pens) do
            items[#items + 1] = {
                label = string.format("Karam %d: %d,%d,%d", index,
                    pen.x, pen.y, pen.z),
                value = index,
            }
        end
        items[#items + 1] = { label = "Uj karam", value = "add" }
        items[#items + 1] = { label = "Utolso karam torlese", value = "remove",
            enabled = #pens > 1 }
        items[#items + 1] = { label = "Vissza", value = "back" }
        local selected = ui.menu("KARAMOK", items)
        if not selected or selected == "back" then return end
        if selected == "add" then
            local last = pens[#pens]
            pens[#pens + 1] = { x = last.x, y = last.y,
                z = last.z, heading = last.heading }
        elseif selected == "remove" then
            table.remove(pens)
        else
            local pen = pens[selected]
            while true do
                local choice = ui.menu("KARAM ETETOPONT", {
                    { label = "X", suffix = pen.x, value = "x" },
                    { label = "Y", suffix = pen.y, value = "y" },
                    { label = "Z", suffix = pen.z, value = "z" },
                    { label = "Irany", suffix = pen.heading, value = "heading" },
                    { label = "Vissza", value = "back" },
                })
                if not choice or choice == "back" then break end
                if choice == "heading" then
                    local value = ui.choice("ETETES IRANYA",
                        { "Eszak", "Kelet", "Del", "Nyugat" }, pen.heading + 1)
                    if value then pen.heading = value - 1 end
                else
                    local value = number("KARAM " .. choice:upper(), pen[choice])
                    if value ~= nil then pen[choice] = value end
                end
            end
        end
    end
end

function setup.farm(settings, existing)
    while true do
        local selected = ui.choice("FARM FELADAT",
            { "Novenyek aratasa", "Allatok etetese KISERLETI" },
            existing and existing.mode == "animal" and 2 or 1)
        if not selected then return nil end
        local mode = selected == 1 and "crop" or "animal"
        local c = common({
            mode = mode, base = defaultBase(settings),
            origin = defaultBase(settings),
            width = 8, depth = 8, crop = "wheat",
            pens = { defaultBase(settings) },
            feedItem = "minecraft:wheat", feedLimit = 2,
            minimumInput = 2, intervalSeconds = 300,
            oneShot = false,
        }, settings)
        if existing and existing.mode == mode then c = Store.clone(existing) end
        local fields = {}
        positionFields(fields, "Bazis", "base")
        positionFields(fields, "Farm kezdet", "origin",
            function() return mode == "crop" end)
        fields[#fields + 1] = integerField("Szelesseg", "width", 1,
            function() return mode == "crop" end)
        fields[#fields + 1] = integerField("Melyseg", "depth", 1,
            function() return mode == "crop" end)
        fields[#fields + 1] = field("Novenyprofil",
            function(v) return v.crop end, function(v)
                local names = { "wheat", "carrots", "potatoes", "beetroot", "wart" }
                local current = 1
                for index, name in ipairs(names) do
                    if name == v.crop then current = index end
                end
                local choice = ui.choice("NOVENYPROFIL", names, current)
                if choice then v.crop = names[choice] end
            end, function() return mode == "crop" end)
        fields[#fields + 1] = field("Etetopontok",
            function(v) return #v.pens end,
            function(v) editPens(v.pens) end,
            function() return mode == "animal" end)
        fields[#fields + 1] = field("Takarmany",
            function(v) return v.feedItem end,
            function(v)
                local value = namedBlock("TAKARMANY ITEM", v.feedItem)
                if value then v.feedItem = value end
            end, function() return mode == "animal" end)
        fields[#fields + 1] = integerField("Etetesi limit", "feedLimit", 2,
            function() return mode == "animal" end)
        fields[#fields + 1] = integerField("Koronkent mp", "intervalSeconds", 1)
        fields[#fields + 1] = integerField("Min. input", "minimumInput", 2)
        addFields(fields, baseFields())
        local config, lines = editCard("FARM ADATLAP", c, fields, function(v)
            local lines = {
                "Mod: " .. (mode == "crop" and "noveny" or "allat"),
                string.format("Bazis: %d,%d,%d", v.base.x, v.base.y, v.base.z),
                mode == "crop" and string.format("Terulet: %dx%d %s",
                    v.width, v.depth, v.crop)
                    or ("Karamok: " .. #v.pens .. " etetes: " .. v.feedItem),
                "Intervallum: " .. v.intervalSeconds .. " mp",
                "Input lada: bazis jobbra",
                "Fuel/leadolada: a szokasos helyen",
                "Auto folytatas: " .. yn(v.resumeOnStartup),
            }
            return lines
        end)
        if config then return config, lines end
    end
end

return setup
