-- KISERLETI ercdetektalo es erctelep-koveto CC:Tweaked turtle-okhoz.
-- A modul csak a branch miner altal atadott, poziciokovetett mozgasokat hasznalja.

local scanner = {}

local TARGETS_FILE = "ore_targets.txt"
local TARGETS_TEMP_FILE = ".ore_targets.tmp"

local groups = {
    { label = "Szen", ids = { "minecraft:coal_ore", "minecraft:deepslate_coal_ore" } },
    { label = "Vas", ids = { "minecraft:iron_ore", "minecraft:deepslate_iron_ore" } },
    { label = "Rez", ids = { "minecraft:copper_ore", "minecraft:deepslate_copper_ore" } },
    { label = "Arany", ids = { "minecraft:gold_ore", "minecraft:deepslate_gold_ore" } },
    { label = "Redstone", ids = { "minecraft:redstone_ore", "minecraft:deepslate_redstone_ore" } },
    { label = "Lazurit", ids = { "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore" } },
    { label = "Gyemant", ids = { "minecraft:diamond_ore", "minecraft:deepslate_diamond_ore" } },
    { label = "Smaragd", ids = { "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore" } },
    { label = "Nether arany", ids = { "minecraft:nether_gold_ore" } },
    { label = "Nether kvarc", ids = { "minecraft:nether_quartz_ore" } },
    { label = "Ancient debris", ids = { "minecraft:ancient_debris" } },
}

local selected = {}
local custom = {}
local loaded = false

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function copyMove(move)
    if move.kind == "h" then return { kind = "h", heading = move.heading } end
    return { kind = move.kind }
end

local function loadTargets()
    if loaded then return end
    loaded = true
    if not fs.exists(TARGETS_FILE) then return end
    local file = fs.open(TARGETS_FILE, "r")
    if not file then return end
    local content = file.readAll()
    file.close()
    local ok, saved = pcall(textutils.unserializeJSON, content)
    if not ok or type(saved) ~= "table" or saved.version ~= 1 then return end
    if type(saved.selected) == "table" then selected = saved.selected end
    if type(saved.custom) == "table" then custom = saved.custom end
end

local function saveTargets()
    local file = fs.open(TARGETS_TEMP_FILE, "w")
    if not file then return false, "Nem irhato az erclista ideiglenes fajlja." end
    file.write(textutils.serializeJSON({
        version = 1,
        selected = selected,
        custom = custom,
    }))
    file.close()
    if fs.exists(TARGETS_FILE) then fs.delete(TARGETS_FILE) end
    fs.move(TARGETS_TEMP_FILE, TARGETS_FILE)
    return true
end

local function groupChecked(group)
    for _, name in ipairs(group.ids) do
        if selected[name] ~= true then return false end
    end
    return true
end

local function toggleGroup(group)
    local newValue = not groupChecked(group)
    for _, name in ipairs(group.ids) do selected[name] = newValue or nil end
end

local function buildRows()
    local rows = {}
    for index, group in ipairs(groups) do
        rows[#rows + 1] = {
            kind = "group",
            index = index,
            label = group.label,
            checked = groupChecked(group),
        }
    end
    for index, name in ipairs(custom) do
        rows[#rows + 1] = {
            kind = "custom",
            index = index,
            label = name,
            checked = selected[name] == true,
        }
    end
    return rows
end

