-- Az uj downloader uj fajllistaja mar ugyanabban a frissitesben ervenyesul.
local oldFs, oldHttp, oldShell = fs, http, shell
local oldTerm, oldTextutils = term, textutils
local oldPrint, oldPrintError = print, printError
local oldLoadfile = loadfile
local oldLocalization = package.loaded.localization

local latest = DOWNLOADER_SOURCE:gsub("    main = {", [[
    newfeature = {
        pastebinID = "", githubPath = "new_feature.lua",
        fileName = "new_feature.lua",
    },
    main = {]], 1)
latest = latest:gsub('    turtleinstall = {\n        "state",',
    '    turtleinstall = {\n        "newfeature", "state",', 1)
assert(latest ~= DOWNLOADER_SOURCE)
assert(latest:find('"newfeature", "state"', 1, true))

local files, requests, failFeature, invalidSelf
local function reset()
    files = { downloader = DOWNLOADER_SOURCE,
        [".github_token"] = "stale-private-token" }
    requests = {}
    failFeature = false
    invalidSelf = false
end
reset()
fs = {
    exists = function(path) return files[path] ~= nil end,
    delete = function(path) files[path] = nil end,
    move = function(from, to)
        assert(files[from] ~= nil and files[to] == nil)
        files[to], files[from] = files[from], nil
    end,
    open = function(path, mode)
        if mode == "r" then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end,
                close = function() end }
        end
        return { write = function(value) files[path] = value end,
            close = function() end }
    end,
}
http = {
    get = function(url, headers)
        assert(headers["Authorization"] == nil,
            "Publikus GitHub-letolteshez nem szabad tokent kuldeni.")
        local path = url:match("/contents/([^?]+)")
        requests[#requests + 1] = path
        if failFeature and path == "new_feature.lua" then
            return nil, "simulated failure"
        end
        local body = path == "downloader.lua"
            and (invalidSelf and "not valid lua !!!" or latest)
            or "return true"
        return {
            getResponseCode = function() return 200, "OK" end,
            readAll = function() return body end,
            close = function() end,
        }
    end,
}
term = { clear = function() end, setCursorPos = function() end }
textutils = { urlEncode = function(value) return value end }
loadfile = function(path)
    if not files[path] then return nil, "missing" end
    return load(files[path], path)
end
print, printError = function() end, function() end
package.loaded.localization = { text = function(value) return value end }
shell = {
    run = function(name, ...)
        assert(name == "downloader")
        local chunk = assert(load(files.downloader, "downloader"))
        local ok = pcall(chunk, ...)
        return ok
    end,
}

local oldChunk = assert(load(DOWNLOADER_SOURCE, "old_downloader"))
assert(pcall(oldChunk, "turtle"))
assert(requests[1] == "downloader.lua")
assert(requests[2] == "new_feature.lua")
assert(files["new_feature.lua"] == "return true")
local selfFetches = 0
for _, path in ipairs(requests) do
    if path == "downloader.lua" then selfFetches = selfFetches + 1 end
end
assert(selfFetches == 1, "Az uj folyamat ne toltse le megegyszer onmagat.")

reset()
failFeature = true
assert(not pcall(oldChunk, "turtle"),
    "Reszleges telepites nem jelezhet sikert a foprogramnak.")

reset()
invalidSelf = true
assert(not pcall(oldChunk, "turtle"),
    "Hibas downloader nem telepulhet.")
assert(files.downloader == DOWNLOADER_SOURCE)

local baseGet = http.get
local oldKeys = keys
local oldStartTimer, oldPullEvent, oldEpoch = os.startTimer, os.pullEvent, os.epoch
keys = { r = 1, q = 2, enter = 3, escape = 4, backspace = 5,
    right = 6, left = 7, up = 8, down = 9 }
local timerId, timers, eventMode, timerSeconds = 0, 0, "automatic", 0
os.startTimer = function(seconds)
    timerId = timerId + 1
    timerSeconds = seconds
    if seconds == 1 then timers = timers + 1 end
    return timerId
end
os.pullEvent = function()
    if eventMode == "force" and timerSeconds == 1 then
        eventMode = "automatic"
        return "key", keys.r
    end
    if eventMode == "cancel" and timerSeconds == 1 then
        return "key", keys.q
    end
    return "timer", timerId
end
local function forbidden(headers)
    return {
        getResponseCode = function() return 403, "Forbidden" end,
        getResponseHeaders = function() return headers end,
        close = function() end,
    }
end

reset()
local failures = 0
http.get = function(url, headers)
    if failures == 0 then
        failures = 1
        requests[#requests + 1] = "downloader.lua"
        return nil, "rate limited", forbidden({ ["Retry-After"] = "2" })
    end
    return baseGet(url, headers)
end
assert(pcall(oldChunk, "downloader"))
assert(timers == 2 and #requests == 2,
    "403 utan a Retry-After idejeig varjon, majd folytassa.")

reset()
failures, timers, eventMode = 0, 0, "automatic"
os.epoch = function() return 1000000 end
http.get = function(url, headers)
    if failures == 0 then
        failures = 1
        requests[#requests + 1] = "downloader.lua"
        local response = forbidden({ ["X-RateLimit-Remaining"] = "0",
            ["X-RateLimit-Reset"] = "1003" })
        response.readAll = function() return "rate limited" end
        return response
    end
    return baseGet(url, headers)
end
assert(pcall(oldChunk, "downloader"))
assert(timers == 4 and #requests == 2,
    "A GitHub reset ido az elso sikertelen valaszbol is ervenyesuljon.")
os.epoch = oldEpoch

reset()
failures, timers, eventMode = 0, 0, "force"
http.get = function(url, headers)
    if failures == 0 then
        failures = 1
        requests[#requests + 1] = "downloader.lua"
        return nil, "rate limited", forbidden({ ["Retry-After"] = "120" })
    end
    return baseGet(url, headers)
end
assert(pcall(oldChunk, "downloader"))
assert(#requests == 2 and timers == 1,
    "R-rel a varakozas kozben azonnal probaljon ujra.")

reset()
failures, timers, eventMode = 0, 0, "cancel"
http.get = function(url)
    requests[#requests + 1] = url:match("/contents/([^?]+)")
    return nil, "rate limited", forbidden({})
end
assert(not pcall(oldChunk, "turtle"), "Q-val megszakithato a frissites.")
assert(#requests == 1 and files.downloader == DOWNLOADER_SOURCE,
    "Megszakitas utan ne telepitsen es ne kerjen tovabbi fajlokat.")

reset()
eventMode = "cancel"
http.get = function(url, headers)
    local path = url:match("/contents/([^?]+)")
    if path == "new_feature.lua" then
        requests[#requests + 1] = path
        return nil, "rate limited", forbidden({ ["Retry-After"] = "30" })
    end
    return baseGet(url, headers)
end
assert(not pcall(oldChunk, "turtle"),
    "Az onfrissites utani varakozas is megszakithato.")
assert(#requests == 2 and requests[1] == "downloader.lua"
    and requests[2] == "new_feature.lua",
    "Megszakitas utan a csomag tobbi fajlja nem toltheto le.")

local function authenticatedGet(url, headers)
    assert(headers.Authorization == "Bearer stale-private-token",
        "A fejlesztoi mod mindket letoltesi szakaszban hasznalja a tokent.")
    local path = url:match("/contents/([^?]+)")
    requests[#requests + 1] = path
    local body = path == "downloader.lua" and latest or "return true"
    return {
        getResponseCode = function() return 200, "OK" end,
        readAll = function() return body end,
        close = function() end,
    }
end
local queuedEvents = {}
local function queueKeys(...)
    queuedEvents = {}
    for _, code in ipairs({ ... }) do
        queuedEvents[#queuedEvents + 1] = { "key", code }
    end
end
os.pullEvent = function()
    local event = table.remove(queuedEvents, 1)
    if event then return event[1], event[2] end
    return "timer", timerId
end

reset()
http.get = authenticatedGet
queueKeys(keys.up, keys.enter)
assert(pcall(oldChunk, "turtle", "--developer-menu"),
    "A foprogram kozvetlenul meg tudja nyitni a fejlesztoi menut.")
assert(requests[1] == "downloader.lua" and requests[2] == "new_feature.lua")
assert(files[".downloader_auth_mode"] == "token",
    "A kozvetlenul valasztott tokenes mod legyen tartos.")

reset()
http.get = authenticatedGet
queueKeys(keys.right, keys.right, keys.right, keys.up,
    keys.up, keys.enter)
local tokenUpdateOk, tokenUpdateReason = pcall(oldChunk, "turtle")
assert(tokenUpdateOk,
    "Programbol inditott frissitesnel elerheto a fejlesztoi menu: "
        .. tostring(tokenUpdateReason))
assert(requests[1] == "downloader.lua" and requests[2] == "new_feature.lua")
assert(files[".downloader_auth_mode"] == "token",
    "A tokenes valasztas a gepen maradjon elmentve.")

requests = {}
queueKeys()
assert(pcall(oldChunk, "downloader"),
    "A kovetkezo programfrissites automatikusan a mentett tokent hasznalja.")
assert(#requests == 1 and files[".downloader_auth_mode"] == "token")

requests = {}
queueKeys(keys.right, keys.right, keys.right, keys.up, keys.escape)
assert(pcall(oldChunk, "downloader"),
    "A titkos menubol kilepes ne irja felul a mentett modot.")
assert(#requests == 1 and files[".downloader_auth_mode"] == "token")

reset()
http.get = authenticatedGet
queueKeys(keys.right, keys.right, keys.right, keys.up,
    keys.up, keys.enter, keys.enter)
assert(pcall(oldChunk), "Kozvetlen inditasnal is mukodjon a titkos menu.")
assert(requests[1] == "downloader.lua" and requests[2] == "new_feature.lua")
assert(files[".downloader_auth_mode"] == "token")

http.get = baseGet
requests = {}
queueKeys(keys.right, keys.right, keys.right, keys.up,
    keys.down, keys.enter, keys.enter)
assert(pcall(oldChunk), "A publikus mod visszakapcsolhato.")
assert(files[".downloader_auth_mode"] == "public"
    and #requests > 0, "A publikus valasztas is maradjon meg.")

requests = {}
queueKeys()
assert(pcall(oldChunk, "downloader"),
    "Az elmentett publikus mod token nelkul induljon legkozelebb is.")

reset()
files[".github_token"] = nil
http.get = baseGet
queueKeys(keys.right, keys.right, keys.right, keys.up, keys.enter)
assert(pcall(oldChunk, "downloader"),
    "Token nelkul a fejlesztoi menu publikus frissitese maradjon elerheto.")
assert(not pcall(oldChunk, "downloader", "--after-self-update",
    "--developer-token"),
    "Az orokolt tokenes mod nem futhat hianyzo tokenfajllal.")

reset()
files[".downloader_auth_mode"] = "token"
files[".github_token"] = nil
requests = {}
queueKeys()
assert(not pcall(oldChunk, "downloader"),
    "A mentett tokenes mod token nelkul ne valtson csendben publikusra.")
assert(#requests == 0)

reset()
http.get = authenticatedGet
queueKeys(keys.right, keys.right, keys.right, keys.up,
    keys.down, keys.enter)
assert(not pcall(oldChunk, "turtle"),
    "A fejlesztoi menubol a frissites megszakithato.")
assert(#requests == 0, "Megszakitaskor semmi nem toltheto le.")

http.get = baseGet
keys = oldKeys
os.startTimer, os.pullEvent, os.epoch = oldStartTimer, oldPullEvent, oldEpoch

fs, http, shell = oldFs, oldHttp, oldShell
term, textutils = oldTerm, oldTextutils
print, printError = oldPrint, oldPrintError
loadfile = oldLoadfile
package.loaded.localization = oldLocalization
DOWNLOADER_SOURCE = nil
return true
