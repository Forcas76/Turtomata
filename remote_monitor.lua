-- CCTurtle megfigyelo Pocket Computerhez es normal/Advanced Computerhez.

local Protocol = require("remote_protocol")
local Version = require("version")
local Settings = require("settings")
local Localization = require("localization")
local monitorSettings = Settings.load()
Localization.setLanguage(monitorSettings.general.language)
local function tr(value) return Localization.text(value) end
local turtles = {}
local selected = 1
local opened = {}
local pages = { "status", "commands", "settings" }
local pageIndex = 1
local page = pages[pageIndex]
local commandSelected = 1
local settingsSelected = monitorSettings.general.language == "en" and 2 or 1
local armedCommand = nil
local feedback = ""
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

local function ordered()
    local result = {}
    for _, value in pairs(turtles) do result[#result + 1] = value end
    table.sort(result, function(a, b) return a.turtleId < b.turtleId end)
    return result
end

local commands = {
    { label = "Adatok frissitese", command = "status", confirm = false },
    { label = "Lepakolas es folytatas", command = "service", confirm = true },
    { label = "Munka leallitasa, haza", command = "return_home", confirm = true },
    { label = "Megfigyelo frissitese", command = "local_update", confirm = true },
}

local function selectedTurtle()
    return ordered()[selected]
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
    if item.command == "local_update" then
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

local function online(value)
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
    print(clip("CCTURTLE " .. Version.label .. " | " .. tr("MEGFIGYELO"), width))
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
        line("Feladat", readableTask(item.task), width)
        line("Muvelet", readableActivity(item.activity), width)
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
        line("Muvelet", readableActivity(item.activity), width)
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
    print(clip("CCTURTLE " .. Version.label .. " | " .. tr("PARANCSOK"), width))
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
    print(clip("CCTURTLE " .. Version.label .. " | " .. tr("BEALLITASOK"), width))
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

local function render()
    selectDisplay(false)
    local targets = { nativeTerm }
    for _, target in ipairs(targets) do
        local previous = term.redirect(target)
        local renderer = page == "commands" and renderCommandBody
            or (page == "settings" and renderSettingsBody or renderStatusBody)
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
    elseif event == "timer" and p1 == discoverTimer then
        discover()
        discoverTimer = os.startTimer(Protocol.DISCOVER_INTERVAL)
        render()
    elseif event == "timer" and p1 == refreshTimer then
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
            else selected = math.max(1, selected - 1) end
        elseif p1 == keys.down then
            if page == "commands" then
                commandSelected = math.min(#commands, commandSelected + 1)
                armedCommand = nil
            elseif page == "settings" then
                settingsSelected = math.min(#Localization.languages(), settingsSelected + 1)
            else selected = math.min(#ordered(), selected + 1) end
        elseif p1 == keys.enter and page == "commands" then
            activateCommand()
        elseif p1 == keys.enter and page == "settings" then
            local selectedLanguage = Localization.languages()[settingsSelected]
            monitorSettings.general.language = selectedLanguage.code
            Settings.save(monitorSettings)
            Localization.setLanguage(selectedLanguage.code)
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
