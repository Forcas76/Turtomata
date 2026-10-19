-- A bázis mögötti leadóláda korlátos, mentett felismerése.
local dock = {}

local function chestAhead()
    local ok, data = turtle.inspect()
    return ok and type(data) == "table"
        and type(data.name) == "string"
        and data.name:find("chest", 1, true) ~= nil
end

function dock.chestOnReturn(nav)
    -- Hazateres kozben ladat soha nem asunk ki, meg akkor sem, ha a
    -- mentes nagyobb eltorest mutat. A seek kesobb korlatozza a korrekciot.
    if nav:getPose().y ~= 0 then return false end
    local faced = nav:face(2)
    return faced.ok and chestAhead()
end

function dock.seek(nav, maximum)
    maximum = maximum or 2
    if nav:distanceHome() > maximum or nav:getPose().y ~= 0 then
        return false, "A mentett pozicio tul messze van a bazistol."
    end
    local faced = nav:face(2)
    if not faced.ok then return false, faced.reason end
    for attempt = 0, maximum do
        if chestAhead() then
            local corrected = attempt > 0 or nav:distanceHome() > 0
            local home = nav.state.anchors.home and nav.state.anchors.home.pose
                or { x = 0, y = 0, z = 0, heading = 0 }
            nav.state.pose = {
                x = home.x, y = home.y, z = home.z, heading = 2,
            }
            nav.state.path = {}
            nav.state.pending = nil
            nav:_checkpoint("dock_verified")
            return true, nil, corrected
        end
        if attempt == maximum then break end
        if turtle.detect() then
            return false, "Akadaly van a leado lada fele."
        end
        local moved = nav:step({ kind = "h", heading = 2 }, { retryLimit = 1 })
        if not moved.ok then return false, moved.reason end
    end
    return false, "Ket lepessel sem talalom a leado ladat."
end

return dock
