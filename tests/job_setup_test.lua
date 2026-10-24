local oldUi = package.loaded["ui"]
local queue, confirmations = {}, {}
local mock = {}
mock.choice = function()
    return table.remove(queue, 1)
end
mock.menu = function()
    return table.remove(queue, 1)
end
mock.integer = function()
    return table.remove(queue, 1)
end
mock.confirm = function()
    return table.remove(confirmations, 1)
end
local setupErrors = 0
mock.message = function() setupErrors = setupErrors + 1 end
mock.waitForEnter = function() end
package.loaded["ui"] = mock
package.loaded["job_setup"] = nil
local Setup = require("job_setup")
local settings = {
    general = { fuelReserve = 8, autoResumeDefault = false },
    inventory = { experimental = false },
    torches = { enabledByDefault = false, interval = 8, placement = "above" },
    ores = { enabledByDefault = false, maxDepth = 4, maxBlocks = 16 },
    safety = {},
    navigation = { defaultActionSeconds = 0.8,
        coordinateMode = "open", coordinateAxisOrder = { "y", "x", "z" } },
}

queue = { 1, 1, 2, 20, "start", "back", nil }
confirmations = { false }
assert(Setup.branch(settings) == nil, "Visszalepes nem indithat feladatot.")

queue = { 1, 1, 2, 20, "start" }
confirmations = { true }
local config, lines = Setup.branch(settings)
assert(config and config.mainLength == 20 and #lines > 0)

queue = { 1, 2, 1, "start" }
confirmations = { true }
local shared = Setup.branch(settings)
assert(shared and shared.sharedMode == true and shared.tunnelMode == 1)

settings.torches.enabledByDefault, settings.torches.interval = true, 1
settings.ores.enabledByDefault = true
queue = { 1, 2, 1, 2, 65, "start", "back", nil }
assert(Setup.branch(settings) == nil)
assert(setupErrors == 1, "A tul hosszu kozos erc-faklyazas nem indulhat.")
settings.torches.enabledByDefault, settings.torches.interval = false, 8
settings.ores.enabledByDefault = false

queue = { 1, 2, 2 }
assert(Setup.branch(settings) == "shared_join")

queue = { 1, "start" }
confirmations = { true }
local farm, farmLines = Setup.farm(settings)
assert(farm and farm.mode == "crop" and farm.width == 8
    and farm.intervalSeconds == 300 and #farmLines > 0)

queue = { 2, "start" }
confirmations = { true }
farm = Setup.farm(settings)
assert(farm and farm.mode == "animal" and #farm.pens == 1)

package.loaded["ui"] = oldUi
package.loaded["job_setup"] = nil
return true
