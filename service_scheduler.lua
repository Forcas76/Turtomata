-- Konzervativ allomasvalasztas a mar igazolt bazisgeometrian.
-- A tenyleges folyosofoglalast a koordinator vegzi el a valasztas utan.
local Stations = require("station_registry")
local scheduler = {}

local function branchZ(worker)
    return worker.assignmentZ
        or tonumber((worker.assignedBranch or ""):match(":(%d+):[^:]+$"))
        or 1
end

local function stationCost(worker, station)
    local slotX = worker.slot - 1
    local stationX = station.pose.x
    -- Ag-bejarat -> bazis z=1 -> dokk -> vissza a sajat sorhelyre.
    return math.abs(branchZ(worker) - 1)
        + math.abs(stationX) + 1 + 1
        + math.abs(stationX - slotX) + 1
end

function scheduler.choose(state, workerId, request)
    local worker = state.workers and state.workers[tostring(workerId)]
    if not worker then return nil, "Ismeretlen turtle." end
    if request.needsRefuel then return "D01", "primary_service" end
    local bestId, bestCost
    local primaryCost = math.abs(branchZ(worker))
        + (worker.slot - 1) + 4
    for id, station in pairs(Stations.ensure(state)) do
        if id ~= "D01" and station.type == "unload_only" then
            local usable = Stations.canUnload(state, id, workerId)
            if usable then
                local cost = stationCost(worker, station)
                local fuel = request.fuelAvailable
                local budget = request.nextBudget
                local ownCost = math.abs(branchZ(worker) - 1)
                    + (worker.slot - 1) + 3
                local extra = math.max(0, cost - ownCost)
                if (fuel == "unlimited" or type(fuel) == "number"
                    and type(budget) == "number"
                    and fuel >= budget + extra)
                    and cost < primaryCost then
                    if not bestCost or cost < bestCost
                        or cost == bestCost and id < bestId then
                        bestId, bestCost = id, cost
                    end
                end
            end
        end
    end
    if bestId then return bestId, "unload_only" end
    return "D01", "primary_service"
end

function scheduler.pruneQueue(state)
    local kept = {}
    for _, entry in ipairs(state.serviceQueue or {}) do
        local worker = state.workers and state.workers[tostring(entry.workerId)]
        if worker and worker.status == "at_branch"
            and not worker.transit
            and not (state.uncertain
                and state.uncertain[tostring(entry.workerId)]) then
            kept[#kept + 1] = entry
        end
    end
    state.serviceQueue = kept
    return kept
end

function scheduler.enqueuePrimary(state, workerId, requestId, needsRefuel)
    if type(requestId) ~= "string" or requestId == "" then
        return false, "Hibas szervizkeres-azonosito."
    end
    local queue = scheduler.pruneQueue(state)
    for index, entry in ipairs(queue) do
        if entry.workerId == workerId then
            if entry.requestId ~= requestId then
                return false, "Fuggo masik szervizkeres; helyzetellenorzes kell."
            end
            return true, nil, index
        end
    end
    state.serviceQueueNext = (state.serviceQueueNext or 0) + 1
    queue[#queue + 1] = {
        workerId = workerId, requestId = requestId,
        needsRefuel = needsRefuel == true,
        sequence = state.serviceQueueNext,
    }
    return true, nil, #queue
end

function scheduler.removePrimary(state, workerId, requestId)
    for index, entry in ipairs(state.serviceQueue or {}) do
        if entry.workerId == workerId and entry.requestId == requestId then
            table.remove(state.serviceQueue, index)
            return true
        end
    end
    return false
end

function scheduler.primaryHead(state)
    return scheduler.pruneQueue(state)[1]
end

function scheduler.queuedForWorker(state, workerId)
    for _, entry in ipairs(scheduler.pruneQueue(state)) do
        if entry.workerId == workerId then return entry end
    end
    return nil
end

return scheduler
