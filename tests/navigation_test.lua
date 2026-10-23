local physical = { x = 0, y = 0, z = 0, heading = 0, failForward = 0 }
local vectors = {
    [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 },
}

turtle = {
    turnRight = function() physical.heading = (physical.heading + 1) % 4 return true end,
    turnLeft = function() physical.heading = (physical.heading + 3) % 4 return true end,
    forward = function()
        if physical.failForward > 0 then physical.failForward = physical.failForward - 1 return false end
        local vector = vectors[physical.heading]
        physical.x, physical.z = physical.x + vector.x, physical.z + vector.z
        return true
    end,
    up = function() physical.y = physical.y + 1 return true end,
    down = function() physical.y = physical.y - 1 return true end,
}

local Navigation = require("navigation")
local Coordinate = require("coordinate_navigation")

local function equal(actual, expected, label)
    if actual ~= expected then error(label .. ": vart=" .. tostring(expected) .. " kapott=" .. tostring(actual), 0) end
end

local nav = Navigation.new({ pose = { x = 0, y = 0, z = 0, heading = 0 } })
nav:setAnchor("home")
assert(nav:forward().ok)
assert(nav:face(1).ok)
assert(nav:forward().ok)
assert(nav:up().ok)
local pose = nav:getPose()
equal(pose.x, 1, "relativ x")
equal(pose.y, 1, "relativ y")
equal(pose.z, 1, "relativ z")
equal(#nav.state.path, 3, "utvonal hossza")
assert(nav:returnHome().ok)
pose = nav:getPose()
equal(pose.x, 0, "hazateres x")
equal(pose.y, 0, "hazateres y")
equal(pose.z, 0, "hazateres z")
equal(pose.heading, 0, "hazateres facing")

-- Egy fizikailag mar vegrehajtott, de meg nem konyvelt push helyreallitasa.
local pendingNav = Navigation.new({ state = {
    pose = { x = 0, y = 0, z = 1, heading = 0 },
    path = {},
    pending = { operation = "push", move = { kind = "h", heading = 0 } },
    anchors = { home = { index = 0, pose = { x = 0, y = 0, z = 0, heading = 0 } } },
} })
assert(pendingNav:recoverPending().code == "uncertain_pose")
assert(pendingNav:resolvePending({ x = 0, y = 0, z = 1, heading = 0 }).ok)
equal(#pendingNav.state.path, 1, "pending push konyvelese")

local pendingTurn = Navigation.new({ state = {
    pose = { x = 0, y = 0, z = 0, heading = 0 },
    path = {}, anchors = {},
    pending = { operation = "turn",
        before = { x = 0, y = 0, z = 0, heading = 0 }, heading = 1 },
} })
assert(pendingTurn:recoverPending().code == "uncertain_pose")
assert(pendingTurn:resolvePending({ x = 0, y = 0, z = 0, heading = 1 }).ok)
equal(pendingTurn:getPose().heading, 1, "ellenorzott fordulas")

-- Akadaly utan korlatozott, tobbszoros ujraprobalas.
physical = { x = 0, y = 0, z = 0, heading = 0, failForward = 3 }
local retryNav = Navigation.new({
    pose = { x = 0, y = 0, z = 0, heading = 0 }, retryLimit = 4,
})
local retried = retryNav:step({ kind = "h", heading = 0 }, {
    onBlocked = function() return { action = "retry" } end,
})
assert(retried.ok)
equal(retryNav:getPose().z, 1, "ujraprobalt lepes")

physical = { x = 0, y = 0, z = 0, heading = 0, failForward = 3 }
local limitedNav = Navigation.new({
    pose = { x = 0, y = 0, z = 0, heading = 0 }, retryLimit = 2,
})
local limited = limitedNav:step({ kind = "h", heading = 0 }, {
    onBlocked = function() return { action = "retry" } end,
})
assert(not limited.ok)
equal(limited.code, "retry_limit", "ujraprobalasi limit")

-- Vilagkoordinatak: Eszak=-Z, Kelet=+X, Del=+Z, Nyugat=-X.
physical = { x = 10, y = 64, z = 20, heading = 0, failForward = 0 }
vectors = Coordinate.WORLD_VECTORS
local worldNav = Coordinate.createNavigator({
    pose = { x = 10, y = 64, z = 20, heading = 0 },
})
local plan = assert(Coordinate.plan(
    { x = 10, y = 64, z = 20, heading = 0 },
    { x = 12, y = 65, z = 18, heading = 3 },
    { "y", "x", "z" }
))
equal(plan.minimumMoves, 5, "vilag tavolsag")
assert(Coordinate.execute(worldNav, plan).ok)
pose = worldNav:getPose()
equal(pose.x, 12, "vilag x")
equal(pose.y, 65, "vilag y")
equal(pose.z, 18, "vilag z")
equal(pose.heading, 3, "vilag facing")

return true
