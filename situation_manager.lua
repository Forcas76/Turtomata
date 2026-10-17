-- Kozos, korlatozott helyzetkezeles. Nem tartalmaz vegtelen ujraprobalast.

local situations = {}
situations.__index = situations

local function outcome(kind, reason, extra)
    local value = extra or {}
    value.kind = kind
    value.reason = reason
    return value
end

local function directionApi(direction)
    if direction == "up" then return turtle.inspectUp, turtle.placeUp, turtle.digUp, turtle.attackUp end
    if direction == "down" then return turtle.inspectDown, turtle.placeDown, turtle.digDown, turtle.attackDown end
    return turtle.inspect, turtle.place, turtle.dig, turtle.attack
end

function situations.new(options)
    local self = setmetatable({}, situations)
    self.options = options or {}
    self.warnings = {}
    return self
end

function situations:warn(message)
    self.warnings[#self.warnings + 1] = tostring(message)
    if #self.warnings > 20 then table.remove(self.warnings, 1) end
    if self.options.telemetry then self.options.telemetry:addWarning() end
    if self.options.onWarning then self.options.onWarning(message) end
end

function situations:lastWarnings(count)
    local result = {}
    local first = math.max(1, #self.warnings - (count or 2) + 1)
    for index = first, #self.warnings do result[#result + 1] = self.warnings[index] end
    return result
end

function situations:handleFallingBlock(direction, digHandler)
    local inspect = directionApi(direction)
    local limit = tonumber(self.options.retryLimit) or 20
    for _ = 1, limit do
        local exists = inspect()
        if not exists then return outcome("handled") end
        local ok, reason = digHandler(direction)
        if not ok then return outcome("blocked", reason or "A blokk nem bonthato.") end
        sleep(0.1)
    end
    return outcome("blocked", "Tul sok blokk esik vissza az utba.")
end

function situations:handleEntity(direction)
    local _, _, _, attack = directionApi(direction)
    local limit = tonumber(self.options.entityRetryLimit) or 6
    for _ = 1, limit do
        if attack() then sleep(0.2) else return outcome("handled") end
    end
    return outcome("blocked", "Az entitas nem tavolodott el az utbol.")
end

function situations:fluidKind(direction)
    local inspect = directionApi(direction)
    local exists, data = inspect()
    local name = data and data.name or ""
    if not exists then return nil end
    if string.find(name, "lava", 1, true) then return "lava" end
    if string.find(name, "water", 1, true) then return "water" end
    return nil
end

function situations:sealFluid(direction, blockSelector)
    local inspect, place = directionApi(direction)
    local exists, data = inspect()
    local name = data and data.name or ""
    local isWater = string.find(name, "water", 1, true) ~= nil
    local isLava = string.find(name, "lava", 1, true) ~= nil
    if not exists or (not isWater and not isLava) then return outcome("skipped", "Nincs felismerheto folyadek.") end
    if isWater and self.options.sealWater == false then return outcome("skipped", "A vizlezaras ki van kapcsolva.") end
    if isLava and self.options.sealLava == false then return outcome("blocked", "A lavalezaras ki van kapcsolva.") end
    local selected, reason = blockSelector and blockSelector()
    if not selected then
        if isLava and self.options.lavaFailureFatal ~= false then return outcome("fatal", reason or "Nincs tomitoblokk a lavahoz.") end
        self:warn(reason or "Nincs tomitoblokk a folyadekhoz.")
        return outcome("skipped", reason)
    end
    if place() then return outcome("handled") end
    if isLava and self.options.lavaFailureFatal ~= false then return outcome("fatal", "Nem sikerult lezárni a lavat.") end
    self:warn("Nem sikerult lezárni a folyadekot.")
    return outcome("skipped", "fluid_place_failed")
end

-- A folyadekforrast eloszor blokkal csereli le, majd a behelyezett blokkot
-- kibontja. Igy a celcella ujra jarhato, de az eredeti forras megszunik.
function situations:clearFluidSource(direction, blockSelector, digHandler)
    local kind = self:fluidKind(direction)
    if not kind then return outcome("skipped", "Nincs felismerheto folyadek.") end
    local sealed = self:sealFluid(direction, blockSelector)
    if sealed.kind ~= "handled" then return sealed end
    if digHandler and digHandler() then
        self:warn((kind == "lava" and "Lava" or "Viz") .. "forras lezarva.")
        return outcome("handled")
    end
    if kind == "lava" and self.options.lavaFailureFatal ~= false then
        return outcome("fatal", "A lezart lava helyet nem sikerult szabadda tenni.")
    end
    return outcome("blocked", "A tomitoblokk nem bonthato vissza.")
end

function situations:placeTorchWithFallback(api)
    local attempts = {}
    for _, key in ipairs({ "preferred", "otherSide", "above", "supportPreferred", "supportOtherSide" }) do
        if api[key] then attempts[#attempts + 1] = api[key] end
    end
    local lastReason = "Nem sikerult faklyat lerakni."
    for _, attempt in ipairs(attempts) do
        if attempt then
            local ok, reason = attempt()
            if ok then return outcome("handled") end
            lastReason = reason or lastReason
        end
    end
    self:warn("Faklya kihagyva: " .. lastReason)
    if self.options.torchFailureFatal then return outcome("fatal", lastReason) end
    return outcome("skipped", lastReason)
end

function situations:movementBlocker(move, moveResult, api)
    if api and api.inspectFluid then
        local fluid = api.inspectFluid(move)
        if fluid then
            local sealed = self:sealFluid(fluid.direction, api.selectSealBlock)
            if sealed.kind == "handled" then return { action = "retry" } end
            if sealed.kind == "fatal" then
                return { result = { ok = false, code = "fluid", reason = sealed.reason } }
            end
        end
    end
    if api and api.clear then
        local cleared, reason = api.clear(move)
        if cleared then return { action = "retry" } end
        return { result = { ok = false, code = "blocked", reason = reason or moveResult.reason } }
    end
    return { result = moveResult }
end

return situations
