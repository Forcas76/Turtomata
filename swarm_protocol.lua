-- Elkülönitett, verziozott csapatmunka-uzenetek.
local protocol = {
    VERSION = 2,
    CHANNEL = "turtomata.swarm.v2",
}

function protocol.message(kind, fields)
    local value = fields or {}
    value.type = kind
    value.version = protocol.VERSION
    return value
end

function protocol.valid(value, kind)
    return type(value) == "table" and value.version == protocol.VERSION
        and (kind == nil or value.type == kind)
        and type(value.jobId) == "string"
end

return protocol
