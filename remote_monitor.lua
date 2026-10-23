-- Turtomata megfigyelo Pocket Computerhez es normal/Advanced Computerhez.

local Protocol = require("remote_protocol")
local SwarmProtocol = require("swarm_protocol")
local SwarmCoordinator = require("swarm_coordinator")
local Version = require("version")
local Settings = require("settings")
local Localization = require("localization")
local monitorSettings = Settings.load()
Localization.setLanguage(monitorSettings.general.language)
local function tr(value) return Localization.text(value) end
local turtles = {}
local selected = 1
local opened = {}
local pages = { "status", "commands", "swarm", "settings" }
local pageIndex = 1
local page = pages[pageIndex]
local commandSelected = 1
local settingsSelected = monitorSettings.general.language == "en" and 2 or 1
local swarmSelected = 1
local armedReconcile = nil
local armedCommand = nil
local feedback = ""
local pendingSwarmClaim = nil
local online
local nativeTerm = term.current()
local display, displayName = nativeTerm, nil

local function hasPeripheralType(name, wanted)
    if peripheral.hasType then
        local ok, result = pcall(peripheral.hasType, name, wanted)
        if ok and result then return true end
    end
    local called = { pcall(peripheral.getType, name) }
    if not called[1] then return false end
    for index = 2, #called do
        local value = called[index]
        if value == wanted then return true end
    end
    return false
end

local function selectDisplay(force)
    if not force and displayName and peripheral.isPresent(displayName)
        and hasPeripheralType(displayName, "monitor") then
        return display
    end
    display, displayName = nativeTerm, nil
    if not peripheral then return display end
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        if hasPeripheralType(name, "monitor") then
            local monitor = peripheral.wrap(name)
            if monitor then
                pcall(monitor.setTextScale, 1)
                local ok, width, height = pcall(monitor.getSize)
                if ok and (width < 35 or height < 16) then
                    pcall(monitor.setTextScale, 0.5)
                end
                display, displayName = monitor, name
                return display
            end
        end
    end
    return display
end

local function nowMs()
    return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function openModems()
    if not peripheral or not rednet then return 0 end
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        local ok, wireless = pcall(peripheral.call, name, "isWireless")
        if ok and wireless then
            if not rednet.isOpen(name) then pcall(rednet.open, name) end
            if rednet.isOpen(name) then opened[name], count = true, count + 1 end
        end
    end
    for name in pairs(opened) do
        if not peripheral.isPresent(name) or not rednet.isOpen(name) then opened[name] = nil end
    end
    return count
end

local function discover()
    if openModems() == 0 then return false end
    rednet.broadcast(Protocol.message("discover", {
        viewerId = os.getComputerID(),
    }), Protocol.CONTROL)
    return true
end

local function swarmHeartbeat()
    local state = SwarmCoordinator.load()
    if not SwarmCoordinator.confirmedThisRun() or not state or not state.active
        or openModems() == 0 then return end
    if state.stopped then
        rednet.broadcast(SwarmProtocol.message("swarm_stop", {
            jobId = state.jobId, epoch = state.epoch,
            coordinatorId = os.getComputerID(),
        }), SwarmProtocol.CHANNEL)
        return
    end
    rednet.broadcast(SwarmProtocol.message("coordinator_heartbeat", {
        jobId = state.jobId, leaderId = state.leaderId,
        coordinatorId = os.getComputerID(), epoch = state.epoch,
    }), SwarmProtocol.CHANNEL)
end

local function markMissingWorkers()
    if not SwarmCoordinator.confirmedThisRun() then return end
    local state = SwarmCoordinator.load()
    if not state or not state.active then return end
    for id, worker in pairs(state.workers or {}) do
        if worker.status ~= "uncertain" then
            local seen = turtles[tonumber(id)]
            local lastSeen = seen and seen.receivedAt or worker.registeredAt or 0
            if lastSeen > 0 and nowMs() - lastSeen
                > Protocol.OFFLINE_AFTER * 1000 then
                SwarmCoordinator.markWorkerUncertain(tonumber(id),
                    "Kapcsolatvesztes: helyszini ellenorzes kell.")
            end
        end
    end
