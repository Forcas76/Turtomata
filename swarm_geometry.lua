-- A szinkronmunka kozos relativ koordinatarendszere.
local geometry = {}

local right = {
    [0] = { x = 1, z = 0 },
    [1] = { x = 0, z = -1 },
    [2] = { x = -1, z = 0 },
    [3] = { x = 0, z = 1 },
}

function geometry.startForSlot(slot)
    if type(slot) ~= "number" or slot < 1 or slot ~= math.floor(slot) then
        return nil, "A sorszam pozitiv egesz szam legyen."
    end
    return { x = slot - 1, y = 0, z = 0, heading = 0 }
end

function geometry.worldForSlot(base, slot)
    if type(base) ~= "table" or type(base.x) ~= "number"
        or type(base.y) ~= "number" or type(base.z) ~= "number"
        or not right[base.heading] then
        return nil, "Hianyos bazispozicio vagy irany."
    end
    local start, reason = geometry.startForSlot(slot)
    if not start then return nil, reason end
    local vector = right[base.heading]
    return {
        x = base.x + start.x * vector.x,
        y = base.y,
        z = base.z + start.x * vector.z,
        heading = base.heading,
    }
end

function geometry.cellKey(pose)
    return string.format("%d,%d,%d", pose.x, pose.y, pose.z)
end

function geometry.branchKey(jobId, z, side)
    if side ~= "left" and side ~= "right" then return nil end
    return tostring(jobId) .. ":" .. tostring(z) .. ":" .. side
end

return geometry
