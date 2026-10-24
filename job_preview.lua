-- Olvasasra szant, feladatspecifikus mentett munka-attekintes.
local preview = {}
local Store = require("state_store")

local jobs = {
    { task = "branch_miner", program = "branch_miner",
        file = "branch_miner_state.txt", label = "Branch mining", version = 2 },
    { task = "excavator", program = "excavator",
        file = "excavator_state.txt", label = "Terulet asas" },
    { task = "nether_builder", program = "nether_builder",
        file = "nether_builder_state.txt", label = "Utvonal keszites" },
    { task = "coordinate", program = "coordinate_task",
        file = "coordinate_state.txt", label = "Koordinatas navigacio" },
    { task = "farm", program = "farm_task",
        file = "farm_state.txt", label = "Farm karbantartas" },
    { task = "chain", program = "task_chain",
        file = "task_chain_state.txt", label = "Feladatlanc" },
}

local function pose(value, world)
    if type(value) ~= "table" then return "ismeretlen" end
    if type(value.x) ~= "number" or type(value.y) ~= "number"
        or type(value.z) ~= "number" then return "ismeretlen" end
    return string.format("%s %d,%d,%d irany=%s",
        world and "vilag" or "relativ", value.x, value.y, value.z,
        tostring(value.heading or "?"))
end

