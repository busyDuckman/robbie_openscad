# Blender render of the base.scad assembly

Cycles render of the `part == 0` explode animation, rebuilt from the scad source on every run.
Uses OpenSCAD nightly (Manifold) and Blender 5.1. Nothing in the repo's .scad files is edited.

## Run (from the repo root)

```bash
"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup --python blender/build_scene.py
"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup blender/robbie.blend --python blender/render.py -- test
"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup blender/robbie.blend --python blender/render.py -- final
wsl -e sh -c 'cd /mnt/c/Users/duckman/git_personal/robbie_openscad/blender/.output && ffmpeg -y -framerate 25 -i final/frame_%04d.png -c:v libx264 -crf 16 -pix_fmt yuv420p robbie.mp4'
```

- `build_scene.py`: exports with OpenSCAD (about 40 s, 181 parallel runs), then creates or updates `robbie.blend`.
  It skips the exports if no `.scad` file has changed. Options after `--`: `--force` re-exports anyway, `--lod 1.0` sets the LOD (the default is 1.0).
- `render.py -- preview`: a quick render of the whole animation (half size, 16 samples, fast Cycles settings), written straight to `.output/preview.mp4`. Review this before running `final`.
- `render.py -- test`: renders 3 half-size frames at 48 samples to `.output/test/` (assembled, mid explode, exploded).
- `render.py -- stills`: renders 3 full-size stills at 512 samples to `.output/stills/` (assembled, half way, exploded).
- `render.py -- final`: renders all 221 frames at 1080p and 256 samples on the GPU (OptiX), to `.output/final/`. That takes about 7 s per frame. Frames that already exist are skipped, so a stopped render picks up where it left off.

## How positions come from OpenSCAD

- **Leaves:** `PARTS` (at the top of `build_scene.py`) lists the modules the assembly draws (base, collar, pinion, n20_motor and so on), each with its material kind.
- **Driver:** `build/driver.scad` is generated. It includes `base.scad` and redefines each leaf so that only the one named in `blender_sel` draws.
  - The leaves' signatures are read from the repo's .scad files.
  - The original modules are called through `build/orig.scad`, which `use`s a copy of base.scad, so cutters inside the parts are untouched.
- **Geometry:** each leaf is exported once as 3MF, in place, at `expand = 0`. 3MF keeps the `color()`s.
- **Motion:** each leaf is exported again at `expand = 0, 0.1 … 1`, drawn as a marker cube at its own origin. The marker's move becomes that leaf's location keyframes, linear between samples. So any change to the offsets or the piecewise ranges in base.scad comes through, as long as the breakpoints fall on the 0.1 grid.
- **New parts:** anything the assembly draws that isn't in `PARTS` is added as `_unlisted`, animated by its bounding box, and a warning is printed. Add its module to `PARTS` to give it its own material.
- **Fixed settings:** exports run with `slice_mode=0` and `LOD` as given, passed with `-D` (or set in the generated files). Your values in base.scad are not changed.

## Scene

- **Rebuilt every run:** the `robbie_parts` collection (with the `SledSpin` empty) and the camera rig. Camera framing is fitted to the assembled, exploded and sled bounding boxes.
- **Created only if missing**, so edits you make in the .blend survive a rerun:
  - the materials, named `kind:#colour`
  - the four area lights, parented to the camera rig, so the result looks like a turntable
  - the world
  - the cyclorama backdrop
- **Materials:**
  - Printed parts use the scad colours with faint 0.2 mm layer lines. Uncoloured printed parts get `PRINTED_DEFAULT`.
  - Screws, the nut and the motor are steel or brass.
  - The AS5600 is gloss white with gold pads.
  - The harness wires are silicone in their scad colours.
- **Timeline** (25 fps, about 17 s, loops seamlessly). Set in seconds by the `T_*` values at the top of `build_scene.py`:
  1. Assembled hold (0.4 s).
  2. Explode (2.5 s), linear in `expand` like `$t`, while the camera turns 70° and pulls back.
  3. Detail orbit (4 s): the camera turns on round to a full turn and moves in on the sleds.
  4. Reassembly (2 s): no turning, and the camera returns to where it started.
  5. Sled spin (8 s): the sleds run once round the ring. Each pinion counter-spins by `-ring_gear_teeth / pinion_teeth`, which the scad echoes, so the gears stay meshed. The `FADE_PARTS` fade to 10 % opacity and back.
- **Sled parts** are found automatically: any part drawn more than once in the assembly turns with the sleds.
- **Fading** works per object, through a `fade` custom property, because materials are shared between parts.

`build/` (exports) and `.output/` (renders, git ignored) are generated and safe to delete.
