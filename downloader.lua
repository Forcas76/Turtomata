-- CC:Tweaked programfrissito Pastebin es GitHub tamogatassal.

local DEBUG = true
local INSTALLER_VERSION = "v1.5.2"
local UPDATE_RECEIPT = ".turtomata_update.txt"
local localizationOk, Localization = pcall(require, "localization")
-- A friss telepitesnel a lokalizacios modul meg nincs jelen.
local bootstrapEnglish = {
    ["Turtle program telepitese"] = "Install turtle program",
    ["Megfigyelo telepitese"] = "Install monitor program",
    ["TELEPITO"] = "INSTALLER",
    ["Forras"] = "Source",
    ["Nyilak + ENTER, vagy kattintas"] = "Arrow keys + ENTER, or click",
    ["komponensek"] = "components",
    ["Ujra"] = "Retry in",
    ["403: mas hiba is lehet."] = "403 may also mean access denied.",
    ["R/Enter: proba most"] = "R/Enter: retry now",
    ["Q/Esc: megszakit"] = "Q/Esc: cancel",
    ["varakozas"] = "backoff",
    ["FEJLESZTOI MENU"] = "DEVELOPER MENU",
    ["Tokenes GitHub frissites"] = "GitHub update with token",
    ["Publikus GitHub frissites"] = "Public GitHub update",
    ["Frissites megszakitasa"] = "Cancel update",
    ["Tokenfajl hianyzik vagy ures."] = "Token file missing or empty.",
    ["Fel/le + Enter"] = "Up/down + Enter",
    ["Frissites indul..."] = "Starting update...",
    ["Frissitve"] = "Updated",
    ["ENTER = lattamozas"] = "ENTER = acknowledge",
}
local function tr(value)
    return localizationOk and Localization.text(value)
        or bootstrapEnglish[value] or value
end

-- Itt valaszd ki a letoltesi forrast: "pastebin" vagy "github".
local DOWNLOAD_SOURCE = "github"

local GITHUB = {
    owner = "Forcas76",
    repo = "CCTurtle",
    branch = "main",
    -- Publikus repo: nincs hitelesites. Privat repohoz add meg a tokenfajlt.
    tokenFile = nil,
}
local DEVELOPER_TOKEN_FILE = ".github_token"
local AUTH_MODE_FILE = ".downloader_auth_mode"

local function savedAuthMode()
    if not fs.exists(AUTH_MODE_FILE) then return "public" end
    local file = fs.open(AUTH_MODE_FILE, "r")
    if not file then return "public" end
    local mode = file.readAll() or ""
    file.close()
    return mode == "token" and "token" or "public"
end

if savedAuthMode() == "token" then GITHUB.tokenFile = DEVELOPER_TOKEN_FILE end

local function developerToken()
    if not fs.exists(DEVELOPER_TOKEN_FILE) then return nil end
    local file = fs.open(DEVELOPER_TOKEN_FILE, "r")
    if not file then return nil end
    local token = file.readAll() or ""
    file.close()
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    return token ~= "" and token or nil
end

