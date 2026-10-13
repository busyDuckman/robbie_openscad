"""
Build / update blender/robbie.blend from base.scad's assembly (part = 0) and its explode animation.

Run from the repo root:
    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python blender/build_scene.py
    ... -- --force        re-export from OpenSCAD even if the .scad sources are unchanged
    ... -- --lod 1.0      LOD passed to the exports (default 1.0, "checks")

How it works
  1. Leaves: the modules in PARTS are the assembly's visible pieces. A generated driver (build/driver.scad)
     includes base.scad and redefines each leaf so only the selected one draws. The originals are reached
     through build/orig.scad, a `use`d copy of base.scad, so the leaf's own internals (and cutters that use
     other leaves) are untouched. base.scad itself is never edited.
  2. Geometry: each leaf is exported once, in place, at expand = 0, as 3MF (keeps the scad colours).
  3. Placement: each leaf is exported again at every expand sample as a tiny marker cube at its own origin.
     The marker's move from expand = 0 is the leaf's offset, so all keyframes come from OpenSCAD's own
     transforms (new offsets, moved parts, new piecewise ranges all come through). Keys are linear between
     samples, exact for breakpoints on the sample grid (0, 0.1, ... 1).
  4. Anything still drawn with every leaf hidden is a new, unlisted part: it's exported as "_unlisted",
     animated from its bounding box, and a warning names it so it can be added to PARTS.
  5. Scene: parts are rebuilt every run. Materials, lights, world and backdrop are only created if missing,
     so hand tweaks in the .blend survive a rerun. The camera rig is refitted every run.
"""

import bpy
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from mathutils import Vector

import numpy as np

# ----------------------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------------------

OPENSCAD = "C:/Program Files/OpenSCAD (Nightly)/openscad.com"

# leaf module (as called in the assembly) : material kind
PARTS = {
    "base": "printed",
    "home_switch_plug": "printed",
    "collar": "printed",
    "guide": "printed",
    "pinion": "printed",
    "lower_sled": "printed",
    "upper_sled": "printed",
    "sled_top": "printed",
    "d2f_switch": "switch",
    "n20_motor": "motor",
    "sensor": "pcb",
    "sled_screw": "metal",
    "top_sled_screw": "metal",
    "bearing_screw": "metal",
    "bearing_nut": "metal",
    "wire_harness": "wire",
}

EXPAND_SAMPLES = [i / 10 for i in range(11)]

FPS = 30
HOLD_START = 20      # frames assembled before the explode
EXPLODE = 150        # frames for expand 0 -> 1 (linear, as $t)
HOLD_END = 50        # frames fully exploded
ORBIT_DEG = 70       # camera turn over the whole clip
CAM_ELEVATION = 22   # degrees
CAM_LENS = 85        # mm

SCALE = 0.001        # scad mm -> blender m
MARKER_COLOUR = "#0A0B0C"  # placement markers, picked out of exports that also hold unlisted parts

# printed parts with no color() in the scad (OpenSCAD's default yellow)
PRINTED_DEFAULT = "#E6E6E3"
PCB_SOLDERMASK = "#1F3F8F"   # the as5600 board is white in the scad

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BUILD = os.path.join(HERE, "build")
BLEND = os.path.join(HERE, "robbie.blend")


def fwd(p):
    return p.replace("\\", "/")


# ----------------------------------------------------------------------------------------
# Driver generation
# ----------------------------------------------------------------------------------------

