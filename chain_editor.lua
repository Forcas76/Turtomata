-- V2: egy mentett, szerkesztheto feladatlanc a kozos bazishoz.
local Store = require("state_store")
local UI = require("ui")
local Setup = require("job_setup")
local editor = {}
local FILE = "task_chain_definition.txt"
local labels = {
    excavator = "Terulet asas",
    farm = "Farm (egy kor)",
    branch_miner = "Branch (bazisrol)",
    nether_builder = "Utvonal (bazisrol)",
}
local function configure(task, settings, base, existing)
    local method = task == "branch_miner" and "branch"
        or task == "nether_builder" and "nether" or task
    local config = Setup[method](settings, existing)
    if not config then return nil end
    if task == "excavator" then
        config.remoteStart.enabled = true
        config.remoteStart.base = Store.clone(base)
        config.remoteStart.work.heading =
            (base.heading + config.remoteStart.relativeTurn) % 4
    elseif task == "farm" then
        config.base = Store.clone(base)
        config.oneShot = true
    end
    return config
end
local function editNumber(title, object, key)
    local value = UI.integer(title, title, object[key])
    if value ~= nil then object[key] = value end
end
local function editBase(base)
    while true do
        local choice = UI.menu("KOZOS BAZIS", {
            { label = "X", suffix = base.x, value = "x" },
            { label = "Y", suffix = base.y, value = "y" },
            { label = "Z", suffix = base.z, value = "z" },
            { label = "Irany", suffix = base.heading, value = "heading" },
            { label = "Vissza", value = "back" },
        })
        if not choice or choice == "back" then return end
        if choice == "heading" then
            local value = UI.choice("BAZIS IRANY",
                { "Eszak", "Kelet", "Del", "Nyugat" }, base.heading + 1)
            if value then base.heading = value - 1 end
        else editNumber("BAZIS " .. choice:upper(), base, choice) end
    end
end
local function save(definition)
    local ok, reason = Store.write(FILE, definition)
    if not ok then UI.message("LANC MENTESHIBA", tostring(reason), "error")
        UI.waitForEnter() end
    return ok
end
function editor.open(settings)
    local definition = Store.read(FILE)
    if type(definition) ~= "table" or definition.version ~= 1 then
        definition = {
            version = 1,
            base = Store.clone(settings.navigation.base
                or { x = 0, y = 64, z = 0, heading = 0 }),
            steps = {},
            resumeOnStartup = settings.general.autoResumeDefault,
        }
    end
    while true do
        local items = {
            { label = "Bazis", suffix = string.format("%d,%d,%d",
                definition.base.x, definition.base.y, definition.base.z),
                value = "base" },
            { label = "Auto folytatas",
                suffix = definition.resumeOnStartup and "BE" or "KI",
                value = "auto" },
        }
        for index, step in ipairs(definition.steps) do
            items[#items + 1] = {
                label = index .. ". " .. labels[step.task],
                suffix = step.enabled == false and "KI" or "BE",
                value = index,
            }
        end
        items[#items + 1] = { label = "Lepes hozzaadasa", value = "add" }
        items[#items + 1] = { label = "Lanc inditasa", value = "start",
            enabled = #definition.steps > 0 }
        items[#items + 1] = { label = "Vissza", value = "back" }
        local choice = UI.menu("KISERLETI FELADATLANC", items)
        if not choice or choice == "back" then return nil end
        if choice == "base" then
            editBase(definition.base)
            for _, step in ipairs(definition.steps) do
                if step.task == "excavator" then
                    step.config.remoteStart.base = Store.clone(definition.base)
                elseif step.task == "farm" then
                    step.config.base = Store.clone(definition.base)
                end
            end
        elseif choice == "auto" then
            definition.resumeOnStartup = not definition.resumeOnStartup
        elseif choice == "add" then
            local selected = UI.choice("UJ LANCLEPES", {
                labels.excavator, labels.farm,
                labels.branch_miner, labels.nether_builder,
            })
            if selected then
                local task = ({ "excavator", "farm",
                    "branch_miner", "nether_builder" })[selected]
                local config = configure(task, settings, definition.base)
                if config then
                    definition.steps[#definition.steps + 1] = {
                        task = task, config = config, enabled = true,
                    }
                end
            end
        elseif choice == "start" then
            local summary = {
                string.format("Bazis: %d,%d,%d irany=%d",
                    definition.base.x, definition.base.y,
                    definition.base.z, definition.base.heading),
                "Lepesek: " .. #definition.steps,
            }
            for index, step in ipairs(definition.steps) do
                summary[#summary + 1] = index .. ". " .. labels[step.task]
                    .. (step.enabled == false and " [KI]" or "")
            end
            summary[#summary + 1] = "Minden lepes utan vissza a bazisra."
            if UI.confirm("LANC ATTEKINTES", summary, "ENTER = inditas") then
                if save(definition) then return Store.clone(definition), summary end
            end
        else
            local index = choice
            local step = definition.steps[index]
            local action = UI.menu("LANCLEPES " .. index, {
                { label = labels[step.task], enabled = false, value = "info" },
                { label = "Beallitasok szerkesztese", value = "edit" },
                { label = "Masolas", value = "copy" },
                { label = "Aktiv", suffix = step.enabled == false and "KI" or "BE",
                    value = "toggle" },
                { label = "Fel", enabled = index > 1, value = "up" },
                { label = "Le", enabled = index < #definition.steps, value = "down" },
                { label = "Torles", value = "delete" },
                { label = "Vissza", value = "back" },
            })
            if action == "edit" then
                local config = configure(step.task, settings,
                    definition.base, step.config)
                if config then step.config = config end
            elseif action == "copy" then
                table.insert(definition.steps, index + 1, Store.clone(step))
            elseif action == "toggle" then
                step.enabled = step.enabled == false
            elseif action == "up" then
                definition.steps[index], definition.steps[index - 1] =
                    definition.steps[index - 1], step
            elseif action == "down" then
                definition.steps[index], definition.steps[index + 1] =
                    definition.steps[index + 1], step
            elseif action == "delete" and UI.confirm("TORLES",
                { index .. ". " .. labels[step.task] }, "ENTER = torles") then
                table.remove(definition.steps, index)
            end
        end
        save(definition)
    end
end
return editor
