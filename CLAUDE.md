# Terrarium

A LÖVE 11.5 / Lua game. Soft-bodied creatures (verlet worm, pressure blob, FABRIK spider) live in a jar, and each is built from a genome. Children inherit a blend of their parents plus mutation, and moss grazing does the selecting. The backlog is in GitHub issues and milestones on `chrischaps/Terrarium`.

## Running
- `love .`: the game.
- `lovec . --selftest`: Character's self-test, run against the jar (nav graph integrity, reachability, about 116 trips, determinism at 30/60/240 fps, a 10-minute replay of the whole jar, audio smoke test). Exits 1 on failure.
- `lovec . --replay <sec>`: open the jar twice from its seed, step both, and compare state hashes (`core/statehash.lua`). Prints `hash <hex>`, so separate runs can be compared too. A mismatch names the first part that drifted.
- `lovec . --test <name>[,<name>]`: just those self-tests (`graphs`, `trips`, `framerate`, `lantern`, `day`, `replay`, `genome`, `audio`). A test is a `test(name, fn)` in `dev.lua`; new ones go there. Exits 2 on an unknown name. `--seed <n>` reseeds `day`, the M1 gate: all six residents wander, graze, rest through the night and wake again over a 900-second day.
- Test modes (`--test`, `--selftest`, `--replay`, `--navdump`, `--headless`) run with no window: `conf.lua` turns it off and `core/headless.lua` stands in a null `love.graphics`, so composing the jar still bakes and draws from `rng.scape` the same way. `--window` opens one anyway. A headless jar must hash the same as a windowed one.
- `LOVE=lovec sh tests/ci.sh`: everything CI runs (`.github/workflows/selftest.yml`, Linux and Windows): the lint, the self-test, the replay hash compared across two processes, and with `WINDOW="xvfb-run -a"` a windowed jar against a headless one.
- `sh tests/check_random.sh`: fails on any `math.random`, `love.math.random` or stray `newRandomGenerator` outside `core/rng.lua`.
- `lovec . --snap - <sec> <file.png>`: fast-forward the sim, then save a screenshot to `%APPDATA%/LOVE/terrarium/`. Add `--nav` for every nav graph, or `--nav worm|blob|spider` for one with its jump arcs.
- `lovec . --navdump <who> <solid>`: print a creature's nodes and edges on one solid.
- `--hour <h|name>` opens the jar at an hour (snaps default to midday), and `--day <sec>` compresses the day: `love . --day 120 --hour lampon`.
- The 200-genome and 30-day population runs (M2/M3) register as named tests in `dev.lua` and must stay runnable in CI.

## Module map (from the proposal)
- `genome.lua`: genes, ranges, crossover, mutation. One table per plan in the shape of Fishbowl's `species.lua`, genes in a fixed list (`real`, `int` or `pick`). Reals are kept to thousandths so `serialise`/`parse` round-trip exactly. A genome is `{plan = 'worm', segments = 14, ...}`
- `bodies/`: worm, blob and spider builders that take a genome (`base.lua` holds the Mover anchor and Face; `fabrik.lua` is the spider's IK)
- `nav/`: per-body navigation graph builder, A*, the ballistics jump model, and the path-following controller
- `core/`: `rng` (the `sim` and `look` streams), `statehash` (a fingerprint of the World for replay checks), `log`, `synth`
- `dev.lua`: argument parsing and the self-test
- `mind.lua`: needs and temperament choose goals. For now it's the M1 stub: the lamp and a hunger counter pick wandering, grazing on moss, or resting (walkers on moss, spiders hanging under a ledge). It only picks nodes from the creature's own graph. It reads the hour from `World:hour()`, which comes from `opts.hour`/`opts.day`, both inputs like the seed.
- `jar/`: tank, glass, day cycle and environment (from Fishbowl), plus the moss grid. Right now it holds `world.lua` (creatures, graphs and controllers on the fixed step), `level.lua`/`collision.lua` (AABB solids), and `room.lua` (the jar's solids in Character's level format: soil, a one-footed cork arch, a standing stone and cairn with a twig between them over a water dish, and a slate shelf; `moss = true` tags the tops the moss grid will cover, and `residents` lists who lives there: two of each kind, each with a placeholder name and a spawn point). Bodies of the same kind share one nav graph (`world.graph_of[key]`), and `World:first(key)` finds the first one of a kind. `scenery.lua` bakes and draws those solids from `rng.scape`. Seen side-on, a roof grounded at both ends seals the floor under it, so `NavGraph:keep_home` keeps only each body's largest mutually reachable set of nodes. The view comes from Fishbowl: `config.lua` (projection, box, creature plane `PLANE_D`), `tank.lua` (project/unproject, and `Tank.pushPlane()` for drawing in level coordinates), `render.lua` (canvases, depth-of-field blur), `scape.lua` (room, desk, soil bed and layers, stones) and `glass.lua` (panes, lid, front glass, the lamp's cone). Light comes from `daycycle.lua`: a jar day is a real day, and the hour is `DayCycle.hourAt(startHour, world.time)`, so it's sim time, never the wall clock (that's read once at load, like the seed). `plants.lua` (ferns, moss sporophytes; it's World's `flora`, stepped on the fixed step) and `motes.lua`. `condensation.lua` fogs the inside of the front glass from `env.damp` (a day-cycle key) and the hour. It's a pure function of the jar's clock, composed from `rng.scape` last, and drawn with `shaders/mist.glsl`. `lantern.lua` is the watch-only follow light. It lives in `main.lua`, outside the World, and reads only `interp_points()`. Never route it through `world.selected`, because selection changes who wanders. Shaders live in `shaders/` (`floor.glsl` relights the soil bed).
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