def balanced(text, i):
    """text[i] == '(' -> index of the matching ')'"""
    depth = 0
    for j in range(i, len(text)):
        c = text[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return j
    raise ValueError("unbalanced parens")


def split_top(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def module_signatures():
    """signature text of every top level module in the repo's .scad files"""
    sigs = {}
    for f in sorted(os.listdir(REPO)):
        if not f.endswith(".scad"):
            continue
        text = strip_comments(open(os.path.join(REPO, f), encoding="utf-8").read())
        for m in re.finditer(r"\bmodule\s+(\w+)\s*\(", text):
            close = balanced(text, m.end() - 1)
            sigs.setdefault(m.group(1), (text[m.end():close], f))
    return sigs


def write_drivers(lod):
    sigs = module_signatures()
    base = fwd(os.path.join(REPO, "base.scad"))
    orig = ["// generated by build_scene.py, do not edit",
            f"include <{base}>",
            "part = -9999;",
            f"LOD = {lod};", ""]
    drv = ["// generated by build_scene.py, do not edit",
           f"include <{base}>",
           "use <orig.scad>",
           'blender_sel = "";',
           "blender_marker = false;",
           f'module blender_marker_shape() color("{MARKER_COLOUR}") cube(0.5, center=true);', ""]
    for name in PARTS:
        if name not in sigs:
            raise SystemExit(f"build_scene: module {name}() not found in {REPO}/*.scad, update PARTS")
        sig, _ = sigs[name]
        params = [p.split("=")[0].strip() for p in split_top(sig)]
        call = ", ".join(f"{p}={p}" for p in params)
        orig.append(f"module blender_orig_{name}({sig}) {name}({call});")
        drv.append(f'module {name}({sig}) if (blender_sel == "{name}") {{ '
                   f"if (blender_marker) blender_marker_shape(); else blender_orig_{name}({call}); }}")
    os.makedirs(BUILD, exist_ok=True)
    for fn, lines in (("orig.scad", orig), ("driver.scad", drv)):
        with open(os.path.join(BUILD, fn), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")


# ----------------------------------------------------------------------------------------
# OpenSCAD exports
# ----------------------------------------------------------------------------------------

def openscad(out, sel, expand, lod, marker=False):
    args = [OPENSCAD, "--backend=manifold", "-o", out,
            "-D", "part=0", "-D", f"expand={expand}", "-D", "slice_mode=0", "-D", f"LOD={lod}",
            "-D", f'blender_sel="{sel}"', "-D", f"blender_marker={'true' if marker else 'false'}"]
    args.append(os.path.join(BUILD, "driver.scad"))
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(args, capture_output=True, text=True, cwd=BUILD)
    log = r.stdout + r.stderr
    if "Current top level object is empty" in log and "ERROR:" not in log:
        return False
    if r.returncode != 0 or "ERROR:" in log:
        raise RuntimeError(f"openscad failed for {sel} @ {expand}:\n{log}")
    return os.path.exists(out)


def marker_bbox(path):
    v, t, c, colours = read_3mf(path)
    ids = [i for i, (_, h) in enumerate(colours) if h == MARKER_COLOUR]
    a = v[t[np.isin(c, ids)].ravel()]
    if len(a) == 0:
        return None
    return a.min(0).tolist(), a.max(0).tolist()


def source_hash(lod):
    h = hashlib.sha256()
    for f in sorted(os.listdir(REPO)):
        if f.endswith(".scad"):
            h.update(f.encode() + open(os.path.join(REPO, f), "rb").read())
    h.update(open(__file__, "rb").read())
    h.update(repr((lod, EXPAND_SAMPLES, OPENSCAD)).encode())
    return h.hexdigest()


def export_all(lod, force):
    key = source_hash(lod)
    pfile = os.path.join(BUILD, "placements.json")
    if not force and os.path.exists(pfile):
        p = json.load(open(pfile))
        if p.get("key") == key:
            print("build_scene: scad unchanged, reusing exports in", BUILD)
            return p

    write_drivers(lod)
    gdir, mdir = os.path.join(BUILD, "geom"), os.path.join(BUILD, "markers")
    os.makedirs(gdir, exist_ok=True)
    os.makedirs(mdir, exist_ok=True)

    jobs = {}
    with ThreadPoolExecutor(max_workers=max(2, (os.cpu_count() or 4) // 2)) as ex:
        # heavy ones first
        for name in list(PARTS) + ["__rest__"]:
            jobs[("geom", name)] = ex.submit(openscad, os.path.join(gdir, f"{name}.3mf"), name, 0, lod)
        for name in PARTS:
            for i, e in enumerate(EXPAND_SAMPLES):
                jobs[("mark", name, i)] = ex.submit(
                    openscad, os.path.join(mdir, f"{name}_{i:02d}.3mf"), name, e, lod, True)
        print(f"build_scene: {len(jobs)} OpenSCAD exports ...")
        done = {k: f.result() for k, f in jobs.items()}

        rest = done[("geom", "__rest__")]
        if rest:
            for i, e in enumerate(EXPAND_SAMPLES):
                jobs[("rest", i)] = ex.submit(openscad, os.path.join(mdir, f"__rest___{i:02d}.3mf"),
                                              "__rest__", e, lod)
            for i in range(len(EXPAND_SAMPLES)):
                jobs[("rest", i)].result()

    parts = {}
    for name in PARTS:
        if not done[("geom", name)]:
            print(f"build_scene: WARNING {name}() draws nothing in the assembly, skipped")
            continue
        boxes = []
        for i in range(len(EXPAND_SAMPLES)):
            f = os.path.join(mdir, f"{name}_{i:02d}.3mf")
            boxes.append(marker_bbox(f) if done[("mark", name, i)] else None)
        parts[name] = {"kind": PARTS[name], "geom": f"geom/{name}.3mf", "boxes": boxes}

    if rest:
        print("build_scene: WARNING the assembly has geometry outside PARTS (a new part?), "
              "added as '_unlisted', animated by its bounding box. Add its module to PARTS.")
        boxes = []
        for i in range(len(EXPAND_SAMPLES)):
            v, _, _, _ = read_3mf(os.path.join(mdir, f"__rest___{i:02d}.3mf"))
            boxes.append([v.min(0).tolist(), v.max(0).tolist()])
        parts["_unlisted"] = {"kind": "printed", "geom": "geom/__rest__.3mf", "boxes": boxes}

    p = {"key": key, "lod": lod, "samples": EXPAND_SAMPLES, "parts": parts}
    json.dump(p, open(pfile, "w"), indent=1)
    return p


def offsets(name, boxes):
    """per sample offset (mm) of the box min from sample 0, None where the part isn't drawn"""
    ref = np.array(boxes[0][0])
    size0 = np.array(boxes[0][1]) - ref
    out, warned = [], False
    for b in boxes:
        if b is None:
            out.append(None)
            continue
        if not warned and np.abs((np.array(b[1]) - np.array(b[0])) - size0).max() > 0.01:
            print(f"build_scene: WARNING {name} changes shape / turns with expand, only its move is animated")
            warned = True
        out.append((np.array(b[0]) - ref).tolist())
    return out


# ----------------------------------------------------------------------------------------
# 3MF
# ----------------------------------------------------------------------------------------

NS = "{http://schemas.microsoft.com/3dmanufacturing/core/2015/02}"


def read_3mf(path):
    """vertices (n,3) mm, triangles (m,3), per triangle colour index, colour list [(name, '#rrggbb')]"""
    with zipfile.ZipFile(path) as z:
        data = z.read("3D/3dmodel.model")
    root = ET.fromstring(data)
    colours = [(b.get("name"), b.get("displaycolor")[:7].upper()) for b in root.iter(NS + "base")]
    verts, tris, cols = [], [], []
    for obj in root.iter(NS + "object"):
        default = int(obj.get("pindex", 0))
        off = len(verts)
        verts += [(float(v.get("x")), float(v.get("y")), float(v.get("z"))) for v in obj.iter(NS + "vertex")]
        for t in obj.iter(NS + "triangle"):
            tris.append((off + int(t.get("v1")), off + int(t.get("v2")), off + int(t.get("v3"))))
            cols.append(int(t.get("p1", default)))
    return np.array(verts), np.array(tris, dtype=np.int32), np.array(cols, dtype=np.int32), colours


# ----------------------------------------------------------------------------------------
# Materials
# ----------------------------------------------------------------------------------------

def srgb(hexstr):
    h = hexstr.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def new_material(name):
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    return m, m.node_tree.nodes["Principled BSDF"]


def set_inputs(bsdf, **kw):
    names = {"base": "Base Color", "metal": "Metallic", "rough": "Roughness", "coat": "Coat Weight",
             "spec": "Specular IOR Level", "sheen": "Sheen Weight", "aniso": "Anisotropic"}
    for k, v in kw.items():
        bsdf.inputs[names[k]].default_value = v


def layer_lines(mat, bsdf, pitch=0.2):
    """FDM layer lines along Z, as a faint bump"""
    nt = mat.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type, wave.bands_direction, wave.wave_profile = "BANDS", "Z", "SIN"
    wave.inputs["Scale"].default_value = 2 * math.pi / (20 * pitch * SCALE)
    wave.inputs["Distortion"].default_value = 0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.00004
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def material_for(kind, cname, chex):
    default = cname == "Default"
    name = f"{kind}:{'default' if default else chex}"
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m, b = new_material(name)
    gold, black, red = chex == "#FFD700", chex in ("#222222", "#000000"), chex == "#FF0000"
    if kind == "printed":
        set_inputs(b, base=srgb(PRINTED_DEFAULT if default else chex), rough=0.42, spec=0.45)
        layer_lines(m, b)
    elif kind == "wire":
        set_inputs(b, base=srgb(chex), rough=0.55, spec=0.4, sheen=0.3)
    elif kind == "pcb":
        if gold:
            set_inputs(b, base=srgb("#E8C27A"), metal=1, rough=0.25)
        elif black:
            set_inputs(b, base=srgb("#141414"), rough=0.45)
        elif chex == "#FFFFFF" or default:
            set_inputs(b, base=srgb(PCB_SOLDERMASK), rough=0.3, coat=0.6)
        else:  # tinned leads
            set_inputs(b, base=srgb("#C8C8C8"), metal=1, rough=0.3)
    elif kind in ("metal", "motor", "switch"):
        if gold:
            set_inputs(b, base=srgb("#D9B26A"), metal=1, rough=0.3)
        elif black:
            set_inputs(b, base=srgb("#161616"), rough=0.5, spec=0.5)
        elif red:
            set_inputs(b, base=srgb("#B01010"), rough=0.4)
        else:  # steel, tinted a touch by the scad colour
            c = srgb(chex)
            g = sum(c[:3]) / 3
            tint = [0.75 * g + 0.25 * x for x in c[:3]]
            k = 0.8 / max(max(tint), 1e-3)
            set_inputs(b, base=[min(1, t * k) for t in tint] + [1], metal=1, rough=0.28)
    else:
        set_inputs(b, base=srgb(chex), rough=0.5)
    return m


# ----------------------------------------------------------------------------------------
# Scene
# ----------------------------------------------------------------------------------------

def collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def clear_collection(c):
    for o in list(c.objects):
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)


def frame_of(i, n):
    return HOLD_START + 1 + round(EXPLODE * i / (n - 1))


def build_parts(p):
    prefs = bpy.context.preferences.edit
    prefs.keyframe_new_interpolation_type = "LINEAR"
    col = collection("robbie_parts")
    clear_collection(col)
    n = len(p["samples"])
    lo, hi = np.full(3, 1e9), np.full(3, -1e9)        # assembled bbox (mm)
    lo1, hi1 = np.full(3, 1e9), np.full(3, -1e9)      # exploded
    for name, part in p["parts"].items():
        v, t, c, colours = read_3mf(os.path.join(BUILD, part["geom"]))
        me = bpy.data.meshes.new(name)
        me.from_pydata((v * SCALE).tolist(), [], t.tolist())
        used = sorted(set(c.tolist()))
        for ci in used:
            me.materials.append(material_for(part["kind"], *colours[ci]))
        remap = {ci: k for k, ci in enumerate(used)}
        me.polygons.foreach_set("material_index", [remap[x] for x in c.tolist()])
        me.validate()
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(35))
        me.update()
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)

        offs = offsets(name, part["boxes"])
        for i, o in enumerate(offs):
            if o is None:
                continue
            ob.location = Vector(o) * SCALE
            ob.keyframe_insert("location", frame=frame_of(i, n))
        lo, hi = np.minimum(lo, v.min(0)), np.maximum(hi, v.max(0))
        last = np.array(offs[-1] or [0, 0, 0])
        lo1, hi1 = np.minimum(lo1, v.min(0) + last), np.maximum(hi1, v.max(0) + last)
    prefs.keyframe_new_interpolation_type = "BEZIER"
    return lo * SCALE, hi * SCALE, lo1 * SCALE, hi1 * SCALE


def backdrop(floor_z):
    if "Backdrop" in bpy.data.objects:
        bpy.data.objects["Backdrop"].location.z = floor_z
        return
    import bmesh
    r0, rf, h = 2.0, 0.8, 3.0  # floor radius, cove radius, wall height
    prof = [(0.0, 0.0), (r0 * 0.5, 0.0), (r0, 0.0)]
    prof += [(r0 + rf * math.sin(a), rf - rf * math.cos(a))
             for a in [math.radians(x) for x in range(10, 91, 10)]]
    prof += [(r0 + rf, h)]
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0, z)) for x, z in prof]
    es = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0, 0, 0), axis=(0, 0, 1), angle=math.tau, steps=128,
                   use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new("Backdrop")
    bm.to_mesh(me)
    me.shade_smooth()
    ob = bpy.data.objects.new("Backdrop", me)
    collection("studio").objects.link(ob)
    ob.location.z = floor_z
    m, b = new_material("backdrop")
    set_inputs(b, base=srgb("#3C3E42"), rough=0.85, spec=0.3)
    me.materials.append(m)


