-- A bázis mögötti leadóláda korlátos, mentett felismerése.
local dock = {}
local Store = require("state_store")
local DOCK_FILE = "base_dock_state.txt"

local function learnedName()
    if not fs or not fs.exists or not fs.getDir then return nil end
    local saved = Store.read(DOCK_FILE)
    return type(saved) == "table" and type(saved.name) == "string"
        and saved.name or nil
end

local function chestAhead()
    local ok, data = turtle.inspect()
    local expected = learnedName()
    return ok and type(data) == "table"
        and type(data.name) == "string"
        and (expected and data.name == expected
            or not expected and data.name:find("chest", 1, true) ~= nil)
end

function dock.isDepositAhead()
    return chestAhead()
end

function dock.learnAtBase(nav)
    local pose = nav:getPose()
    if pose.x ~= 0 or pose.y ~= 0 or pose.z ~= 0 or pose.heading ~= 2 then
        return false, "Ladat csak a bazison, fele fordulva lehet megtanulni."
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" or type(data.name) ~= "string" then
        return false, "Nincs ellenorizheto blokk a leado lada helyen."
    end
    local expected = learnedName()
    if expected then
        if data.name ~= expected then
            return false, "A leado lada tipusa megvaltozott. Kezi ellenorzes kell."
        end
        return true
    end
    if not fs or not fs.open then return false, "Nem mentheto a leado lada tipusa." end
    return Store.write(DOCK_FILE, { version = 1, name = data.name })
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
