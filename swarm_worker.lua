-- Kiserleti oldalagi vegrehajto. Csak koordinatori utvonaljoggal mozog.
local Session = require("swarm_session")
local Protocol = require("swarm_protocol")
local Navigation = require("navigation")
local Safety = require("swarm_safety")
local BaseDock = require("base_dock")
local PickupLedger = require("pickup_ledger")
local TorchManager = require("torch_manager")
local OreScanner = require("ore_scanner")
local InventoryManager = require("inventory_manager")

local state = Session.load()
if not state or not state.active
    or (state.role ~= "worker" and state.role ~= "leader")
    or state.stationCheckPending
    or not state.assignedBranch
    or (state.status ~= "assigned_no_motion" and state.status ~= "at_branch") then
    error("Nincs indithato segedfeladat; a kezelo kiosztasara varj.", 0)
end
if state.transit then
    error("Fuggo utvonaljog: helyszini helyzetellenorzes kell.", 0)
end
if not state.assignmentZ or not state.assignmentSide
    or (state.assignmentSide ~= "left" and state.assignmentSide ~= "right")
    or type(state.branchLength) ~= "number" or state.branchLength < 1 then
    error("Hianyos oldalagi kiosztas.", 0)
end

local stopped, finished = false, false
local nav
local face
local sideHeading = state.assignmentSide == "left" and 3 or 1
local sideSign = state.assignmentSide == "left" and -1 or 1
local slotX = state.role == "leader" and -1 or state.slot - 1
local config = state.workConfig or {}
OreScanner.setWorkTargets(config.oreTargets)
local miningSlot = config.torchEnabled and 3 or 2

local function insideOwnOreRegion(pose)
    if type(pose) ~= "table" then return false end
    local distance = sideSign * pose.x
    local band = math.floor(((state.branchSpacing or 1) - 1) / 2)
    return distance >= 1
        and distance <= state.branchLength + (config.oreScanMaxDepth or 4)
        and math.abs(pose.z - state.assignmentZ) <= band
end

local function targetPose(pose, move)
    local x, y, z = pose.x, pose.y, pose.z
    if move.kind == "u" then y = y + 1
    elseif move.kind == "d" then y = y - 1
    elseif move.heading == 0 then z = z + 1
    elseif move.heading == 1 then x = x + 1
    elseif move.heading == 2 then z = z - 1
    else x = x - 1 end
    return { x = x, y = y, z = z }
end

local function persist(fields)
    local latest = Session.load()
    if not latest or latest.jobId ~= state.jobId or not latest.active then
        error("A helyi munkamentes megvaltozott.", 0)
    end
    for key, value in pairs(fields) do latest[key] = value end
    local ok, reason = Session.update(latest)
    if not ok then error("Nem mentheto a seged: " .. tostring(reason), 0) end
    state = latest
end

local function alive()
    local latest = Session.load()
    local now = os.epoch and os.epoch("utc") or 0
    return latest and latest.active and latest.jobId == state.jobId
        and latest.status ~= "emergency_stop"
        and latest.status ~= "needs_attention"
        and latest.status ~= "needs_reconcile"
        and not latest.stoppedByCoordinator
        and latest.coordinatorId == state.coordinatorId
        and latest.epoch == state.epoch
        and latest.lastHeartbeatAt
        and now - latest.lastHeartbeatAt <= 6000
end

local function ensureLink()
    if stopped then error("Helyi leallitas: a turtle helyben marad.", 0) end
    if not alive() then
        error("Kezeloi kapcsolat megszakadt; a turtle helyben marad.", 0)
    end
end

local function fuelLevel()
    local fuel = turtle.getFuelLevel()
    return fuel == "unlimited" and math.huge or fuel
end

local function ensureFuel(required)
    ensureLink()
    if fuelLevel() >= required then return true end
    local selected = turtle.getSelectedSlot()
    turtle.select(1)
    if turtle.getItemCount(1) > 0 and turtle.refuel(0) then turtle.refuel() end
    turtle.select(selected)
    return fuelLevel() >= required,
        "Nincs eleg uzemanyag a kovetkezo lepeshez."
