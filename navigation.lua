-- Kozos relativ navigacios mag. Minden fizikai mozgas ezen keresztul menjen.

local navigation = {}
navigation.__index = navigation

local DEFAULT_VECTORS = {
    [0] = { x = 0, z = 1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 },
    [3] = { x = -1, z = 0 },
}

local function copyMove(move)
    if move.kind == "h" then return { kind = "h", heading = move.heading } end
    return { kind = move.kind }
end

local function copyPose(pose)
    return {
        x = tonumber(pose and pose.x) or 0,
        y = tonumber(pose and pose.y) or 0,
        z = tonumber(pose and pose.z) or 0,
        heading = tonumber(pose and pose.heading) or 0,
    }
end

local function samePosition(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function result(ok, code, reason, retryable)
    return { ok = ok, code = code, reason = reason, retryable = retryable == true }
end

function navigation.inverse(move)
    if move.kind == "u" then return { kind = "d" } end
    if move.kind == "d" then return { kind = "u" } end
    return { kind = "h", heading = (move.heading + 2) % 4 }
end

function navigation.new(options)
    options = options or {}
    local saved = type(options.state) == "table" and options.state or {}
    local self = setmetatable({}, navigation)
    self.vectors = options.vectors or DEFAULT_VECTORS
    self.state = {
        pose = copyPose(saved.pose or options.pose),
        path = type(saved.path) == "table" and saved.path or {},
        pending = saved.pending,
        anchors = type(saved.anchors) == "table" and saved.anchors or {},
    }
    self.checkpointHandler = options.checkpoint
    self.telemetry = options.telemetry
    self.ensureFuel = options.ensureFuel
    self.onBlocked = options.onBlocked
    self.retryLimit = tonumber(options.retryLimit) or 20
    return self
end

function navigation:_checkpoint(reason)
    if self.checkpointHandler then self.checkpointHandler(self:snapshot(), reason) end
end

function navigation:snapshot()
    local path, anchors = {}, {}
    for index, move in ipairs(self.state.path) do path[index] = copyMove(move) end
    for name, anchor in pairs(self.state.anchors) do
        anchors[name] = { index = anchor.index, pose = copyPose(anchor.pose) }
    end
    return {
        pose = copyPose(self.state.pose),
        path = path,
        pending = self.state.pending and {
            operation = self.state.pending.operation,
            move = self.state.pending.move and copyMove(self.state.pending.move) or nil,
            before = self.state.pending.before and copyPose(self.state.pending.before) or nil,
            heading = self.state.pending.heading,
            turn = self.state.pending.turn and {
                before = copyPose(self.state.pending.turn.before),
                heading = self.state.pending.turn.heading,
            } or nil,
        } or nil,
        anchors = anchors,
    }
end

function navigation:getPose()
    return copyPose(self.state.pose)
end

function navigation:setPose(pose)
    self.state.pose = copyPose(pose)
    self:_checkpoint("pose_set")
end

function navigation:distanceTo(x, y, z)
    local pose = self.state.pose
    return math.abs(pose.x - x) + math.abs(pose.y - y) + math.abs(pose.z - z)
end

function navigation:distanceHome()
    local home = self.state.anchors.home and self.state.anchors.home.pose
        or { x = 0, y = 0, z = 0 }
    return self:distanceTo(home.x, home.y, home.z)
end

function navigation:_turn(delta, action)
    local parent = self.state.pending
    local turn = { operation = "turn", before = self:getPose(),
        heading = (self.state.pose.heading + delta) % 4 }
    if parent then parent.turn = turn
    else self.state.pending = turn end
    self:_checkpoint("before_turn")
    local ok = self.telemetry and self.telemetry:measure("turn", action) or action()
    if ok ~= false then self.state.pose.heading = turn.heading end
    if parent then parent.turn = nil else self.state.pending = nil end
    self:_checkpoint(ok == false and "turn_failed" or "turn")
    if ok == false then return result(false, "turn_failed", "Nem tudok fordulni.") end
    return result(true, "ok")
end

function navigation:_turnRight()
    return self:_turn(1, turtle.turnRight)
end

function navigation:_turnLeft()
    return self:_turn(3, turtle.turnLeft)
end

function navigation:turnRight() return self:_turnRight() end
function navigation:turnLeft() return self:_turnLeft() end

function navigation:face(target)
    target = target % 4
    local difference = (target - self.state.pose.heading) % 4
    if difference == 1 then return self:_turnRight() end
    if difference == 3 then return self:_turnLeft() end
    if difference == 2 then
        local first = self:_turnRight()
        if not first.ok then return first end
        return self:_turnRight()
    end
    return result(true, "ok")
end

function navigation:_positionAfter(pose, move)
    local nextPose = copyPose(pose)
    if move.kind == "u" then nextPose.y = nextPose.y + 1
    elseif move.kind == "d" then nextPose.y = nextPose.y - 1
    else
        local vector = self.vectors[move.heading]
        nextPose.x = nextPose.x + vector.x
        nextPose.z = nextPose.z + vector.z
        nextPose.heading = move.heading
    end
    return nextPose
end

function navigation:_pathEndpoint(path)
    local home = self.state.anchors.home and self.state.anchors.home.pose
        or { x = 0, y = 0, z = 0, heading = 0 }
    local pose = copyPose(home)
    for _, move in ipairs(path) do pose = self:_positionAfter(pose, move) end
    return pose
end

function navigation:recoverPending()
    local pending = self.state.pending
    if not pending then return result(true, "ok") end
    return result(false, "uncertain_pose",
        "Fuggo fizikai muvelet: a valos helyzetet ellenorizni kell.")
end

-- A hivonak fizikailag ellenorzott poziciot es iranyt kell atadnia.
-- A mentesben szereplo pose ehhez onmagaban nem eleg bizonyitek.
function navigation:resolvePending(actual)
    local pending = self.state.pending
    if not pending then return result(true, "ok") end
    if type(actual) ~= "table" or type(actual.x) ~= "number"
        or type(actual.y) ~= "number" or type(actual.z) ~= "number"
        or type(actual.heading) ~= "number" then
        return result(false, "bad_pose", "Ellenorzott helyzet es irany kell.")
    end
    local before = pending.before or self:_pathEndpoint(self.state.path)
    local after
    if pending.operation == "turn" then
        after = copyPose(before)
        after.heading = pending.heading
    elseif pending.move then
        local move = pending.operation == "pop"
            and navigation.inverse(pending.move) or pending.move
        after = self:_positionAfter(before, move)
    else
        return result(false, "bad_pending", "Ismeretlen fuggoben levo muvelet.")
    end
    local wasBefore = samePosition(actual, before)
    local wasAfter = samePosition(actual, after)
    if pending.operation == "turn" then
        wasBefore = wasBefore and actual.heading == before.heading
        wasAfter = wasAfter and actual.heading == after.heading
    end
    if not wasBefore and not wasAfter then
        return result(false, "pose_mismatch", "Nem egyezik a lepes ket oldalan.")
    end
    if wasAfter and not wasBefore and pending.operation == "push" then
        self.state.path[#self.state.path + 1] = copyMove(pending.move)
    elseif wasAfter and not wasBefore and pending.operation == "pop" then
        table.remove(self.state.path)
    end
    self.state.pose = copyPose(actual)
    self.state.pending = nil
    self:_checkpoint("pending_resolved")
    return result(true, "ok")
end

function navigation:step(move, options)
    move = copyMove(move)
    self.state.pending = {
        operation = "step",
        move = copyMove(move),
        before = self:getPose(),
    }
    self:_checkpoint("before_step")
    local moved = self:_tryMove(move, options)
    self.state.pending = nil
    self:_checkpoint(moved.ok and "after_step" or "step_failed")
    return moved
end

function navigation:_physicalMove(move)
    if self.ensureFuel then
        local fuelOk, reason = self.ensureFuel(1, self:distanceHome())
        if not fuelOk then return result(false, "fuel", reason or "Nincs fuel a mozgasra.") end
    end
    local facing
    if move.kind == "h" then
        facing = self:face(move.heading)
        if not facing.ok then return facing end
    end
    local action, kind
    if move.kind == "h" then action, kind = turtle.forward, "move"
    elseif move.kind == "u" then action, kind = turtle.up, "move_vertical"
    elseif move.kind == "d" then action, kind = turtle.down, "move_vertical"
    else return result(false, "bad_move", "Ismeretlen navigacios lepes.") end
    local ok = self.telemetry and self.telemetry:measure(kind, action) or action()
    if not ok then return result(false, "blocked", "Akadaly van a tervezett utvonalon.", true) end
    self.state.pose = self:_positionAfter(self.state.pose, move)
    self:_checkpoint("physical_move")
    return result(true, "ok")
end

function navigation:_tryMove(move, options)
    options = options or {}
    local limit = tonumber(options.retryLimit) or self.retryLimit
    for _ = 1, math.max(1, limit) do
        local moved = self:_physicalMove(move)
        if moved.ok or not moved.retryable then return moved end
        if self.telemetry and self.telemetry.noteUnexpected then
            self.telemetry:noteUnexpected("blocked_move", 1)
        end
        local handler = options.onBlocked or self.onBlocked
        if not handler then return moved end
        local handled = handler(move, moved, options)
        if not handled or handled.action ~= "retry" then
            return handled and handled.result or moved
        end
    end
    return result(false, "retry_limit", "Tul sok sikertelen mozgasi kiserlet.")
end

function navigation:push(move, options)
    move = copyMove(move)
    self.state.pending = { operation = "push", move = copyMove(move),
        before = self:getPose() }
    self:_checkpoint("before_push")
    local moved = self:_tryMove(move, options)
    if not moved.ok then
        self.state.pending = nil
        self:_checkpoint("push_failed")
        return moved
    end
    self.state.path[#self.state.path + 1] = move
    self.state.pending = nil
    self:_checkpoint("after_push")
    return moved
end

function navigation:pop(options)
    local move = self.state.path[#self.state.path]
    if not move then return result(true, "at_anchor") end
    self.state.pending = { operation = "pop", move = copyMove(move),
        before = self:getPose() }
    self:_checkpoint("before_pop")
    local moved = self:_tryMove(navigation.inverse(move), options)
    if not moved.ok then
        self.state.pending = nil
        self:_checkpoint("pop_failed")
        return moved
    end
    table.remove(self.state.path)
    self.state.pending = nil
    self:_checkpoint("after_pop")
    return moved
end

function navigation:forward(options)
    return self:push({ kind = "h", heading = self.state.pose.heading }, options)
end

function navigation:up(options) return self:push({ kind = "u" }, options) end
function navigation:down(options) return self:push({ kind = "d" }, options) end

function navigation:setAnchor(name)
    self.state.anchors[name] = { index = #self.state.path, pose = self:getPose() }
    self:_checkpoint("anchor_" .. tostring(name))
end

function navigation:returnToAnchor(name, options)
    local anchor = self.state.anchors[name]
    if not anchor then return result(false, "missing_anchor", "Nincs ilyen navigacios horgony: " .. tostring(name)) end
    while #self.state.path > anchor.index do
        local moved = self:pop(options)
        if not moved.ok then return moved end
    end
    return self:face(anchor.pose.heading)
end

function navigation:returnHome(options)
    if not self.state.anchors.home then
        self.state.anchors.home = { index = 0, pose = self:_pathEndpoint({}) }
    end
    return self:returnToAnchor("home", options)
end

function navigation:clonePath(fromIndex)
    local resultPath = {}
    for index = (fromIndex or 0) + 1, #self.state.path do
        resultPath[#resultPath + 1] = copyMove(self.state.path[index])
    end
    return resultPath
end

function navigation:replay(path, options)
    for _, move in ipairs(path or {}) do
        local moved = self:push(move, options)
        if not moved.ok then return moved end
    end
    return result(true, "ok")
end

function navigation:goTo(target, order, options)
    options = options or {}
    order = order or { "y", "x", "z" }
    local function headingFor(axis, positive)
        local expected = positive and 1 or -1
        for candidate = 0, 3 do
            if self.vectors[candidate][axis] == expected then return candidate end
        end
        return nil
    end
    for _, axis in ipairs(order) do
        while self.state.pose[axis] ~= target[axis] do
            if options.shouldStop and options.shouldStop() then
                return result(false, "stopped", "Felhasznaloi leallitas.")
            end
            local moved
            if axis == "y" then
                moved = self.state.pose.y < target.y and self:up(options) or self:down(options)
            else
                local direction = headingFor(axis, self.state.pose[axis] < target[axis])
                if direction == nil then
                    return result(false, "bad_vectors", "A navigacios iranyvektorok hianyosak.")
                end
                local faced = self:face(direction)
                if not faced.ok then return faced end
                moved = self:forward(options)
            end
            if not moved.ok then return moved end
        end
    end
    if target.heading ~= nil then return self:face(target.heading) end
    return result(true, "ok")
end

return navigation
