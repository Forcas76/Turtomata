local Estimator = require("swarm_estimator")
local state = {
    jobId = "eta-job", leaderId = 10,
    mainLength = 12, branchLength = 4, branchSpacing = 3,
    tunnelMode = 1, startedAt = 1000,
    workConfig = { defaultActionSeconds = 0.8,
        oreScanEnabled = true, torchEnabled = true,
        branchTorchInterval = 2, mainTorchInterval = 4 },
    branches = {}, workers = {
        ["31"] = { slot = 2, status = "registered_no_motion" },
    },
}
local members = {
    [10] = { online = true, progressCurrent = 4,
        swarm = { role = "leader" } },
    [31] = { online = true, progressCurrent = 0,
        swarm = { role = "worker" } },
}
local before = Estimator.shared(state, members, 5000)
assert(before.mainDone == 4 and before.totalBranches == 8)
assert(before.completedBranches == 0 and before.activeWorkers == 1)
assert(before.elapsedMs == 4000 and before.remainingMs > 0)
assert(before.projectedTotalMs == before.elapsedMs + before.remainingMs)

state.leaderParked = true
state.workers["10"] = { slot = 1, status = "registered_no_motion" }
state.branches["eta-job:3:left"] = { status = "complete" }
state.branches["eta-job:3:right"] = { status = "complete" }
local after = Estimator.shared(state, members, 6000)
assert(after.mainDone == 12 and after.completedBranches == 2)
assert(after.activeWorkers == 2)
assert(after.remainingMs < before.remainingMs)

state.branches["eta-job:6:left"] = { status = "claimed", owner = "31" }
members[31].swarm.assignedBranch = "eta-job:6:left"
members[31].progressCurrent = 3
local progress = Estimator.shared(state, members, 7000)
assert(progress.remainingMs < after.remainingMs)
return true
