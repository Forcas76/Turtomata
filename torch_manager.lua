-- KISERLETI faklyakezelo modul CC:Tweaked banyaszprogramokhoz.
-- Az 1-es slot a fuel, a 2-es slot a faklya helye.

local manager = {}

local function isTorchName(name)
    return type(name) == "string" and string.find(name, "torch", 1, true) ~= nil
end

function manager.isTorch(slot)
    slot = slot or 2
    local detail = turtle.getItemDetail(slot)
    return detail ~= nil and isTorchName(detail.name)
end

function manager.hasTorch()
    return turtle.getItemCount(2) > 0 and manager.isTorch(2)
end

function manager.keepReservedSlot(config)
    return config and config.torchEnabled and manager.isTorch(2)
end

function manager.firstMiningSlot(config)
    return config and config.torchEnabled and 3 or 2
end

function manager.refillFromChest()
    local selected = turtle.getSelectedSlot()
    turtle.select(2)

    if turtle.getItemCount(2) > 0 and not manager.isTorch(2) then
        turtle.select(selected)
        return false, "A 2-es slotban nem faklya van."
    end

    if turtle.getItemSpace(2) > 0 then turtle.suck(64) end
    if turtle.getItemCount(2) == 0 then
        turtle.select(selected)
        return false, "A faklyas lada ures, vagy nincs a fuel lada folott."
    end
    if not manager.isTorch(2) then
        turtle.drop()
        turtle.select(selected)
        return false, "A faklyas ladaban nem faklya van."
    end

    turtle.select(selected)
    return true
end

function manager.placeInDirection(targetHeading, getHeading, face, digHandler)
    if not manager.hasTorch() then return false, "empty" end

    local originalHeading = getHeading()
    face(targetHeading)
    local attempts = 0
    while turtle.detect() do
        local dug, digReason
        if digHandler then dug, digReason = digHandler("forward")
        else dug = turtle.dig() end
        if not dug then
            face(originalHeading)
            return false, digReason or "Nem tudom kialakitani a faklya helyet."
        end
        sleep(0.1)
        attempts = attempts + 1
        if attempts > 20 then
            face(originalHeading)
            return false, "Tul sok blokk esik a faklya helyere."
        end
    end

    local selected = turtle.getSelectedSlot()
    turtle.select(2)
    local placed = turtle.place()
    local restoreSlot = selected <= 2 and 3 or selected
    turtle.select(restoreSlot)
    face(originalHeading)
    if not placed then
        return false, "Nem sikerult lerakni a faklyat. Van megtamaszto blokk?"
    end
    return true
end

function manager.placeAbove(getHeading, face)
    if not manager.hasTorch() then return false, "empty" end
    if turtle.detectUp() then
        return false, "A turtle felett nincs szabad hely a faklyanak."
    end

    local originalHeading = getHeading()
    local selected = turtle.getSelectedSlot()
    turtle.select(2)
    -- Oldalra nezve a placeUp nem a kovetkezo kibontando elso blokkhoz
    -- probalja rogzitani a faklyat.
    face((originalHeading + 1) % 4)
    local placed = turtle.placeUp()
    if not placed then
        face((originalHeading + 3) % 4)
        placed = turtle.placeUp()
    end
    face(originalHeading)
    local restoreSlot = selected <= 2 and 3 or selected
    turtle.select(restoreSlot)
    if not placed then
        return false, "Nem sikerult a fej fole rakni a faklyat."
    end
    return true
end

return manager
