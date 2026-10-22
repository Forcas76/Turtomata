"""Deterministic voxel/action simulator; never controls a real turtle.

Compares complete routes, including return to the same pose. Time is a
weighted model, not measured Minecraft time. Fuel counts successful moves.
"""

from __future__ import annotations

import argparse
import csv
import heapq
import itertools
import json
import math
import random
import statistics
from collections import Counter
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


VECTORS = {0: (0, 0, 1), 1: (1, 0, 0), 2: (0, 0, -1), 3: (-1, 0, 0)}
DELTAS = {**VECTORS, "up": (0, 1, 0), "down": (0, -1, 0)}
INVERSE = {0: 2, 1: 3, 2: 0, 3: 1, "up": "down", "down": "up"}
KINDS = ("horizontal", "vertical", "turn", "inspect", "dig", "place")
PROFILES = {
    "uniform_08": dict.fromkeys(KINDS, 0.8),
    "animated_08": {"horizontal": .8, "vertical": .8, "turn": .8,
                    "inspect": .05, "dig": .8, "place": .8},
    "cheap_turns": {"horizontal": .8, "vertical": .8, "turn": .2,
                    "inspect": .05, "dig": .8, "place": .8},
    "expensive_turns": {"horizontal": .4, "vertical": .4, "turn": .8,
                        "inspect": .05, "dig": .8, "place": .8},
}
NAMES = {
    "current": "Jelenlegi útvonal",
    "separate_local": "Külön keresés, helyi optimalizálás",
    "separate_layers": "Külön keresés, hosszanti rétegek",
    "fused_local": "Összevont ásás + helyi keresés",
    "fused_layers": "Összevont ásás + hosszanti rétegek",
    "area_2": "Terület: két réteg/menet",
    "area_3": "Terület: három réteg/menet",
    "tunnel_current": "3×3: szeletenként középre vissza",
    "tunnel_snake": "3×3: váltott szélről induló szeletek",
}


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def quarter_turns(a, b):
    difference = (b - a) % 4
    return min(difference, 4 - difference)


def levels_for(height):
    return (0, 1) if height == 2 else (-1, 0, 1)


def boundary_targets(length, levels):
    result = set()
    for z in range(1, length + 1):
        for y in levels:
            result.update({(-1, y, z), (1, y, z)})
        result.update({(0, min(levels) - 1, z), (0, max(levels) + 1, z)})
    result.update((0, y, length + 1) for y in levels)
    return result


def make_ores(length, levels, seed, interval):
    """Identical finite veins for every candidate, outside required tunnel.

    Small perpendicular chains all have an exposed boundary root. Protect
    one backing block per planned wall torch to keep supports comparable.
    """
    if seed is None:
        return set()
    rng = random.Random(seed)
    protected = {(-2, 0, z) for z in range(interval, length + 1, interval)} if interval else set()
    ores = set()
    for root in sorted(boundary_targets(length, levels)):
        if rng.random() >= .07:
            continue
        if root[0]:
            direction = (-1 if root[0] < 0 else 1, 0, 0)
        elif root[1] < min(levels):
            direction = (0, -1, 0)
        elif root[1] > max(levels):
            direction = (0, 1, 0)
        else:
            direction = (0, 0, 1)
        cell = root
        for _ in range(rng.randint(1, 3)):
            if cell in protected:
                break
            ores.add(cell)
            cell = add(cell, direction)
    return ores


@dataclass
class Result:
    family: str
    size: str
    pattern: str
    profile: str
    seed: int | None
    torch_interval: int
    counts: dict
    fuel: int
    seconds: float
    required: int
    covered: int
    ore_expected: int
    ore_mined: int
    torches: int


