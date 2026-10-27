extends RefCounted

# A barrel part declares three words, and the shot reads what they add up to. docs/30's "The
# barrel governs, 2026-10-27": every number a barrel contributes to a weapon is the product of its
# length, its quality and its material, so no barrel carries a hand-picked multiplier of its own.
#
# A word the tables do not know is refused, not read as `full`. The same rule WEAR_EVENTS keeps for
# wear words: a typo must not be indistinguishable from a plain barrel. `error_of` names the
# failure, `resolve` marks the spec with it, and SimAttachments.blocked_reason refuses the weapon.
#
# Conversion barrels (a caliber change) also keep a `ranged` table and a literal `wearRate`. Those
# are the caliber's share, not the barrel's words: a sleeve for the small round changes the round
# as well as the bore. `resolve` multiplies them in, so the total is still words times share.

const KEYS: Array[String] = ["length", "quality", "material"]

# Each row is a multiplier over the ranged fields it names. "full" is the identity: the length every
# plain barrel was built with, so a barrel with no length word of its own reads as `full`'s numbers.
const LENGTH: Dictionary = {
	"stub": {"muzzle": 0.6, "rangeMetres": 0.6, "noise": 1.3, "handling": 1.35, "cone": 1.2},
	"short": {"muzzle": 0.8, "rangeMetres": 0.72, "noise": 1.22, "handling": 1.25, "cone": 1.1},
	"carbine": {"muzzle": 0.9, "rangeMetres": 0.85, "noise": 1.08, "handling": 1.1},
	"full": {},
	"long": {"rangeMetres": 1.3, "noise": 1.12, "cone": 0.9},
}

# How true the bore is: accuracy, and what a true bore carries and keeps. "service" is the identity.
const QUALITY: Dictionary = {
	"rough": {"cone": 1.2},
	"service": {},
	"match": {"cone": 0.82, "damage": 1.06, "rangeMetres": 1.18, "handling": 0.85},
}

# What the metal does to the wear a shot puts on the part. Multiplies the part's `wearRate`.
const MATERIAL_WEAR: Dictionary = {
	"mild": 1.4,
	"steel": 1.0,
	"chromed": 0.7,
}

# Past this fraction of its reach a slow round starts to lose its damage (docs/30's first cut).
# Below it nothing is lost, and a round at full muzzle speed never loses anything at all.
const FALLOFF_START: float = 0.6


## Why this barrel declaration is not one the bench knows, or "" when every word is known. The
## reason is an id, not a sentence: the screen words it, the sim only names it.
static func error_of(barrel: Variant) -> String:
	if not barrel is Dictionary:
		return "not-a-barrel"
	var b: Dictionary = barrel as Dictionary
	for key in b.keys():
		if not KEYS.has(String(key)):
			return "unknown-key:%s" % String(key)
	for key in KEYS:
		if not b.has(key):
			return "missing:%s" % key
	if not LENGTH.has(String(b["length"])):
		return "length:%s" % String(b["length"])
	if not QUALITY.has(String(b["quality"])):
		return "quality:%s" % String(b["quality"])
	if not MATERIAL_WEAR.has(String(b["material"])):
		return "material:%s" % String(b["material"])
	return ""


## The part's effective spec: its declared numbers times what its words add up to. A spec with no
## barrel is returned as it stands. A barrel with a bad word comes back carrying `barrelError` and
## no derived numbers, so nothing about it is read as a plain barrel. Never writes into `spec`: it is
## content, and content is shared by every part of that kind.
static func resolve(spec: Dictionary) -> Dictionary:
	if not spec.has("barrel"):
		return spec
	var out: Dictionary = spec.duplicate(true)
	var err: String = error_of(spec["barrel"])
	if err != "":
		out["barrelError"] = err
		return out
	var words: Dictionary = spec["barrel"] as Dictionary
	var ranged: Dictionary = {}
	var share: Variant = spec.get("ranged")
	if share is Dictionary:
		ranged = (share as Dictionary).duplicate(true)
	for table in [LENGTH[String(words["length"])], QUALITY[String(words["quality"])]]:
		for field in (table as Dictionary).keys():
			ranged[field] = float(ranged.get(field, 1.0)) * float((table as Dictionary)[field])
	out["ranged"] = ranged
	out["wearRate"] = float(spec.get("wearRate", 1.0)) * float(MATERIAL_WEAR[String(words["material"])])
	return out


## How much of its damage a round still has at `fraction` of its reach, given the muzzle speed the
## barrel leaves it with. 1.0 for every round at full speed, at any range: a plain barrel is
## byte-identical to before this existed. At full reach a slow round keeps exactly `muzzle`.
static func falloff(muzzle: float, fraction: float) -> float:
	if muzzle >= 1.0 or fraction <= FALLOFF_START:
		return 1.0
	var along: float = clampf((fraction - FALLOFF_START) / (1.0 - FALLOFF_START), 0.0, 1.0)
	return 1.0 - (1.0 - muzzle) * along
