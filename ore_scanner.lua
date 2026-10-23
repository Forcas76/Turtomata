-- KISERLETI ercdetektalo es erctelep-koveto CC:Tweaked turtle-okhoz.
-- A modul csak a branch miner altal atadott, poziciokovetett mozgasokat hasznalja.

local scanner = {}
local UI = require("ui")
local StateStore = require("state_store")

local TARGETS_FILE = "ore_targets.txt"

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
local customGroups = {}
local pendingCandidates = {}
local rejectedIds = {}
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
    local saved = StateStore.read(TARGETS_FILE)
    if type(saved) ~= "table"
        or (saved.version ~= 1 and saved.version ~= 2) then return end
    if type(saved.selected) == "table" then selected = saved.selected end
    if type(saved.custom) == "table" then custom = saved.custom end
    if type(saved.customGroups) == "table" then
        customGroups = saved.customGroups
    end
    if type(saved.pendingCandidates) == "table" then
        pendingCandidates = saved.pendingCandidates
    end
    if type(saved.rejectedIds) == "table" then rejectedIds = saved.rejectedIds end
end

local function saveTargets()
    return StateStore.write(TARGETS_FILE, {
        version = 2,
        selected = selected,
        custom = custom,
        customGroups = customGroups,
        pendingCandidates = pendingCandidates,
        rejectedIds = rejectedIds,
    })
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
    for index, group in ipairs(customGroups) do
        rows[#rows + 1] = {
            kind = "customGroup", index = index, label = group.label,
            checked = groupChecked(group),
        }
    end
    local candidateIds = {}
    for id in pairs(pendingCandidates) do candidateIds[#candidateIds + 1] = id end
    table.sort(candidateIds)
    for _, id in ipairs(candidateIds) do
        rows[#rows + 1] = {
            kind = "candidate", id = id,
            label = "? " .. id, checked = false,
        }
    end
    local rejected = {}
    for id in pairs(rejectedIds) do rejected[#rejected + 1] = id end
    table.sort(rejected)
    for _, id in ipairs(rejected) do
        rows[#rows + 1] = {
            kind = "rejected", id = id,
            label = "- " .. id, checked = false,
        }
    end
    return rows
end

local function validBlockName(value)
    return type(value) == "string"
        and string.match(value, "^[a-z0-9_.-]+:[a-z0-9_./-]+$") ~= nil
end

local function readBlockId()
    write("Blokk ID (mod:blokk): ")
    local value = string.lower(read() or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if not value:find(":", 1, true)
        and value:match("^[a-z0-9_./-]+$") then
        value = "minecraft:" .. value
    end
    if validBlockName(value) then return value end
    printError("Hibas ID. Pelda: create:zinc_ore")
    sleep(1.5)
    return nil
end

local function addCustom()
    clearScreen()
    print("=== UJ ERCCSOPORT ===")
    write("Csoport neve: ")
    local label = (read() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then return false end
    local value = readBlockId()
    if not value then return false end
    customGroups[#customGroups + 1] = { label = label, ids = { value } }
    selected[value], pendingCandidates[value], rejectedIds[value] = true, nil, nil
    return true
end

local function addToGroup(row)
    if not row or row.kind ~= "customGroup" then return false end
    clearScreen()
    print("Csoport: " .. customGroups[row.index].label)
    local id = readBlockId()
    if not id then return false end
    local group = customGroups[row.index]
    for _, existing in ipairs(group.ids) do
        if existing == id then return true end
    end
    group.ids[#group.ids + 1] = id
    selected[id], pendingCandidates[id], rejectedIds[id] = true, nil, nil
    return true
end

local function decideCandidate(row)
    if not row or row.kind ~= "candidate" then return end
    local choice = UI.choice("UJ RAW BLOKK", {
        "Uj csoport", "Meglevo csoport", "Elutasitas", "Vissza",
    })
    if choice == 1 then
        local label = UI.input("UJ CSOPORT", "Nev", row.id)
        if label and label ~= "" then
            customGroups[#customGroups + 1] = { label = label, ids = { row.id } }
            selected[row.id], pendingCandidates[row.id] = true, nil
        end
    elseif choice == 2 then
        local labels = {}
        for _, group in ipairs(customGroups) do labels[#labels + 1] = group.label end
        if #labels == 0 then return end
        local index = UI.choice("CSOPORT", labels)
        if index then
            customGroups[index].ids[#customGroups[index].ids + 1] = row.id
            selected[row.id], pendingCandidates[row.id] = true, nil
        end
    elseif choice == 3 then
        rejectedIds[row.id], pendingCandidates[row.id] = true, nil
    end
end

local function toggleRow(row)
    if row.kind == "group" then
        toggleGroup(groups[row.index])
    elseif row.kind == "customGroup" then
        toggleGroup(customGroups[row.index])
    elseif row.kind == "candidate" then
        decideCandidate(row)
    elseif row.kind == "custom" then
        local name = custom[row.index]
        selected[name] = selected[name] and nil or true
    end
end

local function deleteRow(row)
    if not row then return false end
    local action = row.kind == "group" and "beepitett csoport kikapcsolasa"
        or row.kind == "candidate" and "jelolt elutasitasa"
        or row.kind == "rejected" and "elutasitas torlese"
        or "torles"
    if not UI.confirm("ERCLISTA MEGEROSITES", {
        row.label,
        "Muvelet: " .. action,
        "A mentes a K: kesz gombbal tortenik.",
    }, "ENTER = megerosites") then return false end
    if row.kind == "group" then
        -- A beepitett vanilla sor megmarad, de minden valtozata kikapcsol.
        for _, name in ipairs(groups[row.index].ids) do selected[name] = nil end
        return true
    end
    if row.kind == "candidate" then
        rejectedIds[row.id], pendingCandidates[row.id] = true, nil
        return true
    end
    if row.kind == "rejected" then
        rejectedIds[row.id] = nil
        return true
    end
    if row.kind == "customGroup" then
        local group = table.remove(customGroups, row.index)
        for _, id in ipairs(group.ids) do selected[id] = nil end
        return true
    end
    local name = custom[row.index]
    if not name then return false end
    selected[name] = nil
    table.remove(custom, row.index)
    return true
end

local function viewRow(row)
    if not row then return end
    local group = row.kind == "group" and groups[row.index]
        or row.kind == "customGroup" and customGroups[row.index]
    local lines = {}
    if group then
        for index, id in ipairs(group.ids) do
            lines[#lines + 1] = index .. ". " .. id
        end
    elseif row.kind == "custom" or row.kind == "candidate"
        or row.kind == "rejected" then
        lines[1] = row.id or row.label
    end
    if #lines == 0 then return end
    UI.confirm("BLOKK ID-K: " .. row.label, lines, "ENTER = vissza")
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
        write(string.sub("A:+cs E:+ID V:lista D:torol", 1, width))
        term.setCursorPos(1, height)
        write(string.sub("K: kesz", 1, width))

        local event, p1, p2, p3 = os.pullEvent()
        if event == "mouse_click" then
            local x, y = p2, p3
            if y >= 3 and y <= 2 + (last - first + 1) then
                cursor = first + y - 3
                if x <= 4 then toggleRow(rows[cursor])
                else viewRow(rows[cursor]) end
            elseif y == height - 2 then
                if x <= math.floor(width / 2) then page = math.max(1, page - 1)
                else page = math.min(pageCount, page + 1) end
                cursor = (page - 1) * pageSize + 1
            elseif y == height - 1 then
                if x <= math.floor(width / 4) then addCustom()
                elseif x <= math.floor(width / 2) then addToGroup(rows[cursor])
                elseif x <= math.floor(width * 3 / 4) then viewRow(rows[cursor])
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
            elseif char == "e" then addToGroup(rows[cursor])
            elseif char == "v" then viewRow(rows[cursor])
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

local function knownId(id)
    if selected[id] ~= nil then return true end
    for _, group in ipairs(groups) do
        for _, name in ipairs(group.ids) do
            if name == id then return true end
        end
    end
    for _, entry in ipairs(custom) do
        if entry == id then return true end
    end
    for _, group in ipairs(customGroups) do
        for _, name in ipairs(group.ids) do
            if name == id then return true end
        end
    end
    return false
end

function scanner.discoveryId(blockData)
    loadTargets()
    local id = type(blockData) == "table" and blockData.name
    if type(id) ~= "string" or knownId(id)
        or rejectedIds[id] or pendingCandidates[id] then return nil end
    local basename = id:match("^[^:]+:(.+)$") or id
    return basename:find("raw", 1, true) and id or nil
end

local function beginDiscovery(id, pose)
    pendingCandidates[id] = {
        status = "in_progress",
        x = pose.x, y = pose.y, z = pose.z,
        mined = 0,
    }
    local ok, reason = saveTargets()
    if not ok then pendingCandidates[id] = nil end
    return ok, reason
end

local function finishDiscovery(id, mined)
    local candidate = pendingCandidates[id]
    if not candidate then return true end
    candidate.status = "pending_decision"
    candidate.mined = mined or 0
    return saveTargets()
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

local function mineSelectedVein(session, api, firstMove, firstData, discoveryId)
    local baseLength = #session.path
    local maxDepth = api.maxDepth or 4
    local maxBlocks = api.maxBlocks or 16
    local directions = {
        { kind = "h", heading = 0 }, { kind = "h", heading = 1 },
        { kind = "h", heading = 2 }, { kind = "h", heading = 3 },
        { kind = "u" }, { kind = "d" },
    }

    session.phase = "erctelep"
    session.discoveryId = discoveryId
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
                local dug, code, reason = api.digOre(move, knownData, discoveryId)
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
                    if not exists or not (scanner.matches(refreshed)
                        or discoveryId and refreshed.name == discoveryId) then
                        return false, "changed"
                    end
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
                if exists and (scanner.matches(data)
                    or discoveryId and data.name == discoveryId) then
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
    local discoveryId = scanner.discoveryId(firstData)
    if not scanner.matches(firstData) and not discoveryId then
        return true, nil, 0
    end
    local session = createSession(side, api)
    session.phase = "elore_talalt_ercteler"
    session.branchStep = branchStep or 0
    if discoveryId then
        local saved, saveReason = beginDiscovery(discoveryId, session.anchor)
        if not saved then return false, saveReason end
    end
    api.checkpoint(session)
    local firstMove = { kind = "h", heading = session.anchor.heading }
    local mined, reason = mineSelectedVein(
        session, api, firstMove, firstData, discoveryId
    )
    local minedCount = session.veinMined or 0
    local minedPositions = session.minedPositions or {}
    if mined then api.face(session.anchor.heading) end
    api.checkpoint(nil)
    if discoveryId and mined then
        local saved, saveReason = finishDiscovery(discoveryId, minedCount)
        if not saved then return false, saveReason, minedCount, minedPositions end
    end
    return mined, reason, minedCount, minedPositions
end

local function scanSurface(session, api, move, surfaceName)
    session.surface = surfaceName
    api.checkpoint(session)
    local exists, data = inspectMove(api, move)
    local discoveryId = exists and scanner.discoveryId(data)
    if not exists or not scanner.matches(data) and not discoveryId then
        return true
    end
    if discoveryId then
        local saved, saveReason = beginDiscovery(discoveryId, api.getPose())
        if not saved then return false, saveReason end
    end
    local mined, reason = mineSelectedVein(session, api, move, data, discoveryId)
    if discoveryId and mined then
        local saved, saveReason = finishDiscovery(discoveryId, session.veinMined)
        if not saved then return false, saveReason end
        session.discoveryId = nil
        api.checkpoint(session)
    end
    return mined, reason
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

-- A banyaszat vege mar a mellekag csucsan van. Innen egyetlen visszauton
-- vizsgaljuk at a cellakat es helyezzuk el a faklyakat.
function scanner.scanReturnBranch(side, branchLength, mode, api, resumed)
    loadTargets()
    local tip = api.getPose()
    local branchHeading = resumed and resumed.branchHeading or tip.heading
    local vectors = {
        [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 },
        [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 },
    }
    local vector = vectors[branchHeading]
    local mainHeading = side == "left" and (branchHeading + 1) % 4
        or (branchHeading + 3) % 4
    local anchor = {
        x = tip.x - vector.x * branchLength,
        y = tip.y,
        z = tip.z - vector.z * branchLength,
        heading = mainHeading,
    }
    local session = resumed or {
        active = true, phase = "ag_visszaut_vizsgalat", side = side,
        branchStep = branchLength, scanLevel = 0, surface = "indulas",
        anchor = anchor, path = {}, visited = {}, veinMined = 0,
        returnScan = true, branchHeading = branchHeading,
    }
    if not resumed then
        for _ = 1, branchLength do
            session.path[#session.path + 1] = { kind = "h", heading = branchHeading }
        end
    end
    api.checkpoint(session)
    for step = session.branchStep, 1, -1 do
        if api.shouldStop() then return false, "Felhasznaloi leallitas." end
        session.branchStep = step
        api.checkpoint(session)
        local scanned, reason = scanBranchCell(
            session, api, branchHeading, mode, step == branchLength
        )
        if not scanned then return false, reason end
        if api.placeBranchTorch then
            local placed, torchReason = api.placeBranchTorch(side, step)
            if not placed then return false, torchReason end
        end
        local moved, moveReason = leaveMove(session, api)
        if not moved then return false, moveReason end
        session.branchStep = step - 1
        api.checkpoint(session)
    end
    api.face(mainHeading)
    api.checkpoint(nil)
    return true
end

function scanner.resumeReturnBranch(savedState, branchLength, mode, api)
    if type(savedState) ~= "table" or not savedState.returnScan
        or type(savedState.path) ~= "table" then
        return false, "Nincs visszauti agvizsgalati mentes."
    end
    if savedState.pending or savedState.pendingOre then
        return false, "Fuggo erc-lepes: a fizikai helyzetet kezzel ellenorizni kell."
    end
    local step = math.min(savedState.branchStep or #savedState.path, branchLength)
    while #savedState.path > step do
        local ok, reason = leaveMove(savedState, api)
        if not ok then return false, reason end
    end
    if savedState.discoveryId then
        local ok, reason = finishDiscovery(savedState.discoveryId,
            savedState.veinMined or 0)
        if not ok then return false, reason end
        savedState.discoveryId = nil
    end
    savedState.branchStep = math.min(step, #savedState.path)
    api.checkpoint(savedState)
    return scanner.scanReturnBranch(savedState.side, branchLength, mode,
        api, savedState)
end

function scanner.recover(savedState, api)
    if type(savedState) ~= "table" or not savedState.active
        or type(savedState.anchor) ~= "table" or type(savedState.path) ~= "table" then
        return true
    end
    if savedState.pending or savedState.pendingOre then
        return false, "Fuggo erc-lepes: a fizikai helyzetet kezzel ellenorizni kell."
    end
    api.checkpoint(savedState)
    local returned, reason = retreatToAnchor(savedState, api)
    if not returned then return false, reason end
    if savedState.discoveryId then
        local ok, saveReason = finishDiscovery(savedState.discoveryId,
            savedState.veinMined or 0)
        if not ok then return false, saveReason end
    end
    api.checkpoint(nil)
    return true
end

return scanner