class World:
    def __init__(self, mandatory, origin_air=(), ores=()):
        self.mandatory = set(mandatory)
        self.air = set(origin_air)
        self.initial_air = set(origin_air)
        self.ores = set(ores)
        self.initial_ores = set(ores)
        self.mined_ores = set()
        self.dug = set()
        self.inspected = set()
        self.torches = set()
        self.pose = (0, 0, 0)
        self.heading = 0
        self.counts = Counter()

    def block(self, cell):
        if cell in self.torches:
            return "torch"
        if cell in self.air:
            return "air"
        return "ore" if cell in self.ores else "stone"

    def face(self, heading):
        self.counts["turn"] += quarter_turns(self.heading, heading)
        self.heading = heading

    def target(self, direction):
        return add(self.pose, DELTAS[direction])

    def inspect(self, direction):
        if isinstance(direction, int):
            self.face(direction)
        cell = self.target(direction)
        self.counts["inspect"] += 1
        self.inspected.add(cell)
        return self.block(cell)

    def dig(self, direction):
        if isinstance(direction, int):
            self.face(direction)
        cell = self.target(direction)
        if self.block(cell) == "air":
            return
        assert self.block(cell) != "torch", ("Destroyed torch", cell)
        self.counts["dig"] += 1
        self.dug.add(cell)
        if cell in self.ores:
            self.mined_ores.add(cell)
            self.ores.remove(cell)
        self.air.add(cell)

    def clear(self, direction):
        if self.inspect(direction) != "air":
            self.dig(direction)

    def move(self, direction, digging=False):
        if isinstance(direction, int):
            self.face(direction)
        target = self.target(direction)
        if digging and self.block(target) != "air":
            assert target in self.mandatory, ("Dig outside work volume", target)
            self.clear(direction)
        assert self.block(target) == "air", ("Blocked move", self.pose, target)
        self.pose = target
        self.counts["horizontal" if isinstance(direction, int) else "vertical"] += 1

    def vertical_to(self, y, digging=False):
        while self.pose[1] != y:
            self.move("up" if self.pose[1] < y else "down", digging)

    def go(self, target, order=(1, 0, 2), digging=False):
        for axis in order:
            while self.pose[axis] != target[axis]:
                positive = self.pose[axis] < target[axis]
                direction = ("up" if positive else "down") if axis == 1 else (
                    (1 if positive else 3) if axis == 0 else (0 if positive else 2))
                self.move(direction, digging)

    def scan(self, direction):
        observer_heading = direction if isinstance(direction, int) else self.heading
        if self.inspect(direction) == "ore":
            self.mine_vein(direction)
            self.face(observer_heading)

    def mine_vein(self, first):
        """Common six-neighbour DFS, identical for all simulated patterns.

        Unlimited logical depth/block budget isolates routing from truncation.
        Each fixture is finite; explicit safety cap catches simulator mistakes.
        """
        visited = set()
        anchor = self.pose

        def visit(direction):
            cell = self.target(direction)
            assert self.inspect(direction) == "ore"
            self.dig(direction)
            self.move(direction)
            visited.add(cell)
            assert len(visited) <= 512
            for candidate in (0, 1, 2, 3, "up", "down"):
                target = self.target(candidate)
                if target not in visited and self.inspect(candidate) == "ore":
                    visit(candidate)
            self.move(INVERSE[direction])

        visit(first)
        assert self.pose == anchor

    def torch(self, z):
        saved_y, saved_heading = self.pose[1], self.heading
        self.vertical_to(0)
        self.clear(3)
        target = self.target(3)
        backing = add(target, (-1, 0, 0))
        assert self.block(backing) == "stone", ("Invalid torch backing", backing)
        assert target not in self.torches
        self.torches.add(target)
        self.air.discard(target)
        self.counts["place"] += 1
        assert target == (-1, 0, z)
        self.face(saved_heading)
        self.vertical_to(saved_y)

    def finish(self, family, size, pattern, profile, seed=None, interval=0, required=()):
        assert self.pose == (0, 0, 0) and self.heading == 0, (pattern, self.pose, self.heading)
        assert self.mandatory <= self.air, (pattern, "Incomplete excavation")
        assert set(required) <= self.inspected, (pattern, "Missing scan targets", set(required) - self.inspected)
        assert self.mined_ores == self.initial_ores, (pattern, "Ore mismatch", self.initial_ores - self.mined_ores)
        assert self.dug <= (self.mandatory | self.initial_ores | self.torches), (pattern, "Unexpected excavation")
        counts = {name: self.counts[name] for name in KINDS}
        return Result(family, size, pattern, profile, seed, interval, counts,
                      counts["horizontal"] + counts["vertical"],
                      sum(counts[k] * PROFILES[profile][k] for k in KINDS),
                      len(set(required)), len(set(required) & self.inspected),
                      len(self.initial_ores), len(self.mined_ores), len(self.torches))