-- fileName: a turtle gepen letrehozo fajl neve.
-- githubPath: a fajl helye a GitHub repoban.
local links = {
    main = {
        pastebinID = "",
        githubPath = "main.lua",
        fileName = "main",
    },
    branch = {
        pastebinID = "YAdymjRk",
        githubPath = "branch_miner.lua",
        fileName = "branch_miner.lua",
    },
    downloader = {
        pastebinID = "hnT1J5cK",
        githubPath = "downloader.lua",
        fileName = "downloader",
    },
    excavator = {
        pastebinID = "",
        githubPath = "excavator.lua",
        fileName = "excavator",
    },
    torch = {
        pastebinID = "",
        githubPath = "torch_manager.lua",
        fileName = "torch_manager.lua",
    },
    actionlog = {
        pastebinID = "",
        githubPath = "action_log.lua",
        fileName = "action_log.lua",
    },
    inventory = {
        pastebinID = "",
        githubPath = "inventory_manager.lua",
        fileName = "inventory_manager.lua",
    },
    ore = {
        pastebinID = "",
        githubPath = "ore_scanner.lua",
        fileName = "ore_scanner.lua",
    },
    nether = {
        pastebinID = "",
        githubPath = "nether_builder.lua",
        fileName = "nether_builder.lua",
    },
    ui = { pastebinID = "", githubPath = "ui.lua", fileName = "ui.lua" },
    settings = { pastebinID = "", githubPath = "settings.lua", fileName = "settings.lua" },
    state = { pastebinID = "", githubPath = "state_store.lua", fileName = "state_store.lua" },
    navigation = { pastebinID = "", githubPath = "navigation.lua", fileName = "navigation.lua" },
    coordinate = { pastebinID = "", githubPath = "coordinate_navigation.lua", fileName = "coordinate_navigation.lua" },
    coordinatetask = { pastebinID = "", githubPath = "coordinate_task.lua", fileName = "coordinate_task.lua" },
    situations = { pastebinID = "", githubPath = "situation_manager.lua", fileName = "situation_manager.lua" },
    telemetry = { pastebinID = "", githubPath = "telemetry.lua", fileName = "telemetry.lua" },
    estimator = { pastebinID = "", githubPath = "work_estimator.lua", fileName = "work_estimator.lua" },
    request = { pastebinID = "", githubPath = "job_request.lua", fileName = "job_request.lua" },
    registry = { pastebinID = "", githubPath = "work_registry.lua", fileName = "work_registry.lua" },
    preview = { pastebinID = "", githubPath = "job_preview.lua", fileName = "job_preview.lua" },
    basedock = { pastebinID = "", githubPath = "base_dock.lua", fileName = "base_dock.lua" },
    setup = { pastebinID = "", githubPath = "job_setup.lua", fileName = "job_setup.lua" },
    farm = { pastebinID = "", githubPath = "farm_task.lua", fileName = "farm_task.lua" },
    chain = { pastebinID = "", githubPath = "task_chain.lua", fileName = "task_chain.lua" },
    chaineditor = { pastebinID = "", githubPath = "chain_editor.lua", fileName = "chain_editor.lua" },
    version = { pastebinID = "", githubPath = "version.lua", fileName = "version.lua" },
    localization = { pastebinID = "", githubPath = "localization.lua", fileName = "localization.lua" },
    remoteprotocol = { pastebinID = "", githubPath = "remote_protocol.lua", fileName = "remote_protocol.lua" },
    swarmgeometry = { pastebinID = "", githubPath = "swarm_geometry.lua", fileName = "swarm_geometry.lua" },
    stationregistry = { pastebinID = "", githubPath = "station_registry.lua", fileName = "station_registry.lua" },
    servicescheduler = { pastebinID = "", githubPath = "service_scheduler.lua", fileName = "service_scheduler.lua" },
    pickupledger = { pastebinID = "", githubPath = "pickup_ledger.lua", fileName = "pickup_ledger.lua" },
    swarmsafety = { pastebinID = "", githubPath = "swarm_safety.lua", fileName = "swarm_safety.lua" },
    swarmprotocol = { pastebinID = "", githubPath = "swarm_protocol.lua", fileName = "swarm_protocol.lua" },
    swarmsession = { pastebinID = "", githubPath = "swarm_session.lua", fileName = "swarm_session.lua" },
    swarmmenu = { pastebinID = "", githubPath = "swarm_menu.lua", fileName = "swarm_menu.lua" },
    swarmcoordinator = { pastebinID = "", githubPath = "swarm_coordinator.lua", fileName = "swarm_coordinator.lua" },
    swarmestimator = { pastebinID = "", githubPath = "swarm_estimator.lua", fileName = "swarm_estimator.lua" },
    swarmtraffic = { pastebinID = "", githubPath = "swarm_traffic.lua", fileName = "swarm_traffic.lua" },
    swarmworker = { pastebinID = "", githubPath = "swarm_worker.lua", fileName = "swarm_worker.lua" },
    remote = { pastebinID = "", githubPath = "remote.lua", fileName = "remote.lua" },
    monitor = { pastebinID = "", githubPath = "remote_monitor.lua", fileName = "remote_monitor.lua" },
    startupturtle = { pastebinID = "", githubPath = "startup_turtle.lua", fileName = "startup.lua" },
    startupmonitor = { pastebinID = "", githubPath = "startup_monitor.lua", fileName = "startup.lua" },
}