local function validBlockName(value)
    return type(value) == "string"
        and string.match(value, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") ~= nil
end

local function addCustom()
    clearScreen()
    print("=== UJ ERC/BLOKK ===")
    print("Formatum:")
    print("<mod_neve>:<blokk_neve>")
    print("")
    print("Vanilla: minecraft:coal_ore")
    print("Rovid vanilla: coal_ore")
    print("Modolt: create:zinc_ore")
    write("Azonosito: ")
    local value = string.lower(read() or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    -- Namespace nelkuli rovid nevnel a vanilla minecraft namespace az alap.
    if not string.find(value, ":", 1, true)
        and string.match(value, "^[a-z0-9_./-]+$") then
        value = "minecraft:" .. value
    end
    if not validBlockName(value) then
        printError("Hibas blokknev. Pelda: coal_ore vagy mod:tin_ore")
        sleep(1.5)
        return false
    end
    for _, name in ipairs(custom) do
        if name == value then selected[value] = true return true end
    end
    for _, group in ipairs(groups) do
        for _, name in ipairs(group.ids) do
            if name == value then
                for _, groupedName in ipairs(group.ids) do
                    selected[groupedName] = true
                end
                return true
            end
        end
    end
    custom[#custom + 1] = value
    selected[value] = true
    return true
end

local function toggleRow(row)
    if row.kind == "group" then
        toggleGroup(groups[row.index])
    else
        local name = custom[row.index]
        selected[name] = selected[name] and nil or true
    end
end

local function deleteRow(row)
    if not row then return false end
    if row.kind == "group" then
        -- A beepitett vanilla sor megmarad, de minden valtozata kikapcsol.
        for _, name in ipairs(groups[row.index].ids) do selected[name] = nil end
        return true
    end
    local name = custom[row.index]
    if not name then return false end
    selected[name] = nil
    table.remove(custom, row.index)
    return true
end

function scanner.editTargets()
    loadTargets()
    local cursor, page = 1, 1

    while true do
        local width, height = term.getSize()
        local pageSize = math.max(3, height - 7)
        local rows = buildRows()
        local pageCount = math.max(1, math.ceil(#rows / pageSize))
        if page > pageCount then page = pageCount end
        local first = (page - 1) * pageSize + 1
        local last = math.min(#rows, first + pageSize - 1)
        if cursor < first then cursor = first end
        if cursor > last then cursor = last end

        clearScreen()
        print("=== KISERLETI ERCEK ===")
        print("Kattintas vagy nyilak+ENTER")
        for rowIndex = first, last do
            local row = rows[rowIndex]
            local marker = rowIndex == cursor and ">" or " "
            local check = row.checked and "x" or " "
            local text = string.format("%s[%s] %s", marker, check, row.label)
            print(string.sub(text, 1, width))
        end
        term.setCursorPos(1, height - 2)
        write(string.sub("< Elozo     Kovetkezo >", 1, width))
        term.setCursorPos(1, height - 1)
        write(string.sub("A:+ uj   D: torol/ki", 1, width))
        term.setCursorPos(1, height)
        write(string.sub("K: kesz", 1, width))

        local event, p1, p2, p3 = os.pullEvent()
        if event == "mouse_click" then
            local x, y = p2, p3
            if y >= 3 and y <= 2 + (last - first + 1) then
                cursor = first + y - 3
                toggleRow(rows[cursor])
            elseif y == height - 2 then
                if x <= math.floor(width / 2) then page = math.max(1, page - 1)
                else page = math.min(pageCount, page + 1) end
                cursor = (page - 1) * pageSize + 1
            elseif y == height - 1 then
                if x <= math.floor(width / 2) then addCustom()
                else deleteRow(rows[cursor]) end
            elseif y == height then
                local ok, reason = saveTargets()
                if not ok then return false, reason end
                return true
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                cursor = math.max(1, cursor - 1)
                page = math.floor((cursor - 1) / pageSize) + 1
            elseif key == keys.down then
                cursor = math.min(#rows, cursor + 1)
                page = math.floor((cursor - 1) / pageSize) + 1
            elseif key == keys.left then
                page = math.max(1, page - 1)
                cursor = (page - 1) * pageSize + 1
            elseif key == keys.right then
                page = math.min(pageCount, page + 1)
                cursor = (page - 1) * pageSize + 1
            elseif key == keys.enter or key == keys.space then
                toggleRow(rows[cursor])
            end
        elseif event == "char" then
            local char = string.lower(p1)
            if char == "a" then addCustom()
            elseif char == "d" then deleteRow(rows[cursor])
            elseif char == "k" then
                local ok, reason = saveTargets()
                if not ok then return false, reason end
                return true
            end
        end
    end
end

function scanner.selectedCount()
    loadTargets()
    local count = 0
    for _, enabled in pairs(selected) do
        if enabled then count = count + 1 end
    end
    return count
end

function scanner.matches(blockData)
    loadTargets()
    return type(blockData) == "table"
        and type(blockData.name) == "string"
        and selected[blockData.name] == true
end

local function coordinatesAfter(pose, move)
    local result = { x = pose.x, y = pose.y, z = pose.z }
    if move.kind == "u" then result.y = result.y + 1
    elseif move.kind == "d" then result.y = result.y - 1
    elseif move.heading == 0 then result.z = result.z + 1
    elseif move.heading == 1 then result.x = result.x + 1
    elseif move.heading == 2 then result.z = result.z - 1
    elseif move.heading == 3 then result.x = result.x - 1 end
    return result
end

local function samePosition(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function endpoint(anchor, path)
    local pose = { x = anchor.x, y = anchor.y, z = anchor.z }
    for _, move in ipairs(path or {}) do pose = coordinatesAfter(pose, move) end
    return pose
end

local function normalizePending(state, pose)
    if type(state.pending) ~= "table" then return true end
    local endBefore = endpoint(state.anchor, state.path)
    local move = state.pending.move
    if state.pending.operation == "push" then
        local endAfter = coordinatesAfter(endBefore, move)
        if samePosition(pose, endAfter) then state.path[#state.path + 1] = copyMove(move)
        elseif not samePosition(pose, endBefore) then return false end
    elseif state.pending.operation == "pop" then
        local parentPath = {}
        for index = 1, math.max(0, #state.path - 1) do
            parentPath[index] = copyMove(state.path[index])
        end
        local parentEnd = endpoint(state.anchor, parentPath)
        if samePosition(pose, parentEnd) then table.remove(state.path)
        elseif not samePosition(pose, endBefore) then return false end
    end
    state.pending = nil
    return true
end

local function createSession(side, api)
    local anchor = api.getPose()
    local state = {
        active = true,
        phase = "ag_vizsgalat",
        side = side,
        branchStep = 0,
        scanLevel = 0,
        surface = "indulas",
        anchor = anchor,
        path = {},
        visited = {},
        veinMined = 0,
    }
    api.checkpoint(state)
    return state
end

local function inverseMove(move)
    if move.kind == "u" then return { kind = "d" } end
    if move.kind == "d" then return { kind = "u" } end
    return { kind = "h", heading = (move.heading + 2) % 4 }
end

local serviceAndReplay

local function enterMove(session, api, move)
    local requiredFuel = #session.path
        + math.abs(session.anchor.x) + math.abs(session.anchor.y)
        + math.abs(session.anchor.z) + (api.fuelReserve or 2) + 2
    if not api.ensureFuel(requiredFuel) then
        local serviced, serviceReason = serviceAndReplay(
            session, api, "Keves fuel az erc-vizsgalati utvonalhoz."
        )
        if not serviced then return false, serviceReason end
    end
    session.pending = { operation = "push", move = copyMove(move) }
    api.checkpoint(session)
    local ok, reason = api.moveOpen(move)
    if not ok then
        session.pending = nil
        api.checkpoint(session)
        return false, reason
    end
    session.path[#session.path + 1] = copyMove(move)
    session.pending = nil
    api.checkpoint(session)
    return true
end

local function leaveMove(session, api)
    local move = session.path[#session.path]
    if not move then return true end
    session.pending = { operation = "pop", move = copyMove(move) }
    api.checkpoint(session)
    local ok, reason = api.moveOpen(inverseMove(move))
    if not ok then
        session.pending = nil
        api.checkpoint(session)
        return false, reason
    end
    table.remove(session.path)
    session.pending = nil
    api.checkpoint(session)
    return true
end

local function clonePath(path)
    local result = {}
    for index, move in ipairs(path) do result[index] = copyMove(move) end
    return result
end

local function retreatToAnchor(session, api)
    while #session.path > 0 do
        local ok, reason = leaveMove(session, api)
        if not ok then return false, reason end
    end
    api.face(session.anchor.heading)
    return true
end

local function retreatWithBranchTorches(session, api, side)
    while #session.path > 0 do
        -- A normal ag-visszauton a path hossza megegyezik az aktualis
        -- agat-lepessel. Igy a fáklya a mar teljesen atvizsgalt cellara kerul.
        if api.placeBranchTorch then
            local placed, reason = api.placeBranchTorch(side, #session.path)
            if not placed then return false, reason end
        end
        local ok, reason = leaveMove(session, api)
        if not ok then return false, reason end
    end
    api.face(session.anchor.heading)
    return true
end

local function replayPath(session, api, path)
    for _, move in ipairs(path) do
        local ok, reason = enterMove(session, api, move)
        if not ok then return false, reason end
    end
    return true
end

serviceAndReplay = function(session, api, reason)
    local resumePath = clonePath(session.path)
    local ok, retreatReason = retreatToAnchor(session, api)
    if not ok then return false, retreatReason end
    session.phase = "erc_kiszolgalas"
    api.checkpoint(session)
    local serviced, serviceReason = api.service(
        reason,
        (2 * (#resumePath + (api.maxBlocks or 16))) + 4
    )
    if not serviced then return false, serviceReason end
    if api.shouldStop() then return false, "Felhasznaloi leallitas." end
    session.phase = "erc_utvonal_visszajatszas"
    api.checkpoint(session)
    local replayed, replayReason = replayPath(session, api, resumePath)
    if not replayed then return false, replayReason end
    session.phase = "erctelep"
    api.checkpoint(session)
    return true
end

local function inspectMove(api, move)
    if move.kind == "u" then return turtle.inspectUp() end
    if move.kind == "d" then return turtle.inspectDown() end
    api.face(move.heading)
    return turtle.inspect()
end

local function keyForPose(pose)
    return tostring(pose.x) .. "," .. tostring(pose.y) .. "," .. tostring(pose.z)
end

local function mineSelectedVein(session, api, firstMove, firstData)
    local baseLength = #session.path
    local maxDepth = api.maxDepth or 4
    local maxBlocks = api.maxBlocks or 16
    local directions = {
        { kind = "h", heading = 0 }, { kind = "h", heading = 1 },
        { kind = "h", heading = 2 }, { kind = "h", heading = 3 },
        { kind = "u" }, { kind = "d" },
    }

    session.phase = "erctelep"
    session.veinMined = 0
    session.visited = {}
    session.minedPositions = {}
    api.checkpoint(session)

    local function enterOre(move, knownData)
        while true do
            if api.shouldStop() then return false, "Felhasznaloi leallitas." end
            local neededFuel = #session.path
                + math.abs(session.anchor.x) + math.abs(session.anchor.y)
                + math.abs(session.anchor.z) + (api.fuelReserve or 2) + 2
            if not api.ensureFuel(neededFuel) then
                local serviced, reason = serviceAndReplay(
                    session, api, "Keves fuel az erckiterohoz."
                )
                if not serviced then return false, reason end
            else
                session.pendingOre = { move = copyMove(move), stage = "before_dig" }
                api.checkpoint(session)
                local dug, code, reason = api.digOre(move, knownData)
                if dug then
                    session.pendingOre.stage = "dug"
                    api.checkpoint(session)
                    local moved, moveReason = enterMove(session, api, move)
                    if not moved then return false, moveReason end
                    session.pendingOre = nil
                    session.veinMined = session.veinMined + 1
                    local pose = api.getPose()
                    local poseKey = keyForPose(pose)
                    session.visited[poseKey] = true
                    session.minedPositions[poseKey] = true
                    api.checkpoint(session)
                    return true
                elseif code == "service" then
                    session.pendingOre = nil
                    api.checkpoint(session)
                    local serviced, serviceReason = serviceAndReplay(
                        session, api, reason or "Az erc mar nem fer az inventoryba."
                    )
                    if not serviced then return false, serviceReason end
                    local exists, refreshed = inspectMove(api, move)
                    if not exists or not scanner.matches(refreshed) then return false, "changed" end
                    knownData = refreshed
                elseif code == "changed" then
                    session.pendingOre = nil
                    api.checkpoint(session)
                    return false, "changed"
                else
                    session.pendingOre = nil
                    api.checkpoint(session)
                    return false, reason or "Az erc nem banyaszhato."
                end
            end
        end
    end

    local entered, enterReason = enterOre(firstMove, firstData)
    if not entered then
        if enterReason == "changed" then return true end
        retreatToAnchor(session, api)
        return false, enterReason
    end

    local stack = { { nextDirection = 1, depth = 1 } }
    while #stack > 0 do
        if api.shouldStop() then
            retreatToAnchor(session, api)
            return false, "Felhasznaloi leallitas."
        end
        local frame = stack[#stack]
        if frame.nextDirection > #directions
            or frame.depth >= maxDepth
            or session.veinMined >= maxBlocks then
            table.remove(stack)
            local ok, reason = leaveMove(session, api)
            if not ok then return false, reason end
        else
            local move = directions[frame.nextDirection]
            frame.nextDirection = frame.nextDirection + 1
            local current = api.getPose()
            local nextPose = coordinatesAfter(current, move)
            local nextKey = keyForPose(nextPose)
            if not session.visited[nextKey] then
                local exists, data = inspectMove(api, move)
                if exists and scanner.matches(data) then
                    local ok, reason = enterOre(move, data)
                    if ok then
                        stack[#stack + 1] = {
                            nextDirection = 1,
                            depth = frame.depth + 1,
                        }
                    elseif reason ~= "changed" then
                        retreatToAnchor(session, api)
                        return false, reason
                    end
                end
            end
        end
    end

    if #session.path ~= baseLength then
        return false, "Az erckitero nem az eredeti agpontra tert vissza."
    end
    session.phase = "ag_vizsgalat"
    session.visited = {}
    api.checkpoint(session)
    return true
end

-- Az oldalagat normal asasa kozben kozvetlenul elol talalt ercteler azonnali
-- kitermelese. A session horgonya az aktualis agcella; a kovetes utan ide es
-- az eredeti facingre ter vissza.
function scanner.mineAhead(side, branchStep, api, firstData)
    loadTargets()
    if not scanner.matches(firstData) then return true, nil, 0 end
    local session = createSession(side, api)
    session.phase = "elore_talalt_ercteler"
    session.branchStep = branchStep or 0
    api.checkpoint(session)
    local firstMove = { kind = "h", heading = session.anchor.heading }
    local mined, reason = mineSelectedVein(session, api, firstMove, firstData)
    local minedCount = session.veinMined or 0
    local minedPositions = session.minedPositions or {}
    if mined then api.face(session.anchor.heading) end
    api.checkpoint(nil)
    return mined, reason, minedCount, minedPositions
end

local function scanSurface(session, api, move, surfaceName)
    session.surface = surfaceName
    api.checkpoint(session)
    local exists, data = inspectMove(api, move)
    if not exists or not scanner.matches(data) then return true end
    return mineSelectedVein(session, api, move, data)
end

local function scanHorizontalLevel(session, api, branchHeading, atEnd, label)
    local ok, reason = scanSurface(
        session, api, { kind = "h", heading = (branchHeading + 3) % 4 }, label .. "_bal"
    )
    if not ok then return false, reason end
    ok, reason = scanSurface(
        session, api, { kind = "h", heading = (branchHeading + 1) % 4 }, label .. "_jobb"
    )
    if not ok then return false, reason end
    if atEnd then
        ok, reason = scanSurface(
            session, api, { kind = "h", heading = branchHeading }, label .. "_veg"
        )
    end
    api.face(branchHeading)
    return ok ~= false, reason
end

local function scanBranchCell(session, api, branchHeading, mode, atEnd)
    local ok, reason
    session.scanLevel = 0
    ok, reason = scanHorizontalLevel(session, api, branchHeading, atEnd, "kozep")
    if not ok then return false, reason end

    if mode == 1 then
        ok, reason = scanSurface(session, api, { kind = "d" }, "padlo")
        if not ok then return false, reason end
        ok, reason = enterMove(session, api, { kind = "u" })
        if not ok then return false, reason end
        session.scanLevel = 1
        ok, reason = scanHorizontalLevel(session, api, branchHeading, atEnd, "felso")
        if ok then ok, reason = scanSurface(session, api, { kind = "u" }, "mennyezet") end
        local left, leftReason = leaveMove(session, api)
        if not left then return false, leftReason end
        if not ok then return false, reason end
    else
        ok, reason = enterMove(session, api, { kind = "u" })
        if not ok then return false, reason end
        session.scanLevel = 1
        ok, reason = scanHorizontalLevel(session, api, branchHeading, atEnd, "felso")
        if ok then ok, reason = scanSurface(session, api, { kind = "u" }, "mennyezet") end
        local left, leftReason = leaveMove(session, api)
        if not left then return false, leftReason end
        if not ok then return false, reason end

        ok, reason = enterMove(session, api, { kind = "d" })
        if not ok then return false, reason end
        session.scanLevel = -1
        ok, reason = scanHorizontalLevel(session, api, branchHeading, atEnd, "also")
        if ok then ok, reason = scanSurface(session, api, { kind = "d" }, "padlo") end
        left, leftReason = leaveMove(session, api)
        if not left then return false, leftReason end
        if not ok then return false, reason end
    end
    session.scanLevel = 0
    api.face(branchHeading)
    api.checkpoint(session)
    return true
end

function scanner.scanBranch(side, branchLength, mode, api, skipSteps)
    loadTargets()
    local session = createSession(side, api)
    local mainHeading = session.anchor.heading
    local branchHeading = side == "left" and (mainHeading + 3) % 4
        or (mainHeading + 1) % 4
    api.face(branchHeading)

    for step = 1, branchLength do
        if api.shouldStop() then
            retreatToAnchor(session, api)
            api.checkpoint(nil)
            return false, "Felhasznaloi leallitas."
        end
        session.branchStep = step
        session.surface = "haladas"
        api.checkpoint(session)
        local moved, moveReason = enterMove(
            session, api, { kind = "h", heading = branchHeading }
        )
        if not moved then
            local returned = retreatToAnchor(session, api)
            if returned then api.checkpoint(nil) end
            return false, moveReason
        end
        local currentKey = keyForPose(api.getPose())
        local alreadyKnown = type(skipSteps) == "table"
            and (skipSteps[currentKey] ~= nil
                or skipSteps[step] ~= nil or skipSteps[tostring(step)] ~= nil)
        local scanned, scanReason = true, nil
        if alreadyKnown then
            session.surface = "elore_mar_kibanyaszva"
            api.checkpoint(session)
        else
            scanned, scanReason = scanBranchCell(
                session, api, branchHeading, mode, step == branchLength
            )
        end
        if not scanned then
            local returned = retreatToAnchor(session, api)
            if returned then api.checkpoint(nil) end
            return false, scanReason
        end
    end

    local returned, returnReason = retreatWithBranchTorches(session, api, side)
    if not returned then return false, returnReason end
    api.checkpoint(nil)
    return true
end

function scanner.recover(savedState, api)
    if type(savedState) ~= "table" or not savedState.active
        or type(savedState.anchor) ~= "table" or type(savedState.path) ~= "table" then
        return true
    end
    if not normalizePending(savedState, api.getPose()) then
        return false, "Az erc-utvonal mentese nem egyezik a fizikai pozicioval."
    end
    api.checkpoint(savedState)
    local returned, reason = retreatToAnchor(savedState, api)
    if not returned then return false, reason end
    api.checkpoint(nil)
    return true
end

return scanner