end

local function checkReturnFuel()
    local pose = nav:getPose()
    local distance = math.abs(pose.x) + math.abs(pose.z)
        + math.abs(slotX) + 8
    return ensureFuel(distance)
end

local function requireTorches(count)
    if not config.torchEnabled or (config.branchTorchInterval or 0) < 1
        or state.branchLength < config.branchTorchInterval
        or count < 1 then return true end
    if TorchManager.hasTorch() and turtle.getItemCount(2) >= count then
        if state.torchRequired then persist({ torchRequired = false }) end
        return true
    end
    persist({ torchRequired = count })
    return false
end

local function pendingTorchCount(firstStep)
    if not config.torchEnabled or (config.branchTorchInterval or 0) < 1 then
        return 0
    end
    local count = 0
    for stepNumber = firstStep, state.branchLength do
        if stepNumber % config.branchTorchInterval == 0
            and not (state.torchOutcomes
                and state.torchOutcomes[tostring(stepNumber)]) then
            count = count + 1
        end
    end
    return count
end

local function dig(direction)
    ensureLink()
    local safe, reason = Safety.mayDig(direction)
    if not safe then error(reason, 0) end
    local inspect = direction == "up" and turtle.inspectUp
        or direction == "down" and turtle.inspectDown or turtle.inspect
    local action = direction == "up" and turtle.digUp
        or direction == "down" and turtle.digDown or turtle.dig
    local has, data = inspect()
    if has and data and type(data.name) == "string"
        and (data.name:find("water", 1, true)
            or data.name:find("lava", 1, true)) then
        error("Folyadek a kozos utvonalon; helyszini ellenorzes kell.", 0)
    end
    if has then
        local inventoryBefore
        if config.experimentalInventory then
            local ready, beforeOrReason = InventoryManager.prepareForDig(config, data)
            if not ready then return false, "needs_service", beforeOrReason end
            inventoryBefore = beforeOrReason
        end
        local before = PickupLedger.snapshot()
        if not action() then error("A blokk nem banyaszhato.", 0) end
        persist({ collected = PickupLedger.record(state.collected, before,
            PickupLedger.snapshot()) })
        if config.experimentalInventory then
            local recorded, reason = InventoryManager.afterDig(
                config, data, inventoryBefore)
            if not recorded then error(reason, 0) end
        end
    end
    return true
end

local function placeBranchTorch(stepNumber)
    if not config.torchEnabled or (config.branchTorchInterval or 0) < 1
        or stepNumber % config.branchTorchInterval ~= 0 then return true end
    local key = tostring(stepNumber)
    if state.torchOutcomes and state.torchOutcomes[key] then return true end
    local placed, reason = false, "Nincs faklya a 2-es slotban."
    if TorchManager.hasTorch() then
        local original = nav:getPose().heading
        local function faceHeading(heading)
            face(heading)
        end
        if config.torchPlacementMode == 2 then
            placed, reason = TorchManager.placeAbove(
                function() return nav:getPose().heading end, faceHeading)
        else
            placed, reason = TorchManager.placeInDirection(
                (sideHeading + 1) % 4,
                function() return nav:getPose().heading end,
                faceHeading,
                function(direction)
                    local safe, safetyReason = Safety.mayDig(direction)
                    if not safe then return false, safetyReason end
                    local dug, _, digReason = dig(direction)
                    return dug, digReason
                end)
        end
        face(original)
    end
    local outcomes = state.torchOutcomes or {}
    outcomes[key] = placed and "placed" or (reason or "skipped")
    persist({ torchOutcomes = outcomes })
    return true -- A sikertelen faklyalerakas nem allitja le az agat.
end

