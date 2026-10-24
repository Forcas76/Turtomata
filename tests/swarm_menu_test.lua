local oldUi = package.loaded.ui
local oldSession = package.loaded.swarm_session
local oldRegistry = package.loaded.work_registry
local oldStore = package.loaded.state_store
local oldMenu = package.loaded.swarm_menu
local oldEpoch = os.epoch
local oldTimer, oldPull = os.startTimer, os.pullEvent
local oldPeripheral, oldRednet = peripheral, rednet

local state
local itemsSeen
package.loaded.ui = {
    menu = function(_, items)
        itemsSeen = items
        return "back"
    end,
}
package.loaded.swarm_session = {
    load = function() return state end,
    offers = function() return {} end,
}
package.loaded.work_registry = { load = function() return nil end }
package.loaded.state_store = { read = function() return nil end }
package.loaded.swarm_menu = nil
os.epoch = function() return 10000 end

local menu = require("swarm_menu")
local function enabled(value)
    for _, item in ipairs(itemsSeen) do
        if item.value == value then return item.enabled end
    end
    return nil
end

menu.run()
assert(enabled("worker") == nil)
assert(enabled("join") == true)
assert(enabled("trunk") == false)
assert(enabled("station") == false)

-- Keson befuto hirdetest a csatlakozasi lap varakozas kozben felveszi.
state = nil
local offerReads, joined = 0, false
local offer = { leaderId = 10, jobId = "10-100", coordinatorId = 25,
    workConfig = {} }
package.loaded.swarm_session.offers = function()
    offerReads = offerReads + 1
    return offerReads >= 2 and { offer } or {}
end
package.loaded.swarm_session.join = function(value, slot)
    joined = value == offer and slot == 2
    return joined
end
package.loaded.ui.menu = function(_, items) return items[1].value end
package.loaded.ui.integer = function() return 2 end
package.loaded.ui.confirm = function() return true end
package.loaded.ui.message = function() end
package.loaded.ui.waitForEnter = function() end
peripheral = {
    getNames = function() return { "left" } end,
    call = function() return true end,
}
rednet = { isOpen = function() return true end }
os.startTimer = function() return 1 end
os.pullEvent = function() return "timer", 1 end
menu.joinWorker()
assert(joined and offerReads >= 2)
package.loaded.ui.menu = function(_, items)
    itemsSeen = items
    return "back"
end

state = {
    active = true, role = "worker", status = "registered_no_motion",
    coordinatorId = 42, lastHeartbeatAt = 9000,
}
menu.run()
assert(enabled("worker") == nil)
assert(enabled("station") == true)

state.assignedBranch = 5
state.status = "assigned_no_motion"
menu.run()
assert(enabled("worker") == nil)
assert(enabled("station") == false)

package.loaded.ui = oldUi
package.loaded.swarm_session = oldSession
package.loaded.work_registry = oldRegistry
package.loaded.state_store = oldStore
package.loaded.swarm_menu = oldMenu
os.epoch = oldEpoch
os.startTimer, os.pullEvent = oldTimer, oldPull
peripheral, rednet = oldPeripheral, oldRednet
return true
