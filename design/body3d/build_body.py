#!/usr/bin/env python3
"""Builds Blith's 3D body assets: a skin layer and an anatomical muscle layer that share one
coordinate space, per-triangle BodyRegion labels, named muscles, anchors and CPU-rendered previews.

Sources (downloaded and cached outside the repo, never committed):
  * Skin: BodyParts3D 4.0 "Skin" (FMA7163, file FJ2810), IS-A tree OBJ archive, polygon reduction 99%.
    BodyParts3D, (c) The Database Center for Life Science. https://dbarchive.biosciencedbc.jp/en/bodyparts3d/
  * Muscles/tendons: Z-Anatomy "MuscularSystem100.fbx" (a completed derivative of BodyParts3D).
    Z-Anatomy - The open source atlas of anatomy. https://github.com/LluisV/Z-Anatomy
  Both are CC BY-SA (see LICENSE-ASSETS.md); the generated meshes are CC BY-SA 4.0.

Pipeline
  1. skin: outer shell of FJ2810, welded; genitals replaced by a smooth neutral membrane; holes
     (eyes, armpits, fingertips) closed; decimated with quadric error metrics.
  2. Z-Anatomy muscles are mapped into the BodyParts3D frame (a similarity transform fitted once
     by ICP between Z-Anatomy's own skin and FJ2810), vertices poking out of the skin are pulled
     just under it, deep/hidden parts are dropped by a multi-view visibility test and the rest are
     decimated to a triangle budget proportional to their visible area.
  3. an "underlayer" (the skin pushed inward beneath the muscles) keeps the red figure continuous
     where no muscle covers the body (shin, knee, hands, face gaps).
  4. everything: metres, y up, feet on y = 0, facing +z, person's left at +x, 1.80 m tall.
  5. per-triangle BodyRegion labels (33 regions) from joint landmarks taken from BodyParts3D bones.

    pip install numpy scipy Pillow pyfqmr
    python3 design/body3d/build_body.py          # caches downloads in $BLITH_BODY_CACHE (~/.cache/blith-body)

Deterministic: no randomness except fixed-seed tone jitter.
"""
import json
import os
import struct
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image
from scipy import ndimage, sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbxbin  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'ios', 'Blith', 'Resources', 'Body3D')
DESIGN = os.path.join(ROOT, 'design', 'body3d')
CACHE = os.environ.get('BLITH_BODY_CACHE', os.path.join(os.path.expanduser('~'), '.cache', 'blith-body'))

BP3D_ZIP = 'https://dbarchive.biosciencedbc.jp/data/bodyparts3d/LATEST/isa_BP3D_4.0_obj_99.zip'
ZA_RAW = 'https://raw.githubusercontent.com/LluisV/Z-Anatomy/PC-Version/Resources/Models/FBX/'

HEIGHT = 1.80            # metres, final figure height
SKIN_TRIS = 53000        # before region-border splitting (adds ~12 %)
MUSCLE_TRIS = 128000     # muscles + tendons
UNDER_TRIS = 18000       # continuous underlayer

SOURCE = ('Skin: BodyParts3D 4.0 (FJ2810). Muscles: Z-Anatomy MuscularSystem100 (derived from BodyParts3D). '
          'Mapped to one frame, decimated, genital area smoothed to a neutral form.')
LICENSE = 'CC BY-SA 4.0'
ATTRIBUTION = ('"BodyParts3D, (c) The Database Center for Life Science licensed under CC Attribution-Share Alike 2.1 '
               'Japan"; "Z-Anatomy - The open source atlas of anatomy - CC-BY-SA 4.0". Derived meshes: CC BY-SA 4.0.')

REGION_IDS = ['head', 'neck', 'rightShoulder', 'leftShoulder', 'chest', 'abdomen', 'upperBack', 'lowerBack',
              'rightUpperArm', 'leftUpperArm', 'rightElbow', 'leftElbow', 'rightForearm', 'leftForearm',
              'rightWrist', 'leftWrist', 'rightHand', 'leftHand', 'hips', 'rightHip', 'leftHip',
              'rightThigh', 'leftThigh', 'rightKnee', 'leftKnee', 'rightShin', 'leftShin', 'rightCalf', 'leftCalf',
              'rightAnkle', 'leftAnkle', 'rightFoot', 'leftFoot']
RI = {r: i for i, r in enumerate(REGION_IDS)}


# ----------------------------------------------------------------------------------------------
# Sources
def fetch(url, name):
    dst = os.path.join(CACHE, name)
    if not os.path.exists(dst):
        os.makedirs(CACHE, exist_ok=True)
        print('  downloading', url)
        with urllib.request.urlopen(url, timeout=600) as r, open(dst + '.part', 'wb') as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
        os.replace(dst + '.part', dst)
    return dst


def bp3d_obj(fid):
    """(V, F) of a BodyParts3D element, metres, frame: x = person's left, y = up, z = front."""
    npz = os.path.join(CACHE, 'bp3d', fid + '.npz')
    if not os.path.exists(npz):
        zf = zipfile.ZipFile(fetch(BP3D_ZIP, 'isa_BP3D_4.0_obj_99.zip'))
        V, F = [], []
        for line in zf.read(f'isa_BP3D_4.0_obj_99/{fid}.obj').decode().splitlines():
            if line.startswith('v '):
                V.append([float(x) for x in line.split()[1:4]])
            elif line.startswith('f '):
                p = [int(x.split('/')[0]) - 1 for x in line.split()[1:]]
                F += [[p[0], p[i], p[i + 1]] for i in range(1, len(p) - 1)]
        V = np.array(V) * 0.001
        os.makedirs(os.path.dirname(npz), exist_ok=True)
        np.savez(npz, V=np.stack([V[:, 0], V[:, 2], -V[:, 1]], 1), F=np.array(F))   # LPS mm -> x, up, front
    d = np.load(npz)
    return d['V'], d['F']


def za_parts(name):
    return fbxbin.meshes(fetch(ZA_RAW + name.replace(' ', '%20') + '.fbx', name.replace(' ', '_') + '.fbx'))


def za_to_bp():
    """Similarity transform Z-Anatomy world (cm, y up) -> BodyParts3D frame (m), fitted by ICP
    between Z-Anatomy's own skin ("Regions of human body") and BodyParts3D FJ2810."""
    cf = os.path.join(CACHE, 'za_to_bp.json')
    if not os.path.exists(cf):
        R = np.concatenate([p['V'] for p in za_parts('Regions of human body100')]) * 0.01
        S = outer_shell(*bp3d_obj('FJ2810'))[0][::5]
        tree = cKDTree(R)
        s, t = 1.0, R.mean(0) - S.mean(0)
        for _ in range(40):
            d, i = tree.query(s * S + t)
            k = d < np.percentile(d, 90)
            A, B = S[k], R[i[k]]
            Am, Bm = A - A.mean(0), B - B.mean(0)
            s = (Am * Bm).sum() / (Am * Am).sum()
            t = B.mean(0) - s * A.mean(0)
        json.dump({'s': s, 't': list(t)}, open(cf, 'w'))
    j = json.load(open(cf))
    s, t = j['s'], np.array(j['t'])
    return lambda V: (V * 0.01 - t) / s


# ----------------------------------------------------------------------------------------------
# Mesh helpers
def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def vertex_normals(P, T):
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    N = np.zeros_like(P)
    for i in range(3):
        np.add.at(N, T[:, i], fn)
    return unit(N)


def compact(V, F):
    used, inv = np.unique(F, return_inverse=True)
    return V[used], inv.reshape(-1, 3)


def weld(V, F, eps=1e-6):
    key, first, inv = np.unique(np.round(V / eps).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    F = inv.ravel()[F]
    F = F[(F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])]
    return compact(V[first], F)


def components(nV, F):
    A = sparse.coo_matrix((np.ones(len(F) * 3), (F.ravel(), np.roll(F, 1, 1).ravel())), shape=(nV, nV))
    return connected_components(A, directed=False)[1]