def goal_specs(levels, cap):
    specs = [(y, direction) for y in levels for direction in (3, 1)]
    specs.extend(((min(levels), "down"), (max(levels), "up")))
    if cap:
        specs.extend((y, 0) for y in levels)
    return tuple(specs)


@lru_cache(maxsize=None)
def local_route(levels, cap, vertical_cost, turn_cost, end_heading=0):
    """Exact Dijkstra for a *single column*, including final facing.

    State=(height,facing,inspected-face mask). Inspection cost is constant
    because every required face is inspected once; ore detours are unknown.
    This is not a claim of globally optimal whole-mine coverage.
    """
    specs = goal_specs(levels, cap)

    def visible(y, heading, mask):
        for index, (height, direction) in enumerate(specs):
            if y == height and (not isinstance(direction, int) or direction == heading):
                mask |= 1 << index
        return mask

    first = (0, 0, visible(0, 0, 0))
    complete = (1 << len(specs)) - 1
    queue = [(0., 0, first)]
    counter = itertools.count(1)
    distances = {first: 0.}
    parents = {}
    while queue:
        cost, _, state = heapq.heappop(queue)
        if cost != distances[state]:
            continue
        y, heading, mask = state
        if mask == complete and y == 0 and heading == end_heading:
            actions = []
            while state != first:
                state, action = parents[state]
                actions.append(action)
            return tuple(reversed(actions))
        choices = [("left", y, (heading - 1) % 4, turn_cost),
                   ("right", y, (heading + 1) % 4, turn_cost)]
        if y < max(levels):
            choices.append(("up", y + 1, heading, vertical_cost))
        if y > min(levels):
            choices.append(("down", y - 1, heading, vertical_cost))
        for action, next_y, next_heading, increment in choices:
            target = (next_y, next_heading, visible(next_y, next_heading, mask))
            candidate = cost + increment
            if candidate < distances.get(target, math.inf) - 1e-10:
                distances[target] = candidate
                parents[target] = (state, action)
                heapq.heappush(queue, (candidate, next(counter), target))
    raise AssertionError("No complete local route")


def scan_local(world, levels, cap, profile, end_heading=0):
    route = local_route(levels, cap, PROFILES[profile]["vertical"], PROFILES[profile]["turn"], end_heading)
    done = set()
    specs = goal_specs(levels, cap)

    def observe():
        for index, (y, direction) in enumerate(specs):
            if index not in done and y == world.pose[1] and (
                    not isinstance(direction, int) or world.heading == direction):
                world.scan(direction)
                done.add(index)

    observe()
    for action in route:
        if action in ("left", "right"):
            world.face((world.heading + (-1 if action == "left" else 1)) % 4)
        else:
            world.move(action)
        observe()
    assert len(done) == len(specs) and world.pose[1] == 0 and world.heading == end_heading


def scan_level(world, levels, cap, travel=0, optimize=False):
    if world.pose[1] == min(levels):
        world.scan("down")
    if world.pose[1] == max(levels):
        world.scan("up")
    directions = [3, 1] + ([0] if cap else [])
    if optimize:
        def cost(order):
            facing, total = world.heading, 0
            for direction in (*order, travel):
                total += quarter_turns(facing, direction)
                facing = direction
            return total
        directions = min(itertools.permutations(directions), key=cost)
    for direction in directions:
        world.scan(direction)
    world.face(travel)


def scan_current_cell(world, levels, cap):
    # Match production scanBranchCell: center, upper, then lower; restore
    # branch facing after each horizontal level and return to center.
    for level in (0, 1) if len(levels) == 2 else (0, 1, -1):
        world.vertical_to(level)
        scan_level(world, levels, cap)
        world.vertical_to(0)


def mine_branch_cell(world, levels):
    world.clear(0)
    world.move(0)
    if 1 in levels:
        world.clear("up")
    if -1 in levels:
        world.clear("down")


