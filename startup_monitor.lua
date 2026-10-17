-- A downloader ezt startup.lua neven telepiti a megfigyelo eszkozre.
if not fs.exists("remote_monitor") and not fs.exists("remote_monitor.lua") then
    printError("Hianyzik a remote_monitor.lua.")
    return
end
shell.run("remote_monitor")