local function step(kind, heading, allowDig)
    ensureLink()
    if kind == "h" then
        local faced = nav:face(heading)
        if not faced.ok then error(faced.reason, 0) end
    end
    local inspect = kind == "u" and turtle.inspectUp
        or kind == "d" and turtle.inspectDown or turtle.inspect
    local has, data = inspect()
    if has and data and type(data.name) == "string"
        and (data.name:find("water", 1, true)
            or data.name:find("lava", 1, true)) then
        error("Folyadek a kozos utvonalon; helyszini ellenorzes kell.", 0)
    end
    local move = kind == "h" and { kind = "h", heading = heading }
        or { kind = kind }
    local result = nav:step(move, { retryLimit = 3,
        onBlocked = function()
            if not allowDig then return nil end
            local direction = kind == "u" and "up"
                or kind == "d" and "down" or "forward"
            local inspect = direction == "up" and turtle.inspectUp
                or direction == "down" and turtle.inspectDown or turtle.inspect
            if not inspect() then return nil end
            local dug, code, reason = dig(direction)
            if not dug then
                return { result = { ok = false, code = code, reason = reason } }
            end
            return { action = "retry" }
        end,
    })
    if not result.ok then
        if result.code == "needs_service" then
            return false, "needs_service"
        end
        error(result.reason or result.code, 0)
    end
    return true
end

face = function(heading)
    ensureLink()
    local result = nav:face(heading)
    if not result.ok then error(result.reason, 0) end
end

local function moveX(target, allowDig)
    while nav:getPose().x ~= target do
        local heading = nav:getPose().x < target and 1 or 3
        local moved = step("h", heading, allowDig)
        if not moved then error("Nincs hely az utvonalon.", 0) end
    end
end

local function moveZ(target, allowDig)
    while nav:getPose().z ~= target do
        local heading = nav:getPose().z < target and 0 or 2
        local moved = step("h", heading, allowDig)
        if not moved then error("Nincs hely az utvonalon.", 0) end
    end
end

local function request(kind, payload, response, maxAttempts)
    local requestId = payload.requestId
    local attempts = 0
    while true do
        ensureLink()
        attempts = attempts + 1
        rednet.send(state.coordinatorId, Protocol.message(kind, payload),
            Protocol.CHANNEL)
        local deadline = os.epoch("utc") + 2500
        while os.epoch("utc") < deadline do
            local sender, reply = rednet.receive(Protocol.CHANNEL, 0.5)
            if sender == state.coordinatorId and Protocol.valid(reply, response)
                and reply.jobId == state.jobId and reply.epoch == state.epoch
                and reply.coordinatorId == state.coordinatorId
                and reply.workerId == os.getComputerID()
                and (not requestId or reply.requestId == requestId) then
                if response == "branch_complete_ack"
                    and reply.branchKey ~= payload.branchKey then
                    -- Idegen vagy regi feladatra erkezo valasz.
                else
                if reply.accepted then return reply end
                if response == "branch_transfer_grant" and reply.reason
                    and reply.reason:find("ag mar foglalt", 1, true) then
                    return reply -- Masik turtle nyerte a versenyt; uj ajanlat kell.
                end
                if reply.reason and (reply.reason:find("foglalt", 1, true)
                    or reply.reason:find("hasznalja", 1, true)) then
                    break -- Foglalt folyosonal ugyanazzal az ID-val varunk.
                end
                error("Kezelo elutasitotta: " .. tostring(reply.reason), 0)
                end
            end
        end
        if maxAttempts and attempts >= maxAttempts then
            return { accepted = true } -- Olvasasi keresnel biztonsagos hazateres.
        end
        sleep(1)
    end
end

local function transit(phase, service)
    local id = tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch("utc")) .. "-" .. phase
    local info = { phase = phase, requestId = id }
    persist({ transit = info })
    local grant = request("transit_request", {
        jobId = state.jobId, epoch = state.epoch,
        coordinatorId = state.coordinatorId,
        workerId = os.getComputerID(),
        branchKey = state.assignedBranch,
        phase = phase, requestId = id,
        preferredStationId = service and service.preferredStationId,
        needsRefuel = service and service.needsRefuel,
        needsTorch = service and service.needsTorch,
        fuelAvailable = service and service.fuelAvailable,
        nextBudget = service and service.nextBudget,
    }, "transit_grant")
    info.granted = true
    info.stationId = grant.stationId
    info.leaseId = grant.leaseId
    info.chestName = grant.chestName
    persist({ transit = info })
    return info
