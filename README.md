# Terrarium

A sealed glass jar of moss, stone and soil where small soft-bodied creatures live their whole lives. They hatch, graze, court, lay eggs, grow old and return to the moss. Each one is built from a genome, and its children inherit a blend of their parents with a little drift. Over a few weeks the jar's population becomes something nobody designed.

It's a quiet game about watching something become itself.

## The life loop

```
genome ──▶ body ──▶ where it can go ──▶ where it does go ──▶ who thrives ──▶ courtship ──▶ eggs
   ▲                                                                                     │
   └─────────────────────────────────────────────────────────────────────────────────────┘
```

There's no fitness score. The jar does the choosing: moss grows where the lamp falls, and the creatures whose bodies can reach it are the ones who live long enough to court.

## Running

Install [LÖVE 11.5](https://love2d.org), then from the repo root:

```
love .
```

Or take `terrarium.love` from a [release](https://github.com/chrischaps/Terrarium/releases) and run `love terrarium.love`. Its `SHA256SUMS` says what the download should hash to.

Click a creature to follow it with the lantern, and right-click to drop in a pinch of food. The jar is heard faintly through its glass, and M hushes it. Tab changes how the jar is drawn (`--style <name>` opens it in one).

A jar you leave keeps living. `love . --away 2d` opens one that was left two days ago: while the glass is fogged, the days it missed go by as light and are counted in the mist, and then it clears on the jar as it is now. A week is the most it lives through.

On a touchscreen picture frame, `love . --frame` fills the screen. Tap a creature to follow it, and hold a finger still on the glass to drop in a pinch of food.

The jar asks for LÖVE 11.5 (`conf.lua`), and an older LÖVE stops on a Compatibility Warning dialog before the jar appears, which a frame on a wall has no one to dismiss. On a Raspberry Pi, use Raspberry Pi OS trixie (Debian 13), whose `apt install love` is 11.5. Bookworm's is 11.4. Checked on the frame's Pi 5 on 2026-10-30, with trixie's 11.5 package unpacked to the home folder: `love terrarium.love --frame` came up at 1280 × 720 within 3 seconds and showed no dialog. Linux has no `lovec`, so run the self-test with `love`, which already prints to the terminal.

## Milestones

| Milestone | Done when |
|---|---|
| **M1 · One jar** | All six creatures live through a full day, and Character's trip self-test passes in the jar |
| **M2 · Genes make bodies** | A lineup of random creatures looks like one family: varied, but related |
| **M3 · The cycle of life** | Ten seeds each survive a headless 30-day run, with the population between 4 and 16 and all three kinds alive |
| **M4 · The jar remembers (v1)** | Names, the family book, saving, and catch-up after time away. Ships v0.1.0 |

Work is tracked in [issues](https://github.com/chrischaps/Terrarium/issues) and [milestones](https://github.com/chrischaps/Terrarium/milestones).

## Lineage

Terrarium brings two earlier projects together:
- **[Character](https://github.com/chrischaps/Character)**: verlet, pressure-blob and FABRIK creatures that navigate by what their bodies can actually do.
- **[Fishbowl](https://github.com/chrischaps/Fishbowl)**: a tank that lives through a day and remembers you.

Shared libraries come from [LoveLibs](https://github.com/chrischaps/LoveLibs), vendored as a git subtree in `lib/LoveLibs`.