local downloadOrder = {
    "state", "navigation", "coordinate", "situations", "telemetry", "estimator", "localization", "ui", "settings", "request", "registry", "preview", "basedock", "setup",
    "torch", "actionlog", "inventory", "ore", "branch", "excavator", "nether", "farm", "chain", "chaineditor",
    "coordinatetask", "version", "remoteprotocol", "swarmgeometry", "stationregistry", "servicescheduler", "pickupledger", "swarmsafety", "swarmprotocol", "swarmsession", "swarmmenu", "swarmtraffic", "swarmcoordinator", "swarmestimator", "swarmworker", "remote", "main", "startupturtle", "downloader",
}

local componentGroups = {
    main = {
        "state", "navigation", "coordinate", "situations", "telemetry", "estimator", "localization", "ui", "settings",
        "request", "registry", "preview", "basedock", "setup", "torch", "actionlog", "inventory", "ore", "branch", "excavator",
        "nether", "farm", "chain", "chaineditor", "coordinatetask", "version", "remoteprotocol", "swarmgeometry", "stationregistry", "servicescheduler", "pickupledger", "swarmsafety", "swarmprotocol", "swarmsession", "swarmmenu", "swarmtraffic", "swarmcoordinator", "swarmestimator", "swarmworker", "remote", "main",
    },
    branch = { "state", "navigation", "basedock", "situations", "telemetry", "estimator", "localization", "ui", "request", "torch", "actionlog", "inventory", "ore", "swarmgeometry", "swarmsafety", "swarmsession", "pickupledger", "branch" },
    excavator = { "state", "navigation", "basedock", "situations", "telemetry", "estimator", "localization", "ui", "request", "torch", "actionlog", "inventory", "pickupledger", "excavator" },
    nether = { "state", "navigation", "basedock", "situations", "telemetry", "estimator", "localization", "ui", "request", "torch", "actionlog", "pickupledger", "nether" },
    coordinate = { "state", "navigation", "coordinate", "situations", "telemetry", "estimator", "localization", "ui", "request", "coordinatetask" },
    turtleinstall = {
        "state", "navigation", "coordinate", "situations", "telemetry", "estimator", "localization", "ui", "settings",
        "request", "registry", "preview", "basedock", "setup", "torch", "actionlog", "inventory", "ore", "branch", "excavator", "nether",
        "farm", "chain", "chaineditor", "coordinatetask", "version", "remoteprotocol", "swarmgeometry", "stationregistry", "servicescheduler", "pickupledger", "swarmsafety", "swarmprotocol", "swarmsession", "swarmmenu", "swarmtraffic", "swarmcoordinator", "swarmestimator", "swarmworker", "remote", "main", "startupturtle", "downloader",
    },
    monitorinstall = { "state", "settings", "localization", "version", "remoteprotocol", "swarmgeometry", "stationregistry", "servicescheduler", "swarmprotocol", "swarmtraffic", "swarmcoordinator", "swarmestimator", "monitor", "startupmonitor", "downloader" },
}

local function delTerm()
    if not DEBUG then sleep(2) end
    term.clear()
    term.setCursorPos(1, 1)
end

local function encodePath(path)
    return (path:gsub("[^/]+", function(part)
        return textutils.urlEncode(part)
    end))
end

local function githubUrl(path)
    return "https://api.github.com/repos/"
        .. textutils.urlEncode(GITHUB.owner)
        .. "/"
        .. textutils.urlEncode(GITHUB.repo)
        .. "/contents/"
        .. encodePath(path)
        .. "?ref="
        .. textutils.urlEncode(GITHUB.branch)
end

local function githubHeaders()
    local headers = {
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["User-Agent"] = "CC-Tweaked-Turtomata-Downloader",
    }
    if GITHUB.tokenFile then
        local token = developerToken()
        if not token then error("Tokenfajl hianyzik vagy ures.", 0) end
        headers["Authorization"] = "Bearer " .. token
    end
    return headers
