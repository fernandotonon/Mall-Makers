#!/usr/bin/env python3
"""Creates Shoprise's game passes, developer product and badges on Roblox through Open Cloud and
writes their ids into src/ReplicatedStorage/Config/Shop.luau and Achievements.luau.

  python3 tools/creator_hub_setup.py            # dry run: shows what would be created
  python3 tools/creator_hub_setup.py --apply    # creates what is missing

API key: ~/.roblox/shoprise_api_key (never commit it). Scopes needed for universe 10768853423:
game-pass:read/write, developer-product:read/write, legacy-universe.badge:manage-and-spend-robux.
Idempotent: items that already exist (same name) are reused. Badges are only created while the
universe still has free badges today (expectedCost=0), so the script never spends Robux; run it
again on another day to create the remaining badges.
"""
import io, json, os, re, sys, urllib.request, uuid
from PIL import Image, ImageDraw, ImageFont

UNIVERSE = 10768853423
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOP = f"{ROOT}/src/ReplicatedStorage/Config/Shop.luau"
ACH = f"{ROOT}/src/ReplicatedStorage/Config/Achievements.luau"
APPLY = "--apply" in sys.argv
KEY_PATH = os.path.expanduser("~/.roblox/shoprise_api_key")

def key():
    k = open(KEY_PATH).read().strip()
    assert k, "empty API key file"
    return k

def request(method, url, fields=None, files=None, auth=True):
    headers = {}
    data = None
    if auth:
        headers["x-api-key"] = key()
    if fields is not None or files:
        boundary = uuid.uuid4().hex
        buf = io.BytesIO()
        for k, v in (fields or {}).items():
            buf.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
        for k, (fname, blob) in (files or {}).items():
            buf.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{fname}\"\r\nContent-Type: image/png\r\n\r\n".encode())
            buf.write(blob + b"\r\n")
        buf.write(f"--{boundary}--\r\n".encode())
        data = buf.getvalue()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {url} -> HTTP {e.code}: {e.read().decode()[:400]}")

EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"
TEXT_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

def icon(emoji, bg, label=None):
    img = Image.new("RGBA", (512, 512), bg)
    d = ImageDraw.Draw(img)
    light = tuple(min(255, int(c + (255 - c) * 0.35)) for c in bg)
    d.ellipse((40, 40, 472, 472), fill=light)
    try:
        ef = ImageFont.truetype(EMOJI_FONT, 160)
        em = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        ImageDraw.Draw(em).text((20, 10), emoji, font=ef, embedded_color=True)
        em = em.resize((300, 300), Image.LANCZOS)
        img.alpha_composite(em, (106, 70 if label else 106))
    except Exception:
        pass
    if label:
        tf = ImageFont.truetype(TEXT_FONT, 54)
        w = d.textlength(label, font=tf)
        d.text(((512 - w) / 2, 390), label, font=tf, fill="white")
    out = io.BytesIO()
    img.convert("RGB").save(out, "PNG")
    return out.getvalue()

def parse_shop():
    s = open(SHOP).read()
    items = []
    for kind in ("GamePasses", "Products"):
        block = re.search(kind + r"\s*=\s*\{(.*?)\n\t\},", s, re.S).group(1)
        for m in re.finditer(r"(\w+) = \{ Id = (\d+), Price = (\d+), Name = \"([^\"]+)\", Icon = \"([^\"]+)\".*?Desc = \"([^\"]+)\"", block):
            items.append(dict(kind=kind, key=m[1], id=int(m[2]), price=int(m[3]), name=m[4], icon=m[5], desc=m[6]))
    return items

def set_id(path, pattern_key, new_id, is_achievement=False):
    s = open(path).read()
    if is_achievement:
        s2 = re.sub(r'(\{ Id = "%s",.*?BadgeId = )\d+' % re.escape(pattern_key), lambda m: m[1] + str(new_id), s, count=1)
    else:
        s2 = re.sub(r'(\b%s = \{ Id = )\d+' % re.escape(pattern_key), lambda m: m[1] + str(new_id), s, count=1)
    assert s2 != s or str(new_id) in s, f"could not write id for {pattern_key}"
    open(path, "w").write(s2)

