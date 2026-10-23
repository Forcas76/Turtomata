local oldFs, oldTextutils, oldTurtle = fs, textutils, turtle
local oldDock = package.loaded.base_dock
local files, objects, nextId = {}, {}, 0
fs = {
    exists = function(path) return files[path] ~= nil end,
    getName = function(path) return path:match("[^/]+$") end,
    getDir = function() return "" end,
    combine = function(a, b) return a .. "/" .. b end,
    delete = function(path) files[path] = nil end,
    move = function(a, b) files[b], files[a] = files[a], nil end,
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
textutils = {
    serializeJSON = function(value)
        nextId = nextId + 1
        objects[tostring(nextId)] = value
        return tostring(nextId)
    end,
    unserializeJSON = function(value) return objects[value] end,
}
local physical, heading = 0, 2
turtle = {
    inspect = function()
        if physical == 0 and heading == 2 then
            return true, { name = "storage:oak_cabinet" }
        end
        return false, "No block"
    end,
    detect = function() return false end,
    forward = function() physical = physical - 1 return true end,
    turnRight = function() heading = (heading + 1) % 4 return true end,
    turnLeft = function() heading = (heading + 3) % 4 return true end,
}
package.loaded.base_dock = nil
local Dock = require("base_dock")
local Navigation = require("navigation")
local nav = Navigation.new({ pose = { x = 0, y = 0, z = 0, heading = 2 } })
assert(Dock.learnAtBase(nav))
assert(Dock.isDepositAhead(), "A modolt lada neve tanulhato legyen.")
physical = 2
nav = Navigation.new({ pose = { x = 0, y = 0, z = 0, heading = 2 } })
assert(Dock.seek(nav, 2))
assert(physical == 0 and nav:getPose().z == 0)

fs, textutils, turtle = oldFs, oldTextutils, oldTurtle
package.loaded.base_dock = oldDock
return true
