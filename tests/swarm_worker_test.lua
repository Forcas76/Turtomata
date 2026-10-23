local oldSession = package.loaded.swarm_session
local oldSafety = package.loaded.swarm_safety
local oldDock = package.loaded.base_dock
local oldEpoch, oldQueue = os.epoch, os.queueEvent
local oldTurtle, oldRednet, oldParallel = turtle, rednet, parallel
local oldPrintError = printError

local state = {
    version = 1, active = true, role = "worker", status = "assigned_no_motion",
    jobId = "10-100", leaderId = 10, coordinatorId = 25, epoch = 1,
    slot = 2, pose = { x = 1, y = 0, z = 0, heading = 0 },
    mainLength = 6, branchSpacing = 3, branchLength = 2, tunnelMode = 2,
    assignedBranch = "10-100:3:right", assignmentZ = 3,
    assignmentSide = "right", lastHeartbeatAt = 100000,
}
package.loaded.swarm_session = {
    load = function() return state end,
    update = function(value) state = value return true end,
}
package.loaded.swarm_safety = { mayDig = function() return true end }
package.loaded.base_dock = { learnAtBase = function() return true end }
os.epoch = function() return 100000 end
os.queueEvent = function() end
local physical = { x = 1, y = 0, z = 0, heading = 0 }
local selected, fuel = 2, 1000
local floorsDug = 0
local vectors = {
    [0] = { 0, 1 }, [1] = { 1, 0 },
    [2] = { 0, -1 }, [3] = { -1, 0 },
}
turtle = {
    getFuelLevel = function() return fuel end,
    getItemCount = function() return 0 end,
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    inspect = function() return false end,
    inspectUp = function() return false end,
    inspectDown = function()
        if physical.z == 3 and physical.x >= 1 and physical.y == 0 then
            return true, { name = "minecraft:stone" }
        end
        return false
    end,
    digDown = function() floorsDug = floorsDug + 1 return true end,
    turnLeft = function()
        physical.heading = (physical.heading + 3) % 4 return true
    end,
    turnRight = function()
        physical.heading = (physical.heading + 1) % 4 return true
    end,
    forward = function()
        physical.x = physical.x + vectors[physical.heading][1]
        physical.z = physical.z + vectors[physical.heading][2]
        fuel = fuel - 1
        return true
    end,
    up = function() physical.y = physical.y + 1 fuel = fuel - 1 return true end,
    down = function() physical.y = physical.y - 1 fuel = fuel - 1 return true end,
}
local sent, actions = nil, {}
rednet = {
    send = function(_, message)
        sent = message
        actions[#actions + 1] = message.type
        return true
    end,
    receive = function()
        local kind = sent.type == "transit_request" and "transit_grant"
            or sent.type == "transit_arrival" and "transit_arrival_ack"
            or "branch_complete_ack"
        return 25, {
            type = kind, version = 1, jobId = state.jobId,
            epoch = state.epoch, coordinatorId = 25, workerId = 42,
            requestId = sent.requestId, branchKey = sent.branchKey,
            accepted = true,
        }
    end,
}
local oldId = os.getComputerID
os.getComputerID = function() return 42 end
parallel = { waitForAll = function(worker) worker() end }
local errors = {}
printError = function(message) errors[#errors + 1] = message end
package.loaded.swarm_worker = nil
require("swarm_worker")
assert(#errors == 0, errors[1])
assert(physical.x == 1 and physical.y == 0 and physical.z == 0)
assert(physical.heading == 0)
assert(floorsDug == 2)
assert(state.status == "registered_no_motion")
assert(state.assignedBranch == nil and state.branchProgress == nil)
assert(actions[#actions] == "branch_complete")

-- Masik turtle a keresztfolyoson: a seged nem bonthatja/uthet ra.
state.status = "assigned_no_motion"
state.assignedBranch = "10-100:6:right"
state.assignmentZ, state.assignmentSide = 6, "right"
state.pose = { x = 1, y = 0, z = 0, heading = 0 }
state.navigation = nil
state.branchProgress = nil
physical.x, physical.y, physical.z, physical.heading = 1, 0, 0, 0
local digs = 0
turtle.forward = function()
    local nextX = physical.x + vectors[physical.heading][1]
    local nextZ = physical.z + vectors[physical.heading][2]
    if nextX == 0 and nextZ == 1 then return false end
    physical.x, physical.z = nextX, nextZ
    fuel = fuel - 1
    return true
end
turtle.inspect = function()
    if physical.x == 1 and physical.z == 1 and physical.heading == 3 then
        return true, { name = "computercraft:turtle_normal" }
    end
    return false
end
turtle.dig = function() digs = digs + 1 return true end
package.loaded.swarm_safety = nil
package.loaded.swarm_worker = nil
require("swarm_worker")
assert(digs == 0)
assert(physical.x == 1 and physical.z == 1)
assert(state.status == "needs_attention" and state.transit)
assert(#errors == 1)

-- A regi heartbeat nem ad mozgasi jogot, meg akkor sem, ha van kiosztott ag.
state.status = "assigned_no_motion"
state.lastHeartbeatAt = 90000
state.transit, state.navigation = nil, nil
state.pose = { x = 1, y = 0, z = 0, heading = 0 }
physical.x, physical.y, physical.z, physical.heading = 1, 0, 0, 0
package.loaded.swarm_worker = nil
require("swarm_worker")
assert(physical.x == 1 and physical.z == 0)
assert(#errors == 2 and state.status == "needs_attention")

package.loaded.swarm_session = oldSession
package.loaded.swarm_safety = oldSafety
package.loaded.base_dock = oldDock
package.loaded.swarm_worker = nil
os.epoch, os.queueEvent, os.getComputerID = oldEpoch, oldQueue, oldId
turtle, rednet, parallel, printError = oldTurtle, oldRednet, oldParallel, oldPrintError
return true
