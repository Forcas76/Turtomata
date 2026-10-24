-- Kiserleti oldalagi vegrehajto. Csak koordinatori utvonaljoggal mozog.
local Session = require("swarm_session")
local Protocol = require("swarm_protocol")
local Navigation = require("navigation")
local Safety = require("swarm_safety")
local BaseDock = require("base_dock")
local PickupLedger = require("pickup_ledger")

local state = Session.load()
if not state or not state.active or state.role ~= "worker"
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
local sideHeading = state.assignmentSide == "left" and 3 or 1
local sideSign = state.assignmentSide == "left" and -1 or 1
local slotX = state.slot - 1

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
    local distance = math.abs(pose.x) + math.abs(pose.z) + slotX + 8
    return ensureFuel(distance)
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
        local before = PickupLedger.snapshot()
        if not action() then error("A blokk nem banyaszhato.", 0) end
        persist({ collected = PickupLedger.record(state.collected, before,
            PickupLedger.snapshot()) })
    end
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
            dig(direction)
            return { action = "retry" }
        end,
    })
    if not result.ok then error(result.reason or result.code, 0) end
end

local function face(heading)
    ensureLink()
    local result = nav:face(heading)
    if not result.ok then error(result.reason, 0) end
end

local function moveX(target, allowDig)
    while nav:getPose().x ~= target do
        local heading = nav:getPose().x < target and 1 or 3
        step("h", heading, allowDig)
    end
end

local function moveZ(target, allowDig)
    while nav:getPose().z ~= target do
        local heading = nav:getPose().z < target and 0 or 2
        step("h", heading, allowDig)
    end
end

local function request(kind, payload, response)
    local requestId = payload.requestId
    while true do
        ensureLink()
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
                if reply.reason and (reply.reason:find("foglalt", 1, true)
                    or reply.reason:find("hasznalja", 1, true)) then
                    break -- Foglalt folyosonal ugyanazzal az ID-val varunk.
                end
                error("Kezelo elutasitotta: " .. tostring(reply.reason), 0)
                end
            end
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
    local needed = 2 * (slotX + state.assignmentZ + state.branchLength)
        + 16
    local fuelOk, reason = ensureFuel(needed)
    if not fuelOk then error(reason .. " Tegyel uzemanyagot az 1-es slotba.", 0) end
    local info = transit("outbound")
    step("h", 0, true) -- A sorhelyrol a kozos keresztfolyosora.
    moveX(0, true)
    moveZ(state.assignmentZ, false) -- A kesz fotengelyen nincs bontas.
    step("h", sideHeading, true)
    face(sideHeading)
    arrived(info, "at_branch")
end

local inventoryFull
local function carveCeiling()
    if inventoryFull() then return false end
    dig("up")
    if inventoryFull() then return false end
    if state.tunnelMode == 2 then
        dig("down")
    end
    return true
end

inventoryFull = function()
    for slot = 2, 16 do
        if turtle.getItemCount(slot) == 0 then return false end
    end
    return true
end

local function mineBranch()
    local completed = state.branchProgress or 0
    if completed > 1 then moveX(sideSign * completed, false) end
    if completed == 0 then
        if inventoryFull() or not checkReturnFuel() then return false end
        if not carveCeiling() then return false end
        completed = 1
        persist({ branchProgress = completed })
    end
    for index = completed + 1, state.branchLength do
        ensureLink()
        if inventoryFull() then return false end
        if not checkReturnFuel() then return false end
        step("h", sideHeading, true)
        if not carveCeiling() then return false end
        persist({ branchProgress = index })
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
        if turtle.getItemCount(slot) > 0 then
            if slot == 1 and turtle.refuel(0) then turtle.refuel()
            elseif not turtle.drop() or turtle.getItemCount(slot) > 0 then
                unloadError = true
            end
        end
    end
    face(2)
    step("u", nil, false)
    turtle.select(1)
    local needed = 2 * (slotX + state.assignmentZ + state.branchLength) + 20
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
    if fuelLevel() < slotX + 4 then
        error("Nincs fuel a sorhelyre visszaereshez.", 0)
    end
    step("d", nil, false)
    turtle.select(2)
    if unloadError then
        error("A D01 leado lada megtelt; a maradek inventoryban van. Fuel toltes megkiserelve.", 0)
    end
    if fuelLevel() < needed then
        error("A fuel lada nem tudta feltolteni a kovetkezo uthoz.", 0)
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
    for slot = 2, 16 do
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
    turtle.select(2)
    face(0)
end

local function inbound()
    returnToBranchEntry()
    local nextBudget = 2 * (slotX + state.assignmentZ + state.branchLength)
        + 20
    local needsRefuel = fuelLevel() < nextBudget
    local info = transit("inbound", {
        preferredStationId = state.stationRegistered,
        needsRefuel = needsRefuel,
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
        step("h", 0, false)
        moveX(slotX, false)
        step("h", 2, false)
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
    latest.status = "registered_no_motion"
    local ok, reason = Session.update(latest)
    if not ok then error(tostring(reason), 0) end
    state = latest
end

local function run()
    ensureLink()
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
    elseif pose.x ~= sideSign or pose.y ~= 0
        or pose.z ~= state.assignmentZ or pose.heading ~= sideHeading then
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
        inbound()
        if done then complete() break end
    end
    print("Az oldalagat kesz; a seged a sajat sorhelyen all.")
end

local function workerTask()
    local ok, reason = pcall(run)
    if not ok then
        printError("Kozos munka megallt: " .. tostring(reason))
        local latest = Session.load()
        if latest and latest.active and latest.role == "worker" then
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
