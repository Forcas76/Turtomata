-- Determinisztikus munkaterv- es muveletszam-becsles.
-- Az eredmeny szandekosan tipusonkent bontott, hogy a telemetry a futas
-- kozben mert atlagokkal ujra tudja szamolni.

local estimator = {}

local function nonNegative(value)
    return math.max(0, tonumber(value) or 0)
end

local function whole(value)
    return math.floor(nonNegative(value))
end

local function add(plan, kind, count)
    plan[kind] = nonNegative(plan[kind]) + nonNegative(count)
end

local function result(plan, formula)
    local total = 0
    for _, count in pairs(plan) do total = total + nonNegative(count) end
    return { plan = plan, totalActions = math.ceil(total), formula = formula or {} }
end

function estimator.total(plan)
    local total = 0
    for _, count in pairs(plan or {}) do total = total + nonNegative(count) end
    return math.ceil(total)
end

function estimator.durationMs(estimate, secondsPerAction)
    local total = estimate.totalActions or estimator.total(estimate.plan or estimate)
    return math.floor(total * (tonumber(secondsPerAction) or 0.8) * 1000)
end

local function branchJunctions(config, completed)
    if config.tunnelMode == 3 then return 0 end
    local spacing = math.max(1, whole(config.branchSpacing))
    local count = 0
    for localStep = completed + 1, whole(config.mainLength) do
        if (whole(config.startOffset) + localStep) % spacing == 0 then count = count + 1 end
    end
    return count
end

