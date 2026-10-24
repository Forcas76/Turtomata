local oldStore = package.loaded.state_store
local oldCoordinator = package.loaded.swarm_coordinator
local files = {}
package.loaded.state_store = {
    read = function(path) return files[path] end,
    write = function(path, value) files[path] = value return true end,
}
package.loaded.swarm_coordinator = nil
local Coordinator = require("swarm_coordinator")

local request = {
    jobId = "10-12345", leaderId = 10, coordinatorId = 25,
    epoch = 1, accepted = true, mainLength = 12,
    branchLength = 4, branchSpacing = 3, tunnelMode = 1,
}
assert(Coordinator.claimAcknowledged(request, 25))
assert(Coordinator.load().status == "registration_only")
local hello = {
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, workerId = 31, slot = 2, physicalConfirmed = true,
}
assert(Coordinator.registerWorker(hello, 31))
assert(Coordinator.registerWorker(hello, 31)) -- duplicate is idempotent
assert(Coordinator.load().workers["31"].slot == 2)
local stationRequest = {
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, slot = 2, chestName = "minecraft:chest",
    physicalConfirmed = true, requestId = "station-31",
}
local stationOk, stationReason, station = Coordinator.registerStation(
    stationRequest, 31)
assert(stationOk, stationReason)
assert(station.id == "D02" and Coordinator.load().stations.D02.verified)
assert(not Coordinator.registerStation(stationRequest, 32))
local cancelled = {
    jobId = request.jobId, coordinatorId = 25, epoch = 1,
    workerId = 35, requestId = "cancel-before-ack",
    joinRequestId = "join-old",
}
assert(Coordinator.leaveWorker(cancelled, 35))
assert(Coordinator.leaveWorker(cancelled, 35))
assert(not Coordinator.registerWorker({
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, workerId = 35, slot = 5, physicalConfirmed = true,
    joinRequestId = "join-old",
}, 35))
local freshJoin = {
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, workerId = 35, slot = 5, physicalConfirmed = true,
    joinRequestId = "join-new",
}
assert(Coordinator.registerWorker(freshJoin, 35))
assert(Coordinator.leaveWorker({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 35, requestId = "leave-new",
}, 35))
assert(not Coordinator.registerWorker(freshJoin, 35))
freshJoin.joinRequestId = "join-again"
assert(Coordinator.registerWorker(freshJoin, 35))
assert(Coordinator.leaveWorker({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 35, requestId = "leave-again",
}, 35))
local conflict = {
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, workerId = 32, slot = 2, physicalConfirmed = true,
}
assert(not Coordinator.registerWorker(conflict, 32))
conflict.slot = 3
conflict.epoch = 0
assert(not Coordinator.registerWorker(conflict, 32))
conflict.epoch = 1
conflict.physicalConfirmed = false
assert(not Coordinator.registerWorker(conflict, 32))
conflict.physicalConfirmed = true
assert(Coordinator.registerWorker(conflict, 32))
local ready = {
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, z = 3, side = "left", mainCompleted = 4,
    leaderPose = { x = 0, y = 0, z = 4, heading = 0 },
}
assert(Coordinator.noteBranchReady(ready, 10))
assert(Coordinator.load().leaderParked ~= true)
assert(Coordinator.load().cells["0,0,0"] == "10")
assert(Coordinator.noteBranchReady(ready, 10))
assert(not Coordinator.noteBranchReady(ready, 11))
ready.z = 4
assert(not Coordinator.noteBranchReady(ready, 10))
ready.z = 3
local leaderRoute = { jobId = request.jobId, epoch = 1,
    coordinatorId = 25, pose = { x = -1, y = 0, z = 0, heading = 0 },
    phase = "parked" }