end

local function arrived(info, status)
    local pose = nav:getPose()
    request("transit_arrival", {
        jobId = state.jobId, epoch = state.epoch,
        coordinatorId = state.coordinatorId,
        workerId = os.getComputerID(),
        phase = info.phase, requestId = info.requestId,
        pose = pose, pending = nav:snapshot().pending ~= nil,
    }, "transit_arrival_ack")
    local latest = Session.load()
    latest.transit = nil
    latest.status = status
    local ok, reason = Session.update(latest)
    if not ok then error(tostring(reason), 0) end
    state = latest
end

local function outbound()
    local needed = 2 * (math.abs(slotX) + state.assignmentZ + state.branchLength)
        + 16
    local fuelOk, reason = ensureFuel(needed)
    if not fuelOk then error(reason .. " Tegyel uzemanyagot az 1-es slotba.", 0) end
    local info = transit("outbound")
    if state.role == "leader" then
        step("h", 1, false) -- Bal oldali varakozobol a D01 cellajara.
        local moved = step("h", 0, true)
        if not moved then error("Nincs hely az indulasi folyoson.", 0) end
    else
        local moved = step("h", 0, true)
        if not moved then error("Nincs hely az indulasi folyoson.", 0) end
        moveX(0, true)
    end
    moveZ(state.assignmentZ, false) -- A kesz fotengelyen nincs bontas.
    local entered = step("h", sideHeading, true)
    if not entered then error("Az oldalagelejen nincs hely.", 0) end
    face(sideHeading)
    arrived(info, "at_branch")
end

local inventoryFull
local function carveCeiling()
    if inventoryFull() then return false end
    if not dig("up") then return false end
    if inventoryFull() then return false end
    if state.tunnelMode == 2 then
        if not dig("down") then return false end
    end
    return true
end

inventoryFull = function()
    if config.experimentalInventory then
        return InventoryManager.isCompletelyFull(config)
    end
    for slot = miningSlot, 16 do
        if turtle.getItemCount(slot) == 0 then return false end
    end
    return true
end

local function buildOreApi(stopBeforeAnchor)
    local function oreMove(move)
        ensureLink()
        local destination = targetPose(nav:getPose(), move)
        if not insideOwnOreRegion(destination) then
            return false, "Az erc-utvonal elhagyna a kiosztott ag teruletet."
        end
        if move.kind == "h" then face(move.heading) end
        local result = nav:step(move)
        return result.ok, result.reason
    end
    local function oreDig(move, _, discoveryId)
        ensureLink()
        local destination = targetPose(nav:getPose(), move)
        if not insideOwnOreRegion(destination) then
            return false, "changed", "Masik ag vagy kozos folyosocella."
        end
        local direction = move.kind == "u" and "up"
            or move.kind == "d" and "down" or "forward"
        if move.kind == "h" then face(move.heading) end
        local inspect = direction == "up" and turtle.inspectUp
            or direction == "down" and turtle.inspectDown or turtle.inspect
        local has, block = inspect()
        if not has or not block or not (OreScanner.matches(block)
            or discoveryId and block.name == discoveryId) then
            return false, "changed", "Az erc mar nincs ott."
        end
        local safe, reason = Safety.mayDig(direction)
        if not safe then return false, "blocked", reason end
        if inventoryFull() then
            return false, "service", "Az inventory megtelt."
        end
        local dug, code, reason = dig(direction)
        if not dug then return false, "service", reason end
        return true
    end
    return {
            maxDepth = config.oreScanMaxDepth or 4,
            maxBlocks = config.oreScanMaxBlocks or 16,
            fuelReserve = config.fuelReserve or 5,
            stopBeforeAnchor = stopBeforeAnchor,
            getPose = function() return nav:getPose() end,
            face = face,
            moveOpen = oreMove,
            digOre = oreDig,
            ensureFuel = ensureFuel,
            shouldStop = function() return stopped end,
            checkpoint = function(scan)
                persist({ oreScan = scan or false })
            end,
            placeBranchTorch = function(_, stepNumber)
                return placeBranchTorch(stepNumber)
            end,
            service = function()
                return false, "Erc-vizsgalat kozben kiszolgalas kell; helyszini ellenorzes."
            end,
        }
