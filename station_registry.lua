-- Kozos munka allomasai. A konfiguracio a koordinatori mentes resze.
-- Ez a modul nem mozgat turtle-t es nem feltetelez szabad utvonalat.
local Geometry = require("swarm_geometry")
local stations = {}

function stations.id(slot)
    if type(slot) ~= "number" or slot < 1 or slot ~= math.floor(slot) then
        return nil, "Hibas allomassorszam."
    end
    return string.format("D%02d", slot)
end

function stations.ensure(state)
    state.stations = state.stations or {}
    if not state.stations.D01 then
        state.stations.D01 = {
            id = "D01", type = "primary_service", ownerSlot = 1,
            pose = { x = 0, y = 0, z = 0, heading = 0 },
            chest = { x = 0, y = 0, z = -1 },
            enabled = true, verified = false, status = "unknown",
        }
    end
    return state.stations
end

function stations.isChest(name)
    return type(name) == "string"
        and (name:find("chest", 1, true) ~= nil
            or name:find("barrel", 1, true) ~= nil)
end

function stations.register(state, slot, workerId, chestName, confirmed)
    local id, reason = stations.id(slot)
    if not id then return false, reason end
    if confirmed ~= true or not stations.isChest(chestName) then
        return false, "A lada helyszini ellenorzese hianyzik."
    end
    local expected = slot == 1 and state.leaderId or nil
    if slot > 1 then
        local worker = state.workers and state.workers[tostring(workerId)]
        if not worker or worker.slot ~= slot or worker.transit
            or worker.assignedBranch or worker.status ~= "registered_no_motion" then
            return false, "A seged nincs a szabad sajat sorhelyen."
        end
        expected = workerId
    end
    if workerId ~= expected then return false, "Idegen allomasjelentes." end
    local pose = Geometry.startForSlot(slot)
    if state.cells and state.cells[Geometry.cellKey(pose)] ~= tostring(workerId) then
        return false, "A dokkolocella nem a jelento turtle-e."
    end
    local all = stations.ensure(state)
    local old = all[id]
    if old and old.lease then return false, "Az allomas jelenleg foglalt." end
    if old and old.chestName and old.chestName ~= chestName then
        old.enabled, old.verified, old.status = false, false, "unknown"
        return false, "A lada tipusa megvaltozott; kezi ellenorzes kell."
    end
    all[id] = {
        id = id, type = slot == 1 and "primary_service" or "unload_only",
        ownerSlot = slot, pose = pose,
        chest = { x = pose.x, y = 0, z = -1 },
        chestName = chestName, enabled = true, verified = true,
        status = "available",
        lastVerifiedAt = os.epoch and os.epoch("utc") or 0,
    }
    return true, nil, all[id]
end

function stations.canUnload(state, stationId, workerId)
    local station = stations.ensure(state)[stationId]
    if not station or not station.enabled or not station.verified
        or station.status == "full" or station.status == "blocked"
        or station.status == "unknown" then
        return false, "Az allomas nem ellenorzott vagy nem hasznalhato."
    end
    if station.lease and station.lease.workerId ~= workerId then
        return false, "Az allomas foglalt."
    end
    if station.ownerSlot > 1 then
        local ownerId, owner
        for id, candidate in pairs(state.workers or {}) do
            if candidate.slot == station.ownerSlot then
                ownerId, owner = id, candidate
                break
            end
        end
        if not owner or ownerId ~= tostring(workerId) then
            local away = owner and owner.status == "at_branch"
                and not owner.transit and owner.pose
                and Geometry.cellKey(owner.pose) ~= Geometry.cellKey(station.pose)
                and not (state.uncertain and state.uncertain[ownerId])
            if not away then
                return false, "A segedallomas tulajdonosanak helye nem biztos."
            end
        end
    end
    local occupant = state.cells and state.cells[Geometry.cellKey(station.pose)]
    if occupant and occupant ~= tostring(workerId) then
        local other = state.workers and state.workers[occupant]
        if not other or other.slot ~= station.ownerSlot
            or other.status ~= "at_branch" or other.transit
            or not other.pose
            or Geometry.cellKey(other.pose) == Geometry.cellKey(station.pose)
            or state.uncertain and state.uncertain[occupant] then
            return false, "A dokkolocellat masik turtle foglalja."
        end
    end
    return true
end

function stations.canSupply(state, stationId, workerId)
    if stationId ~= "D01" then
        return false, "Fuel es faklya csak a foallomason veheto fel."
    end
    return stations.canUnload(state, stationId, workerId)
end

function stations.reserve(state, stationId, workerId, requestId)
    if type(requestId) ~= "string" or requestId == "" then
        return false, "Hibas foglalasi azonosito."
    end
    local station = stations.ensure(state)[stationId]
    if station and station.lease and station.lease.workerId == workerId
        and station.lease.requestId == requestId then
        return true, nil, station.lease
    end
    if station and station.lease then
        return false, "Az allomas korabbi foglalasa meg ervenyes."
    end
    local ok, reason = stations.canUnload(state, stationId, workerId)
    if not ok then return false, reason end
    station.lease = {
        workerId = workerId, requestId = requestId,
        leaseId = tostring(state.epoch) .. ":" .. stationId .. ":"
            .. tostring(workerId) .. ":" .. requestId,
    }
    station.status = "reserved"
    return true, nil, station.lease
end

function stations.release(state, stationId, workerId, leaseId, departed)
    local station = stations.ensure(state)[stationId]
    local lease = station and station.lease
    if not lease or lease.workerId ~= workerId or lease.leaseId ~= leaseId
        or departed ~= true then
        return false, "Fizikai tavozasi igazolas nelkul a foglalas megmarad."
    end
    station.lease = nil
    if station.status == "reserved" then station.status = "available" end
    return true
end

return stations