assert(Coordinator.requestLeaderRoute(leaderRoute, 10))
assert(Coordinator.releaseLeaderRoute(leaderRoute, 10))
assert(Coordinator.load().leaderParked == true)
assert(Coordinator.load().cells["-1,0,0"] == "10")
assert(Coordinator.load().cells["0,0,0"] == nil)
ready.leaderPose = leaderRoute.pose
local claimed, claimReason, branchKey = Coordinator.claimNextBranch(31)
assert(claimed, claimReason)
assert(branchKey == "10-12345:3:left")
assert(Coordinator.claimNextBranch(31))
assert(Coordinator.load().workers["31"].status == "offered_no_motion")
assert(Coordinator.acknowledgeAssignment({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 31, branchKey = branchKey, accepted = true,
}, 31))
assert(Coordinator.load().workers["31"].status == "assigned_no_motion")
assert(not Coordinator.claimNextBranch(32))
assert(Coordinator.markWorkerUncertain(31, "offline"))
assert(Coordinator.load().cells["1,0,0"] == "31")
assert(Coordinator.load().branches[branchKey].owner == "31")
assert(not Coordinator.claimNextBranch(31))
local correction = {
    jobId = request.jobId, coordinatorId = 25, epoch = 1,
    workerId = 31, pose = { x = 4, y = 0, z = 3, heading = 2 },
}
assert(Coordinator.recordPoseCorrection(correction, 31))
assert(Coordinator.load().workers["31"].status == "needs_reconcile")
assert(Coordinator.load().cells["1,0,0"] == "31")
local approved, approveReason = Coordinator.approvePose(31)
assert(approved, approveReason)
assert(Coordinator.load().cells["1,0,0"] == nil)
assert(Coordinator.load().cells["4,0,3"] == "31")
assert(Coordinator.recordPoseCorrection(correction, 31))
assert(Coordinator.load().workers["31"].status == "needs_attention")
assert(not Coordinator.claimNextBranch(31))

ready.side = "right"
assert(Coordinator.noteBranchReady(ready, 10))
local claimedRight, rightReason, rightKey = Coordinator.claimNextBranch(32)
assert(claimedRight, rightReason)
assert(rightKey == "10-12345:3:right")
assert(Coordinator.acknowledgeAssignment({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 32, branchKey = rightKey, accepted = true,
}, 32))
local helper3 = { jobId = request.jobId, leaderId = 10,
    coordinatorId = 25, epoch = 1, workerId = 33,
    slot = 4, physicalConfirmed = true }
assert(Coordinator.registerWorker(helper3, 33))
assert(Coordinator.registerStation({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 33, slot = 4, chestName = "minecraft:chest",
    physicalConfirmed = true, requestId = "station-33",
}, 33))
ready.z, ready.side, ready.mainCompleted = 6, "left", 6
assert(Coordinator.noteBranchReady(ready, 10))
local claimed3, reason3, key3 = Coordinator.claimNextBranch(33)
assert(claimed3, reason3)
assert(Coordinator.acknowledgeAssignment({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 33, branchKey = key3, accepted = true,
}, 33))
local transit = { jobId = request.jobId, epoch = 1,
    coordinatorId = 25, workerId = 32, branchKey = rightKey,
    requestId = "transit-1", phase = "outbound" }
assert(Coordinator.requestTransit(transit, 32))
assert(Coordinator.requestTransit(transit, 32))
assert(Coordinator.load().corridors.entry.owner == "32")
assert(Coordinator.load().corridors.trunk.owner == "32")
local transit3 = { jobId = request.jobId, epoch = 1,
    coordinatorId = 25, workerId = 33, branchKey = key3,
    requestId = "transit-33", phase = "outbound" }