end

local function header(headers, name)
    for key, value in pairs(headers or {}) do
        if type(key) == "string" and string.lower(key) == name then
            return tostring(value)
        end
    end
end

local function retryDelay(headers, attempts)
    local retryAfter = tonumber(header(headers, "retry-after") or "")
    if retryAfter and retryAfter > 0 then return math.ceil(retryAfter), "Retry-After" end

    if header(headers, "x-ratelimit-remaining") == "0" then
        local reset = tonumber(header(headers, "x-ratelimit-reset") or "")
        if reset and os.epoch then
            local remaining = math.ceil(reset - os.epoch("utc") / 1000) + 1
            if remaining > 0 then return remaining, "GitHub limit reset" end
        end
    end
    -- 403 jogosultsagi hiba is lehet; ilyenkor a felhasznalo megszakithatja.
    return math.min(60 * (2 ^ math.min(attempts - 1, 4)), 900), "varakozas"
end

local function waitForGithub(seconds, code, name, source)
    local remaining = seconds
    while remaining > 0 do
        delTerm()
        print("GitHub " .. tostring(code) .. " " .. name)
        print(tr("Ujra") .. ": " .. math.floor(remaining / 60) .. "m "
            .. (remaining % 60) .. "s (" .. tr(source) .. ")")
        print(tr("403: mas hiba is lehet."))
        print("")
        print(tr("R/Enter: proba most"))
        print(tr("Q/Esc: megszakit"))
        local timer = os.startTimer(1)
        while true do
            local event, value, _, y = os.pullEvent()
            if event == "key" then
                if value == keys.r or value == keys.enter then return "force" end
                if value == keys.q or value == keys.escape
                    or value == keys.backspace then return "cancel" end
            elseif event == "char" then
                if string.lower(value) == "r" then return "force" end
                if string.lower(value) == "q" then return "cancel" end
            elseif event == "mouse_click" then
                if y == 5 then return "force" end
                if y == 6 then return "cancel" end
            elseif event == "timer" and value == timer then
                remaining = remaining - 1
                break
            end
        end
    end
    return "retry"
end

local function downloadFromGithub(link, temporaryName)
    if not http then
        return false, "A HTTP API nincs engedelyezve a CC:Tweaked beallitasokban."
    end

    local attempts = 0
    while true do
        local response, errorMessage, failedResponse = http.get(
            githubUrl(link.githubPath), githubHeaders())
        local result = response or failedResponse
        if not result then return false, errorMessage or "Ismeretlen HTTP hiba." end

        local code, message = result.getResponseCode()
        local headers = result.getResponseHeaders and result.getResponseHeaders() or {}
        local content = response and response.readAll() or nil
        result.close()

        if code == 403 or code == 429 then
            attempts = attempts + 1
            local delay, source = retryDelay(headers, attempts)
            local choice = waitForGithub(delay, code, link.fileName, source)
            if choice == "cancel" then
                return false, "A frissites megszakitva.", true
            end
        else
            if code < 200 or code >= 300 then
                return false, "GitHub HTTP hiba: " .. tostring(code) .. " "
                    .. tostring(message or "")
            end
            if not content or content == "" then
                return false, "A GitHub ures fajlt adott vissza: " .. link.githubPath
            end
            local file = fs.open(temporaryName, "w")
            if not file then return false, "Nem tudom letrehozni: " .. temporaryName end
            file.write(content)
            file.close()
            return true
        end
    end
end

local function downloadFromPastebin(link, temporaryName)
    if not link.pastebinID or link.pastebinID == "" then
        return false, "Ehhez a fajlhoz nincs Pastebin ID beallitva."
    end
    local ok = shell.run("pastebin", "get", link.pastebinID, temporaryName)
    if not ok then return false, "A Pastebin letoltes sikertelen." end
    if not fs.exists(temporaryName) or fs.getSize(temporaryName) == 0 then
        return false, "A Pastebin ures fajlt adott vissza."
    end
    return true
end

