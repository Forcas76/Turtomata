-- Az elore talalt ercteler azonnali kovetese es a mar ismert agcella kihagyasa.

fs = {
    exists = function(path) return path == "ore_targets.txt" end,
    open = function()
        return { readAll = function() return "{}" end, close = function() end }
    end,
}
textutils = {
    unserializeJSON = function()
        return {
            version = 1,
            selected = { ["minecraft:coal_ore"] = true },
            custom = {},
        }
    end,
}

local vectors = {
    [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 },
}
local pose = { x = 0, y = 0, z = 0, heading = 0 }
local world = {
    ["0,0,1"] = "minecraft:coal_ore",
    ["0,0,2"] = "minecraft:coal_ore",
}
local inspectedAt = {}

local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function target(move)
    if move.kind == "u" then return pose.x, pose.y + 1, pose.z end
    if move.kind == "d" then return pose.x, pose.y - 1, pose.z end
    local vector = vectors[move.heading]
    return pose.x + vector.x, pose.y, pose.z + vector.z
end
local function inspectMove(move)
    inspectedAt[key(pose.x, pose.y, pose.z)] = (inspectedAt[key(pose.x, pose.y, pose.z)] or 0) + 1
    local x, y, z = target(move)
    local name = world[key(x, y, z)]
    if not name then return false end
    return true, { name = name }
end

turtle = {
    inspect = function() return inspectMove({ kind = "h", heading = pose.heading }) end,
    inspectUp = function() return inspectMove({ kind = "u" }) end,
    inspectDown = function() return inspectMove({ kind = "d" }) end,
}

local api = {
    maxDepth = 4, maxBlocks = 16, fuelReserve = 2,
    getPose = function()
        return { x = pose.x, y = pose.y, z = pose.z, heading = pose.heading }
    end,
    face = function(heading) pose.heading = heading end,
    moveOpen = function(move)
        if move.kind == "h" then pose.heading = move.heading end
        pose.x, pose.y, pose.z = target(move)
        return true
    end,
    digOre = function(move)
        local x, y, z = target(move)
        local cell = key(x, y, z)
        if world[cell] ~= "minecraft:coal_ore" then return false, "changed" end
        world[cell] = nil
        return true
    end,
    ensureFuel = function() return true end,
    shouldStop = function() return false end,
    checkpoint = function() end,
    service = function() return true end,
}

package.loaded["ore_scanner"] = nil
local Scanner = require("ore_scanner")
local mined, reason, count, positions = Scanner.mineAhead(
    "right", 1, api, { name = "minecraft:coal_ore" }
)
assert(mined, reason)
assert(count == 2)
assert(positions["0,0,1"] and positions["0,0,2"])
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.heading == 0)

-- Az x=1 agcella ismert: ott egyetlen felulet-inspect sem tortenhet.
pose = { x = 0, y = 0, z = 0, heading = 0 }
world = {}
inspectedAt = {}
local torchSteps = {}
api.placeBranchTorch = function(side, step)
    torchSteps[#torchSteps + 1] = side .. ":" .. step
    return true
end
local scanned, scanReason = Scanner.scanBranch(
    "right", 2, 1, api, { ["1,0,0"] = true }
)
assert(scanned, scanReason)
assert((inspectedAt["1,0,0"] or 0) == 0)
assert((inspectedAt["2,0,0"] or 0) > 0)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0)
assert(torchSteps[1] == "right:2" and torchSteps[2] == "right:1",
    "Az erckereses visszautja nem kezelte a faklyapontokat.")

-- A frissen kiásott ág végéről közvetlenül visszafelé vizsgáljon:
-- nincs még egy oda-vissza bejárás.
pose = { x = 2, y = 0, z = 0, heading = 1 }
world, inspectedAt, torchSteps = {}, {}, {}
local horizontalMoves = 0
local normalMove = api.moveOpen
api.moveOpen = function(move)
    if move.kind == "h" then horizontalMoves = horizontalMoves + 1 end
    return normalMove(move)
end
scanned, scanReason = Scanner.scanReturnBranch("right", 2, 1, api)
assert(scanned, scanReason)
assert(horizontalMoves == 2, "A vizsgalat ne jarja be ujra kifele az agat.")
assert(pose.x == 0 and pose.y == 0 and pose.z == 0 and pose.heading == 0)
assert(torchSteps[1] == "right:2" and torchSteps[2] == "right:1")

-- Megszakitas utan a mar kesz csucscellat ne vizsgalja ujra.
pose = { x = 2, y = 0, z = 0, heading = 1 }
world, inspectedAt, torchSteps = {}, {}, {}
local savedSession
api.checkpoint = function(session) savedSession = session end
api.shouldStop = function() return pose.x == 1 end
scanned = Scanner.scanReturnBranch("right", 2, 1, api)
assert(not scanned and savedSession and savedSession.returnScan)
assert(savedSession.branchStep == 1 and pose.x == 1)
api.shouldStop = function() return false end
local inspectedAtTip = inspectedAt["2,0,0"] or 0
scanned, scanReason = Scanner.resumeReturnBranch(savedSession, 2, 1, api)
assert(scanned, scanReason)
assert((inspectedAt["2,0,0"] or 0) == inspectedAtTip)
assert(pose.x == 0 and pose.y == 0 and pose.z == 0)
assert(torchSteps[1] == "right:2" and torchSteps[2] == "right:1")

-- Kihagyas csak cellahataron lep eletbe; a visszaut es a faklyak megmaradnak.
pose = { x = 2, y = 0, z = 0, heading = 1 }
world, inspectedAt, torchSteps = {}, {}, {}
local skipped = {}
api.shouldSkipScan = function() return true end
api.markSkipped = function(side, step)
    skipped[#skipped + 1] = side .. ":" .. step
end
scanned, scanReason = Scanner.scanReturnBranch("right", 2, 1, api)
assert(scanned, scanReason)
assert((inspectedAt["2,0,0"] or 0) == 0)
assert((inspectedAt["1,0,0"] or 0) == 0)
assert(skipped[1] == "right:2" and skipped[2] == "right:1")
assert(torchSteps[1] == "right:2" and torchSteps[2] == "right:1")
assert(pose.x == 0 and pose.y == 0 and pose.z == 0)

-- Kozos agban a scanner nem lephet vissza a foagi cellaba utvonaljog nelkul.
pose = { x = 2, y = 0, z = 0, heading = 1 }
world, inspectedAt, torchSteps = {}, {}, {}
api.stopBeforeAnchor = true
api.shouldSkipScan = nil
scanned, scanReason = Scanner.scanReturnBranch("right", 2, 1, api)
assert(scanned, scanReason)
assert(pose.x == 1 and pose.y == 0 and pose.z == 0)
api.stopBeforeAnchor = nil

return true