def return_center(world, interval):
    for z in range(world.pose[2], 0, -1):
        world.face(2)
        if interval and z % interval == 0:
            world.torch(z)
        world.move(2)
    world.face(0)


def run_branch(length, height, pattern, profile, seed=None, interval=0):
    levels = levels_for(height)
    volume = {(0, y, z) for y in levels for z in range(1, length + 1)}
    world = World(volume, {(0, y, 0) for y in levels}, make_ores(length, levels, seed, interval))
    fused = pattern.startswith("fused")
    layers = pattern.endswith("layers")
    for z in range(1, length + 1):
        mine_branch_cell(world, levels)
        if fused:
            if layers:
                scan_level(world, levels, z == length, optimize=True)
            else:
                scan_local(world, levels, z == length, profile, end_heading=2 if z == length else 0)
    if not fused:
        return_center(world, 0)
        for z in range(1, length + 1):
            world.move(0)
            if pattern == "current":
                scan_current_cell(world, levels, z == length)
            elif layers:
                scan_level(world, levels, z == length, optimize=True)
            else:
                scan_local(world, levels, z == length, profile, end_heading=2 if z == length else 0)
    if layers:
        world.vertical_to(1)
        for z in range(length, 0, -1):
            scan_level(world, levels, z == length, travel=2, optimize=True)
            if len(levels) == 2 and interval and z % interval == 0:
                world.torch(z)
            world.move(2)
        if len(levels) == 3:
            world.vertical_to(-1)
            for z in range(1, length + 1):
                world.move(0)
                scan_level(world, levels, z == length, optimize=True)
            world.vertical_to(0)
            return_center(world, interval)
        else:
            world.vertical_to(0)
            world.face(0)
    else:
        return_center(world, interval)
    required = boundary_targets(length, levels)
    expected_torches = length // interval if interval else 0
    assert len(world.torches) == expected_torches
    return world.finish(f"branch_1x{height}", str(length), pattern, profile, seed, interval, required)


def run_area(width, depth, height, stride, profile):
    volume = {(x, y, z) for x in range(width) for y in range(height) for z in range(1, depth + 1)}
    world = World(volume, {(0, y, 0) for y in range(height)})
    for layer_pass in range(math.ceil(height / stride)):
        bottom = layer_pass * stride
        y = bottom + (1 if stride == 3 and height - bottom >= 3 else 0)
        for row in range(depth):
            z = row + 1 if layer_pass % 2 == 0 else depth - row
            xs = range(width) if (layer_pass * depth + row) % 2 == 0 else range(width - 1, -1, -1)
            for x in xs:
                world.go((x, y, z), order=(1, 2, 0), digging=True)
                if stride == 3 and y > bottom:
                    world.clear("down")
                if y + 1 < min(bottom + stride, height):
                    world.clear("up")
    world.go((0, 0, 0))
    world.face(0)
    return world.finish("area", f"{width}x{depth}x{height}", f"area_{stride}", profile)


def run_tunnel(length, snake, profile):
    volume = {(x, y, z) for x in (-1, 0, 1) for y in (0, 1, 2) for z in range(1, length + 1)}
    world = World(volume, {(0, y, 0) for y in (0, 1, 2)})
    world.move("up")

    completed_columns = set()

    def clear_column():
        key = (world.pose[0], world.pose[2])
        if key in completed_columns:
            return
        world.clear("up")
        world.clear("down")
        completed_columns.add(key)

    for z in range(1, length + 1):
        world.move(0, digging=True)
        clear_column()
        if snake:
            targets = (-1, 1) if z == 1 else ((-1,) if world.pose[0] == 1 else (1,))
        else:
            targets = (-1, 1, 0)
        for x in targets:
            while world.pose[0] != x:
                world.move(1 if world.pose[0] < x else 3, digging=True)
                clear_column()
        world.face(0)
    world.go((0, 1, 0), order=(0, 2, 1))
    world.move("down")
    world.face(0)
    return world.finish("tunnel_3x3", str(length), "tunnel_snake" if snake else "tunnel_current", profile)


