-- KISERLETI kezzel inicializalt vilagkoordinatas navigacio.

local Navigation = require("navigation")
local coordinate = {}

coordinate.WORLD_VECTORS = {
    [0] = { x = 0, z = -1 }, -- Eszak
    [1] = { x = 1, z = 0 },  -- Kelet
    [2] = { x = 0, z = 1 },  -- Del
    [3] = { x = -1, z = 0 }, -- Nyugat
}

coordinate.FACING_NAMES = {
    [0] = "Eszak (-Z)",
    [1] = "Kelet (+X)",
    [2] = "Del (+Z)",
    [3] = "Nyugat (-X)",
}

local function copyTarget(value)
    return {
        x = tonumber(value.x), y = tonumber(value.y), z = tonumber(value.z),
        heading = value.heading ~= nil and tonumber(value.heading) or nil,
    }
end

function coordinate.validatePose(value)
    if type(value) ~= "table" then return false, "Hianyzik a koordinata." end
    for _, key in ipairs({ "x", "y", "z", "heading" }) do
        local number = tonumber(value[key])
        if not number or number ~= math.floor(number) then return false, "Hibas " .. key .. " ertek." end
    end
    if value.heading < 0 or value.heading > 3 then return false, "A facing 0 es 3 kozott lehet." end
    return true
end

function coordinate.validateTarget(value)
    if type(value) ~= "table" then return false, "Hianyzik a celkoordinata." end
    for _, key in ipairs({ "x", "y", "z" }) do
        local number = tonumber(value[key])
        if not number or number ~= math.floor(number) then return false, "Hibas cel " .. key .. "." end
    end
    if value.heading ~= nil and (value.heading < 0 or value.heading > 3) then
        return false, "Hibas cel-facing."
    end
    return true
end

function coordinate.distance(startPose, target)
    return math.abs(startPose.x - target.x)
        + math.abs(startPose.y - target.y)
        + math.abs(startPose.z - target.z)
end

function coordinate.plan(startPose, target, order)
    local valid, reason = coordinate.validatePose(startPose)
    if not valid then return nil, reason end
    valid, reason = coordinate.validateTarget(target)
    if not valid then return nil, reason end
    return {
        start = copyTarget(startPose),
        target = copyTarget(target),
        order = order or { "y", "x", "z" },
        minimumMoves = coordinate.distance(startPose, target),
    }
end

function coordinate.createNavigator(options)
    options = options or {}
    options.vectors = coordinate.WORLD_VECTORS
    local nav = Navigation.new(options)
    if not nav.state.anchors.home then nav:setAnchor("home") end
    return nav
end

function coordinate.execute(nav, plan, options)
    if not nav or not plan then return { ok = false, code = "bad_plan", reason = "Hianyzik a navigacios terv." } end
    return nav:goTo(plan.target, plan.order, options)
end

return coordinate
