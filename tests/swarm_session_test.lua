local oldStore = package.loaded.state_store
local oldSession = package.loaded.swarm_session
local oldId, oldEpoch = os.getComputerID, os.epoch
local files = {}
package.loaded.state_store = {
    read = function(path, fallback) return files[path] or fallback end,
    write = function(path, value) files[path] = value return true end,
}
package.loaded.swarm_session = nil
os.getComputerID = function() return 10 end
os.epoch = function() return 12345 end
local Session = require("swarm_session")
local ok, reason, leader = Session.openLeader({
    mainLength = 20, branchLength = 4, branchSpacing = 3,
    tunnelMode = 1,
})
assert(ok, reason)
assert(leader.jobId == "10-12345" and leader.role == "leader")
assert(Session.claimCoordinator(leader.jobId, 25))
assert(Session.load().coordinatorId == 25 and Session.load().epoch == 1)
assert(not Session.claimCoordinator(leader.jobId, 26))
assert(Session.claimCoordinator(leader.jobId, 25))
assert(Session.load().epoch == 1)

files["swarm_session.txt"] = nil
assert(Session.observeOffer({ jobId = leader.jobId, leaderId = 10,
    coordinatorId = 25, epoch = 1, mainLength = 20,
    branchLength = 4, branchSpacing = 3, tunnelMode = 1 }))
local offer = Session.offers()[1]
assert(offer.jobId == leader.jobId)
assert(Session.join(offer, 1) == false)
local joined, joinReason, worker = Session.join(offer, 3)
assert(joined, joinReason)
assert(worker.pose.x == 2 and worker.pose.z == 0)
assert(worker.status == "join_pending" and worker.coordinatorId == 25)
assert(Session.forgetOffer(leader.jobId))
assert(#Session.offers() == 0)

package.loaded.state_store = oldStore
package.loaded.swarm_session = oldSession
os.getComputerID, os.epoch = oldId, oldEpoch
return true