local function installTemporaryFile(temporaryName, fileName)
    local backupName = fileName .. ".download_backup"
    if fs.exists(backupName) then fs.delete(backupName) end

    if fs.exists(fileName) then fs.move(fileName, backupName) end
    local installed, installError = pcall(fs.move, temporaryName, fileName)
    if not installed then
        if fs.exists(fileName) then fs.delete(fileName) end
        if fs.exists(backupName) then fs.move(backupName, fileName) end
        return false, "Nem sikerult telepiteni a fajlt: " .. tostring(installError)
    end

    if fs.exists(backupName) then fs.delete(backupName) end
    return true
end

local function downloadLink(link)
    local temporaryName = "." .. link.fileName .. ".download_tmp"
    if fs.exists(temporaryName) then fs.delete(temporaryName) end

    print("Letoltes: " .. link.fileName .. " (" .. DOWNLOAD_SOURCE .. ")")
    local downloaded, downloadError, cancelled
    if DOWNLOAD_SOURCE == "pastebin" then
        downloaded, downloadError = downloadFromPastebin(link, temporaryName)
    elseif DOWNLOAD_SOURCE == "github" then
        downloaded, downloadError, cancelled = downloadFromGithub(link, temporaryName)
    else
        return false, "Ismeretlen DOWNLOAD_SOURCE: " .. tostring(DOWNLOAD_SOURCE)
    end

    if not downloaded then
        if fs.exists(temporaryName) then fs.delete(temporaryName) end
        return false, downloadError, cancelled
    end

    if link.fileName == "downloader" then
        local chunk, syntaxError = loadfile(temporaryName)
        if not chunk then
            fs.delete(temporaryName)
            return false, "A letoltott downloader Lua-kodja hibas: "
                .. tostring(syntaxError)
        end
    end
    return installTemporaryFile(temporaryName, link.fileName)
end

local function downloadThat(name)
    local link = links[name]
    if not link then return false, "Ismeretlen komponens: " .. tostring(name) end

    local ok, errorMessage, cancelled = downloadLink(link)
    if ok then print("Letoltes sikeres: " .. link.fileName)
    else printError("Hiba a letoltesnel (" .. link.fileName .. "): " .. errorMessage) end
    return ok, cancelled
end

local function downloadAll()
    local allSuccessful = true
    for _, name in ipairs(downloadOrder) do
        local link = links[name]
        if DOWNLOAD_SOURCE == "pastebin" and (not link.pastebinID or link.pastebinID == "") then
            print("Kihagyva (nincs Pastebin ID): " .. link.fileName)
        else
            local ok, cancelled = downloadThat(name)
            if not ok then allSuccessful = false end
            if cancelled then return false end
        end
        if not DEBUG then sleep(1) end
    end
    return allSuccessful
end

local afterSelfUpdate = false
local function downloadGroup(names)
    local allSuccessful = true
    for _, name in ipairs(names) do
        -- Az elso szakasz mar telepitette az uj downloadert.
        if name ~= "downloader" or not afterSelfUpdate then
            local ok, cancelled = downloadThat(name)
            if not ok then allSuccessful = false end
            if cancelled then return false end
        end
        if not DEBUG then sleep(1) end
    end
    return allSuccessful
end

local args = { ... }
local fileMap = {
    all = "all",
    m = "main",
    main = "main",
    b = "branch",
    branch = "branch",
    d = "downloader",
    downloader = "downloader",
    e = "excavator",
    excavator = "excavator",
    t = "torch",
    torch = "torch",
    l = "actionlog",
    log = "actionlog",
    actionlog = "actionlog",
    i = "inventory",
    inv = "inventory",
    inventory = "inventory",
    o = "ore",
    ore = "ore",
    scanner = "ore",
    n = "nether",
    nether = "nether",
    builder = "nether",
    nav = "navigation",
    navigation = "navigation",
    coord = "coordinate",
    coordinate = "coordinate",
    ui = "ui",
    settings = "settings",
    state = "state",
    telemetry = "telemetry",
    estimator = "estimator",
    situations = "situations",
    turtleinstall = "turtleinstall",
    turtle = "turtleinstall",
    monitorinstall = "monitorinstall",
    monitor = "monitorinstall",
    observer = "monitorinstall",
}

