local oldStore = package.loaded.state_store
local oldCoordinator = package.loaded.swarm_coordinator
local files = {}
package.loaded.state_store = {
    read = function(path) return files[path] end,
    write = function(path, value) files[path] = value return true end,
}
package.loaded.swarm_coordinator = nil
local Coordinator = require("swarm_coordinator")
local identity = {
    jobId = "dynamic-1", leaderId = 10, coordinatorId = 25,
    epoch = 1, mainLength = 12, branchLength = 4,
    branchSpacing = 3, tunnelMode = 1,
}
local claim = {}
for key, value in pairs(identity) do claim[key] = value end
claim.accepted = true
assert(Coordinator.claimAcknowledged(claim, 25))
local worker = {}
for key, value in pairs(identity) do worker[key] = value end
worker.workerId, worker.slot, worker.physicalConfirmed = 31, 2, true
assert(Coordinator.registerWorker(worker, 31))

local ready = {}
for key, value in pairs(identity) do ready[key] = value end
ready.z, ready.side, ready.mainCompleted = 3, "left", 4
ready.leaderPose = { x = 0, y = 0, z = 4, heading = 0 }
assert(Coordinator.noteBranchReady(ready, 10))
assert(not Coordinator.load().leaderParked)
local assigned, reason, branch = Coordinator.claimNextBranch(31)
assert(assigned, reason)
assert(Coordinator.acknowledgeAssignment({
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, branchKey = branch, accepted = true,
}, 31))
local transit = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, branchKey = branch,
    requestId = "out-1", phase = "outbound",
}
assert(Coordinator.requestTransit(transit, 31))
local route = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    requestId = "leader-return", phase = "return",
}
assert(not Coordinator.requestLeaderRoute(route, 10))
assert(Coordinator.load().leaderTravel == "return_pending")
assert(Coordinator.requestTransit(transit, 31)) -- elveszett grant ACK ujrakerese
transit.pose = { x = -1, y = 0, z = 3, heading = 3 }
assert(Coordinator.confirmTransitArrival(transit, 31))
assert(Coordinator.requestLeaderRoute(route, 10))
assert(Coordinator.load().leaderTravel == "exclusive")
route.phase, route.pose = "forward", { x = 0, y = 0, z = 4, heading = 0 }
assert(Coordinator.releaseLeaderRoute(route, 10))
assert(Coordinator.load().leaderTravel == "forward")

ready.side = "right"
assert(Coordinator.noteBranchReady(ready, 10))
local nextQuery = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, branchKey = branch,
}
local offered, offerReason, target = Coordinator.queryNextBranch(nextQuery, 31)
assert(offered and target == "dynamic-1:3:right", offerReason)
local handoff = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, requestId = "transfer-1",
    fromBranch = branch, targetBranch = target,
    pose = { x = -1, y = 0, z = 3, heading = 3 },
}
assert(Coordinator.requestBranchTransfer(handoff, 31))
assert(Coordinator.requestBranchTransfer(handoff, 31)) -- elveszett ACK
assert(Coordinator.load().branches[branch].status == "claimed")
assert(not Coordinator.requestLeaderRoute(route, 10))
local arrival = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, requestId = "transfer-1", phase = "transfer",
    pose = { x = 1, y = 0, z = 3, heading = 1 },
}
assert(Coordinator.confirmTransitArrival(arrival, 31))
assert(Coordinator.load().branches[branch].status == "complete")
assert(Coordinator.load().workers["31"].assignedBranch == target)
assert(Coordinator.requestLeaderRoute(route, 10))
route.phase, route.pose = "forward", { x = 0, y = 0, z = 7, heading = 0 }
assert(Coordinator.releaseLeaderRoute(route, 10))
ready.z, ready.side, ready.mainCompleted = 6, "left", 7
ready.leaderPose = { x = 0, y = 0, z = 7, heading = 0 }
assert(Coordinator.noteBranchReady(ready, 10))
handoff.requestId = "transfer-2"
handoff.fromBranch, handoff.targetBranch = target, "dynamic-1:6:left"
handoff.pose = { x = 1, y = 0, z = 3, heading = 1 }
assert(Coordinator.requestBranchTransfer(handoff, 31))
assert(Coordinator.markWorkerUncertain(31))
local correction = {
    jobId = identity.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, pose = { x = 1, y = 0, z = 3, heading = 1 },
}
assert(Coordinator.recordPoseCorrection(correction, 31))
assert(Coordinator.approvePose(31))
assert(Coordinator.load().branches["dynamic-1:6:left"].status == "ready")
assert(Coordinator.load().workers["31"].assignedBranch == target)
handoff.requestId = "transfer-3"
assert(Coordinator.requestBranchTransfer(handoff, 31))
assert(Coordinator.markWorkerUncertain(31))
correction.pose = { x = -1, y = 0, z = 6, heading = 3 }
assert(Coordinator.recordPoseCorrection(correction, 31))
assert(Coordinator.approvePose(31))
assert(Coordinator.load().branches[target].status == "complete")
assert(Coordinator.load().workers["31"].assignedBranch == "dynamic-1:6:left")
ready.side = "right"
assert(Coordinator.noteBranchReady(ready, 10))
assert(Coordinator.requestLeaderRoute(route, 10))
route.phase, route.pose = "parked", { x = -1, y = 0, z = 0, heading = 0 }
assert(Coordinator.releaseLeaderRoute(route, 10))
assert(Coordinator.load().workers["10"].status == "registered_no_motion")
local leaderAssigned, leaderReason = Coordinator.claimNextBranch(10)
assert(leaderAssigned, leaderReason)

package.loaded.state_store = oldStore
package.loaded.swarm_coordinator = oldCoordinator
return true