def signed_volume(V, F):
    return np.einsum('ij,ij->i', V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum() / 6


def outer_shell(V, F):
    """FJ2810 is a skin *shell* (outer and inner surface); keep the largest outward-facing piece."""
    lab = components(len(V), F)          # before welding: the two shells share rim positions
    tl = lab[F[:, 0]]
    best = max((c for c in np.unique(tl) if signed_volume(V, F[tl == c]) > 0), key=lambda c: (tl == c).sum())
    return weld(*compact(V, F[tl == best]))


def adjacency(nV, F):
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    A = sparse.csr_matrix((np.ones(len(e) * 2), (np.concatenate([e[:, 0], e[:, 1]]), np.concatenate([e[:, 1], e[:, 0]]))),
                          shape=(nV, nV))
    A.data[:] = 1
    return A


def boundary_loops(F):
    he = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    n = int(F.max()) + 1
    key, rkey = he[:, 0] * n + he[:, 1], he[:, 1] * n + he[:, 0]
    b = he[~np.isin(key, rkey)]
    nxt = dict(zip(b[:, 0].tolist(), b[:, 1].tolist()))
    seen, loops = set(), []
    for s in list(nxt):
        if s in seen:
            continue
        loop, c = [s], nxt[s]
        seen.add(s)
        while c != s and c not in seen and c in nxt:
            loop.append(c)
            seen.add(c)
            c = nxt[c]
        loops.append(np.array(loop))
    return loops


def clean_boundary(V, F):
    """Remove faces at bow-tie vertices (a boundary passing through a vertex twice) and keep the
    largest piece, so every boundary is a simple loop."""
    while True:
        he = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
        n = int(F.max()) + 1
        b = he[~np.isin(he[:, 0] * n + he[:, 1], he[:, 1] * n + he[:, 0])]
        bad = np.nonzero(np.bincount(b[:, 0], minlength=n) > 1)[0]
        if not len(bad):
            break
        F = F[~np.isin(F, bad).any(1)]
        tl = components(n, F)[F[:, 0]]
        F = F[tl == np.bincount(tl).argmax()]
    return compact(V, F)


def taubin(V, F, iters=4, lam=0.5, mu=-0.53):
    A = adjacency(len(V), F)
    deg = np.asarray(A.sum(1)).ravel()[:, None]
    for _ in range(iters):
        for k in (lam, mu):
            V = V + k * ((A @ V) / deg - V)
    return V


def fill_hole(V, F, loop, bulge=0.0, rings=None):
    """Close a boundary loop with concentric rings, relaxed to a harmonic membrane, optionally
    bulged along the mean normal. The loop follows the boundary half-edge direction."""
    n = len(loop)
    rings = rings if rings is not None else int(np.clip(n // 8, 1, 8))
    P = V[loop]
    c = P.mean(0)
    base = len(V)
    ring_ids = [loop]
    newV = []
    for k in range(1, rings):
        f = 1 - k / rings
        newV.append(c + (P - c) * f)
        ring_ids.append(base + (k - 1) * n + np.arange(n))
    cid = base + (rings - 1) * n
    newV.append(c[None])
    tris = []
    for k in range(rings - 1):
        o, i = ring_ids[k], ring_ids[k + 1]
        o1, i1 = np.roll(o, -1), np.roll(i, -1)
        tris += [np.stack([o1, o, i], 1), np.stack([o1, i, i1], 1)]
    r = ring_ids[-1]
    tris.append(np.stack([np.roll(r, -1), r, np.full(n, cid)], 1))
    V2 = np.concatenate([V] + newV)
    F2 = np.concatenate([F] + tris)
    inner = np.arange(base, len(V2))
    A = adjacency(len(V2), F2)
    Ai = A[inner]
    deg = np.asarray(Ai.sum(1)).ravel()
    for _ in range(300):
        V2[inner] = (Ai @ V2) / deg[:, None]
    if bulge:
        nrm = unit(vertex_normals(V2, F2)[loop].mean(0))
        rr = np.linalg.norm(V2[inner] - c, axis=1) / max(np.linalg.norm(P - c, axis=1).mean(), 1e-9)
        V2[inner] += nrm * bulge * np.clip(1 - rr ** 2, 0, 1)[:, None]
    return V2, F2, inner


def smooth_region(V, F, verts, iters=20, lam=0.5):
    A = adjacency(len(V), F)
    Ai = A[verts]
    deg = np.asarray(Ai.sum(1)).ravel()
    for _ in range(iters):
        V[verts] = V[verts] * (1 - lam) + lam * (Ai @ V) / deg[:, None]
    return V


def decimate(V, F, target, preserve_border=True, aggressiveness=7.0):
    if len(F) <= target:
        return V, F
    import pyfqmr
    s = pyfqmr.Simplify()
    s.setMesh(np.ascontiguousarray(V, np.float64), np.ascontiguousarray(F, np.int32))
    s.simplify_mesh(target_count=int(target), aggressiveness=aggressiveness, preserve_border=preserve_border, verbose=False)
    v, f, _ = s.getMesh()
    return compact(np.asarray(v, np.float64), np.asarray(f, np.int64))


# ----------------------------------------------------------------------------------------------
# Skin
GENITAL_CENTRE = np.array([0.0, 0.735, 0.158])   # BodyParts3D frame, from the midsagittal profile
GENITAL_RADII = np.array([0.043, 0.056, 0.066])
CROTCH_Y = 0.712                                  # perineum height on the midline


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def face_weight(V):
    """1 over the front of the face (brow to chin), fading out; BodyParts3D frame."""
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    return (smoothstep(1.405, 1.435, y) * (1 - smoothstep(1.545, 1.57, y)) * smoothstep(0.095, 0.125, z)
            * (1 - smoothstep(0.065, 0.085, np.abs(x))))


def refine_face(V, F, iters=40):
    """Sculpt-like face: low-pass the scan's eye, lid, lip and nostril detail (Taubin, so the head
    keeps its volume, jaw and profile), partly sparing the nose tip so the silhouette stays."""
    w = face_weight(V)
    near = (np.abs(V[:, 0]) < 0.012) & (V[:, 1] > 1.46) & (V[:, 1] < 1.53)
    tip = V[near][np.argmax(V[near][:, 2])]
    w = w * (1 - 0.6 * np.exp(-(np.linalg.norm(V - tip, axis=1) / 0.016) ** 2))
    A = adjacency(len(V), F)
    deg = np.asarray(A.sum(1)).ravel()[:, None]
    # closed lids: flatten the crease around the filled eye openings first
    we = sum(np.exp(-(np.linalg.norm((V - [sx * 0.031, 1.518, 0.152]) / [0.024, 0.014, 0.03], axis=1)) ** 2)
             for sx in (-1, 1))
    for _ in range(30):
        V = V + (0.5 * we)[:, None] * ((A @ V) / deg - V)
    for _ in range(iters):
        for k in (0.6, -0.62):
            V = V + (w * k)[:, None] * ((A @ V) / deg - V)
    return V


def build_skin():
    V, F = outer_shell(*bp3d_obj('FJ2810'))
    # neutral groin: drop everything inside the genital ellipsoid, keep the main piece, membrane-fill
    q = (V - GENITAL_CENTRE) / GENITAL_RADII
    inside = (q ** 2).sum(1) < 1
    F = F[~inside[F].any(1)]
    lab = components(len(V), F)
    tl = lab[F[:, 0]]
    F = F[tl == np.bincount(tl).argmax()]
    V, F = clean_boundary(V, F)
    loops = boundary_loops(F)
    groin = min(loops, key=lambda l: np.linalg.norm(V[l].mean(0) - GENITAL_CENTRE))
    V, F, inner = fill_hole(V, F, groin, bulge=0.004, rings=10)
    # blend the seam: relax a band around the patch
    ring = np.unique(F[np.isin(F, groin).any(1)])
    band = np.nonzero(np.linalg.norm((V - GENITAL_CENTRE) / (GENITAL_RADII * 1.35), axis=1) < 1)[0]
    patch = np.union1d(inner, np.union1d(ring, band))
    # the membrane webs down between the thighs; lift it to the natural crotch line
    low = patch[(V[patch, 1] < CROTCH_Y) & (np.abs(V[patch, 0]) < 0.05)]
    V[low, 1] = CROTCH_Y - (CROTCH_Y - V[low, 1]) * 0.2
    V = smooth_region(V, F, patch, iters=40, lam=0.5)
    # close the remaining holes (eyes get a gentle closed-lid bulge)
    for loop in boundary_loops(F):
        P = V[loop]
        eye = abs(abs(P[:, 0].mean()) - 0.031) < 0.01 and abs(P[:, 1].mean() - 1.518) < 0.01
        V, F, _ = fill_hole(V, F, loop, bulge=0.0045 if eye else 0.0)
    V = taubin(V, F, iters=4)
    V = refine_face(V, F)
    V, F = decimate(V, F, SKIN_TRIS)
    assert not boundary_loops(F), 'skin must be closed'
    return V, F


# ----------------------------------------------------------------------------------------------
# CPU renderer (previews and visibility)
def rasterize(P2, Z, tris, W, H, chunk=60000):
    """Vectorised z-buffer rasteriser. P2 (N,2) pixel coords, Z (N,) depth (smaller wins).
    Returns the triangle id per pixel (-1 = empty) and barycentrics."""
    A, B, C = P2[tris[:, 0]], P2[tris[:, 1]], P2[tris[:, 2]]
    lo = np.maximum(np.floor(np.minimum(np.minimum(A, B), C) - 0.5).astype(np.int64), 0)
    hi = np.ceil(np.maximum(np.maximum(A, B), C) - 0.5).astype(np.int64)
    hi[:, 0] = np.minimum(hi[:, 0], W - 1)
    hi[:, 1] = np.minimum(hi[:, 1], H - 1)
    size = np.maximum(hi - lo + 1, 0).max(1)
    den = (B[:, 0] - A[:, 0]) * (C[:, 1] - A[:, 1]) - (B[:, 1] - A[:, 1]) * (C[:, 0] - A[:, 0])
    ok = (size > 0) & (np.abs(den) > 1e-12)
    out = []
    k, prev = 1, 0
    maxs = size[ok].max() if ok.any() else 0
    while prev < maxs:
        sel = np.nonzero(ok & (size > prev) & (size <= k))[0]
        step = max(1, chunk // (k * k) + 1)
        ar = np.arange(k)
        for s in range(0, len(sel), step):
            idx = sel[s:s + step]
            gx = np.broadcast_to(lo[idx, 0, None, None] + ar[None, None, :], (len(idx), k, k))
            gy = np.broadcast_to(lo[idx, 1, None, None] + ar[None, :, None], (len(idx), k, k))
            px, py = gx + 0.5, gy + 0.5
            a, b, c = A[idx][:, None, None, :], B[idx][:, None, None, :], C[idx][:, None, None, :]
            d = den[idx][:, None, None]
            w0 = ((b[..., 0] - px) * (c[..., 1] - py) - (b[..., 1] - py) * (c[..., 0] - px)) / d
            w1 = ((c[..., 0] - px) * (a[..., 1] - py) - (c[..., 1] - py) * (a[..., 0] - px)) / d
            w2 = 1.0 - w0 - w1
            m = (w0 >= -1e-7) & (w1 >= -1e-7) & (w2 >= -1e-7) & (gx <= hi[idx, 0, None, None]) & (gy <= hi[idx, 1, None, None])
            if not m.any():
                continue
            ti = np.broadcast_to(idx[:, None, None], m.shape)[m]
            bc = np.stack([w0[m], w1[m], w2[m]], 1)
            dep = (bc * Z[tris[ti]]).sum(1)
            out.append((gy[m] * W + gx[m], dep, ti, bc))
        prev, k = k, k * 2
    tid = np.full(H * W, -1, np.int64)
    bary = np.zeros((H * W, 3), np.float32)
    if out:
        pix, dep, ti, bc = (np.concatenate(x) for x in zip(*out))
        order = np.lexsort((dep, pix))
        ps = pix[order]
        first = np.ones(len(ps), bool)
        first[1:] = ps[1:] != ps[:-1]
        sel = order[first]
        tid[ps[first]] = ti[sel]
        bary[ps[first]] = bc[sel]
    return tid.reshape(H, W), bary.reshape(H, W, 3)


class G:
    pass


def project(P, N, T, yaw, W, H, fov=21.0, dist=5.6, cy=0.90, cx=0.0):
    """Perspective camera looking at the figure from +z; turntable yaw in degrees."""
    a = np.radians(yaw)
    Ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    Pc = P @ Ry.T
    Nc = N @ Ry.T
    z = dist - Pc[:, 2]
    f = (H / 2) / np.tan(np.radians(fov / 2))
    X = W / 2 + f * (Pc[:, 0] - cx) / z
    Y = H / 2 - f * (Pc[:, 1] - cy) / z
    tid, bc = rasterize(np.stack([X, Y], 1), z, T, W, H)
    m = tid >= 0
    t = T[tid[m]]
    w = bc[m][..., None]
    g = G()
    g.mask, g.tid, g.W, g.H = m, tid[m], W, H
    g.pos = (Pc[t] * w).sum(1)
    g.nrm = unit((Nc[t] * w).sum(1))
    g.view = unit(np.array([cx, cy, dist]) - g.pos)
    return g


BG = np.array([8, 11, 16]) / 255.0      # canvas #080B10


def compose(g, col, glow=None, glow_sigma=6.0):
    img = np.tile(BG, (g.H, g.W, 1)).reshape(-1, 3)
    flat = np.nonzero(g.mask.ravel())[0]
    img[flat] = col
    img = img.reshape(g.H, g.W, 3)
    if glow is not None:
        gl = np.zeros((g.H, g.W, 3))
        gl.reshape(-1, 3)[flat] = glow
        img = img + ndimage.gaussian_filter(gl, (glow_sigma, glow_sigma, 0))
    return (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)]) / 255.0


LIGHT = unit(np.array([-0.45, 0.55, 0.70]))


def debug_render(P, T, name, yaws=(0, 180, -35), cy=None, dist=5.6, fov=21.0, W=600, H=1000):
    N = vertex_normals(P, T)
    cy = cy if cy is not None else (P[:, 1].max() + P[:, 1].min()) / 2
    ims = []
    for yaw in yaws:
        g = project(P, N, T, yaw, W, H, fov=fov, dist=dist, cy=cy)
        lam = np.clip(g.nrm @ LIGHT, 0, 1)
        ims.append(compose(g, np.array([0.82, 0.82, 0.86]) * (0.3 + 0.7 * lam)[:, None]))
    Image.fromarray(np.concatenate(ims, 1)).save(name)




# ----------------------------------------------------------------------------------------------
# Bones -> body parts and joint landmarks (BodyParts3D bones share the skin's frame exactly)
BONE_INDEX = 'isa_BP3D_4.0_obj_99/'
HEAD_BONES = ('ethmoid', 'frontal bone', 'occipital', 'parietal', 'temporal bone', 'sphenoid', 'vomer', 'mandible',
              'maxilla', 'nasal bone', 'lacrimal', 'palatine', 'zygomatic', 'concha', 'tooth', 'incisor', 'molar',
              'canine', 'premolar')
NECK_BONES = ('atlas', 'axis', 'cervical vertebra', 'hyoid')
ARM_BONES = ('humerus', 'radius', 'ulna', 'capitate', 'hamate', 'lunate', 'pisiform', 'scaphoid', 'trapezium',
             'trapezoid', 'triquetral', 'metacarpal', 'finger', 'thumb', 'hand')
# 'foot' and 'hand', not 'of foot': BodyParts3D names some bones "Navicular bone of left foot", and
# those fell through to the trunk, which labelled the sole of the foot as Hips.
LEG_BONES = ('femur', 'patella', 'tibia', 'fibula', 'calcaneus', 'talus', 'cuboid', 'cuneiform', 'foot', 'metatarsal',
             'toe', 'hallux')
PARTS = ['head', 'neck', 'trunk', 'armL', 'armR', 'legL', 'legR']


def bone_files():
    """[(file id, English name)] of every BodyParts3D bone element."""
    cf = os.path.join(CACHE, 'bp3d', 'bones.json')
    if not os.path.exists(cf):
        zf = zipfile.ZipFile(fetch(BP3D_ZIP, 'isa_BP3D_4.0_obj_99.zip'))
        els = urllib.request.urlopen('https://dbarchive.biosciencedbc.jp/data/bodyparts3d/LATEST/isa_element_parts.txt',
                                     timeout=120).read().decode('utf-8').splitlines()[1:]
        ids = sorted({l.split('\t')[2] for l in els if l.split('\t')[1] == 'bone organ'})
        out = []
        for fid in ids:
            head = zf.read(f'{BONE_INDEX}{fid}.obj')[:1200].decode('utf-8', 'replace')
            name = [l.split(' : ', 1)[1].strip() for l in head.splitlines() if l.startswith('# English name')]
            if name and name[0]:
                out.append((fid, name[0]))
        os.makedirs(os.path.dirname(cf), exist_ok=True)
        json.dump(out, open(cf, 'w'))
    return json.load(open(cf))


def bone_part(name):
    n = name.lower()
    side = 'L' if 'left' in n else ('R' if 'right' in n else '')
    if any(k in n for k in HEAD_BONES):
        return 'head'
    if any(k in n for k in NECK_BONES):
        return 'neck'
    if side and any(k in n for k in ARM_BONES):
        return 'arm' + side
    if side and any(k in n for k in LEG_BONES):
        return 'leg' + side
    return 'trunk'


def load_bones():
    pts, part, named = [], [], {}
    for fid, name in bone_files():
        V, _ = bp3d_obj(fid)
        named[name.lower()] = V
        pts.append(V[::2])
        part += [PARTS.index(bone_part(name))] * len(V[::2])
    return np.concatenate(pts), np.array(part), named


class Landmarks:
    pass


def landmarks(skin_V, skin_part, named):
    L = Landmarks()
    top = lambda V, d: V[V[:, 1] > V[:, 1].max() - d].mean(0)
    bot = lambda V, d: V[V[:, 1] < V[:, 1].min() + d].mean(0)
    for s, side in (('L', 'left'), ('R', 'right')):
        hum, rad = named[f'{side} humerus'], named[f'{side} radius']
        fem, tib = named[f'{side} femur'], named[f'{side} tibia']
        arm = skin_V[skin_part == PARTS.index('arm' + s)]
        leg = skin_V[skin_part == PARTS.index('leg' + s)]
        setattr(L, 'arm' + s, [top(hum, 0.04), bot(hum, 0.025), bot(rad, 0.015), arm[arm[:, 1].argmin()]])
        foot = leg[leg[:, 1] < leg[:, 1].min() + 0.1]
        setattr(L, 'leg' + s, [top(fem, 0.03), (bot(fem, 0.02) + top(tib, 0.02)) / 2, named[f'{side} talus'].mean(0),
                               foot[foot[:, 2].argmax()]])
    L.y_crest = named['right hip bone'][:, 1].max()
    L.y_crotch = CROTCH_Y
    ster = [v for k, v in named.items() if 'sternum' in k or 'xiphoid' in k]
    L.y_xiph = min(v[:, 1].min() for v in ster) if ster else None
    # torso centre line z_c(y) from the midline front/back extents of trunk skin
    mid = (np.abs(skin_V[:, 0]) < 0.02) & (skin_part == PARTS.index('trunk'))
    ys = np.arange(L.y_crotch, 1.40, 0.01)
    zc = [np.nan] * len(ys)
    for i, y in enumerate(ys):
        m = mid & (np.abs(skin_V[:, 1] - y) < 0.01)
        if m.sum() > 2:
            zc[i] = (skin_V[m, 2].max() + skin_V[m, 2].min()) / 2
    zc = np.array(zc)
    ok = ~np.isnan(zc)
    L.zc_y, L.zc = ys, ndimage.gaussian_filter1d(np.interp(ys, ys[ok], zc[ok]), 3, mode='nearest')
    # navel: deepest local dip of the front midline profile, 0.18-0.34 m above the crotch
    fm = (np.abs(skin_V[:, 0]) < 0.006) & (skin_V[:, 2] > np.interp(skin_V[:, 1], L.zc_y, L.zc))
    fm &= (skin_V[:, 1] > L.y_crotch + 0.18) & (skin_V[:, 1] < L.y_crotch + 0.34)
    yy = np.arange(L.y_crotch + 0.18, L.y_crotch + 0.34, 0.004)
    prof = np.array([skin_V[fm & (np.abs(skin_V[:, 1] - y) < 0.004), 2].max() if (fm & (np.abs(skin_V[:, 1] - y) < 0.004)).any() else np.nan for y in yy])
    ok = ~np.isnan(prof)
    prof = np.interp(yy, yy[ok], prof[ok])
    L.y_navel = float(yy[np.argmax(ndimage.gaussian_filter1d(prof, 6) - prof)])
    if L.y_xiph is None:
        L.y_xiph = L.y_navel + 0.17
    return L


def zc_at(L, y):
    return np.interp(y, L.zc_y, L.zc)


def limb_coords(p, pts, lateral_sign, front=np.array([0, 0, 1.0])):
    """Arclength s along a joint polyline and angle theta around it (0 front, +90 lateral, 180 back)."""
    pts = [np.asarray(q, float) for q in pts]
    nseg = len(pts) - 1
    best = np.full(len(p), np.inf)
    s, th = np.zeros(len(p)), np.zeros(len(p))
    acc = 0.0
    for i in range(nseg):
        a0, a1 = pts[i], pts[i + 1]
        ln = np.linalg.norm(a1 - a0)
        ax = (a1 - a0) / ln
        t = (p - a0) @ ax
        d = np.linalg.norm(p - (a0 + np.clip(t, 0, ln)[:, None] * ax), axis=1)
        te = t.copy()
        if i > 0:
            te = np.maximum(te, 0)
        if i < nseg - 1:
            te = np.minimum(te, ln)
        r = p - (a0 + te[:, None] * ax)
        f = unit(front - (front @ ax) * ax)
        lat = np.cross(ax, f)
        if lat[0] * lateral_sign < 0:
            lat = -lat
        u = d < best
        best[u] = d[u]
        s[u] = acc + te[u]
        th[u] = np.degrees(np.arctan2(r[u] @ lat, r[u] @ f))
        acc += ln
    return s, th


def seg_lengths(pts):
    return [float(np.linalg.norm(np.asarray(pts[i + 1]) - np.asarray(pts[i]))) for i in range(len(pts) - 1)]


def classify_regions(p, part, L):
    """BodyRegion index per point (BodyParts3D frame) given its nearest-bone body part."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    left = x >= 0
    side = lambda l, r: np.where(left, RI[l], RI[r])
    reg = np.full(len(p), RI['chest'])
    reg[part == PARTS.index('head')] = RI['head']
    reg[part == PARTS.index('neck')] = RI['neck']
    # trunk
    tr = part == PARTS.index('trunk')
    front = z > zc_at(L, y)
    yn = L.y_navel
    y_chest = L.y_xiph + 0.01 - 0.55 * np.minimum(ax, 0.15)      # costal arch
    y_hipf = yn - 0.075
    y_back, y_crest = yn + 0.11, L.y_crest - 0.04
    f = tr & front
    reg[f & (y >= y_chest)] = RI['chest']
    reg[f & (y < y_chest) & (y >= y_hipf)] = RI['abdomen']
    low = f & (y < y_hipf)
    reg[low & (ax < 0.095)] = RI['hips']
    reg[low & (ax >= 0.095)] = side('leftHip', 'rightHip')[low & (ax >= 0.095)]
    b = tr & ~front
    reg[b & (y >= y_back)] = RI['upperBack']
    reg[b & (y < y_back) & (y >= y_crest)] = RI['lowerBack']
    low = b & (y < y_crest)
    sac = ax < np.interp(y, [L.y_crotch, y_crest], [0.012, 0.05])
    reg[low & sac] = RI['hips']
    reg[low & ~sac] = side('leftHip', 'rightHip')[low & ~sac]
    # shoulder cap (trunk or arm skin over the shoulder joint)
    S = np.where(left[:, None], L.armL[0], L.armR[0])
    cap = (np.linalg.norm(p - S - np.stack([np.sign(x + 1e-9) * 0.012, np.full(len(x), 0.012), np.zeros(len(x))], 1), axis=1) < 0.098)
    cap &= (ax > np.abs(S[:, 0]) - 0.07) & (tr | (part == PARTS.index('armL')) | (part == PARTS.index('armR')))
    reg[cap] = side('leftShoulder', 'rightShoulder')[cap]
    # arms
    for s_, sg, nm in (('L', 1, 'left'), ('R', -1, 'right')):
        m = part == PARTS.index('arm' + s_)
        pts = getattr(L, 'arm' + s_)
        lu, lf, _ = seg_lengths(pts)
        s, _ = limb_coords(p[m], pts, sg)
        r = np.full(m.sum(), RI[nm + 'Hand'])
        r[s < lu + lf + 0.02] = RI[nm + 'Wrist']
        r[s < lu + lf - 0.025] = RI[nm + 'Forearm']
        r[s < lu + 0.04] = RI[nm + 'Elbow']
        r[s < lu - 0.035] = RI[nm + 'UpperArm']
        r[(s < 0.3 * lu) | cap[m]] = RI[nm + 'Shoulder']
        reg[m] = r
    # legs
    for s_, sg, nm in (('L', 1, 'left'), ('R', -1, 'right')):
        m = part == PARTS.index('leg' + s_)
        pts = getattr(L, 'leg' + s_)
        lt, ls, _ = seg_lengths(pts)
        s, th = limb_coords(p[m], pts, sg)
        yy, zz, aa = y[m], z[m], ax[m]
        A = pts[2]
        r = np.where(np.abs(th) < 90, RI[nm + 'Shin'], RI[nm + 'Calf'])
        r[s < lt + 0.05] = RI[nm + 'Knee']
        r[s < lt - 0.05] = RI[nm + 'Thigh']
        glute = (np.abs(th) > 100) & (yy > L.y_crotch - 0.035 + 0.3 * np.maximum(aa - 0.05, 0))
        lateral = (th > 55) & (th <= 100) & (yy > L.y_crotch + 0.01)
        r[(s < lt - 0.05) & (glute | lateral)] = RI[nm + 'Hip']
        r[yy < A[1] + 0.05] = RI[nm + 'Ankle']
        r[yy < A[1] - 0.018 + 0.45 * np.maximum(zz - A[2] - 0.02, 0)] = RI[nm + 'Foot']
        reg[m] = r
    return reg


def label_skin(V, F, classify):
    """Per-vertex labels (majority-smoothed), then triangles that straddle a boundary are split
    where the classifier's label changes along each edge, so region borders are clean lines.
    Returns (V, F, vertex labels, triangle labels)."""
    lab = classify(V)
    A = adjacency(len(V), F) + sparse.identity(len(V), format='csr')
    for _ in range(6):
        oh = sparse.csr_matrix((np.ones(len(lab)), (np.arange(len(lab)), lab)), shape=(len(lab), len(REGION_IDS)))
        lab = np.asarray((A @ oh).argmax(1)).ravel()
    L3 = lab[F]
    diff = ~((L3[:, 0] == L3[:, 1]) & (L3[:, 1] == L3[:, 2]))
    ce = np.unique(np.concatenate([np.sort(F[diff & (L3[:, i] != L3[:, j])][:, [i, j]], 1)
                                   for i, j in ((0, 1), (1, 2), (2, 0))]), axis=0)
    e0, e1 = ce[:, 0], ce[:, 1]
    ts = np.linspace(0, 1, 11)[1:-1]
    labs = np.stack([classify(V[e0] * (1 - t) + V[e1] * t) for t in ts], 1)
    ne = labs != lab[e0][:, None]
    first = np.where(ne.any(1), ne.argmax(1), len(ts) // 2)
    tc = np.where(ne.any(1), (np.concatenate([[0.0], ts])[first] + ts[first]) / 2, 0.5)
    nV = len(V)
    ekey = {(int(a), int(b)): nV + k for k, (a, b) in enumerate(ce)}
    newV = [V, V[e0] * (1 - tc[:, None]) + V[e1] * tc[:, None]]
    newL = [lab, np.zeros(len(ce), int)]
    cross = lambda a, b: ekey[(a, b) if a < b else (b, a)]
    tris, tl, centres, cl = [], [], [], []
    base_c = nV + len(ce)
    for ti in np.nonzero(diff)[0]:
        g, l = F[ti], L3[ti]
        if l[0] != l[1] and l[1] != l[2] and l[0] != l[2]:
            ab, bc, ca = cross(g[0], g[1]), cross(g[1], g[2]), cross(g[2], g[0])
            c = base_c + len(centres)
            centres.append(V[g].mean(0))
            tris += [(g[0], ab, c), (g[0], c, ca), (g[1], bc, c), (g[1], c, ab), (g[2], ca, c), (g[2], c, bc)]
            tl += [l[0], l[0], l[1], l[1], l[2], l[2]]
        else:
            k = 0 if l[1] == l[2] else (1 if l[0] == l[2] else 2)
            a, b, c = g[k], g[(k + 1) % 3], g[(k + 2) % 3]
            ab, ac = cross(a, b), cross(a, c)
            tris += [(a, ab, ac), (ab, b, c), (ab, c, ac)]
            tl += [l[k], l[(k + 1) % 3], l[(k + 1) % 3]]
    if centres:
        newV.append(np.array(centres))
        newL.append(np.zeros(len(centres), int))
    V2 = np.concatenate(newV)
    F2 = np.concatenate([F[~diff], np.array(tris, int).reshape(-1, 3)])
    T2 = np.concatenate([L3[~diff, 0], np.array(tl, int)])
    lab2 = np.concatenate(newL)
    lab2[nV:] = -1
    # new vertices take the label of any triangle using them (only used for muscle lookups)
    for i in range(3):
        m = lab2[F2[:, i]] < 0
        lab2[F2[m, i]] = T2[m]
    return V2, F2, lab2, T2


# ----------------------------------------------------------------------------------------------
# Muscles (Z-Anatomy)
SKIP_PATH = ('Bursae', 'Tendon sheaths', 'Fasciae.g', 'Extra-ocular', 'Muscles of tongue', 'Muscles of soft palate',
             'Pharyngeal', 'Laryngeal', 'Pelvic diaphragm', 'Levator ani', 'Perineal', 'Rotatores', 'Multifidus',
             'Interspinales', 'Intertransversarii', 'Suboccipital', 'Levatores costarum', 'Auditory ossicles',
             'Intrinsic auricular', 'Endo-abdominal')
SKIP_NAME = ('Cross Section', 'intercostal', 'Diaphragm', 'Transversus thoracis', 'tarsus', 'pterygoid', 'Longus colli',
             'Longus capitis', 'Rectus anterior capitis', 'Rectus lateralis capitis', 'Psoas', 'Iliacus', 'Quadratus lumborum',
             'Transversus abdominis', 'Obturator', 'gemellus', 'Piriformis', 'Quadratus femoris', 'Subclavius', 'Popliteus',
             'Tibialis posterior', 'Flexor digitorum longus', 'Flexor hallucis longus', 'Pronator quadratus', 'Supinator',
             'Coracobrachialis', 'Serratus posterior', 'Semispinalis', 'Spinalis', 'Longissimus colli',
             'Iliocostalis colli', 'Subscapularis', 'Transverse arytenoid', 'Deep part of masseter', 'Palatopharyngeus',
             'Genioglossus', 'Hyoglossus', 'Stylopharyngeus', 'Stylohyoid', 'Geniohyoid', 'Mylohyoid', 'Pyramidalis',
             'Linea alba', 'Palpebral part', 'Vastus intermedius', 'Adductor brevis', 'Adductor minimus', 'Pectoralis minor', 'Rhomboid minor',
             'Flexor digitorum profundus', 'Flexor pollicis longus', 'Extensor indicis')
TENDON_WORDS = ('tendon', 'aponeurosis', 'Linea alba', 'tract', 'ligament', 'retinaculum')
MIDLINE_NAMES = ('Linea alba',)


def pretty(name):
    """Z-Anatomy object name -> (display name, side, kind)."""
    import re
    side = 'right' if name.endswith('.r') else ('left' if name.endswith('.l') else 'midline')
    n = re.sub(r'\.[rl]$', '', name).strip().strip('()').strip()
    n = re.sub(r'\bmuscles?\b', '', n)
    n = re.sub(r'\s+', ' ', n).strip()
    m = re.match(r'^(.*?)\b(head|part|belly|portion|layer)s? of (.*)$', n, re.I)
    if m:
        n = f'{m.group(3)} ({m.group(1).strip().lower()} {m.group(2).lower()})'.replace('( ', '(')
    m = re.match(r'^Tendon of (.*)$', n, re.I)
    if m:
        n = f'{m.group(1)} tendon'
    n = n.replace('Bucinator', 'Buccinator').replace('Lumbrical of', 'Lumbricals of')
    kind = 'tendon' if any(w.lower() in name.lower() for w in TENDON_WORDS) else 'muscle'
    return n[0].upper() + n[1:], side, kind


def load_muscles(to_bp):
    cf = os.path.join(CACHE, 'za_muscles.npz')
    if not os.path.exists(cf):
        parts = za_parts('MuscularSystem100')
        keep = [q for q in parts if len(q['F']) and not any(k in '/'.join(q['path']) for k in SKIP_PATH)
                and not any(k.lower() in q['name'].lower() for k in SKIP_NAME)]
        np.savez_compressed(cf, names=np.array([q['name'] for q in keep]),
                            V=np.array([q['V'] for q in keep], dtype=object), F=np.array([q['F'] for q in keep], dtype=object))
    d = np.load(cf, allow_pickle=True)
    out = []
    for n, V, F in zip(d['names'], d['V'], d['F']):
        if any(k.lower() in str(n).lower() for k in SKIP_NAME):
            continue
        V, F = weld(to_bp(V.astype(np.float64)), F.astype(np.int64), 1e-7)
        if len(F) >= 8:
            out.append(dict(name=str(n), V=V, F=F))
    return out


def snap_field(parts, skin_V, skin_F, skin_N, skin_tree, gap=0.0015, max_shift=0.03):
    """Per skin vertex, how far everything beneath it must move along the skin normal so the
    outermost muscle surface sits `gap` under the skin. Smooth across the skin, so muscles keep
    their thickness, relief and layering; the red figure's envelope then matches the skin."""
    allV = np.concatenate([q['V'] for q in parts])
    _, j = skin_tree.query(allV)
    sd = ((allV - skin_V[j]) * skin_N[j]).sum(1)
    D = np.full(len(skin_V), -np.inf)
    np.maximum.at(D, j, sd)
    known = np.isfinite(D)
    D = np.where(known, np.clip(D + gap, -max_shift, max_shift), 0.0)
    A = adjacency(len(skin_V), skin_F)
    deg = np.asarray(A.sum(1)).ravel()
    for _ in range(200):                                   # fill uncovered skin by diffusion
        D = np.where(known, D, (A @ D) / deg)
    for _ in range(12):                                    # then smooth everything
        D = 0.5 * D + 0.5 * (A @ D) / deg
    return D


def apply_snap(V, D, skin_V, skin_N, skin_tree):
    _, j = skin_tree.query(V)
    return V - skin_N[j] * D[j][:, None]


def rectus_to_midline(V, gap=0.0012):
    """Stretch a rectus abdominis medially (lateral border fixed) so left and right meet at the
    midline and the front of the abdomen reads as one continuous surface."""
    ax, y = np.abs(V[:, 0]), V[:, 1]
    ys = np.arange(y.min(), y.max() + 0.01, 0.01)
    med = np.array([ax[np.abs(y - b) < 0.008].min() if (np.abs(y - b) < 0.008).any() else np.nan for b in ys])
    lat = np.array([ax[np.abs(y - b) < 0.008].max() if (np.abs(y - b) < 0.008).any() else np.nan for b in ys])
    ok = ~np.isnan(med)
    med = ndimage.gaussian_filter1d(np.interp(ys, ys[ok], med[ok]), 2, mode='nearest')
    lat = ndimage.gaussian_filter1d(np.interp(ys, ys[ok], lat[ok]), 2, mode='nearest')
    m, l = np.interp(y, ys, med), np.interp(y, ys, lat)
    k = (l - gap) / np.maximum(l - m, 1e-6)
    new = np.maximum(l - (l - ax) * k, gap * 0.5)
    V = V.copy()
    V[:, 0] = np.sign(V[:, 0]) * new
    return V


# Sheets that lie over another muscle. The part of the sheet directly above it is dropped, so the
# muscle underneath can be seen and tapped: both obliques' aponeuroses cover the rectus abdominis
# in the source model, which made the whole half of the abdomen one tap target.
UNCOVER = (('External abdominal oblique', 'Rectus abdominis'), ('Internal abdominal oblique', 'Rectus abdominis'))


def uncover(parts, pairs=UNCOVER, reach=0.006, depth=0.03):
    """Runs on the full-detail parts, before the visibility passes, so the uncovered muscle gets the
    triangle budget of a visible one. A sheet triangle (either face of the sheet) is dropped when
    the muscle underneath lies straight behind it, seen from the front, within `depth`."""
    named = [(pretty(q['name'])[0], pretty(q['name'])[1]) for q in parts]
    for cover, under in pairs:
        for q, (name, side) in zip(parts, named):
            if name != cover:
                continue
            U = [p['V'] for p, (n2, s2) in zip(parts, named) if n2 == under and s2 == side]
            if not U:
                continue
            U = np.concatenate(U)
            tree = cKDTree(U[:, :2])
            P = q['V'][q['F']]
            c = P.mean(1)
            over = np.zeros(len(c), bool)
            for k, ids in enumerate(tree.query_ball_point(c[:, :2], reach)):
                if ids:
                    dz = c[k, 2] - U[ids, 2]
                    over[k] = bool(((dz > -0.002) & (dz < depth)).any())
            q['V'], q['F'] = compact(q['V'], q['F'][~over])
            print(f"  {cover} ({side}): {int(over.sum())} of {len(over)} triangles in front of {under} dropped")


def split_at_navel(mparts, y_navel, name='Rectus abdominis'):
    """Each rectus abdominis becomes an upper and a lower part at the navel, so the front of the
    abdomen is four tap targets."""
    out = []
    for q in mparts:
        if q['name'] != name:
            out.append(q)
            continue
        up = q['V'][q['F']].mean(1)[:, 1] >= y_navel
        for mask, label in ((up, 'upper'), (~up, 'lower')):
            if mask.sum() >= 20:
                V_, F_ = compact(q['V'], q['F'][mask])
                out.append(dict(q, V=V_, F=F_, name=f'{name} ({label} part)'))
    return out


def sphere_dirs():
    dirs = [[0, 1, 0], [0, -1, 0]]
    for el in (-35, 0, 35):
        for az in range(0, 360, 30):
            a, e = np.radians(az + (15 if el else 0)), np.radians(el)
            dirs.append([np.sin(a) * np.cos(e), np.sin(e), np.cos(a) * np.cos(e)])
    return unit(np.array(dirs, float))


def visibility(V, F, px=0.003, dirs=None):
    """Visible pixel count per triangle, summed over orthographic views from all around."""
    dirs = sphere_dirs() if dirs is None else dirs
    cnt = np.zeros(len(F))
    c = V.mean(0)
    for d in dirs:
        up = np.array([0, 0, 1.0]) if abs(d[1]) > 0.9 else np.array([0, 1.0, 0])
        u = unit(np.cross(up, d))
        v = np.cross(d, u)
        P = V - c
        X, Y, Z = P @ u / px, -(P @ v) / px, -(P @ d)
        W, H = int(X.max() - X.min()) + 4, int(Y.max() - Y.min()) + 4
        tid, _ = rasterize(np.stack([X - X.min() + 2, Y - Y.min() + 2], 1), Z, F, W, H)
        t = tid[tid >= 0]
        cnt += np.bincount(t, minlength=len(F))
    return cnt


def merge(parts):
    Vs, Fs, pid, o = [], [], [], 0
    for i, q in enumerate(parts):
        Vs.append(q['V'])
        Fs.append(q['F'] + o)
        pid.append(np.full(len(q['F']), i))
        o += len(q['V'])
    return np.concatenate(Vs), np.concatenate(Fs), np.concatenate(pid)


def build_underlayer(skin_V, skin_F, skin_tree, muscle_pts, bone_pts, closed=(), below=0.003):
    """The skin pushed inward so it sits `below` under the outermost muscle beneath each point
    (half-way to the bone, at most 4.5 mm, where no muscle covers): one continuous surface that
    fills every gap between muscles without covering them. `closed` = [(centre, radii)] zones
    (eye and mouth openings) kept shallow so the face reads as closed lids and lips."""
    N = vertex_normals(skin_V, skin_F)
    _, j = skin_tree.query(muscle_pts)
    sd = ((muscle_pts - skin_V[j]) * N[j]).sum(1)
    top = np.full(len(skin_V), -np.inf)
    np.maximum.at(top, j, sd)
    covered = np.isfinite(top)
    db, _ = cKDTree(bone_pts).query(skin_V)
    bare = np.clip(0.5 * db, 0.0015, 0.0045)
    need = np.clip(np.where(covered, -top + below, bare), 0.0015, 0.04)
    A = adjacency(len(skin_V), skin_F).tocsr()
    depth = need.copy()
    for _ in range(2):                                     # dilate so borders dip under muscle edges
        depth = np.maximum(depth, A.multiply(depth[None, :]).max(1).toarray().ravel())
    deg = np.asarray(A.sum(1)).ravel()
    for _ in range(4):
        depth = np.maximum(need, 0.5 * depth + 0.5 * (A @ depth) / deg)
    depth = np.minimum(depth, np.maximum(0.85 * db, 0.0015))
    for c, r in closed:
        q = np.linalg.norm((skin_V - c) / r, axis=1)
        w = np.clip((1.6 - q) / 0.6, 0, 1)                 # 1 inside the opening, fading out by 1.6x
        depth = depth * (1 - w) + 0.002 * w
    return decimate(skin_V - N * depth[:, None], skin_F.copy(), UNDER_TRIS)


# ----------------------------------------------------------------------------------------------
# Anchors
REGION_VIEW = {'upperBack': (0, 0, -1), 'lowerBack': (0, 0, -1), 'rightCalf': (0, 0, -1), 'leftCalf': (0, 0, -1),
               'rightHand': (-0.7, 0, 0.7), 'leftHand': (0.7, 0, 0.7), 'rightFoot': (0, 0.5, 0.85), 'leftFoot': (0, 0.5, 0.85),
               'rightShoulder': (-0.45, 0.25, 0.85), 'leftShoulder': (0.45, 0.25, 0.85),
               'rightHip': (-0.8, 0, -0.6), 'leftHip': (0.8, 0, -0.6)}
MIDLINE_REGIONS = {'head', 'neck', 'chest', 'abdomen', 'upperBack', 'lowerBack', 'hips'}


def tri_area(P, T):
    return 0.5 * np.linalg.norm(np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]]), axis=1)


