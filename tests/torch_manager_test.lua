local oldTurtle = turtle
local oldManager = package.loaded.torch_manager
local selected, count, requested = 5, 37, nil
turtle = {
    getSelectedSlot = function() return selected end,
    select = function(slot) selected = slot return true end,
    getItemCount = function(slot) return slot == 2 and count or 0 end,
    getItemSpace = function(slot) return slot == 2 and 64 - count or 64 end,
    getItemDetail = function(slot)
        return slot == 2 and count > 0 and { name = "minecraft:torch" } or nil
    end,
    suck = function(amount)
        requested = amount
        count = count + math.min(amount, 64 - count)
        return true
    end,
}
package.loaded.torch_manager = nil
local Manager = require("torch_manager")
assert(Manager.refillFromChest())
assert(requested == 27 and count == 64 and selected == 5)
requested = nil
assert(Manager.refillFromChest())
assert(requested == nil and count == 64)
package.loaded.torch_manager = oldManager
turtle = oldTurtle
return true
