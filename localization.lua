-- Kozos magyar/angol lokalizacio. A magyar szovegek a stabil kulcsok.

local localization = {}
local language = nil

local english = {
    ["BE"] = "ON", ["KI"] = "OFF", ["Vissza"] = "Back",
    ["BEALLITASOK"] = "SETTINGS", ["MEGFIGYELO"] = "MONITOR",
    ["PARANCSOK"] = "COMMANDS",
    ["Beallitasok"] = "Settings", ["Diagnosztika"] = "Diagnostics",
    ["Kilepes"] = "Exit", ["Program frissitese"] = "Update program",
    ["Felbehagyott munka"] = "Resume saved job",
    ["Munka kezelese"] = "Manage jobs", ["MUNKA KEZELES"] = "MANAGE JOBS",
    ["Tulajdonos"] = "Owner", ["Auto folytatas"] = "Auto resume",
    ["Munka felszabaditasa"] = "Release job",
    ["Mentett munka torlese"] = "Delete saved job",
    ["Nincs mentett munka"] = "No saved job",
    ["MENTES TORLESE"] = "DELETE SAVE",
    ["MENTES VEGLEGES TORLESE"] = "PERMANENTLY DELETE SAVE",
    ["A folytatasi mentes vegleg torlodik."] = "The resume save will be deleted permanently.",
    ["Csak bazison allo turtle-n hasznald!"] = "Only use this while the turtle is at base!",
    ["Az aktiv reszfeladat mentese is torlodik."] = "The active sub-job save will also be deleted.",
    ["ENTER = torles"] = "ENTER = delete",
    ["MENTES TOROLVE"] = "SAVE DELETED", ["TORLESI HIBA"] = "DELETE ERROR",
    ["A mentes torolve."] = "The save was deleted.",
    ["Feladat: "] = "Job: ", ["Haladas: "] = "Progress: ",
    ["Branch mining"] = "Branch mining", ["Terulet kiasasa"] = "Excavate area",
    ["Nether utepito"] = "Nether builder", ["Utvonal keszites"] = "Route building",
    ["Koordinatara navigalas"] = "Navigate to coordinates",
    ["Farm karbantartas"] = "Farm maintenance",
    ["Feladatlanc"] = "Task chain",
    ["Navigacio es altalanos"] = "Navigation and general",
    ["Biztonsag es helyzetkezeles"] = "Safety and situations",
    ["Inventory KISERLETI"] = "Inventory EXPERIMENTAL",
    ["Faklyazas"] = "Torch placement", ["Erckereses"] = "Ore scanning",
    ["Nyelv / Language"] = "Language / Nyelv",
    ["Alapertekek visszaallitasa"] = "Restore defaults",
    ["Magyar"] = "Hungarian", ["Angol"] = "English",
    ["Alapbol engedelyezve"] = "Enabled by default",
    ["Keresett ercek"] = "Selected ores", ["Max. kovetesi melyseg"] = "Maximum vein depth",
    ["Max. blokk / erctelep"] = "Maximum blocks per vein",
    ["Alap tavolsag"] = "Default interval", ["Alap elhelyezes"] = "Default placement",
    ["Oldalt"] = "On the side", ["Fej folott"] = "Above the turtle",
    ["Viz lezarasa"] = "Seal water", ["Lava lezarasa"] = "Seal lava",
    ["Faklyahiba vegzetes"] = "Torch failure is fatal",
    ["Ujraprobalasi limit"] = "Retry limit", ["Tomitoblokk"] = "Sealing block",
    ["Kezdo mp / muvelet"] = "Initial seconds/action",
    ["Koordinata mod"] = "Coordinate mode", ["Fuel tartalek"] = "Fuel reserve",
    ["Kikapcsolva"] = "Disabled", ["Bekapcsolva"] = "Enabled",
    ["Uj munka"] = "New job", ["Kezi folytatas"] = "Manual resume",
    ["Ujra"] = "Retry in",
    ["403: mas hiba is lehet."] = "403 may also mean access denied.",
    ["R/Enter: proba most"] = "R/Enter: retry now",
    ["Q/Esc: megszakit"] = "Q/Esc: cancel", ["varakozas"] = "backoff",
    ["Kezdo tavolsag"] = "Starting distance", ["Alagut hossza"] = "Tunnel length",
    ["Fotengely"] = "Main tunnel", ["Oldalagat"] = "Side branch",
    ["Agak tavolsaga"] = "Branch spacing", ["Szelesseg"] = "Width",
    ["Melyseg"] = "Depth", ["Magassag"] = "Height", ["Hossz"] = "Length",
    ["Egyenesen"] = "Forward", ["Jobbra"] = "Right", ["Hatra"] = "Back", ["Balra"] = "Left",
    ["Felfele"] = "Up", ["Lefele"] = "Down", ["Mindegy"] = "Any",
    ["Eszak"] = "North", ["Kelet"] = "East", ["Del"] = "South", ["Nyugat"] = "West",
    ["Inditasi hiba"] = "Startup error", ["Hianyzo program"] = "Missing program",
    ["INDITASI OSSZEFOGLALO"] = "JOB SUMMARY", ["ENTER = turtle inditasa"] = "ENTER = start turtle",
    ["ENTER = tovabb"] = "ENTER = continue", ["ENTER = inditas"] = "ENTER = start",
    ["ENTER = vissza a fomenube"] = "ENTER = return to main menu",
    ["Fel/le, Enter, kattintas"] = "Up/down, Enter, click",
    ["Allapot"] = "Status", ["Haladas"] = "Progress", ["Pozicio"] = "Position",
    ["Fuel"] = "Fuel", ["Inventory"] = "Inventory", ["Anyag/Faklya"] = "Material/Torches",
    ["Eltelt"] = "Elapsed", ["Hatralevo"] = "Remaining",
    ["Q: megallas es haza | S: reszletek"] = "Q: stop and return | S: details",
    ["Adatok frissitese"] = "Refresh data", ["Lepakolas es folytatas"] = "Unload and continue",
    ["Munka leallitasa, haza"] = "Stop job and return",
    ["Megfigyelo frissitese"] = "Update monitor",
    ["Parancs elkuldve; visszaigazolasra var."] = "Command sent; waiting for acknowledgement.",
    ["A parancs kuldese sikertelen."] = "Failed to send command.",
    ["Megeroses: valaszd ki meg egyszer."] = "Confirm: select the command again.",
    ["Nincs kivalasztott turtle."] = "No turtle selected.",
    ["Nincs vezetek nelkuli modem."] = "No wireless modem found.",
    ["Teknos"] = "Turtle", ["Kapcsolat"] = "Connection", ["Kesz"] = "Done",
    ["ELERHETO"] = "ONLINE", ["NINCS JEL"] = "NO SIGNAL", ["NEM ELERHETO"] = "OFFLINE",
    ["Feladat"] = "Task", ["Muvelet"] = "Activity", ["Uzemanyag"] = "Fuel",
    ["Tarhely"] = "Inventory", ["Uzemanyag / tarhely"] = "Fuel / inventory",
    ["Fomenu"] = "Main menu", ["Varakozik"] = "Idle", ["Indulas"] = "Starting",
    ["Hazateres"] = "Returning home", ["Lepakolas es tankolas"] = "Unloading and refuelling",
    ["Visszateres a munkahoz"] = "Returning to work", ["Befejezve"] = "Completed",
    ["Erckereses a bal agban"] = "Scanning left branch for ore",
    ["Erckereses a jobb agban"] = "Scanning right branch for ore",
    ["Agas banyaszat"] = "Branch mining", ["Nether utepites"] = "Nether building",
    ["Koordinatas mozgas"] = "Coordinate navigation",
    ["Terulet kitermelese"] = "Excavating area",
    ["Mentett munka folytatasa"] = "Resuming saved job",
    ["Lepcso epites"] = "Building stairs", ["Alagut epites"] = "Building tunnel",
    ["Bal oldalagat asasa"] = "Mining left branch", ["Jobb oldalagat asasa"] = "Mining right branch",
    ["Oldalagak keszen"] = "Side branches completed", ["Navigalas"] = "Navigating",
    ["Megallitva a bazison"] = "Stopped at base",
    ["Program frissitese..."] = "Updating program...",
    ["Frissites kesz. Ujrainditas..."] = "Update complete. Restarting...",
    ["A frissites sikertelen."] = "Update failed.",
    ["Nincs wireless/Ender modem."] = "No Wireless/Ender modem found.",
    ["Csatlakoztass modemet; automatikusan felismerem."] = "Attach a modem; it will be detected automatically.",
    ["Turtle keresese..."] = "Searching for turtles...",
    ["Bekapcsolas utan automatikusan megjelenik."] = "A powered turtle appears automatically.",
    ["Bal/jobb: oldal | Fel/le: teki | Q"] = "Left/right: page | Up/down: turtle | Q",
    ["Bal/jobb: oldal | Fel/le/katt: teki | Q"] = "Left/right: page | Up/down/click: turtle | Q",
    ["Bal/jobb: oldal | Fel/le: opcio | Enter"] = "Left/right: page | Up/down: option | Enter",
    ["Allapot elkuldve."] = "Status sent.",
    ["Biztonsagos leallitas es hazateres kerese fogadva."] = "Safe stop and return request accepted.",
    ["Lepakolas, feltoltes es folytatas kerese fogadva."] = "Unload, refill and resume request accepted.",
    ["Nincs aktiv munka; a turtle mar a fomenuben van."] = "There is no active job; the turtle is already in the main menu.",
    ["Nincs aktiv munka, amit ki lehetne szolgalni."] = "There is no active job to service.",
    ["A koordinatas feladatnak nincs ladakezelese."] = "Coordinate navigation has no chest service.",
    ["Ismeretlen parancs."] = "Unknown command.",
    ["Turtle program telepitese"] = "Install turtle program",
    ["Megfigyelo telepitese"] = "Install monitor program",
    ["TELEPITO"] = "INSTALLER", ["Forras"] = "Source", ["komponensek"] = "components",
    ["Nyilak + ENTER, vagy kattintas"] = "Arrow keys + ENTER, or click",
    ["FEJLESZTOI MENU"] = "DEVELOPER MENU",
    ["Tokenes GitHub frissites"] = "GitHub update with token",
    ["Publikus GitHub frissites"] = "Public GitHub update",
    ["Frissites megszakitasa"] = "Cancel update",
    ["Tokenfajl hianyzik vagy ures."] = "Token file missing or empty.",
    ["Fel/le + Enter"] = "Up/down + Enter",
    ["Frissites indul..."] = "Starting update...",
    ["A teljes turtle program frissul."] = "The complete turtle program will be updated.",
    ["Siker utan az eszkoz ujraindul."] = "The device will restart after a successful update.",
    ["ENTER = frissites"] = "ENTER = update",
    ["Kerlek varj."] = "Please wait.",
    ["Ellenorizd a downloader uzeneteit."] = "Check the downloader messages.",
    ["BEALLITASOK > ERCKERESES"] = "SETTINGS > ORE SCANNING",
    ["BEALLITASOK > FAKLYAZAS"] = "SETTINGS > TORCHES",
    ["BEALLITASOK > BIZTONSAG"] = "SETTINGS > SAFETY",
    ["BEALLITASOK > NAVIGACIO"] = "SETTINGS > NAVIGATION",
    ["Faklya elhelyezese"] = "Torch placement",
    ["Kezdo muveleti ido"] = "Initial action time", ["Masodperc"] = "Seconds",
    ["Koordinatas navigacio modja"] = "Coordinate navigation mode",
    ["Csak szabad ut"] = "Open path only", ["Alagut a celig (KISERLETI)"] = "Dig to target (EXPERIMENTAL)",
    ["KISERLETI faklyazas"] = "EXPERIMENTAL torch placement",
    ["Fout: hany beasas"] = "Main: every N branches", ["Faklya tavolsag"] = "Torch interval",
    ["Ag: hany blokkonkent"] = "Branch: every N blocks",
    ["Faklya helye (KISERLETI)"] = "Torch position (EXPERIMENTAL)",
    ["BRANCH MINING MOD"] = "BRANCH MINING MODE",
    ["Branch 1x2"] = "Branch 1x2", ["Branch 1x3"] = "Branch 1x3", ["Egyenes 3x3"] = "Straight 3x3",
    ["INDULAS"] = "START", ["MERETEK"] = "DIMENSIONS", ["UZEMANYAG"] = "FUEL",
    ["KISERLETI inventory"] = "EXPERIMENTAL inventory",
    ["KISERLETI erckereses"] = "EXPERIMENTAL ore scanning",
    ["TERULET"] = "AREA", ["KISERLETI koordinatas indulas"] = "EXPERIMENTAL coordinate start",
    ["LADABAZIS IRANYA"] = "CHEST BASE FACING", ["LADABAZIS"] = "CHEST BASE",
    ["MUNKAPONT"] = "WORK POINT", ["ASAS IRANYA A KEZDO IRANYHOZ"] = "DIGGING DIRECTION RELATIVE TO START",
    ["Vilag X"] = "World X", ["Vilag Y"] = "World Y", ["Vilag Z"] = "World Z",
    ["NETHER UTEPITO"] = "NETHER BUILDER", ["UTVONAL KESZITES"] = "ROUTE BUILDING",
    ["Lepcso fel/le"] = "Stairs up/down",
    ["Vedett 1x2 alagut"] = "Protected 1x2 tunnel",
    ["Sima 1x2 alagut"] = "Plain 1x2 tunnel", ["LEPCSO IRANYA"] = "STAIR DIRECTION",
    ["EPITOANYAG"] = "BUILDING MATERIAL", ["Blokk"] = "Block",
    ["JELENLEGI FACING"] = "CURRENT FACING", ["JELENLEGI HELY"] = "CURRENT POSITION",
    ["CEL"] = "TARGET", ["Cel X"] = "Target X", ["Cel Y"] = "Target Y", ["Cel Z"] = "Target Z",
    ["VEGSO FACING"] = "FINAL FACING", ["FOLYTATHATO MUNKAK"] = "RESUMABLE JOBS",
    ["DIAGNOSZTIKA"] = "DIAGNOSTICS", ["KISERLETI"] = "EXPERIMENTAL",
}

local function loadLanguage()
    if language then return language end
    language = "en"
    if fs and fs.exists("settings.txt") then
        local file = fs.open("settings.txt", "r")
        if file then
            local raw = file.readAll()
            file.close()
            local ok, value = pcall(textutils.unserializeJSON, raw)
            if ok and type(value) == "table" and value.general
                and value.general.language == "hu" then language = "hu" end
        end
    end
    return language
end

function localization.setLanguage(value)
    language = value == "hu" and "hu" or "en"
end

function localization.getLanguage()
    return loadLanguage()
end

function localization.text(value)
    if type(value) ~= "string" or loadLanguage() ~= "en" then return value end
    return english[value] or value
end

function localization.languages()
    return {
        { code = "hu", label = "Magyar" },
        { code = "en", label = "Angol" },
    }
end

return localization
