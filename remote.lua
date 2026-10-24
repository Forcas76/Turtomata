-- Opcionális, hot-join Rednet telemetria a turtle kozponti programjahoz.

local Protocol = require("remote_protocol")
local StateStore = require("state_store")
local WorkEstimator = require("work_estimator")
local WorkRegistry = require("work_registry")
local SwarmProtocol = require("swarm_protocol")
local SwarmSession = require("swarm_session")
local SwarmGeometry = require("swarm_geometry")

local remote = {}
local opened = {}
local sequence = 0
local ACTIVE_JOB_FILE = ".remote_active_job"

local stateFiles = {
    { task = "Branch mining", path = "branch_miner_state.txt", kind = "branch" },
    { task = "Terulet asas", path = "excavator_state.txt", kind = "excavator" },
    { task = "Nether utepito", path = "nether_builder_state.txt", kind = "nether" },
    { task = "Koordinatas navigacio", path = "coordinate_state.txt", kind = "coordinate" },
    { task = "Farm karbantartas", path = "farm_state.txt", kind = "farm" },
    { task = "Feladatlanc", path = "task_chain_state.txt", kind = "chain" },
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
            or (marker.task == "farm" and entry.kind == "farm")
            or (marker.task == "chain" and entry.kind == "chain")
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
    if kind == "chain" then
        return state.config and state.config.base
    end
    if kind == "farm" then
        return state.navigation and state.navigation.pose
    end
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
    elseif kind == "farm" then
        local config = state.config or {}
        local total = config.mode == "crop"
            and (config.width or 0) * (config.depth or 0)
            or #(config.pens or {})
        return math.max(0, (state.nextIndex or 1) - 1), total
    elseif kind == "chain" then
        return math.max(0, (state.index or 1) - 1),
            #(config.steps or {})
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
    local registry = WorkRegistry.load()
    local owner = not entry and registry or nil
    local used, items = inventoryValue()
    sequence = sequence + 1
    local message = Protocol.message("status", {
        turtleId = os.getComputerID(),
        label = os.getComputerLabel() or ("Teknos #" .. os.getComputerID()),
        sequence = sequence,
        online = true,
        task = entry and entry.task or owner and owner.task or "Fomenu",
        activity = state and (state.activity or state.phase or "dolgozik")
            or owner and owner.status or "Varakozik",
        fuel = fuelValue(),
        inventoryUsed = used,
        inventoryItems = items,
    })
    if state then
        message.position = poseOf(entry.kind, state)
        if type(state.collected) == "table" then
            message.collected = state.collected
        end
        if type(state.skippedOreScans) == "table" then
            local skipped = 0
            for _ in pairs(state.skippedOreScans) do skipped = skipped + 1 end
            message.skippedOreScans = skipped
        end
        message.progressCurrent, message.progressTotal = progressOf(entry.kind, state)
        message.elapsedMs = state.telemetry and state.telemetry.activeMs or 0
        message.remainingActions, message.remainingMs = remainingEstimate(entry.kind, state)
    end
    if owner and owner.lastError then message.lastError = owner.lastError end
    local swarm = SwarmSession.load()
    if swarm and swarm.active then
        message.swarm = {
            role = swarm.role, jobId = swarm.jobId, slot = swarm.slot,
            leaderId = swarm.leaderId, coordinatorId = swarm.coordinatorId,
            epoch = swarm.epoch, status = swarm.status,
            assignedBranch = swarm.assignedBranch,
            stationId = swarm.transit and swarm.transit.stationId,
            stationIssue = swarm.stationIncident
                and swarm.stationIncident.reason,
            serviceRequired = swarm.transit and swarm.transit.stationId == "D01"
                and "primary" or swarm.transit and "unload" or nil,
            coordinatorOnline = swarm.lastHeartbeatAt
                and nowMs() - swarm.lastHeartbeatAt <= 6000 or false,
        }
        if swarm.assignedBranch then
            message.task = "Kozos oldalagat"
            message.activity = swarm.status
            message.position = swarm.pose
            message.progressCurrent = swarm.branchProgress or 0
            message.progressTotal = swarm.branchLength or 0
        end
        if type(swarm.collected) == "table" then
            message.collected = swarm.collected
        end
    end
    local chain = StateStore.read("task_chain_state.txt")
    if registry and registry.task == "chain"
        and registry.status ~= "released"
        and type(chain) == "table" and chain.active == true
        and type(chain.config) == "table" and type(chain.config.steps) == "table" then
        local step = chain.config.steps[chain.index or 1]
        message.chainCurrent = chain.index
        message.chainTotal = #chain.config.steps
        message.chainTask = step and step.task
        message.chainPhase = chain.phase
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

local function publishSwarmOffer()
    local session = SwarmSession.load()
    if not session or not session.active then return end
    if openModems() == 0 then return end
    if session.stationRegistration and session.coordinatorId then
        local registration = session.stationRegistration
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("station_register_request", {
                jobId = session.jobId, epoch = session.epoch,
                coordinatorId = session.coordinatorId,
                workerId = os.getComputerID(),
                slot = registration.slot,
                chestName = registration.chestName,
                physicalConfirmed = true,
                requestId = registration.requestId,
            }), SwarmProtocol.CHANNEL)
    end
    if session.stationIncident and session.coordinatorId then
        local incident = session.stationIncident
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("station_issue", {
                jobId = session.jobId, epoch = session.epoch,
                coordinatorId = session.coordinatorId,
                workerId = os.getComputerID(),
                stationId = incident.stationId,
                leaseId = incident.leaseId,
                requestId = incident.requestId,
                issue = incident.issue, reason = incident.reason,
            }), SwarmProtocol.CHANNEL)
    end
    if session.role == "worker" and session.status == "join_pending" then
        rednet.send(session.coordinatorId, SwarmProtocol.message("join_request", {
            jobId = session.jobId, leaderId = session.leaderId,
            coordinatorId = session.coordinatorId, epoch = session.epoch,
            workerId = os.getComputerID(), slot = session.slot,
            physicalConfirmed = true,
        }), SwarmProtocol.CHANNEL)
        return
    end
    if session.role == "worker" and session.status == "leave_pending" then
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("leave_request", {
                jobId = session.jobId, epoch = session.epoch,
                coordinatorId = session.coordinatorId,
                workerId = os.getComputerID(),
                requestId = session.leaveRequestId,
            }), SwarmProtocol.CHANNEL)
        return
    end
    if (session.role == "worker" or session.role == "leader")
        and session.status == "needs_reconcile" then
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("pose_correction", {
                jobId = session.jobId, coordinatorId = session.coordinatorId,
                epoch = session.epoch, workerId = os.getComputerID(),
                pose = session.pose,
            }), SwarmProtocol.CHANNEL)
        return
    end
    if (session.role == "worker" or session.role == "leader")
        and session.status == "needs_attention" then
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("worker_attention", {
                jobId = session.jobId, coordinatorId = session.coordinatorId,
                epoch = session.epoch, workerId = os.getComputerID(),
                reason = session.lastError,
            }), SwarmProtocol.CHANNEL)
        return
    end
    if session.role ~= "leader" then return end
    if session.status == "close_pending" then
        rednet.send(session.coordinatorId,
            SwarmProtocol.message("leader_close_request", {
                jobId = session.jobId, epoch = session.epoch,
                coordinatorId = session.coordinatorId,
                leaderId = os.getComputerID(),
                requestId = session.closeRequestId,
            }), SwarmProtocol.CHANNEL)
        return
    end
    rednet.broadcast(SwarmProtocol.message("job_offer", {
        jobId = session.jobId, leaderId = session.leaderId,
        coordinatorId = session.coordinatorId, epoch = session.epoch,
        mainLength = session.mainLength,
        branchLength = session.branchLength,
        branchSpacing = session.branchSpacing,
        tunnelMode = session.tunnelMode,
        workConfig = session.workConfig,
    }), SwarmProtocol.CHANNEL)
    if not session.coordinatorId then return end
    local mined = StateStore.read("branch_miner_state.txt")
    if type(mined) ~= "table" or type(mined.config) ~= "table"
        or mined.config.swarmTrunkOnly ~= true
        or mined.config.swarmJobId ~= session.jobId
        or not mined.position or mined.position.y ~= 0
        or (mined.mainCompleted or 0) < session.branchSpacing then return end
    local z = session.publishZ or session.branchSpacing
    if z > session.mainLength then return end
    local parked = mined.active == false and mined.activity == "kesz"
        and mined.position.x == -1 and mined.position.z == 0
    local ahead = mined.active == true and mined.activity == "fotengely"
        and mined.position.x == 0 and mined.position.z > z
        and (mined.mainCompleted or 0) > z
    if not parked and not ahead then return end
    local side = session.publishSide or "left"
    rednet.send(session.coordinatorId,
        SwarmProtocol.message("branch_ready", {
            jobId = session.jobId, leaderId = session.leaderId,
            coordinatorId = session.coordinatorId, epoch = session.epoch,
            z = z, side = side, mainCompleted = mined.mainCompleted,
            leaderPose = { x = mined.position.x, y = mined.position.y,
                z = mined.position.z, heading = mined.heading },
        }), SwarmProtocol.CHANNEL)
