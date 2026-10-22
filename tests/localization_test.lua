package.loaded["localization"] = nil
local Localization = require("localization")

assert(Localization.getLanguage() == "en")

local previousFs, previousTextutils = fs, textutils
fs = {
    exists = function(path) return path == "settings.txt" end,
    open = function()
        return { readAll = function() return "saved-hu" end,
            close = function() end }
    end,
}
textutils = {
    unserializeJSON = function()
        return { general = { language = "hu" } }
    end,
}
package.loaded["localization"] = nil
Localization = require("localization")
assert(Localization.getLanguage() == "hu")
fs, textutils = previousFs, previousTextutils

assert(require("settings").defaults().general.language == "en")
Localization.setLanguage("hu")
assert(Localization.text("Beallitasok") == "Beallitasok")
Localization.setLanguage("en")
assert(Localization.text("Beallitasok") == "Settings")
assert(Localization.text("Farm karbantartas") == "Farm maintenance")
assert(Localization.text("Feladatlanc") == "Task chain")
assert(Localization.text("Lepakolas es folytatas") == "Unload and continue")
assert(Localization.text("ismeretlen dinamikus adat") == "ismeretlen dinamikus adat")
assert(Localization.getLanguage() == "en")

return true
