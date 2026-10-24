package.loaded["remote_protocol"] = nil
package.loaded["remote"] = nil

local oldId, oldLabel, oldEpoch = os.getComputerID, os.getComputerLabel, os.epoch
os.getComputerID = function() return 42 end
os.getComputerLabel = function() return "Banyasz" end
os.epoch = function() return 123456 end

local swarmSaved
local scanActive = false
package.loaded["state_store"] = {
    read = function(path)
        if path == "swarm_session.txt" then return swarmSaved end
        if path == ".remote_active_job" then
            return { task = "branch_miner" }
        end
        if path == "branch_miner_state.txt" then
            return {
                active = true, activity = "bal_ag_erckereses", mainCompleted = 5,
                collected = { ["minecraft:coal"] = 17 },
                oreScan = scanActive and { active = true,
                    returnScan = true } or nil,
                position = { x = 1, y = 0, z = 5 }, heading = 1,
                telemetry = { activeMs = 8000 },
                config = {
                    tunnelMode = 1, mainLength = 10, startOffset = 0,
                    branchLength = 2, branchSpacing = 3,
                    torchEnabled = false, oreScanEnabled = true,
                    defaultActionSeconds = 0.8,
                },
            }
        end
    end,
    write = function(path, value)
        if path == "swarm_session.txt" then swarmSaved = value end
        return true
    end,
}

