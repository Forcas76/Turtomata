-- Feladat kozben tenylegesen inventoryba kerult dropok osszesitese.
-- Egy dig elotti/utani mintat vet ossze; fuel/faklya-lada suck nem szamit bele.
local ledger = {}

function ledger.snapshot()
    local totals = {}
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            if detail and type(detail.name) == "string" then
                totals[detail.name] = (totals[detail.name] or 0)
                    + (detail.count or turtle.getItemCount(slot))
            end
        end
    end
    return totals
end

function ledger.record(current, before, after)
    current = current or {}
    for name, count in pairs(after or {}) do
        local gained = count - ((before or {})[name] or 0)
        if gained > 0 then current[name] = (current[name] or 0) + gained end
    end
    return current
end

function ledger.ordered(current)
    local entries = {}
    for name, count in pairs(current or {}) do
        if type(name) == "string" and type(count) == "number" and count > 0 then
            entries[#entries + 1] = { name = name, count = count }
        end
    end
    table.sort(entries, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return entries
end

return ledger