def run_all(seeds):
    results = []
    patterns = ("current", "separate_local", "separate_layers", "fused_local", "fused_layers")
    for profile in PROFILES:
        for height in (2, 3):
            for length in (1, 2, 8, 16, 32, 64):
                for interval in (0, 8):
                    for pattern in patterns:
                        results.append(run_branch(length, height, pattern, profile, interval=interval))
            for seed in range(seeds):
                for interval in (0, 8):
                    for pattern in patterns:
                        results.append(run_branch(32, height, pattern, profile, seed, interval))
        for size in ((8, 16, 6), (16, 16, 6), (8, 16, 4), (4, 8, 1), (4, 8, 2), (4, 8, 3), (1, 4, 7)):
            for stride in (2, 3):
                results.append(run_area(*size, stride, profile))
        for length in (1, 2, 8, 16, 32, 64):
            for snake in (False, True):
                results.append(run_tunnel(length, snake, profile))
    # Exact movement formulas on the complete, empty, unlit branch fixtures.
    for r in results:
        if r.family.startswith("branch") and r.seed is None and r.torch_interval == 0:
            length = int(r.size)
            if r.pattern == "current":
                assert r.fuel == (6 if r.family == "branch_1x2" else 8) * length
            if r.pattern == "fused_layers":
                assert r.fuel == (2 * length + 2 if r.family == "branch_1x2" else 4 * length + 4)
    return results


def validate_lua_baseline(results):
    """Cross-check Python baseline against the real Lua scanner, not formulas."""
    from simulation_lua_baseline import make_runtime, run_case, deterministic_vein
    lua = make_runtime()
    validated, skipped, limited = [], [], []
    for r in results:
        if r.pattern != "current" or r.profile != "uniform_08" or r.seed is not None or r.torch_interval:
            continue
        height = int(r.family[-1])
        length = int(r.size)
        options = dict(lua=lua, mode=height - 1, length=length,
                       max_depth=4, max_blocks=16, torch_interval=0)
        actual = run_case(**options, skip_step=None, ores=[])
        assert actual["ok"] and actual["returnedToAnchor"] and not actual["missingSurfaceTargets"]
        assert actual["currentMiningAndScannerMoves"] == r.fuel
        assert actual["verticalMoves"] == r.counts["vertical"]
        assert actual["horizontalMoves"] == r.counts["horizontal"] - 2 * length
        assert actual["quarterTurns"] == r.counts["turn"] - 4
        inspections = sum(actual[k] for k in ("horizontalInspects", "upInspects", "downInspects"))
        assert inspections == r.counts["inspect"] - height * length
        validated.append(actual)
        if length == 32:
            skipped.append(run_case(**options, skip_step=16, ores=[]))
            limited.append(run_case(**options, skip_step=None, ores=deterministic_vein(length)))
    return {"matchedBaselines": validated, "oneSkippedCell": skipped, "depthLimitedVeins": limited}


