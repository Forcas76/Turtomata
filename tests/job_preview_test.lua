local oldStore = package.loaded.state_store
local oldPreview = package.loaded.job_preview
local saved = {
    version = 2, active = true,
    config = { tunnelMode = 1, mainLength = 20, branchLength = 4,
        branchSpacing = 3 },
    position = { x = 0, y = 0, z = 7 }, heading = 0,
    mainCompleted = 7, activity = "hazateres",
}
package.loaded.state_store = {
    read = function(path)
        if path == "branch_miner_state.txt" then return saved end
    end,
    clone = function(value)
        local result = {}
        for key, item in pairs(value) do result[key] = item end
        return result
    end,
}
package.loaded.job_preview = nil
local Preview = require("job_preview")
local jobs = Preview.list()
assert(#jobs == 1 and jobs[1].task == "branch_miner")
assert(jobs[1].progress == "7/20")
assert(#Preview.describe(jobs[1], saved) > 0)
saved.version = 1
assert(#Preview.list() == 0) -- a branch_miner ezt sem tudja folytatni
package.loaded.state_store = oldStore
package.loaded.job_preview = oldPreview
return true
