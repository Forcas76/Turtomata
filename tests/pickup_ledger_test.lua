local Ledger = require("pickup_ledger")
local result = Ledger.record({}, { ["minecraft:cobblestone"] = 3 }, {
    ["minecraft:cobblestone"] = 5, ["minecraft:raw_iron"] = 1,
})
assert(result["minecraft:cobblestone"] == 2)
assert(result["minecraft:raw_iron"] == 1)
Ledger.record(result, { ["minecraft:cobblestone"] = 5 }, {
    ["minecraft:cobblestone"] = 1,
})
assert(result["minecraft:cobblestone"] == 2) -- lepakolas nem negativ pickup
local list = Ledger.ordered(result)
assert(list[1].name == "minecraft:cobblestone" and list[1].count == 2)
return true
