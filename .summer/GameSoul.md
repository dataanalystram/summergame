# Game Soul — 2012: The Escape

## Pitch
An endless chase down a downtown Los Angeles freeway while the ground splits apart under the limo.
The player steers an armored black limousine between glowing chasms and falling concrete, and the run
ends when the road drops away. Distance survived is the score.

## Tone and look
- Disaster-movie poster palette: burnt orange sky with dark storm clouds, brown haze, ember sparks.
- A warm low sun from the right, cool fill light, heavy aerial perspective.
- Downtown canyon of worn brownstones and pale mid-rise blocks on both sides, roofs disappearing into smoke.
- The freeway itself is the hero prop: wide multi-lane asphalt slabs, white dashed lane paint, low concrete parapets.
- Below the deck: a glowing magma chasm; fragments of city ground float and tilt.
- UI: cinematic title card "2012 / THE ESCAPE", spaced Helvetica caps, minimal HUD, warm white type.

## Feel
Fast, heavy, cinematic. Speed ramps with distance. Collapse telegraphs itself with glowing cracks and
shaking slabs, then whole lane strips tilt and drop away. Falling rubble is marked on the road by a
pulsing orange ring. Three chassis hits are survivable; losing the road is fatal.

## Rules
- Auto-accelerate. A / D or arrows steer, S or Down brakes. Space starts, Space/R restarts after a crash.
- Holes never close the entire road: a safe corridor of at least three lanes always exists.
- Best distance is stored in `user://run.cfg`.

## Files
- `scripts/game.gd` — world generation, driving, collapse, debris, camera, audio hooks.
- `scripts/hud.gd` — title screen, stats, chassis, game-over card.
- `shaders/apocalypse_sky.gdshader`, `shaders/abyss.gdshader`, `shaders/crack.gdshader`, `shaders/warn_marker.gdshader`.