end

local function dispatchAssignments()
    if not SwarmCoordinator.confirmedThisRun() then return end
    local state = SwarmCoordinator.load()
    if not state or not state.active or state.stopped
        or openModems() == 0 then return end
    local leader = turtles[state.leaderId]
    if not leader or not online(leader) then return end
    local list = {}
    for id, worker in pairs(state.workers or {}) do
        list[#list + 1] = { id = tonumber(id), slot = worker.slot,
            status = worker.status, key = worker.assignedBranch }
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    for _, worker in ipairs(list) do
        if worker.status == "registered_no_motion" and not state.closing then
            local ok, _, key = SwarmCoordinator.claimNextBranch(worker.id)
            if ok then worker.key, worker.status = key, "offered_no_motion" end
        end
        if worker.status == "offered_no_motion" and worker.key then
            local z, side = worker.key:match(":(%d+):([^:]+)$")
            if z and side then
                rednet.send(worker.id, SwarmProtocol.message("task_offer", {
                    jobId = state.jobId, epoch = state.epoch,
                    coordinatorId = os.getComputerID(),
                    workerId = worker.id, branchKey = worker.key,
                    z = tonumber(z), side = side,
                }), SwarmProtocol.CHANNEL)
            end
        end
    end
end

local function ordered()
    local result = {}
    for _, value in pairs(turtles) do result[#result + 1] = value end
    table.sort(result, function(a, b) return a.turtleId < b.turtleId end)
    return result
end

local commands = {
    { label = "Adatok frissitese", command = "status", confirm = false },
    { label = "Kozos munka kezelese (kiserleti)", command = "swarm_claim", confirm = true },
    { label = "Kozos munka veszleallas", command = "swarm_stop", confirm = true },
    { label = "Lepakolas es folytatas", command = "service", confirm = true },
    { label = "Munka leallitasa, haza", command = "return_home", confirm = true },
    { label = "Megfigyelo frissitese", command = "local_update", confirm = true },
}

local function selectedTurtle()
    return ordered()[selected]
end

local function orderedSwarmWorkers(state)
    local list = {}
    for id, worker in pairs(state and state.workers or {}) do
        list[#list + 1] = { id = tonumber(id), slot = worker.slot,
            status = worker.status, correctedPose = worker.correctedPose }
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

local function approveSelectedPose()
    local state = SwarmCoordinator.load()
    local worker = orderedSwarmWorkers(state)[swarmSelected]
    if not worker or worker.status ~= "needs_reconcile"
        or not worker.correctedPose then
        feedback = "Nincs kijelolt helyzetjavitas."
        return
    end
    if armedReconcile ~= worker.id then
        armedReconcile = worker.id
        feedback = "Ellenorizd a turtle fizikai helyet; Enter ujra = jovahagyas."
        return
    end
    armedReconcile = nil
    local ok, reason = SwarmCoordinator.approvePose(worker.id)
    feedback = ok and "Helyzet egyeztetve; nincs automatikus mozgas."
        or tostring(reason)
    if ok then
        rednet.send(worker.id, SwarmProtocol.message("pose_reconcile_ack", {
            jobId = state.jobId, epoch = state.epoch,
            coordinatorId = os.getComputerID(), workerId = worker.id,
            accepted = true,
            status = SwarmCoordinator.load().workers[tostring(worker.id)].status,
        }), SwarmProtocol.CHANNEL)
    end
end

local function sendCommand(command)
    local target = selectedTurtle()
    if not target then feedback = tr("Nincs kivalasztott turtle.") return false end
    if openModems() == 0 then feedback = tr("Nincs vezetek nelkuli modem.") return false end
    local requestId = tostring(os.getComputerID()) .. "-" .. tostring(nowMs())
    local sent = rednet.send(target.turtleId, Protocol.message("command", {
        targetId = target.turtleId,
        command = command,
        requestId = requestId,
    }), Protocol.CONTROL)
    feedback = tr(sent and "Parancs elkuldve; visszaigazolasra var."
        or "A parancs kuldese sikertelen.")
    return sent
end

local function activateCommand()
    local item = commands[commandSelected]
    if not item then return end
    if item.confirm and armedCommand ~= item.command then
        armedCommand = item.command
        feedback = tr("Megeroses: valaszd ki meg egyszer.")
        return
    end
    armedCommand = nil
    if item.command == "swarm_stop" then
        local ok, reason = SwarmCoordinator.emergencyStop()
        feedback = ok and "Veszleallas mentve; a turtle-k helyben megallnak."
            or tostring(reason)
        if ok then swarmHeartbeat() end
    elseif item.command == "swarm_claim" then
        local target = selectedTurtle()
        local swarm = target and target.swarm
        local existing = SwarmCoordinator.load()
        if not target or not online(target) or not swarm
            or swarm.role ~= "leader" or not swarm.jobId then
            feedback = "Nincs elerheto kozosmunka-vezeto turtle."
        elseif existing and existing.active and existing.jobId ~= swarm.jobId then
            feedback = "Ezen az eszkozon mar masik munka van mentve."
        elseif swarm.coordinatorId and swarm.coordinatorId ~= os.getComputerID() then
            feedback = "Ezt a munkat masik eszkoz kezeli."
        elseif openModems() == 0 then
            feedback = "Nincs vezetek nelkuli modem."
        else
            pendingSwarmClaim = {
                jobId = swarm.jobId, leaderId = target.turtleId,
                requestId = tostring(os.getComputerID()) .. "-" .. tostring(nowMs()),
            }
            local sent = rednet.send(target.turtleId,
                SwarmProtocol.message("coordinator_claim", {
                    jobId = swarm.jobId, leaderId = target.turtleId,
                    requestId = pendingSwarmClaim.requestId,
                }), SwarmProtocol.CHANNEL)
            feedback = sent and "Kezeloi visszaigazolasra var."
                or "A kezelo-keres nem kuldheto."
            if not sent then pendingSwarmClaim = nil end
        end
    elseif item.command == "local_update" then
        feedback = tr("Program frissitese...")
        local ok = shell.run("downloader", "monitor")
        if ok then
            feedback = tr("Frissites kesz. Ujrainditas...")
            sleep(1)
            os.reboot()
        else
            feedback = tr("A frissites sikertelen.")
        end
    else
        sendCommand(item.command)
    end
end

local function clip(value, width)
    value = tostring(value or "-")
    if #value <= width then return value end
    return string.sub(value, 1, math.max(1, width - 1)) .. ">"
end

local function duration(ms)
    local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    return string.format("%02d:%02d:%02d",
        math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
end

online = function(value)
    return nowMs() - value.receivedAt <= Protocol.OFFLINE_AFTER * 1000
end

local function percent(value)
    local total = tonumber(value.progressTotal) or 0
    if total <= 0 then return "-" end
    return math.floor(((tonumber(value.progressCurrent) or 0) / total) * 100) .. "%"
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function line(label, value, width)
    local prefix = tr(label) .. ": "
    print(clip(prefix .. tostring(value or "-"), width))
end

local activityNames = {
    idle = "Varakozik",
    menu = "Fomenu",
    indulas = "Indulas",
    kitores = "Terulet kitermelese",
    hazateres = "Hazateres",
    urites_tankolas = "Lepakolas es tankolas",
    vissza_munkapontra = "Visszateres a munkahoz",
    auto_ujrainditas = "Mentett munka folytatasa",
    lepcso_epites = "Lepcso epites",
    alagut_epites = "Alagut epites",
    bal_oldalagat = "Bal oldalagat asasa",
    jobb_oldalagat = "Jobb oldalagat asasa",
    bal_ag_erckereses = "Erckereses a bal agban",
    jobb_ag_erckereses = "Erckereses a jobb agban",
    agak_keszen = "Oldalagak keszen",
    navigalas = "Navigalas",
    kesz = "Befejezve",
    megallitva_otthon = "Megallitva a bazison",
}

local taskNames = {
    ["Branch mining"] = "Agas banyaszat",
    ["Terulet asas"] = "Terulet kiasasa",
    ["Nether utepito"] = "Nether utepites",
    ["Koordinatas navigacio"] = "Koordinatas mozgas",
    ["Varakozas a fomenuben"] = "Fomenu",
}

local function readableActivity(value)
    value = tostring(value or "Ismeretlen")
    if activityNames[value] then return tr(activityNames[value]) end
    value = value:gsub("_", " ")
    return value:sub(1, 1):upper() .. value:sub(2)
end

local function readableTask(value)
    return tr(taskNames[value] or tostring(value or "Ismeretlen"))
end

local function printWrapped(value, width, maximumLines)
    value = tostring(value or "")
    local lineText, printed = "", 0
    for word in value:gmatch("%S+") do
        if lineText == "" then lineText = word
        elseif #lineText + #word + 1 <= width then lineText = lineText .. " " .. word
        else
            print(clip(lineText, width))
            printed = printed + 1
            if printed >= maximumLines then return end
            lineText = word
        end
    end
    if lineText ~= "" and printed < maximumLines then print(clip(lineText, width)) end
end

local function renderStatusBody()
    local width, height = term.getSize()
    local list = ordered()
    if selected > #list then selected = math.max(1, #list) end
    clear()
    term.setTextColor(colors.cyan)
    print(clip("TURTOMATA " .. Version.label .. " | " .. tr("MEGFIGYELO"), width))
    term.setTextColor(colors.lightGray)
    print(string.rep("-", math.min(width, 39)))
    if openModems() == 0 then
        term.setTextColor(colors.red)
        print(tr("Nincs wireless/Ender modem."))
        print(tr("Csatlakoztass modemet; automatikusan felismerem."))
    elseif #list == 0 then
        term.setTextColor(colors.orange)
        print(tr("Turtle keresese..."))
        print(tr("Bekapcsolas utan automatikusan megjelenik."))
    elseif width < 35 or height < 16 then
        local item = list[selected]
        term.setTextColor(online(item) and colors.lime or colors.red)
        print(clip((item.label or ("Teknos #" .. item.turtleId))
            .. " " .. tr(online(item) and "ELERHETO" or "NEM ELERHETO"), width))
        term.setTextColor(colors.white)
        line("Feladat", readableTask(item.task)
            .. (item.chainCurrent and (" [" .. item.chainCurrent .. "/"
                .. tostring(item.chainTotal) .. "]") or ""), width)
        line("Muvelet", readableActivity(item.activity), width)
        if item.swarm then
            line("Kozos munka", item.swarm.role .. " / " .. item.swarm.status
                .. " / #" .. tostring(item.swarm.coordinatorId or "-")
                .. (item.swarm.coordinatorOnline and " +" or " !"), width)
        end
        if item.lastError then line("Hiba", item.lastError, width) end
        line("Haladas", percent(item), width)
        line("Uzemanyag", item.fuel == -1 and "vegtelen" or item.fuel, width)
        line("Tarhely", item.inventoryUsed and (item.inventoryUsed .. "/16 hely") or "-", width)
        line("Eltelt", duration(item.elapsedMs), width)
        line("Hatra", duration(item.remainingMs), width)
        if item.position then
            line("Pozicio", string.format("%d,%d,%d", item.position.x, item.position.y, item.position.z), width)
        end
        term.setCursorPos(1, height)
        write(clip(tr("Bal/jobb: oldal | Fel/le: teki | Q"), width))
    else
        print(string.format("%-4s %-16s %-12s %s", "ID", tr("Teknos"), tr("Kapcsolat"), tr("Kesz")))
        local maximum = math.max(1, height - 13)
        for index = 1, math.min(#list, maximum) do
            local item = list[index]
            term.setTextColor(index == selected and colors.yellow
                or (online(item) and colors.white or colors.red))
            print(clip(string.format("%-4d %-16s %-12s %s",
                item.turtleId, item.label or tr("Teknos"), tr(online(item) and "ELERHETO" or "NINCS JEL"),
                percent(item)), width))
        end
        local item = list[selected]
        term.setTextColor(colors.lightGray)
        print(string.rep("-", math.min(width, 39)))
        term.setTextColor(colors.white)
        line("Feladat", readableTask(item.task), width)
        if item.chainCurrent then
            line("Lanc", tostring(item.chainCurrent) .. "/"
                .. tostring(item.chainTotal) .. " "
                .. tostring(item.chainTask or "-"), width)
        end
        line("Muvelet", readableActivity(item.activity), width)
        if item.swarm then
            line("Kozos munka", item.swarm.role .. " / " .. item.swarm.status
                .. " / #" .. tostring(item.swarm.coordinatorId or "-")
                .. (item.swarm.coordinatorOnline and " +" or " !"), width)
        end
        if item.lastError then line("Hiba", item.lastError, width) end
        line("Uzemanyag / tarhely", tostring(item.fuel == -1 and "vegtelen" or item.fuel)
            .. " / " .. tostring(item.inventoryUsed or "-") .. "/16", width)
        line("Ido", "eltelt " .. duration(item.elapsedMs) .. " / hatra " .. duration(item.remainingMs), width)
        if item.position then
            line("Pozicio", string.format("%d,%d,%d h=%s", item.position.x,
                item.position.y, item.position.z, tostring(item.position.heading or "-")), width)
        end
        term.setCursorPos(1, height)
        write(clip(tr("Bal/jobb: oldal | Fel/le/katt: teki | Q"), width))
    end
end

local function renderCommandBody()
    local width, height = term.getSize()
    local target = selectedTurtle()
    clear()
    term.setTextColor(colors.orange)
    print(clip("TURTOMATA " .. Version.label .. " | " .. tr("PARANCSOK"), width))
    term.setTextColor(colors.lightGray)
    print(string.rep("-", math.min(width, 39)))
    if not target then
        term.setTextColor(colors.red)
        print("Nincs elerheto turtle.")
    else
        term.setTextColor(online(target) and colors.lime or colors.red)
        print(clip((target.label or ("Teknos #" .. target.turtleId))
            .. " " .. tr(online(target) and "ELERHETO" or "NEM ELERHETO"), width))
        print("")
        for index, item in ipairs(commands) do
            term.setTextColor(index == commandSelected and colors.yellow or colors.white)
            print(clip((index == commandSelected and "> " or "  ") .. tr(item.label), width))
        end
        if feedback ~= "" then
            print("")
            term.setTextColor(armedCommand and colors.orange or colors.lightGray)
            printWrapped(feedback, width, 3)
        end
    end
    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, height)
    write(clip(tr("Bal/jobb: oldal | Fel/le: opcio | Enter"), width))
end

local function renderSettingsBody()
    local width, height = term.getSize()
    clear()
    term.setTextColor(colors.cyan)
    print(clip("TURTOMATA " .. Version.label .. " | " .. tr("BEALLITASOK"), width))
    term.setTextColor(colors.lightGray)
    print(string.rep("-", math.min(width, 39)))
    print(tr("Nyelv / Language"))
    print("")
    local languages = Localization.languages()
    for index, value in ipairs(languages) do
        term.setTextColor(index == settingsSelected and colors.yellow or colors.white)
        print(clip((index == settingsSelected and "> " or "  ") .. tr(value.label), width))
    end
    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, height)
    write(clip(tr("Bal/jobb: oldal | Fel/le: opcio | Enter"), width))
end

local function renderSwarmBody()
    local width, height = term.getSize()
    local state = SwarmCoordinator.load()
    clear()
    term.setTextColor(colors.cyan)
    print(clip("TURTOMATA " .. Version.label .. " | " .. tr("KOZOS MUNKA"), width))
    term.setTextColor(colors.lightGray)
    print(string.rep("-", math.min(width, 39)))
    if not state or not state.active then
        print(tr("Nincs ezen az eszkozon kezelt kozos munka."))
        print(tr("A Parancsok oldalon valassz vezetot."))
    else
        line("Munka", state.jobId, width)
        line("Vezeto", "#" .. tostring(state.leaderId), width)
        line("Kezelo", "#" .. tostring(state.coordinatorId), width)
        line("Epoch", state.epoch, width)
        line("Allapot", state.status or "-", width)
        local ready, claimed = 0, 0
        for _, branch in pairs(state.branches or {}) do
            if branch.status == "ready" then ready = ready + 1
            elseif branch.status == "claimed" then claimed = claimed + 1 end
        end
        line("Agak", "szabad " .. ready .. " / foglalt " .. claimed, width)
        print(tr("Resztvevok (kiserleti kozos munka):"))
        print(clip("  #" .. state.leaderId .. " / 1 / leader", width))
        local list = orderedSwarmWorkers(state)
        swarmSelected = math.max(1, math.min(swarmSelected, #list))
        for index = 1, math.min(#list, math.max(0, height - 11)) do
            local worker = list[index]
            term.setTextColor(index == swarmSelected and colors.yellow or colors.white)
            print(clip((index == swarmSelected and "> " or "  ")
                .. "#" .. worker.id .. " / " .. worker.slot
                .. " / " .. worker.status, width))
        end
        print("")
        term.setTextColor(colors.orange)
        print(clip(tr("Ag kiosztas: automatikus; inditas: turtle menuben."), width))
        local worker = list[swarmSelected]
        if worker and worker.correctedPose then
            local pose = worker.correctedPose
            print(clip(string.format("Javitas: %d,%d,%d h%d",
                pose.x, pose.y, pose.z, pose.heading), width))
            print(clip("Enter 2x = helyszini ellenorzes utan jovahagyas", width))
        end
        if feedback ~= "" then print(clip(feedback, width)) end
    end
    term.setTextColor(colors.lightGray)
    term.setCursorPos(1, height)
    write(clip(tr("Bal/jobb: oldal | Q"), width))
end

local function render()
    selectDisplay(false)
    local targets = { nativeTerm }
    for _, target in ipairs(targets) do
        local previous = term.redirect(target)
        local renderer = page == "commands" and renderCommandBody
            or (page == "settings" and renderSettingsBody
            or (page == "swarm" and renderSwarmBody or renderStatusBody))
        local ok, reason = pcall(renderer)
        term.redirect(previous)
        if not ok then error(reason, 0) end
    end
    if displayName and display ~= nativeTerm then
        local previous = term.redirect(display)
        local ok, reason = pcall(renderStatusBody)
        term.redirect(previous)
        if not ok then error(reason, 0) end
    end
end

local function displaySize()
    local target = selectDisplay(false)
    local ok, width, height = pcall(target.getSize)
    if ok then return width, height end
    return nativeTerm.getSize()
end

discover()
local discoverTimer = os.startTimer(Protocol.DISCOVER_INTERVAL)
local refreshTimer = os.startTimer(1)
render()

while true do
    local event, p1, p2, p3 = os.pullEventRaw()
    if event == "terminate" then break
    elseif event == "rednet_message" and p3 == Protocol.STATUS
        and Protocol.valid(p2, "status") then
        p2.receivedAt = nowMs()
        turtles[p2.turtleId or p1] = p2
        render()
    elseif event == "rednet_message" and p3 == Protocol.ACK
        and Protocol.valid(p2, "ack") then
        feedback = (p2.accepted and "OK: " or "HIBA: ")
            .. tostring(tr(p2.reason or "Nincs reszlet."))
        render()
    elseif event == "rednet_message" and p3 == SwarmProtocol.CHANNEL
        and SwarmProtocol.valid(p2) then
        if p2.type == "coordinator_ack" and pendingSwarmClaim
            and p1 == pendingSwarmClaim.leaderId
            and p2.jobId == pendingSwarmClaim.jobId
            and p2.requestId == pendingSwarmClaim.requestId then
            local accepted, reason = SwarmCoordinator.claimAcknowledged(
                p2, os.getComputerID())
            feedback = accepted and "Kezelo elfogadva; egyelore csak regisztracio."
                or (p2.reason or reason or "A kezelo-keres elutasitva.")
            pendingSwarmClaim = nil
            render()
        elseif p2.type == "join_request" then
            local accepted, reason, state = SwarmCoordinator.registerWorker(p2, p1)
            rednet.send(p1, SwarmProtocol.message("join_ack", {
                jobId = p2.jobId, workerId = p1, epoch = p2.epoch,
                accepted = accepted, reason = reason,
                coordinatorId = os.getComputerID(),
            }), SwarmProtocol.CHANNEL)
            feedback = accepted and ("Segedturtle #" .. p1 .. " regisztralva, sorszam: "
                .. tostring(p2.slot)) or tostring(reason)
            render()
        elseif p2.type == "branch_ready" then
            local accepted, reason, key = SwarmCoordinator.noteBranchReady(p2, p1)
            rednet.send(p1, SwarmProtocol.message("branch_ready_ack", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(),
                branchKey = key, accepted = accepted, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if accepted then render() end
        elseif p2.type == "pose_correction" then
            local accepted, reason, phase = SwarmCoordinator.recordPoseCorrection(p2, p1)
            if accepted and phase == "approved" then
                rednet.send(p1, SwarmProtocol.message("pose_reconcile_ack", {
                    jobId = p2.jobId, epoch = p2.epoch,
                    coordinatorId = os.getComputerID(), workerId = p1,
                    accepted = true,
                    status = SwarmCoordinator.load().workers[tostring(p1)].status,
                }), SwarmProtocol.CHANNEL)
            elseif not accepted then
                feedback = tostring(reason)
            end
            render()
        elseif p2.type == "task_ack" then
            local ok, reason = SwarmCoordinator.acknowledgeAssignment(p2, p1)
            if not ok then feedback = tostring(reason) end
            render()
        elseif p2.type == "transit_request" then
            local state = SwarmCoordinator.load()
            local leader = state and turtles[state.leaderId]
            local ok, reason
            if not leader or not online(leader) then
                ok, reason = false, "A vezeto turtle nem elerheto."
            else
                ok, reason = SwarmCoordinator.requestTransit(p2, p1)
            end
            rednet.send(p1, SwarmProtocol.message("transit_grant", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(), workerId = p1,
                requestId = p2.requestId, phase = p2.phase,
                accepted = ok, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if ok then render() end
        elseif p2.type == "transit_arrival" then
            local ok, reason = SwarmCoordinator.confirmTransitArrival(p2, p1)
            rednet.send(p1, SwarmProtocol.message("transit_arrival_ack", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(), workerId = p1,
                requestId = p2.requestId, phase = p2.phase,
                accepted = ok, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if ok then render() end
        elseif p2.type == "branch_complete" then
            local ok, reason = SwarmCoordinator.completeBranch(p2, p1)
            rednet.send(p1, SwarmProtocol.message("branch_complete_ack", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(), workerId = p1,
                branchKey = p2.branchKey, accepted = ok, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if ok then render() end
        elseif p2.type == "worker_attention" then
            local state = SwarmCoordinator.load()
            if state and state.active and state.jobId == p2.jobId
                and state.epoch == p2.epoch
                and state.coordinatorId == p2.coordinatorId
                and p2.workerId == p1 then
                SwarmCoordinator.markWorkerUncertain(p1, p2.reason)
                render()
            end
        elseif p2.type == "leave_request" then
            local ok, reason = SwarmCoordinator.leaveWorker(p2, p1)
            rednet.send(p1, SwarmProtocol.message("leave_ack", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(), workerId = p1,
                requestId = p2.requestId, accepted = ok, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if ok then render() end
        elseif p2.type == "leader_close_request" then
            local ok, reason = SwarmCoordinator.closeLeader(p2, p1)
            rednet.send(p1, SwarmProtocol.message("leader_close_ack", {
                jobId = p2.jobId, epoch = p2.epoch,
                coordinatorId = os.getComputerID(), leaderId = p1,
                requestId = p2.requestId, accepted = ok, reason = reason,
            }), SwarmProtocol.CHANNEL)
            if ok then render() end
        end
    elseif event == "timer" and p1 == discoverTimer then
        discover()
        discoverTimer = os.startTimer(Protocol.DISCOVER_INTERVAL)
        render()
    elseif event == "timer" and p1 == refreshTimer then
        swarmHeartbeat()
        markMissingWorkers()
        dispatchAssignments()
        refreshTimer = os.startTimer(1)
        render()
    elseif event == "peripheral" or event == "peripheral_detach" then
        openModems()
        selectDisplay(true)
        discover()
        render()
    elseif event == "key" then
        if p1 == keys.q then break
        elseif p1 == keys.left then
            pageIndex = pageIndex == 1 and #pages or pageIndex - 1
            page = pages[pageIndex]
            armedCommand = nil
        elseif p1 == keys.right then
            pageIndex = pageIndex == #pages and 1 or pageIndex + 1
            page = pages[pageIndex]
            armedCommand = nil
        elseif p1 == keys.up then
            if page == "commands" then
                commandSelected = math.max(1, commandSelected - 1)
                armedCommand = nil
            elseif page == "settings" then
                settingsSelected = math.max(1, settingsSelected - 1)
            elseif page == "swarm" then
                swarmSelected = math.max(1, swarmSelected - 1)
                armedReconcile = nil
            else selected = math.max(1, selected - 1) end
        elseif p1 == keys.down then
            if page == "commands" then
                commandSelected = math.min(#commands, commandSelected + 1)
                armedCommand = nil
            elseif page == "settings" then
                settingsSelected = math.min(#Localization.languages(), settingsSelected + 1)
            elseif page == "swarm" then
                swarmSelected = math.min(#orderedSwarmWorkers(SwarmCoordinator.load()),
                    swarmSelected + 1)
                armedReconcile = nil
            else selected = math.min(#ordered(), selected + 1) end
        elseif p1 == keys.enter and page == "commands" then
            activateCommand()
        elseif p1 == keys.enter and page == "settings" then
            local selectedLanguage = Localization.languages()[settingsSelected]
            monitorSettings.general.language = selectedLanguage.code
            Settings.save(monitorSettings)
            Localization.setLanguage(selectedLanguage.code)
        elseif p1 == keys.enter and page == "swarm" then
            approveSelectedPose()
        end
        render()
    elseif event == "mouse_click" then
        local _, height = nativeTerm.getSize()
        if page == "commands" then
            local commandIndex = p3 - 4
            if commands[commandIndex] then
                commandSelected = commandIndex
                activateCommand()
            end
        elseif page == "settings" then
            local languageIndex = p3 - 4
            local selectedLanguage = Localization.languages()[languageIndex]
            if selectedLanguage then
                settingsSelected = languageIndex
                monitorSettings.general.language = selectedLanguage.code
                Settings.save(monitorSettings)
                Localization.setLanguage(selectedLanguage.code)
            end
        elseif p3 >= 4 and p3 < height - 7 then
            selected = math.min(#ordered(), math.max(1, p3 - 3))
        end
        render()
    elseif event == "monitor_touch" and p1 == displayName then
        local list = ordered()
        local width, height = displaySize()
        if width < 35 or height < 16 then
            if p2 <= math.floor(width / 2) then selected = math.max(1, selected - 1)
            else selected = math.min(#list, selected + 1) end
        elseif p3 >= 4 and p3 < height - 7 then
            selected = math.min(#list, math.max(1, p3 - 3))
        end
        render()
    end
end

selectDisplay(false)
local finalTargets = { nativeTerm }
if displayName and display ~= nativeTerm then finalTargets[#finalTargets + 1] = display end
for _, target in ipairs(finalTargets) do
    local previous = term.redirect(target)
    clear()
    print("Megfigyelo leallitva.")
    term.redirect(previous)
end
