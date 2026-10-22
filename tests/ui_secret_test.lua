local oldTerm, oldKeys, oldPrint, oldWrite = term, keys, print, write
local oldPullEvent = os.pullEvent
local oldUi = package.loaded.ui
local oldLocalization = package.loaded.localization

term = {
    getSize = function() return 39, 18 end,
    clear = function() end,
    setCursorPos = function() end,
    isColor = function() return false end,
}
keys = { enter = 1, escape = 2, backspace = 3, left = 4,
    right = 5, up = 6, down = 7 }
print, write = function() end, function() end
package.loaded.ui = nil
package.loaded.localization = { text = function(value) return value end }
local ui = require("ui")

local events = {}
local function queue(...)
    events = { ... }
    os.pullEvent = function()
        local key = table.remove(events, 1)
        assert(key, "A megerosito kepernyo nem vart tovabbi bemenetet.")
        return "key", key
    end
end

local function secretConfirm()
    local step = 0
    return ui.confirm("Frissites", "Folytatod?", "ENTER = frissites", {
        onKey = function(key)
            if key == keys.right then
                step = step == 3 and 1 or step + 1
                return true
            end
            if key == keys.up and step == 3 then
                return true, "developer"
            end
            step = 0
            return false
        end,
    })
end

queue(keys.right, keys.right, keys.right, keys.up)
assert(secretConfirm() == "developer",
    "A titkos kod utolso fel nyila nyissa meg a fejlesztoi menut.")
queue(keys.left)
assert(secretConfirm() == false,
    "A bal nyil tovabbra is visszalep, ha nincs titkos kod.")
queue(keys.right, keys.right, keys.right, keys.left)
assert(secretConfirm() == false,
    "A regi bal nyilas kod helyett mar vissza kell lepni.")
queue(keys.right, keys.enter)
assert(secretConfirm() == true,
    "Az Enter a reszleges titkos kod utan is frissitsen.")

term, keys, print, write = oldTerm, oldKeys, oldPrint, oldWrite
os.pullEvent = oldPullEvent
package.loaded.ui = oldUi
package.loaded.localization = oldLocalization
return true
