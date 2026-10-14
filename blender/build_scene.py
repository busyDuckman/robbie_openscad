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
    "magnet": "metal",
    "sled_pin": "printed",
    "bearing_screw": "metal",
    "bearing_nut": "metal",
    "wire_harness": "wire",
}

EXPAND_SAMPLES = [i / 10 for i in range(11)]

FPS = 25
# timeline, seconds. The clip ends as it starts, so it loops.
T_HOLD = 0.4         # assembled
T_EXPLODE = 2.5      # expand 0 -> 1 (linear, as $t), camera turns ORBIT_DEG
T_DETAIL = 4.0       # exploded, camera turns on round to 360 and moves in on the sleds
T_REASSEMBLE = 2.0   # expand 1 -> 0, camera back to its start, no turning
T_SPIN = 8.0         # sleds run round the ring SPIN_DEG, faded parts see-through
T_FADE = 0.8         # fade in / out time, inside T_SPIN
ORBIT_DEG = 70       # camera turn during the explode
SPIN_DEG = 360       # sled travel, a whole turn so the loop is seamless
CAM_ELEVATION = 22   # degrees
CAM_LENS = 85        # mm
DETAIL_ZOOM = 0.5    # camera distance in the detail orbit, vs the exploded fit

# see-through while the sleds turn (opacity FADE_OPACITY), so the gears show
FADE_PARTS = ["upper_sled", "sled_top", "sensor", "sled_screw", "top_sled_screw", "bearing_screw", "bearing_nut",
              "sled_pin"]
FADE_OPACITY = 0.1
# parts that also spin on their own axis as the sleds turn: ratio of the turn, from the scad (echoed)
SPIN_PARTS = {"pinion": "-ring_gear_teeth / pinion_teeth"}

SCALE = 0.001        # scad mm -> blender m
MARKER_COLOUR = "#0A0B0C"  # placement markers, picked out of exports that also hold unlisted parts

# printed parts with no color() in the scad (OpenSCAD's default yellow)
PRINTED_DEFAULT = "#E6E6E3"
PCB_SOLDERMASK = "#F4F4F2"   # gloss white

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
           f'module blender_marker_shape() color("{MARKER_COLOUR}") cube(0.5, center=true);']
    drv += [f'echo(str("blender_spin {n}=", {e}));' for n, e in SPIN_PARTS.items()] + [""]
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
        return False, log
    if r.returncode != 0 or "ERROR:" in log:
        raise RuntimeError(f"openscad failed for {sel} @ {expand}:\n{log}")
    return os.path.exists(out), log


def marker_points(path):
    v, t, c, colours = read_3mf(path)
    ids = [i for i, (_, h) in enumerate(colours) if h == MARKER_COLOUR]
    return v[t[np.isin(c, ids)].ravel()]


def clusters(a, r=2.0):
    """centres of the separate marker cubes (one per copy of the part)"""
    groups = []
    for p in a:
        for g in groups:
            if np.abs(g[0] - p).max() < r:
                g.append(p)
                break
        else:
            groups.append([p])
    return [((np.min(g, 0) + np.max(g, 0)) / 2).tolist() for g in groups]


EXPORT_VERSION = 2  # bump when the export code changes


