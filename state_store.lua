-- Kozos, atomi JSON allapotkezelo CC:Tweaked programokhoz.

local store = {}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
    return result
end

local function decode(content)
    local ok, value = pcall(textutils.unserializeJSON, content)
    if ok and type(value) == "table" then return value end
    return nil, "A fajl nem ervenyes JSON objektum."
end

function store.read(path, fallback)
    if not fs.exists(path) then return clone(fallback), "missing" end
    local handle = fs.open(path, "r")
    if not handle then return clone(fallback), "unreadable" end
    local content = handle.readAll()
    handle.close()
    local value, reason = decode(content)
    if not value then return clone(fallback), reason end
    return value
end

function store.write(path, value)
    local temporary = "." .. fs.getName(path) .. ".tmp"
    local backup = "." .. fs.getName(path) .. ".bak"
    local directory = fs.getDir(path)
    if directory ~= "" then
        temporary = fs.combine(directory, temporary)
        backup = fs.combine(directory, backup)
    end

    local ok, encoded = pcall(textutils.serializeJSON, value)
    if not ok or type(encoded) ~= "string" then
        return false, "Az allapot nem alakithato JSON-na."
    end

    local handle = fs.open(temporary, "w")
    if not handle then return false, "Nem irhato az ideiglenes allapotfajl." end
    handle.write(encoded)
    handle.close()

    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists(path) then fs.move(path, backup) end
    local moved, reason = pcall(fs.move, temporary, path)
    if not moved then
        if fs.exists(temporary) then fs.delete(temporary) end
        if fs.exists(backup) and not fs.exists(path) then fs.move(backup, path) end
        return false, "Nem cserelheto az allapotfajl: " .. tostring(reason)
    end
    if fs.exists(backup) then fs.delete(backup) end
    return true
end

function store.remove(path)
    if not fs.exists(path) then return true end
    local ok, reason = pcall(fs.delete, path)
    if not ok then return false, tostring(reason) end
    return true
end

function store.clone(value)
    return clone(value)
end

return store
