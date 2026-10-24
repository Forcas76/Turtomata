local oldStore = package.loaded.state_store
local oldReset = package.loaded.developer_reset
local removed = {}
package.loaded.state_store = {
    removeAll = function(path)
        removed[path] = true
        return true
    end,
}
package.loaded.developer_reset = nil
local Reset = require("developer_reset")
assert(Reset.run())
for _, path in ipairs({ "settings.txt", "ore_targets.txt",
    "branch_miner_state.txt", "swarm_session.txt",
    "swarm_coordinator.txt", "work_registry.txt",
    ".downloader_auth_mode", ".github_token" }) do
    assert(removed[path])
end
assert(not removed["main.lua"] and not removed["startup.lua"])
package.loaded.state_store = oldStore
package.loaded.developer_reset = oldReset
return true