assert(not Coordinator.requestTransit(transit3, 33))
transit.pose = { x = 1, y = 0, z = 3, heading = 1 }
assert(Coordinator.confirmTransitArrival(transit, 32))
assert(Coordinator.confirmTransitArrival(transit, 32))
assert(Coordinator.load().workers["32"].status == "at_branch")
assert(Coordinator.load().corridors.entry == nil)
assert(Coordinator.requestTransit(transit3, 33))
transit3.pose = { x = -1, y = 0, z = 6, heading = 3 }
assert(Coordinator.confirmTransitArrival(transit3, 33))
assert(Coordinator.load().corridors.trunk == nil)
transit.phase, transit.requestId = "inbound", "transit-2"
assert(Coordinator.requestTransit(transit, 32))
assert(Coordinator.load().dockOwner == "32")
transit.pose = { x = 2, y = 0, z = 0, heading = 0 }
assert(Coordinator.confirmTransitArrival(transit, 32))
assert(Coordinator.load().dockOwner == nil)
transit3.phase, transit3.requestId = "inbound", "transit-33-home"
transit3.preferredStationId = "D04"
transit3.needsRefuel = false
transit3.fuelAvailable = 1000
transit3.nextBudget = 100
local ownOk, ownReason, ownTransit = Coordinator.requestTransit(transit3, 33)
assert(ownOk, ownReason)
assert(ownTransit.stationId == "D04" and ownTransit.leaseId)
assert(Coordinator.load().dockOwner == nil)
assert(Coordinator.load().stations.D04.lease.workerId == 33)
assert(Coordinator.reportStationIssue({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 33, stationId = "D04", leaseId = ownTransit.leaseId,
    requestId = transit3.requestId, issue = "full",
    reason = "A lada megtelt.",
}, 33))
assert(Coordinator.load().stations.D04.status == "full")
assert(Coordinator.markWorkerUncertain(33, "partial unload"))
assert(Coordinator.recordPoseCorrection({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 33, pose = { x = 3, y = 0, z = 0, heading = 0 },
}, 33))
assert(Coordinator.approvePose(33))
assert(Coordinator.load().stations.D04.lease == nil)
assert(Coordinator.load().stations.D04.status == "full")
transit.phase, transit.requestId = "outbound", "transit-3"
assert(Coordinator.requestTransit(transit, 32))
assert(Coordinator.markWorkerUncertain(32, "unload"))
assert(not Coordinator.confirmTransitArrival(transit, 32))
local fixSlot = {
    jobId = request.jobId, coordinatorId = 25, epoch = 1,
    workerId = 32, pose = { x = 2, y = 0, z = 0, heading = 0 },
}
assert(Coordinator.recordPoseCorrection(fixSlot, 32))
assert(Coordinator.approvePose(32))
assert(Coordinator.load().corridors.entry == nil)
assert(Coordinator.load().corridors.trunk == nil)
assert(Coordinator.load().workers["32"].transit == nil)
assert(Coordinator.load().workers["32"].status == "assigned_no_motion")
assert(Coordinator.completeBranch({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    workerId = 32, branchKey = rightKey,
}, 32))
local leaving = { jobId = request.jobId, epoch = 1,
    coordinatorId = 25, workerId = 32, requestId = "leave-32" }
assert(Coordinator.leaveWorker(leaving, 32))
assert(Coordinator.leaveWorker(leaving, 32))
assert(Coordinator.load().workers["32"] == nil)
assert(not Coordinator.closeLeader({
    jobId = request.jobId, epoch = 1, coordinatorId = 25,
    leaderId = 10, requestId = "close-1",
}, 10))
assert(Coordinator.emergencyStop())
assert(Coordinator.load().stopped == true)
assert(Coordinator.resumeStopped())
assert(Coordinator.load().stopped == false)
assert(Coordinator.load().recoveryReview == true)
assert(Coordinator.load().workers["31"].status == "uncertain")
assert(Coordinator.emergencyStop())
assert(not Coordinator.requestTransit(transit, 32))
assert(not Coordinator.noteBranchReady(ready, 10))

-- Restartra a mentett tabla nem jogosit uj seged fogadasara ACK nelkul.
package.loaded.swarm_coordinator = nil
Coordinator = require("swarm_coordinator")
local nextWorker = {
    jobId = request.jobId, leaderId = 10, coordinatorId = 25,
    epoch = 1, workerId = 33, slot = 4, physicalConfirmed = true,
}
assert(not Coordinator.registerWorker(nextWorker, 33))
assert(Coordinator.claimAcknowledged(request, 25))
assert(not Coordinator.registerWorker(nextWorker, 33))
assert(not Coordinator.claimAcknowledged(request, 26))

files["swarm_coordinator.txt"] = nil
package.loaded.swarm_coordinator = nil
Coordinator = require("swarm_coordinator")
assert(Coordinator.claimAcknowledged(request, 25))
local closing = { jobId = request.jobId, epoch = 1,
    coordinatorId = 25, leaderId = 10, requestId = "close-new" }
assert(Coordinator.closeLeader(closing, 10))
assert(Coordinator.closeLeader(closing, 10))
assert(Coordinator.load().active == false)

package.loaded.state_store = oldStore
package.loaded.swarm_coordinator = oldCoordinator
return true
