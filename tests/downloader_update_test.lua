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

fs, http, shell = oldFs, oldHttp, oldShell
term, textutils = oldTerm, oldTextutils
print, printError = oldPrint, oldPrintError
loadfile = oldLoadfile
package.loaded.localization = oldLocalization
DOWNLOADER_SOURCE = nil
return true
