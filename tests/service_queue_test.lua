local oldStore = package.loaded.state_store
local oldCoordinator = package.loaded.swarm_coordinator
local files = {}
package.loaded.state_store = {
    read = function(path) return files[path] end,
    write = function(path, value) files[path] = value return true end,
}
package.loaded.swarm_coordinator = nil
local Coordinator = require("swarm_coordinator")
local claim = { accepted = true, jobId = "10-queue", leaderId = 10,
    coordinatorId = 25, epoch = 1, mainLength = 12,
    branchLength = 4, branchSpacing = 3, tunnelMode = 1 }
assert(Coordinator.claimAcknowledged(claim, 25))
local state = Coordinator.load()
state.leaderParked = true
state.workers = {
    ["31"] = { slot = 2, status = "at_branch",
        assignedBranch = "10-queue:3:left",
        pose = { x = -1, y = 0, z = 3, heading = 3 } },
    ["32"] = { slot = 3, status = "at_branch",
        assignedBranch = "10-queue:6:right",
        pose = { x = 1, y = 0, z = 6, heading = 1 } },
}
state.corridors = { entry = { owner = "99", direction = "home" },
    trunk = { owner = "99", direction = "home" } }
files["swarm_coordinator.txt"] = state
local function request(id, branch, requestId)
    return { jobId = claim.jobId, coordinatorId = 25, epoch = 1,
        workerId = id, branchKey = branch, requestId = requestId,
        phase = "inbound", needsRefuel = true,
        fuelAvailable = 1000, nextBudget = 100 }
end
local first = request(31, "10-queue:3:left", "req-31")
local second = request(32, "10-queue:6:right", "req-32")
assert(not Coordinator.requestTransit(first, 31))
assert(not Coordinator.requestTransit(second, 32))
assert(#Coordinator.load().serviceQueue == 2)
assert(Coordinator.load().serviceQueue[1].workerId == 31)
state.corridors = {}
assert(not Coordinator.requestTransit(second, 32),
    "A kesobb erkezo keres nem elozi meg a sort.")
assert(Coordinator.requestTransit(first, 31))
assert(#Coordinator.load().serviceQueue == 1)
assert(Coordinator.load().serviceQueue[1].workerId == 32)
assert(not Coordinator.requestTransit(second, 32))
first.pose = { x = 1, y = 0, z = 0, heading = 0 }
assert(Coordinator.confirmTransitArrival(first, 31))
assert(Coordinator.requestTransit(second, 32))
assert(#Coordinator.load().serviceQueue == 0)
second.pose = { x = 2, y = 0, z = 0, heading = 0 }
assert(Coordinator.confirmTransitArrival(second, 32))

-- Husz szervizkeres tartos FIFO-sorban, egyetlen D01-dokkjoggal.
local pending = {}
state.corridors = { entry = { owner = "99", direction = "home" },
    trunk = { owner = "99", direction = "home" } }
for id = 31, 50 do
    local worker = state.workers[tostring(id)]
    if not worker then
        worker = { slot = id - 29 }
        state.workers[tostring(id)] = worker
    end
    worker.status = "at_branch"
    worker.transit = nil
    worker.assignedBranch = "10-queue:6:right"
    worker.pose = { x = 1, y = 0, z = 6, heading = 1 }
    pending[#pending + 1] = request(id, worker.assignedBranch,
        "bulk-" .. id)
    assert(not Coordinator.requestTransit(pending[#pending], id))
end
assert(#Coordinator.load().serviceQueue == 20)
package.loaded.swarm_coordinator = nil
Coordinator = require("swarm_coordinator")
assert(not Coordinator.requestTransit(pending[1], 31),
    "Ujrainditas utan nincs automatikus jog.")
assert(Coordinator.claimAcknowledged(claim, 25))
assert(#Coordinator.load().serviceQueue == 20)
state.corridors = {}
for index, item in ipairs(pending) do
    local id = item.workerId
    assert(Coordinator.load().serviceQueue[1].workerId == id)
    assert(Coordinator.requestTransit(item, id))
    assert(Coordinator.load().dockOwner == tostring(id))
    assert(#Coordinator.load().serviceQueue == 20 - index)
    item.pose = { x = id - 30, y = 0, z = 0, heading = 0 }
    assert(Coordinator.confirmTransitArrival(item, id))
    assert(Coordinator.load().dockOwner == nil)
end
assert(#Coordinator.load().serviceQueue == 0)
state.corridors = { entry = { owner = "99", direction = "home" },
    trunk = { owner = "99", direction = "home" } }
state.workers["31"].status = "at_branch"
state.workers["31"].assignedBranch = "10-queue:6:right"
local stale = request(31, "10-queue:6:right", "old-request")
assert(not Coordinator.requestTransit(stale, 31))
assert(#Coordinator.load().serviceQueue == 1)
assert(Coordinator.recordPoseCorrection({ jobId = claim.jobId,
    coordinatorId = 25, epoch = 1, workerId = 31,
    pose = { x = 1, y = 0, z = 6, heading = 1 } }, 31))
assert(#Coordinator.load().serviceQueue == 0)
assert(Coordinator.approvePose(31))
assert(Coordinator.load().workers["31"].status == "at_branch",
    tostring(Coordinator.load().workers["31"].status) .. " / "
    .. tostring(Coordinator.load().workers["31"].assignedBranch) .. " / "
    .. tostring(Coordinator.load().workers["31"].pose.x) .. ","
    .. tostring(Coordinator.load().workers["31"].pose.z) .. " / "
    .. tostring(Coordinator.load().workers["31"].pose.heading))
assert(not Coordinator.requestTransit(request(31,
    "10-queue:6:right", "new-request"), 31))
assert(Coordinator.load().serviceQueue[1].requestId == "new-request")

package.loaded.state_store = oldStore
package.loaded.swarm_coordinator = oldCoordinator
return true
