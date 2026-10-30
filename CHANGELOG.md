# Changelog

Each release's notes are its section here. When a `v*` tag is pushed, the release workflow (`.github/workflows/release.yml`) drafts the GitHub release with that section as its notes. A tag with no section gets a placeholder to fill in by hand.

## v0.1.0 · The jar remembers

The first jar you can keep.

Terrarium is a sealed glass jar of moss, stone and soil. Small soft-bodied creatures live their whole lives in it. Each one is built from a genome. They graze the moss the lamp grows, court, lay eggs, grow old and go back to the moss, and their children carry a blend of their parents with a little drift. Nobody chooses who thrives. The moss does, by growing where the light falls, and over a few weeks the jar becomes something nobody designed.

You don't breed anything. You watch.

### In the jar

- **Three kinds to a jar**, drawn from the jar's seed out of five: a verlet worm, a pressure blob, a FABRIK spider, a cobalt springtail that somersaults across the moss, and a snail that leaves a slime trail. When a snail dies, its shell stays in the moss.
- **Genes you can see.** Every gene shows within a minute: length and stiffness, size and give, legs and reach, colour, markings and glow, and a temperament (bold or shy, sociable or not, an early riser or a night owl).
- **A body that never lies.** Each creature can only go where its own body could actually get to. Its routes are built from its size, spring and reach.
- **A day that's a real day.** A lamp comes on in the morning and goes off at night. The moss grows under it, and the creatures sleep and wake by it. At night the glass fogs, and markings glow.
- **A life.** Hatchlings come out small and pale and grow up through three moults. Adults court on their own beat: worms coil, blobs pulse, spiders tap, springtails hop, snails sway. Elders slow, then go back to the moss in their sleep, and the moss there grows back richer.
- **Heard through the glass.** Every sound is made from the creatures' genes, so each voice deepens as it grows. Press M to hush the jar.

### What you can do

- **Follow one** with the lantern: click it.
- **Drop in a pinch of food**: right-click. You get a few pinches a day.
- **Name them**, and keep their family book: who arrived, who is gone, and who their parents and children were.
- **Leave it.** The jar keeps living while it's shut, up to a week of it, and when you open it again the time you were away passes on the glass.

### Getting it

- **Windows**: download `terrarium-win64.zip`, unzip it, and run `Terrarium/Terrarium.exe`. The jar saves to `%APPDATA%\terrarium`.
- **Anywhere LÖVE runs**: install [LÖVE 11.5](https://love2d.org) and run `love terrarium.love`.
- **On a picture frame**: `love terrarium.love --frame` fills a touchscreen. Tap a creature to follow it, and hold a finger still on the glass to drop in food.

`SHA256SUMS` lists what each download should hash to.

### Under the glass

A jar is its seed plus its history. Everything alive advances on a fixed 120 Hz step from one seeded RNG, so the same jar replays the same on any machine. Every release is checked on Linux and Windows against the packed game itself: a 116-trip navigation test, 200 random bodies per kind, ten jars each left alone for a month, and a week in one jar on the live step.
