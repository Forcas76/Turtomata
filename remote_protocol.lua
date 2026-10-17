-- A CCTurtle tavoli felugyelet kozos Rednet protokollja.

local protocol = {
    VERSION = 1,
    STATUS = "ccturtle.status.v1",
    CONTROL = "ccturtle.control.v1",
    ACK = "ccturtle.ack.v1",
    DISCOVER_INTERVAL = 10,
    HEARTBEAT_INTERVAL = 2,
    OFFLINE_AFTER = 8,
}

function protocol.message(kind, fields)
    local value = fields or {}
    value.type = kind
    value.version = protocol.VERSION
    value.sentAt = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
    return value
end

function protocol.valid(message, kind)
    return type(message) == "table"
        and message.version == protocol.VERSION
        and (kind == nil or message.type == kind)
end

return protocol
