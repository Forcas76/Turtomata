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
    local function readOne(name)
        if not fs.exists(name) then return nil, "missing" end
        local handle = fs.open(name, "r")
        if not handle then return nil, "unreadable" end
        local content = handle.readAll()
        handle.close()
        return decode(content)
    end
    local value, reason = readOne(path)
    if value then return value end
    local directory = fs.getDir(path)
    local backup = "." .. fs.getName(path) .. ".bak"
    if directory ~= "" then backup = fs.combine(directory, backup) end
    local recovered = readOne(backup)
    if recovered then return recovered, "recovered_backup" end
    return clone(fallback), reason
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

    local primaryValid = false
    if fs.exists(path) then
        local old = fs.open(path, "r")
        if old then
            primaryValid = decode(old.readAll()) ~= nil
            old.close()
        end
    end
    if primaryValid then
        if fs.exists(backup) then fs.delete(backup) end
        fs.move(path, backup)
    elseif fs.exists(path) then
        -- Serult elsodleges peldany nem irhatja felul a jo tartalekot.
        fs.delete(path)
    end
    local moved, reason = pcall(fs.move, temporary, path)
    if not moved then
        if fs.exists(temporary) then fs.delete(temporary) end
        if fs.exists(backup) and not fs.exists(path) then fs.move(backup, path) end
        return false, "Nem cserelheto az allapotfajl: " .. tostring(reason)
    end
    -- A legutobbi ervenyes peldanyt megtartjuk egy kovetkezo olvasashoz.
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