def report(results, seeds, lua_validation):
    lines = ["# Turtomata – mozgásminták szimulációja", "", "Dátum: 2026. október 18.", "",
             "## Módszer és értelmezés", "",
             "Ez végrehajtott, determinisztikus Python voxel- és műveletszimuláció, nem Minecraftban mért futási idő. "
             "A modell minden mozgást, negyedfordulást, inspectet, bontást és lerakást külön megszámol. "
             "Egy sikeres vízszintes vagy függőleges lépés egy fuel-egység. Az idő a lent megadott súlyok összege.", "",
             "Minden út azonos pozícióból és facingből indul, majd ugyanoda és ugyanabba az irányba tér vissza. "
             "Azonos a kiásandó térfogat, az ellenőrizendő oldalfal-, padló-, mennyezet- és végfalblokkok halmaza. "
             "Minden futás assertionökkel ellenőrzi a teljes lefedettséget, a kitermelt érceket és a fáklyák számát.", "",
             "Az ércmezők az alagúton kívüli falakból induló, 1–3 blokkos determinisztikus telérek. "
             "Minden minta ugyanazt a hatirányú DFS-kitérőt használja; a fixture-ök teljes bejárásához a keresési korlát nem vágja le a teléreket. "
             "Ez a mozgásminták összehasonlítása, nem a jelenlegi limitkezelés vagy előreérzékelési gyorsítótár teljes emulációja.", "",
             "A fáklyás változatban pontosan ugyanazokra a koordinátákra kerül oldalfali fáklya, 8 blokkonként, "
             "azonos védett hátlappal. Ha az út a felső szinten halad, a lerakáshoz szükséges le/fel mozgás is költség. "
             "A már lerakott fáklyát egyik út sem bonthatja ki vagy járhatja át.", "",
             "Kizárt költségek: inventory-korlát és kiszolgálási utak, ládák kezelése, hálózat, mentés, képernyőfrissítés, "
             "gravel/víz/láva/mob, szerverlag és a jelenlegi program fix sleep várakozásai. "
             "Az eredmények ezek nélküli útvonal-mikrobenchmarkok; az időértékek nem valódi játékbeli ígéretek.", "",
             "A bontás előtti ellenőrzést egy inspect modellezi. A külön detect* hívások, az onBlocked előtti első sikertelen "
             "mozgáspróbák, az API esetleges további cooldownja és az induló cella előkészítése nincsenek külön elszámolva. "
             "A modell műveletnyoma ezért nem a teljes gyártási API-hívássorozat szó szerinti másolata.", "",
             "A helyi optimalizálás minden cellára Dijkstrával megkeresi az adott időprofil szerinti legolcsóbb "
             "(magasság, facing, vizsgált felületek) bejárást. A teljes bánya globális optimumát nem állítjuk.", "",
             "Az oldalági eredmények egyetlen oldalágra vonatkoznak, főági haladás nélkül. "
             "A helyi Dijkstra-minta időprofilonként eltérő utat is választhat, ezért ugyanazon mintanév fuelértéke profilok között változhat. "
             "A területásási modellben az induló hozzáférési oszlop szabad; éles megvalósításkor a felemelkedés a kijelölt térfogaton belül is végrehajtható.", "",
             f"Összes végrehajtott és ellenőrzött futás: **{len(results)}**. Véletlenérc-fixture-ök: **{seeds} seed/magasság/időprofil/fáklyabeállítás**.", "",
             f"A valódi Lua érckeresővel további **{len(lua_validation['matchedBaselines'])}** üres alapútvonalat is összevetettünk: "
             "a scanner vízszintes/függőleges mozgása, fordulása és inspect-száma egyezik a Python alapmintával "
             "a külön hozzáadott bányászati oda-vissza út és a bontás előtti inspectek levonása után.", "",
             "## Fő eredmények", "",
             "A 0,8 mp/művelet profilban a vizsgált 32 blokkos oldalágaknál az összevont, cellánként helyileg optimalizált "
             "bejárás a leggyorsabb. Az összevont hosszanti rétegbejárás használja a legkevesebb fuelt. "
             "Olcsóbb fordulások mellett a rétegbejárás időben is nyerhet, ezért a választás a tényleges műveleti időktől függ.", "",
             "A gyors, helyi 1×2 minta egy lehetséges cellasorrendje: alsó bal fal → fel → felső bal fal "
             "és mennyezet → megfordulás → felső jobb fal → le → alsó jobb fal és padló → menetirány. "
             "A fuel-takarékos változat ehelyett az alsó szinten kifelé, a felsőn hazafelé halad, és csak a két végén vált magasságot.", "",
             "A háromréteges területásás magasabb térfogatoknál csökkenti a bejárást, de a 4 blokk magas példánál "
             "a két réteges változat kedvezőbb. A 3×3-as alagútnál a váltott szélső oszlopból folytatott kígyózás "
             "a vizsgált esetekben azonos kitermelés mellett kevesebb mozgást és fordulást igényel.", "",
             "## Időprofilok", "", "| Profil | Vízszintes | Függőleges | Negyedfordulás | Inspect | Bontás | Lerakás |",
             "|---|---:|---:|---:|---:|---:|---:|"]
    for name, profile in PROFILES.items():
        lines.append("| " + name + " | " + " | ".join(f"{profile[k]:.2f}" for k in KINDS) + " |")
    lines += ["", "Minden idő másodperc. A uniform_08 a korábbi 0,8 mp/művelet becslés. "
              "A többi profil feltételezett érzékenységvizsgálat, nem ténylegesen mért CC:Tweaked-idő.", ""]
    for height in (2, 3):
        family = f"branch_1x{height}"
        lines += [f"## 1×{height}, 32 blokkos oldalág, érc és fáklya nélkül", "",
                  "| Minta | Vízszintes | Függőleges | Fordulás | Inspect | Bontás | Fuel | Idő, 0,8 mp/műv. |",
                  "|---|---:|---:|---:|---:|---:|---:|---:|"]
        for r in results:
            if (r.family, r.size, r.profile, r.seed, r.torch_interval) == (family, "32", "uniform_08", None, 0):
                c = r.counts
                lines.append(f"| {NAMES[r.pattern]} | {c['horizontal']} | {c['vertical']} | {c['turn']} | {c['inspect']} | {c['dig']} | {r.fuel} | {r.seconds:.1f} s |")
        lines += ["", "### Ugyanez fáklyákkal, 8 blokkonként", "",
                  "| Minta | Fuel | Fordulás | Fáklya | Idő, 0,8 mp/műv. |", "|---|---:|---:|---:|---:|"]
        for r in results:
            if (r.family, r.size, r.profile, r.seed, r.torch_interval) == (family, "32", "uniform_08", None, 8):
                lines.append(f"| {NAMES[r.pattern]} | {r.fuel} | {r.counts['turn']} | {r.torches} | {r.seconds:.1f} s |")
        lines += ["", "### Átlag determinisztikus érctelérek mellett, fáklya nélkül", "",
                  "| Minta | Átlag fuel | Átlag kitermelt érc | Átlag idő | Medián idő | P90 idő | Maximum idő |",
                  "|---|---:|---:|---:|---:|---:|---:|"]
        for pattern in ("current", "separate_local", "separate_layers", "fused_local", "fused_layers"):
            rows = [r for r in results if (r.family, r.profile, r.pattern, r.torch_interval) == (family, "uniform_08", pattern, 0) and r.seed is not None]
            times = sorted(r.seconds for r in rows)
            lines.append(f"| {NAMES[pattern]} | {statistics.mean(r.fuel for r in rows):.1f} | {statistics.mean(r.ore_mined for r in rows):.1f} | "
                         f"{statistics.mean(times):.1f} s | {statistics.median(times):.1f} s | {times[math.ceil(.9*len(times))-1]:.1f} s | {max(times):.1f} s |")
        lines += ["", "### Idő/fuel szerinti választás különböző időprofiloknál", "",
                  "| Profil | Leggyorsabb minta | Idő | Fuel | Legkisebb fuel |", "|---|---|---:|---:|---|"]
        for profile in PROFILES:
            rows = [r for r in results if (r.family, r.size, r.profile, r.seed, r.torch_interval) == (family, "32", profile, None, 0)]
            best = min(rows, key=lambda r: (r.seconds, r.fuel))
            fuel = min(rows, key=lambda r: (r.fuel, r.seconds))
            lines.append(f"| {profile} | {NAMES[best.pattern]} | {best.seconds:.1f} s | {best.fuel} | {NAMES[fuel.pattern]}: {fuel.fuel} |")
        lines.append("")
    lines += ["## Területásás, ércvizsgálat és fáklyázás nélkül", "",
              "| Méret | Minta | Kiásott blokk | Fuel | Fordulás | Idő, 0,8 mp/műv. |", "|---|---|---:|---:|---:|---:|"]
    for r in results:
        if r.family == "area" and r.profile == "uniform_08":
            lines.append(f"| {r.size} | {NAMES[r.pattern]} | {r.counts['dig']} | {r.fuel} | {r.counts['turn']} | {r.seconds:.1f} s |")
    lines += ["", "## 3×3 egyenes alagút, 32 blokk, ércvizsgálat és fáklyázás nélkül", "",
              "| Minta | Kiásott blokk | Fuel | Fordulás | Idő, 0,8 mp/műv. |", "|---|---:|---:|---:|---:|"]
    for r in results:
        if (r.family, r.size, r.profile) == ("tunnel_3x3", "32", "uniform_08"):
            lines.append(f"| {NAMES[r.pattern]} | {r.counts['dig']} | {r.fuel} | {r.counts['turn']} | {r.seconds:.1f} s |")
    lines += ["", "## A valódi Lua keresőn kimutatott lefedettségi és limitproblémák", "",
              "Ezek külön ellenőrző esetek; az eltérő kitermelésű vagy hiányos lefedettségű futásokat nem használtuk gyorsasági nyertesnek.", "",
              "| Mód, 32 blokk | Egy kihagyott cella miatt kimaradt célblokk | Limitpróba: kibányászott / hátrahagyott érc |",
              "|---|---:|---:|"]
    for skipped, limited in zip(lua_validation["oneSkippedCell"], lua_validation["depthLimitedVeins"]):
        lines.append(f"| {skipped['mode']} | {skipped['missingSurfaceTargets']} | {limited['minedOre']} / {limited['remainingOre']} |")
    lines += ["", "A limitpróba maxDepth=4, maxBlocks=16 mellett fut, a fixture szándékosan tartalmaz a mélységi kereten túli ércet. "
              "A kereső sikeresen visszatér, de a teljes érctelér kitermelését ez nem bizonyítja.", "",
              "## Értelmezés és következő lépés", "",
              "- A leggyorsabb és a legkevesebb fuelt használó minta eltérhet: a plusz függőleges mozgás csökkentheti a fordulásszámot.",
              "- A rétegenkénti út és a cellánkénti, forgásra optimalizált vizsgálat megtakarításai nem adhatók össze.",
              "- A kiásandó blokkok és vizsgálandó felületek számát nem csökkentjük. A lefedettség minden összehasonlított futásban teljes.",
              "- A fáklyák pontos helye befolyásolja az optimális utat. A felső szinten visszatérő minta a rögzített alsó fáklyapontokért külön le/fel mozog.",
              "- A gyártási érckereső külön Lua-próbája a valódi ore_scanner.lua-t futtatja; ezt a movement_simulation.py modelljétől külön kell értelmezni.",
              "- A két összevont minta korábban kezdi a keresést: az első oldalág ásása közben. A külön keresési minták megőrzik az ásás utáni vizsgálati fázist.",
              "- Következő lépésként valódi turtle-ön mérendő mozgás/fordulás/bontás/inspect/mentés idő, majd a mért súlyokkal újraszámolandó a nyertes.",
              "- A bányászati programok működését ez a szimuláció nem módosítja.", "",
              "## Újrafuttatás", "", "Python 3 és a valódi Lua-próbához a lupa csomag szükséges. A szimuláció nem fut a játékbeli computeren.", "",
              "```text", "python tests/movement_simulation.py --output-dir tervek/szimulacio --seeds 30",
              "python tests/simulation_lua_baseline.py --lengths 1 2 16 32 --json", "```", "",
              "A CSV minden egyes futás nyers műveletszámait tartalmazza; a JSON a névvel ellátott mezőket is megőrzi.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=30)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.seeds < 1:
        parser.error("--seeds must be positive")
    results = run_all(args.seeds)
    lua_validation = validate_lua_baseline(results)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    from dataclasses import asdict
    data = [asdict(r) for r in results]
    (args.output_dir / "eredmenyek.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output_dir / "lua_baseline.json").write_text(json.dumps(lua_validation, ensure_ascii=False, indent=2), encoding="utf-8")
    with (args.output_dir / "eredmenyek.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        fields = [k for k in data[0] if k != "counts"] + list(KINDS)
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in data:
            writer.writerow({**{k: v for k, v in row.items() if k != "counts"}, **row["counts"]})
    destination = args.output_dir / "szimulacios_eredmenyek.md"
    destination.write_text(report(results, args.seeds, lua_validation), encoding="utf-8")
    print(f"PASS: {len(results)} complete routes; excavation, scan coverage, ore and final poses validated.")
    print(destination)
    for height in (2, 3):
        rows = [r for r in results if (r.family, r.size, r.profile, r.seed, r.torch_interval) == (f"branch_1x{height}", "32", "uniform_08", None, 0)]
        for r in rows:
            print(f"1x{height} {r.pattern:18s} fuel={r.fuel:4d} turns={r.counts['turn']:4d} seconds={r.seconds:7.1f}")


if __name__ == "__main__":
    main()
