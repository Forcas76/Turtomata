-- Egy turtle tartos munkatulajdonosa es auto-folytatasi szandeka.
local store = require("state_store")
local registry = {}
local FILE = "work_registry.txt"

local jobs = {
    branch_miner = "branch_miner_state.txt",
    excavator = "excavator_state.txt",
    nether_builder = "nether_builder_state.txt",
    coordinate = "coordinate_state.txt",
    farm = "farm_state.txt",
    chain = "task_chain_state.txt",
}

local function valid(value)
    return type(value) == "table" and value.version == 1
        and type(value.task) == "string" and type(value.stateFile) == "string"
        and jobs[value.task] == value.stateFile
end

function registry.load()
    local value, reason = store.read(FILE)
    if not valid(value) then return nil, reason or "invalid_registry" end
    return value
end

function registry.start(task, autoResume)
    if not jobs[task] then return false, "Ismeretlen feladat." end
    local old = registry.load()
    if old and old.status ~= "completed" and old.status ~= "released" then
        local state = store.read(old.stateFile)
        if type(state) == "table" and state.active then
            return false, "Mar van aktiv munka: " .. old.task
        end
    end
    return store.write(FILE, {
        version = 1, task = task, stateFile = jobs[task],
        autoResume = autoResume == true, status = "running",
        generation = (old and old.generation or 0) + 1,
        attempts = 0,
    })
end

function registry.update(status, reason)
    local value = registry.load()
    if not value then return false, "Nincs aktiv munkanyilvantartas." end
    value.status = status
    value.lastError = reason
    return store.write(FILE, value)
end

function registry.resume(task)
    local value = registry.load()
    if value and value.task ~= task then
        local old = store.read(value.stateFile)
        if type(old) == "table" and old.active then
            return false, "Masik aktiv munka tulajdonolja a turtle-t: "
                .. value.task
        end
        return true
    end
    if not value then return true end
    value.status = "running"
    value.lastError = nil
    value.attempts = 0
    return store.write(FILE, value)
end

function registry.autoCandidate()
    local value = registry.load()
    if not value or not value.autoResume or value.status ~= "running" then return nil end
    local state = store.read(value.stateFile)
    if type(state) ~= "table" or state.active ~= true
        or type(state.config) ~= "table" then
        registry.update("needs_attention", "A munkamentes hianyzik vagy ervenytelen.")
        return nil
    end
    if state.phase == "needs_attention" or state.phase == "needs_supplies"
        or state.phase == "megallitva_otthon" then
        registry.update("needs_attention", "A munkamentes kezi ellenorzest igenyel.")
        return nil
    end
    local navigation = state.navigation or state
    if navigation.pending or state.pending
        or state.remote and state.remote.navigation
            and state.remote.navigation.pending then
        registry.update("needs_attention", "Fuggo fizikai lepes: kezileg ellenorizd a helyet.")
        return nil
    end
    if value.task == "chain" and state.childStarted then
        local step = state.config.steps and state.config.steps[state.index or 1]
        local childFile = step and jobs[step.task]
        local child = childFile and store.read(childFile)
        if type(child) ~= "table" or child.pending
            or child.navigation and child.navigation.pending
            or child.remote and child.remote.navigation
                and child.remote.navigation.pending then
            registry.update("needs_attention",
                "A lanc reszfeladatanak helyzete ellenorizendo.")
            return nil
        end
    end
    if value.attempts >= 3 then
        registry.update("needs_attention", "Harom sikertelen automatikus folytatas.")
        return nil
    end
    value.attempts = value.attempts + 1
    local ok = store.write(FILE, value)
    return ok and value or nil
end

function registry.stateFile(task) return jobs[task] end

function registry.setAutoResume(enabled)
    local value = registry.load()
    if not value then return false, "Nincs nyilvantartott munka." end
    value.autoResume = enabled == true
    return store.write(FILE, value)
end

function registry.release()
    local value = registry.load()
    if not value then return false, "Nincs nyilvantartott munka." end
    value.status = "released"
    value.autoResume = false
    return store.write(FILE, value)
end

return registry
