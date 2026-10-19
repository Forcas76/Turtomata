"""Action counter and coverage probe for the production ore_scanner.lua.

This is deliberately not a second implementation of the scanner.  It loads the
real Lua module through Lupa and supplies a deterministic in-memory turtle/world.
It is intended as a baseline for route simulations, not as a production test.

Examples:
    python tests/simulation_lua_baseline.py
    python tests/simulation_lua_baseline.py --lengths 1 2 16 32 --json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


HARNESS = r'''
fs = {
    exists = function(path) return path == "ore_targets.txt" end,
    open = function()
        return { readAll = function() return "{}" end, close = function() end }
    end,
}
textutils = {
    unserializeJSON = function()
        return {
            version = 1,
            selected = { ["minecraft:coal_ore"] = true },
            custom = {},
        }
    end,
}

local vectors = {
    [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 },
}

local function key(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function copyKeys(source)
    local result = {}
    for k, v in pairs(source) do result[k] = v end
    return result
end

package.loaded["ore_scanner"] = nil
local Scanner = require("ore_scanner")

function run_scanner_probe(mode, branchLength, skipStep, oreKeys,
        maxDepth, maxBlocks, torchInterval)
    local pose = { x = 0, y = 0, z = 0, heading = 0 }
    local world = {}
    if oreKeys then
        for _, oreKey in ipairs(oreKeys) do
            world[oreKey] = "minecraft:coal_ore"
        end
    end
    local inspected = {}
    local mined = {}
    local counts = {
        horizontalMoves = 0,
        verticalMoves = 0,
        quarterTurns = 0,
        horizontalInspects = 0,
        upInspects = 0,
        downInspects = 0,
        checkpoints = 0,
        torchCallbacks = 0,
        torchPlacements = 0,
        oreDigs = 0,
    }

    local function target(move)
        if move.kind == "u" then return pose.x, pose.y + 1, pose.z end
        if move.kind == "d" then return pose.x, pose.y - 1, pose.z end
        local vector = vectors[move.heading]
        return pose.x + vector.x, pose.y, pose.z + vector.z
    end

    local function face(targetHeading)
        local difference = (targetHeading - pose.heading) % 4
        counts.quarterTurns = counts.quarterTurns
            + math.min(difference, 4 - difference)
        pose.heading = targetHeading
    end

    local function inspect(move, counterName)
        counts[counterName] = counts[counterName] + 1
        local x, y, z = target(move)
        local targetKey = key(x, y, z)
        inspected[targetKey] = (inspected[targetKey] or 0) + 1
        local name = world[targetKey]
        if not name then return false end
        return true, { name = name }
    end

    turtle = {
        inspect = function()
            return inspect({ kind = "h", heading = pose.heading }, "horizontalInspects")
        end,
        inspectUp = function()
            return inspect({ kind = "u" }, "upInspects")
        end,
        inspectDown = function()
            return inspect({ kind = "d" }, "downInspects")
        end,
    }

    local api = {
        maxDepth = maxDepth,
        maxBlocks = maxBlocks,
        fuelReserve = 2,
        getPose = function()
            return { x = pose.x, y = pose.y, z = pose.z, heading = pose.heading }
        end,
        face = face,
        moveOpen = function(move)
            if move.kind == "h" then
                face(move.heading)
                counts.horizontalMoves = counts.horizontalMoves + 1
            else
                counts.verticalMoves = counts.verticalMoves + 1
            end
            pose.x, pose.y, pose.z = target(move)
            return true
        end,
        digOre = function(move)
            local x, y, z = target(move)
            local targetKey = key(x, y, z)
            if world[targetKey] ~= "minecraft:coal_ore" then
                return false, "changed"
            end
            world[targetKey] = nil
            mined[targetKey] = true
            counts.oreDigs = counts.oreDigs + 1
            return true
        end,
        ensureFuel = function() return true end,
        shouldStop = function() return false end,
        checkpoint = function() counts.checkpoints = counts.checkpoints + 1 end,
        service = function() return true end,
        placeBranchTorch = function(_, step)
            counts.torchCallbacks = counts.torchCallbacks + 1
            if torchInterval > 0 and step % torchInterval == 0 then
                counts.torchPlacements = counts.torchPlacements + 1
            end
            return true
        end,
    }

    local skip = nil
    if skipStep and skipStep > 0 then
        skip = { [key(skipStep, 0, 0)] = true }
    end
    local ok, reason = Scanner.scanBranch(
        "right", branchLength, mode, api, skip
    )
    local remainingOre = {}
    for oreKey, name in pairs(world) do
        if name == "minecraft:coal_ore" then remainingOre[oreKey] = true end
    end
    return {
        ok = ok,
        reason = reason,
        counts = counts,
        inspected = copyKeys(inspected),
        mined = copyKeys(mined),
        remainingOre = remainingOre,
        pose = copyKeys(pose),
    }
end
'''


def make_runtime() -> LuaRuntime:
    lua = LuaRuntime(unpack_returned_tuples=True)
    root_pattern = str(ROOT / "?.lua").replace("\\", "/")
    init_pattern = str(ROOT / "?/init.lua").replace("\\", "/")
    lua.execute(
        f'package.path = "{root_pattern};{init_pattern};" .. package.path'
    )
    lua.execute(HARNESS)
    return lua


def expected_surfaces(mode: int, length: int) -> set[str]:
    result: set[str] = set()
    for x in range(1, length + 1):
        if mode == 1:  # 1x2: lower and upper observation levels
            result.update(
                {
                    f"{x},0,-1", f"{x},0,1", f"{x},-1,0",
                    f"{x},1,-1", f"{x},1,1", f"{x},2,0",
                }
            )
        else:  # 1x3: centre, upper and lower observation levels
            result.update(
                {
                    f"{x},0,-1", f"{x},0,1",
                    f"{x},1,-1", f"{x},1,1", f"{x},2,0",
                    f"{x},-1,-1", f"{x},-1,1", f"{x},-2,0",
                }
            )
    end_levels = (0, 1) if mode == 1 else (-1, 0, 1)
    result.update(f"{length + 1},{y},0" for y in end_levels)
    return result


def lua_keys(table) -> set[str]:
    return {str(key) for key, value in table.items() if value}


def deterministic_vein(length: int) -> list[str]:
    """Separated veins with one ore deliberately beyond depth four."""
    result: list[str] = []
    # Keep seeds apart so each bounded DFS invocation is independently observable.
    for x in range(2, length + 1, 5):
        result.extend(
            [
                f"{x},0,1", f"{x},0,2", f"{x},0,3", f"{x},1,3",
                f"{x},1,4",
            ]
        )
    return result


def table_to_dict(table) -> dict[str, int]:
    return {str(key): int(value) for key, value in table.items()}


def run_case(
    lua: LuaRuntime,
    *,
    mode: int,
    length: int,
    skip_step: int | None,
    ores: Iterable[str],
    max_depth: int,
    max_blocks: int,
    torch_interval: int,
) -> dict:
    ore_list = list(ores)
    ore_table = lua.table_from(ore_list)
    result = lua.globals().run_scanner_probe(
        mode,
        length,
        skip_step,
        ore_table,
        max_depth,
        max_blocks,
        torch_interval,
    )
    counts = table_to_dict(result["counts"])
    actual = lua_keys(result["inspected"])
    expected = expected_surfaces(mode, length)
    missing = expected - actual
    extra = actual - expected
    pose = {str(k): int(v) for k, v in result["pose"].items()}
    return {
        "mode": f"1x{mode + 1}",
        "length": length,
        "skip_step": skip_step,
        "ok": bool(result["ok"]),
        "reason": result["reason"],
        **counts,
        "scannerMoves": counts["horizontalMoves"] + counts["verticalMoves"],
        # Current branch_miner also traverses the mined branch out and back.
        "currentMiningAndScannerMoves": 2 * length
        + counts["horizontalMoves"]
        + counts["verticalMoves"],
        "expectedSurfaceTargets": len(expected),
        "inspectedExpectedTargets": len(expected & actual),
        "missingSurfaceTargets": len(missing),
        "extraVeinInspects": len(extra),
        "minedOre": len(lua_keys(result["mined"])),
        "remainingOre": len(lua_keys(result["remainingOre"])),
        "returnedToAnchor": pose.get("x") == 0
        and pose.get("y") == 0
        and pose.get("z") == 0
        and pose.get("heading") == 0,
        "missing": sorted(missing),
    }


def print_table(title: str, rows: list[dict]) -> None:
    print(f"\n{title}")
    print(
        "mode  L  Hmove Vmove turns inspect checkpoints torch "
        "mine+scan coverage missing ore/left anchor"
    )
    for row in rows:
        inspections = (
            row["horizontalInspects"] + row["upInspects"] + row["downInspects"]
        )
        print(
            f"{row['mode']:>4} {row['length']:>2} "
            f"{row['horizontalMoves']:>6} {row['verticalMoves']:>5} "
            f"{row['quarterTurns']:>5} {inspections:>7} "
            f"{row['checkpoints']:>11} {row['torchPlacements']:>5} "
            f"{row['currentMiningAndScannerMoves']:>9} "
            f"{row['inspectedExpectedTargets']:>3}/{row['expectedSurfaceTargets']:<3} "
            f"{row['missingSurfaceTargets']:>7} "
            f"{row['minedOre']:>3}/{row['remainingOre']:<3} "
            f"{str(row['returnedToAnchor']):>6}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lengths", nargs="+", type=int, default=[1, 2, 16, 32])
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--max-blocks", type=int, default=16)
    parser.add_argument("--torch-interval", type=int, default=3)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if any(length < 1 for length in args.lengths):
        parser.error("Every branch length must be at least 1.")

    lua = make_runtime()
    baseline: list[dict] = []
    skipped: list[dict] = []
    veins: list[dict] = []
    for mode in (1, 2):
        for length in args.lengths:
            common = {
                "lua": lua,
                "mode": mode,
                "length": length,
                "max_depth": args.max_depth,
                "max_blocks": args.max_blocks,
                "torch_interval": args.torch_interval,
            }
            baseline.append(run_case(**common, skip_step=None, ores=[]))
            skipped.append(
                run_case(
                    **common,
                    skip_step=max(1, length // 2),
                    ores=[],
                )
            )
            veins.append(
                run_case(
                    **common,
                    skip_step=None,
                    ores=deterministic_vein(length),
                )
            )

    payload = {
        "description": "Production ore_scanner.lua action/coverage probe",
        "baseline": baseline,
        "oneSkippedCell": skipped,
        "deterministicVeins": veins,
    }
    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print_table("EMPTY CORRIDOR / NO SKIP", baseline)
        print_table("EMPTY CORRIDOR / ONE CURRENT-STYLE SKIPPED CELL", skipped)
        print_table("DETERMINISTIC VEINS / ONE ORE BEYOND DEPTH FOUR", veins)

    failed = [row for row in baseline if not row["ok"] or not row["returnedToAnchor"]]
    failed.extend(
        row for row in baseline if row["missingSurfaceTargets"] != 0
    )
    if failed:
        raise SystemExit("Baseline scanner coverage/return invariant failed.")


if __name__ == "__main__":
    main()
