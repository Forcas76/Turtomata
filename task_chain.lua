-- V2 KISERLETI feladatlanc: minden lepes ugyanarra a bazisra ter vissza.
local Store = require("state_store")
local Request = require("job_request")
local UI = require("ui")
local request, requestError = Request.consume("chain", { ... })
if requestError then error(requestError, 0) end
if not request then error("A lanc csak a kozponti menubol indithato.", 0) end

local FILE = "task_chain_state.txt"
local ACTIVE_FILE = ".remote_active_job"
local types = {
    excavator = { program = "excavator", file = "excavator_state.txt" },
    farm = { program = "farm_task", file = "farm_state.txt" },
    branch_miner = { program = "branch_miner", file = "branch_miner_state.txt" },
    nether_builder = { program = "nether_builder", file = "nether_builder_state.txt" },
}
local state
if request.action == "resume" then
    state = Store.read(FILE)
    if type(state) ~= "table" or state.version ~= 1
        or state.active ~= true then error("Nincs ervenyes lancmentes.", 0) end
else
    state = {
        version = 1, active = true, phase = "ready",
        config = request.config, index = 1, childStarted = false,
    }
end
local function save()
    local ok, reason = Store.write(FILE, state)
    if not ok then error(reason, 0) end
end
local function samePosition(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end
local function validateStep(step, base)
    if type(step) ~= "table" or not types[step.task]
        or type(step.config) ~= "table" then
        return false, "Nem tamogatott lanclepes."
    end
    if step.task == "excavator" then
        local remote = step.config.remoteStart
        if not remote or not remote.enabled or not samePosition(remote.base, base)
            or remote.base.heading ~= base.heading then
            return false, "A teruletaso lanclepes bazisa nem egyezik."
        end
    elseif step.task == "farm" then
        if not samePosition(step.config.base, base)
            or step.config.base.heading ~= base.heading then
            return false, "A farm lanclepes bazisa nem egyezik."
        end
    elseif step.work and (not samePosition(step.work, base)
        or step.work.heading ~= base.heading) then
        return false, "Branch/utvonal csak a bazis pontjaban tamogatott."
    end
    return true
end
local function atBase(step, saved, base)
    if step.task == "excavator" then
        local position = saved.position or {}
        return position.x == 0 and position.y == 0 and position.z == 0
            and saved.remote and saved.remote.phase == "at_base"
    end
    if step.task == "branch_miner" or step.task == "nether_builder" then
        local position = saved.position or {}
        return position.x == 0 and position.y == 0 and position.z == 0
    end
    return saved.navigation and samePosition(
        saved.navigation.pose, base)
end
local function runStep(step)
    local definition = types[step.task]
    local saved = Store.read(definition.file)
    if state.childStarted and type(saved) == "table" and saved.active == false then
        if state.childCompleted then return true, saved end
        return false, "A reszfeladat befejezese es a lancmentes kozott ujraindult; ellenorzes kell."
    end
    local action = state.childStarted and "resume" or "new"
    if action == "resume" and
        (type(saved) ~= "table" or saved.active ~= true) then
        return false, "Az aktiv reszfeladat mentese hianyzik."
    end
    local config = Store.clone(step.config)
    config.resumeOnStartup = false
    if step.task == "farm" then config.oneShot = true end
    local token, reason = Request.create(step.task, action, config)
    if not token then return false, reason end
    state.childStarted = true
    state.phase = "running"
    save()
    Store.write(ACTIVE_FILE, {
        task = step.task, program = definition.program,
        action = action, config = config,
    })
    local launched = shell.run(definition.program, "--request", token)
    Store.write(ACTIVE_FILE, {
        task = "chain", program = "task_chain",
        action = "resume", config = state.config,
    })
    saved = Store.read(definition.file)
    if not launched or type(saved) ~= "table" then
        return false, "A reszfeladat hibaval tert vissza."
    end
    if saved.active then
        if saved.phase == "megallitva_otthon"
            or saved.activity == "megallitva_otthon" then
            state.phase = "megallitva_otthon"
            save()
            return false, "A lancot a felhasznalo szuneteltette."
        end
        return false, "A reszfeladat nem fejezodott be."
    end
    state.childCompleted = true
    save()
    return true, saved
end

save()
local ok, reason = pcall(function()
    local config = state.config
    if type(config) ~= "table" or type(config.base) ~= "table"
        or type(config.steps) ~= "table" or #config.steps == 0 then
        error("Ures vagy hianyos feladatlanc.", 0)
    end
    for index = state.index, #config.steps do
        local step = config.steps[index]
        if step.enabled ~= false then
            local valid, why = validateStep(step, config.base)
            if not valid then error(why, 0) end
            state.index = index
            state.phase = "to_work"
            save()
            local finished, savedOrReason = runStep(step)
            if not finished then error(savedOrReason, 0) end
            if not atBase(step, savedOrReason, config.base) then
                error("A reszfeladat nem az eredeti bazison ert veget.", 0)
            end
        end
        state.phase = "next"
        state.childStarted = false
        state.childCompleted = false
        state.index = index + 1
        save()
        UI.message("LANC HALADAS", {
            string.format("%d/%d lepes feldolgozva.", index, #config.steps),
            step.enabled == false and "Kikapcsolt lepes atugorva."
                or "A turtle visszatert az eredeti bazisra.",
        })
    end
    state.active = false
    state.phase = "completed"
    save()
end)
if not ok then
    if state.phase ~= "megallitva_otthon" then
        state.phase = "needs_attention"
    end
    state.lastError = tostring(reason)
    save()
    printError(tostring(reason))
end
