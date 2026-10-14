-- CC:Tweaked programfrissito Pastebin es GitHub tamogatassal.

local DEBUG = true

-- Itt valaszd ki a letoltesi forrast: "pastebin" vagy "github".
local DOWNLOAD_SOURCE = "github"

local GITHUB = {
    owner = "Forcas76",
    repo = "CCTurtle",
    branch = "main",

    -- Publikus reponal maradjon ures. Privat reponal ide kerulhet a token.
    -- Fine-grained token eseten eleg a Contents: Read-only jogosultsag.
    token = "",

    -- Javasolt: a token inkabb ebben a kulon fajlban legyen a turtle gepen.
    -- Igy a downloader sajat frissitese nem irja felul es nem kerul a repoba.
    tokenFile = ".github_token",
}

-- fileName: a turtle gepen letrehozo fajl neve.
-- githubPath: a fajl helye a GitHub repoban.
local links = {
    main = {
        pastebinID = "YAdymjRk",
        githubPath = "branch_miner.lua",
        fileName = "main",
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
}

local downloadOrder = {
    "main", "excavator", "torch", "actionlog", "inventory", "ore", "downloader",
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
        ["User-Agent"] = "CC-Tweaked-CCTurtle-Downloader",
    }
    local token = GITHUB.token
    if GITHUB.tokenFile and fs.exists(GITHUB.tokenFile) then
        local tokenFile = fs.open(GITHUB.tokenFile, "r")
        if tokenFile then
            token = tokenFile.readAll() or ""
            tokenFile.close()
            token = token:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    if token ~= "" then
        headers["Authorization"] = "Bearer " .. token
    end
    return headers
end

local function responseError(errorMessage, failedResponse)
    if not failedResponse then return errorMessage or "Ismeretlen HTTP hiba." end

    local code, message = failedResponse.getResponseCode()
    failedResponse.close()
    return "GitHub HTTP hiba: " .. tostring(code) .. " " .. tostring(message or "")
end

local function downloadFromGithub(link, temporaryName)
    if not http then
        return false, "A HTTP API nincs engedelyezve a CC:Tweaked beallitasokban."
    end

    local response, errorMessage, failedResponse = http.get(
        githubUrl(link.githubPath),
        githubHeaders()
    )
    if not response then
        return false, responseError(errorMessage, failedResponse)
    end

    local code, message = response.getResponseCode()
    local content = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return false, "GitHub HTTP hiba: " .. tostring(code) .. " " .. tostring(message or "")
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
    local downloaded, downloadError
    if DOWNLOAD_SOURCE == "pastebin" then
        downloaded, downloadError = downloadFromPastebin(link, temporaryName)
    elseif DOWNLOAD_SOURCE == "github" then
        downloaded, downloadError = downloadFromGithub(link, temporaryName)
    else
        return false, "Ismeretlen DOWNLOAD_SOURCE: " .. tostring(DOWNLOAD_SOURCE)
    end

    if not downloaded then
        if fs.exists(temporaryName) then fs.delete(temporaryName) end
        return false, downloadError
    end

    return installTemporaryFile(temporaryName, link.fileName)
end

local function downloadThat(name)
    local link = links[name]
    if not link then return false, "Ismeretlen komponens: " .. tostring(name) end

    local ok, errorMessage = downloadLink(link)
    if ok then print("Letoltes sikeres: " .. link.fileName)
    else printError("Hiba a letoltesnel (" .. link.fileName .. "): " .. errorMessage) end
    return ok
end

local function downloadAll()
    local allSuccessful = true
    for _, name in ipairs(downloadOrder) do
        local link = links[name]
        if DOWNLOAD_SOURCE == "pastebin" and (not link.pastebinID or link.pastebinID == "") then
            print("Kihagyva (nincs Pastebin ID): " .. link.fileName)
        elseif not downloadThat(name) then
            allSuccessful = false
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
}

delTerm()
print("Komponensek frissitese")
print("Forras: " .. DOWNLOAD_SOURCE)
print("")

local requested = args[1] and fileMap[string.lower(args[1])] or "all"
if #args > 1 or not requested then
    printError("Hasznalat: downloader [all|main|excavator|torch|actionlog|inventory|ore|downloader]")
elseif requested == "all" then
    if downloadAll() then print("Minden komponens frissitve.")
    else printError("Legalabb egy komponens frissitese sikertelen.") end
else
    downloadThat(requested)
end
