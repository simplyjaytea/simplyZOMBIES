import json
from pathlib import Path


ATLAS_SIZE = 1024
DENSITY = 128
PAD = 4

FROZEN = {
    "cap_soft": (0, 0, 128, 128),
    "pack": (128, 0, 256, 128),
    "carrier": (384, 0, 256, 128),
    "helmet_hard": (640, 0, 128, 128),
    "coat_padded": (768, 0, 256, 128),
    "drape_over": (0, 128, 256, 128),
    "jacket_smooth": (256, 128, 256, 128),
    "apron": (512, 128, 128, 128),
    "coverall": (640, 128, 128, 128),
    "hazmat": (768, 128, 256, 128),
    "hat_other": (0, 256, 128, 128),
    "mask": (128, 256, 128, 128),
    "respirator": (256, 256, 128, 128),
    "eyes": (384, 256, 128, 128),
    "scarf": (512, 256, 128, 128),
    "belt": (640, 256, 128, 128),
    "boots": (768, 256, 256, 128),
    "inner_paint": (0, 384, 128, 128),
    "legs_paint": (128, 384, 128, 128),
    "face_paint": (256, 384, 128, 128),
    "feet_paint": (384, 384, 128, 128),
    "glove_paint": (512, 384, 128, 128),
    "wet_cloth": (640, 384, 128, 128),
    "raider_paint": (768, 384, 128, 128),
    "zombie_paint": (896, 384, 128, 128),
}

RAMPS = {
    "cap_soft": ["#343b35", "#40483f", "#4c5448", "#586050", "#646b58"],
    "pack": ["#39382f", "#46443a", "#535044", "#605c4c", "#6d6855"],
    "carrier": ["#30352f", "#3d443a", "#4a5144", "#575e4d", "#646b55"],
    "helmet_hard": ["#4a4d48", "#585b54", "#666960", "#74776b", "#828577"],
    "coat_padded": ["#303831", "#3c453a", "#485243", "#545f4c", "#606c55"],
}

FAMILIES = {
    "pack": {"glb": "pack.glb", "tris": 0, "variants": {"default": "pack"}},
    "carrier": {"glb": "carrier.glb", "tris": 0, "variants": {"flat": "carrier_flat", "loaded": "carrier_loaded", "rig": "carrier_rig"}},
    "helmet_hard": {"glb": "helmet_hard.glb", "tris": 0, "variants": {"default": "helmet_hard"}},
    "cap_soft": {"glb": "cap_soft.glb", "tris": 0, "variants": {"cap": "cap_soft_cap", "knit": "cap_soft_knit"}},
    "coat_padded": {"glb": "coat_padded.glb", "tris": 0, "variants": {"default": "coat_padded", "hood": "coat_padded_hood"}},
}

FAMILY_CAPS = {"pack": 700, "carrier": 900, "helmet_hard": 400, "cap_soft": 400, "coat_padded": 2200}
TORSO_LAYERS = {
    "inner": {"item.wrap.cloth", "item.thermals.top", "item.shirt.linen"},
    "mid": {"item.jacket.leather", "item.apron.welding", "item.coat.winter", "item.coat.parka", "item.coverall.paper", "item.suit.hazmat", "item.named.butchers_apron"},
    "over": {"item.blanket.wool", "item.poncho.rain", "item.raincoat.hooded", "item.poncho.tarp"},
}
PACKS = {"item.pack.hiking", "item.pack.school", "item.pack.frame"}
CARRIERS = {"item.vest.scrap", "item.vest.riot", "item.vest.carrier"}
HARD_HELMETS = {"item.helmet.bike", "item.helmet.hardhat"}
GLOVES = {"item.gloves.work": "work", "item.gloves.leather": "leather", "item.gloves.mesh": "mesh", "item.gloves.wool": "wool", "item.gloves.chemical": "chemical"}


def worn_items(repo):
    items = {}
    for path in sorted((repo / "godot/content/items").glob("*.json")):
        data = json.loads(path.read_text())
        entries = data.get("items", data) if isinstance(data, dict) else data
        if isinstance(entries, dict):
            entries = list(entries.values())
        for item in entries:
            if isinstance(item, dict) and item.get("equipSlot") not in (None, "primary", "secondary"):
                items[item["id"]] = item
    return items


def torso_layer(item_id):
    return next(layer for layer, ids in TORSO_LAYERS.items() if item_id in ids)


def picture(item):
    item_id = item["id"]
    slot = item["equipSlot"]
    if item_id in PACKS:
        return {"slot": slot, "family": "pack", "variant": "default", "read": "10m", "parts": [], "drawnBeyond": [{"part": "torso", "reason": "a pack on the back; it protects nothing"}]}
    if item_id in CARRIERS:
        return {"slot": slot, "family": "carrier", "variant": "flat", "loadedWhen": "plate", "read": "10m", "parts": ["arm_left", "arm_right", "torso"], "drawnBeyond": []}
    if item_id == "item.rig.chest":
        return {"slot": slot, "family": "carrier", "variant": "rig", "read": "10m", "parts": [], "drawnBeyond": [{"part": "torso", "reason": "a load-bearing rig over the chest; it protects nothing"}]}
    if item_id in HARD_HELMETS:
        return {"slot": slot, "family": "helmet_hard", "variant": "default", "hair": "tucked", "read": "10m", "parts": ["head"], "drawnBeyond": []}
    if item_id in ("item.cap.canvas", "item.hat.wool"):
        return {"slot": slot, "family": "cap_soft", "variant": "cap" if item_id == "item.cap.canvas" else "knit", "hair": "tucked", "read": "10m", "parts": ["head"], "drawnBeyond": []}
    if item_id in ("item.coat.winter", "item.coat.parka"):
        parka = item_id == "item.coat.parka"
        parts = ["arm_left", "arm_right", "torso"] + (["head"] if parka else [])
        entry = {"slot": slot, "layer": "mid", "family": "coat_padded", "variant": "hood" if parka else "default", "sleeve": "padded", "read": "10m", "parts": sorted(parts), "drawnBeyond": []}
        if parka:
            entry["hair"] = "hidden"
        return entry
    if item_id in GLOVES:
        return {"slot": slot, "hand": GLOVES[item_id], "body": "none", "bodyReason": "first cut, arms only", "parts": ["hand_left", "hand_right"], "read": "2m"}
    return None


def manifest(repo, plant=None):
    items = {}
    for item_id, item in worn_items(repo).items():
        entry = picture(item)
        if entry is None:
            entry = {"slot": item["equipSlot"], "none": "first cut"}
        if item["equipSlot"] == "torso":
            entry["layer"] = torso_layer(item_id)
        items[item_id] = entry
    if plant == "missing-entry":
        items.pop("item.pack.school")
    return {
        "version": 1,
        "atlas": "clothing_atlas.png",
        "material": "ClothingAtlas",
        "survivorRig": "survivor.glb",
        "dressedCap": 14500,
        "hair": {"default": "hair", "tucked": "hair_tucked"},
        "families": FAMILIES,
        "sleeves": {"knit": "arms_sleeve", "padded": "arms_sleeve_padded"},
        "handPages": {"bare": "arms_atlas.png", "work": "arms_hands_work.png", "leather": "arms_hands_leather.png", "mesh": "arms_hands_mesh.png", "wool": "arms_hands_wool.png", "chemical": "arms_hands_chemical.png"},
        "handExtras": {"chemical": "arms_cuff_chemical"},
        "items": items,
    }


def write_manifest(path, manifest):
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