end

local function scanOreAhead(stepNumber)
    if not config.oreScanEnabled then return true end
    local has, block = turtle.inspect()
    if not has or not block or not (OreScanner.matches(block)
        or OreScanner.discoveryId(block)) then return true end
    local required = 2 * (math.abs(slotX) + state.assignmentZ
        + state.branchLength) + 2 * (config.oreScanMaxBlocks or 16) + 20
    if not ensureFuel(required) then return false end
    local mined, reason = OreScanner.mineAhead(state.assignmentSide,
        stepNumber, buildOreApi(false), block)
    if not mined then error(reason or "Az elottem talalt ercteler elakadt.", 0) end
    return true
end

local function scanOreOnReturn()
    if not config.oreScanEnabled then return true end
    if not requireTorches(pendingTorchCount(1)) then return false end
    local required = 2 * (math.abs(slotX) + state.assignmentZ
        + state.branchLength) + 2 * (config.oreScanMaxBlocks or 16) + 20
    if not ensureFuel(required) then return false end
    local scanned, reason = OreScanner.scanReturnBranch(
        state.assignmentSide, state.branchLength, state.tunnelMode,
        buildOreApi(true))
    if not scanned then error(reason, 0) end
    persist({ oreScanComplete = true })
    return true
end

local function mineBranch()
    local completed = state.branchProgress or 0
    if completed > 1 then moveX(sideSign * completed, false) end
    if not config.oreScanEnabled
        and pendingTorchCount(math.max(1, completed)) > 0
        and not requireTorches(1) then return false end
    if completed == 0 then
        if inventoryFull() or not checkReturnFuel() then return false end
        if not carveCeiling() then return false end
        completed = 1
        persist({ branchProgress = completed })
        if not config.oreScanEnabled then placeBranchTorch(completed) end
    end
    for index = completed + 1, state.branchLength do
        ensureLink()
        if not config.oreScanEnabled and pendingTorchCount(index) > 0
            and not requireTorches(1) then return false end
        if inventoryFull() then return false end
        if not checkReturnFuel() then return false end
        face(sideHeading)
        if not scanOreAhead(index) then return false end
        local stepped, stepReason = step("h", sideHeading, true)
        if not stepped and stepReason == "needs_service" then return false end
        if not carveCeiling() then return false end
        persist({ branchProgress = index })
        if not config.oreScanEnabled then placeBranchTorch(index) end
    end
    if config.oreScanEnabled and not state.oreScanComplete then
        if not scanOreOnReturn() then return false end
    end
    return true
end

local function returnToBranchEntry()
    moveX(sideSign, false)
    face(sideHeading)
end

