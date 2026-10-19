package.loaded["navigation"] = nil
package.loaded["base_dock"] = nil
local Navigation = require("navigation")
local Dock = require("base_dock")
local previousTurtle = turtle

local physical = 0
local heading = 0
turtle = {
    inspect = function()
        if physical == 0 and heading == 2 then
            return true, { name = "minecraft:chest" }
        end
        return false, "No block"
    end,
    detect = function() return false end,
    forward = function()
        physical = physical - 1
        return true
    end,
    turnRight = function() heading = (heading + 1) % 4 return true end,
    turnLeft = function() heading = (heading + 3) % 4 return true end,
}

local function navAt(z)
    return Navigation.new({
        state = {
            pose = { x = 0, y = 0, z = z, heading = 0 },
            path = z > 0 and { { kind = "h", heading = 0 } } or {},
            anchors = { home = {
                index = 0, pose = { x = 0, y = 0, z = 0, heading = 0 },
            } },
        },
        ensureFuel = function() return true end,
    })
end

local nav = navAt(2)
assert(Dock.chestOnReturn(nav), "A lada elott meg kell allni.")
assert(Dock.seek(nav, 2))
assert(nav:getPose().z == 0 and #nav.state.path == 0)
assert(physical == 0, "A turtle nem lephet bele a ladaba.")

physical, heading = 2, 0
nav = navAt(0)
assert(Dock.seek(nav, 2), "Ket blokkal korai megallasnal meg kell talalni a ladat.")
assert(physical == 0 and nav:getPose().z == 0)

turtle = previousTurtle
return true
