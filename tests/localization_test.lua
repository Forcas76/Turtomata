package.loaded["localization"] = nil
local Localization = require("localization")

Localization.setLanguage("hu")
assert(Localization.text("Beallitasok") == "Beallitasok")
Localization.setLanguage("en")
assert(Localization.text("Beallitasok") == "Settings")
assert(Localization.text("Lepakolas es folytatas") == "Unload and continue")
assert(Localization.text("ismeretlen dinamikus adat") == "ismeretlen dinamikus adat")
assert(Localization.getLanguage() == "en")

return true