turtle = {
    getFuelLevel = function() return 900 end,
    getItemCount = function(slot) return slot <= 3 and slot or 0 end,
}
peripheral = { getNames = function() return {} end }
local sentMessages, queued = {}, {}
rednet = {
    send = function(recipient, message, protocol)
        sentMessages[#sentMessages + 1] = {
            recipient = recipient, message = message, protocol = protocol,
        }
        return true
    end,
}
local oldQueueEvent = os.queueEvent
os.queueEvent = function(...)
    queued[#queued + 1] = { ... }
end

local Protocol = require("remote_protocol")
assert(Protocol.STATUS == "turtomata.status.v1")
assert(Protocol.CONTROL == "turtomata.control.v1")
assert(Protocol.ACK == "turtomata.ack.v1")
local Remote = require("remote")
local snapshot = Remote.snapshot()
assert(Protocol.valid(snapshot, "status"))
assert(snapshot.turtleId == 42 and snapshot.label == "Banyasz")
assert(snapshot.task == "Branch mining")
assert(snapshot.activity == "bal_ag_erckereses")
assert(snapshot.progressCurrent == 5 and snapshot.progressTotal == 10)
assert(snapshot.position.x == 1 and snapshot.position.z == 5)
assert(snapshot.fuel == 900 and snapshot.inventoryUsed == 3)
assert(snapshot.collected["minecraft:coal"] == 17)
assert(snapshot.remainingActions and snapshot.remainingMs)

Remote.handleCommand(7, {
    type = "command", version = Protocol.VERSION, targetId = 42,
    command = "return_home", requestId = "test-1",
})
assert(#sentMessages == 1 and sentMessages[1].protocol == Protocol.ACK)
assert(sentMessages[1].message.accepted == true)
assert(queued[1][1] == "turtomata_remote_command" and queued[1][2] == "return_home")

Remote.handleCommand(7, {
    type = "command", version = Protocol.VERSION, targetId = 42,
    command = "service", requestId = "test-2",
})
assert(#sentMessages == 2 and sentMessages[2].message.accepted == true)
assert(queued[2][1] == "turtomata_remote_command" and queued[2][2] == "service")

local Session = require("swarm_session")
local SwarmProtocol = require("swarm_protocol")
local opened, _, leader = Session.openLeader({
    mainLength = 12, branchLength = 4, branchSpacing = 3, tunnelMode = 1,
})
assert(opened and Remote.snapshot().swarm.jobId == leader.jobId)
Remote.handleSwarm(25, SwarmProtocol.message("coordinator_claim", {
    jobId = leader.jobId, leaderId = 42, requestId = "claim-1",
}))
assert(sentMessages[3].protocol == SwarmProtocol.CHANNEL)
assert(sentMessages[3].message.accepted == true)
assert(Session.load().coordinatorId == 25)
Remote.handleSwarm(26, SwarmProtocol.message("coordinator_claim", {
    jobId = leader.jobId, leaderId = 42, requestId = "claim-2",
}))
assert(sentMessages[4].message.accepted == false)
Remote.handleSwarm(26, SwarmProtocol.message("coordinator_heartbeat", {
    jobId = leader.jobId, leaderId = 42, coordinatorId = 26, epoch = 1,
}))
assert(Session.load().lastHeartbeatAt == nil)
Remote.handleSwarm(25, SwarmProtocol.message("coordinator_heartbeat", {
    jobId = leader.jobId, leaderId = 42, coordinatorId = 25, epoch = 1,
}))
assert(Session.load().lastHeartbeatAt == 123456)
assert(Remote.snapshot().swarm.coordinatorOnline == true)
Remote.handleSwarm(25, SwarmProtocol.message("branch_ready_ack", {
    jobId = leader.jobId, coordinatorId = 25, epoch = 1,
    branchKey = leader.jobId .. ":3:left", accepted = true,
}))
assert(Session.load().publishSide == "right")
Remote.handleSwarm(25, SwarmProtocol.message("branch_ready_ack", {
    jobId = leader.jobId, coordinatorId = 25, epoch = 1,
    branchKey = leader.jobId .. ":3:left", accepted = true,
}))
assert(Session.load().publishSide == "right")
Remote.handleSwarm(25, SwarmProtocol.message("swarm_stop", {
    jobId = leader.jobId, coordinatorId = 25, epoch = 1,
}))
assert(Session.load().status == "emergency_stop")
assert(Session.load().stoppedByCoordinator == true)
Remote.handleSwarm(25, SwarmProtocol.message("coordinator_heartbeat", {
    jobId = leader.jobId, leaderId = 42, coordinatorId = 25, epoch = 1,
    recoveryReview = true,
}))
assert(Session.load().status == "needs_reconcile")

swarmSaved = {
    version = 2, active = true, role = "worker", jobId = "10-12345",
    leaderId = 10, coordinatorId = 25, epoch = 1, slot = 2,
    status = "registered_no_motion", mainLength = 12,
    branchLength = 4, branchSpacing = 3, tunnelMode = 1,
}
swarmSaved.status = "emergency_stop"
swarmSaved.stoppedByCoordinator = true
Remote.handleSwarm(25, SwarmProtocol.message("coordinator_heartbeat", {
    jobId = swarmSaved.jobId, leaderId = 10,
    coordinatorId = 25, epoch = 1, recoveryReview = true,
}))
assert(swarmSaved.status == "needs_reconcile")
swarmSaved.status = "registered_no_motion"
Remote.handleSwarm(25, SwarmProtocol.message("task_offer", {
    jobId = "10-12345", coordinatorId = 25, epoch = 1,
    workerId = 42, branchKey = "10-12345:3:left", z = 3, side = "left",
}))
assert(Session.load().assignedBranch == "10-12345:3:left")
assert(Session.load().status == "assigned_no_motion")
assert(sentMessages[5].message.type == "task_ack")
assert(sentMessages[5].message.accepted == true)
swarmSaved.stationRegistration = {
    slot = 2, chestName = "minecraft:chest", requestId = "station-42",
}
Remote.handleSwarm(25, SwarmProtocol.message("station_register_ack", {
    jobId = swarmSaved.jobId, coordinatorId = 25, epoch = 1,
    workerId = 42, slot = 2, requestId = "station-42",
    stationId = "D02", accepted = true,
}))
assert(swarmSaved.stationRegistered == "D02"
    and swarmSaved.stationChestName == "minecraft:chest"
    and swarmSaved.stationRegistration == nil)
swarmSaved.status = "leave_pending"
swarmSaved.leaveRequestId = "leave-42"
Remote.handleSwarm(25, SwarmProtocol.message("leave_ack", {
    jobId = swarmSaved.jobId, coordinatorId = 25, epoch = 1,
    workerId = 42, requestId = "leave-42", accepted = false,
    reason = "A seged nincs a sorhelyen.",
}))
assert(Session.load().active and Session.load().status == "needs_attention")
assert(Session.load().lastError == "A seged nincs a sorhelyen.")
swarmSaved.status = "leave_pending"
Remote.handleSwarm(25, SwarmProtocol.message("leave_ack", {
    jobId = swarmSaved.jobId, coordinatorId = 25, epoch = 1,
    workerId = 42, requestId = "leave-42", accepted = true,
}))
assert(Session.load().active == false and Session.load().status == "left")

Remote.handleCommand(7, {
    type = "command", version = Protocol.VERSION, targetId = 42,
    command = "skip_ore_scan", requestId = "skip-off",
})
assert(sentMessages[#sentMessages].message.accepted == false)
scanActive = true
Remote.handleCommand(7, {
    type = "command", version = Protocol.VERSION, targetId = 42,
    command = "skip_ore_scan", requestId = "skip-on",
})
assert(sentMessages[#sentMessages].message.accepted == true)
assert(queued[#queued][1] == "turtomata_remote_command"
    and queued[#queued][2] == "skip_ore_scan")

os.getComputerID, os.getComputerLabel, os.epoch = oldId, oldLabel, oldEpoch
os.queueEvent = oldQueueEvent
return true
