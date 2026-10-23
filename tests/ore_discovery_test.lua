local oldFs, oldTextutils, oldTurtle = fs, textutils, turtle
local oldScanner = package.loaded.ore_scanner
local files, objects, sequence = {}, {}, 0
fs = {
    exists = function(path) return files[path] ~= nil end,
    getName = function(path) return path:match("[^/]+$") end,
    getDir = function() return "" end,
    combine = function(a, b) return a .. "/" .. b end,
    open = function(path, mode)
        if mode == "r" then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end,
                close = function() end }
        end
        return { write = function(value) files[path] = value end,
            close = function() end }
    end,
    delete = function(path) files[path] = nil end,
    move = function(from, to) files[to], files[from] = files[from], nil end,
}
textutils = {
    serializeJSON = function(value)
        sequence = sequence + 1
        objects[tostring(sequence)] = value
        return tostring(sequence)
    end,
    unserializeJSON = function(value) return objects[value] end,
}

local pose = { x = 0, y = 0, z = 0, heading = 0 }
local blocks = {
    ["0,0,1"] = "example:raw_tin_ore",
    ["0,0,2"] = "example:raw_tin_ore",
}
local mined = 0
local vectors = {
    [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 },
}
local function target(move)
    if move.kind == "u" then return pose.x, pose.y + 1, pose.z end
    if move.kind == "d" then return pose.x, pose.y - 1, pose.z end
    local vector = vectors[move.heading]
    return pose.x + vector.x, pose.y, pose.z + vector.z
end
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function inspect(move)
    local x, y, z = target(move)
    local name = blocks[key(x, y, z)]
    if name then return true, { name = name } end
    return false
end
turtle = {
    inspect = function() return inspect({ kind = "h", heading = pose.heading }) end,
    inspectUp = function() return inspect({ kind = "u" }) end,
    inspectDown = function() return inspect({ kind = "d" }) end,
}
package.loaded.ore_scanner = nil
local Scanner = require("ore_scanner")
local api = {
    maxDepth = 4, maxBlocks = 16, fuelReserve = 2,
    getPose = function()
        return { x = pose.x, y = pose.y, z = pose.z, heading = pose.heading }
    end,
    face = function(value) pose.heading = value end,
    moveOpen = function(move)
        if move.kind == "h" then pose.heading = move.heading end
        pose.x, pose.y, pose.z = target(move)
        return true
    end,
    digOre = function(move, _, discoveryId)
        local x, y, z = target(move)
        local where = key(x, y, z)
        if blocks[where] ~= discoveryId then return false, "changed" end
        blocks[where] = nil
        mined = mined + 1
        return true
    end,
    ensureFuel = function() return true end,
    shouldStop = function() return false end,
    checkpoint = function() end,
    service = function() return true end,
}
local candidate = { name = "example:raw_tin_ore" }
assert(Scanner.discoveryId(candidate) == candidate.name)
local ok, reason, count = Scanner.mineAhead("right", 1, api, candidate)
assert(ok, reason)
assert(count == 2 and mined == 2, "Az elso raw telert vegig kell banyaszni.")
assert(Scanner.discoveryId(candidate) == nil,
    "Ugyanaz az ID ne induljon uj ismeretlen telercnek.")
local saved = textutils.unserializeJSON(files["ore_targets.txt"])
assert(saved.pendingCandidates[candidate.name].status == "pending_decision")
blocks["0,0,1"] = candidate.name
ok, reason, count = Scanner.mineAhead("right", 1, api, candidate)
assert(ok and count == 0 and mined == 2,
    "A masodik telert jovahagyasig nem szabad kibanyaszni.")

fs, textutils, turtle = oldFs, oldTextutils, oldTurtle
package.loaded.ore_scanner = oldScanner
return true
