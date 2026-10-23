-- Turtle- es bazisblokkokat nem bontunk ki automatikus akadalykezeleskor.
local safety = {}

local function protectedName(name)
    if type(name) ~= "string" then return false end
    local basename = (name:match("^[^:]+:(.+)$") or name):lower()
    return basename:find("turtle", 1, true) ~= nil
        or basename:find("chest", 1, true) ~= nil
end

function safety.inspect(direction)
    local inspect = direction == "up" and turtle.inspectUp
        or direction == "down" and turtle.inspectDown or turtle.inspect
    local ok, data = inspect()
    if not ok or type(data) ~= "table" then return false end
    return protectedName(data.name), data.name
end

function safety.mayDig(direction)
    local protected, name = safety.inspect(direction)
    if protected then
        return false, "Vedett blokk az utban: " .. tostring(name)
    end
    return true
end

return safety