local function unloadAndRefuel()
    face(2)
    local learned, reason = BaseDock.learnAtBase(nav)
    if not learned then error(reason, 0) end
    local unloadError = false
    for slot = 1, 16 do
        ensureLink()
        turtle.select(slot)
        if slot == 2 and config.torchEnabled then
            if turtle.getItemCount(2) > 0 and not TorchManager.isTorch(2)
                and (not turtle.drop() or turtle.getItemCount(2) > 0) then
                unloadError = true
            end
        elseif turtle.getItemCount(slot) > 0 then
            if slot == 1 and turtle.refuel(0) then turtle.refuel()
            elseif not turtle.drop() or turtle.getItemCount(slot) > 0 then
                unloadError = true
            end
        end
    end
    face(2)
    step("u", nil, false)
    turtle.select(1)
    local needed = 2 * (math.abs(slotX) + state.assignmentZ
        + state.branchLength) + 20
    local attempts = 0
    while fuelLevel() < needed and attempts < 16 do
        ensureLink()
        if not turtle.suck(64) then break end
        if turtle.refuel(0) then turtle.refuel()
        else
            turtle.drop()
            error("A fuel ladaban nem egetheto targy van.", 0)
        end
        attempts = attempts + 1
    end
    if config.torchEnabled then
        step("u", nil, false)
        local torchOk, torchReason = TorchManager.refillFromChest()
        if not torchOk then persist({ torchSupplyWarning = torchReason }) end
        step("d", nil, false)
        local required = tonumber(state.torchRequired) or 0
        if required > 0 and (not TorchManager.hasTorch()
            or turtle.getItemCount(2) < required) then
            error("A faklyalada nem tudta potolni a szukseges "
                .. required .. " faklyat.", 0)
        end
    end
    if fuelLevel() < math.abs(slotX) + 4 then
        error("Nincs fuel a sorhelyre visszaereshez.", 0)
    end
    step("d", nil, false)
    turtle.select(miningSlot)
    if unloadError then
        error("A D01 leado lada megtelt; a maradek inventoryban van. Fuel toltes megkiserelve.", 0)
    end
    if fuelLevel() < needed then
        error("A fuel lada nem tudta feltolteni a kovetkezo uthoz.", 0)
    end
    if config.experimentalInventory then
        local refreshed, refreshReason = InventoryManager.refresh(
            config, "kozos_bazis_indulas", true)
        if not refreshed then error(refreshReason, 0) end
    end
end

local function unloadAtStation()
    face(2)
    local found, block = turtle.inspect()
    if not found or not block or block.name ~= state.transit.chestName then
        persist({ stationIncident = {
            stationId = state.transit.stationId,
            leaseId = state.transit.leaseId,
            requestId = state.transit.requestId,
            issue = "blocked", reason = "A lada eltunt vagy megvaltozott.",
        } })
        error("A seged leado ladaja eltunt vagy megvaltozott.", 0)
    end
    for slot = miningSlot, 16 do
        ensureLink()
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            if not turtle.drop() or turtle.getItemCount(slot) > 0 then
                persist({ stationIncident = {
                    stationId = state.transit.stationId,
                    leaseId = state.transit.leaseId,
                    requestId = state.transit.requestId,
                    issue = "full", reason = "Reszleges vagy sikertelen lepakolas.",
                } })
                error("A seged ladaja megtelt; a maradek az inventoryban van.", 0)
            end
        end
    end
    turtle.select(miningSlot)
    face(0)
    if config.experimentalInventory then
        local refreshed, refreshReason = InventoryManager.refresh(
            config, "kozos_sajat_lada", true)
        if not refreshed then error(refreshReason, 0) end
    end
end

local function inbound()
    returnToBranchEntry()
    local nextBudget = 2 * (math.abs(slotX) + state.assignmentZ
        + state.branchLength)
        + 20
    local needsRefuel = fuelLevel() < nextBudget
    local info = transit("inbound", {
        preferredStationId = state.stationRegistered,
        needsRefuel = needsRefuel,
        needsTorch = config.torchEnabled and not TorchManager.hasTorch(),
        fuelAvailable = turtle.getFuelLevel(),
        nextBudget = nextBudget,
    })
    step("h", sideHeading == 1 and 3 or 1, false)
    if info.stationId and info.stationId ~= "D01" then
        local stationX = tonumber(info.stationId:match("^D(%d+)$"))
        if not stationX or not info.chestName then
            error("Hibas segedallomas-jog; nincs mozgas.", 0)
        end
        stationX = stationX - 1
        moveZ(1, false)
        moveX(stationX, false)
        step("h", 2, false)
        unloadAtStation()
        if stationX ~= slotX then
            step("h", 0, false)
            moveX(slotX, false)
            step("h", 2, false)
            face(0)
        end
    else
        moveZ(0, false)
        unloadAndRefuel()
        if state.role == "leader" then
            step("h", 3, false)
        else
            step("h", 0, false)
            moveX(slotX, false)
            step("h", 2, false)
        end
        face(0)
    end
    arrived(info, "assigned_no_motion")
