-- Egyszer hasznalatos, tokennel vedett atadas a kozponti main es a feladatok kozott.

local stateStore = require("state_store")
local requests = {}
local FILE = ".turtomata_job_request.txt"

local function token()
    local epoch = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
    return tostring(epoch) .. "-" .. tostring(math.random(100000, 999999))
end

function requests.create(task, action, config)
    local value = {
        version = 1,
        token = token(),
        task = task,
        action = action or "new",
        config = config or {},
    }
    local ok, reason = stateStore.write(FILE, value)
    if not ok then return nil, reason end
    return value.token
end

function requests.consume(task, args)
    args = args or {}
    if args[1] ~= "--request" or not args[2] then return nil end
    local value = stateStore.read(FILE)
    if type(value) ~= "table" or value.version ~= 1
        or value.token ~= args[2] or value.task ~= task then
        return nil, "Hibas vagy lejart kozponti inditasi keres."
    end
    stateStore.remove(FILE)
    return value
end

return requests
