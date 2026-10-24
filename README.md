# Turtomata

Modular [CC:Tweaked](https://tweaked.cc/) software for mining, route building, farming, and live monitoring with Minecraft turtles. The central turtle program is `main.lua`; a Pocket Computer or regular Computer can run `remote_monitor.lua` to watch turtles and issue commands over Rednet.

**Current version:** v1.4.1 (defined in `version.lua`). The version appears in the turtle menu, the monitor's status and command pages, and the downloader menu.

The saved-job menu is always openable. It includes an active shared job and explains when no valid resumable save exists. The monitor's status page shows a compact one-word activity per turtle; Enter opens the selected turtle's detail page, while an attached monitor keeps showing the list. Torch refills request only the missing count in slot 2. After a successful update, the downloader saves its version and UTC time in `.turtomata_update.txt` and waits for Enter acknowledgement.

During an active branch, area-excavation, or route-building job, the turtle records items actually picked up by digging, grouped by item ID. On the monitor's selected-turtle detail page, press `I` or click to open the scrollable item list. Counts remain after unloading; they are forgotten when the job is completed or its save is deleted.

[Magyar dokumentáció / Hungarian documentation](README_HU.md)

> **Experimental features:** Area excavation, coordinate navigation, farming, task chains, ore scanning, automatic torch placement, and inventory-capacity prediction are still experimental. Test them in a safe area before leaving a turtle unattended.

**Experimental shared branch mining:** Place leader turtle #1 in front of the deposit chest, facing the main tunnel. Queue helpers to its right, one block apart, with the same facing; confirm each slot locally (slot 2 is one block right, slot 3 two blocks right). The slot is not a GPS measurement. Open a shared job on #1, then manually claim coordinator status on the intended Computer or Pocket Computer's Commands page. Helpers join on their own screens. Once the coordinator heartbeat is present, #1 mines **only the main tunnel** and parks one block left of base. Finished branch points are published with acknowledgements. A helper with an assigned branch can then be started locally; the coordinator serializes traffic through the narrow trunk and shared dock while helpers may mine distinct branches concurrently. The helper returns to its slot after unloading and refuelling at the original chests.

This first worker implementation is limited to **1×2/1×3 branches**; shared ore searching and torch placement are not enabled. Give helpers enough initial fuel (or fuel in slot 1) to reach the first service trip. A connection loss, uncertain move, or local stop keeps reservations and requires manual position correction/reconciliation; it does not trigger a blind return. A helper may withdraw a pending join only with a coordinator acknowledgement, or leave from its own slot when free; then the leader may close the advertisement once all helpers have left. The coordinator's Commands page also has a confirmed emergency stop, which halts all participants in place; it does not send them home. **Treat this as unverified in-game experimental code: test with two turtles in a disposable area before using valuable inventories or more workers.** A coordinator restart requires a new leader acknowledgement before further grants.

An optional chest directly behind a helper can be registered on that turtle's Shared Job menu while it is free at its starting slot. The turtle turns in place to inspect the chest and waits for coordinator acknowledgement. A returning helper may use any verified, free helper chest if its owner is confirmed away at a branch, the route is shorter than D01, and fuel is sufficient. Otherwise it uses D01 for unloading and refuelling. Helper chests never supply fuel or torches. A station lease persists until verified arrival or manual reconciliation. D01 requests use a persisted first-in, first-out queue, visible on the coordinator screen. If D01's deposit chest is full, the turtle still attempts fuel service, retains undropped items, and stops for reconciliation. The narrow corridor is still serialized: simultaneous docking, queue-aware ETA, and automatic full-chest rerouting remain planned, not enabled.

During a branch return scan, the selected turtle can receive **Skip branch scan (experimental)** from the monitor's Commands page. The request takes effect at the next branch-cell boundary, skips remaining ore inspections, but still returns through the branch and handles planned torch points. Skipped scans are counted separately from ore-free scans. Shared helper branches do not yet scan ore, so this command applies to a solo branch job.

## Getting started

On the in-game turtle or monitor Computer, fetch the installer with:

```text
pastebin get hnT1J5cK downloader
```

Then run `downloader` and select the appropriate package. Alternatively, copy the required Lua files manually and run:

```text
main
```

`downloader` without arguments opens a menu:

| Choice | Installs |
| --- | --- |
| Install turtle program (`Turtle program telepitese` in the source) | The full turtle system, Rednet telemetry, and `startup.lua` to launch `main` on boot. |
| Install monitor program (`Megfigyelo telepitese` in the source) | The Rednet monitor and `startup.lua` to launch `remote_monitor` on boot. |

The same packages can be selected from the shell with `downloader turtle` and `downloader monitor`. Installation replaces an existing `startup.lua`; the downloader uses a backup while replacing it. A successful in-program update restarts the device. The updater downloads a fresh copy of itself first, then uses that copy for the component list, so newly added components are included in one update. A failed download does not count as a successful update or trigger a success reboot.

The downloader fetches the installer itself from Pastebin, then downloads the complete package from the public GitHub repository **without a token**. Its default source is GitHub; `DOWNLOAD_SOURCE` near the top of `downloader.lua` can be changed to `pastebin`, but new modules have no Pastebin IDs. Downloads are staged before replacing working files, and a self-update checks the new Lua syntax. The downloader still points to the current `Forcas76/CCTurtle` GitHub repository until that repository is renamed and its configuration is updated.

If GitHub responds with **403** (or **429**) during an update, the downloader pauses and retries the same file. It uses GitHub's `Retry-After` or rate-limit reset header when available; otherwise it starts with a 60-second wait and increases it on repeated failures. The wait screen shows a countdown: press `R` or Enter to retry immediately, or `Q`/Esc/Backspace to cancel. A forced retry can still be rate-limited. Cancellation stops the remaining downloads and prevents an in-program success reboot. A 403 can also mean access was denied rather than a temporary limit; cancel and check repository access if waiting does not help.

Additional downloader commands:

```text
downloader main        # central system and dependencies
downloader branch      # branch miner and dependencies
downloader excavator   # area excavator and dependencies
downloader nether      # route builder and dependencies; legacy command name
downloader coordinate  # coordinate navigation and dependencies
downloader downloader  # downloader only
```

## Controls and language

Use the arrow keys and Enter in menus. On an Advanced Turtle, you can click menu rows and scroll. Backspace or Escape returns to the previous screen. At numeric prompts, an empty Enter accepts the displayed default. A job starts only after its summary and a final Enter.

**English is the default for a fresh installation.** On the turtle, choose `Settings > Language / Nyelv` to switch between English and Hungarian. On a monitor Computer or Pocket Computer, use the left/right arrows to open its Settings page and change the language there. Each device stores its choice in its own `settings.txt`, so an existing Hungarian selection remains Hungarian after an update. Some dynamic or untranslated technical messages may still appear in their original Hungarian wording.

The program's source labels are often unaccented Hungarian. The English labels below are what the localization layer displays when English is selected.

## Turtle main menu

| English menu item | Source label | Purpose |
| --- | --- | --- |
| Branch mining | `Branch mining` | Mine 1×2 or 1×3 main/side branches, or a straight 3×3 tunnel. |
| Excavate area | `Terulet kiasasa` | **Experimental:** excavate a width × depth × height volume. |
| Route building | `Utvonal keszites` | Build stairs, a protected 1×2 tunnel, or a plain 1×2 tunnel. |
| Navigate to coordinates | `Koordinatara navigalas` | **Experimental:** travel from a supplied world position to a target. |
| Farm maintenance | `Farm karbantartas` | **Experimental:** maintain crops or feed animals. |
| Task chain | `Feladatlanc` | **Experimental:** run saved steps in a chosen order. |
| Resume saved job | `Felbehagyott munka` | Preview active saves, including progress and last saved position, then resume. |
| Manage jobs | `Munka kezelese` | Configure auto-resume, release ownership, or permanently delete a selected saved job. |
| Settings | `Beallitasok` | Navigation, safety, inventory, torch, ore, and language settings. |
| Diagnostics | `Diagnosztika` | Check required modules and display the current fuel level. |
| Update program | `Program frissitese` | Run the downloader for the full turtle package and reboot on success. |
| Exit | `Kilepes` | Close `main`. |

`Manage jobs > Delete saved job` removes the selected job's resume state **and its backup** after confirmation. If a task chain is active, deleting its save also deletes its active sub-job save. Use release or deletion only when the turtle is physically at its base; deleting a save discards the position needed for a safe resume. Releasing a job does **not** delete its save. A stale branch-mining save can be deleted here before starting a new job.

On the first 1.2 startup, pre-1.2 unfinished job saves may be discarded after an explicit warning; they are not blindly auto-resumed under the new route logic. `ore_targets.txt` and general settings are kept. The saved branch-job menu also offers length, option, and physically verified relative-position corrections.

The `Settings > Navigation and general > Shared base` coordinates and facing provide defaults for *new* coordinate jobs and task chains. Changing the shared base does not relocate an existing saved job.

## Branch mining

| Mode or field | Meaning |
| --- | --- |
| `Branch 1x2` | One-block-wide, two-block-high main tunnel with side branches. |
| `Branch 1x3` | One-block-wide, three-block-high main tunnel with side branches. |
| `Egyenes 3x3` (Straight 3×3) | Straight 3×3 tunnel without side branches. The turtle moves up one block at the start; its initial level becomes the tunnel floor. |
| New job | Start from the initial position. |
| Manual resume | Travel along an already mined main tunnel to the specified distance and start a new section there. This is a fallback when a saved resume cannot be used. |
| Starting distance | Length of the already existing main tunnel to traverse for manual resume. |
| Main tunnel / Side branch | Lengths of the new main route and each left/right branch. |
| Branch spacing | Distance between side branches; default is 3. |
| Tunnel length | Length of the straight 3×3 tunnel. |

Experimental ore scanning can be enabled for 1×2 and 1×3 modes. Each side branch is excavated outward, then inspected and torched on the same return trip; the turtle no longer makes a separate full scanning trip. It follows selected veins only up to the configured depth and block limits. A previously unknown block ID containing `raw` or `ore` may have its **first vein** mined up to those limits. Later veins of that ID are skipped until the player approves it in the ore list. Unfinished physical movements require position review before resuming.

## Area excavation — experimental

Enter width (to the turtle's right), depth (forward), and height (upward from the starting level). The turtle follows a serpentine path through the volume. When another layer remains above, it may dig upward during the current pass and process two layers together. Start with a small test volume.

Area excavation can optionally start at a separate world-coordinate work point. The chest base remains where the turtle started; choose the work point and a mining facing relative to the base facing (forward, right, back, or left). The turtle returns to the original base for unloading, fuel, and torches, then navigates back to the same work point and facing. Do not move or rotate the turtle by hand once the job has begun.

## Route building

| Mode | Behavior |
| --- | --- |
| Up/down stairs | Ascend or descend one level per step, with two blocks of headroom. |
| Protected 1×2 tunnel | Enclose an exposed path with a floor, side walls, and ceiling. |
| Plain 1×2 tunnel | Mine a two-block-high path. Fill a missing floor with `minecraft:cobblestone`. |

The plain tunnel watches for water and lava ahead, above, and below. If it encounters three water-affected steps in a five-step window, or detects lava, it switches the remaining route to the protected profile. The switch is saved across restarts. Steps made before the switch are not retroactively enclosed. If a fluid cannot be sealed safely or building material is exhausted, the turtle stops rather than continuing blindly.

Without torches, slots 2–5 hold building material and slots 6–16 are mining storage. With torches, slot 2 is reserved for torches and building material uses slots 3–5. If material runs out, the turtle returns along its saved route and replenishes from the drop-off chest. The plain tunnel always uses `minecraft:cobblestone` for missing floor blocks. Torch placement is optional; failure to place one, including an empty torch slot, warns but does not abort the plain-tunnel job. The route builder's save file remains `nether_builder_state.txt` for compatibility.

## Farming and task chains — experimental

The farm turtle starts at its base. The drop-off chest is behind it, the fuel chest is above that chest, and a seed/feed chest is to the turtle's right. Slot 1 is for fuel and slot 2 for seeds or feed. The crop profile harvests only recognized, mature vanilla crops and replants them. Animal feeding is experimental: two successful `place` calls do not prove that a new animal was born. After a restart, the farm immediately makes its rounds instead of waiting for a previously saved timer.

A task chain is an editable, saved sequence. Steps can be added, changed, copied, enabled/disabled, reordered, or deleted. The turtle returns to the shared base between steps. Area excavation and farming may start at remote coordinates. Within a chain, branch mining and route building currently start only at the base; remote-start adapters for those modes are not implemented. Coordinate-farm routes require known, unobstructed walking positions. Test real farm layouts in-game before relying on automation.

## Coordinate navigation — experimental

Enter the turtle's current world X/Y/Z, facing, target X/Y/Z, and optionally its final facing. Heading convention: north = −Z, east = +X, south = +Z, west = −X. **The program does not determine its start position with GPS**; it navigates from the coordinates you provide. In open-path mode it stops and saves when blocked; in digging mode it tries to clear the route. It does not invent an unverified detour through unknown water or lava. The standalone coordinate job has no chest-unloading service.

## Live Rednet monitoring

The turtle automatically opens attached wireless modems when available. Standard Wireless and Ender Modems are supported; without a modem, local mining still works. The same `remote_monitor.lua` works on a Pocket Computer and on a regular or Advanced Computer. Multiple turtles can appear on one monitor, and multiple monitor devices can watch the same turtle.

If a Computer has a monitor peripheral attached, the status display is drawn both on its terminal and on the first detected external monitor. The terminal remains interactive. Connecting or removing a monitor while the program is running is detected. On an Advanced Monitor, turtles can be selected by touch.

Use left/right arrows on the Computer or Pocket Computer to switch between status and commands. When an external monitor is present, it **always** remains on the live status page while the Computer terminal may show commands. On the commands page, use up/down or click to choose a command and Enter to send it. Safe stop and return requires a second confirmation. The turtle acknowledges accepted commands or reports an error.

Current commands:

- Refresh data: request an immediate full status update.
- Unload and resume: for branch mining, area excavation, or route building, return to the chests at a safe point, unload/refuel/replenish, return to work, and continue.
- Stop job and return home: finish the current safe operation, return to base, and do not automatically continue.

Coordinate navigation rejects unloading requests because it has no chest service. No startup pairing is required: a monitor switched on later discovers a working turtle and receives a complete state packet. Heartbeats arrive every two seconds; after eight seconds without a signal the monitor marks it offline but keeps searching.

## Settings

| Setting | Purpose |
| --- | --- |
| Navigation and general | Starting action time, coordinate mode, shared base, fuel reserve, and language. |
| Safety and situations | Water/lava sealing, retry limits, an ordered, extensible sealing-block list, and torch-failure handling. |
| Inventory EXPERIMENTAL | Capacity check against the predicted drop of the next block. |
| Torch placement | Default enablement, intervals, and placement mode. |
| Ore scanning | Default enablement, ore list, and vein-following limits. |
| Restore defaults | Recreate common defaults, including English as the language. |

Ore IDs use `<mod_name>:<block_name>`, such as `minecraft:coal_ore`. A short vanilla name such as `coal_ore` automatically receives the `minecraft:` prefix. In the ore list, `A` adds a named custom group, `E` adds an ID, `V` opens the selected group's ID list, `D` removes/disables after confirmation, and `K` saves and exits. In the `V` list, select an ID with the arrow keys or mouse to edit it or delete it after confirmation; IDs can also be added there. Edits to built-in groups are saved as overrides. Unknown `raw`/`ore` candidates can be approved into a group or rejected there.

## Automatic torches — experimental

With torch placement enabled, slot 2 is reserved for torches and a torch chest must be placed **above the fuel chest**. The turtle returns for more when it runs out. Branch mining has separate main-route and side-branch spacing: the former counts completed main-route digs, the latter counts blocks along a branch.

On the main route, the turtle attempts the torch at the designated dig position once any side branches for that position are complete. On a side branch **without** ore scanning, it can try immediately after digging the relevant block. **With** ore scanning, it places branch torches on the return pass after inspection, avoiding an extra traversal. Side placement uses a wall; overhead placement tries to attach a wall torch above the turtle. If placement fails, it tries another side, an overhead position, then a support block if needed. In branch mining, a missed torch is a warning rather than a fatal error.

## Chest layout and reserved slots

At the starting position, point the turtle toward the intended work area:

```text
Side view (work direction ->)

  [torch chest]  (only when torches are enabled)
  [fuel chest]
  [drop-off chest] [TURTLE]
```

- The drop-off chest is directly behind the turtle; the fuel chest is above it.
- When enabled, the torch chest sits above the fuel chest.
- Slot 1 is the refuelling slot. The turtle drops non-fuel items from it; it consumes a full stack taken from the fuel chest (for example, all 64 coal items).
- Slot 2 is reserved for torches when torch placement is enabled, except in farming, where it holds seed/feed.
- Leave space above the turtle so it can reach the stacked chests.

When experimental inventory management is on, `inventory_state.txt` is refreshed whenever the turtle leaves the chests and when it detects a new block type. It checks whether the anticipated drop fits in an existing stack or a free mining slot. It returns to unload only when that item will no longer fit. The file contains one overwritten JSON state line, not a movement log.

## Saves, recovery, and run-time controls

Jobs use shared navigation code for relative position/facing, the route home, and an exact path stack. Before a movement, navigation saves a pending transaction; on restart it reconciles that transaction with the saved position to avoid applying the move twice. State writes use a temporary file and backup. **Do not manually move or turn a turtle after an unexpected shutdown**; check its physical position before resuming.

Important local data includes `settings.txt`, `work_registry.txt`, `branch_miner_state.txt`, `excavator_state.txt`, `nether_builder_state.txt`, `coordinate_state.txt`, `farm_state.txt`, `task_chain_state.txt`, `inventory_state.txt`, and `ore_targets.txt`. The Resume saved job menu lists active saves only. Automatic continuation is opt-in per job; if enabled, a saved job may resume when the program starts. A job requiring physical-position review is not resumed blindly.

The live dashboard redraws a fixed set of rows instead of filling the terminal with messages. It shows task, phase, progress, position/facing, fuel, inventory, supplies, elapsed time, estimated remaining time, and warnings. During ore scanning, the position and timing continue to update.

- `Q` or `Ctrl+T`: request a safe stop.
- `S`: request an immediate status refresh when starting a legacy task directly.

Branch mining, area excavation, and route building return to base, unload, and save on a safe stop. Coordinate navigation stops safely and saves its current world position.

The initial ETA uses expected action counts × the default **0.8 seconds per action**. `work_estimator.lua` separately estimates movement, vertical movement, digging, turning, placement, and checks. Examples include branch length/spacing, 3×3 tunnel slices, excavation volume, staircase steps, protected tunnel cells, and Manhattan coordinate distance plus turns. During a job, measured action times and unexpected delays adjust the remaining estimate. Ore-vein size, fluids, gravel, mobs, and inventory trips cannot be known exactly in advance.

`situation_manager.lua` handles retryable obstacles, torch fallback placement, and water/lava detected ahead, above, or below. A nonessential failure such as a missed torch normally warns and continues. Navigation uncertainty instead causes a save and stop.

`action_log.lua` appends only a job's start time, job name, and starting fuel level to `action_log.txt`; it does not log every movement or turn.

## Project layout

| File | Role |
| --- | --- |
| `main.lua`, `ui.lua`, `settings.lua`, `localization.lua` | Central menu, UI, persistent settings, and language strings. |
| `navigation.lua`, `coordinate_navigation.lua`, `situation_manager.lua` | Movement, experimental world-coordinate navigation, and situation handling. |
| `state_store.lua`, `work_registry.lua`, `job_preview.lua`, `job_request.lua` | Atomic saves, job ownership, resume previews, and job hand-off. |
| `telemetry.lua`, `work_estimator.lua` | Live timing/ETA and initial action-count formulas. |
| `branch_miner.lua`, `excavator.lua`, `nether_builder.lua` | Mining, area excavation, and route building. |
| `farm_task.lua`, `task_chain.lua`, `chain_editor.lua`, `coordinate_task.lua` | Experimental farming, task chains, and coordinate jobs. |
| `inventory_manager.lua`, `torch_manager.lua`, `ore_scanner.lua` | Experimental capacity, torch, and ore systems. |
| `remote.lua`, `remote_protocol.lua`, `remote_monitor.lua` | Rednet telemetry and remote commands. |
| `downloader.lua`, `startup_turtle.lua`, `startup_monitor.lua` | Installation, updates, and boot scripts. |

## Tests

The Lua tests use mocked turtle and CC:Tweaked APIs. Run them with Python and [Lupa](https://pypi.org/project/lupa/):

```text
python tests/run_lua_tests.py
```

In-game testing is still necessary for movement, chest orientation, fluids, crops, mobs, and wireless range.
