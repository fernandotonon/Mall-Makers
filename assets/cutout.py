#!/usr/bin/env python3
"""cutout.py [<id> ...]  — source/<image> (white studio background) -> cutout/<id>.png (RGBA).
The background is flood-filled from the image border (tolerance on near-white) and turned
transparent, so white highlights *inside* the object survive (a plain threshold matte would
punch holes that TRELLIS turns into geometry). A pre-matted PNG keeps its alpha in trellis-cli."""
import json, os, sys
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.abspath(__file__))
M = json.load(open(f"{ROOT}/source/manifest.json"))["generated"]
ids = sys.argv[1:] or list(M)
THRESH = 235  # every channel >= THRESH counts as background
for aid in ids:
    src = f"{ROOT}/source/{M[aid]['image']}"
    im = Image.open(src).convert("RGB")
    a = np.asarray(im)
    white = (a >= THRESH).all(axis=2)
    h, w = white.shape
    reach = np.zeros_like(white)
    reach[0, :] = white[0, :]; reach[-1, :] = white[-1, :]; reach[:, 0] = white[:, 0]; reach[:, -1] = white[:, -1]
    # iterative 4-neighbour flood fill (numpy, no scipy)
    while True:
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]; grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]; grown[:, :-1] |= reach[:, 1:]
        grown &= white
        if (grown == reach).all():
            break
        reach = grown
    alpha = np.where(reach, 0, 255).astype(np.uint8)
    # soften the matte edge by one pixel so the silhouette is not aliased
    edge = reach.copy()
    edge[1:, :] |= reach[:-1, :]; edge[:-1, :] |= reach[1:, :]; edge[:, 1:] |= reach[:, :-1]; edge[:, :-1] |= reach[:, 1:]
    alpha[edge & ~reach] = 128
    out = np.dstack([a, alpha])
    os.makedirs(f"{ROOT}/cutout", exist_ok=True)
    Image.fromarray(out, "RGBA").save(f"{ROOT}/cutout/{aid}.png")
    print(f"{aid}: {w}x{h} bg={reach.mean()*100:.1f}%")
