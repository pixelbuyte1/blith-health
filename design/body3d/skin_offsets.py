"""Per-vertex skin offsets for the muscle layer's translucent skin shell.

Some Z-Anatomy muscles sit slightly outside the BodyParts3D skin. The app pushes each skin vertex out
along its normal just far enough to clear the muscles near it (plus a small margin), so the shell hugs
the body instead of floating as a pale outline. Writes ios/Blith/Resources/Body3D/skin_offsets.bin:
"BLO1", u32 vertexCount, then one float32 offset in metres per skin vertex.

    python3 design/body3d/skin_offsets.py
"""
import json, struct, sys
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "ios/Blith/Resources/Body3D"
BASE, MARGIN, HEAD = 0.0015, 0.003, 0.0015

data = (RES / "body.bin").read_bytes()
meta = json.loads((RES / "body3d.json").read_text())
def u32(o): return struct.unpack_from("<I", data, o)[0]
off, layers = 8, []
for _ in range(2):
    v, t, g = u32(off), u32(off + 4), u32(off + 8); o = off + 12
    pos = np.frombuffer(data, "<f4", v * 3, o).reshape(v, 3); o += v * 12
    nrm = np.frombuffer(data, "<f4", v * 3, o).reshape(v, 3); o += v * 12
    groups = [struct.unpack_from("<IIII", data, o + i * 16) for i in range(g)]; o += g * 16
    o += t + (4 - t % 4) % 4
    idx = np.frombuffer(data, "<u4", t * 3, o).reshape(t, 3); o += t * 12
    layers.append((pos, nrm, groups, idx)); off = o
(sp, sn, sg, si), (mp, _, mg, mi) = layers
head = [r["id"] for r in meta["regions"]].index("head")

# Muscle vertices that are drawn (facial muscles are hidden under the smooth head).
drawn = np.zeros(len(mp), bool)
for r, m, f, c in mg:
    if r != head: drawn[np.unique(mi[f:f + c])] = True
pts = mp[drawn]

# For every drawn muscle vertex, the skin vertices within 3 cm whose normal it pokes past.
need = np.full(len(sp), BASE, np.float32)
tree = cKDTree(sp)
for p, near in zip(pts, tree.query_ball_point(pts, 0.03)):
    if not near: continue
    near = np.asarray(near)
    signed = np.einsum("ij,ij->i", p - sp[near], sn[near])
    lateral = np.linalg.norm((p - sp[near]) - signed[:, None] * sn[near], axis=1)
    hit = (signed > -MARGIN) & (lateral < 0.012)
    if hit.any():
        np.maximum.at(need, near[hit], signed[hit] + MARGIN)

# Head stays close: no muscles are drawn under it.
head_verts = np.unique(np.concatenate([si[f:f + c].ravel() for r, m, f, c in sg if r == head]))
need[head_verts] = np.minimum(need[head_verts], HEAD)

# Smooth across the mesh so the offset changes gradually (no ridges), keeping peaks covered.
tris = si.astype(np.int64)
for it in range(6):
    s = np.zeros(len(sp)); w = np.zeros(len(sp))
    tot = need[tris].sum(axis=1)
    for k in range(3):
        np.add.at(s, tris[:, k], tot); np.add.at(w, tris[:, k], 3)
    avg = np.where(w > 0, s / np.maximum(w, 1), need)
    need = np.maximum(avg, need * 0.85).astype(np.float32) if it < 3 else avg.astype(np.float32)
need = np.clip(need, BASE, 0.03)

# Never inflate two facing parts of the skin into each other (arm against ribs, fingers against thigh):
# where another sheet of skin lies within 7 cm along a vertex's normal, each side may grow only to half
# the gap, less 1.5 mm of clearance, so the arms stay free of the torso instead of looking glued on.
gap = np.full(len(sp), np.inf)
for i, near in enumerate(tree.query_ball_point(sp, 0.07)):
    near = np.asarray(near)
    d = sp[near] - sp[i]
    dist = np.linalg.norm(d, axis=1)
    ok = (dist > 1e-4) & ((d @ sn[i]) > 0.6 * dist) & ((sn[near] @ sn[i]) < -0.2)
    if ok.any(): gap[i] = dist[ok].min()
# Only the arms and torso: hands against thighs and the inner thighs keep the full clearance their muscles need.
TORSO_ARMS = {"chest", "abdomen", "upperBack", "lowerBack", "rightShoulder", "leftShoulder", "rightUpperArm",
              "leftUpperArm", "rightElbow", "leftElbow", "rightForearm", "leftForearm"}
limited = np.zeros(len(sp), bool)
for r, m, f, c in sg:
    if meta["regions"][r]["id"] in TORSO_ARMS: limited[np.unique(si[f:f + c])] = True
cap = np.where(np.isfinite(gap) & limited, np.maximum(gap / 2 - 0.0015, BASE), 0.03).astype(np.float32)
hard = cap.copy()
for it in range(3):  # let the limit fade into neighbouring vertices so no ridge forms
    s = np.zeros(len(sp)); w = np.zeros(len(sp))
    tot = cap[tris].sum(axis=1)
    for k in range(3):
        np.add.at(s, tris[:, k], tot); np.add.at(w, tris[:, k], 3)
    cap = np.minimum(np.where(w > 0, s / np.maximum(w, 1), cap), cap).astype(np.float32)
cap = np.minimum(cap, hard)
need = np.minimum(need, cap).astype(np.float32)


out = RES / "skin_offsets.bin"
out.write_bytes(b"BLO1" + struct.pack("<I", len(need)) + need.astype("<f4").tobytes())
print(f"{out.relative_to(ROOT)}: {len(need)} vertices, median {np.median(need)*1000:.1f} mm, "
      f"p95 {np.percentile(need,95)*1000:.1f} mm, max {need.max()*1000:.1f} mm")
