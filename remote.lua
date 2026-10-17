-- Opcionális, hot-join Rednet telemetria a turtle kozponti programjahoz.

local Protocol = require("remote_protocol")
local StateStore = require("state_store")
local WorkEstimator = require("work_estimator")

local remote = {}
local opened = {}
local sequence = 0
local ACTIVE_JOB_FILE = ".remote_active_job"

local stateFiles = {
    { task = "Branch mining", path = "branch_miner_state.txt", kind = "branch" },
    { task = "Terulet asas", path = "excavator_state.txt", kind = "excavator" },
    { task = "Nether utepito", path = "nether_builder_state.txt", kind = "nether" },
    { task = "Koordinatas navigacio", path = "coordinate_state.txt", kind = "coordinate" },
}

local function nowMs()
    return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function openModems()
    if not peripheral or not rednet then return 0 end
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        local ok, wireless = pcall(peripheral.call, name, "isWireless")
        if ok and wireless then
            if not rednet.isOpen(name) then pcall(rednet.open, name) end
            if rednet.isOpen(name) then opened[name], count = true, count + 1 end
        end
    end
    for name in pairs(opened) do
        if not peripheral.isPresent(name) or not rednet.isOpen(name) then opened[name] = nil end
    end
    return count
end

local function fuelValue()
    if not turtle then return nil end
    local value = turtle.getFuelLevel()
    return value == "unlimited" and -1 or value
end

local function inventoryValue()
    if not turtle then return nil, nil end
    local used, items = 0, 0
    for slot = 1, 16 do
        local count = turtle.getItemCount(slot)
        if count > 0 then used = used + 1 end
        items = items + count
    end
    return used, items
end

local function activeState()
    local marker = StateStore.read(ACTIVE_JOB_FILE)
    if type(marker) ~= "table" or type(marker.task) ~= "string" then return nil, nil end
    for _, entry in ipairs(stateFiles) do
        local matches = (marker.task == "branch_miner" and entry.kind == "branch")
            or (marker.task == "excavator" and entry.kind == "excavator")
            or (marker.task == "nether_builder" and entry.kind == "nether")
            or (marker.task == "coordinate" and entry.kind == "coordinate")
        if matches then
            local value = StateStore.read(entry.path)
            if type(value) ~= "table" then
                value = { active = true, activity = "indulas", config = marker.config or {} }
            end
            return entry, value
        end
    end
    return nil, nil
end

local function poseOf(kind, state)
    if kind == "coordinate" then
        return state.navigation and state.navigation.pose
    end
    if kind == "excavator" and state.remote and state.remote.phase ~= "at_work" then
        return state.remote.navigation and state.remote.navigation.pose
    end
    local position = state.position or {}
    return {
        x = position.x or 0, y = position.y or 0, z = position.z or 0,
        heading = state.heading or 0,
    }
end

local function progressOf(kind, state)
    local config = state.config or {}
    if kind == "branch" then
        return state.mainCompleted or 0, config.mainLength or 0
    elseif kind == "excavator" then
        return state.visited or 0,
            (config.width or 0) * (config.depth or 0) * (config.height or 0)
    elseif kind == "nether" then
        return state.completed or 0, config.length or 0
    elseif kind == "coordinate" then
        local pose, target = poseOf(kind, state), config.target or {}
        if not pose then return 0, 0 end
        local remaining = math.abs((pose.x or 0) - (target.x or 0))
            + math.abs((pose.y or 0) - (target.y or 0))
            + math.abs((pose.z or 0) - (target.z or 0))
        local start = config.start or pose
        local total = math.abs((start.x or 0) - (target.x or 0))
            + math.abs((start.y or 0) - (target.y or 0))
            + math.abs((start.z or 0) - (target.z or 0))
        return math.max(0, total - remaining), total
    end
    return 0, 0
end

