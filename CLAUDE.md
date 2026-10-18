# Terrarium

A LÖVE 11.5 / Lua game. Soft-bodied creatures (verlet worm, pressure blob, FABRIK spider) live in a jar, and each is built from a genome. Children inherit a blend of their parents plus mutation, and moss grazing does the selecting. The backlog is in GitHub issues and milestones on `chrischaps/Terrarium`.

## Running
- `love .`: the game.
- `lovec . --selftest`: Character's self-test, run against the jar (nav graph integrity, reachability, about 116 trips, determinism at 30/60/240 fps, audio smoke test). Exits 1 on failure.
- `lovec . --snap - <sec> <file.png>`: fast-forward the sim, then save a screenshot to `%APPDATA%/LOVE/terrarium/`. Add `--nav` for every nav graph, or `--nav worm|blob|spider` for one with its jump arcs.
- `lovec . --navdump <who> <solid>`: print a creature's nodes and edges on one solid.
- `--hour <h|name>` opens the jar at an hour (snaps default to midday), and `--day <sec>` compresses the day: `love . --day 120 --hour lampon`.
- Headless self-tests and the 30-day population run will live under `tests/` (see M1/M3 issues). They must stay runnable in CI.

## Module map (from the proposal)
- `genome.lua`: genes, ranges, crossover, mutation
- `bodies/`: worm, blob and spider builders that take a genome (`base.lua` holds the Mover anchor and Face; `fabrik.lua` is the spider's IK)
- `nav/`: per-body navigation graph builder, A*, the ballistics jump model, and the path-following controller
- `core/`: `rng` (the `sim` and `look` streams), `log`, `synth`
- `dev.lua`: argument parsing and the self-test
- `mind.lua`: needs and temperament choose goals
- `jar/`: tank, glass, day cycle and environment (from Fishbowl), plus the moss grid. Right now it holds `world.lua` (creatures, graphs and controllers on the fixed step), `level.lua`/`collision.lua` (AABB solids), and `room.lua` (the jar's solids in Character's level format: soil, a one-footed cork arch, a standing stone and cairn with a twig between them over a water dish, and a slate shelf; `moss = true` tags the tops the moss grid will cover). `scenery.lua` bakes and draws those solids from `rng.scape`. Seen side-on, a roof grounded at both ends seals the floor under it, so `NavGraph:keep_home` keeps only each body's largest mutually reachable set of nodes. The view comes from Fishbowl: `config.lua` (projection, box, creature plane `PLANE_D`), `tank.lua` (project/unproject, and `Tank.pushPlane()` for drawing in level coordinates), `render.lua` (canvases, depth-of-field blur), `scape.lua` (room, desk, soil bed and layers, stones) and `glass.lua` (panes, lid, front glass, the lamp's cone). Light comes from `daycycle.lua`: a jar day is a real day, and the hour is `DayCycle.hourAt(startHour, world.time)`, so it's sim time, never the wall clock (that's read once at load, like the seed). `plants.lua` (ferns, moss sporophytes; it's World's `flora`, stepped on the fixed step) and `motes.lua`. Shaders live in `shaders/` (`floor.glsl` relights the soil bed).
- `core/rng.lua` has three streams: `sim`, `look`, and `scape`. `scape` is the jar's fixed composition. It's seeded from the jar seed and drawn from only at load
- Files copied from Character carry a `-- From chrischaps/Character @ <sha> (<path>)` header. Their internal requires were remapped (`creatures.` → `bodies.`, `core.navgraph` → `nav.navgraph`, `world.` → `jar.`). Other edits are marked `-- Terrarium:`.
- `book.lua`: save data and the family book
- Require path is `lib/?.lua`, so LoveLibs modules load as `require('LoveLibs.<area>.<module>')`, the same as in [Character](https://github.com/chrischaps/Character), where it's `libs/`. Code ported from Character keeps its requires unchanged.
- `lib/LoveLibs/`: git subtree of chrischaps/LoveLibs. Don't edit it in place. Update with `git subtree pull --prefix=lib/LoveLibs https://github.com/chrischaps/LoveLibs.git master --squash`

## Rules
- **Deterministic.** Simulation advances only on the fixed 120 Hz step. All randomness comes from the jar's seeded RNG; never call `math.random` or `love.math.random` directly. Rendering must never affect the simulation.
- **The body never lies.** A creature is only offered paths its own body can travel, so rebuild its nav graph from its body.
- **Every trait is visible.** A gene that changes nothing you can see within a minute is cut.
- **You witness; you don't breed.** The player's verbs are watching, following with the lantern, naming, and dropping in food.
- **Gentle mortality.** Death is shown as returning to the moss.