def surface_anchor(P, N, c, d):
    """Front-most surface point along direction d near the line through c, and its local normal."""
    d = unit(np.asarray(d, float))
    rel = P - c
    perp = np.linalg.norm(rel - (rel @ d)[:, None] * d, axis=1)
    ok = (N @ d) > 0.15
    if not ok.any():
        ok[:] = True
    perp = np.where(ok, perp, np.inf)
    near = perp < perp.min() + 0.012
    i = np.argmax(np.where(near, P @ d, -np.inf))
    nb = np.linalg.norm(P - P[i], axis=1) < 0.02
    return P[i], unit(N[nb].mean(0))


def region_anchors(V, F, N, tri_reg):
    area = tri_area(V, F)
    cen = V[F].mean(1)
    out = []
    for i, name in enumerate(REGION_IDS):
        m = tri_reg == i
        c = (cen[m] * area[m, None]).sum(0) / area[m].sum()
        if name in MIDLINE_REGIONS:
            c[0] = 0.0
        d = np.array(REGION_VIEW.get(name, (0, 0, 1)), float)
        if name.startswith('right'):
            d[0] = -abs(d[0])
        vid = np.unique(F[m])
        a, n = surface_anchor(V[vid], N[vid], c, d)
        ext = V[vid].max(0) - V[vid].min(0)
        out.append((a, n, float(np.clip(0.5 * np.linalg.norm(ext), 0.05, 0.45))))
    return out


