-- A downloader ezt startup.lua neven telepiti a turtle-re.
if not turtle then
    printError("Ez a startup a turtle telepitesi csomaghoz tartozik.")
    return
end
if not fs.exists("main") and not fs.exists("main.lua") then
    printError("Hianyzik a main.lua.")
    return
end
shell.run("main")
