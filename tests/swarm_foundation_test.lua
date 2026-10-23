local Geometry = require("swarm_geometry")
local Safety = require("swarm_safety")

local p = assert(Geometry.startForSlot(3))
assert(p.x == 2 and p.y == 0 and p.z == 0 and p.heading == 0)
assert(Geometry.startForSlot(0) == nil)
local world = assert(Geometry.worldForSlot(
    { x = 100, y = 64, z = 200, heading = 1 }, 3))
assert(world.x == 100 and world.y == 64 and world.z == 198)
assert(Geometry.branchKey("job", 6, "left") == "job:6:left")

local oldTurtle = turtle
local front = { name = "computercraft:turtle_normal" }
turtle = {
    inspect = function() return true, front end,
    inspectUp = function() return true, { name = "minecraft:stone" } end,
    inspectDown = function() return true, { name = "minecraft:chest" } end,
}
assert(not Safety.mayDig("forward"))
assert(Safety.mayDig("up"))
assert(not Safety.mayDig("down"))
front = { name = "minecraft:deepslate" }
assert(Safety.mayDig("forward"))
turtle = oldTurtle
return true