# ----------------------------------------------------------------------------------------------
# Output
NONE = 0xFFFFFFFF


def write_layer(f, pos, nrm, groups, tri_region, tris):
    f.write(struct.pack('<III', len(pos), len(tris), len(groups)))
    f.write(pos.astype('<f4').tobytes())
    f.write(nrm.astype('<f4').tobytes())
    for g in groups:
        f.write(struct.pack('<IIII', *g))
    f.write(tri_region.astype(np.uint8).tobytes())
    f.write(b'\0' * ((-len(tri_region)) % 4))
    f.write(tris.astype('<u4').tobytes())


def rnd(v, k=4):
    return [round(float(x), k) for x in v]


# ----------------------------------------------------------------------------------------------
# Preview looks (CPU approximations of the SceneKit materials in Body3D.swift)
def ssao(g, strength=9.0, sigma=7.0):
    depth = np.full((g.H, g.W), np.nan)
    depth.reshape(-1)[np.nonzero(g.mask.ravel())[0]] = -g.pos[:, 2]
    fill = np.where(np.isnan(depth), np.nanmax(depth) + 0.05, depth)
    blur = ndimage.gaussian_filter(fill, sigma)
    occ = np.clip((fill - blur) * strength, 0, 0.6)
    return 1 - occ.reshape(-1)[np.nonzero(g.mask.ravel())[0]]


