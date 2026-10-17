package.loaded["work_estimator"] = nil
local Estimator = require("work_estimator")

local branch = Estimator.branch({
    tunnelMode = 1, mainLength = 6, startOffset = 0,
    branchLength = 2, branchSpacing = 3,
    torchEnabled = false, oreScanEnabled = false,
}, { mainCompleted = 0, homeDistance = 0, initial = true })
assert(branch.totalActions == 74, "Hibas 1x2 branch keplet: " .. branch.totalActions)
assert(Estimator.durationMs(branch, 0.8) == 59200)

local tunnel = Estimator.branch({
    tunnelMode = 3, mainLength = 1, startOffset = 0,
    torchEnabled = false,
}, { mainCompleted = 0, homeDistance = 0, initial = true })
assert(tunnel.totalActions == 25, "Hibas 3x3 keplet: " .. tunnel.totalActions)

local area = Estimator.excavator({
    width = 2, depth = 2, height = 2, torchEnabled = false,
}, { baseCompleted = 0, visited = 0 })
assert(area.totalActions == 16, "Hibas teruletkeplet: " .. area.totalActions)

local remoteArea = Estimator.excavator({
    width = 2, depth = 2, height = 2, torchEnabled = false,
    remoteStart = {
        enabled = true,
        base = { x = 0, y = 64, z = 0, heading = 0 },
        work = { x = 3, y = 65, z = -2, heading = 1 },
    },
}, { baseCompleted = 0, visited = 0 })
assert(remoteArea.plan.move == area.plan.move + 12,
    "A koordinatas oda-vissza ut nincs a teruletbecslesben.")
assert(remoteArea.plan.turn == area.plan.turn + 4)

local nether = Estimator.nether({
    mode = 2, length = 1, torchEnabled = false,
}, { completed = 0, pathLength = 0 })
assert(nether.totalActions == 20, "Hibas Nether-keplet: " .. nether.totalActions)

local coordinate = Estimator.coordinate(
    { x = 0, y = 64, z = 0, heading = 0 },
    { x = 2, y = 65, z = -2 }
)
assert(coordinate.plan.move == 5)
assert(coordinate.totalActions == 9)

package.loaded["telemetry"] = nil
local Telemetry = require("telemetry")
local telemetry = Telemetry.new({}, { defaultSeconds = 0.8 })
assert(telemetry:estimateMs({ move = 10 }) == 8000)
telemetry:noteUnexpected("blocked_move", 1)
assert(telemetry:estimateMs({ move = 10 }) == 8800)

return true
