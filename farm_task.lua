-- KISERLETI noveny- es allattenyeszto karbantarto feladat.
-- A turtle a bazison indul; a leadolada mogotte, input lada a jobb oldalon.
local Store = require("state_store")
local Request = require("job_request")
local Coordinate = require("coordinate_navigation")
local UI = require("ui")

local request, requestError = Request.consume("farm", { ... })
if requestError then error(requestError, 0) end
if not request then error("A farm csak a kozponti menubol indithato.", 0) end

local FILE = "farm_state.txt"
local crops = {
    wheat = { block = "minecraft:wheat", seed = "minecraft:wheat_seeds", age = 7 },
    carrots = { block = "minecraft:carrots", seed = "minecraft:carrot", age = 7 },
    potatoes = { block = "minecraft:potatoes", seed = "minecraft:potato", age = 7 },
    beetroot = { block = "minecraft:beetroots", seed = "minecraft:beetroot_seeds", age = 3 },
    wart = { block = "minecraft:nether_wart", seed = "minecraft:nether_wart", age = 3 },
}

local state
if request.action == "resume" then
    state = Store.read(FILE)
    if type(state) ~= "table" or state.version ~= 1 or not state.active then
        error("Nincs ervenyes farmmentes.", 0)
    end
else
    local config = request.config
    state = {
        version = 1, active = true, phase = "starting",
        config = config, nextIndex = 1, cycle = 0,
        navigation = {
            pose = config.base, path = {}, pending = nil,
            anchors = { home = { index = 0, pose = config.base } },
        },
    }
end
local config = state.config
local profile = crops[config.crop]
if config.mode == "crop" and not profile then error("Ismeretlen novenyprofil.", 0) end
local inputItem = config.mode == "crop" and profile.seed or config.feedItem
local stopRequested, serviceRequested, finished = false, false, false
local nav

local function save()
    if nav then state.navigation = nav:snapshot() end
    local ok, reason = Store.write(FILE, state)
    if not ok then error(reason, 0) end
end
local function fuel()
    local value = turtle.getFuelLevel()
    return value == "unlimited" and math.huge or value
end
local function ensureFuel(required)
    local distance = nav and #nav.state.path or 0
    if fuel() >= required + distance + (config.fuelReserve or 8) then
        return true
    end
    local selected = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then turtle.refuel() end
    turtle.select(selected)
    if fuel() >= required + distance + (config.fuelReserve or 8) then
        return true
    end
    return false, "Keves fuel a hazauttartalekhoz."
end
local function face(direction)
    local result = nav:face(direction)
    if not result.ok then error(result.reason, 0) end
end
local function atBase()
    local pose = nav:getPose()
    return pose.x == config.base.x and pose.y == config.base.y
        and pose.z == config.base.z
end
local function chestAhead()
    local ok, data = turtle.inspect()
    return ok and type(data) == "table"
        and type(data.name) == "string"
        and data.name:find("chest", 1, true) ~= nil
end
local function inventoryFull()
    for slot = 3, 16 do
        if turtle.getItemSpace(slot) > 0 then return false end
    end
    return true
end
local function home()
    state.phase = "returning"
    save()
    local result = nav:returnHome()
    if not result.ok then return false, result.reason end
    return true
end
local function service()
    if not atBase() then return false, "Kiszolgalas csak a bazison." end
    state.phase = "servicing"
    save()
    face((config.base.heading + 2) % 4)
    if not chestAhead() then return false, "Hianyzik a leadolada a bazis mogott." end
    for slot = 3, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            if not turtle.drop() then return false, "A leadolada megtelt." end
        end
    end
    local requiredFuel = (config.fuelReserve or 8) + 8
    if config.mode == "crop" then
        requiredFuel = requiredFuel
            + 2 * Coordinate.distance(config.base, config.origin)
            + 3 * config.width * config.depth
    else
        for _, pen in ipairs(config.pens) do
            requiredFuel = math.max(requiredFuel,
                (config.fuelReserve or 8)
                + 2 * Coordinate.distance(config.base, pen) + 8)
        end
        requiredFuel = requiredFuel + #config.pens * 4
    end
    turtle.select(1)
    if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then turtle.refuel()
        elseif not turtle.drop() then
            return false, "Nem egetheto targy az 1-es slotban."
        end
    end
    if fuel() < requiredFuel then
        local raised = nav:step({ kind = "u" })
        if not raised.ok then return false, "Nem erek fel a fuel ladahoz." end
        face((config.base.heading + 2) % 4)
        turtle.select(1)
        while fuel() < requiredFuel do
            if not turtle.suck(64) or not turtle.refuel(0) then
                return false, "Nincs eleg egetheto anyag a fuel ladaban."
            end
            turtle.refuel()
        end
        local lowered = nav:step({ kind = "d" })
        if not lowered.ok then return false, "Nem tudok lejonni a fuel ladatol." end
    end
    turtle.select(2)
    local detail = turtle.getItemDetail(2)
    if detail and detail.name ~= inputItem then
        face((config.base.heading + 2) % 4)
        if not turtle.drop() then return false, "A hibas input nem pakolhato le." end
    end
    if turtle.getItemCount(2) < (config.minimumInput or 2) then
        face((config.base.heading + 1) % 4)
        turtle.select(2)
        turtle.suck(64)
        detail = turtle.getItemDetail(2)
        if not detail or detail.name ~= inputItem then
            return false, "Nincs megfelelo vetomag/takarmany a jobb oldali ladaban."
        end
    end
    face(config.base.heading)
    state.phase = "ready"
    save()
    return true