def light(name, loc, power, size, color=(1, 1, 1), parent=None):
    if name in bpy.data.objects:
        return bpy.data.objects[name]
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape, ld.size, ld.energy, ld.color = "DISK", size, power, color
    ob = bpy.data.objects.new(name, ld)
    collection("studio").objects.link(ob)
    ob.location = loc
    ob.parent = parent
    tc = ob.constraints.new("TRACK_TO")
    tc.target = bpy.data.objects["LightTarget"]
    tc.track_axis, tc.up_axis = "TRACK_NEGATIVE_Z", "UP_Y"
    return ob


def empty(name, parent=None):
    ob = bpy.data.objects.get(name)
    if ob is None:
        ob = bpy.data.objects.new(name, None)
        collection("studio").objects.link(ob)
        ob.parent = parent
    return ob


def studio(lo, hi, lo1, hi1):
    sc = bpy.context.scene
    f0, f1 = 1, HOLD_START + EXPLODE + HOLD_END + 1
    fe0, fe1 = HOLD_START + 1, HOLD_START + EXPLODE + 1
    sc.frame_start, sc.frame_end = f0, f1
    sc.render.fps = FPS

    backdrop(min(0.0, lo[2]))

    rig = empty("CamRig")
    rig.animation_data_clear()
    prefs = bpy.context.preferences.edit
    prefs.keyframe_new_interpolation_type = "LINEAR"
    rig.rotation_euler = (0, 0, 0)
    rig.keyframe_insert("rotation_euler", index=2, frame=f0)
    rig.rotation_euler = (0, 0, math.radians(ORBIT_DEG))
    rig.keyframe_insert("rotation_euler", index=2, frame=f1)
    prefs.keyframe_new_interpolation_type = "BEZIER"

    target = empty("CamTarget")
    lt = empty("LightTarget")
    lt.location = (0, 0, (lo[2] + hi[2]) / 2)

    cam = bpy.data.objects.get("Camera")
    if cam is None:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        collection("studio").objects.link(cam)
    cam.parent = rig
    cam.data.lens = CAM_LENS
    cam.data.clip_start, cam.data.clip_end = 0.01, 50
    cam.constraints.clear()
    tc = cam.constraints.new("TRACK_TO")
    tc.target = target
    tc.track_axis, tc.up_axis = "TRACK_NEGATIVE_Z", "UP_Y"
    sc.camera = cam

    # fit: a box of diameter D and height H, seen from CAM_ELEVATION, in the 16:9 frame
    el = math.radians(CAM_ELEVATION)
    sw = cam.data.sensor_width
    hf = 2 * math.atan(sw / 2 / CAM_LENS)
    vf = 2 * math.atan(sw * 9 / 16 / 2 / CAM_LENS)

    def fit(a, b):
        d_xy = max(b[0] - a[0], b[1] - a[1])
        h = b[2] - a[2]
        app_h = h * math.cos(el) + d_xy * math.sin(el)
        dist = max(app_h / 2 / math.tan(vf / 2), d_xy / 2 / math.tan(hf / 2)) * 1.04 + d_xy / 2
        return dist, (a[2] + b[2]) / 2

    cam.animation_data_clear()
    target.animation_data_clear()
    for frame, (a, b) in ((fe0, (lo, hi)), (fe1, (lo1, hi1))):
        dist, cz = fit(a, b)
        target.location = (0, 0, cz)
        target.keyframe_insert("location", frame=frame)
        cam.location = (0, -dist * math.cos(el), cz + dist * math.sin(el))
        cam.keyframe_insert("location", frame=frame)

    size = max(hi1[0] - lo1[0], hi1[2] - lo1[2])
    r = 4 * size
    light("Key", (r * 0.75, -r * 0.85, r * 0.9), 50, size * 2.5, (1.0, 0.96, 0.9), rig)
    light("Fill", (-r * 1.0, -r * 0.6, r * 0.4), 12, size * 4, (0.9, 0.95, 1.0), rig)
    light("Rim", (-r * 0.3, r * 1.0, r * 0.8), 45, size * 2, (1, 1, 1), rig)
    light("Top", (0, 0, r * 1.4), 15, size * 3, (1, 1, 1), rig)

    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    if w.node_tree is None:
        w.use_nodes = True
    if "studio_world" not in w:
        w["studio_world"] = True
        bg = w.node_tree.nodes["Background"]
        bg.inputs["Color"].default_value = srgb("#202226")
        bg.inputs["Strength"].default_value = 0.25

    r_ = sc.render
    r_.engine = "CYCLES"
    r_.resolution_x, r_.resolution_y, r_.resolution_percentage = 1920, 1080, 100
    r_.image_settings.file_format = "PNG"
    r_.filepath = "//.output/final/frame_"
    sc.cycles.samples = 256
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    force = "--force" in argv
    lod = float(argv[argv.index("--lod") + 1]) if "--lod" in argv else 1.0

    p = export_all(lod, force)

    if os.path.exists(BLEND):
        bpy.ops.wm.open_mainfile(filepath=BLEND)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    studio(*build_parts(p))
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
    print("build_scene: saved", BLEND)


main()
