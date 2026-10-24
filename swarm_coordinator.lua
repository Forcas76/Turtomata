-- A kezelo eszkozon tartosan mentett, fail-closed parositas.
local Store = require("state_store")
local Traffic = require("swarm_traffic")
local Geometry = require("swarm_geometry")
local Stations = require("station_registry")
local Scheduler = require("service_scheduler")
local coordinator = {}
local FILE = "swarm_coordinator.txt"
local confirmedThisRun = false

function coordinator.confirmedThisRun()
    return confirmedThisRun
end

function coordinator.emergencyStop()
    local value = coordinator.load()
    if not confirmedThisRun or not value or not value.active then
        return false, "Nincs kezelt aktiv kozos munka."
    end
    value.stopped = true
    value.status = "emergency_stop"
    return Store.write(FILE, value)
end

function coordinator.load()
    local value = Store.read(FILE)
    return type(value) == "table" and value.version == 1 and value or nil
end

function coordinator.claimAcknowledged(message, ownId)
    if not message.accepted or message.coordinatorId ~= ownId
        or type(message.jobId) ~= "string" or type(message.leaderId) ~= "number"
        or type(message.epoch) ~= "number"
        or type(message.mainLength) ~= "number" or message.mainLength < 1
        or type(message.branchLength) ~= "number" or message.branchLength < 1
        or type(message.branchSpacing) ~= "number" or message.branchSpacing < 1
        or (message.tunnelMode ~= 1 and message.tunnelMode ~= 2) then
        return false, "Hibas vagy elutasitott kezelo-visszaigazolas."
    end
    local current = coordinator.load()
    if current and current.active and current.jobId ~= message.jobId then
        return false, "Ezen az eszkozon mar van aktiv kozos munka."
    end
    local value = current and current.active and current or {
        version = 1, active = true, workers = {},
        jobId = message.jobId, leaderId = message.leaderId,
        coordinatorId = ownId, epoch = message.epoch,
        mainLength = message.mainLength,
        branchLength = message.branchLength,
        branchSpacing = message.branchSpacing,
        tunnelMode = message.tunnelMode,
    }
    if value.leaderId ~= message.leaderId or value.epoch ~= message.epoch
        or value.mainLength ~= message.mainLength
        or value.branchLength ~= message.branchLength
        or value.branchSpacing ~= message.branchSpacing
        or value.tunnelMode ~= message.tunnelMode then
        return false, "A kezelo allapota elter az uj visszaigazolastol."
    end
    value.status = value.stopped and "emergency_stop" or "registration_only"
    Stations.ensure(value)
    local reserved, reserveReason = Traffic.reserveCell(value,
        { x = 0, y = 0, z = 0 }, message.leaderId)
    if not reserved then return false, reserveReason end
    local ok, reason = Store.write(FILE, value)
    if ok then confirmedThisRun = true end
    return ok, reason
end

function coordinator.registerStation(message, sender)
    local value = coordinator.load()
    if not confirmedThisRun or not value or not value.active
        or value.stopped or value.closing
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or type(message.requestId) ~= "string" then
        return false, "Idegen vagy nem egyeztetett allomasjelentes."
    end
    local ok, reason, station = Stations.register(value, message.slot,
        sender, message.chestName, message.physicalConfirmed)
    -- Tipusvaltozasnal a regi allomast letiltva is tartosan elmentjuk.
    local saved, saveReason = Store.write(FILE, value)
    if not saved then return false, saveReason end
    return ok, reason, station
end

