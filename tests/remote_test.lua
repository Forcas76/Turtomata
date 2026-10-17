package.loaded["remote_protocol"] = nil
package.loaded["remote"] = nil

local oldId, oldLabel, oldEpoch = os.getComputerID, os.getComputerLabel, os.epoch
os.getComputerID = function() return 42 end
os.getComputerLabel = function() return "Banyasz" end
os.epoch = function() return 123456 end

package.loaded["state_store"] = {
    read = function(path)
        if path == "branch_miner_state.txt" then
            return {
                active = true, activity = "bal_ag_erckereses", mainCompleted = 5,
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
}

turtle = {
    getFuelLevel = function() return 900 end,
    getItemCount = function(slot) return slot <= 3 and slot or 0 end,
}
peripheral = { getNames = function() return {} end }
rednet = {}

local Protocol = require("remote_protocol")
local Remote = require("remote")
local snapshot = Remote.snapshot()
assert(Protocol.valid(snapshot, "status"))
assert(snapshot.turtleId == 42 and snapshot.label == "Banyasz")
assert(snapshot.task == "Branch mining")
assert(snapshot.activity == "bal_ag_erckereses")
assert(snapshot.progressCurrent == 5 and snapshot.progressTotal == 10)
assert(snapshot.position.x == 1 and snapshot.position.z == 5)
assert(snapshot.fuel == 900 and snapshot.inventoryUsed == 3)
assert(snapshot.remainingActions and snapshot.remainingMs)

os.getComputerID, os.getComputerLabel, os.epoch = oldId, oldLabel, oldEpoch
return true
