local oldUi = package.loaded.ui
local oldSession = package.loaded.swarm_session
local oldRegistry = package.loaded.work_registry
local oldStore = package.loaded.state_store
local oldMenu = package.loaded.swarm_menu
local oldEpoch = os.epoch

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
    error("Missing menu item: " .. value)
end

menu.run()
assert(enabled("worker") == false)
assert(enabled("trunk") == false)
assert(enabled("station") == false)

state = {
    active = true, role = "worker", status = "registered_no_motion",
    coordinatorId = 42, lastHeartbeatAt = 9000,
}
menu.run()
assert(enabled("worker") == false)
assert(enabled("station") == true)

state.assignedBranch = 5
state.status = "assigned_no_motion"
menu.run()
assert(enabled("worker") == true)
assert(enabled("station") == false)

package.loaded.ui = oldUi
package.loaded.swarm_session = oldSession
package.loaded.work_registry = oldRegistry
package.loaded.state_store = oldStore
package.loaded.swarm_menu = oldMenu
os.epoch = oldEpoch
return true
