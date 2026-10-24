-- Turtle-n helyben mentett szinkronmunka/ajanlat allapot.
local Store = require("state_store")
local Geometry = require("swarm_geometry")
local session = {}

local STATE_FILE = "swarm_session.txt"
local OFFERS_FILE = "swarm_offers.txt"
local function copyConfig(value)
    return Store.clone and Store.clone(value) or value
end

function session.load()
    local value = Store.read(STATE_FILE)
    return type(value) == "table" and value.version == 2 and value or nil
end

function session.openLeader(config)
    if type(config) ~= "table" or type(config.mainLength) ~= "number"
        or config.mainLength < 1 or type(config.branchLength) ~= "number"
        or config.branchLength < 1 or type(config.branchSpacing) ~= "number"
        or config.branchSpacing < 1
        or (config.tunnelMode ~= 1 and config.tunnelMode ~= 2) then
        return false, "Hibas kozos agas munkabeallitas."
    end
    local current = session.load()
    if current and current.active then
        return false, "Mar van aktiv szinkronmunka ezen a turtle-n."
    end
    local id = tostring(os.getComputerID()) .. "-"
        .. tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000))
    local value = {
        version = 2, active = true, role = "leader", jobId = id,
        leaderId = os.getComputerID(), slot = 1,
        coordinatorId = nil, epoch = 0,
        mainLength = config.mainLength, branchLength = config.branchLength,
        branchSpacing = config.branchSpacing, tunnelMode = config.tunnelMode,
        workConfig = copyConfig(config),
        status = "waiting_for_coordinator",
    }
    local ok, reason = Store.write(STATE_FILE, value)
    return ok, reason, ok and value or nil
end

function session.claimCoordinator(jobId, coordinatorId)
    local value = session.load()
    if not value or not value.active or value.role ~= "leader"
        or value.jobId ~= jobId then
        return false, "Ez a turtle nem a munka vezetoje."
    end
    if value.coordinatorId and value.coordinatorId ~= coordinatorId then
        return false, "A munkanak mar van masik kezeloje."
    end
    if not value.coordinatorId then
        value.coordinatorId = coordinatorId
        value.epoch = value.epoch + 1
        value.status = "coordinated"
        local ok, reason = Store.write(STATE_FILE, value)
        if not ok then return false, reason end
    end
    return true, nil, value
end

function session.observeOffer(offer)
    if type(offer) ~= "table" or type(offer.jobId) ~= "string"
        or type(offer.leaderId) ~= "number"
        or type(offer.mainLength) ~= "number" or offer.mainLength < 1
        or type(offer.branchLength) ~= "number" or offer.branchLength < 1
        or type(offer.branchSpacing) ~= "number" or offer.branchSpacing < 1
        or (offer.tunnelMode ~= 1 and offer.tunnelMode ~= 2)
        or type(offer.epoch) ~= "number" then
        return false, "Hibas munkaajanlat."
    end
    local current = session.load()
    if current and current.active then return true end
    local offers = Store.read(OFFERS_FILE, {})
    local now = os.epoch and os.epoch("utc") or 0
    for id, old in pairs(offers) do
        if type(old) ~= "table" or now > 0
            and (type(old.seenAt) ~= "number" or now - old.seenAt > 30000) then
            offers[id] = nil
        end
    end
    offers[offer.jobId] = {
        jobId = offer.jobId, leaderId = offer.leaderId,
        coordinatorId = offer.coordinatorId,
        epoch = offer.epoch,
        mainLength = offer.mainLength,
        branchLength = offer.branchLength,
        branchSpacing = offer.branchSpacing,
        tunnelMode = offer.tunnelMode,
        workConfig = type(offer.workConfig) == "table"
            and copyConfig(offer.workConfig) or nil,
        seenAt = now,
    }
    return Store.write(OFFERS_FILE, offers)
end

function session.offers()
    local values = Store.read(OFFERS_FILE, {})
    local result = {}
    for _, offer in pairs(values) do
        local now = os.epoch and os.epoch("utc") or 0
        if type(offer) == "table" and offer.coordinatorId
            and (now == 0 or type(offer.seenAt) == "number"
                and now - offer.seenAt <= 30000) then
            result[#result + 1] = offer
        end
    end
    table.sort(result, function(a, b) return a.jobId < b.jobId end)
    return result
end

function session.forgetOffer(jobId)
    local offers = Store.read(OFFERS_FILE, {})
    if not offers[jobId] then return true end
    offers[jobId] = nil
    return Store.write(OFFERS_FILE, offers)
end

function session.join(offer, slot)
    local current = session.load()
    if current and current.active then
        return false, "Mar van mentett szinkronmunka."
    end
    local pose, reason = Geometry.startForSlot(slot)
    if not pose then return false, reason end
    if slot == 1 or not offer.coordinatorId then
        return false, "Hibas sorszam vagy nincs kezelo."
    end
    if type(offer.mainLength) ~= "number"
        or type(offer.branchLength) ~= "number"
        or type(offer.branchSpacing) ~= "number"
        or offer.branchSpacing < 1
        or (offer.tunnelMode ~= 1 and offer.tunnelMode ~= 2) then
        return false, "Az ajanlatbol hianyzik a munkameret."
    end
    if type(offer.workConfig) ~= "table" then
        return false, "Az ajanlatbol hianyzik a kozos munkabeallitas; frissitsd a resztvevoket."
    end
    local value = {
        version = 2, active = true, role = "worker",
        jobId = offer.jobId, leaderId = offer.leaderId,
        coordinatorId = offer.coordinatorId, epoch = offer.epoch,
        slot = slot, pose = pose, status = "join_pending",
        mainLength = offer.mainLength,
        branchLength = offer.branchLength,
        branchSpacing = offer.branchSpacing,
        tunnelMode = offer.tunnelMode,
        workConfig = type(offer.workConfig) == "table"
            and copyConfig(offer.workConfig) or nil,
    }
    local ok, saveReason = Store.write(STATE_FILE, value)
    return ok, saveReason, ok and value or nil
end

function session.update(value)
    if not value.active then value.collected = nil end
    return Store.write(STATE_FILE, value)
end

return session
