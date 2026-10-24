-- A hirdetes akkor is menjen ki, ha a status-telemetria hibazik.
local oldState = package.loaded.state_store
local oldSession = package.loaded.swarm_session
local oldRemote = package.loaded.remote
local oldPeripheral, oldRednet, oldTurtle = peripheral, rednet, turtle
local oldId, oldEpoch = os.getComputerID, os.epoch
local oldTimer, oldPull = os.startTimer, os.pullEventRaw

local observed = 0
package.loaded.state_store = { read = function() return nil end }
package.loaded.swarm_session = {
    load = function()
        return {
            version = 2, active = true, role = "leader",
            status = "coordinated", jobId = "10-1", leaderId = 10,
            coordinatorId = 25, epoch = 1, mainLength = 8,
            branchLength = 2, branchSpacing = 3, tunnelMode = 1,
            workConfig = { sharedMode = true, oreScanEnabled = true },
        }
    end,
    observeOffer = function(message)
        assert(message.workConfig.oreScanEnabled == true)
        observed = observed + 1
        return true
    end,
}
package.loaded.remote = nil
peripheral = {
    getNames = function() return { "left" } end,
    call = function(_, method)
        if method == "isWireless" then return true end
    end,
    isPresent = function() return true end,
}
local sent = {}
rednet = {
    isOpen = function() return true end,
    broadcast = function(message, channel)
        sent[#sent + 1] = { message = message, channel = channel }
    end,
    send = function() return true end,
}
turtle = {
    getFuelLevel = function() return 100 end,
    getItemCount = function() error("telemetria teszthiba") end,
}
os.getComputerID = function() return 10 end
os.epoch = function() return 100000 end
os.startTimer = function() return 1 end
local tick = 0
os.pullEventRaw = function()
    tick = tick + 1
    if tick == 1 then return "timer", 1 end
    error("teszt vege")
end
local Remote = require("remote")
assert(not pcall(Remote.run))
local offer
for _, entry in ipairs(sent) do
    if entry.message.type == "job_offer" then offer = entry.message end
end
assert(offer and offer.coordinatorId == 25)
assert(Remote.lastError:find("Allapotkuldes", 1, true))
os.getComputerID = function() return 11 end
Remote.handleSwarm(10, offer)
assert(observed == 1)

package.loaded.state_store = oldState
package.loaded.swarm_session = oldSession
package.loaded.remote = oldRemote
peripheral, rednet, turtle = oldPeripheral, oldRednet, oldTurtle
os.getComputerID, os.epoch = oldId, oldEpoch
os.startTimer, os.pullEventRaw = oldTimer, oldPull
return true