end

local function complete()
    request("branch_complete", {
        jobId = state.jobId, epoch = state.epoch,
        coordinatorId = state.coordinatorId,
        workerId = os.getComputerID(), branchKey = state.assignedBranch,
    }, "branch_complete_ack")
    local latest = Session.load()
    latest.assignedBranch = nil
    latest.assignmentZ = nil
    latest.assignmentSide = nil
    latest.branchProgress = nil
    latest.oreScan = nil
    latest.oreScanComplete = nil
    latest.torchOutcomes = nil
    latest.torchRequired = nil
    latest.status = "registered_no_motion"
    local ok, reason = Session.update(latest)
    if not ok then error(tostring(reason), 0) end
    state = latest
end

local function handoffFuelBudget(targetZ)
    local pose = nav:getPose()
    local length = state.branchLength
    local moves = 2 + math.abs(targetZ - pose.z)
        + 2 * math.max(0, length - 1)
        + targetZ + math.abs(slotX) + 8
    if config.oreScanEnabled then
        moves = moves + length * (state.tunnelMode == 2 and 4 or 2)
            + 2 * (config.oreScanMaxBlocks or 16)
    end
    return moves + (config.fuelReserve or 5)
end

local function enoughForAnotherBranch(targetZ)
    if inventoryFull() then return false end
    if config.torchEnabled and (config.branchTorchInterval or 0) > 0
        and state.branchLength >= config.branchTorchInterval then
        local required = config.oreScanEnabled
            and math.floor(state.branchLength / config.branchTorchInterval)
            or 1
        if not TorchManager.hasTorch()
            or turtle.getItemCount(2) < required then return false end
    end
    return ensureFuel(handoffFuelBudget(targetZ))
end

local function transferToBranch(targetKey, targetZ, targetSide, attempt)
    local requestId = tostring(os.getComputerID()) .. "-transfer-"
        .. tostring(os.epoch("utc")) .. "-" .. tostring(attempt)
    local sourceKey = state.assignedBranch
    local info = { phase = "transfer", requestId = requestId,
        fromBranch = sourceKey, branchKey = targetKey }
    persist({ transit = info })
    local grant = request("branch_transfer_request", {
        jobId = state.jobId, epoch = state.epoch,
        coordinatorId = state.coordinatorId,
        workerId = os.getComputerID(), requestId = requestId,
        fromBranch = sourceKey, targetBranch = targetKey,
        pose = nav:getPose(), pending = nav:snapshot().pending ~= nil,
    }, "branch_transfer_grant")
    if not grant.accepted then
        persist({ transit = false })
        return false -- Az ajanlatot kozben masik turtle kapta.
    end
    if grant.branchKey ~= targetKey then
        error("Az agvaltas visszaigazolasa masik agra szol.", 0)
    end
    info.granted = true
    persist({ transit = info })
    local targetHeading = targetSide == "left" and 3 or 1
    local backHeading = sideHeading == 1 and 3 or 1
    local toTrunk = step("h", backHeading, false)
    if not toTrunk then error("Nem erheto el a foag az agvaltaskor.", 0) end
    moveZ(targetZ, false)
    local entered = step("h", targetHeading, true)
    if not entered then error("Az uj ag elso cellaja nem jarhato.", 0) end
    face(targetHeading)
    request("transit_arrival", {
        jobId = state.jobId, epoch = state.epoch,
        coordinatorId = state.coordinatorId,
        workerId = os.getComputerID(), requestId = requestId,
        phase = "transfer", pose = nav:getPose(),
        pending = nav:snapshot().pending ~= nil,
    }, "transit_arrival_ack")
    persist({
        transit = false, assignedBranch = targetKey,
        assignmentZ = targetZ, assignmentSide = targetSide,
        branchProgress = 0, oreScan = false, oreScanComplete = false,
        torchOutcomes = {}, torchRequired = false,
        status = "at_branch",
    })
    sideHeading = targetHeading
    sideSign = targetSide == "left" and -1 or 1
    return true
