"""
Render blender/robbie.blend with Cycles on the GPU.

    blender --background blender/robbie.blend --python blender/render.py -- preview
        quick, half size, 16 sample render of the whole animation straight to blender/.output/preview.mp4
        (-- preview NAME writes NAME.mp4)
    blender --background blender/robbie.blend --python blender/render.py -- test
        a few low sample, half size frames (assembled, mid explode, end, or the frame numbers given) to
        blender/.output/test/
    blender --background blender/robbie.blend --python blender/render.py -- stills
        3 full size, 512 sample stills (assembled, half way, exploded) to blender/.output/stills/
    blender --background blender/robbie.blend --python blender/render.py -- final
        every frame, full quality, to blender/.output/final/ (existing frames are skipped, so it resumes)

Then to make the mp4 (ffmpeg is in WSL):
    wsl -e sh -c 'cd /mnt/c/Users/duckman/git_personal/robbie_openscad/blender/.output && \
        ffmpeg -y -framerate 25 -i final/frame_%04d.png -c:v libx264 -crf 16 -pix_fmt yuv420p robbie.mp4'
"""

import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
mode = argv[0] if argv else "test"

sc = bpy.context.scene
cy = bpy.context.preferences.addons["cycles"].preferences
for dev in ("OPTIX", "CUDA"):
    try:
        cy.compute_device_type = dev
    except TypeError:
        continue
    cy.get_devices()
    gpus = [d for d in cy.devices if d.type == dev]
    if gpus:
        for d in cy.devices:
            d.use = d.type == dev
        sc.cycles.device = "GPU"
        print("render: using", dev, [d.name for d in gpus])
        break
else:
    print("render: no GPU found, using CPU")

sc.cycles.use_denoising = True
sc.cycles.denoiser = "OPENIMAGEDENOISE"

if mode == "preview":
    # fast Cycles: keep the scene on the GPU between frames, short light paths, GPU denoiser
    sc.render.use_persistent_data = True
    sc.cycles.samples = 16
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 2
    sc.cycles.caustics_reflective = sc.cycles.caustics_refractive = False
    sc.cycles.use_fast_gi = True
    if sc.cycles.device == "GPU" and cy.compute_device_type == "OPTIX":
        sc.cycles.denoiser = "OPTIX"
    sc.render.resolution_percentage = 50
    im = sc.render.image_settings
    if hasattr(im, "media_type"):
        im.media_type = "VIDEO"
    im.file_format = "FFMPEG"
    sc.render.ffmpeg.format = "MPEG4"
    sc.render.ffmpeg.codec = "H264"
    sc.render.ffmpeg.constant_rate_factor = "HIGH"
    sc.render.filepath = f"//.output/{argv[1] if len(argv) > 1 else 'preview'}.mp4"
    bpy.ops.render.render(animation=True)
elif mode == "test":
    sc.cycles.samples = 48
    sc.render.resolution_percentage = 50
    f0, f1 = sc.frame_start, sc.frame_end
    hold = 20
    frames = [int(x) for x in argv[1:]] or [f0, f0 + hold + (f1 - f0 - hold) // 3, f1]
    for f in frames:
        sc.frame_set(f)
        sc.render.filepath = f"//.output/test/frame_{f:04d}.png"
        bpy.ops.render.render(write_still=True)
elif mode == "stills":
    sc.cycles.samples = 512
    sc.render.resolution_percentage = 100
    f0, f1 = sc.frame_start, sc.frame_end
    hold = 20
    for f in [f0, f0 + hold + (f1 - f0 - hold) // 2, f1]:
        sc.frame_set(f)
        sc.render.filepath = f"//.output/stills/still_{f:04d}.png"
        bpy.ops.render.render(write_still=True)
else:
    sc.cycles.samples = 256
    sc.cycles.adaptive_threshold = 0.01
    sc.render.resolution_percentage = 100
    sc.render.use_overwrite = False
    sc.render.use_placeholder = True
    sc.render.filepath = "//.output/final/frame_"
    bpy.ops.render.render(animation=True)
