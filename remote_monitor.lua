-- CCTurtle megfigyelo Pocket Computerhez es normal/Advanced Computerhez.

local Protocol = require("remote_protocol")
local turtles = {}
local selected = 1
local opened = {}

local function nowMs()
    return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function openModems()
    if not peripheral or not rednet then return 0 end
    local count = 0
    for _, name in ipairs(peripheral.getNames()) do
        local ok, wireless = pcall(peripheral.call, name, "isWireless")
        if ok and wireless then
            if not rednet.isOpen(name) then pcall(rednet.open, name) end
            if rednet.isOpen(name) then opened[name], count = true, count + 1 end
        end
    end
    for name in pairs(opened) do
        if not peripheral.isPresent(name) or not rednet.isOpen(name) then opened[name] = nil end
    end
    return count
end

local function discover()
    if openModems() == 0 then return false end
    rednet.broadcast(Protocol.message("discover", {
        viewerId = os.getComputerID(),
    }), Protocol.CONTROL)
    return true
end

local function ordered()
    local result = {}
    for _, value in pairs(turtles) do result[#result + 1] = value end
    table.sort(result, function(a, b) return a.turtleId < b.turtleId end)
    return result
end

local function clip(value, width)
    value = tostring(value or "-")
    if #value <= width then return value end
    return string.sub(value, 1, math.max(1, width - 1)) .. ">"
end

local function duration(ms)
    local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    return string.format("%02d:%02d:%02d",
        math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
end

local function online(value)
    return nowMs() - value.receivedAt <= Protocol.OFFLINE_AFTER * 1000
end

local function percent(value)
    local total = tonumber(value.progressTotal) or 0
    if total <= 0 then return "-" end
    return math.floor(((tonumber(value.progressCurrent) or 0) / total) * 100) .. "%"
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function line(label, value, width)
    local prefix = label .. ": "
    print(clip(prefix .. tostring(value or "-"), width))
end

local function render()
    local width, height = term.getSize()
    local list = ordered()
    if selected > #list then selected = math.max(1, #list) end
    clear()
    term.setTextColor(colors.cyan)
    print(clip("CCTURTLE MEGFIGYELO", width))
    term.setTextColor(colors.lightGray)
    print(string.rep("-", math.min(width, 39)))
    if openModems() == 0 then
        term.setTextColor(colors.red)
        print("Nincs wireless/Ender modem.")
        print("Csatlakoztass modemet; automatikusan felismerem.")
    elseif #list == 0 then
        term.setTextColor(colors.orange)
        print("Turtle keresese...")
        print("Bekapcsolas utan automatikusan megjelenik.")
    elseif width < 35 then
        local item = list[selected]
        term.setTextColor(online(item) and colors.lime or colors.red)
        print(clip((item.label or ("Turtle #" .. item.turtleId))
            .. (online(item) and " ONLINE" or " OFFLINE"), width))
        term.setTextColor(colors.white)
        line("Feladat", item.task, width)
        line("Allapot", item.activity, width)
        line("Haladas", percent(item), width)
        line("Fuel", item.fuel == -1 and "vegtelen" or item.fuel, width)
        line("Inventory", item.inventoryUsed and (item.inventoryUsed .. "/16") or "-", width)
        line("Eltelt", duration(item.elapsedMs), width)
        line("Hatra", duration(item.remainingMs), width)
        if item.position then
            line("Pozicio", string.format("%d,%d,%d", item.position.x, item.position.y, item.position.z), width)
        end
        term.setCursorPos(1, height)
        write(clip("< > turtle  Q kilepes", width))
    else
        print(string.format("%-4s %-16s %-8s %s", "ID", "Nev", "Allapot", "Haladas"))
        local maximum = math.max(1, height - 13)
        for index = 1, math.min(#list, maximum) do
            local item = list[index]
            term.setTextColor(index == selected and colors.yellow
                or (online(item) and colors.white or colors.red))
            print(clip(string.format("%-4d %-16s %-8s %s",
                item.turtleId, item.label or "Turtle", online(item) and "ONLINE" or "OFFLINE",
                percent(item)), width))
        end
        local item = list[selected]
        term.setTextColor(colors.lightGray)
        print(string.rep("-", math.min(width, 39)))
        term.setTextColor(colors.white)
        line("Feladat", item.task, width)
        line("Allapot", item.activity, width)
        line("Fuel / inv", tostring(item.fuel == -1 and "vegtelen" or item.fuel)
            .. " / " .. tostring(item.inventoryUsed or "-") .. "/16", width)
        line("Ido", duration(item.elapsedMs) .. " / hatra " .. duration(item.remainingMs), width)
        if item.position then
            line("Pozicio", string.format("%d,%d,%d h=%s", item.position.x,
                item.position.y, item.position.z, tostring(item.position.heading or "-")), width)
        end
        term.setCursorPos(1, height)
        write(clip("Nyilak/kattintas: valtas | Q: kilepes", width))
    end
end

discover()
local discoverTimer = os.startTimer(Protocol.DISCOVER_INTERVAL)
local refreshTimer = os.startTimer(1)
render()

while true do
    local event, p1, p2, p3 = os.pullEventRaw()
    if event == "terminate" then break
    elseif event == "rednet_message" and p3 == Protocol.STATUS
        and Protocol.valid(p2, "status") then
        p2.receivedAt = nowMs()
        turtles[p2.turtleId or p1] = p2
        render()
    elseif event == "timer" and p1 == discoverTimer then
        discover()
        discoverTimer = os.startTimer(Protocol.DISCOVER_INTERVAL)
        render()
    elseif event == "timer" and p1 == refreshTimer then
        refreshTimer = os.startTimer(1)
        render()
    elseif event == "peripheral" or event == "peripheral_detach" then
        openModems()
        discover()
        render()
    elseif event == "key" then
        if p1 == keys.q then break
        elseif p1 == keys.left or p1 == keys.up then selected = math.max(1, selected - 1)
        elseif p1 == keys.right or p1 == keys.down then selected = math.min(#ordered(), selected + 1) end
        render()
    elseif event == "mouse_click" then
        local _, height = term.getSize()
        if p3 >= 4 and p3 < height - 7 then selected = math.max(1, p3 - 3) end
        render()
    end
end

clear()
print("Megfigyelo leallitva.")
