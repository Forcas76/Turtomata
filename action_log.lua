-- Egysoros inditasi naplo CC:Tweaked programokhoz.

local logger = {}
local LOG_FILE = "action_log.txt"

local function timestamp()
    if os.epoch and os.date then
        local okEpoch, epoch = pcall(os.epoch, "local")
        if okEpoch and type(epoch) == "number" then
            local okDate, formatted = pcall(
                os.date,
                "%Y-%m-%d %H:%M:%S",
                math.floor(epoch / 1000)
            )
            if okDate and type(formatted) == "string" then return formatted end
        end
    end

    local day = os.day and os.day() or 0
    local time = os.time and os.time() or 0
    local formattedTime = textutils.formatTime and textutils.formatTime(time, true)
        or tostring(time)
    return "MC nap " .. tostring(day) .. " " .. formattedTime
end

local function fuelText()
    local fuel = turtle.getFuelLevel()
    return fuel == "unlimited" and "korlatlan" or tostring(fuel)
end

function logger.log(action)
    action = tostring(action or "ismeretlen")
    action = action:gsub("[\r\n]+", " ")
    local file = fs.open(LOG_FILE, "a")
    if not file then return false, "Nem irhato az action_log.txt." end
    file.writeLine(string.format("[%s] %s | fuel=%s", timestamp(), action, fuelText()))
    file.close()
    return true
end

return logger
