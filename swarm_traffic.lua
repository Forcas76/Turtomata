-- Fail-closed foglalasi szabalyok. A kezelo allapotat a hivo menti.
local Geometry = require("swarm_geometry")
local traffic = {}

local function owner(id)
    return type(id) == "number" and id >= 0 and tostring(id) or nil
end

local function tableFor(state, name)
    state[name] = state[name] or {}
    return state[name]
end

local function validPose(pose)
    return type(pose) == "table" and type(pose.x) == "number"
        and type(pose.y) == "number" and type(pose.z) == "number"
        and pose.x == math.floor(pose.x)
        and pose.y == math.floor(pose.y)
        and pose.z == math.floor(pose.z)
end

function traffic.branchReady(state, key)
    if type(key) ~= "string" then return false, "Hibas agakodol." end
    local branches = tableFor(state, "branches")
    if branches[key] then return false, "Az ag mar nyilvantartasban van." end
    branches[key] = { status = "ready" }
    return true
end

function traffic.claimBranch(state, key, workerId)
    local id = owner(workerId)
    local branch = state.branches and state.branches[key]
    if not id or not branch then return false, "Ismeretlen ag vagy turtle." end
    if state.uncertain and state.uncertain[id] then
        return false, "A turtle helyzete ellenorizendo."
    end
    if branch.owner == id then return true end
    if branch.status ~= "ready" then return false, "Az ag nem szabad." end
    branch.owner, branch.status = id, "claimed"
    return true
end

function traffic.reserveCell(state, pose, workerId)
    local id = owner(workerId)
    if not id or not validPose(pose) then
        return false, "Hibas turtle vagy cella."
    end
    if state.uncertain and state.uncertain[id] then
        return false, "A turtle helyzete ellenorizendo."
    end
    local key = Geometry.cellKey(pose)
    local cells = tableFor(state, "cells")
    if cells[key] and cells[key] ~= id then
        return false, "A cella mar foglalt."
    end
    cells[key] = id
    return true, key
end

-- A regi helyet csak a sikeres mozgast koveto fizikai ACK utan lehet elengedni.
function traffic.releaseCell(state, key, workerId, confirmedPose)
    local id = owner(workerId)
    if not id or not state.cells or state.cells[key] ~= id then
        return false, "A turtle nem birtokolja a cellat."
    end
    if not validPose(confirmedPose)
        or Geometry.cellKey(confirmedPose) == key
        or state.cells[Geometry.cellKey(confirmedPose)] ~= id then
        return false, "Nincs igazolt, lefoglalt uj pozicio."
    end
    state.cells[key] = nil
    return true
end

function traffic.reserveDock(state, workerId)
    local id = owner(workerId)
    if not id then return false, "Hibas turtle." end
    if state.uncertain and state.uncertain[id] then
        return false, "A turtle helyzete ellenorizendo."
    end
    if state.dockOwner and state.dockOwner ~= id then
        return false, "A bazisdokk foglalt."
    end
    state.dockOwner = id
    return true
end

-- Keskeny foag: a teljes szakaszt egy turtle hasznalhatja, iranytol fuggetlenul.
-- Uj tulajdonost csak igazoltan kiurult szakasz utan fogadhat.
function traffic.reserveCorridor(state, sectionKey, workerId, direction)
    local id = owner(workerId)
    if not id or type(sectionKey) ~= "string" or sectionKey == ""
        or (direction ~= "out" and direction ~= "home") then
        return false, "Hibas folyosokeres."
    end
    if state.uncertain and state.uncertain[id] then
        return false, "A turtle helyzete ellenorizendo."
    end
    local corridors = tableFor(state, "corridors")
    local current = corridors[sectionKey]
    if current and current.owner ~= id then
        return false, "A folyosot masik turtle hasznalja."
    end
    if current and current.direction ~= direction then
        return false, "Iranyvaltas elott meg kell erkezni a pihenobe."
    end
    corridors[sectionKey] = current or { owner = id, direction = direction }
    return true
end

function traffic.releaseCorridor(state, sectionKey, workerId, confirmedBay)
    local id = owner(workerId)
    local current = state.corridors and state.corridors[sectionKey]
    if not current or current.owner ~= id or confirmedBay ~= true then
        return false, "A folyosot csak igazolt varakozohelyrol lehet elengedni."
    end
    if state.uncertain and state.uncertain[id] then
        return false, "Bizonytalan helyzetnel a foglalas megmarad."
    end
    state.corridors[sectionKey] = nil
    return true
end

function traffic.releaseDock(state, workerId, confirmedOutside)
    local id = owner(workerId)
    if state.dockOwner ~= id or confirmedOutside ~= true then
        return false, "A dokk nem engedheto el igazolas nelkul."
    end
    state.dockOwner = nil
    return true
end

function traffic.markUncertain(state, workerId)
    local id = owner(workerId)
    if not id then return false end
    state.uncertain = tableFor(state, "uncertain")
    state.uncertain[id] = true
    -- A cella, ag es dokk foglalasa szandekosan megmarad.
    return true
end

return traffic