local function add(lines, label, value)
    lines[#lines + 1] = label .. ": " .. tostring(value == nil and "ismeretlen" or value)
end

local function bool(value) return value and "BE" or "KI" end

function preview.describe(job, saved)
    local config = saved.config or {}
    local lines = { job.label }
    if job.task == "branch_miner" then
        local mode = ({ "1x2", "1x3", "3x3" })[config.tunnelMode] or "?"
        add(lines, "Mod", mode)
        add(lines, "Fout", tostring(saved.mainCompleted or "?") .. "/" .. tostring(config.mainLength or "?"))
        if config.tunnelMode ~= 3 then
            add(lines, "Oldalag", config.branchLength)
            add(lines, "Agkoz", config.branchSpacing)
            add(lines, "Utolso kesz ag", saved.branchesCompletedAt)
        if type(saved.branchProgress) == "table" then
            add(lines, "Aktualis agpont", saved.branchProgress.at)
            add(lines, "Bal/jobb kesz", bool(saved.branchProgress.leftDone)
                .. "/" .. bool(saved.branchProgress.rightDone))
        end
        end
        add(lines, "Kezdoeltolas", config.startOffset)
        add(lines, "Erc", bool(config.oreScanEnabled))
        add(lines, "Faklya", bool(config.torchEnabled))
        add(lines, "Inv.", bool(config.experimentalInventory))
        add(lines, "Fuel tartalek", config.fuelReserve)
        add(lines, "Tevekenyseg", saved.activity)
        add(lines, "Mentett fizikai hely", pose(
            saved.navigation and saved.navigation.pose or saved.position))
    elseif job.task == "excavator" then
        add(lines, "Meret", string.format("%sx%sx%s",
            tostring(config.width or "?"), tostring(config.depth or "?"),
            tostring(config.height or "?")))
        add(lines, "Feldolgozott cella", saved.visited)
        add(lines, "Befejezett alapcella", saved.baseCompleted)
        add(lines, "Faklya", bool(config.torchEnabled))
        add(lines, "Inv.", bool(config.experimentalInventory))
        add(lines, "Fuel tartalek", config.fuelReserve)
        if config.remoteStart and config.remoteStart.enabled then
            add(lines, "Bazis", pose(config.remoteStart.base, true))
            add(lines, "Munkapont", pose(config.remoteStart.work, true))
        end
        add(lines, "Tevekenyseg", saved.activity)
        add(lines, "Mentett fizikai hely", pose(
            saved.remote and saved.remote.phase ~= "at_work"
                and saved.remote.navigation and saved.remote.navigation.pose
                or saved.position,
            saved.remote and saved.remote.phase ~= "at_work"))
    elseif job.task == "nether_builder" then
        local mode = config.mode == 1 and ("lepcso " .. tostring(config.stairDirection))
            or config.mode == 2 and "vedett 1x2" or "sima 1x2"
        add(lines, "Mod", mode)
        add(lines, "Hossz", tostring(saved.completed or "?") .. "/" .. tostring(config.length or "?"))
        add(lines, "Epitoanyag", config.builderBlock)
        add(lines, "Faklya", bool(config.torchEnabled))
        add(lines, "Fedettre valtott", bool(saved.floodShell))
        add(lines, "Tevekenyseg", saved.activity)
        add(lines, "Mentett fizikai hely", pose(saved.position))
    elseif job.task == "coordinate" then
        add(lines, "Start", pose(config.start, true))
        add(lines, "Cel", pose(config.target, true))
        add(lines, "Rombolasi mod", config.mode)
        add(lines, "Fuel tartalek", config.fuelReserve)
        add(lines, "Fazis", saved.phase)
        add(lines, "Mentett fizikai hely", pose(
            saved.navigation and saved.navigation.pose, true))
    elseif job.task == "farm" then
        add(lines, "Mod", config.mode == "crop" and "noveny" or "allat")
        add(lines, "Bazis", pose(config.base, true))
        if config.mode == "crop" then
            add(lines, "Terulet", tostring(config.width) .. "x"
                .. tostring(config.depth) .. " / " .. tostring(config.crop))
        else add(lines, "Karamok", config.pens and #config.pens) end
        add(lines, "Kovetkezo cella/karam", saved.nextIndex)
        add(lines, "Befejezett korok", saved.cycle)
        add(lines, "Intervallum mp", config.intervalSeconds)
        add(lines, "Fazis", saved.phase)
        add(lines, "Mentett fizikai hely", pose(
            saved.navigation and saved.navigation.pose, true))
    elseif job.task == "chain" then
        add(lines, "Bazis", pose(config.base, true))
        add(lines, "Lepes", tostring(saved.index or "?") .. "/"
            .. tostring(config.steps and #config.steps or "?"))
        local step = config.steps and config.steps[saved.index or 1]
        add(lines, "Aktualis feladat", step and step.task)
        add(lines, "Reszfeladat elindult", bool(saved.childStarted))
        add(lines, "Fazis", saved.phase)
        add(lines, "Hiba", saved.lastError)
    end
    if saved.navigation and saved.navigation.pending or saved.pending then
        lines[#lines + 1] = "FIGYELEM: fuggo mozgas, helyzetet ellenorizni kell."
    end
    return lines
end

function preview.list()
    local result = {}
    for _, job in ipairs(jobs) do
        local saved = Store.read(job.file)
        if type(saved) == "table" and saved.version == (job.version or 1)
            and saved.active == true and type(saved.config) == "table" then
            local entry = Store.clone(job)
            entry.saved = saved
            if job.task == "branch_miner" then
                entry.progress = tostring(saved.mainCompleted or "?")
                    .. "/" .. tostring(saved.config.mainLength or "?")
            elseif job.task == "excavator" then
                entry.progress = tostring(saved.visited or "?") .. " cella"
            elseif job.task == "nether_builder" then
                entry.progress = tostring(saved.completed or "?")
                    .. "/" .. tostring(saved.config.length or "?")
            elseif job.task == "farm" then
                entry.progress = tostring(saved.nextIndex or "?")
                    .. " / " .. tostring(saved.phase or "?")
            elseif job.task == "chain" then
                entry.progress = tostring(saved.index or "?")
                    .. "/" .. tostring(saved.config.steps and
                    #saved.config.steps or "?")
            else entry.progress = tostring(saved.phase or "?") end
            result[#result + 1] = entry
        end
    end
    return result
end

return preview
