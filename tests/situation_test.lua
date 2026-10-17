local cell = "minecraft:water"
local selected = false

sleep = function() end
turtle = {
    inspect = function()
        if not cell then return false end
        return true, { name = cell }
    end,
    inspectUp = function() return false end,
    inspectDown = function() return false end,
    place = function()
        if not selected then return false end
        cell = "minecraft:cobblestone"
        return true
    end,
    placeUp = function() return false end,
    placeDown = function() return false end,
    dig = function()
        if cell ~= "minecraft:cobblestone" then return false end
        cell = nil
        return true
    end,
    digUp = function() return false end,
    digDown = function() return false end,
    attack = function() return false end,
    attackUp = function() return false end,
    attackDown = function() return false end,
}

package.loaded["situation_manager"] = nil
local Situations = require("situation_manager")
local manager = Situations.new({ sealWater = true, sealLava = true })
local cleared = manager:clearFluidSource("forward", function()
    selected = true
    return true
end, turtle.dig)

assert(cleared.kind == "handled")
assert(cell == nil)
assert(#manager:lastWarnings(1) == 1)

return true