def blue_look(g):
    lam = np.clip(g.nrm @ LIGHT, 0, 1)
    ndv = np.clip((g.nrm * g.view).sum(1), 0, 1)
    fres = (1 - ndv) ** 2.2
    base = hexc('#1B3A8C') * (1 - lam[:, None]) * 0.75 + hexc('#4F8EFF') * lam[:, None] * 0.62
    base *= ssao(g, 5.0)[:, None]
    rim = hexc('#B9DAFF') * (fres * 1.25)[:, None]
    col = base + rim
    alpha = np.clip(0.74 + 0.26 * fres, 0, 1)
    col = BG * (1 - alpha[:, None]) + col * alpha[:, None]
    return col, rim * 0.55 + hexc('#4F8EFF') * 0.06


def muscle_look(g, tone):
    lam = np.clip(g.nrm @ LIGHT, 0, 1)
    wrap = np.clip((g.nrm @ LIGHT + 0.35) / 1.35, 0, 1)
    h = unit(LIGHT + g.view)
    spec = np.clip((g.nrm * h).sum(1), 0, 1) ** 24 * 0.10
    ndv = np.clip((g.nrm * g.view).sum(1), 0, 1)
    rim = (1 - ndv) ** 3 * 0.10
    ao = ssao(g, 12.0, 5.0)
    col = tone * (0.16 + 0.62 * wrap + 0.22 * lam)[:, None] * ao[:, None] + (spec + rim)[:, None] * np.array([1.0, 0.75, 0.72])
    return col


