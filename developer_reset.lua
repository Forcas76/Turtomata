-- Csak a helyi adatfajlokat torli. Programot vagy startupot nem modosit.
local Store = require("state_store")
local reset = {}

local files = {
    "settings.txt", "ore_targets.txt", "inventory_state.txt",
    "branch_miner_state.txt", "excavator_state.txt",
    "nether_builder_state.txt", "coordinate_state.txt",
    "farm_state.txt", "task_chain_state.txt",
    "task_chain_definition.txt", "work_registry.txt",
    "base_dock_state.txt", "swarm_session.txt", "swarm_offers.txt",
    "swarm_coordinator.txt", ".turtomata_job_request.txt",
    ".remote_active_job", ".turtomata_12_ready",
    ".turtomata_update.txt", ".downloader_auth_mode",
    ".github_token", "action_log.txt",
}

function reset.files()
    local copy = {}
    for index, path in ipairs(files) do copy[index] = path end
    return copy
end

function reset.run()
    for _, path in ipairs(files) do
        local ok, reason = Store.removeAll(path)
        if not ok then return false, path .. ": " .. tostring(reason) end
    end
    return true
end

return reset
