#!/usr/bin/env python3
"""matte.py [<id> ...]  — high-quality matte: source/<image> -> cutout/<id>.png (RGBA)

Runs the same BiRefNet 1024² ONNX model that QtMeshEditor's "best" matting tier uses
(~/Library/Application Support/QtMeshEditor/QtMeshEditor/ai_models/rembg/birefnet.onnx) with the same
preprocessing (ImageNet normalisation, NCHW), min-max normalised saliency, bilinear upsample to full
resolution, threshold 0.5 with a +-0.15 feather band, uniform-background rescue (non-white pixels that are not
connected to the border background but that the net missed are kept; enclosed white holes stay clear), then crop to the subject and
re-pad so it fills 85% of a square — exactly what QtMeshEditor hands TRELLIS.2.
"""
import json, os, sys
import numpy as np
from PIL import Image
import onnxruntime as ort

ROOT = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.expanduser("~/Library/Application Support/QtMeshEditor/QtMeshEditor/ai_models/rembg/birefnet.onnx")
M = json.load(open(f"{ROOT}/source/manifest.json"))["generated"]
NET, THRESH, FEATHER, RATIO, BG_WHITE = 1024, 0.5, 2, 0.85, 235

def flood_background(a):
    white = (a >= BG_WHITE).all(axis=2)
    reach = np.zeros_like(white)
    reach[0, :] = white[0, :]; reach[-1, :] = white[-1, :]; reach[:, 0] = white[:, 0]; reach[:, -1] = white[:, -1]
    while True:
        g = reach.copy()
        g[1:, :] |= reach[:-1, :]; g[:-1, :] |= reach[1:, :]; g[:, 1:] |= reach[:, :-1]; g[:, :-1] |= reach[:, 1:]
        g &= white
        if (g == reach).all():
            return reach
        reach = g

def main(ids):
    so = ort.SessionOptions()
    sess = ort.InferenceSession(MODEL, so, providers=["CPUExecutionProvider"])
    in_name, out_name = sess.get_inputs()[0].name, sess.get_outputs()[0].name
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32); std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    os.makedirs(f"{ROOT}/cutout", exist_ok=True)
    for aid in ids:
        img = Image.open(f"{ROOT}/source/{M[aid]['image']}").convert("RGB")
        W, H = img.size
        small = np.asarray(img.resize((NET, NET), Image.LANCZOS), dtype=np.float32) / 255.0
        x = ((small - mean) / std).transpose(2, 0, 1)[None].astype(np.float32)
        out = sess.run([out_name], {in_name: x})[0].reshape(NET, NET)
        lo, hi = float(out.min()), float(out.max())
        sal = (out - lo) / ((hi - lo) if hi - lo > 1e-6 else 1.0)
        full = np.asarray(Image.fromarray((sal * 65535).astype(np.uint16)).resize((W, H), Image.BILINEAR), dtype=np.float32) / 65535.0
        band = 0.075 * FEATHER
        alpha = np.clip((full - (THRESH - band)) / (2 * band), 0.0, 1.0)
        rgb = np.asarray(img)
        bg = flood_background(rgb)
        # rescue: parts the net missed that are neither border-connected background nor background-coloured
        # (enclosed white holes, e.g. between chair legs, stay transparent)
        white = (rgb >= BG_WHITE).all(axis=2)
        rescued = (~bg) & (~white) & (alpha < 0.5)
        alpha[rescued] = 1.0
        alpha[bg & (alpha < 0.5)] = 0.0  # border-connected white is background for sure
        fg = alpha > 0.5
        ys, xs = np.where(fg)
        if len(xs) < W * H / 200:
            print(f"{aid}: segmentation kept too little, keeping flood matte only"); alpha = (~bg).astype(np.float32); ys, xs = np.where(alpha > 0.5)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        fgW, fgH = x1 - x0 + 1, y1 - y0 + 1
        square = max(fgW, fgH); outSz = max(8, int(square / RATIO))
        offX, offY = (outSz - fgW) // 2, (outSz - fgH) // 2
        canvas = np.zeros((outSz, outSz, 4), dtype=np.uint8)
        crop_rgb = rgb[y0:y1 + 1, x0:x1 + 1]; crop_a = (alpha[y0:y1 + 1, x0:x1 + 1] * 255 + 0.5).astype(np.uint8)
        canvas[offY:offY + fgH, offX:offX + fgW, :3] = crop_rgb
        canvas[offY:offY + fgH, offX:offX + fgW, 3] = crop_a
        Image.fromarray(canvas, "RGBA").save(f"{ROOT}/cutout/{aid}.png")
        soft = int(((alpha > 0.02) & (alpha < 0.98)).sum())
        print(f"{aid}: {W}x{H} -> {outSz}x{outSz} fg={fg.mean()*100:.1f}% rescued={int(rescued.sum())} softEdgePx={soft}")

if __name__ == "__main__":
    main(sys.argv[1:] or list(M))