def region_palette():
    import colorsys
    pal = np.zeros((len(REGION_IDS), 3))
    base, k = {}, 0
    for i, r in enumerate(REGION_IDS):
        key = r.replace('left', '').replace('right', '').lower()
        if key not in base:
            base[key] = k
            k += 1
        pal[i] = colorsys.hls_to_rgb((base[key] * 0.618034) % 1.0, 0.62 if r.startswith('left') else 0.5, 0.75)
    return pal


def muscle_tones(entries):
    rng = np.random.RandomState(7)
    tones = []
    for e in entries:
        if e['kind'] == 'tendon':
            t = hexc('#93403F')
        else:
            t = hexc('#9C2328') * (1 + rng.uniform(-0.08, 0.08)) + np.array([rng.uniform(-0.02, 0.02), 0, 0])
        tones.append(np.clip(t, 0, 1))
    return np.array(tones)


UNDER_TONE = hexc('#74191E')


def render_previews(skin, mus, entries, W=900, H=1400):
    sV, sF, sreg = skin
    sN = vertex_normals(sV, sF)
    for name, yaw in (('front', 0), ('back', 180), ('34', -35)):
        g = project(sV, sN, sF, yaw, W, H)
        col, glow = blue_look(g)
        Image.fromarray(compose(g, col, glow, 7.0)).save(os.path.join(DESIGN, f'preview-{name}.png'), optimize=True)
    mV, mN, mF, mgrp = mus
    tones = np.concatenate([muscle_tones(entries), UNDER_TONE[None]])
    for name, yaw in (('front', 0), ('back', 180), ('34', -35)):
        g = project(mV, mN, mF, yaw, W, H)
        col = muscle_look(g, tones[mgrp[g.tid]])
        Image.fromarray(compose(g, col)).save(os.path.join(DESIGN, f'preview-muscle-{name}.png'), optimize=True)
    pal = region_palette()
    ims = []
    for yaw in (0, 180):
        g = project(sV, sN, sF, yaw, W // 2, H // 2)
        lam = np.clip(g.nrm @ LIGHT, 0, 1)
        ims.append(compose(g, pal[sreg[g.tid]] * (0.55 + 0.45 * lam)[:, None]))
    Image.fromarray(np.concatenate(ims, 1)).save(os.path.join(DESIGN, 'preview-regions.png'), optimize=True)


# ----------------------------------------------------------------------------------------------
def slug(name):
    import re
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def main():
    os.makedirs(OUT, exist_ok=True)
    print('skin')
    sV, sF = build_skin()
    print('bones and regions')
    bpts, bpart, named = load_bones()
    btree = cKDTree(bpts)
    s_part = bpart[btree.query(sV)[1]]
    L = landmarks(sV, s_part, named)
    sV, sF, s_lab, s_reg = label_skin(sV, sF, lambda P: classify_regions(P, bpart[btree.query(P)[1]], L))
    sN = vertex_normals(sV, sF)
    print(f'  navel y {L.y_navel:.3f}, xiphoid y {L.y_xiph:.3f}, crest y {L.y_crest:.3f}')

    print('muscles')
    parts = load_muscles(za_to_bp())
    stree = cKDTree(sV)
    D = snap_field(parts, sV, sF, sN, stree)
    print(f'  snap shift: median {np.median(np.abs(D)) * 1000:.1f} mm, max {np.abs(D).max() * 1000:.1f} mm')
    for q in parts:
        q['V'] = apply_snap(q['V'], D, sV, sN, stree)
        if q['name'].startswith('Rectus abdominis'):
            q['V'] = rectus_to_midline(q['V'])
        if face_weight(q['V']).mean() > 0.5:               # soften the scan-like facial rings
            q['V'] = taubin(q['V'], q['F'], iters=12)
    uncover(parts)
    for q in parts:
        q['pre'] = decimate(q['V'], q['F'], max(250, len(q['F']) * 0.4))
    pre = [dict(V=q['pre'][0], F=q['pre'][1]) for q in parts]
    V, F, pid = merge(pre)
    vis = np.bincount(pid, weights=visibility(V, F), minlength=len(parts))
    keep = [i for i in range(len(parts)) if vis[i] >= 40]
    print(f'  pass 1: {len(keep)} of {len(parts)} parts visible')
    kpts = np.concatenate([np.concatenate([pre[i]['V'], pre[i]['V'][pre[i]['F']].mean(1)]) for i in keep])
    oris = np.concatenate([q['V'] for q in parts if q['name'].startswith('Orbicularis oris')])
    mouth = np.array([0.0, (oris[:, 1].max() + oris[:, 1].min()) / 2, oris[:, 2].max()])
    closed = [(np.array([sx * 0.031, 1.518, 0.155]), np.array([0.017, 0.009, 0.03])) for sx in (-1, 1)]
    closed.append((mouth, np.array([0.024, 0.008, 0.03])))
    uV, uF = build_underlayer(sV, sF, stree, kpts, bpts, closed)
    V, F, pid = merge([pre[i] for i in keep] + [dict(V=uV, F=uF)])
    cnt = visibility(V, F)
    vis2 = np.bincount(pid, weights=cnt, minlength=len(keep) + 1)[:len(keep)]
    final = [(keep[k], vis2[k]) for k in range(len(keep)) if vis2[k] >= 60]
    print(f'  pass 2: {len(final)} parts kept')
    w = np.array([v for _, v in final]) ** 0.75
    budget = np.maximum(40, np.round(MUSCLE_TRIS * w / w.sum())).astype(int)
    budget = np.minimum(budget, [len(parts[i]['F']) for i, _ in final])
    mparts = []
    for (i, _), b in zip(final, budget):
        V_, F_ = decimate(parts[i]['V'], parts[i]['F'], b)
        name, side, kind = pretty(parts[i]['name'])
        mparts.append(dict(V=V_, F=F_, name=name, side=side, kind=kind, src=parts[i]['name']))

    mparts = split_at_navel(mparts, L.y_navel)

    # regions for muscle triangles: region of the nearest skin point
    for q in mparts:
        _, j = stree.query(q['V'][q['F']].mean(1))
        q['treg'] = s_lab[j]
        area = tri_area(q['V'], q['F'])
        q['region'] = int(np.bincount(q['treg'], weights=area, minlength=len(REGION_IDS)).argmax())
    _, j = stree.query(uV[uF].mean(1))
    u_treg = s_lab[j]

    # final visibility on the shipped muscle layer -> anchors of each muscle
    V, F, pid = merge(mparts + [dict(V=uV, F=uF)])
    cnt = visibility(V, F, px=0.004)
    FN = unit(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]))
    cen = V[F].mean(1)
    for k, q in enumerate(mparts):
        m = (pid == k)
        wv = cnt[m] + 1e-6
        c = (cen[m] * wv[:, None]).sum(0) / wv.sum()
        n = unit((FN[m] * wv[:, None]).sum(0))
        tri = np.argmin(np.linalg.norm(cen[m] - c, axis=1) - 0.002 * (cnt[m] > 0))
        q['anchor'], q['normal'] = cen[m][tri], n
        q['visible'] = float(cnt[m].sum())

    # order muscles by region, then name; ids unique per side
    mparts.sort(key=lambda q: (q['region'], q['name'], q['side']))
    entries = []
    for q in mparts:
        sid = {'left': '.l', 'right': '.r'}.get(q['side'], '')
        entries.append(dict(id=slug(q['name']) + sid, name=q['name'], side=q['side'], kind=q['kind'],
                            region=REGION_IDS[q['region']]))
    ids = [e['id'] for e in entries]
    for e in entries:
        if ids.count(e['id']) > 1:
            k = sum(1 for x in entries[:entries.index(e)] if x['id'] == e['id'])
            e['id'] += f'-{k + 1}' if k else ''

    # global frame: 1.80 m, feet on y = 0, centred on x/z
    y0 = sV[:, 1].min()
    k = HEIGHT / (sV[:, 1].max() - y0)
    c = np.array([(sV[:, 0].max() + sV[:, 0].min()) / 2, y0, (sV[:, 2].max() + sV[:, 2].min()) / 2])
    tf = lambda P: (np.asarray(P) - c) * k

    # skin layer: triangles sorted by region
    order = np.argsort(s_reg, kind='stable')
    sFo, s_rego = sF[order], s_reg[order]
    s_groups = []
    for r in range(len(REGION_IDS)):
        idx = np.nonzero(s_rego == r)[0]
        assert len(idx), REGION_IDS[r]
        s_groups.append((r, NONE, int(idx[0]), len(idx)))
    sVt = tf(sV)
    # muscle layer: underlayer (per region) first, then one group per muscle
    mV, mN, mT, mR, m_groups, mgrp = [], [], [], [], [], []
    o = t0 = 0
    uN = vertex_normals(uV, uF)
    uo = np.argsort(u_treg, kind='stable')
    for r in range(len(REGION_IDS)):
        idx = uo[u_treg[uo] == r]
        if len(idx):
            m_groups.append((r, NONE, t0, len(idx)))
            t0 += len(idx)
    mV.append(tf(uV)); mN.append(uN); mT.append(uF[uo]); mR.append(u_treg[uo]); mgrp.append(np.full(len(uF), len(mparts)))
    o = len(uV)
    for k2, q in enumerate(mparts):
        mV.append(tf(q['V'])); mN.append(vertex_normals(q['V'], q['F'])); mT.append(q['F'] + o); mR.append(q['treg'])
        mgrp.append(np.full(len(q['F']), k2))
        m_groups.append((q['region'], k2, t0, len(q['F'])))
        o += len(q['V'])
        t0 += len(q['F'])
    mV, mN, mT, mR, mgrp = map(np.concatenate, (mV, mN, mT, mR, mgrp))

    with open(os.path.join(OUT, 'body.bin'), 'wb') as f:
        f.write(b'BLB3')
        f.write(struct.pack('<I', 2))
        write_layer(f, sVt, sN, s_groups, s_rego, sFo)
        write_layer(f, mV, mN, m_groups, mR, mT)

    ra = region_anchors(sVt, sFo, sN, s_rego)
    for e, q in zip(entries, mparts):
        e['anchor'], e['normal'] = rnd(tf(q['anchor'])), rnd(q['normal'])
    meta = {
        'format': 'BLB3',
        'source': SOURCE,
        'license': LICENSE,
        'attribution': ATTRIBUTION,
        'height': round(float(sVt[:, 1].max() - sVt[:, 1].min()), 4),
        'bounds': {'min': rnd(sVt.min(0)), 'max': rnd(sVt.max(0))},
        'counts': {'skinTriangles': int(len(sFo)), 'muscleTriangles': int(sum(len(q['F']) for q in mparts)),
                   'underlayerTriangles': int(len(uF)), 'muscles': len(entries)},
        'regions': [{'id': r, 'anchor': rnd(a), 'normal': rnd(n), 'radius': round(rad, 3)} for r, (a, n, rad) in zip(REGION_IDS, ra)],
        'muscles': entries,
    }
    with open(os.path.join(OUT, 'body3d.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    for fn in ('body.bin', 'body3d.json'):
        print(f'  {fn}: {os.path.getsize(os.path.join(OUT, fn)) / 1e6:.2f} MB')
    print(f"  skin {len(sFo)} tris, muscles {meta['counts']['muscleTriangles']} tris in {len(entries)} named parts, "
          f"underlayer {len(uF)} tris")
    np.savez(os.path.join(CACHE, 'last_build.npz'), mV=mV, mN=mN, mT=mT, mgrp=mgrp, sV=sVt, sF=sFo, sreg=s_rego)
    json.dump(entries, open(os.path.join(CACHE, 'last_entries.json'), 'w'))
    print('previews')
    render_previews((sVt, sFo, s_rego), (mV, mN, mT, mgrp), entries)


if __name__ == '__main__':
    main()