end

local function tryNextBranch()
    returnToBranchEntry()
    for attempt = 1, 3 do
        local requestId = tostring(os.getComputerID()) .. "-next-"
            .. tostring(os.epoch("utc")) .. "-" .. tostring(attempt)
        local offer = request("branch_next_query", {
            jobId = state.jobId, epoch = state.epoch,
            coordinatorId = state.coordinatorId,
            workerId = os.getComputerID(), requestId = requestId,
            branchKey = state.assignedBranch,
        }, "branch_next_offer", 3)
        if not offer.branchKey then return false end
        local targetZ, targetSide = offer.branchKey:match(":(%d+):([^:]+)$")
        targetZ = tonumber(targetZ)
        if not targetZ or (targetSide ~= "left" and targetSide ~= "right")
            or targetZ < 1 or targetZ > state.mainLength then
            error("A kovetkezo ag ajanlata hibas.", 0)
        end
        if not enoughForAnotherBranch(targetZ) then return false end
        if transferToBranch(offer.branchKey, targetZ, targetSide, attempt) then
            return true
        end
    end
    return false
end

local function run()
    ensureLink()
    if config.experimentalInventory then
        local initialized, initReason = InventoryManager.initialize(config)
        if not initialized then error(initReason, 0) end
    end
    if type(state.oreScan) == "table" and state.oreScan.active then
        error("Felbeszakadt erckitero: helyszini pozicioellenorzes kell.", 0)
    end
    local savedNav = state.navigation or {
        pose = state.pose, path = {}, pending = nil, anchors = {},
    }
    nav = Navigation.new({ state = savedNav, ensureFuel = ensureFuel,
        checkpoint = function(snapshot)
            persist({ navigation = snapshot, pose = snapshot.pose })
        end,
    })
    local recovered = nav:recoverPending()
    if not recovered.ok then
        persist({ status = "needs_reconcile" })
        error("Fuggo fizikai lepes: korrigald a poziciot a turtle menujeben.", 0)
    end
    local pose = nav:getPose()
    if state.status == "assigned_no_motion" then
        if pose.x ~= slotX or pose.y ~= 0 or pose.z ~= 0 or pose.heading ~= 0 then
            error("A turtle nincs a mentett sorhelyen.", 0)
        end
    elseif pose.x ~= sideSign * math.max(1, state.branchProgress or 0)
        or pose.y ~= 0 or pose.z ~= state.assignmentZ
        or pose.heading ~= sideHeading then
        error("A turtle nincs az igazolt ag-varakozohelyen.", 0)
    end
    while true do
        if state.status == "assigned_no_motion"
            and (state.branchProgress or 0) >= state.branchLength then
            complete()
            break
        end
        if state.status == "assigned_no_motion" then outbound() end
        local done = mineBranch()
        if not done or not tryNextBranch() then
            inbound()
            if done then complete() break end
        end
    end
    print("Az oldalagat kesz; a turtle a sajat varakozohelyen all.")
end

local function workerTask()
    local ok, reason = pcall(run)
    OreScanner.setWorkTargets(nil)
    if not ok then
        printError("Kozos munka megallt: " .. tostring(reason))
        local latest = Session.load()
        if latest and latest.active
            and (latest.role == "worker" or latest.role == "leader") then
            latest.status = "needs_attention"
            latest.lastError = tostring(reason)
            Session.update(latest)
        end
        -- A foglalasok helyreallitasig megmaradnak.
    end
    finished = true
    os.queueEvent("swarm_worker_finished")
end

local function stopListener()
    while not finished do
        local event, key = os.pullEventRaw()
        if event == "swarm_worker_finished" then return end
        if event == "terminate" or event == "key" and key == keys.q then
            stopped = true
        end
    end
end

parallel.waitForAll(workerTask, stopListener)
