local previousFs, previousTextutils = fs, textutils
local files, objects, nextId = {}, {}, 0
fs = {
    exists = function(path) return files[path] ~= nil end,
    getName = function(path) return path:match("[^/]+$") end,
    getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
    combine = function(a, b) return a .. "/" .. b end,
    delete = function(path) files[path] = nil end,
    move = function(a, b) files[b], files[a] = files[a], nil end,
    open = function(path, mode)
        if mode == "r" then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        return { write = function(value) files[path] = value end,
            close = function() end }
    end,
}
textutils = {
    serializeJSON = function(value)
        nextId = nextId + 1
        objects[tostring(nextId)] = value
        return tostring(nextId)
    end,
    unserializeJSON = function(value) return objects[value] end,
}
package.loaded["state_store"] = nil
package.loaded["work_registry"] = nil
local Store = require("state_store")
local Registry = require("work_registry")

assert(Registry.start("branch_miner", true))
assert(Store.write("branch_miner_state.txt", {
    version = 1, active = true, config = { mainLength = 8 },
}))
assert(Registry.autoCandidate().attempts == 1)
assert(Registry.load().attempts == 1)
assert(Registry.update("paused"))
assert(Registry.autoCandidate() == nil)
assert(Registry.resume("branch_miner"))
assert(Store.write("branch_miner_state.txt", {
    version = 1, active = true, config = {}, pending = { move = {} },
}))
assert(Registry.autoCandidate() == nil)
assert(Registry.load().status == "needs_attention")

local good = Store.read("branch_miner_state.txt")
files["branch_miner_state.txt"] = "corrupt"
assert(Store.read("branch_miner_state.txt").active == true)
assert(Store.write("branch_miner_state.txt", { version = 1, active = false }))
assert(Store.read(".branch_miner_state.txt.bak").active == true)

assert(Registry.release())
assert(Registry.start("chain", true))
assert(Store.write("task_chain_state.txt", {
    version = 1, active = true, phase = "running",
    config = { base = { x = 1, y = 64, z = 2 },
        steps = { { task = "farm" } } },
}))
assert(Registry.autoCandidate().task == "chain")
local allowed = Registry.resume("farm")
assert(allowed == false)
assert(Store.write("task_chain_state.txt", {
    version = 1, active = true, phase = "running",
    childStarted = true, index = 1,
    config = { steps = { { task = "farm" } } },
}))
assert(Store.write("farm_state.txt", {
    version = 1, active = true, config = {},
    navigation = { pending = { operation = "push" } },
}))
assert(Registry.autoCandidate() == nil)
assert(Registry.load().status == "needs_attention")
assert(Registry.setAutoResume(false))
assert(Registry.autoCandidate() == nil)
assert(Registry.release())
assert(Registry.load().status == "released")

fs, textutils = previousFs, previousTextutils
package.loaded["state_store"] = nil
package.loaded["work_registry"] = nil
return true
