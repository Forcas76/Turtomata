-- Kozos billentyus/kattinthato menu es strukturalt munkakepernyo.

local ui = {}

local function size()
    local width, height = term.getSize()
    return width, height
end

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function color(name, fallback)
    return colors and colors[name] or fallback
end

local function setTextColor(value)
    if term.isColor and term.isColor() and value then term.setTextColor(value) end
end

local function clip(textValue, width)
    textValue = tostring(textValue or "")
    if #textValue <= width then return textValue end
    if width <= 3 then return string.sub(textValue, 1, width) end
    return string.sub(textValue, 1, width - 3) .. "..."
end

function ui.clear() clear() end

function ui.message(title, lines, kind)
    clear()
    local width = size()
    setTextColor(kind == "error" and color("red") or color("cyan"))
    print(clip(title or "CCTURTLE", width))
    setTextColor(color("white"))
    print(string.rep("-", math.min(width, 39)))
    if type(lines) == "string" then lines = { lines } end
    for _, line in ipairs(lines or {}) do print(clip(line, width)) end
end

function ui.waitForEnter(label)
    local _, height = size()
    term.setCursorPos(1, height)
    write(label or "ENTER = tovabb")
    while true do
        local event, key = os.pullEvent()
        if event == "key" and key == keys.enter then return true end
        if event == "mouse_click" then return true end
    end
end

function ui.menu(title, items, options)
    options = options or {}
    local selected = math.max(1, math.min(options.selected or 1, #items))
    local offset = 0
    while true do
        local width, height = size()
        local firstRow, footerRows = 3, 2
        local visible = math.max(1, height - firstRow - footerRows + 1)
        if selected <= offset then offset = selected - 1 end
        if selected > offset + visible then offset = selected - visible end

        clear()
        setTextColor(color("cyan"))
        print(clip(title or "CCTURTLE", width))
        setTextColor(color("lightGray"))
        print(string.rep("-", math.min(width, 39)))
        local hitRows = {}
        for row = 1, visible do
            local index = offset + row
            local item = items[index]
            if item then
                local enabled = item.enabled ~= false
                local prefix = index == selected and "> " or "  "
                if index == selected then setTextColor(color("yellow"))
                elseif not enabled then setTextColor(color("gray"))
                else setTextColor(color("white")) end
                local suffix = item.suffix and ("  " .. tostring(item.suffix)) or ""
                term.setCursorPos(1, firstRow + row - 1)
                write(clip(prefix .. tostring(item.label) .. suffix, width))
                hitRows[firstRow + row - 1] = index
            end
        end
        setTextColor(color("lightGray"))
        term.setCursorPos(1, height)
        write(clip("Fel/le, Enter, kattintas", width))

        local event, a, b, c = os.pullEvent()
        if event == "key" then
            if a == keys.up then
                repeat selected = selected == 1 and #items or selected - 1
                until items[selected].enabled ~= false or selected == 1
            elseif a == keys.down then
                repeat selected = selected == #items and 1 or selected + 1
                until items[selected].enabled ~= false or selected == #items
            elseif a == keys.enter and items[selected].enabled ~= false then
                return items[selected].value or selected, selected
            elseif (a == keys.backspace or a == keys.left or a == keys.escape)
                and options.allowBack ~= false then
                return nil, "back"
            end
        elseif event == "char" then
            local number = tonumber(a)
            if number and items[number] and items[number].enabled ~= false then
                return items[number].value or number, number
            end
        elseif event == "mouse_scroll" then
            selected = math.max(1, math.min(#items, selected + a))
        elseif event == "mouse_click" then
            local clicked = hitRows[c]
            if clicked and items[clicked].enabled ~= false then
                if clicked == selected then return items[clicked].value or clicked, clicked end
                selected = clicked
            end
        end
    end
end

function ui.choice(title, labels, defaultIndex)
    local items = {}
    for index, label in ipairs(labels) do items[index] = { label = label, value = index } end
    return ui.menu(title, items, { selected = defaultIndex or 1 })
end

function ui.input(title, label, defaultValue, validator, hint)
    while true do
        clear()
        print(title or "Adatbevitel")
        print(string.rep("-", math.min(select(1, size()), 39)))
        if hint then print(hint) print("") end
        write(label .. " [" .. tostring(defaultValue or "") .. "]: ")
        local value = read()
        if value == "" then value = defaultValue end
        local ok, normalized, reason
        if validator then ok, normalized, reason = validator(value)
        else ok, normalized = true, value end
        if ok then return normalized end
        printError(reason or "Hibas ertek.")
        sleep(1)
    end
end

function ui.integer(title, label, defaultValue, minimum, maximum)
    return ui.input(title, label, defaultValue, function(value)
        local number = tonumber(value)
        if not number or number ~= math.floor(number) then return false, nil, "Egesz szam kell." end
        if minimum and number < minimum then return false, nil, "Minimum: " .. minimum end
        if maximum and number > maximum then return false, nil, "Maximum: " .. maximum end
        return true, number
    end)
end

function ui.confirm(title, lines, label)
    ui.message(title, lines)
    ui.waitForEnter(label or "ENTER = inditas")
    return true
end

function ui.renderDashboard(model)
    model = model or {}
    local width, height = size()
    clear()
    setTextColor(color("cyan"))
    print(clip("CCTURTLE | " .. tostring(model.task or "Munka"), width))
    setTextColor(color("lightGray"))
    print(string.rep("-", math.min(width, 39)))
    local rows = {
        { "Allapot", model.status },
        { "Haladas", model.progress },
        { "Pozicio", model.position },
        { "Fuel", model.fuel },
        { "Inventory", model.inventory },
        { "Anyag/Faklya", model.supplies },
        { "Eltelt", model.elapsed },
        { "Hatralevo", model.remaining },
    }
    for _, row in ipairs(rows) do
        if row[2] ~= nil and select(2, term.getCursorPos()) < height - 3 then
            setTextColor(color("lightGray"))
            write(clip(row[1] .. ":", 13))
            setTextColor(color("white"))
            print(clip(" " .. tostring(row[2]), math.max(1, width - 13)))
        end
    end
    local events = model.events or {}
    local start = math.max(1, #events - 1)
    if #events > 0 and select(2, term.getCursorPos()) < height - 1 then
        setTextColor(color("orange"))
        print(string.rep("-", math.min(width, 39)))
        for index = start, #events do
            if select(2, term.getCursorPos()) < height then print(clip("! " .. events[index], width)) end
        end
    end
    setTextColor(color("lightGray"))
    term.setCursorPos(1, height)
    write(clip("Q: megallas es haza | S: reszletek", width))
end

return ui
