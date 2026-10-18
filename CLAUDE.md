# Terrarium

A LÖVE 11.5 / Lua game. Soft-bodied creatures (verlet worm, pressure blob, FABRIK spider) live in a jar, and each is built from a genome. Children inherit a blend of their parents plus mutation, and moss grazing does the selecting. The backlog is in GitHub issues and milestones on `chrischaps/Terrarium`.

## Running
- `love .`: the game.
- Headless self-tests and the 30-day population run will live under `tests/` (see M1/M3 issues). They must stay runnable in CI.

## Module map (from the proposal)
- `genome.lua`: genes, ranges, crossover, mutation
- `bodies/`: worm, blob and spider builders that take a genome
- `nav/`: per-body navigation graph builder and A*
- `mind.lua`: needs and temperament choose goals
- `jar/`: tank, glass, day cycle and environment (from Fishbowl), plus the moss grid
- `book.lua`: save data and the family book
- Require path is `lib/?.lua`, so LoveLibs modules load as `require('LoveLibs.<area>.<module>')`, the same as in [Character](https://github.com/chrischaps/Character), where it's `libs/`. Code ported from Character keeps its requires unchanged.
- `lib/LoveLibs/`: git subtree of chrischaps/LoveLibs. Don't edit it in place. Update with `git subtree pull --prefix=lib/LoveLibs https://github.com/chrischaps/LoveLibs.git master --squash`

## Rules
- **Deterministic.** Simulation advances only on the fixed 120 Hz step. All randomness comes from the jar's seeded RNG; never call `math.random` or `love.math.random` directly. Rendering must never affect the simulation.
- **The body never lies.** A creature is only offered paths its own body can travel, so rebuild its nav graph from its body.
- **Every trait is visible.** A gene that changes nothing you can see within a minute is cut.
- **You witness; you don't breed.** The player's verbs are watching, following with the lantern, naming, and dropping in food.
- **Gentle mortality.** Death is shown as returning to the moss.