local function remainingEstimate(kind, state)
    local config = state.config or {}
    local ok, estimate
    if kind == "branch" then
        ok, estimate = pcall(WorkEstimator.branch, config, {
            mainCompleted = state.mainCompleted or 0,
            homeDistance = math.abs((state.position or {}).x or 0)
                + math.abs((state.position or {}).y or 0)
                + math.abs((state.position or {}).z or 0),
        })
    elseif kind == "excavator" then
        ok, estimate = pcall(WorkEstimator.excavator, config, {
            baseCompleted = state.baseCompleted or 0, visited = state.visited or 0,
        })
    elseif kind == "nether" then
        ok, estimate = pcall(WorkEstimator.nether, config, {
            completed = state.completed or 0,
            pathLength = state.navigation and #(state.navigation.path or {}) or 0,
        })
    elseif kind == "coordinate" then
        ok, estimate = pcall(WorkEstimator.coordinate, poseOf(kind, state), config.target)
    end
    if not ok or type(estimate) ~= "table" then return nil, nil end
    local seconds = config.defaultActionSeconds or 0.8
    return estimate.totalActions, WorkEstimator.durationMs(estimate, seconds)
end

function remote.snapshot()
    local entry, state = activeState()
    local used, items = inventoryValue()
    sequence = sequence + 1
    local message = Protocol.message("status", {
        turtleId = os.getComputerID(),
        label = os.getComputerLabel() or ("Teknos #" .. os.getComputerID()),
        sequence = sequence,
        online = true,
        task = entry and entry.task or "Fomenu",
        activity = state and (state.activity or state.phase or "dolgozik") or "Varakozik",
        fuel = fuelValue(),
        inventoryUsed = used,
        inventoryItems = items,
    })
    if state then
        message.position = poseOf(entry.kind, state)
        message.progressCurrent, message.progressTotal = progressOf(entry.kind, state)
        message.elapsedMs = state.telemetry and state.telemetry.activeMs or 0
        message.remainingActions, message.remainingMs = remainingEstimate(entry.kind, state)
    end
    return message
end

function remote.publish(recipient)
    if openModems() == 0 then return false, "Nincs vezetek nelkuli modem." end
    local message = remote.snapshot()
    if recipient then return rednet.send(recipient, message, Protocol.STATUS) end
    rednet.broadcast(message, Protocol.STATUS)
    return true
end

local function acknowledge(recipient, command, requestId, accepted, reason)
    return rednet.send(recipient, Protocol.message("ack", {
        turtleId = os.getComputerID(),
        command = command,
        requestId = requestId,
        accepted = accepted == true,
        reason = reason,
    }), Protocol.ACK)
end

function remote.handleCommand(sender, message)
    if message.targetId ~= os.getComputerID() then return end
    if message.command == "status" then
        acknowledge(sender, message.command, message.requestId, true, "Allapot elkuldve.")
        remote.publish(sender)
    elseif message.command == "return_home" then
        local entry = activeState()
        if not entry then
            acknowledge(sender, message.command, message.requestId, false,
                "Nincs aktiv munka; a turtle mar a fomenuben van.")
            return
        end
        acknowledge(sender, message.command, message.requestId, true,
            "Biztonsagos leallitas es hazateres kerese fogadva.")
        os.queueEvent("ccturtle_remote_command", "return_home", sender, message.requestId)
    elseif message.command == "service" then
        local entry = activeState()
        if not entry then
            acknowledge(sender, message.command, message.requestId, false,
                "Nincs aktiv munka, amit ki lehetne szolgalni.")
        elseif entry.kind == "coordinate" then
            acknowledge(sender, message.command, message.requestId, false,
                "A koordinatas feladatnak nincs ladakezelese.")
        else
            acknowledge(sender, message.command, message.requestId, true,
                "Lepakolas, feltoltes es folytatas kerese fogadva.")
            os.queueEvent("ccturtle_remote_command", "service", sender, message.requestId)
        end
    else
        acknowledge(sender, message.command, message.requestId, false, "Ismeretlen parancs.")
    end
end

function remote.run()
    openModems()
    local timer = os.startTimer(0.1)
    while true do
        local event, p1, message, messageProtocol = os.pullEventRaw()
        if event == "timer" and p1 == timer then
            remote.publish()
            timer = os.startTimer(Protocol.HEARTBEAT_INTERVAL)
        elseif event == "rednet_message" and messageProtocol == Protocol.CONTROL
            and Protocol.valid(message, "discover") then
            remote.publish(p1)
        elseif event == "rednet_message" and messageProtocol == Protocol.CONTROL
            and Protocol.valid(message, "command") then
            remote.handleCommand(p1, message)
        elseif event == "peripheral" or event == "peripheral_detach" then
            openModems()
        end
    end
end

return remote
