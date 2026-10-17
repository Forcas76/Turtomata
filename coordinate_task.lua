-- KISERLETI vilagkoordinatas navigacios feladat.

local ui = require("ui")
local stateStore = require("state_store")
local jobRequest = require("job_request")
local Coordinate = require("coordinate_navigation")
local Telemetry = require("telemetry")
local Situations = require("situation_manager")
local WorkEstimator = require("work_estimator")

local args = { ... }
local request, requestReason = jobRequest.consume("coordinate", args)
local STATE_FILE = "coordinate_state.txt"
local stopRequested, finished = false, false
local state

if requestReason then error(requestReason, 0) end
if request and request.action == "resume" then
    state = stateStore.read(STATE_FILE)
    if type(state) ~= "table" or not state.active then error("Nincs folytathato koordinatas mentes.", 0) end
elseif request then
    local config = request.config or {}
    state = {
        version = 1,
        active = true,
        phase = "indulas",
        config = config,
        navigation = { pose = config.start, path = {}, pending = nil, anchors = {} },
        telemetry = {},
        warnings = {},
    }
else
    error("A koordinatas feladat csak a kozponti main programbol indithato.", 0)
end

local config = state.config
local telemetry = Telemetry.new(state.telemetry, { defaultSeconds = config.defaultActionSeconds })
local situations = Situations.new(config.safety or {}, { telemetry = telemetry })

local function save(navState, reason)
    if navState then state.navigation = navState end
    state.telemetry = telemetry:snapshot()
    state.phase = reason or state.phase
    state.warnings = situations:lastWarnings(20)
    local ok, saveReason = stateStore.write(STATE_FILE, state)
    if not ok then error(saveReason, 0) end
end

local function fuelLevel()
    local value = turtle.getFuelLevel()
    return value == "unlimited" and math.huge or value
end

local function ensureFuel(required)
    local targetRequired = required + (config.fuelReserve or 0)
    if fuelLevel() >= targetRequired then return true end
    local selected = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then
        while turtle.getItemCount(1) > 0 and fuelLevel() < targetRequired do turtle.refuel(1) end
    end
    turtle.select(selected == 1 and 2 or selected)
    if fuelLevel() >= targetRequired then return true end
    return false, "Nincs eleg fuel a kovetkezo lepeshez es a tartalekhoz."
end

local nav
nav = Coordinate.createNavigator({
    state = state.navigation,
    telemetry = telemetry,
    retryLimit = config.safety and config.safety.retryLimit,
    ensureFuel = ensureFuel,
    checkpoint = function(navState, reason)
        save(navState, reason)
        local pose = navState.pose
        local remaining = math.abs(pose.x - config.target.x)
            + math.abs(pose.y - config.target.y)
            + math.abs(pose.z - config.target.z)
        local estimate = WorkEstimator.coordinate(pose, config.target)
        ui.renderDashboard({
            task = "Koordinatas navigacio KISERLETI",
            status = reason,
            progress = "Hatralevo " .. remaining .. " lepes",
            position = string.format("%d, %d, %d", pose.x, pose.y, pose.z),
            fuel = tostring(turtle.getFuelLevel()),
            elapsed = Telemetry.formatDuration(telemetry:elapsedMs()),
            remaining = string.format("%d muv. / kb. %s", estimate.totalActions,
                Telemetry.formatDuration(telemetry:estimateMs(estimate.plan))),
            events = situations:lastWarnings(2),
        })
    end,
})

local function directionApi(move)
    if move.kind == "u" then return turtle.inspectUp, turtle.digUp, turtle.attackUp end
    if move.kind == "d" then return turtle.inspectDown, turtle.digDown, turtle.attackDown end
    return turtle.inspect, turtle.dig, turtle.attack
end

local function clearObstacle(move)
    if config.mode ~= "dig" then return false, "A csak szabad ut modban akadaly van." end
    local inspect, dig, attack = directionApi(move)
    local limit = (config.safety and config.safety.retryLimit) or 20
    for _ = 1, limit do
        local exists, data = inspect()
        if not exists then
            if attack() then sleep(0.2) else return true end
        else
            local name = data and data.name or ""
            if string.find(name, "water", 1, true) or string.find(name, "lava", 1, true) then
                return false, "Folyadek van a koordinatas utvonalon; nincs biztonsagos kerulo."
            end
            if not dig() then return false, "A koordinatas utvonal blokkja nem bonthato." end
            sleep(0.1)
        end
    end
    return false, "Tul sok blokk esik vissza a koordinatas utvonalra."
end

local moveOptions = {
    shouldStop = function() return stopRequested end,
    onBlocked = function(move, moveResult)
        local cleared, reason = clearObstacle(move)
        if cleared then return { action = "retry" } end
        return { result = { ok = false, code = "blocked", reason = reason or moveResult.reason } }
    end,
}

local function worker()
    local recovered = nav:recoverPending()
    if not recovered.ok then error(recovered.reason, 0) end
    if not nav.state.anchors.home then nav:setAnchor("home") end
    state.phase = "navigalas"
    save(nav:snapshot(), state.phase)
    local plan, reason = Coordinate.plan(nav:getPose(), config.target, config.axisOrder)
    if not plan then error(reason, 0) end
    local moved = Coordinate.execute(nav, plan, moveOptions)
    if moved.ok then
        state.active = false
        state.phase = "kesz"
        save(nav:snapshot(), state.phase)
        ui.message("KOORDINATAS NAVIGACIO", {
            "A turtle elerte a celkoordinatat.",
            string.format("Pozicio: %d, %d, %d", config.target.x, config.target.y, config.target.z),
            "Eltelt: " .. Telemetry.formatDuration(telemetry:elapsedMs()),
        })
    elseif moved.code == "stopped" and stopRequested then
        state.phase = "hazateres"
        save(nav:snapshot(), state.phase)
        local homePlan, homeReason = Coordinate.plan(nav:getPose(), config.start, config.axisOrder)
        local homeOptions = {
            shouldStop = function() return false end,
            onBlocked = moveOptions.onBlocked,
        }
        local home = homePlan and Coordinate.execute(nav, homePlan, homeOptions)
            or { ok = false, reason = homeReason }
        if home.ok then
            state.phase = "megallitva_otthon"
            save(nav:snapshot(), state.phase)
            ui.message("KOORDINATAS NAVIGACIO", "A turtle visszatert a kezdopontra.")
        else
            state.phase = "hazateres_elakadt"
            save(nav:snapshot(), state.phase)
            ui.message("HAZATERES ELakadt", home.reason or home.code, "error")
        end
    else
        state.phase = moved.code == "stopped" and "megallitva" or "elakadt"
        save(nav:snapshot(), state.phase)
        ui.message("NAVIGACIO MEGALLT", moved.reason or moved.code, "error")
    end
    finished = true
    os.queueEvent("coordinate_finished")
end

local function listener()
    while not finished do
        local event, key = os.pullEventRaw()
        if event == "coordinate_finished" then return end
        if event == "terminate" or (event == "key" and key == keys.q)
            or (event == "ccturtle_remote_command" and key == "return_home") then
            stopRequested = true
        end
    end
end

parallel.waitForAll(worker, listener)
