local Stations = require("station_registry")
local Scheduler = require("service_scheduler")

local state = {
    epoch = 1, leaderId = 10,
    cells = { ["1,0,0"] = "31", ["2,0,0"] = "32" },
    workers = {
        ["31"] = { slot = 2, status = "at_branch",
            pose = { x = -1, y = 0, z = 6, heading = 3 },
            assignmentZ = 6 },
        ["32"] = { slot = 3, status = "at_branch",
            pose = { x = 1, y = 0, z = 6, heading = 1 },
            assignmentZ = 6 },
    },
}
Stations.ensure(state)
state.stations.D02 = {
    id = "D02", type = "unload_only", ownerSlot = 2,
    pose = { x = 1, y = 0, z = 0 }, chestName = "minecraft:chest",
    enabled = true, verified = true, status = "available",
}
state.stations.D03 = {
    id = "D03", type = "unload_only", ownerSlot = 3,
    pose = { x = 2, y = 0, z = 0 }, chestName = "minecraft:chest",
    enabled = true, verified = true, status = "available",
}
local request = { needsRefuel = false, fuelAvailable = 500,
    nextBudget = 80 }
assert(Stations.canUnload(state, "D02", 32))
assert(Scheduler.choose(state, 32, request) == "D02")
assert(Scheduler.choose(state, 32, { needsRefuel = true,
    fuelAvailable = 500, nextBudget = 80 }) == "D01")
local ok, reason, lease = Stations.reserve(state, "D02", 32, "req-1")
assert(ok, reason)
assert(Stations.reserve(state, "D02", 32, "req-1"))
assert(not Stations.reserve(state, "D02", 31, "req-2"))
assert(Scheduler.choose(state, 31, request) == "D01")
assert(Stations.release(state, "D02", 32, lease.leaseId, true))
state.workers["31"].status = "needs_attention"
assert(not Stations.canUnload(state, "D02", 32))
assert(Scheduler.choose(state, 32, request) == "D03")
state.workers["31"].status = "at_branch"
state.uncertain = { ["31"] = true }
assert(not Stations.canUnload(state, "D02", 32))
state.uncertain = nil
state.stations.D02.status = "full"
assert(not Stations.canUnload(state, "D02", 32))
assert(Scheduler.choose(state, 32, request) == "D03")
state.stations.D03.status = "full"
assert(Scheduler.choose(state, 32, request) == "D01")
return true