def source_hash(lod):
    h = hashlib.sha256()
    for f in sorted(os.listdir(REPO)):
        if f.endswith(".scad"):
            h.update(f.encode() + open(os.path.join(REPO, f), "rb").read())
    h.update(repr((lod, EXPAND_SAMPLES, OPENSCAD, PARTS, SPIN_PARTS, MARKER_COLOUR, EXPORT_VERSION)).encode())
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

        rest = done[("geom", "__rest__")][0]
        if rest:
            for i, e in enumerate(EXPAND_SAMPLES):
                jobs[("rest", i)] = ex.submit(openscad, os.path.join(mdir, f"__rest___{i:02d}.3mf"),
                                              "__rest__", e, lod)
            for i in range(len(EXPAND_SAMPLES)):
                jobs[("rest", i)].result()

    parts = {}
    for name in PARTS:
        if not done[("geom", name)][0]:
            print(f"build_scene: WARNING {name}() draws nothing in the assembly, skipped")
            continue
        boxes, centres = [], []
        for i in range(len(EXPAND_SAMPLES)):
            a = marker_points(os.path.join(mdir, f"{name}_{i:02d}.3mf")) if done[("mark", name, i)][0] else []
            boxes.append([a.min(0).tolist(), a.max(0).tolist()] if len(a) else None)
            if i == 0 and len(a):
                centres = clusters(a)
        parts[name] = {"kind": PARTS[name], "geom": f"geom/{name}.3mf", "boxes": boxes, "centres": centres}
        if name in SPIN_PARTS:
            m = re.search(rf"blender_spin {name}=([-\d.eE+]+)", done[("geom", name)][1])
            if not m:
                raise SystemExit(f"build_scene: no spin ratio echoed for {name}, check SPIN_PARTS")
            parts[name]["spin"] = float(m.group(1))

    if rest:
        print("build_scene: WARNING the assembly has geometry outside PARTS (a new part?), "
              "added as '_unlisted', animated by its bounding box. Add its module to PARTS.")
        boxes = []
        for i in range(len(EXPAND_SAMPLES)):
            v, _, _, _ = read_3mf(os.path.join(mdir, f"__rest___{i:02d}.3mf"))
            boxes.append([v.min(0).tolist(), v.max(0).tolist()])
        parts["_unlisted"] = {"kind": "printed", "geom": "geom/__rest__.3mf", "boxes": boxes, "centres": []}

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
            set_inputs(b, base=srgb(PCB_SOLDERMASK), rough=0.12, coat=1.0)
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


def timeline():
    """frames: start, explode start, explode end, detail end, reassembled, spin end (= start, loops)"""
    t = np.cumsum([0, T_HOLD, T_EXPLODE, T_DETAIL, T_REASSEMBLE, T_SPIN])
    return [1 + round(x * FPS) for x in t]


def lin(a, b, i, n):
    return a + round((b - a) * i / (n - 1))


def key(ob, path, value, frame, interp, index=-1):
    bpy.context.preferences.edit.keyframe_new_interpolation_type = interp
    if path.startswith('["'):
        ob[path[2:-2]] = value
    elif index >= 0:
        getattr(ob, path)[index] = value
    else:
        setattr(ob, path, value)
    ob.keyframe_insert(path, index=index, frame=frame)


def ensure_fade(mat):
    """mix to transparent by the object's "fade" property (0 solid, 1 at FADE_OPACITY), per object as
    materials are shared between parts"""
    nt = mat.node_tree
    if "fade_mix" not in nt.nodes:
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
        if not out.inputs["Surface"].links:
            return
        src = out.inputs["Surface"].links[0].from_socket
        attr = nt.nodes.new("ShaderNodeAttribute")
        attr.attribute_type, attr.attribute_name = "OBJECT", "fade"
        mul = nt.nodes.new("ShaderNodeMath")
        mul.name, mul.operation = "fade_mul", "MULTIPLY"
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.name = "fade_mix"
        nt.links.new(attr.outputs["Fac"], mul.inputs[0])
        nt.links.new(mul.outputs[0], mix.inputs[0])
        nt.links.new(src, mix.inputs[1])
        nt.links.new(tr.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    nt.nodes["fade_mul"].inputs[1].default_value = 1 - FADE_OPACITY


def make_mesh(name, v, t, c, colours, kind):
    used = sorted(set(c.tolist()))
    vi = np.unique(t)
    remap_v = np.full(len(v), -1)
    remap_v[vi] = np.arange(len(vi))
    me = bpy.data.meshes.new(name)
    me.from_pydata((v[vi] * SCALE).tolist(), [], remap_v[t].tolist())
    for ci in used:
        m = material_for(kind, *colours[ci])
        ensure_fade(m)
        me.materials.append(m)
    remap = {ci: k for k, ci in enumerate(used)}
    me.polygons.foreach_set("material_index", [remap[x] for x in c.tolist()])
    me.validate()
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(35))
    me.update()
    return me


