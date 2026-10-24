-- Kozos branch munka kb. hatralevo ideje: teljes munka, parhuzamos oldalagak.
-- Az alap muveletido es a tenyleges haladas alapjan minden kijelzeskor ujraszamol.
local Estimator = {}

local function integer(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function branchActions(state, z, transferShare)
    local config = state.workConfig or {}
    local length = integer(state.branchLength)
    local height = state.tunnelMode == 2 and 3 or 2
    local travel = 2 * z + 4
    local chainedTravel = math.min(travel, integer(state.branchSpacing) + 4)
    travel = travel * (1 - transferShare) + chainedTravel * transferShare
    local actions = length * (height + 2) + travel + 4
    if config.oreScanEnabled then
        actions = actions + length * (height + 4)
    end
    if config.torchEnabled and (config.branchTorchInterval or 0) > 0 then
        local placements = math.floor(length / config.branchTorchInterval)
        actions = actions + placements * (config.torchPlacementMode == 2 and 1 or 4)
    end
    return actions
end

function Estimator.shared(state, members, nowMs)
    state, members = state or {}, members or {}
    local config = state.workConfig or {}
    local length = integer(state.mainLength)
    local spacing = math.max(1, integer(state.branchSpacing))
    local stepMs = math.max(100, (tonumber(config.defaultActionSeconds) or 0.8) * 1000)
    local leader = members[state.leaderId]
    local mainDone = state.leaderParked and length
        or math.max(integer(state.leaderFrontier),
            leader and leader.online and leader.swarm
                and not leader.swarm.assignedBranch
                and integer(leader.progressCurrent) or 0)
    mainDone = math.min(length, mainDone)
    local mainRemaining = length - mainDone
    local height = state.tunnelMode == 2 and 3 or 2
    local mainActions = mainRemaining * (height + 2)
    if not state.leaderParked then mainActions = mainActions + length + 5 end
    if config.torchEnabled and (config.mainTorchInterval or 0) > 0 then
        local interval = config.mainTorchInterval
        mainActions = mainActions
            + (math.floor(length / interval) - math.floor(mainDone / interval))
                * (config.torchPlacementMode == 2 and 1 or 4)
    end

    local complete, total, branchRemaining, longestTail = 0, 0, 0, 0
    local transferShare = math.min(0.5,
        integer(state.transferCount) / math.max(1, integer(state.completedBranches) + 1))
    for z = spacing, length, spacing do
        for _, side in ipairs({ "left", "right" }) do
            total = total + 1
            local key = state.jobId .. ":" .. z .. ":" .. side
            local branch = state.branches and state.branches[key]
            if branch and branch.status == "complete" then
                complete = complete + 1
            else
                local actions = branchActions(state, z, transferShare)
                if branch and branch.owner then
                    local worker = members[tonumber(branch.owner)]
                    if worker and worker.online and worker.swarm
                        and worker.swarm.assignedBranch == key then
                        local progress = math.min(integer(state.branchLength),
                            integer(worker.progressCurrent))
                        local fraction = state.branchLength > 0
                            and progress / state.branchLength or 0
                        actions = actions * (1 - 0.8 * fraction)
                    end
                end
                branchRemaining = branchRemaining + actions
                if z > mainDone then
                    longestTail = math.max(longestTail, actions)
                end
            end
        end
    end
    local activeWorkers = 0
    for id, worker in pairs(state.workers or {}) do
        local member = members[tonumber(id)]
        if member and member.online
            and worker.status ~= "uncertain"
            and worker.status ~= "needs_attention"
            and worker.status ~= "needs_reconcile" then
            activeWorkers = activeWorkers + 1
        end
    end
    local remainingActions
    if state.leaderParked then
        remainingActions = branchRemaining / math.max(1, activeWorkers)
    elseif activeWorkers == 0 then
        remainingActions = mainActions + branchRemaining
    else
        -- A keskeny kozos folyosot sorositjuk, az agakban parhuzamos az asas.
        local effectiveWorkers = 1 + math.max(0, activeWorkers - 1) * 0.7
        remainingActions = math.max(mainActions + longestTail,
            branchRemaining / effectiveWorkers)
    end
    local startedAt = tonumber(state.startedAt) or tonumber(nowMs) or 0
    local elapsedMs = math.max(0, (tonumber(nowMs) or startedAt) - startedAt)
    local remainingMs = math.ceil(math.max(0, remainingActions) * stepMs)
    return {
        elapsedMs = elapsedMs, remainingMs = remainingMs,
        projectedTotalMs = elapsedMs + remainingMs,
        remainingActions = math.ceil(mainActions + branchRemaining),
        mainDone = mainDone, mainTotal = length,
        completedBranches = complete, totalBranches = total,
        activeWorkers = activeWorkers,
        actionSeconds = stepMs / 1000,
    }
end

return Estimator