function coordinator.reportStationIssue(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    local transit = worker and worker.transit
    local station = value and value.stations and value.stations[message.stationId]
    if not confirmedThisRun or not value or not value.active
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or message.issue ~= "full" and message.issue ~= "blocked"
        or not transit or transit.phase ~= "inbound"
        or transit.requestId ~= message.requestId
        or transit.stationId ~= message.stationId
        or not station or not station.lease
        or station.lease.workerId ~= sender
        or station.lease.leaseId ~= message.leaseId then
        return false, "Ervenytelen allomashiba-jelentes."
    end
    station.status = message.issue
    station.lastError = message.reason
    return Store.write(FILE, value)
end

function coordinator.registerWorker(message, sender)
    local value = coordinator.load()
    if not confirmedThisRun or not value or not value.active
        or value.stopped or value.closing
        or value.status ~= "registration_only" then
        return false, "A kezelo nem fogad csatlakozast."
    end
    if message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.leaderId ~= value.leaderId or message.workerId ~= sender then
        return false, "Idegen vagy regi munkamenet."
    end
    if value.leftWorkers and value.leftWorkers[tostring(sender)] then
        return false, "Ez a turtle mar visszavonta a jelentkezest."
    end
    local slot = message.slot
    if type(slot) ~= "number" or slot <= 1 or slot ~= math.floor(slot)
        or message.physicalConfirmed ~= true then
        return false, "Hibas sorszam vagy hianyzik a helyi megerosites."
    end
    for id, worker in pairs(value.workers) do
        if worker.slot == slot and tonumber(id) ~= sender then
            return false, "Ezt a sorszamot mar masik turtle hasznalja."
        end
    end
    local previous = value.workers[tostring(sender)]
    if previous and previous.slot ~= slot then
        return false, "A turtle mar masik sorszammal szerepel."
    end
    local reserved, reserveReason = Traffic.reserveCell(value,
        { x = slot - 1, y = 0, z = 0 }, sender)
    if not reserved then return false, reserveReason end
    value.workers[tostring(sender)] = previous or {
        slot = slot, status = "registered_no_motion",
        registeredAt = os.epoch and os.epoch("utc") or 0,
    }
    local ok, reason = Store.write(FILE, value)
    return ok, reason, value
end

function coordinator.markWorkerUncertain(workerId, reason)
    local value = coordinator.load()
    local id = tostring(workerId)
    if not value or not value.active or not value.workers
        or not value.workers[id] then
        return false, "Ismeretlen resztvevo."
    end
    local worker = value.workers[id]
    if worker.status == "uncertain" then return true end
    worker.status = "uncertain"
    worker.lastError = reason or "Kapcsolatvesztes vagy bizonytalan pozicio."
    Traffic.markUncertain(value, workerId)
    Scheduler.pruneQueue(value)
    return Store.write(FILE, value)
end

function coordinator.recordPoseCorrection(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    if not confirmedThisRun or not value or not value.active or not worker
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender then
        return false, "Idegen vagy nem egyeztetett helyzetjelentes."
    end
    local pose = message.pose
    if type(pose) ~= "table" or type(pose.x) ~= "number"
        or type(pose.y) ~= "number" or type(pose.z) ~= "number"
        or type(pose.heading) ~= "number"
        or pose.x ~= math.floor(pose.x) or pose.y ~= math.floor(pose.y)
        or pose.z ~= math.floor(pose.z)
        or pose.heading ~= math.floor(pose.heading)
        or pose.heading < 0 or pose.heading > 3 then
        return false, "Hibas kozos pozicio."
    end
    local key = Geometry.cellKey(pose)
    if value.cells and value.cells[key]
        and value.cells[key] ~= tostring(sender) then
        return false, "A javitott cellat masik turtle birtokolja."
    end
    if worker.lastApprovedPose and not worker.correctedPose
        and worker.status ~= "uncertain"
        and (not (value.uncertain and value.uncertain[tostring(sender)])
            or worker.status == "needs_attention")
        and worker.pose
        and Geometry.cellKey(worker.pose) == key
        and worker.pose.heading == pose.heading
        and Geometry.cellKey(worker.lastApprovedPose) == key
        and worker.lastApprovedPose.heading == pose.heading then
        return true, nil, "approved"
    end
    worker.correctedPose = {
        x = pose.x, y = pose.y, z = pose.z, heading = pose.heading,
    }
    worker.status = "needs_reconcile"
    Traffic.markUncertain(value, sender)
    Scheduler.pruneQueue(value)
    local ok, reason = Store.write(FILE, value)
    return ok, reason, ok and "pending" or nil
end

function coordinator.approvePose(workerId)
    local value = coordinator.load()
    local id = tostring(workerId)
    local worker = value and value.workers and value.workers[id]
    if not confirmedThisRun or not value or not value.active
        or not worker or worker.status ~= "needs_reconcile"
        or not worker.correctedPose then
        return false, "Nincs ellenorizheto helyzetjavitas."
    end
    local pose = worker.correctedPose
    local newKey = Geometry.cellKey(pose)
    if value.cells and value.cells[newKey] and value.cells[newKey] ~= id then
        return false, "A javitott cella kozben foglaltta valt."
    end
    value.cells = value.cells or {}
    for key, owner in pairs(value.cells) do
        if owner == id and key ~= newKey then value.cells[key] = nil end
    end
    value.cells[newKey] = id
    worker.pose, worker.correctedPose = pose, nil
    worker.lastApprovedPose = pose
    local slotPose = Geometry.startForSlot(worker.slot)
    local z, side
    if worker.assignedBranch then
        z, side = worker.assignedBranch:match(":(%d+):([^:]+)$")
    end
    local branchX = side == "left" and -1 or side == "right" and 1
    if pose.x == slotPose.x and pose.y == 0 and pose.z == 0
        and pose.heading == 0 then
        worker.status = worker.assignedBranch
            and "assigned_no_motion" or "registered_no_motion"
        worker.lastError = nil
    elseif branchX and pose.x == branchX and pose.y == 0
        and pose.z == tonumber(z)
        and pose.heading == (side == "left" and 3 or 1) then
        worker.status, worker.lastError = "at_branch", nil
    else
        worker.status = "needs_attention"
        worker.lastError = "A javitott hely nem igazolt sorhely/ag-varakozo."
    end
    if worker.status ~= "needs_attention" then
        if worker.transit then
            local entry = value.corridors and value.corridors.entry
            local trunk = value.corridors and value.corridors.trunk
            if not entry or entry.owner ~= id or not trunk
                or trunk.owner ~= id or worker.transit.phase == "inbound"
                    and worker.transit.stationId == "D01"
                    and value.dockOwner ~= id then
                return false, "Az utvonaljog allapota elter; nincs feloldas."
            end
            value.corridors.entry, value.corridors.trunk = nil, nil
            if worker.transit.phase == "inbound" then
                if worker.transit.stationId == "D01" then value.dockOwner = nil
                else
                    local station = value.stations
                        and value.stations[worker.transit.stationId]
                    if station and station.status == "reserved" then
                        station.status = "unknown"
                        station.lastError = "Kezi helyzetegyeztetes utan ladaellenorzes kell."
                    end
                    local released, reason = Stations.release(value,
                        worker.transit.stationId, workerId,
                        worker.transit.leaseId, true)
                    if not released then return false, reason end
                end
            end
            worker.transit = nil
        end
        if value.uncertain then value.uncertain[id] = nil end
    end
    local ok, reason = Store.write(FILE, value)
    return ok, reason, ok and pose or nil
end

function coordinator.noteBranchReady(message, sender)
    local value = coordinator.load()
    if not confirmedThisRun or not value or not value.active
        or value.stopped or value.closing
        or sender ~= value.leaderId or message.leaderId ~= sender
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId then
        return false, "Idegen vagy nem egyeztetett agjelentes."
    end
    local z = message.z
    if type(z) ~= "number" or z ~= math.floor(z) or z < 1
        or z > value.mainLength or z % value.branchSpacing ~= 0
        or (message.side ~= "left" and message.side ~= "right")
        or type(message.mainCompleted) ~= "number"
        or message.mainCompleted < z
        or type(message.leaderPose) ~= "table"
        or message.leaderPose.x ~= -1 or message.leaderPose.y ~= 0
        or message.leaderPose.z ~= 0 or message.leaderPose.heading ~= 0 then
        return false, "Az ag helye vagy a foag haladasa ervenytelen."
    end
    if not value.leaderParked then
        local reserved, reserveReason = Traffic.reserveCell(value,
            message.leaderPose, sender)
        if not reserved then return false, reserveReason end
        local released, releaseReason = Traffic.releaseCell(value,
            "0,0,0", sender, message.leaderPose)
        if not released then return false, releaseReason end
        value.leaderParked = true
    end
    local key = value.jobId .. ":" .. z .. ":" .. message.side
    if value.branches and value.branches[key] then return true, nil, key end
    local ok, reason = Traffic.branchReady(value, key)
    if not ok then return false, reason end
    local saved, saveReason = Store.write(FILE, value)
    return saved, saveReason, saved and key or nil
end

function coordinator.claimNextBranch(workerId)
    local value = coordinator.load()
    local id = tostring(workerId)
    if not confirmedThisRun or not value or not value.active
        or value.stopped or value.closing
        or not value.workers or not value.workers[id] then
        return false, "A turtle nincs egyeztetve."
    end
    if value.workers[id].status == "uncertain"
        or value.workers[id].status == "needs_attention"
        or value.workers[id].status == "needs_reconcile"
        or value.uncertain and value.uncertain[id] then
        return false, "A turtle helyzete ellenorizendo."
    end
    local worker = value.workers[id]
    for key, branch in pairs(value.branches or {}) do
        if branch.owner == id and branch.status ~= "complete" then
            worker.assignedBranch = key
            if worker.status == "registered_no_motion" then
                worker.status = "offered_no_motion"
                local saved, reason = Store.write(FILE, value)
                return saved, reason, saved and key or nil
            end
            return true, nil, key -- Ujrakuldesnel ugyanaz a feladat.
        end
    end
    local available = {}
    for key, branch in pairs(value.branches or {}) do
        if branch.status == "ready" then available[#available + 1] = key end
    end
    table.sort(available, function(a, b)
        local za = tonumber(a:match(":(%d+):[^:]+$")) or math.huge
        local zb = tonumber(b:match(":(%d+):[^:]+$")) or math.huge
        if za ~= zb then return za < zb end
        return a < b
    end)
    local key = available[1]
    if not key then return false, "Nincs szabad ag." end
    local ok, reason = Traffic.claimBranch(value, key, workerId)
    if not ok then return false, reason end
    value.workers[id].assignedBranch = key
    value.workers[id].status = "offered_no_motion"
    local saved, saveReason = Store.write(FILE, value)
    return saved, saveReason, saved and key or nil
end

function coordinator.acknowledgeAssignment(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    if not confirmedThisRun or not worker or not value.active
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or worker.assignedBranch ~= message.branchKey then
        return false, "Idegen vagy regi feladat-visszaigazolas."
    end
    if message.accepted ~= true then
        worker.status = "offered_no_motion"
        worker.lastError = message.reason or "A turtle elutasitotta a feladatot."
    else
        worker.status = "assigned_no_motion"
    end
    return Store.write(FILE, value)
end

function coordinator.requestTransit(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    if not confirmedThisRun or not value or not value.active or value.stopped
        or not value.leaderParked or not worker
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or type(message.requestId) ~= "string"
        or worker.assignedBranch ~= message.branchKey
        or (message.phase ~= "outbound" and message.phase ~= "inbound") then
        return false, "Ervenytelen utvonal-keres."
    end
    if worker.status == "uncertain" or worker.status == "needs_reconcile"
        or value.uncertain and value.uncertain[tostring(sender)] then
        return false, "A turtle helyzete ellenorizendo."
    end
    if worker.transit then
        if worker.transit.requestId == message.requestId
            and worker.transit.phase == message.phase then
            return true, nil, worker.transit
        end
        return false, "A turtle mar rendelkezik masik utvonaljoggal."
    end
    if (message.phase == "outbound" and worker.status ~= "assigned_no_motion")
        or (message.phase == "inbound" and worker.status ~= "at_branch") then
        return false, "A turtle nem a vart induloponton van."
    end
    local stationId = "D01"
    if message.phase == "inbound" then
        stationId = Scheduler.queuedForWorker(value, sender)
            and "D01" or Scheduler.choose(value, sender, message)
    end
    local head = Scheduler.primaryHead(value)
    if message.phase == "inbound" and stationId == "D01" then
        local queued, queueReason, index = Scheduler.enqueuePrimary(
            value, sender, message.requestId, message.needsRefuel)
        if not queued then return false, queueReason end
        local saved, saveReason = Store.write(FILE, value)
        if not saved then return false, saveReason end
        if index ~= 1 then
            return false, "A bazisdokk foglalt; szervizvarolista."
        end
    elseif head then
        return false, "A bazisdokk foglalt; a szervizsor kovetkezik."
    end
    -- A teljes szuk folyosot egyben foglaljuk; nem engedunk szembeforgalmat.
    local ok, reason = Traffic.reserveCorridor(value, "entry", sender,
        message.phase == "outbound" and "out" or "home")
    if not ok then return false, reason end
    ok, reason = Traffic.reserveCorridor(value, "trunk", sender,
        message.phase == "outbound" and "out" or "home")
    if not ok then return false, reason end
    local stationLease
    if message.phase == "inbound" then
        if stationId == "D01" then
            ok, reason = Traffic.reserveDock(value, sender)
        else
            ok, reason, stationLease = Stations.reserve(value, stationId,
                sender, message.requestId)
        end
        if not ok then return false, reason end
    end
    worker.transit = {
        requestId = message.requestId, phase = message.phase,
        branchKey = message.branchKey,
        stationId = message.phase == "inbound" and stationId or nil,
        leaseId = stationLease and stationLease.leaseId or nil,
        chestName = stationLease and value.stations[stationId].chestName or nil,
    }
    worker.status = message.phase == "outbound"
        and "transit_out" or "transit_home"
    if stationId == "D01" and message.phase == "inbound" then
        Scheduler.removePrimary(value, sender, message.requestId)
    end
    local saved, saveReason = Store.write(FILE, value)
    return saved, saveReason, saved and worker.transit or nil
end

function coordinator.confirmTransitArrival(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    local transit = worker and worker.transit
    if worker and worker.lastArrivalRequest == message.requestId
        and message.jobId == value.jobId and message.epoch == value.epoch
        and message.coordinatorId == value.coordinatorId
        and message.phase == worker.lastArrivalPhase
        and type(message.pose) == "table"
        and type(message.pose.x) == "number"
        and type(message.pose.y) == "number"
        and type(message.pose.z) == "number"
        and worker.pose and Geometry.cellKey(message.pose)
            == Geometry.cellKey(worker.pose)
        and message.pose.heading == worker.pose.heading
        and worker.status ~= "uncertain" then
        return true, nil, worker.status
    end
    if not confirmedThisRun or not value or not transit
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or message.requestId ~= transit.requestId
        or message.phase ~= transit.phase or message.pending == true then
        return false, "Ervenytelen erkezesi igazolas."
    end
    if worker.status == "uncertain"
        or value.uncertain and value.uncertain[tostring(sender)] then
        return false, "Kapcsolatvesztes utan helyszini ellenorzes kell."
    end
    local pose = message.pose
    local z, side = transit.branchKey:match(":(%d+):([^:]+)$")
    local branchX = side == "left" and -1 or side == "right" and 1
    local expected = transit.phase == "outbound"
        and { x = branchX, y = 0, z = tonumber(z), heading =
            side == "left" and 3 or 1 }
        or { x = worker.slot - 1, y = 0, z = 0, heading = 0 }
    if not branchX or type(pose) ~= "table"
        or pose.x ~= expected.x or pose.y ~= expected.y
        or pose.z ~= expected.z or pose.heading ~= expected.heading then
        return false, "A turtle nem az igazolt varakozoponton all."
    end
    if not value.corridors or not value.corridors.entry
        or value.corridors.entry.owner ~= tostring(sender)
        or not value.corridors.trunk
        or value.corridors.trunk.owner ~= tostring(sender)
        or transit.phase == "inbound" and transit.stationId == "D01"
            and value.dockOwner ~= tostring(sender) then
        return false, "A folyosofoglalas nem egyezik."
    end
    -- A koordinatori ACK csak a tartos mentest kovetoen mehet ki.
    value.corridors["entry"] = nil
    value.corridors["trunk"] = nil
    if transit.phase == "inbound" then
        if transit.stationId == "D01" then value.dockOwner = nil
        else
            local released, releaseReason = Stations.release(value,
                transit.stationId, sender, transit.leaseId, true)
            if not released then return false, releaseReason end
        end
    end
    worker.pose = pose
    worker.transit = nil
    worker.lastArrivalRequest = message.requestId
    worker.lastArrivalPhase = message.phase
    worker.status = transit.phase == "outbound"
        and "at_branch" or "assigned_no_motion"
    local ok, reason = Store.write(FILE, value)
    return ok, reason, ok and worker.status or nil
end

function coordinator.completeBranch(message, sender)
    local value = coordinator.load()
    local worker = value and value.workers and value.workers[tostring(sender)]
    if not confirmedThisRun or not value or not value.active or not worker
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or type(message.branchKey) ~= "string" then
        return false, "Idegen vagy regi agjelentes."
    end
    if worker.lastCompletedBranch == message.branchKey then return true end
    local branch = value.branches and value.branches[message.branchKey]
    if not branch or branch.owner ~= tostring(sender)
        or branch.status ~= "claimed"
        or worker.assignedBranch ~= message.branchKey
        or worker.status ~= "assigned_no_motion"
        or worker.transit then
        return false, "Az ag vagy a turtle nincs befejezheto allapotban."
    end
    branch.status = "complete"
    worker.lastCompletedBranch = message.branchKey
    worker.assignedBranch = nil
    worker.status = "registered_no_motion"
    return Store.write(FILE, value)
end

function coordinator.leaveWorker(message, sender)
    local value = coordinator.load()
    if not confirmedThisRun or not value or not value.active
        or message.jobId ~= value.jobId or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or message.workerId ~= sender
        or type(message.requestId) ~= "string" then
        return false, "Idegen kilepesi keres."
    end
    local id = tostring(sender)
    if value.leftWorkers and value.leftWorkers[id] == message.requestId then
        return true
    end
    local worker = value.workers and value.workers[id]
    if not worker then
        -- A join ACK elveszhetett: a kesobbi join uzeneteket is tiltsuk.
        value.leftWorkers = value.leftWorkers or {}
        value.leftWorkers[id] = message.requestId
        return Store.write(FILE, value)
    end
    if worker.status ~= "registered_no_motion"
        or worker.assignedBranch or worker.transit
        or value.uncertain and value.uncertain[id] then
        return false, "Csak ures sorhelyen allo szabad seged lephet ki."
    end
    local pose = worker.pose or Geometry.startForSlot(worker.slot)
    local slotPose = Geometry.startForSlot(worker.slot)
    if not pose or Geometry.cellKey(pose) ~= Geometry.cellKey(slotPose)
        or pose.heading ~= 0 then
        return false, "A seged nincs a sajat sorhelyen."
    end
    value.cells[Geometry.cellKey(slotPose)] = nil
    value.workers[id] = nil
    value.leftWorkers = value.leftWorkers or {}
    value.leftWorkers[id] = message.requestId
    return Store.write(FILE, value)
end

function coordinator.closeLeader(message, sender)
    local value = coordinator.load()
    if not value or message.jobId ~= value.jobId
        or message.epoch ~= value.epoch
        or message.coordinatorId ~= value.coordinatorId
        or sender ~= value.leaderId or message.leaderId ~= sender
        or type(message.requestId) ~= "string" then
        return false, "Idegen lezarasi keres."
    end
    if not value.active and value.closedRequestId == message.requestId then
        return true
    end
    if not confirmedThisRun or not value.active or value.stopped then
        return false, "A munka nem zarhato le automatikusan."
    end
    value.closing = true
    if next(value.workers or {}) or next(value.corridors or {})
        or value.dockOwner then
        local ok, reason = Store.write(FILE, value)
        return false, ok and "Varakozas a segedek kilepesere." or reason
    end
    for _, branch in pairs(value.branches or {}) do
        if branch.status == "claimed" then
            Store.write(FILE, value)
            return false, "Ellenorizendo foglalt ag maradt."
        end
    end
    value.active = false
    value.status = "closed"
    value.closedRequestId = message.requestId
    return Store.write(FILE, value)
end

return coordinator
