-- A csoport ID-i megnezhetok, a torles csak jovahagyas utan tortenik.
local oldUi, oldStore, oldScanner = package.loaded.ui,
    package.loaded.state_store, package.loaded.ore_scanner
local oldTerm, oldKeys, oldOs = term, keys, os
local oldPrint, oldWrite = print, write

local confirms = {}
local approveDelete = false
local approveIdDelete = false
local menuResponses = {}
local inputValue
package.loaded.ui = {
    confirm = function(title, lines)
        confirms[#confirms + 1] = { title = title, lines = lines }
        if title == "ERCLISTA MEGEROSITES" then return approveDelete end
        if title == "BLOKK ID TORLESE" then return approveIdDelete end
        return false
    end,
    menu = function()
        local answer = table.remove(menuResponses, 1)
        assert(answer, "Hianyzik a reszmenu valasza.")
        return answer
    end,
    input = function() return inputValue end,
    message = function() end,
    waitForEnter = function() end,
}
local saved
local readBack
package.loaded.state_store = {
    read = function()
        if readBack then return readBack end
        return { version = 2, selected = {
                ["mod:zinc_ore"] = true, ["minecraft:coal_ore"] = true },
            custom = {}, customGroups = {
                { label = "Cink", ids = { "mod:zinc_ore", "mod:deep_zinc_ore" } },
            }, pendingCandidates = {}, rejectedIds = {} }
    end,
    write = function(_, data) saved = data return true end,
}
package.loaded.ore_scanner = nil
term = { getSize = function() return 39, 20 end,
    clear = function() end, setCursorPos = function() end }
keys = { up = 1, down = 2, left = 3, right = 4, enter = 5, space = 6 }
print, write = function() end, function() end

local events = {}
os = { pullEvent = function()
    local event = table.remove(events, 1)
    assert(event, "Elfogytak a menuesemenyek.")
    return table.unpack(event)
end }
local scanner = require("ore_scanner")

events = {
    { "mouse_click", 1, 8, 14 }, -- Cink neve: ID-lista
    { "char", "d" }, { "char", "k" },
}
menuResponses = { "back" }
assert(scanner.editTargets())
assert(confirms[1].title == "ERCLISTA MEGEROSITES")
assert(#saved.customGroups == 1, "Megszakitott torlesnel megmarad a csoport.")

-- V-nezetben az elso ID modositasa atvezeti a kijelolest is.
inputValue = "mod:new_zinc_ore"
menuResponses = { 1, "edit", "back" }
events = { { "mouse_click", 1, 8, 14 }, { "char", "k" } }
assert(scanner.editTargets())
assert(saved.customGroups[1].ids[1] == inputValue)
assert(saved.selected[inputValue] and not saved.selected["mod:zinc_ore"])

-- Az egyedi ID torlese is kulon megerositest ker.
menuResponses = { 2, "delete", "back" }
events = { { "mouse_click", 1, 8, 14 }, { "char", "k" } }
assert(scanner.editTargets())
assert(#saved.customGroups[1].ids == 2)
approveIdDelete = true
menuResponses = { 2, "delete", "back" }
events = { { "mouse_click", 1, 8, 14 }, { "char", "k" } }
assert(scanner.editTargets())
assert(#saved.customGroups[1].ids == 1)

approveDelete = true
menuResponses = { "back" }
events = { { "mouse_click", 1, 8, 14 }, { "char", "d" }, { "char", "k" } }
assert(scanner.editTargets())
assert(#saved.customGroups == 0, "Jovahagyott torlesnel tunjon el a csoport.")
assert(not saved.selected[inputValue])

-- A beepitett csoport modositasat is kulon mentesben kell tarolni.
inputValue = "minecraft:coal_ore_new"
menuResponses = { 1, "edit", "back" }
events = { { "mouse_click", 1, 8, 3 }, { "char", "k" } }
assert(scanner.editTargets())
assert(saved.version == 3)
assert(saved.groupOverrides.Szen[1] == inputValue)
assert(saved.selected[inputValue] and not saved.selected["minecraft:coal_ore"])
readBack = saved
package.loaded.ore_scanner = nil
scanner = require("ore_scanner")
assert(scanner.matches({ name = inputValue }))
assert(not scanner.matches({ name = "minecraft:coal_ore" }))

-- Regi, onallo egyedi ID is szerkesztheto a V-nezetben.
saved.custom[1] = "mod:single_ore"
saved.selected["mod:single_ore"] = true
package.loaded.ore_scanner = nil
scanner = require("ore_scanner")
inputValue = "mod:renamed_single_ore"
menuResponses = { 1, "edit", "back" }
events = { { "mouse_click", 1, 8, 14 }, { "char", "k" } }
assert(scanner.editTargets())
assert(saved.custom[1] == inputValue)
assert(saved.selected[inputValue] and not saved.selected["mod:single_ore"])

package.loaded.ui, package.loaded.state_store, package.loaded.ore_scanner =
    oldUi, oldStore, oldScanner
term, keys, os, print, write = oldTerm, oldKeys, oldOs, oldPrint, oldWrite
return true
