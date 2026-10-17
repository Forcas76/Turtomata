-- Aktiv futasido-, muveletido- es ETA-kezelo.

local telemetry = {}
telemetry.__index = telemetry

local function nowMs()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

local function positive(value, fallback)
    value = tonumber(value)
    if value and value > 0 then return value end
    return fallback
end

function telemetry.new(saved, options)
    saved = type(saved) == "table" and saved or {}
    options = options or {}
    local self = setmetatable({}, telemetry)
    self.state = {
        activeMs = tonumber(saved.activeMs) or 0,
        counts = type(saved.counts) == "table" and saved.counts or {},
        averages = type(saved.averages) == "table" and saved.averages or {},
        warnings = tonumber(saved.warnings) or 0,
        unexpected = type(saved.unexpected) == "table" and saved.unexpected or {},
    }
    self.defaultSeconds = positive(options.defaultSeconds, 0.8)
    self.alpha = positive(options.alpha, 0.22)
    if self.alpha > 1 then self.alpha = 1 end
    self.sessionStarted = nowMs()
    self.pausedAt = nil
    self.onChange = options.onChange
    return self
end

function telemetry:measure(kind, callback)
    local started = nowMs()
    local results = { callback() }
    local elapsed = math.max(0, nowMs() - started)
    local previous = self.state.averages[kind]
    self.state.averages[kind] = previous
        and ((previous * (1 - self.alpha)) + (elapsed * self.alpha)) or elapsed
    self.state.counts[kind] = (self.state.counts[kind] or 0) + 1
    if self.onChange then self.onChange(self.state) end
    return table.unpack(results)
end

function telemetry:averageMs(kind)
    return self.state.averages[kind] or (self.defaultSeconds * 1000)
end

function telemetry:estimateMs(plan)
    local total = 0
    for kind, count in pairs(plan or {}) do
        total = total + self:averageMs(kind) * math.max(0, tonumber(count) or 0)
    end
    return math.floor(total * self:overheadFactor())
end

function telemetry:noteUnexpected(kind, count)
    kind = tostring(kind or "other")
    self.state.unexpected[kind] = (self.state.unexpected[kind] or 0)
        + math.max(1, tonumber(count) or 1)
    if self.onChange then self.onChange(self.state) end
end

function telemetry:overheadFactor()
    local measured, unexpected = 0, 0
    for _, count in pairs(self.state.counts) do measured = measured + (tonumber(count) or 0) end
    for _, count in pairs(self.state.unexpected) do unexpected = unexpected + (tonumber(count) or 0) end
    if unexpected == 0 then return 1 end
    -- A mar tapasztalt akadalyok gyakorisagat legfeljebb +100% tartalekkent
    -- vetitjuk ra a hatralevo tervre. A tenyleges atlagidok ettol fuggetlenul
    -- tovabbra is muvelettipusonkent tanulnak.
    return 1 + math.min(1, unexpected / math.max(10, measured))
end

function telemetry:elapsedMs()
    local session = self.pausedAt and (self.pausedAt - self.sessionStarted)
        or (nowMs() - self.sessionStarted)
    return self.state.activeMs + math.max(0, session)
end

function telemetry:pause()
    if not self.pausedAt then self.pausedAt = nowMs() end
end

function telemetry:resume()
    if not self.pausedAt then return end
    self.state.activeMs = self.state.activeMs + math.max(0, self.pausedAt - self.sessionStarted)
    self.sessionStarted = nowMs()
    self.pausedAt = nil
end

function telemetry:addWarning()
    self.state.warnings = self.state.warnings + 1
    self:noteUnexpected("warning", 1)
end

function telemetry:snapshot()
    local result = {
        activeMs = self:elapsedMs(),
        counts = {},
        averages = {},
        warnings = self.state.warnings,
        unexpected = {},
    }
    for key, value in pairs(self.state.counts) do result.counts[key] = value end
    for key, value in pairs(self.state.averages) do result.averages[key] = value end
    for key, value in pairs(self.state.unexpected) do result.unexpected[key] = value end
    return result
end

function telemetry.formatDuration(milliseconds)
    local seconds = math.max(0, math.floor((tonumber(milliseconds) or 0) / 1000))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds % 60)
end

return telemetry