BG = {"VIP": (150, 110, 20), "StylePack": (120, 70, 170), "MallRush": (30, 140, 140)}

def shop():
    items = parse_shop()
    existing_passes = existing_products = {}
    if APPLY or os.path.exists(KEY_PATH):
        existing_passes = {p["name"]: p["gamePassId"] for p in request("GET", f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE}/game-passes/creator?pageSize=50").get("gamePasses", [])}
        existing_products = {p["name"]: p["productId"] for p in request("GET", f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE}/developer-products/creator?pageSize=50").get("developerProducts", [])}
    for it in items:
        have = (existing_passes if it["kind"] == "GamePasses" else existing_products).get(it["name"])
        if it["id"] and it["id"] == have:
            print(f"  ok      {it['name']} ({it['id']})")
            continue
        if have:
            print(f"  reuse   {it['name']} -> {have}")
            new_id = have
        elif not APPLY:
            print(f"  create  {it['kind'][:-1]} {it['name']} for R$ {it['price']}")
            continue
        else:
            fields = {"name": it["name"], "description": it["desc"], "isForSale": "true", "price": str(it["price"]), "isRegionalPricingEnabled": "false"}
            png = icon(it["icon"], BG.get(it["key"], (40, 90, 140)))
            if it["kind"] == "GamePasses":
                r = request("POST", f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE}/game-passes", fields, {"imageFile": ("icon.png", png)})
                new_id = r["gamePassId"]
            else:
                r = request("POST", f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE}/developer-products", fields, {"imageFile": ("icon.png", png)})
                new_id = r["productId"]
            print(f"  created {it['name']} -> {new_id}")
        set_id(SHOP, it["key"], new_id)

def badges():
    s = open(ACH).read()
    achs = [dict(id=m[1], name=m[2], icon=m[3], desc=m[4], badge=int(m[5])) for m in re.finditer(r'\{ Id = "(\w+)", Name = "([^"]+)", Icon = "([^"]+)", Desc = "([^"]+)".*?BadgeId = (\d+) \}', s)]
    existing = {}
    cursor = ""
    while True:
        r = request("GET", f"https://badges.roblox.com/v1/universes/{UNIVERSE}/badges?limit=100" + (f"&cursor={cursor}" if cursor else ""), auth=False)
        existing.update({b["name"]: b["id"] for b in r.get("data", [])})
        cursor = r.get("nextPageCursor")
        if not cursor:
            break
    quota = int(request("GET", f"https://badges.roblox.com/v1/universes/{UNIVERSE}/free-badges-quota", auth=False))
    print(f"  free badges left today: {quota}")
    for a in achs:
        have = existing.get(a["name"])
        if a["badge"] and a["badge"] == have:
            print(f"  ok      badge {a['name']} ({have})")
            continue
        if have:
            print(f"  reuse   badge {a['name']} -> {have}")
            set_id(ACH, a["id"], have, True)
            continue
        if quota <= 0:
            print(f"  later   badge {a['name']} (no free badges left today)")
            continue
        if not APPLY:
            print(f"  create  badge {a['name']}")
            quota -= 1
            continue
        r = request("POST", f"https://apis.roblox.com/legacy-badges/v1/universes/{UNIVERSE}/badges",
                    {"name": a["name"], "description": a["desc"], "paymentSourceType": "1", "expectedCost": "0", "isActive": "true"},
                    {"files": ("badge.png", icon(a["icon"], (30, 120, 120)))})
        quota -= 1
        print(f"  created badge {a['name']} -> {r['id']}")
        set_id(ACH, a["id"], r["id"], True)

if __name__ == "__main__":
    if not os.path.exists(KEY_PATH):
        raise SystemExit(f"missing API key file {KEY_PATH}")
    print("Game passes and products:")
    shop()
    print("Badges:")
    badges()
    if not APPLY:
        print("\n(dry run; pass --apply to create)")
