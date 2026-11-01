# Drawing the jar in a style

Notes for whoever makes the next look for the jar (epic #93: watercolour #96, ASCII #97, the spike #98, and whatever follows). They come from building pencil (#95, PR #115). Chris reviewed it in play, asked for an A/B, chose one side, and then shaped it over two more rounds. The code is the reference. This page records what Chris asked for and why, and the traps on the way.

## What Chris chose, and why

1. **Per thing, not per frame.** The first pencil was one shader over the finished frame. Chris asked to A/B it against an approach that "applies the effect on an individual entity level instead of on the whole scene at the end". He chose per entity (`pencil-each`), and the difference shows in motion:
   - A frame filter lays its texture on the screen, so a creature walks *through* hatching that stays put.
   - Drawn per thing, the strokes travel with the body.
   - A thing's outline comes from its own silhouette. Glow, condensation or a neighbour can't blur or double it, and soft markings (a blob's spots) survive.
   - Still frames in bright light look much alike. Judge in motion, and at night.
2. **Give the props the same treatment, not just the creatures.** Every scenery piece, stone, fern, the soil and the moss is drawn on its own.
3. **The background should be close to plain paper.** The room, the jar's air and its far side get no texture of their own: a faint wash where it's dark and faint lines. The vignette is turned down (0.40 to 0.12).
4. **Props are mostly outline**, "with only as much texture as is necessary to convey darkness":
   - Their surface texture (stone grain, bark, pebbles) is not drawn as detail.
   - Their shade comes from their broad tone, never from the texture.
   - It never goes past two layers of hatching.
   - Creatures keep every marking, because a marking is a gene ("every trait is visible").
5. **No blur.** The depth of field's blur turned into smudges. A drawing has no depth of field, so distance is drawn as lighter line weight instead.

So expect Chris to want: the creatures carrying their look with them, the props reduced to the style's essentials, a quiet ground, and nothing photographic leaking through. These were stated for pencil, so confirm them on your own look rather than assuming them.

## How the seam works now

A style is an entry in `Styles.list` (`jar/styles.lua`) with its shader in `shaders/styles/`. See CLAUDE.md's style bullet for the whole of it. What pencil added that you can reuse:

- **`each = {shader, setup}`** on a style turns on per-thing drawing. `main.lua` then sends each thing through **`Styles.body(name, time, x0, y0, x1, y1, ax, ay, seed, look, draw)`**:
  - `draw()` draws the thing alone onto a cleared scratch canvas, scissored to its bounds.
  - The canvas is laid into the frame through the `each` shader (premultiplied, colour only).
  - The thing's coverage is then multiplied out of the frame's alpha.
- **The frame's alpha is the mask.** After the scene is drawn, alpha is 0 where something was drawn on its own and 1 on the ground round it. Anything alpha-blended in front later (motes, condensation, the glass) raises it back. The frame shader (`masked`) draws only the ground and keeps the rest.
- **What's drawn per thing**, all in `main.lua`:

  | What | Where |
  |---|---|
  | Each creature, with its glow | `drawAlone` |
  | Each scenery piece | `drawProps`, with `Scenery.drawPiece` / `Scenery.bounds` |
  | Contact shadows and the water | `Scenery.drawGround` (drawn as ground, not per thing) |
  | Each stone and fern | `drawObject`, with `Scape.stoneBounds` / `Plants.bounds` |
  | The far stones and ferns | `drawObject` with `LOOK.far`, sharp, no blur |
  | The soil's bed and its front face | `Scape.bedBounds` / `Scape.frontBounds` |
  | The moss | `drawProps` |
  | The small things (trails, eggs, crumbs, remains), together | `litter` |

  The room and the far wall stay ground.
- **`look`** (`Styles.LOOK`) is pencil's way of telling a creature from a prop. It's four numbers: weight, detail, softness, darkest. Your shader can read it or ignore it. The split it encodes is what Chris wanted:
  - `creature`: everything.
  - `prop`: mostly outline.
  - `soil`: like a prop, with its tone taken more broadly.
  - `far`: lighter.
- **`glass = {aberration, grain, vignette}`** on a style sets what the composite lays over its frame. Paper has no colour fringe or film grain. Film grain is per-frame noise and crawls over anything meant to hold still.
- **`#include "file.glsl"`** works in any shader that `Render.shader` loads, resolved within its own folder. Pencil's two passes share `pencil_common.glsl`.
- **`each.lay(alone, quad, x0, y0, kind, seed)`** (ascii-each, #97) replaces `Styles.body`'s two draws for a style that lays its things in its own way. `kind` is the look's name (`Styles.KIND`: `creature`, `prop`, `soil`, `far`, `moss`). Ascii lays each thing in as it is and marks it on a map of what's where, so its cells pass can set a cell by the thing it holds. **`each.begin(target)`** (from `Styles.begin`, called where `drawScene` and `plate` clear their canvas) lets a style start such a map afresh each frame.
- **`Styles.LOOK.moss`** is the moss's own look. To pencil it's the same four numbers as a prop. Ascii sets it as grass.
- **The A/B harness:** `lovec . --script scripts/pencil_ab.lua` films the creature that moves furthest, with the camera held still, two styles side by side. Copy it and change the two names to A/B your own variants. Chris tested the result in play, flipping with Tab.

## Traps

> **Partial alpha leaks the photo.** Wherever the frame's alpha is between 0 and 1, the frame pass mixes its drawing with the photo underneath. A blurred layer (the depth of field) or a soft-edged sprite drawn over a per-thing body leaves grey smudges. Draw such layers on their own too, or sharp, or not at all.

> **A shared scratch canvas keeps the last thing.** Clearing only the current thing's scissor leaves the previous thing just outside it. Edge filters reaching past the bounds read it and draw a hard 1 px seam. Clear a margin wider than your widest tap (`MARGIN` in `Styles.body`). Raising an edge threshold hides this; it doesn't fix it.

> **Edges need a light-relative floor.** Sobel on `log2(rgb + f0)` treats night and day alike. A fixed `f0` either loses edges at night or turns the day's surface textures into clutter. Scaling `f0` with the local light fixed both.

> **Judge at 1:1.** A downscaled screenshot of fine texture reads as static. Crop at full size before deciding something is noisy.

> **LÖVE throws on `send` to a uniform the compiler removed.** A debug early-`return` in a shader then crashes the style's `setup`. Blend the probe in instead (`probe + 0.001 * normal`), so every uniform stays live.

> **GLSL builtins:** `noise1`/`noise2` are reserved names, so name your own differently.

> **Nothing from the clock that should hold still.** Pencil's hatching never reads `time`, and only the line boils (4 drawings a second). Check it the way #95 did: style one frame at several jar times and count the changed pixels. Within one drawing, none should change.

## Before you call a style done

- `lovec . --test styles,frame`.
- `lovec . --replay 60` and `lovec . --replay 60 --window --style <yours>` print the same hash, because watching must change nothing. CI checks every style this way.
- `lovec . --script scripts/styles.lua` (day, night, close-up) and `lovec . --style <yours> --script scripts/lineup.lua`: the five families must still be told apart.
- `none` and the other styles still render byte for byte as before. Script captures are deterministic, so compare the PNGs.
- `--bench 10` against `--style none`. Per-thing drawing costs a pass per thing: pencil-each runs about 2.5 ms over none on the desktop, and the Pi is unmeasured.