function estimator.branch(config, state)
    state = state or {}
    local completed = whole(state.mainCompleted)
    local remaining = math.max(0, whole(config.mainLength) - completed)
    local offset = whole(config.startOffset)
    local currentHome = state.homeDistance ~= nil and whole(state.homeDistance) or (offset + completed)
    local initialTravel = state.initial and offset or 0
    local plan, formula = {}, {}

    if config.tunnelMode == 3 then
        -- Szeletenkent: 1 fo elorelepes + 4 oldalmozgás, 9 bontas es 6 fordulas.
        add(plan, "move", (remaining * 5) + currentHome + remaining + initialTravel)
        add(plan, "move_vertical", state.initial and 2 or (currentHome > 0 and 1 or 0))
        add(plan, "dig", remaining * 9)
        add(plan, "turn", remaining * 6 + 2)
        formula[#formula + 1] = string.format("3x3: %d x (5m + 9a + 6f)", remaining)
        formula[#formula + 1] = string.format("Kezdes+hazaut: %d mozgas", currentHome + remaining + initialTravel)
    else
        local height = config.tunnelMode == 2 and 3 or 2
        local junctions = branchJunctions(config, completed)
        local branchLength = whole(config.branchLength)
        local branchMoves = junctions * 4 * branchLength
        add(plan, "move", (remaining * 2) + currentHome + initialTravel + branchMoves)
        add(plan, "dig", (remaining * height) + (junctions * 2 * branchLength * height))
        add(plan, "turn", junctions * 8 + 2)
        formula[#formula + 1] = string.format("Fout: %d x (2m + %da)", remaining, height)
        formula[#formula + 1] = string.format("Ag: %d pont x 2 x %d blokk", junctions, branchLength)

        if config.oreScanEnabled then
            add(plan, "move", junctions * 4 * branchLength)
            add(plan, "inspect", junctions * 2 * branchLength * (height + 2))
            formula[#formula + 1] = "Erc: bejaras + dinamikus talalat"
        end
    end

    if config.torchEnabled then
        local mainInterval = math.max(1, whole(config.mainTorchInterval))
        local torches = math.floor(remaining / mainInterval)
        if config.tunnelMode ~= 3 then
            local branchInterval = math.max(1, whole(config.branchTorchInterval))
            torches = torches + branchJunctions(config, completed) * 2
                * math.floor(whole(config.branchLength) / branchInterval)
        end
        add(plan, "place", torches)
        if config.torchPlacementMode ~= 2 then
            add(plan, "dig", torches)
            add(plan, "turn", torches * 2)
        end
    end
    return result(plan, formula)
end

local function excavationTarget(config, baseIndex)
    local width, depth = whole(config.width), whole(config.depth)
    local cellsPerPass = math.max(1, width * depth)
    local layerPass = math.floor((baseIndex - 1) / cellsPerPass)
    local withinPass = (baseIndex - 1) % cellsPerPass
    local row = math.floor(withinPass / math.max(1, width))
    local column = withinPass % math.max(1, width)
    local globalRow = layerPass * depth + row
    local x = globalRow % 2 == 0 and column or (width - 1 - column)
    local z = layerPass % 2 == 0 and (row + 1) or (depth - row)
    return x, layerPass * 2, z
end

function estimator.excavator(config, state)
    state = state or {}
    local volume = whole(config.width) * whole(config.depth) * whole(config.height)
    local baseTotal = whole(config.width) * whole(config.depth) * math.ceil(whole(config.height) / 2)
    local completed = whole(state.baseCompleted)
    local remainingBases = math.max(0, baseTotal - completed)
    local remainingBlocks = math.max(0, volume - whole(state.visited))
    local finalHome = 0
    if baseTotal > 0 then
        local x, y, z = excavationTarget(config, baseTotal)
        finalHome = math.abs(x) + math.abs(y) + math.abs(z)
    end
    local rowTurns = math.max(0, whole(config.depth) - 1)
        * math.ceil(whole(config.height) / 2) * 2
    local remainingTurns = baseTotal > 0
        and math.ceil(rowTurns * (remainingBases / baseTotal)) or 0
    local plan = {
        move = remainingBases + finalHome,
        dig = remainingBlocks,
        turn = remainingTurns,
    }
    local formula = {
        string.format("Blokk: %d x %d x %d = %d", whole(config.width), whole(config.depth), whole(config.height), volume),
        string.format("Ut: %d cella + %d hazaut", remainingBases, finalHome),
    }
    if config.remoteStart and config.remoteStart.enabled
        and config.remoteStart.base and config.remoteStart.work then
        local base, work = config.remoteStart.base, config.remoteStart.work
        local distance = math.abs(base.x - work.x) + math.abs(base.y - work.y)
            + math.abs(base.z - work.z)
        -- Egy odaut az indulasnal, egy visszaut a befejezesnel. A kozbeni
        -- kiszolgalasi utak dinamikus tobbletet a telemetry tanulja meg.
        local remoteMoves = state.remoteMoves ~= nil
            and whole(state.remoteMoves) or (distance * 2)
        add(plan, "move", remoteMoves)
        add(plan, "turn", 4)
        formula[#formula + 1] = state.remoteMoves ~= nil
            and string.format("Koordinatas hatralevo: %d lepes", remoteMoves)
            or string.format("Kihelyezes: 2 x %d koordinata-lepes", distance)
    end
    if config.torchEnabled then
        local torches = math.floor(remainingBases / math.max(1, whole(config.torchInterval)))
        add(plan, "place", torches)
        if config.torchPlacementMode ~= 2 then add(plan, "turn", torches * 2) end
    end
    return result(plan, formula)
end

function estimator.nether(config, state)
    state = state or {}
    local completed = whole(state.completed)
    local remaining = math.max(0, whole(config.length) - completed)
    local pathLength = whole(state.pathLength)
    local plan, formula = {}, {}
    if config.mode == 1 then
        add(plan, "move", remaining * 4 + pathLength)
        add(plan, "dig", remaining * 4)
        add(plan, "place", remaining)
        add(plan, "turn", remaining * 2)
        formula[#formula + 1] = string.format("Lepcso: %d x (4m + 4a + 1e)", remaining)
    elseif config.mode == 2 or state.floodShell == true then
        add(plan, "move", remaining * 4 + pathLength)
        add(plan, "dig", remaining * 2)
        add(plan, "place", remaining * 6)
        add(plan, "turn", remaining * 8)
        formula[#formula + 1] = string.format("Alagut: %d x (4m + 2a + 6e)", remaining)
    else
        add(plan, "move", remaining * 2 + pathLength)
        add(plan, "dig", remaining * 2)
        -- A padlo lerakasa csak hianyzo blokk eseten tortenik.
        add(plan, "place", remaining)
        formula[#formula + 1] = string.format("Sima 1x2: %d x (2m + 2a + max. 1e)", remaining)
    end
    if config.torchEnabled then
        local interval = math.max(1, whole(config.torchInterval))
        local torches = math.floor((completed + remaining) / interval) - math.floor(completed / interval)
        add(plan, "place", torches)
        add(plan, "move", torches * 2)
        formula[#formula + 1] = string.format("Faklyazas: kb. %d hely", torches)
    end
    return result(plan, formula)
end

function estimator.coordinate(startPose, target)
    local distance = math.abs(startPose.x - target.x)
        + math.abs(startPose.y - target.y)
        + math.abs(startPose.z - target.z)
    local axes = 0
    if startPose.x ~= target.x then axes = axes + 1 end
    if startPose.y ~= target.y then axes = axes + 1 end
    if startPose.z ~= target.z then axes = axes + 1 end
    local turns = math.max(0, axes - (startPose.y ~= target.y and 1 or 0)) * 2
    if target.heading ~= nil then turns = turns + 1 end
    return result({ move = distance, turn = turns }, {
        string.format("Ut: |dX|+|dY|+|dZ| = %d", distance),
        string.format("Iranyvaltas: legfeljebb %d", turns),
    })
end

return estimator
