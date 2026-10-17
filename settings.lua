-- Kozponti, tartos beallitasok.

local stateStore = require("state_store")
local settings = {}

local FILE = "settings.txt"
local CURRENT_VERSION = 1

local DEFAULTS = {
    version = CURRENT_VERSION,
    general = {
        fuelReserve = 8,
        finalEnter = true,
        language = "hu",
    },
    navigation = {
        defaultActionSeconds = 0.8,
        coordinateAxisOrder = { "y", "x", "z" },
        coordinateMode = "open",
    },
    safety = {
        retryLimit = 20,
        entityRetryLimit = 6,
        sealWater = true,
        sealLava = true,
        lavaFailureFatal = true,
        torchFailureFatal = false,
        sealBlock = "minecraft:cobblestone",
    },
    inventory = {
        experimental = false,
    },
    torches = {
        enabledByDefault = false,
        interval = 8,
        placement = "above",
    },
    ores = {
        enabledByDefault = false,
        maxDepth = 4,
        maxBlocks = 16,
    },
    display = {
        refreshMs = 250,
        eventRows = 2,
        useColor = true,
    },
}

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function normalize(value)
    local result = stateStore.clone(DEFAULTS)
    if type(value) == "table" then merge(result, value) end
    result.version = CURRENT_VERSION
    return result
end

function settings.defaults()
    return stateStore.clone(DEFAULTS)
end

function settings.load(path)
    local loaded, status = stateStore.read(path or FILE, DEFAULTS)
    return normalize(loaded), status
end

function settings.save(value, path)
    return stateStore.write(path or FILE, normalize(value))
end

function settings.reset(path)
    local value = settings.defaults()
    local ok, reason = settings.save(value, path)
    return ok, reason, value
end

function settings.get(value, dottedPath, fallback)
    local cursor = value
    for part in string.gmatch(dottedPath or "", "[^.]+") do
        if type(cursor) ~= "table" then return fallback end
        cursor = cursor[part]
    end
    if cursor == nil then return fallback end
    return cursor
end

function settings.set(value, dottedPath, newValue)
    local parts = {}
    for part in string.gmatch(dottedPath or "", "[^.]+") do parts[#parts + 1] = part end
    if #parts == 0 then return false, "Ures beallitasi utvonal." end
    local cursor = value
    for index = 1, #parts - 1 do
        local part = parts[index]
        if type(cursor[part]) ~= "table" then cursor[part] = {} end
        cursor = cursor[part]
    end
    cursor[parts[#parts]] = newValue
    return true
end

return settings