local secretStep = 0
local function secretKey(value)
    local sequence = { keys.right, keys.right, keys.right, keys.up }
    if value == sequence[secretStep + 1] then
        secretStep = secretStep + 1
        if secretStep == #sequence then
            secretStep = 0
            return true
        end
    else
        secretStep = value == keys.right and 1 or 0
    end
    return false
end

local function developerMenu()
    local tokenReady = DOWNLOAD_SOURCE == "github" and developerToken() ~= nil
    local choices = {
        { label = "Tokenes GitHub frissites", mode = "token", enabled = tokenReady },
        { label = "Publikus GitHub frissites", mode = "public", enabled = true },
        { label = "Frissites megszakitasa", mode = "cancel", enabled = true },
    }
    local selected = tokenReady and GITHUB.tokenFile and 1 or 2
    while true do
        delTerm()
        print(tr("FEJLESZTOI MENU"))
        print(tokenReady and ".github_token: OK"
            or tr("Tokenfajl hianyzik vagy ures."))
        print("")
        for index, choice in ipairs(choices) do
            print((index == selected and "> " or "  ")
                .. tr(choice.label) .. (choice.enabled and "" or " [--]"))
        end
        print("")
        print(tr("Fel/le + Enter"))
        local event, value, _, y = os.pullEvent()
        if event == "key" then
            if value == keys.up then
                selected = selected == 3 and 2 or selected == 2 and 1 or 3
                if not choices[selected].enabled then selected = 3 end
            elseif value == keys.down then
                selected = selected == 1 and 2 or selected == 2 and 3 or 1
                if not choices[selected].enabled then selected = 2 end
            elseif value == keys.enter and choices[selected].enabled then
                return choices[selected].mode
            elseif value == keys.escape or value == keys.backspace then
                return "keep"
            end
        elseif event == "mouse_click" then
            local clicked = y - 3
            if choices[clicked] and choices[clicked].enabled then
                return choices[clicked].mode
            end
        end
    end
end

local function applyDeveloperMode(mode, saveChoice)
    if mode == "keep" then return end
    if mode == "cancel" then error("A frissites megszakitva.", 0) end
    if mode == "token" then
        if not developerToken() then error("Tokenfajl hianyzik vagy ures.", 0) end
    end
    if saveChoice ~= false then
        local file = fs.open(AUTH_MODE_FILE, "w")
        if not file then error("Nem mentheto a downloader modja.", 0) end
        file.write(mode)
        file.close()
    end
    GITHUB.tokenFile = mode == "token" and DEVELOPER_TOKEN_FILE or nil
end

local function developerWindow()
    if not os.startTimer or not os.pullEvent then return end
    delTerm()
    print("TURTOMATA " .. INSTALLER_VERSION)
    print(tr("Frissites indul..."))
    local timer = os.startTimer(5)
    while true do
        local event, value = os.pullEvent()
        if event == "timer" and value == timer then return end
        if event == "key" and secretKey(value) then
            applyDeveloperMode(developerMenu())
            return
        end
    end
end