def build_parts(p):
    F = timeline()
    fade = round(T_FADE * FPS)
    col = collection("robbie_parts")
    clear_collection(col)
    n = len(p["samples"])

    # sled parts (drawn more than once) hang off this, it runs them round the ring
    spin = bpy.data.objects.new("SledSpin", None)
    col.objects.link(spin)
    key(spin, "rotation_euler", 0.0, F[4], "BEZIER", 2)
    key(spin, "rotation_euler", math.radians(SPIN_DEG), F[5], "BEZIER", 2)

    box = {k: [np.full(3, 1e9), np.full(3, -1e9)] for k in ("start", "exploded", "sleds")}

    def grow(k, lo, hi):
        box[k][0], box[k][1] = np.minimum(box[k][0], lo), np.maximum(box[k][1], hi)

    for name, part in p["parts"].items():
        v, t, c, colours = read_3mf(os.path.join(BUILD, part["geom"]))
        offs = offsets(name, part["boxes"])
        centres = part.get("centres", [])
        sled = len(centres) > 1

        # parts that spin on their own axis: one object per copy, origin on its axis
        if name in SPIN_PARTS:
            cxy = np.array(centres)[:, :2]
            tri_xy = v[t].mean(1)[:, :2]
            near = np.argmin(((tri_xy[:, None, :] - cxy[None]) ** 2).sum(2), 1)
            pieces = [(f"{name}_{k}", np.array([centres[k][0], centres[k][1], 0.0]), near == k)
                      for k in range(len(centres))]
        else:
            pieces = [(name, np.zeros(3), np.ones(len(t), bool))]

        for oname, origin, mask in pieces:
            me = make_mesh(oname, v - origin, t[mask], c[mask], colours, part["kind"])
            ob = bpy.data.objects.new(oname, me)
            col.objects.link(ob)
            if sled:
                ob.parent = spin
            for i, o in enumerate(offs):
                if o is None:
                    continue
                loc = Vector((origin + np.array(o)) * SCALE)
                key(ob, "location", loc, lin(F[1], F[2], i, n), "LINEAR")
                key(ob, "location", loc, lin(F[4], F[3], i, n), "LINEAR")
            if name in SPIN_PARTS:
                key(ob, "rotation_euler", 0.0, F[4], "BEZIER", 2)
                key(ob, "rotation_euler", math.radians(SPIN_DEG * part["spin"]), F[5], "BEZIER", 2)
            if name in FADE_PARTS:
                for f, val in ((F[4], 0.0), (F[4] + fade, 1.0), (F[5] - fade, 1.0), (F[5], 0.0)):
                    key(ob, '["fade"]', val, f, "BEZIER")

        last = np.array(offs[-1] or [0, 0, 0])
        grow("start", v.min(0), v.max(0))
        grow("exploded", v.min(0) + last, v.max(0) + last)
        if sled:
            grow("sleds", v.min(0) + last, v.max(0) + last)
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "BEZIER"
    return {k: (a * SCALE, b * SCALE) for k, (a, b) in box.items()}


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


def studio(box):
    sc = bpy.context.scene
    F = timeline()
    (lo, hi), (lo1, hi1) = box["start"], box["exploded"]
    sc.frame_start, sc.frame_end = F[0], F[5] - 1   # F[5] is frame 1 again
    sc.render.fps = FPS

    backdrop(min(0.0, lo[2]))

    # camera turn: ORBIT_DEG over the explode, on round to a full turn in the detail orbit, then still
    rig = empty("CamRig")
    rig.animation_data_clear()
    for f, a in ((F[0], 0), (F[2], ORBIT_DEG), (F[3], 360)):
        key(rig, "rotation_euler", math.radians(a), f, "BEZIER", 2)

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

    start, exploded = fit(lo, hi), fit(lo1, hi1)
    sl, sh = box["sleds"]
    detail = (exploded[0] * DETAIL_ZOOM, (sl[2] + sh[2]) / 2)
    cam.animation_data_clear()
    target.animation_data_clear()
    for frame, (dist, cz) in ((F[1], start), (F[2], exploded),
                              (F[2] + round(0.4 * (F[3] - F[2])), detail), (F[3], detail), (F[4], start)):
        key(target, "location", Vector((0, 0, cz)), frame, "BEZIER")
        key(cam, "location", Vector((0, -dist * math.cos(el), cz + dist * math.sin(el))), frame, "BEZIER")

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
    sc.cycles.transparent_max_bounces = 64   # faded parts stack many layers deep
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
    studio(build_parts(p))
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
    print("build_scene: saved", BLEND)


main()