end
local function cropPoint(index)
    local width = config.width
    local row = math.floor((index - 1) / width)
    local column = (index - 1) % width
    if row % 2 == 1 then column = width - 1 - column end
    local front = Coordinate.WORLD_VECTORS[config.origin.heading]
    local right = Coordinate.WORLD_VECTORS[(config.origin.heading + 1) % 4]
    return {
        x = config.origin.x + row * front.x + column * right.x,
        y = config.origin.y,
        z = config.origin.z + row * front.z + column * right.z,
        heading = config.origin.heading,
    }
end
local function visit(target)
    local result = nav:goTo(target, { "y", "x", "z" },
        { shouldStop = function() return stopRequested end })
    if not result.ok then return false, result.reason end
    return true
end
local function workCrop()
    local exists, data = turtle.inspectDown()
    if exists and data and data.name == profile.block then
        local age = data.state and tonumber(data.state.age)
        if age == nil or age < profile.age then return true end
        state.pending = { kind = "harvest", index = state.nextIndex }
        save()
        if not turtle.digDown() then return false, "Nem sikerult learatni." end
        exists = false
    elseif exists then
        return true -- Ismeretlen novenyt/termofoldet nem bant.
    end
    if not exists then
        turtle.select(2)
        if turtle.getItemCount(2) == 0 then return false, "Elfogyott a vetomag." end
        if not turtle.placeDown() then return false, "Nem sikerult ujravetni." end
    end
    state.pending = nil
    save()
    return true
end
local function workAnimal()
    if state.pending and state.pending.index == state.nextIndex then
        state.pending = nil
        save()
        return true -- Az elozo etetes kimenetele bizonytalan: nem ismeteljuk.
    end
    turtle.select(2)
    if turtle.getItemCount(2) < 2 then return false, "Nincs ket takarmany." end
    local used = 0
    for _ = 1, math.max(2, config.feedLimit or 2) do
        if turtle.getItemCount(2) == 0 then break end
        state.pending = { kind = "feed", index = state.nextIndex }
        save()
        if turtle.place() then used = used + 1 end
        state.pending = nil
        save()
        if used >= 2 then break end
    end
    return true
end
local function now()
    return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end
local function worker()
    nav = Coordinate.createNavigator({
        state = state.navigation, ensureFuel = ensureFuel,
        checkpoint = function(snapshot) state.navigation = snapshot save() end,
    })
    if nav.state.pending then
        state.phase = "needs_attention"
        save()
        error("Fuggo mozgast kezzel ellenorizni kell.", 0)
    end
    while not stopRequested do
        if atBase() then
            local ready, reason = service()
            if not ready then error(reason, 0) end
        end
        local total = config.mode == "crop" and config.width * config.depth
            or #config.pens
        for index = state.nextIndex, total do
            if stopRequested then break end
            state.nextIndex = index
            if serviceRequested or inventoryFull() or turtle.getItemCount(2) < 2 then
                local ok, reason = home()
                if not ok then error(reason, 0) end
                ok, reason = service()
                if not ok then error(reason, 0) end
                serviceRequested = false
            end
            local target = config.mode == "crop" and cropPoint(index)
                or config.pens[index]
            state.phase = "to_work"
            save()
            local reached, reason = visit(target)
            if not reached then error(reason, 0) end
            state.phase = "working"
            save()
            local worked
            if config.mode == "crop" then worked, reason = workCrop()
            else worked, reason = workAnimal() end
            if not worked then error(reason, 0) end
            state.nextIndex = index + 1
            save()
            UI.renderDashboard({
                task = config.mode == "crop" and "Farm: aratas" or "Farm: etetes",
                status = state.phase, progress = index .. "/" .. total,
                position = string.format("%d,%d,%d", nav:getPose().x,
                    nav:getPose().y, nav:getPose().z),
                fuel = tostring(turtle.getFuelLevel()),
                inventory = "input=" .. turtle.getItemCount(2),
            })
        end
        local ok, reason = home()
        if not ok then error(reason, 0) end
        ok, reason = service()
        if not ok then error(reason, 0) end
        if stopRequested then break end
        state.cycle = state.cycle + 1
        state.nextIndex = 1
        state.lastCompletedAt = now()
        state.nextDueAt = state.lastCompletedAt + config.intervalSeconds * 1000
        if config.oneShot then
            state.active = false
            state.phase = "completed"
            save()
            break
        end
        state.phase = "waiting"
        save()
        local timer = os.startTimer(config.intervalSeconds)
        while not stopRequested do
            local event, id = os.pullEvent()
            if event == "timer" and id == timer then break end
        end
    end
    if stopRequested then
        local ok, reason = home()
        if not ok then error(reason, 0) end
        state.phase = "megallitva_otthon"
        save()
    end
end
local function task()
    local ok, reason = pcall(worker)
    if not ok then
        local why = tostring(reason)
        if why:find("vetomag", 1, true)
            or why:find("takarmany", 1, true)
            or why:find("egetheto anyag", 1, true)
            or why:find("leado lada megtelt", 1, true) then
            state.phase = "needs_supplies"
        else
            state.phase = "needs_attention"
        end
        state.lastError = tostring(reason)
        save()
        printError(tostring(reason))
    end
    finished = true
    os.queueEvent("farm_finished")
end
local function listener()
    while not finished do
        local event, value = os.pullEventRaw()
        if event == "farm_finished" then return end
        if event == "terminate" or event == "key" and value == keys.q
            or event == "turtomata_remote_command" and value == "return_home" then
            stopRequested = true
        elseif event == "turtomata_remote_command" and value == "service" then
            serviceRequested = true
        end
    end
end
parallel.waitForAll(task, listener)