end

function remote.handleSwarm(sender, message)
    if not SwarmProtocol.valid(message) then return end
    if message.type == "station_issue_ack"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        local incident = state and state.stationIncident
        if state and incident and state.jobId == message.jobId
            and state.epoch == message.epoch
            and state.coordinatorId == sender
            and incident.requestId == message.requestId
            and incident.stationId == message.stationId
            and message.accepted then
            state.stationIncident = nil
            SwarmSession.update(state)
        end
    elseif message.type == "station_register_ack"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        local registration = state and state.stationRegistration
        if state and state.active and registration
            and state.jobId == message.jobId
            and state.epoch == message.epoch
            and state.coordinatorId == sender
            and registration.requestId == message.requestId
            and registration.slot == message.slot then
            state.stationRegistration = nil
            state.stationRegistered = message.accepted
                and message.stationId or nil
            state.stationChestName = message.accepted
                and registration.chestName or nil
            state.stationError = message.accepted and nil or message.reason
            SwarmSession.update(state)
        end
    elseif message.type == "job_offer" and sender ~= os.getComputerID()
        and message.leaderId == sender then
        SwarmSession.observeOffer(message)
    elseif message.type == "coordinator_claim"
        and message.leaderId == os.getComputerID() then
        local ok, reason, state = SwarmSession.claimCoordinator(
            message.jobId, sender)
        rednet.send(sender, SwarmProtocol.message("coordinator_ack", {
            jobId = message.jobId, leaderId = os.getComputerID(),
            coordinatorId = sender, requestId = message.requestId,
            accepted = ok, reason = reason,
            epoch = state and state.epoch,
            mainLength = state and state.mainLength,
            branchLength = state and state.branchLength,
            branchSpacing = state and state.branchSpacing,
            tunnelMode = state and state.tunnelMode,
            workConfig = state and state.workConfig,
        }), SwarmProtocol.CHANNEL)
    elseif message.type == "join_ack"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        if state and state.role == "worker" and state.jobId == message.jobId
            and state.coordinatorId == sender
            and message.coordinatorId == sender
            and state.epoch == message.epoch
            and state.status == "join_pending" then
            state.status = message.accepted and "registered_no_motion" or "join_rejected"
            state.lastError = message.reason
            SwarmSession.update(state)
        end
    elseif message.type == "coordinator_heartbeat" then
        local state = SwarmSession.load()
        if state and state.active and state.jobId == message.jobId
            and state.leaderId == message.leaderId
            and state.coordinatorId == sender
            and message.coordinatorId == sender
            and state.epoch == message.epoch then
            local now = nowMs()
            if now - (state.lastHeartbeatAt or 0) >= 2000 then
                state.lastHeartbeatAt = now
                SwarmSession.update(state)
            end
        end
    elseif message.type == "swarm_stop" then
        local state = SwarmSession.load()
        if state and state.active and state.jobId == message.jobId
            and state.coordinatorId == sender
            and message.coordinatorId == sender
            and state.epoch == message.epoch then
            state.status = "emergency_stop"
            state.lastError = "Kozos munka tavoli veszleallitas."
            SwarmSession.update(state)
        end
    elseif message.type == "pose_reconcile_ack"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        if state and (state.role == "worker" or state.role == "leader")
            and state.active
            and state.status == "needs_reconcile"
            and state.jobId == message.jobId
            and state.coordinatorId == sender and state.epoch == message.epoch
            and message.accepted == true then
            state.status = message.status == "at_branch" and "at_branch"
                or message.status == "assigned_no_motion"
                    and "assigned_no_motion"
                or message.status == "registered_no_motion"
                    and "registered_no_motion" or "needs_attention"
            if state.status == "at_branch"
                and type(message.branchKey) == "string"
                and message.branchKey ~= state.assignedBranch then
                local z, side = message.branchKey:match(":(%d+):([^:]+)$")
                if z and (side == "left" or side == "right") then
                    state.assignedBranch = message.branchKey
                    state.assignmentZ, state.assignmentSide = tonumber(z), side
                    state.branchProgress = 0
                    state.oreScan, state.oreScanComplete = nil, nil
                    state.torchOutcomes, state.torchRequired = nil, nil
                else
                    state.status = "needs_attention"
                    state.lastError = "Hibas agvaltas-visszaigazolas."
                end
            end
            if state.status ~= "needs_attention" then
                state.transit = nil
                -- A koordinatortol visszaigazolt kezi egyeztetes mar
                -- lezarta a regi lease-t; az allomas unknown marad.
                state.stationIncident = nil
            end
            state.navigation = {
                pose = state.pose, path = {}, pending = nil, anchors = {},
            }
            if type(state.oreScan) == "table" and state.oreScan.active then
                local sign = state.assignmentSide == "left" and -1 or 1
                if state.pose.x == sign * state.branchLength
                    and state.pose.y == 0
                    and state.pose.z == state.assignmentZ then
                    state.oreScan = nil
                    state.oreScanComplete = nil
                else
                    state.status = "needs_attention"
                    state.lastError = "Az erckitero utan a fizikai agcsucsra kell visszaallitani."
                end
            end
            if state.status ~= "needs_attention" then state.lastError = nil end
            SwarmSession.update(state)
        end
    elseif message.type == "branch_ready_ack" then
        local state = SwarmSession.load()
        if state and state.active and state.role == "leader"
            and state.jobId == message.jobId
            and state.coordinatorId == sender
            and message.coordinatorId == sender
            and state.epoch == message.epoch
            and message.accepted == true then
            local z = state.publishZ or state.branchSpacing
            local side = state.publishSide or "left"
            if message.branchKey == SwarmGeometry.branchKey(state.jobId, z, side) then
                if side == "left" then state.publishSide = "right"
                else
                    state.publishZ = z + state.branchSpacing
                    state.publishSide = "left"
                end
                SwarmSession.update(state)
            end
        end
    elseif message.type == "task_offer"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        local accepted, reason = false, "Nincs fogadhato segedmunkamenet."
        if state and state.active
            and (state.role == "worker" or state.role == "leader")
            and state.jobId == message.jobId
            and state.coordinatorId == sender
            and message.coordinatorId == sender
            and state.epoch == message.epoch
            and (state.status == "registered_no_motion"
                or state.status == "assigned_no_motion")
            and type(message.z) == "number"
            and type(state.mainLength) == "number"
            and type(state.branchSpacing) == "number"
            and state.branchSpacing > 0
            and message.z >= 1 and message.z <= state.mainLength
            and message.z % state.branchSpacing == 0
            and message.branchKey == SwarmGeometry.branchKey(
                state.jobId, message.z, message.side)
            and (not state.assignedBranch
                or state.assignedBranch == message.branchKey) then
            state.assignedBranch = message.branchKey
            state.assignmentZ, state.assignmentSide = message.z, message.side
            state.status = "assigned_no_motion"
            accepted, reason = SwarmSession.update(state)
        end
        rednet.send(sender, SwarmProtocol.message("task_ack", {
            jobId = message.jobId, epoch = message.epoch,
            coordinatorId = sender, workerId = os.getComputerID(),
            branchKey = message.branchKey, accepted = accepted,
            reason = reason,
        }), SwarmProtocol.CHANNEL)
    elseif message.type == "leave_ack"
        and message.workerId == os.getComputerID() then
        local state = SwarmSession.load()
        if state and state.active and state.role == "worker"
            and state.status == "leave_pending"
            and state.jobId == message.jobId
            and state.coordinatorId == sender
            and state.epoch == message.epoch
            and state.leaveRequestId == message.requestId
            and message.accepted == true then
            state.active, state.status = false, "left"
            SwarmSession.update(state)
        end
    elseif message.type == "leader_close_ack"
        and message.leaderId == os.getComputerID() then
        local state = SwarmSession.load()
        if state and state.active and state.role == "leader"
            and state.status == "close_pending"
            and state.jobId == message.jobId
            and state.coordinatorId == sender
            and state.epoch == message.epoch
            and state.closeRequestId == message.requestId
            and message.accepted == true then
            state.active, state.status = false, "closed"
            SwarmSession.update(state)
            rednet.broadcast(SwarmProtocol.message("job_closed", {
                jobId = state.jobId, leaderId = os.getComputerID(),
                epoch = state.epoch,
            }), SwarmProtocol.CHANNEL)
        end
    elseif message.type == "job_closed" and message.leaderId == sender then
        SwarmSession.forgetOffer(message.jobId)
        local state = SwarmSession.load()
        if state and state.active and state.role == "worker"
            and state.status == "join_pending"
            and state.jobId == message.jobId and state.leaderId == sender then
            state.active, state.status = false, "closed_before_join"
            SwarmSession.update(state)
        end
    end
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
        os.queueEvent("turtomata_remote_command", "return_home", sender, message.requestId)
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
            os.queueEvent("turtomata_remote_command", "service", sender, message.requestId)
        end
    elseif message.command == "skip_ore_scan" then
        local entry, state = activeState()
        if not entry or entry.kind ~= "branch"
            or not state or not state.oreScan
            or not state.oreScan.returnScan then
            acknowledge(sender, message.command, message.requestId, false,
                "Nincs aktiv visszauti agvizsgalat ezen a turtle-n.")
        else
            acknowledge(sender, message.command, message.requestId, true,
                "A kihagyas a kovetkezo agcella-hataron lep eletbe.")
            os.queueEvent("turtomata_remote_command", "skip_ore_scan",
                sender, message.requestId)
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
            publishSwarmOffer()
            timer = os.startTimer(Protocol.HEARTBEAT_INTERVAL)
        elseif event == "rednet_message" and messageProtocol == Protocol.CONTROL
            and Protocol.valid(message, "discover") then
            remote.publish(p1)
        elseif event == "rednet_message" and messageProtocol == Protocol.CONTROL
            and Protocol.valid(message, "command") then
            remote.handleCommand(p1, message)
        elseif event == "rednet_message" and messageProtocol == SwarmProtocol.CHANNEL then
            remote.handleSwarm(p1, message)
        elseif event == "peripheral" or event == "peripheral_detach" then
            openModems()
        end
    end
end

return remote
