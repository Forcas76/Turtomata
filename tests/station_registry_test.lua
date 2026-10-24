local Stations = require("station_registry")
local state = {
    epoch = 1, leaderId = 10,
    cells = { ["0,0,0"] = "10", ["1,0,0"] = "31" },
    workers = { ["31"] = { slot = 2, status = "registered_no_motion" } },
}
local all = Stations.ensure(state)
assert(all.D01.type == "primary_service" and all.D01.verified == false)
assert(not Stations.canUnload(state, "D01", 31))
assert(not Stations.register(state, 2, 31, "minecraft:stone", true))
assert(not Stations.register(state, 2, 32, "minecraft:chest", true))
local ok, reason, secondary = Stations.register(state, 2, 31,
    "minecraft:chest", true)
assert(ok, reason)
assert(secondary.id == "D02" and secondary.type == "unload_only")
assert(secondary.pose.x == 1 and secondary.chest.z == -1)
assert(Stations.canUnload(state, "D02", 31))
assert(not Stations.canSupply(state, "D02", 31))
assert(not Stations.canUnload(state, "D02", 32)) -- sajat turtle all a cellan
local reserved, reserveReason, lease = Stations.reserve(state, "D02", 31, "req-1")
assert(reserved, reserveReason)
assert(Stations.reserve(state, "D02", 31, "req-1"))
assert(not Stations.reserve(state, "D02", 31, "req-new"))
assert(not Stations.reserve(state, "D02", 32, "req-2"))
assert(not Stations.release(state, "D02", 31, lease.leaseId, false))
state.stations.D02.status = "full"
assert(Stations.release(state, "D02", 31, lease.leaseId, true))
assert(state.stations.D02.status == "full")
assert(Stations.register(state, 1, 10, "minecraft:barrel", true))
assert(Stations.canSupply(state, "D01", 10))
assert(not Stations.register(state, 2, 31, "minecraft:barrel", true))
assert(state.stations.D02.enabled == false)
return true