local function installMenu()
    local items = {
        { label = tr("Turtle program telepitese"), value = "turtleinstall" },
        { label = tr("Megfigyelo telepitese"), value = "monitorinstall" },
    }
    local selected = 1
    while true do
        delTerm()
        print("TURTOMATA " .. INSTALLER_VERSION .. " " .. tr("TELEPITO"))
        print(tr("Forras") .. ": " .. DOWNLOAD_SOURCE
            .. " / " .. (GITHUB.tokenFile and "TOKEN" or "PUBLIC"))
        if fs.exists(UPDATE_RECEIPT) then
            local receipt = fs.open(UPDATE_RECEIPT, "r")
            if receipt then
                print((receipt.readAll() or ""):gsub("\n", " | "))
                receipt.close()
            end
        end
        print("")
        for index, item in ipairs(items) do
            print((index == selected and "> " or "  ") .. item.label)
        end
        print("")
        print(tr("Nyilak + ENTER, vagy kattintas"))
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            if secretKey(p1) then applyDeveloperMode(developerMenu())
            elseif p1 == keys.up then selected = math.max(1, selected - 1)
            elseif p1 == keys.down then selected = math.min(#items, selected + 1)
            elseif p1 == keys.enter then return items[selected].value end
        elseif event == "mouse_click" and p3 >= 4 and p3 < 4 + #items then
            selected = p3 - 3
            return items[selected].value
        end
    end
end

delTerm()
print("TURTOMATA " .. INSTALLER_VERSION .. " " .. tr("komponensek"))
print(tr("Forras") .. ": " .. DOWNLOAD_SOURCE)
print("")

local requested = args[1] and fileMap[string.lower(args[1])] or nil
afterSelfUpdate = args[2] == "--after-self-update"
local directDeveloperMenu = args[2] == "--developer-menu"
local inheritedToken = afterSelfUpdate and args[3] == "--developer-token"
if (#args > 1 and not afterSelfUpdate and not directDeveloperMenu)
    or #args > (inheritedToken and 3 or afterSelfUpdate and 2
        or directDeveloperMenu and 2 or 1)
    or (args[3] and not inheritedToken) or (args[1] and not requested) then
    error("Hasznalat: downloader [turtle|monitor|all|main|branch|excavator|nether|navigation|coordinate|ui|settings|downloader]", 0)
end
if inheritedToken then applyDeveloperMode("token", false)
elseif directDeveloperMenu then applyDeveloperMode(developerMenu())
elseif not afterSelfUpdate and args[1] then developerWindow()
elseif not args[1] then requested = installMenu() end

if not afterSelfUpdate then
    -- A letoltott Lua program nem valtja le a mar futo chunkot, ezert
    -- az uj fajl telepitese utan uj shell.run kell a friss fajllistahoz.
    if not downloadThat("downloader") then
        error("A downloader onfrissitese sikertelen; a tobbi fajl valtozatlan.", 0)
    end
    print("Uj downloader indul a friss komponenslistaval...")
    local continued
    if GITHUB.tokenFile then
        continued = shell.run("downloader", requested,
            "--after-self-update", "--developer-token")
    else
        continued = shell.run("downloader", requested, "--after-self-update")
    end
    if not continued then
        error("A friss downloader nem tudta befejezni a telepitest.", 0)
    end
    return
end

local successful
if requested == "downloader" then
    print("A downloader frissitve.")
    successful = true
elseif requested == "all" then
    successful = downloadGroup(componentGroups.turtleinstall)
    if successful then print("A turtle program telepitve/frissitve.") end
elseif componentGroups[requested] then
    successful = downloadGroup(componentGroups[requested])
    if successful then
        if requested == "turtleinstall" then print("Turtle telepites kesz. A startup.lua a main programot inditja.")
        elseif requested == "monitorinstall" then print("Megfigyelo telepites kesz. A startup.lua a monitort inditja.")
        else print("A komponenscsomag frissitve.") end
    end
else
    successful = downloadThat(requested)
end
if not successful then error("A komponenscsomag frissitese nem teljes.", 0) end
local installedVersion = INSTALLER_VERSION
if fs.exists("version.lua") and loadfile then
    local versionChunk = loadfile("version.lua")
    if versionChunk then
        local ok, value = pcall(versionChunk)
        if ok and type(value) == "table" and type(value.label) == "string" then
            installedVersion = value.label
        end
    end
end
local epoch = os.epoch and os.epoch("utc") or os.time() * 1000
local timestamp = os.date("!%Y-%m-%d %H:%M:%S", math.floor(epoch / 1000)) .. " UTC"
local receipt = fs.open(UPDATE_RECEIPT, "w")
if receipt then
    receipt.write("Turtomata " .. installedVersion .. "\n"
        .. "Downloader " .. INSTALLER_VERSION .. "\n"
        .. timestamp .. "\n" .. tostring(requested))
    receipt.close()
end
print("")
print("Turtomata " .. installedVersion .. " | Downloader " .. INSTALLER_VERSION)
print(tr("Frissitve") .. ": " .. timestamp)
print(tr("ENTER = lattamozas"))
if type(read) == "function" then read() end
