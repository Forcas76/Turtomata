-- A csoport ID-i megnezhetok, a torles csak jovahagyas utan tortenik.
local oldUi, oldStore, oldScanner = package.loaded.ui,
    package.loaded.state_store, package.loaded.ore_scanner
local oldTerm, oldKeys, oldOs = term, keys, os
local oldPrint, oldWrite = print, write

local confirms = {}
local approveDelete = false
package.loaded.ui = {
    confirm = function(title, lines)
        confirms[#confirms + 1] = { title = title, lines = lines }
        return title == "ERCLISTA MEGEROSITES" and approveDelete
    end,
}
local saved
package.loaded.state_store = {
    read = function()
        return { version = 2, selected = { ["mod:zinc_ore"] = true },
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
assert(scanner.editTargets())
assert(confirms[1].title:find("Cink", 1, true))
assert(confirms[1].lines[1]:find("mod:zinc_ore", 1, true))
assert(confirms[1].lines[2]:find("mod:deep_zinc_ore", 1, true))
assert(#saved.customGroups == 1, "Megszakitott torlesnel megmarad a csoport.")

approveDelete = true
events = { { "mouse_click", 1, 8, 14 }, { "char", "d" }, { "char", "k" } }
assert(scanner.editTargets())
assert(#saved.customGroups == 0, "Jovahagyott torlesnel tunjon el a csoport.")
assert(not saved.selected["mod:zinc_ore"])

package.loaded.ui, package.loaded.state_store, package.loaded.ore_scanner =
    oldUi, oldStore, oldScanner
term, keys, os, print, write = oldTerm, oldKeys, oldOs, oldPrint, oldWrite
return true
